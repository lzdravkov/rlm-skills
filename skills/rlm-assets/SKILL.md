---
name: rlm-assets
description: Manage Salesforce Revenue Cloud asset lifecycle including asset creation from orders, amendment, renewal, cancellation, transfer, rollback, delta pricing, proration, AssetStatePeriod tracking, and AssetRelationship. Use when working with Asset records, initiating lifecycle actions, querying asset state history, or handling partial cancellations and co-term amendments. Do NOT use for billing schedules (use rlm-billing) or product configuration (use rlm-product-configurator). Triggers on: "asset", "amendment", "renewal", "cancellation", "transfer", "rollback", "AssetStatePeriod", "AssetAction", "AssetRelationship", "co-term", "delta pricing", "proration", "lifecycle", "RenewalStatus", "LifecycleEndDate", "subscription lifecycle".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Asset Lifecycle

## Object Model

```
Order (Activated)
  └── OrderItem
        └── Asset                        (created by Create/Update Asset From Order Action)
              ├── AssetStatePeriod[]     (tracks state changes over subscription lifetime)
              ├── AssetAction[]          (records each lifecycle action taken)
              └── AssetRelationship[]    (links assets: parent/child, replacement, etc.)

Asset ──→ QuoteAction (Amendment | Renewal | Cancellation | Transfer)
            └── Quote (new lifecycle quote)
                  └── QuoteLineItem (modified subscription terms)
```

---

## Instructions

### Step 1: Understand asset creation

Assets are created automatically when an order is activated, via the **Create or Update Asset From Order** platform action. Key fields set at creation:

| Field | Value at Creation |
|---|---|
| `Status` | `Purchased` |
| `LifecycleStartDate` | Order start date |
| `LifecycleEndDate` | Calculated from term (null for Evergreen) |
| `Quantity` | From OrderItem |
| `Product2Id` | From OrderItem |
| `AccountId` | From Order |
| `RenewalStatus` | `Draft` (updated to `Eligible` as term approaches end) |

The `CreateAssetOrderEvent` platform event fires when asset creation completes.

### Step 2: Query asset state

```apex
// Get all active assets for an account
List<Asset> assets = [
    SELECT Id, Name, Status, Product2.Name,
           Quantity, LifecycleStartDate, LifecycleEndDate,
           RenewalStatus, AccountId
    FROM Asset
    WHERE AccountId = :accountId
      AND Status = 'Purchased'
    ORDER BY LifecycleEndDate ASC NULLS LAST
];

// Assets expiring in the next 90 days (renewal candidates)
List<Asset> expiring = [
    SELECT Id, Name, LifecycleEndDate, RenewalStatus
    FROM Asset
    WHERE AccountId = :accountId
      AND Status = 'Purchased'
      AND LifecycleEndDate <= NEXT_N_DAYS:90
    ORDER BY LifecycleEndDate ASC
];
```

### Step 3: AssetStatePeriod — tracking state over time

`AssetStatePeriod` records the quantity and status of an asset across its full lifecycle, including changes from amendments. Query it for historical billing and audit:

```apex
List<AssetStatePeriod> history = [
    SELECT Id, AssetId, StartDate, EndDate,
           Quantity, MrrAmount, Status,
           ChangeType   // Created | Amended | Renewed | Cancelled
    FROM AssetStatePeriod
    WHERE AssetId = :assetId
    ORDER BY StartDate ASC
];
```

**Key rule**: When an amendment changes quantity or price, the old `AssetStatePeriod` is closed (`EndDate` set) and a new one is created from the amendment effective date. This is the authoritative record for proration calculations.

### Step 4: Amendment flow

Amendment modifies an existing subscription — quantity change, product swap, attribute reconfiguration, or price adjustment.

```
Initiate Amendment Action (assetId, effectiveDate)
  → creates amendmentQuoteId
  → opens Quote with existing line items pre-populated
  → modify: quantity, attributes (via PST), or price
  → approve (if required) → convert to order → activate
  → Asset updated; new AssetStatePeriod created from effectiveDate
```

**Delta pricing**: Only items that changed are repriced. Unchanged items carry forward their existing price. Enable via `RevenueManagementSettings.enableDeltaPricing = true`.

**Effective date rules**:
- `effectiveDate` < `Asset.LifecycleStartDate` → rejected
- `effectiveDate` > `Asset.LifecycleEndDate` → rejected
- `effectiveDate` = today → immediate effect (proration from today)

```apex
// Initiate amendment via Apex (or use Initiate Amendment Action in Flow)
// Business API:
// POST /commerce/assets/{assetId}/amendment
// Body: { "effectiveDate": "2026-07-01" }
// Response: { "quoteId": "0Q0..." }
```

### Step 5: Renewal flow

Renewal extends the subscription term past the current `LifecycleEndDate`.

1. Use **Get Renewable Assets Summary Action** to check which assets are eligible
2. Initiate renewal for each eligible asset
3. Review/approve the renewal quote
4. Convert to order → `Asset.LifecycleEndDate` updated, new `AssetStatePeriod` created

```apex
// Check eligibility first
List<Asset> eligible = [
    SELECT Id, Name, LifecycleEndDate, RenewalStatus
    FROM Asset
    WHERE AccountId = :accountId
      AND RenewalStatus = 'Eligible'
];

// Initiate renewal via Business API:
// POST /commerce/assets/{assetId}/renewal
// Body: { "renewalTerm": 12, "renewalTermUnit": "Months", "startDate": "2027-01-01" }
// Response: { "quoteId": "0Q0..." }
```

**`RenewalStatus` values**:

| Value | Meaning |
|---|---|
| `Draft` | Not yet eligible |
| `Eligible` | Within renewal window |
| `InProgress` | Renewal quote exists |
| `Renewed` | Renewal order activated |
| `Expired` | Term ended without renewal |

### Step 6: Cancellation flow

Full or partial cancellation. Partial cancellation reduces quantity on the asset rather than ending it.

```
Initiate Cancellation Action (assetId, cancellationDate)
  → creates cancellationQuoteId
  → approve → convert to order → activate
  → Full: Asset.Status = 'Cancelled', LifecycleEndDate = cancellationDate
  → Partial: Asset.Quantity reduced, new AssetStatePeriod created
```

**Proration on cancellation**: The billing skill calculates the credit due for the unused portion of the current term using `AssetStatePeriod.StartDate` + `cancellationDate`.

### Step 7: Co-term amendment (aligning end dates)

When a customer has multiple assets with different end dates, co-terming aligns them to a single date. This is an amendment where `effectiveDate` and the new `LifecycleEndDate` are explicitly set to match an existing asset.

```apex
// POST /commerce/assets/{assetId}/amendment
// Body: { "effectiveDate": "2026-07-01", "endDate": "2027-06-30" }
// This aligns the amended asset's term to an existing contract end date.
```

Co-terming generates a proration credit for the shortened or extended period, reflected in the amendment quote price.

### Step 8: Transfer

Transfers asset ownership to a different account. The asset moves; billing follows.

```
Initiate Transfer Action (assetId, targetAccountId)
  → creates transferQuoteId
  → approve → activates transfer
  → Asset.AccountId updated to targetAccountId
  → New BillingArrangement created for target account
```

### Step 9: Rollback

Reverts the most recent lifecycle action. Use only when a lifecycle order was processed in error.

```
Initiate Rollback on Last Action (assetId)
  → creates rollbackQuoteId
  → approve → asset reverts to pre-action state
```

**Constraints**:
- Cannot rollback if the asset has been billed for the new term
- Cannot rollback a rollback (only one level of undo)
- Cannot rollback a transfer if the target account has already processed activity on the asset

### Step 10: AssetRelationship

Links related assets — common for bundle parents/children, replacement assets, or upsell relationships.

```apex
AssetRelationship ar = new AssetRelationship();
ar.AssetId = parentAsset.Id;
ar.RelatedAssetId = childAsset.Id;
ar.RelationshipType = 'Component';   // Component | Replacement | Reference
insert ar;
```

---

## Deployment

No catalog objects are deployed for asset management — `Asset` and related objects are standard Salesforce objects. Deploy the following Apex/metadata if using invocable actions:

```
1. Apex classes: any custom asset lifecycle handlers
2. Flows: any flows subscribing to CreateAssetOrderEvent
3. RevenueManagementSettings: enableDeltaPricing = true (if using delta pricing)
4. RevenueManagementSettings: enableAutoAddDerivedAsset = true (if BOM assets auto-create)
```

---

## Common Issues

### Lifecycle action fails: "No active assets found"
Cause: `Asset.Status != 'Purchased'` or `Asset.LifecycleEndDate` has passed.
Solution: Verify `Status = 'Purchased'` and `LifecycleEndDate > TODAY`. For Evergreen assets, `LifecycleEndDate` is null — check that `Status = 'Purchased'`.

### Amendment effective date rejected
Cause: `effectiveDate` falls outside `LifecycleStartDate` to `LifecycleEndDate` range, or a conflicting amendment is already in progress.
Solution: Check `Asset.LifecycleStartDate` and `LifecycleEndDate`. Query for in-progress `QuoteAction` records: `SELECT Id FROM QuoteAction WHERE AssetId = :assetId AND Status = 'In Progress'`.

### AssetStatePeriod not created after amendment
Cause: `enableDeltaPricing` is false, or the amendment order was not fully activated.
Solution: Verify `Order.Status = 'Activated'`. Enable `RevenueManagementSettings.enableDeltaPricing = true`.

### Delta pricing not applied — full reprice on amendment
Cause: `enableDeltaPricing = false` in `RevenueManagementSettings`.
Solution: Set `enableDeltaPricing = true`. Note: this only reprices changed items; unchanged items carry forward.

### Renewal status stuck on "Draft"
Cause: The asset is outside the renewal eligibility window (typically 90 days before `LifecycleEndDate`), or the renewal window is not configured in Setup.
Solution: Check Setup → Revenue Cloud → Renewal Settings for the eligibility window. Manually query `Asset.RenewalStatus` and `LifecycleEndDate`.

### Rollback fails: "Cannot rollback billed asset"
Cause: An invoice covering the new term period has already been posted.
Solution: Void or credit the invoice first, then retry the rollback. If already paid, issue a credit memo instead of rollback.

---

## See Also

| Skill | Why |
|---|---|
| `rlm-transaction-management` | Quote and order creation for lifecycle actions; PST for attribute changes on amendment quotes |
| `rlm-billing` | `AssetStatePeriod` data drives proration calculations; cancellation generates credit memos |
| `rlm-product-configurator` | Amendment quotes can reconfigure product attributes — same PST pattern applies |
| `rlm-usage-management` | Usage grants are tied to assets; amendment or cancellation affects `UsageEntitlementBucket` lifecycle |
| `rlm-dynamic-revenue-orchestrator` | Re-provisioning may be triggered by amendment orders via `SalesTrxnDecompositionEvent` |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-05-02 | Initial skill — Asset lifecycle, AssetStatePeriod, amendment/renewal/cancellation/transfer/rollback, delta pricing, co-term |

---

## References
- See `references/asset-object-reference.md` for full field-level reference for Asset, AssetStatePeriod, AssetAction, AssetRelationship
- See `rlm-transaction-management/references/asset-lifecycle-patterns.md` for invocable action input/output specs
- RLM Developer Guide v66.0, Chapter 8: Transaction Management — Asset Lifecycle (p. 1300)

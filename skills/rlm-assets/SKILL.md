---
name: rlm-assets
description: Manage Salesforce Revenue Cloud asset lifecycle including asset creation from orders, amendment, renewal, cancellation, transfer, rollback, delta pricing, proration, AssetStatePeriod tracking, and AssetRelationship. Use when working with Asset records, initiating lifecycle actions, querying asset state history, or handling partial cancellations and co-term amendments. Do NOT use for billing schedules (use rlm-billing) or product configuration (use rlm-product-configurator). Triggers on: "asset", "amendment", "renewal", "cancellation", "transfer", "rollback", "AssetStatePeriod", "AssetAction", "AssetRelationship", "co-term", "delta pricing", "proration", "lifecycle", "RenewalStatus", "LifecycleEndDate", "subscription lifecycle".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Asset Lifecycle

## Object Model

```
Order (Activated)
  └── OrderItem
        └── Asset                        (created by Create or Update Asset From Order Action)
              ├── AssetStatePeriod[]     (tracks state changes over subscription lifetime)
              ├── AssetAction[]          (records each lifecycle action taken; CategoryEnum incl. Amendments/Renewals/Cancellations/Swaps/Upgrades/Downgrades/Transfers)
              │     └── AssetActionSource[] (links an AssetAction back to the order/quote line that generated it)
              ├── AssetRelationship[]    (links assets: Crossgrade/Replacement/Upgrade)
              └── AssetContractRelationship[] (links an asset to its governing Contract)

Asset ──→ initiateAmendment | initiateRenewal | initiateCancellation | initiateTransfer | initiateRollBackLastAction
            (Standard Invocable Actions — see Steps 4-9)
            └── Quote or Order (new lifecycle transaction, per each action's *OutputType input)
                  └── QuoteLineItem (modified subscription terms)
```

> **Correction (v68 re-baseline):** the previous diagram routed lifecycle actions through a
> `QuoteAction` object. `QuoteAction` could **not be confirmed** as a real v68 standard object in
> the sections of the Developer Guide reviewed for this re-baseline (Ch.8 Standard Objects, printed
> 1235–1367) — treat it as **unverified**. The confirmed mechanism is that each Standard Invocable
> Action (Initiate Amendment/Renewal/Cancellation/Transfer/Rollback) creates a `Quote` or `Order`
> directly. `AssetActionSource` and `AssetContractRelationship` are newly added here — they are
> real v68 standard objects in the Asset* cluster that had no coverage in the v1.0.0 skill.
> Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard Objects.

---

## Instructions

### Step 1: Understand asset creation

Assets are created automatically when an order is activated, via the **Create or Update Asset From
Order Action** (`createOrUpdateAssetFromOrder`, avail API v60.0+, `POST /services/data/v68.0/
actions/standard/createOrUpdateAssetFromOrder` — requires the **Assetize Order** permission set).
It creates an asset for each order item in the order; modifies existing assets for change-order
requests (renewal, amendment, cancellation). If the order item's custom product name has a value,
the asset name is set to that custom product name. There is a line-item-level sibling action,
**Create or Update Asset From Order Item Action** (`createOrUpdateAssetFromOrderItem`), for
tracking assets as individual order items progress through their lifecycle. Key fields set at
creation:

| Field | Value at Creation |
|---|---|
| `Status` | `Purchased` |
| `Quantity` | From OrderItem |
| `Product2Id` | From OrderItem |
| `AccountId` | From Order |

> **Correction (v68 re-baseline):** `LifecycleStartDate`, `LifecycleEndDate`, and `RenewalStatus`
> could **not be confirmed** as real `Asset` fields in the Standard Objects section reviewed for
> this re-baseline. Treat these three as **unverified** — do not build validation logic on them
> without confirming their exact API names in your org's Asset field metadata first. See
> `references/asset-object-reference.md` for the corrected field list and the confirmed real
> mechanism for tracking renewal eligibility (the **Get Renewable Assets Summary Action**, keyed on
> `orderId`, not a `RenewalStatus` picklist).

The `CreateAssetOrderEvent` platform event fires when asset creation completes — note its real
shape is nested (`AssetDetails` list of `CreateAssetOrderDtlEvent`, each with `AssetId`), not the
flat `AssetId`/`OrderId` shown in earlier versions of this skill. See
`references/asset-object-reference.md`.

### Step 2: Query asset state

```apex
// Get all active assets for an account
// NOTE (v68 re-baseline): LifecycleStartDate/LifecycleEndDate/RenewalStatus are UNVERIFIED fields
// (see Step 1 correction) — this query is annotated, not silently rewritten. If these fields do not
// exist in your org, use standard Asset fields (e.g. PurchaseDate, UsageEndDate) instead.
List<Asset> assets = [
    SELECT Id, Name, Status, Product2.Name,
           Quantity, LifecycleStartDate, LifecycleEndDate,
           RenewalStatus, AccountId
    FROM Asset
    WHERE AccountId = :accountId
      AND Status = 'Purchased'
    ORDER BY LifecycleEndDate ASC NULLS LAST
];
```

For renewal candidates, prefer the confirmed v68 mechanism — the **Get Renewable Assets Summary
Action** — over filtering on the unverified `RenewalStatus` field:

```apex
// Preferred: call getRenewableAssetsSummary with the relevant orderId, then inspect
// renewableAssetsSummary[].endDate / .lastAssetAction (Initial Sale | Upsell | Downsell |
// Renewal | Cancellation) in the response, rather than querying Asset.RenewalStatus directly.
```

### Step 3: AssetStatePeriod — tracking state over time

`AssetStatePeriod` records the quantity and status of an asset across its full lifecycle, including changes from amendments. Query it for historical billing and audit:

```apex
List<AssetStatePeriod> history = [
    SELECT Id, AssetId, StartDate, EndDate,
           Quantity, Mrr
    FROM AssetStatePeriod
    WHERE AssetId = :assetId
    ORDER BY StartDate ASC
];
```

> **Correction (v68 re-baseline):** the field is `Mrr`, not `MrrAmount`. `Status`, `ChangeType`,
> `OrderId`, and `ProratedMrrAmount` (used elsewhere in this skill and in
> `references/asset-object-reference.md`) could **not be confirmed** as real `AssetStatePeriod`
> fields — see the corrected field table in `references/asset-object-reference.md` for the
> confirmed field set and this annotation.

**Key rule**: When an amendment changes quantity or price, the old `AssetStatePeriod` is closed (`EndDate` set) and a new one is created from the amendment effective date. This is the authoritative record for proration calculations.

### Step 4: Amendment flow

Amendment modifies an existing subscription — quantity change, product swap, attribute reconfiguration, or price adjustment.

```
Initiate Amendment Action (initiateAmendment)
  Inputs: amendAssetIds, amendStartDate, amendOutputType (Quote|Order), quantityChange
  → creates amendRecordId (Quote or Order per amendOutputType)
  → if Quote: opens with existing line items pre-populated
  → modify: quantity, attributes (via PST), or price
  → approve (if required) → convert to order → activate
  → Asset updated; new AssetStatePeriod created from effectiveDate
```

**Delta pricing**: Only items that changed are repriced. Unchanged items carry forward their existing price. Enable via `RevenueManagementSettings.enableDeltaPricing = true`.

> **Annotation:** `enableDeltaPricing` was not independently re-verified against Ch.2
> RevenueManagementSettings in this pass (out of scope for the Ch.8-focused read performed for this
> re-baseline); no contradicting evidence was found, so it is kept as-is.

**Effective date rules** (as previously documented — not independently re-verified against Ch.8 this
pass since `Asset.LifecycleStartDate`/`LifecycleEndDate` are themselves unverified per Step 1; treat
these rules as describing intended behavior, confirm the underlying field names in your org):
- `effectiveDate` before the asset's lifecycle start → rejected
- `effectiveDate` after the asset's lifecycle end → rejected
- `effectiveDate` = today → immediate effect (proration from today)

```apex
// Initiate amendment via Apex (or use Initiate Amendment Action in Flow)
// Business API:
// POST /connect/revenue-management/assets/actions/amend
// Or Standard Invocable Action (Actions REST API):
// POST /services/data/v68.0/actions/standard/initiateAmendment
// Body: { "inputs": [ { "amendAssetIds": ["02i..."], "amendStartDate": "2026-07-01T00:00:00.000Z",
//                        "amendOutputType": "Quote", "quantityChange": 0 } ] }
// Response: { "outputValues": { "amendRecordId": "0Q0...", "requestIdentifier": "16P..." } }
```

> **Correction (v68 re-baseline):** the previous `POST /commerce/assets/{assetId}/amendment` path
> and simplified `{ effectiveDate }` body do not reflect the real Business API/Invocable Action
> shape — corrected above. `quantityChange` is required and is an additive delta, not an absolute
> quantity. For usage products, direct-to-Order (`amendOutputType: Order`) is not supported — use
> the 2-step Quote-then-convert flow. Full detail: `rlm-transaction-management/references/
> asset-lifecycle-patterns.md`.

### Step 5: Renewal flow

Renewal extends the subscription term of an eligible asset.

1. Use **Get Renewable Assets Summary Action** (`getRenewableAssetsSummary`, input `orderId`) to
   retrieve renewal opportunities for the assets tied to an order
2. Initiate renewal for each eligible asset via `initiateRenewal`
3. Review/approve the renewal quote (if `renewOutputType = Quote`)
4. Convert to order → asset term extended, new `AssetStatePeriod` created

```apex
// Check eligibility first — via the invocable action, not a RenewalStatus field query
// (see correction below)
Map<String, Object> summaryInputs = new Map<String, Object>{ 'orderId' => orderId };
// invoke getRenewableAssetsSummary; each entry in outputValues.renewableAssetsSummary[] has
// assetId, startDate, endDate, lastAssetAction, renewalPriceDetails[], etc.

// Initiate renewal via Business API:
// POST /connect/revenue-management/assets/actions/renew
// Or Standard Invocable Action:
// POST /services/data/v68.0/actions/standard/initiateRenewal
// Body: { "inputs": [ { "renewAssetIds": ["02i..."], "renewOutputType": "Quote",
//                        "renewStartDate": "2027-01-01T00:00:00.000Z" } ] }
// Response: { "outputValues": { "renewRecordId": "0Q0...", "requestIdentifier": "16P..." } }
```

> **Correction (v68 re-baseline):** the previous "check eligibility first" query
> (`WHERE RenewalStatus = 'Eligible'`) and the `RenewalStatus` value table below could **not be
> confirmed** — no `Asset.RenewalStatus` field, and no `RenewalStatus`/`CurrentTermEndDate` output
> field on Get Renewable Assets Summary, were found in the v68 sections reviewed (Ch.8 Standard
> Objects; Apex Reference `renew_assets_summary.RenewalOpptyDetail`; Standard Invocable Actions).
> The confirmed renewal-history taxonomy instead comes from `RenewalOpptyDetail.lastAssetAction`:
> `Initial Sale` \| `Upsell` \| `Downsell` \| `Renewal` \| `Cancellation`. The previous
> `POST /commerce/assets/{assetId}/renewal` Business API path and `renewalTerm`/`renewalTermUnit`
> body were also fabricated — corrected above. Full detail:
> `rlm-transaction-management/references/asset-lifecycle-patterns.md`.
>
> **`RenewalStatus` values below are UNVERIFIED** — kept for reference only in case your org has a
> genuine custom or managed-package field by this name, but do not assume it is a standard v68
> field:

| Value | Meaning (unverified) |
|---|---|
| `Draft` | Not yet eligible |
| `Eligible` | Within renewal window |
| `InProgress` | Renewal quote exists |
| `Renewed` | Renewal order activated |
| `Expired` | Term ended without renewal |

### Step 6: Cancellation flow

Full or partial cancellation. Partial cancellation reduces quantity on the asset rather than ending it.

```
Initiate Cancellation Action (initiateCancellation)
  Inputs: cancelAssetIds, cancelStartDate, cancelOutputType (Quote|Order)
  → creates cancelRecordId
  → approve → convert to order → activate
  → Partial: Asset.Quantity reduced, new AssetStatePeriod created
```

> **Correction (v68 re-baseline):** the previous `Asset.Status = 'Cancelled'` claim for full
> cancellation is **unverified** — the confirmed `Asset.Status` values are `Purchased` | `Shipped` |
> `Installed` | `Registered` | `Obsolete`; no `Cancelled` value was found in the Standard Objects
> section reviewed. The Business API path is `POST /connect/revenue-management/assets/actions/cancel`
> (previously fabricated as `/commerce/assets/{assetId}/cancellation`); all assets in one
> `cancelAssetIds` request must belong to the same price book.

**Proration on cancellation**: The billing skill calculates the credit due for the unused portion of the current term using `AssetStatePeriod.StartDate` + `cancellationDate`.

### Step 7: Co-term amendment (aligning end dates)

When a customer has multiple assets with different end dates, co-terming aligns them to a single date. This is an amendment where the amendment's effective start date and the asset's resulting end date are aligned to an existing asset's term.

```apex
// POST /connect/revenue-management/assets/actions/amend
// Or: POST /services/data/v68.0/actions/standard/initiateAmendment
// Body: { "inputs": [ { "amendAssetIds": ["02i..."], "amendStartDate": "2026-07-01T00:00:00.000Z",
//                        "amendOutputType": "Quote", "quantityChange": 0 } ] }
// This aligns the amended asset's term to an existing contract end date.
```

> **Annotation:** `initiateAmendment` does not expose a direct `endDate` input (per the confirmed
> Standard Invocable Actions reference) — term alignment for co-terming is achieved by setting the
> resulting amendment quote/order's line item end date in the quote itself, not via an action input.
> This distinction was not explicit in the sections reviewed; flagged rather than asserting a
> specific mechanism.

Co-terming generates a proration credit for the shortened or extended period, reflected in the amendment quote price.

### Step 8: Transfer

Transfers asset ownership to a different account. `initiateTransfer` (avail v65.0+) generates **2**
quotes/orders — a negative-quantity **source** transaction (reduces the existing asset) and a
positive-quantity **target** transaction (creates a new asset on the target account). Transfer is
complete once both are assetized.

```
Initiate Transfer Action (initiateTransfer)
  Inputs: transferRecords ([{assetId, transferQuantity}]), targetAccountId, transferDate, outputRecordType
  → creates assetTransferSourceId, assetTransferTargetId
  → approve both → source asset quantity reduced; target account gets a new asset
```

> **Correction (v68 re-baseline):** the previous single-`assetId`/`targetAccountId` input shape and
> `transferQuoteId` output, plus the "New BillingArrangement created" claim, were fabricated or
> unverified — `BillingArrangement` was not confirmed as a real object and is out of scope for this
> skill (see `rlm-billing`). No dedicated Business API resource was found for Transfer in v68 — this
> action is available only via the Standard Invocable Actions / Actions REST layer:
> `POST /services/data/v68.0/actions/standard/initiateTransfer`.

### Step 9: Rollback

Reverts the most recent **amendment or renewal only** (not cancellation or transfer) on a future-dated
transaction. Use only when a lifecycle order was processed in error.

```
Initiate Rollback on Last Action (initiateRollBackLastAction)
  Inputs: assetIds, outputType (Quote|Order)
  → creates recordId (reversal Quote or Order)
  → approve → asset reverts to pre-action state
```

**Constraints (confirmed against the Standard Invocable Actions reference)**:
- Supported for **amendment and renewal only** — not cancellation or transfer
- Can roll back only **future-dated** transactions
- **Not supported for legacy assets**

> **Correction (v68 re-baseline):** the previous constraint list ("cannot rollback if billed",
> "cannot rollback a rollback", "cannot rollback a transfer") could **not be confirmed** against the
> v68 Standard Invocable Actions reference and has been replaced with the constraints actually
> documented there. No dedicated Business API resource was found for Rollback in v68 either — same
> as Transfer, invocable-action/Actions-REST only:
> `POST /services/data/v68.0/actions/standard/initiateRollBackLastAction`.

### Step 10: AssetRelationship

Links related assets — real confirmed `RelationshipType` values are Crossgrade/Replacement/Upgrade
(default `Replacement`), used for swap/upgrade/downgrade linkage, not bundle parent/child.

```apex
AssetRelationship ar = new AssetRelationship();
ar.AssetId = parentAsset.Id;
ar.RelatedAssetId = childAsset.Id;
ar.RelationshipType = 'Replacement';   // Crossgrade | Replacement | Upgrade (default: Replacement)
insert ar;
```

> **Correction (v68 re-baseline):** `RelationshipType` values `Component` and `Reference` (used in
> the prior version of this file) could **not be confirmed** — the confirmed real values are
> `Crossgrade`, `Replacement`, and `Upgrade`. `IsActive` on `AssetRelationship` is also **unverified**
> — see `references/asset-object-reference.md`. This object is now understood to back the v66+
> **Initiate Swap / Upgrade / Downgrade** Business APIs
> (`POST /revenue/transaction-management/assets/actions/{swap|upgrade|downgrade}`), which create
> `AssetRelationship` + linked `AssetAction` records categorized Swaps/Upgrades/Downgrades — genuinely
> new v66+ material not previously covered by this skill.

For bundle parent/child hierarchy tracking, use `Asset.ParentId`/`RootAssetId` directly (see
`references/asset-object-reference.md`) rather than `AssetRelationship`.

---

## Deployment

No catalog objects are deployed for asset management — `Asset` and related objects are standard Salesforce objects. Deploy the following Apex/metadata if using invocable actions:

```
1. Apex classes: any custom asset lifecycle handlers
2. Flows: any flows subscribing to CreateAssetOrderEvent
3. RevenueManagementSettings: enableDeltaPricing = true (if using delta pricing)
4. RevenueManagementSettings: enableAutoAddDerivedAsset = true (if BOM assets auto-create)
```

> **Annotation:** `enableDeltaPricing` and `enableAutoAddDerivedAsset` were not independently
> re-verified against Ch.2 RevenueManagementSettings in this pass (out of scope for the
> Ch.8-focused read performed for this re-baseline); kept as-is, no contradicting evidence found.

---

## Common Issues

### Lifecycle action fails: "No active assets found"
Cause: `Asset.Status` is not `Purchased`, or the asset's term has passed.
Solution: Verify `Asset.Status = 'Purchased'`. (Prior guidance referenced `Asset.LifecycleEndDate`,
which is **unverified** as a real field — see Step 1 correction; if your org lacks this field, use
whatever term-end field your Asset schema actually exposes.)

### Amendment effective date rejected
Cause: `amendStartDate` falls outside the asset's active term, or a conflicting amendment is
already in progress.
Solution: Confirm the asset's term boundaries in your org's Asset schema. The prior guidance to
query `QuoteAction WHERE Status = 'In Progress'` is **unverified** — `QuoteAction` could not be
confirmed as a real object (see Object Model correction above). To check for in-flight actions,
query `AssetAction` for the asset instead.

### AssetStatePeriod not created after amendment
Cause: `enableDeltaPricing` is false, or the amendment order was not fully activated.
Solution: Verify `Order.Status = 'Activated'`. Enable `RevenueManagementSettings.enableDeltaPricing = true`.

### Delta pricing not applied — full reprice on amendment
Cause: `enableDeltaPricing = false` in `RevenueManagementSettings`.
Solution: Set `enableDeltaPricing = true`. Note: this only reprices changed items; unchanged items carry forward.

### Renewal candidates not surfacing
Cause: The prior version of this skill described a `RenewalStatus` field "stuck on Draft" — that
field is **unverified** (see Step 5 correction). If renewal candidates aren't surfacing, call
**Get Renewable Assets Summary Action** with the relevant `orderId` and inspect
`renewableAssetsSummary[].endDate`/`.lastAssetAction` instead of querying a `RenewalStatus` picklist.
Solution: Confirm the order ID is correct and that `SalesTransactionContext`'s `OrderEntitiesMapping`
is mapped for your pricing procedure objects/fields (required for this action to return pricing).

### Rollback fails
Cause: The rollback action is **not supported for legacy assets**, only supports **future-dated**
transactions, and only reverses **amendment or renewal** (not cancellation or transfer).
Solution: Confirm the asset and the action being reversed meet these three constraints. (Prior
guidance describing "Cannot rollback billed asset" / invoice-based blocking is **unverified** against
the confirmed Initiate Rollback on Last Action constraints and has been replaced.)

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
| 2.0.0 | 2026-09-11 | **v68 (Winter '27) re-baseline.** Corrected fabricated `/commerce/assets/{id}/...` Business API paths to the confirmed v68 inventory (`/connect/revenue-management/assets/actions/{amend,cancel,renew}`; Transfer/Rollback confirmed to have no dedicated Connect resource, invocable-action/Actions-REST only); rewrote Amendment/Renewal/Cancellation/Transfer/Rollback flows against confirmed Standard Invocable Action I/O (`initiateAmendment`, `initiateRenewal`, `initiateCancellation`, `initiateTransfer`, `initiateRollBackLastAction`); flagged `Asset.LifecycleStartDate`/`LifecycleEndDate`/`RenewalStatus`, `AssetStatePeriod.Status`/`ChangeType`/`OrderId`/`ProratedMrrAmount`, and `QuoteAction` as unverified (not found in the v68 Standard Objects sections reviewed); corrected `AssetStatePeriod.MrrAmount` → `Mrr`; corrected `AssetRelationship.RelationshipType` values to confirmed `Crossgrade`\|`Replacement`\|`Upgrade`; added surgical coverage for `AssetActionSource` and `AssetContractRelationship` (previously uncovered) and the v66+ Swap/Upgrade/Downgrade Business APIs; corrected the Get Renewable Assets Summary Action's real `orderId` → `renewableAssetsSummary[]` shape; bumped compatibility to API v68.0+. |
| 1.0.0 | 2026-05-02 | Initial skill — Asset lifecycle, AssetStatePeriod, amendment/renewal/cancellation/transfer/rollback, delta pricing, co-term |

---

## References
- See `references/asset-object-reference.md` for full field-level reference for Asset, AssetStatePeriod, AssetAction, AssetActionSource, AssetRelationship, AssetContractRelationship
- See `rlm-transaction-management/references/asset-lifecycle-patterns.md` for invocable action input/output specs
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard Objects (Asset* cluster)
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard Invocable Actions
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Business API Resources

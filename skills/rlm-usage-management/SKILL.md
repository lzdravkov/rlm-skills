---
name: rlm-usage-management
description: Model, track, and bill usage entitlements using Salesforce Revenue Cloud's Usage Management module. Use when creating usage grants, entitlement buckets, usage resources, managing drawdown policies (ExpiringFirst/GrantedFirst), configuring overage policies, setting up billing period items, tracking usage summaries, or working with usage commitment assets. Do NOT use for standard order billing (use rlm-billing) or rate management (use rlm-rate-management). Triggers on: "usage", "usage grant", "entitlement", "drawdown", "usage bucket", "ProductUsageGrant", "UsageEntitlementBucket", "UsageResource", "overage", "usage summary", "usage commitment", "usage billing", "ExpiringFirst", "GrantedFirst", "UnitOfMeasure".
compatibility: Salesforce Revenue Cloud, API v66.0+, Usage Management module enabled
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Usage Management

## Object Model

```
Product2
  └── ProductUsageResource         (defines what usage resources a product provides)
       └── ProductUsageResourcePolicy  (policies governing the usage resource)

ProductUsageGrant                  (defines how usage is granted when a product is sold)
  ├── DrawdownOrder                (ExpiringFirst | GrantedFirst)
  └── ProductUsageResourceId

[At subscription/order time]
UsageEntitlementAccount            (per-account entitlement container)
  └── UsageEntitlementBucket[]     (individual grant buckets, accumulate over time)
       └── UsageEntitlementEntry[] (individual consumption records)

UsageResource                      (catalog of trackable usage resources)
UsageRatableSummary                (rolled-up summary of usage for billing)
UsageSummary                       (detailed usage record per period)

UnitOfMeasure                      (e.g., GB, Hour, Seat)
UnitOfMeasureClass                 (groups units of measure)

UsageCommitmentPolicy              (commitment levels, e.g., 100 GB/month minimum)
TransactionUsageEntitlement        (links a transaction line to usage entitlements)
UsageBillingPeriodItem             (billing period-level usage data for invoicing)
UsageCmtAssetRelatedObj            (links a commitment asset to related objects)
UsageRatableSumCmtAssetRt          (rate information for ratable summaries)
UsagePrdGrantBindingPolicy         (binding policy for product usage grants)
UsageGrantRenewalPolicy            (defines how grants renew at end of period)
UsageGrantRolloverPolicy           (defines how unused grants roll over)
UsageOveragePolicy                 (defines overage behavior when grant is exhausted)
```

---

## Instructions

### Step 1: Set Up Units of Measure

```apex
UnitOfMeasureClass uomClass = new UnitOfMeasureClass();
uomClass.Name = 'Data';
uomClass.DeveloperName = 'Data';
insert uomClass;

UnitOfMeasure uom = new UnitOfMeasure();
uom.Name = 'Gigabyte';
uom.UnitCode = 'GB';
uom.UnitOfMeasureClassId = uomClass.Id;
uom.RoundingMethod = 'Nearest';  // Up | Down | Nearest
uom.Scale = 3;                   // Decimal precision
insert uom;
```

### Step 2: Define Usage Resources

A `UsageResource` represents a trackable resource category:

```apex
UsageResource resource = new UsageResource();
resource.Name = 'Data Storage';
resource.DeveloperName = 'Data_Storage';
resource.UnitOfMeasureId = uom.Id;
resource.IsActive = true;
insert resource;
```

### Step 3: Link Products to Usage Resources

`ProductUsageResource` connects a Product2 to a UsageResource:

```apex
ProductUsageResource pur = new ProductUsageResource();
pur.Product2Id = product.Id;
pur.UsageResourceId = resource.Id;
pur.IsActive = true;
insert pur;
```

### Step 4: Configure Product Usage Grants

`ProductUsageGrant` defines how usage is granted when the product is sold:

```apex
ProductUsageGrant grant = new ProductUsageGrant();
grant.Name = '100 GB Storage Grant';
grant.Product2Id = product.Id;
grant.ProductUsageResourceId = pur.Id;
grant.Quantity = 100;                          // 100 GB per billing period
grant.DrawdownOrder = 'ExpiringFirst';         // ExpiringFirst | GrantedFirst
grant.EffectiveStartDate = DateTime.now();
grant.ProductSellingModelId = sellingModel.Id;
insert grant;
```

**DrawdownOrder values:**
- `ExpiringFirst` — consume grants that expire soonest first (recommended for time-limited grants)
- `GrantedFirst` — consume the most recently granted usage first
- `GrantedLast` — deprecated

### Step 5: Set Up Overage Policy

```apex
UsageOveragePolicy overagePolicy = new UsageOveragePolicy();
overagePolicy.Name = 'Standard Overage';
overagePolicy.OverageType = 'Chargeable';   // Chargeable | Block | Allow
overagePolicy.OverageRate = 0.10;           // per GB overage charge
overagePolicy.UsageResourceId = resource.Id;
insert overagePolicy;
```

### Step 6: Configure Grant Renewal and Rollover

```apex
// Renewal policy — how grants refresh each period
UsageGrantRenewalPolicy renewal = new UsageGrantRenewalPolicy();
renewal.Name = 'Monthly Renewal';
renewal.RenewalType = 'Fixed';      // Fixed | Cumulative
renewal.RenewalPeriod = 'Monthly';
insert renewal;

// Rollover policy — what happens to unused grants
UsageGrantRolloverPolicy rollover = new UsageGrantRolloverPolicy();
rollover.Name = 'No Rollover';
rollover.RolloverType = 'None';     // None | FullRollover | CappedRollover
insert rollover;
```

### Step 7: Entitlement Buckets (Runtime)

At subscription activation, the platform creates `UsageEntitlementAccount` and `UsageEntitlementBucket` records automatically from the `ProductUsageGrant` definitions. To query:

```apex
List<UsageEntitlementBucket> buckets = [
    SELECT Id, Name, RemainingQuantity, GrantedQuantity,
           ConsumedQuantity, ExpirationDate, Status,
           UsageEntitlementAccountId
    FROM UsageEntitlementBucket
    WHERE UsageEntitlementAccountId IN (
        SELECT Id FROM UsageEntitlementAccount WHERE AccountId = :accountId
    )
    AND Status = 'Active'
    ORDER BY ExpirationDate ASC
];
```

### Step 8: Usage Summary Queries

```apex
// Monthly usage summary
List<UsageSummary> summaries = [
    SELECT Id, UsageResourceId, UsageResource.Name,
           ConsumedQuantity, BillingPeriodStartDate, BillingPeriodEndDate,
           AccountId
    FROM UsageSummary
    WHERE AccountId = :accountId
      AND BillingPeriodStartDate >= :periodStart
      AND BillingPeriodEndDate <= :periodEnd
];

// Ratable summary for billing
List<UsageRatableSummary> ratables = [
    SELECT Id, TotalQuantity, BillableQuantity, OverageQuantity,
           UsageSummaryId, RateCardEntryId
    FROM UsageRatableSummary
    WHERE UsageSummary.AccountId = :accountId
];
```

### Step 9: Commitment Policies

For minimum-commitment products:

```apex
UsageCommitmentPolicy commitment = new UsageCommitmentPolicy();
commitment.Name = '100 GB Monthly Minimum';
commitment.CommitmentQuantity = 100;
commitment.CommitmentPeriod = 'Monthly';
commitment.UsageResourceId = resource.Id;
insert commitment;
```

---

## Deployment Sequence

```
1. UnitOfMeasureClass
2. UnitOfMeasure                  (→ UnitOfMeasureClass)
3. UsageResource                  (→ UnitOfMeasure)
4. UsageOveragePolicy             (→ UsageResource)
5. UsageGrantRenewalPolicy
6. UsageGrantRolloverPolicy
7. UsageCommitmentPolicy          (→ UsageResource)
8. ProductUsageResource           (→ Product2, UsageResource)
9. ProductUsageResourcePolicy     (→ ProductUsageResource, UsageOveragePolicy, etc.)
10. ProductUsageGrant             (→ Product2, ProductUsageResource, ProductSellingModel)
11. UsagePrdGrantBindingPolicy    (→ ProductUsageGrant)
```

Runtime objects (created by platform, not deployed):
- `UsageEntitlementAccount`
- `UsageEntitlementBucket`
- `UsageEntitlementEntry`
- `UsageSummary`
- `UsageRatableSummary`
- `UsageBillingPeriodItem`
- `TransactionUsageEntitlement`

---

## Common Issues

### `UsageEntitlementBucket` not created after activation
Cause: `ProductUsageGrant.IsActive = false` or `EffectiveStartDate` is in the future.
Solution: Confirm the grant is active and the effective date has passed.

### DrawdownOrder has no effect
Cause: Only one active bucket exists; drawdown order only matters when multiple buckets are present.
Solution: Check for multiple active `UsageEntitlementBucket` records for the account.

### Overage charges not appearing on invoice
Cause: `UsageOveragePolicy.OverageType` is `Allow` (not `Chargeable`) or the overage rate is not linked to a `RateCardEntry`.
Solution: Set `OverageType = 'Chargeable'` and ensure the overage rate is linked to an active rate card.

### Usage not rolling up to `UsageRatableSummary`
Cause: The IndustriesUsageSettings or the usage billing Flow is not activated.
Solution: Enable `IndustriesUsageSettings` and verify the usage billing Flow is active.

---

## See Also

| Skill | Why |
|---|---|
| `rlm-rate-management` | Overage charges are calculated using `RateCardEntry` records; `UsageRatableSummary.RateCardEntryId` links to rate management |
| `rlm-billing` | `UsageBillingPeriodItem` records are consumed by billing runs to generate invoice lines for usage-based charges |
| `rlm-transaction-management` | `TransactionUsageEntitlement` is created when an order containing usage-based products is decomposed; links the order line to usage entitlements |
| `rlm-deployment` | `IndustriesUsageSettings` must be deployed before runtime objects can be created |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.1.0 | 2026-05-02 | Added See Also table |
| 1.0.0 | 2026-04-29 | Initial skill — 22+ usage objects, DrawdownOrder, overage policy, grant renewal/rollover, commitment policies |

---

## References
- See `references/usage-objects-reference.md` for full field-level reference for all 22+ objects
- See `references/usage-invocable-actions.md` for Usage Management Standard Invocable Actions
- RLM Developer Guide v66.0, Chapter 11: Usage Management (p. 1841)

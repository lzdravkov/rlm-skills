---
name: rlm-rate-management
description: Model and apply usage-based or tiered pricing using Rate Cards, Rating Requests, and Rate Adjustments in Salesforce Revenue Cloud (RLM v66). Use when setting up rate cards with entries, binding rate adjustments to attributes or tiers, configuring rating frequency policies, linking price books to rate cards, or executing batch rating jobs. Do NOT use for standard list pricing (use rlm-pricing) or product catalog setup (use rlm-product-catalog). Triggers on: "rate card", "rate entry", "rating request", "rating frequency", "price book rate card", "rate adjustment", "binding object", "attribute adjustment", "tier adjustment", "batch rating", "RatingRequestBatchJob", "BindingObject".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition, Rate Management Permission Set License required
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Rate Management

## Important: Access Requirement

Rate Management objects are only accessible when the **Rate Management** permission set license is enabled for the org. Without it, all Rate Management objects return "Object not found" errors.

Verify access:
```bash
sf data query \
  --query "SELECT Id, Name FROM PermissionSetLicense WHERE DeveloperName = 'RateManagement'" \
  --target-org <alias>
```

---

## Object Model

```
RateCard
  └── RateCardEntry[]            (individual rate entries per card)
       └── BindingObjectRateCardEntry (binds a line item to a rate card entry)

RateCard ←─ PriceBookRateCard ──→ Pricebook2   (links rate card to a pricebook)

RateAdjustmentByAttribute        (adjust rate based on attribute value)
  └── AttributeAdjustmentCondition  (defines the attribute+value condition)
       └── AttributeBasedAdjustment (defines the adjustment amount/percentage/override)

RateAdjustmentByTier             (step-function rate adjustment by quantity tier)

BindingObjectCustomExt           (custom extension data for a binding object)
BindingObjectRateAdjustment      (binds a line item to a rate adjustment)

RatingRequest                    (ad-hoc rating calculation request)
RatingFrequencyPolicy            (cadence for how often rating runs)
RatingRequestBatchJob            (batch processing of rating requests)
```

---

## Instructions

### Step 1: Create a Rate Card

A `RateCard` is the top-level container for rate data. Create with standard DML:

```apex
RateCard rc = new RateCard();
rc.Name = 'Data Usage Rate Card 2026';
rc.CurrencyIsoCode = 'USD';
rc.EffectiveStartDate = Date.today();
insert rc;
```

### Step 2: Add Rate Card Entries

`RateCardEntry` stores the individual rate values:

```apex
RateCardEntry entry = new RateCardEntry();
entry.RateCardId = rc.Id;
entry.UnitPrice = 0.05;        // price per unit
entry.StartQuantity = 0;       // tier start (for tiered rates)
entry.EndQuantity = 1000;      // tier end
entry.RateUnit = 'GB';         // unit of measure
insert entry;
```

### Step 3: Link Rate Card to Pricebook

`PriceBookRateCard` associates a `RateCard` with a `Pricebook2`:

```apex
PriceBookRateCard pbrc = new PriceBookRateCard();
pbrc.RateCardId = rc.Id;
pbrc.Pricebook2Id = pricebook.Id;
pbrc.IsActive = true;
insert pbrc;
```

### Step 4: Configure Rate Adjustments

**By Attribute** — adjust rate when a specific attribute equals a value:

```apex
RateAdjustmentByAttribute raa = new RateAdjustmentByAttribute();
raa.Name = 'Enterprise Discount';
raa.RateCardId = rc.Id;
insert raa;

AttributeAdjustmentCondition cond = new AttributeAdjustmentCondition();
cond.RateAdjustmentByAttributeId = raa.Id;
cond.AttributeDefinitionId = attrDef.Id;
cond.AttributeValue = 'Enterprise';
insert cond;

AttributeBasedAdjustment adj = new AttributeBasedAdjustment();
adj.RateAdjustmentByAttributeId = raa.Id;
adj.AdjustmentType = 'Percentage';   // Amount | Override | Percentage
adj.AdjustmentValue = -15;           // 15% discount
insert adj;
```

`AdjustmentType` values:
- `Amount` — fixed dollar amount adjustment
- `Percentage` — percentage off the rate
- `Override` — replace the rate entirely

**By Tier** — step-function adjustment based on quantity tiers:

```apex
RateAdjustmentByTier rat = new RateAdjustmentByTier();
rat.Name = 'Volume Tier Adjustment';
rat.RateCardId = rc.Id;
insert rat;
```

### Step 5: Binding Objects

Binding objects connect a transaction line item to a specific rate card entry or adjustment. They are populated during the rating process, not created manually for most cases.

| Object | Purpose |
|---|---|
| `BindingObjectRateCardEntry` | Binds a line item to a specific `RateCardEntry` |
| `BindingObjectRateAdjustment` | Binds a line item to a `RateAdjustmentByAttribute` or `RateAdjustmentByTier` |
| `BindingObjectCustomExt` | Stores custom extension data for a bound object |

### Step 6: Rating Requests

A `RatingRequest` triggers calculation of charges based on usage data:

```apex
RatingRequest rr = new RatingRequest();
rr.Name = 'Monthly Rating - Nov 2026';
rr.RatingFrequencyPolicyId = rfp.Id;
rr.EffectiveStartDate = Date.newInstance(2026, 11, 1);
rr.EffectiveEndDate = Date.newInstance(2026, 11, 30);
insert rr;
```

For bulk processing, use `RatingRequestBatchJob`:

```apex
RatingRequestBatchJob batchJob = new RatingRequestBatchJob();
batchJob.RatingRequestId = rr.Id;
batchJob.Status = 'Pending';
insert batchJob;
```

### Step 7: Rating Frequency Policy

Controls how often rating runs:

```apex
RatingFrequencyPolicy rfp = new RatingFrequencyPolicy();
rfp.Name = 'Monthly';
rfp.Frequency = 'Monthly';
rfp.FrequencyStartDay = 1;
insert rfp;
```

---

## Deployment Sequence

```
1. RatingFrequencyPolicy
2. RateCard
3. RateCardEntry[]
4. PriceBookRateCard (→ Pricebook2, RateCard)
5. RateAdjustmentByAttribute / RateAdjustmentByTier (→ RateCard)
6. AttributeAdjustmentCondition (→ RateAdjustmentByAttribute, AttributeDefinition)
7. AttributeBasedAdjustment (→ RateAdjustmentByAttribute)
8. RatingRequest (→ RatingFrequencyPolicy)
9. RatingRequestBatchJob (→ RatingRequest)
```

---

## Binding Workflow: Link Rate Adjustments to a Transaction Line Item

Binding objects are normally created by the rating engine, but when testing or manually wiring:

```apex
// After rating runs, query the created binding objects
List<BindingObjectRateCardEntry> bindings = [
    SELECT Id, RateCardEntryId, TransactionLineItemId
    FROM BindingObjectRateCardEntry
    WHERE TransactionLineItemId = :quoteLineItemId
];

// To manually bind a rate adjustment to a line item (testing only):
BindingObjectRateAdjustment bindAdj = new BindingObjectRateAdjustment();
bindAdj.RateAdjustmentByAttributeId = raa.Id;
bindAdj.TransactionLineItemId = quoteLineItemId;
insert bindAdj;

// Add custom extension data to a binding:
BindingObjectCustomExt ext = new BindingObjectCustomExt();
ext.BindingObjectId = bindAdj.Id;
ext.CustomData__c = '{"tierLevel": "enterprise"}';
insert ext;
```

**Note**: In production, the rating engine creates `BindingObjectRateCardEntry` and `BindingObjectRateAdjustment` automatically during a `RatingRequest` execution. Manual creation is only needed for testing or custom rating extensions.

---

## Common Issues

### Rate Management objects not visible in SOQL
Cause: Rate Management permission set license not assigned.
Solution: Assign the Rate Management PSL in Setup → Permission Set Licenses.

### `AdjustmentType` invalid value error
Cause: Value must be exactly `Amount`, `Override`, or `Percentage` (case-sensitive).
Solution: Use these exact values; do not use `Discount` or `Fixed`.

### Rating not producing results
Cause: `RatingFrequencyPolicy` not linked to `RatingRequest`, or `PriceBookRateCard.IsActive = false`.
Solution: Verify the policy link and ensure the rate card is active.

### Rate card changes not reflected on new rating runs
Cause: `RateCardEntry` records updated but `PriceBookRateCard.IsActive` is still pointing to the old rate card.
Solution: Deactivate the old `PriceBookRateCard`, create a new one linking the updated `RateCard` to `Pricebook2`, then re-run the rating request.

### Tier adjustments not applied
Cause: `RateAdjustmentByTier` exists but has no `RateCardEntry` records with matching `StartQuantity`/`EndQuantity` bounds that overlap the usage quantity.
Solution: Verify `RateCardEntry.StartQuantity` and `EndQuantity` cover the actual consumed quantity. Check that `RateAdjustmentByTier.RateCardId` matches the active `PriceBookRateCard`.

### Binding objects not created after rating run
Cause: The `RatingRequest` completed but no `BindingObjectRateCardEntry` records appear.
Solution: Check `RatingRequestBatchJob.Status` — if `Failed`, query `RatingRequestBatchJob.ErrorMessage`. Verify that the `QuoteLineItem` or `OrderItem` has a `PriceBookEntryId` that resolves to the active `PriceBookRateCard`.

---

## See Also

| Skill | Why |
|---|---|
| `rlm-pricing` | Standard list pricing (PriceBookEntry, PriceAdjustmentSchedule) and rate card pricing are complementary paths in the same pricing waterfall |
| `rlm-usage-management` | Usage overage charges use rate card entries to calculate the overage billing amount; `UsageRatableSummary.RateCardEntryId` points here |
| `rlm-billing` | Rate card charges flow into billing line items via `UsageBillingPeriodItem` and `InvoiceLine` |
| `rlm-deployment` | Rate Management objects must be deployed after `Pricebook2` and `AttributeDefinition` exist |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.1.0 | 2026-05-02 | Added See Also table; expanded Common Issues (3 new entries); added Binding Workflow example; fixed frontmatter compatibility format |
| 1.0.0 | 2026-04-29 | Initial skill — rate cards, rate card entries, rate adjustments, binding objects, rating requests, frequency policy |

---

## References
- See `references/rate-management-objects.md` for full field-level reference for all Rate Management objects
- RLM Developer Guide v66.0, Chapter 6: Rate Management (p. 826)

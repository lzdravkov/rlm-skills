---
name: rlm-rate-management
description: Model and apply usage-based or tiered pricing using Rate Cards, Rating Requests, and Rate Adjustments in Salesforce Revenue Cloud (RLM v68). Use when setting up rate cards with entries, binding rate adjustments to attributes or tiers, configuring rating frequency policies, linking price books to rate cards, or executing batch rating jobs. Do NOT use for standard list pricing (use rlm-pricing) or product catalog setup (use rlm-product-catalog). Triggers on: "rate card", "rate entry", "rating request", "rating frequency", "price book rate card", "rate adjustment", "binding object", "attribute adjustment", "tier adjustment", "batch rating", "RatingRequestBatchJob", "BindingObject".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition, Rate Management Permission Set License required
metadata:
  version: 2.0.0
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
  └── RateCardEntry[]            (individual rate entries per card; Rate + RateUnitOfMeasureId)
       ├── RateAdjustmentByAttribute  (adjustment type/value directly on this object,
       │                               keyed to an AttributeBasedAdjRule — see note below)
       ├── RateAdjustmentByTier       (step-function adjustment by quantity: LowerBound/UpperBound)
       └── BindingObjectRateCardEntry (binds an Account/Contract/BindingObjectCustomExt
                                        target to a rate card entry, via BindingObjectId)
            └── BindingObjectRateAdjustment (adjustment type/value/bounds for that binding)

RateCard ←─ PriceBookRateCard ──→ Pricebook2   (PriceBookId + RateCardId, both master-detail)

BindingObjectCustomExt            (the external/custom target object itself — one of the
                                    polymorphic targets of BindingObjectRateCardEntry.BindingObjectId)

RatingRequest                     (ad-hoc rating calculation request; ContextDefinition +
                                    RatingProcedureName)
RatingFrequencyPolicy             (cadence for how often rating runs — RatingPeriod: Daily|Monthly)
RatingRequestBatchJob             (batch processing of rating requests; BatchJobId + ErrorCode)
```

> **v68 note:** `RateAdjustmentByAttribute` is **not** a parent of `AttributeAdjustmentCondition`/
> `AttributeBasedAdjustment` — those two objects are defined once, in Chapter 5 (Salesforce
> Pricing), and shared between pricing and rating via a `UsageType` picklist (`Pricing`|`Rating`).
> `RateAdjustmentByAttribute` instead links directly to the Ch.5 `AttributeBasedAdjRule` object via
> `AttributeBasedAdjRuleId`, and carries its own `AdjustmentType`/`AdjustmentValue` fields. See
> `references/rate-management-objects.md` for the corrected field-level model.
> Source: RLM Developer Guide v68.0, Ch.6 Rate Management › Standard Objects (printed pp.908–942).

---

## Instructions

### Step 1: Create a Rate Card

A `RateCard` is the top-level container for rate data. Create with standard DML:

```apex
RateCard rc = new RateCard();
rc.Name = 'Data Usage Rate Card 2026';
rc.Type = 'Base';              // Attribute | Base | Tier
rc.EffectiveFrom = Date.today();
insert rc;
```

**v68 correction:** `RateCard` has no `CurrencyIsoCode` or `IsActive` field, and the effective-dating
fields are `EffectiveFrom`/`EffectiveTo` (not `EffectiveStartDate`). Source: Ch.6 Rate Management ›
Standard Objects › RateCard (printed pp.928–930).

### Step 2: Add Rate Card Entries

`RateCardEntry` stores the individual rate values. Tiering (quantity ranges) is modeled separately
on `RateAdjustmentByTier`, not on the entry itself:

```apex
RateCardEntry entry = new RateCardEntry();
entry.RateCardId = rc.Id;
entry.ProductId = product.Id;
entry.Rate = 0.05;                        // rate value for this entry
entry.RateUnitOfMeasureId = gbUom.Id;      // lookup to UnitOfMeasure
entry.RateCardType = 'Base';               // Attribute | Base | Tier
entry.Status = 'Active';                   // Active | Draft | Inactive
insert entry;
```

**v68 correction:** There is no `UnitPrice`, `StartQuantity`, `EndQuantity`, `RateUnit`, or
`CurrencyIsoCode` field on `RateCardEntry`. The rate value is `Rate`; the unit of measure is a
lookup (`RateUnitOfMeasureId`), not a free-text string. Source: Ch.6 › RateCardEntry (printed
pp.930–935).

### Step 3: Link Rate Card to Pricebook

`PriceBookRateCard` associates a `RateCard` with a `Pricebook2`:

```apex
PriceBookRateCard pbrc = new PriceBookRateCard();
pbrc.RateCardId = rc.Id;
pbrc.PriceBookId = pricebook.Id;   // NOT Pricebook2Id — relationship name is "PriceBook"
pbrc.RateCardType = 'Base';
insert pbrc;
```

**v68 correction:** The lookup field is `PriceBookId` (relationship name `PriceBook`), not
`Pricebook2Id`, and there is no `IsActive` field — both `PriceBookId` and `RateCardId` are
master-detail. Source: Ch.6 › PriceBookRateCard (printed pp.917–919).

### Step 4: Configure Rate Adjustments

**By Attribute** — adjust rate when a specific attribute-based rule (Ch.5 Salesforce Pricing
object model) matches. Unlike the pre-v68 version of this skill, `RateAdjustmentByAttribute` is
master-detail to `RateCardEntry` and carries the adjustment type/value directly — it does **not**
have its own `AttributeAdjustmentCondition`/`AttributeBasedAdjustment` children:

```apex
// 1. Define the attribute rule + its condition(s) in the Ch.5 Pricing object model,
//    tagged for rating via UsageType = 'Rating':
AttributeBasedAdjRule rule = new AttributeBasedAdjRule();
rule.Name = 'Enterprise Discount';
insert rule;

AttributeAdjustmentCondition cond = new AttributeAdjustmentCondition();
cond.AttributeBasedAdjRuleId = rule.Id;     // NOT a RateAdjustmentByAttribute lookup
cond.AttributeDefinitionId = attrDef.Id;
cond.Operator = 'equals';
cond.StringValue = 'Enterprise';
cond.UsageType = 'Rating';                  // Pricing | Rating
insert cond;

// 2. Apply the rule to a rate card entry:
RateAdjustmentByAttribute raa = new RateAdjustmentByAttribute();
raa.RateCardEntryId = entry.Id;             // master-detail — required
raa.AttributeBasedAdjRuleId = rule.Id;
raa.AdjustmentType = 'Percentage';          // Amount | Override | Percentage
raa.AdjustmentValue = -15;                  // 15% discount
insert raa;
```

`AdjustmentType` values:
- `Amount` — fixed dollar amount adjustment
- `Percentage` — percentage off the rate
- `Override` — replace the rate entirely

**v68 correction:** `AttributeAdjustmentCondition` and `AttributeBasedAdjustment` are objects
documented once in Chapter 5 (Salesforce Pricing) and reused for rating via `UsageType`; there is
no `RateAdjustmentByAttributeId` field on either. `RateAdjustmentByAttribute` itself links to
`RateCardEntryId` (master-detail, required) and `AttributeBasedAdjRuleId`, and holds
`AdjustmentType`/`AdjustmentValue` directly. Source: Ch.6 › RateAdjustmentByAttribute (printed
pp.919–923); Ch.5 › AttributeAdjustmentCondition (pp.666–669) and AttributeBasedAdjustment
(pp.671–675).

**By Tier** — step-function adjustment based on quantity tiers, also master-detail to
`RateCardEntry`:

```apex
RateAdjustmentByTier rat = new RateAdjustmentByTier();
rat.RateCardEntryId = entry.Id;    // master-detail — required, NOT RateCardId
rat.AdjustmentType = 'Percentage'; // Amount | Override | Percentage
rat.AdjustmentValue = -5;
rat.LowerBound = 1000;
rat.UpperBound = null;             // open-ended upper tier
insert rat;
```

**v68 correction:** `RateAdjustmentByTier` is master-detail to `RateCardEntry` via
`RateCardEntryId`, not a bare header keyed to `RateCard.Name`. Source: Ch.6 ›
RateAdjustmentByTier (printed pp.924–927).

### Step 5: Binding Objects

Binding objects connect a transaction line item to a specific rate card entry or adjustment. They are populated during the rating process, not created manually for most cases.

| Object | Purpose |
|---|---|
| `BindingObjectRateCardEntry` | Binds a target record (`Account`, `Contract`, or `BindingObjectCustomExt`, via the polymorphic `BindingObjectId`) to a specific `RateCardEntry` |
| `BindingObjectRateAdjustment` | Master-detail child of `BindingObjectRateCardEntry`; carries `AdjustmentType`/`AdjustmentValue`/`LowerBound`/`UpperBound` for that binding |
| `BindingObjectCustomExt` | The external/custom target object itself (one of the valid `BindingObjectId` targets) — not a data wrapper around an existing binding |

**v68 correction:** the pre-v68 version of this table described these objects around a
`TransactionLineItemId`/`ExtensionData` model that doesn't match the documented schema — see the
Binding Workflow section below and `references/rate-management-objects.md` for corrected fields.
Source: Ch.6 › BindingObjectRateCardEntry, BindingObjectRateAdjustment, BindingObjectCustomExt
(printed pp.909–916).

### Step 6: Rating Requests

A `RatingRequest` triggers rating of the aggregated usage records for a given context definition
and rating procedure:

```apex
RatingRequest rr = new RatingRequest();
rr.ContextDefinition = 'UsageRatingContext';   // context def used to build the context instance
rr.RatingProcedureName = 'MonthlyUsageRating'; // the rating procedure to run
rr.DoesExcludeWaterfall = false;               // available in API 64.0+
insert rr;
```

**v68 correction:** There is no `RatingFrequencyPolicyId`, `EffectiveStartDate`, or
`EffectiveEndDate` field on `RatingRequest` — those concerns live on `RatingFrequencyPolicy` and
the rateable-summary records themselves. `Status` (system-managed) uses the values
`Failed`/`Pending`/`RatingComplete`/`RatingInProgress`/`ReadyForRating`, not
`Pending`/`InProgress`/`Completed`/`Failed`. Source: Ch.6 › RatingRequest (printed pp.938–940).

For bulk processing, `RatingRequestBatchJob` links a `RatingRequest` to the `BatchJob` that
processed it, and surfaces batch-level failures:

```apex
// RatingRequestBatchJob is created by the platform when a batch job processes a RatingRequest.
// Its own fields are limited to the batch-job link and error detail — there is no Status,
// StartTime, EndTime, or RecordsProcessed field to set directly.
List<RatingRequestBatchJob> failedJobs = [
    SELECT Id, BatchJobId, ErrorCode, ErrorMessage
    FROM RatingRequestBatchJob
    WHERE RatingRequestId = :rr.Id AND ErrorCode != null
];
```

**v68 correction:** `RatingRequestBatchJob` has no `Status`/`StartTime`/`EndTime`/
`RecordsProcessed` fields — only `BatchJobId`, `ErrorCode` (`BadRequest`|`InternalError`), and
`ErrorMessage`. Source: Ch.6 › RatingRequestBatchJob (printed pp.940–942).

### Step 7: Rating Frequency Policy

Controls how often rating runs:

```apex
RatingFrequencyPolicy rfp = new RatingFrequencyPolicy();
rfp.Name = 'Monthly';
rfp.RatingPeriod = 'Monthly';           // Daily | Monthly (only two valid values)
rfp.RatingDelayDuration = 2;
rfp.RatingDelayDurationUnit = 'Days';   // Days | Hours — available in API 65.0+
insert rfp;
```

**v68 correction:** The cadence field is `RatingPeriod` with only two valid values (`Daily`,
`Monthly`) — not a 5-value `Frequency` picklist. There is no `FrequencyStartDay` field; delay is
controlled via `RatingDelayDuration` + `RatingDelayDurationUnit`. `ProductId` on this object is
deprecated and scheduled for retirement. Source: Ch.6 › RatingFrequencyPolicy (printed pp.936–938).

---

## Deployment Sequence

```
1. RatingFrequencyPolicy
2. RateCard
3. RateCardEntry[] (→ RateCard, Product2, ProductSellingModel, UsageResource)
4. PriceBookRateCard (→ Pricebook2 via PriceBookId, RateCard)
5. AttributeBasedAdjRule + AttributeAdjustmentCondition (Ch.5 Pricing objects, tagged
   UsageType = 'Rating') — must exist before step 6
6. RateAdjustmentByAttribute (→ RateCardEntry, AttributeBasedAdjRuleId)
7. RateAdjustmentByTier (→ RateCardEntry)
8. RatingRequest (references a ContextDefinition + RatingProcedureName; not a direct
   RatingFrequencyPolicy lookup)
9. RatingRequestBatchJob (→ RatingRequest, BatchJob)
```

**v68 correction:** Steps 6–7 reflect that `RateAdjustmentByAttribute`/`RateAdjustmentByTier` are
master-detail to `RateCardEntry` (not bare `RateCard` children), and that `AttributeAdjustmentCondition`
is a Ch.5 Pricing object, not a Rate Management child of `RateAdjustmentByAttribute`.

---

## Binding Workflow: Link Rate Adjustments to a Transaction Line Item

Binding objects are normally created by the rating engine, but when testing or manually wiring:

```apex
// After rating runs, query the created binding objects for a target Account or Contract
List<BindingObjectRateCardEntry> bindings = [
    SELECT Id, RateCardEntryId, RateCardId, NegotiatedRate, BindingObjectId
    FROM BindingObjectRateCardEntry
    WHERE BindingObjectId = :targetAccountId
];

// To manually bind a rate card entry to a target record (testing only):
BindingObjectRateCardEntry bindEntry = new BindingObjectRateCardEntry();
bindEntry.BindingObjectId = targetAccountId;   // polymorphic: Account | Contract | BindingObjectCustomExt
bindEntry.RateCardEntryId = entry.Id;
bindEntry.RateCardId = rc.Id;
bindEntry.NegotiatedRate = 0.045;
insert bindEntry;

// Add a rate adjustment to that binding — master-detail child of BindingObjectRateCardEntry:
BindingObjectRateAdjustment bindAdj = new BindingObjectRateAdjustment();
bindAdj.BindingObjectRateCardEntryId = bindEntry.Id;
bindAdj.AdjustmentType = 'Percentage';   // Amount | Override | Percentage
bindAdj.AdjustmentValue = -10;
bindAdj.LowerBound = 0;
bindAdj.UpperBound = 5000;
insert bindAdj;

// BindingObjectCustomExt is itself a valid BindingObjectId target (for custom/external
// targets that aren't Account or Contract) — it isn't a wrapper you attach after the fact:
BindingObjectCustomExt customTarget = new BindingObjectCustomExt();
customTarget.Name = 'External Partner Entitlement 4471';
insert customTarget;
```

**v68 correction:** There is no `TransactionLineItemId` field on `BindingObjectRateCardEntry` or
`BindingObjectRateAdjustment`, and `BindingObjectCustomExt` has no `BindingObjectId`/`CustomData__c`
fields — it *is* one of the polymorphic targets referenced *from*
`BindingObjectRateCardEntry.BindingObjectId`, not a container attached to an existing binding.
Source: Ch.6 › BindingObjectRateCardEntry, BindingObjectRateAdjustment, BindingObjectCustomExt
(printed pp.909–916).

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
Cause: `RatingRequest.RatingProcedureName` doesn't resolve to an active rating procedure, or the
referenced `RateCardEntry.Status` is `Draft`/`Inactive` rather than `Active`.
Solution: Verify the procedure name and confirm the entry's `Status = 'Active'`.

### Rate card changes not reflected on new rating runs
Cause: `RateCardEntry` records updated on a `RateCard` that's still linked via `PriceBookRateCard`,
but the entries in question have `Status = 'Draft'`.
Solution: Set the updated `RateCardEntry.Status` to `Active`, or create a new `RateCard`/
`PriceBookRateCard` pairing and re-run the rating request. (There is no `IsActive` field on
`PriceBookRateCard` to toggle — see the v68 correction under Step 3.)

### Tier adjustments not applied
Cause: `RateAdjustmentByTier` exists but its `LowerBound`/`UpperBound` don't cover the consumed
quantity, or it isn't linked to the `RateCardEntry` actually resolved for the usage record.
Solution: Verify `RateAdjustmentByTier.LowerBound`/`UpperBound` cover the actual consumed quantity,
and confirm `RateAdjustmentByTier.RateCardEntryId` (master-detail — not a `RateCardId` lookup)
points at the entry used by the active `PriceBookRateCard`.

### Binding objects not created after rating run
Cause: The `RatingRequest` completed but no `BindingObjectRateCardEntry` records appear.
Solution: Query `RatingRequestBatchJob.ErrorCode`/`ErrorMessage` for the request (there is no
`Status` field on this object — see Step 6). Verify that the target record referenced by
`BindingObjectRateCardEntry.BindingObjectId` and the `RateCardEntry` resolve to the active
`PriceBookRateCard`.

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
| 2.0.0 | 2026-09-11 | v68.0 (Winter '27) re-baseline. Corrected field names across `RateCard`, `RateCardEntry`, `PriceBookRateCard`, `RateAdjustmentByAttribute`, `RateAdjustmentByTier`, `RatingFrequencyPolicy`, `RatingRequest`, `RatingRequestBatchJob`, and the `BindingObject*` objects against the v68 Dev Guide (Ch.6 Rate Management, printed pp.908–954); corrected the Object Model diagram and Deployment Sequence to reflect that `AttributeAdjustmentCondition`/`AttributeBasedAdjustment` are shared Ch.5 Salesforce Pricing objects (via `UsageType`), not Rate Management–specific children of `RateAdjustmentByAttribute`; replaced page-number citations with section-title citations; bumped compatibility to API v68.0+ |
| 1.1.0 | 2026-05-02 | Added See Also table; expanded Common Issues (3 new entries); added Binding Workflow example; fixed frontmatter compatibility format |
| 1.0.0 | 2026-04-29 | Initial skill — rate cards, rate card entries, rate adjustments, binding objects, rating requests, frequency policy |

---

## References
- See `references/rate-management-objects.md` for full field-level reference for all Rate Management objects
- RLM Developer Guide v68.0 (Winter '27), Chapter 6: Rate Management — Standard Objects, Metadata API, Business APIs, Standard Invocable Actions (printed pp.907–954)
- RLM Developer Guide v68.0, Chapter 5: Salesforce Pricing — Standard Objects, for the shared `AttributeAdjustmentCondition`/`AttributeBasedAdjustment`/`AttributeBasedAdjRule` objects (printed pp.663–746)

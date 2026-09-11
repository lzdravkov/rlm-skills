# Rate Management — Object Reference

All objects require Rate Management permission set license.

> **v68 verification note (2026-09-11):** Field names in this reference were re-verified against the
> RLM Developer Guide v68.0 (Winter '27), Chapter 6: Rate Management — Standard Objects, and
> Chapter 5: Salesforce Pricing — Standard Objects (for the two shared attribute-condition objects).
> Several field names in the pre-v68 version of this document did not match the documented schema
> (e.g., `RateCard.EffectiveStartDate`/`EffectiveEndDate` vs. the actual `EffectiveFrom`/`EffectiveTo`).
> This pass corrects them in place; see the Changelog in `SKILL.md` for the summary of changes.

---

## RateCard

Top-level container for rate data.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `Type` | Picklist | `Attribute` \| `Base` \| `Tier` — the rate card's role in the rating waterfall |
| `EffectiveFrom` | DateTime | When the rate card becomes effective |
| `EffectiveTo` | DateTime | When the rate card remains effective until |
| `Description` | String | |
| `OwnerId` | Reference → Group, User | Polymorphic owner field |

**Correction (v68):** There is no `CurrencyIsoCode` or `IsActive` field on `RateCard`. The
effective-dating fields are `EffectiveFrom`/`EffectiveTo` (DateTime), not `EffectiveStartDate`/
`EffectiveEndDate`. Source: RLM Developer Guide, Ch.6 Rate Management › Standard Objects › RateCard
(printed pp.928–930).

---

## RateCardEntry

Individual rate entry within a RateCard. Each entry is linked to exactly one rate card.

| Field | Type | Description |
|---|---|---|
| `RateCardId` | Reference → RateCard | Required. Master-detail. |
| `Rate` | Double | The rate value for this entry |
| `ProductId` | Reference → Product2 | Product whose resource is being rated |
| `ProductSellingModelId` | Reference → ProductSellingModel | |
| `UsageProductId` | Reference → Product2 | Product associated with the resource for which the rate is specified |
| `UsageResourceId` | Reference → UsageResource | Create/Update supported |
| `RateUnitOfMeasureId` | Reference → UnitOfMeasure | Standard unit of measure for the rate |
| `RateUnitOfMeasureName` | String | Name of the standard unit of measure |
| `DefaultUnitOfMeasureId` | Reference → UnitOfMeasure | Default UoM for this entry |
| `DefaultUnitOfMeasureClassId` | Reference → UnitOfMeasureClass | Default UoM classification |
| `RateCardType` | Picklist | `Attribute` \| `Base` \| `Tier`. Available in API 63.0+ |
| `RateNegotiation` | Picklist | `Negotiable` \| `NonNegotiable`. Default `Negotiable`. Available in API 63.0+ |
| `Status` | Picklist | `Active` \| `Draft` \| `Inactive`. Default `Draft`. Available in API 63.0+ |

**Correction (v68):** There is no `UnitPrice`, `StartQuantity`, `EndQuantity`, `RateUnit`, or
`CurrencyIsoCode` field on `RateCardEntry`. The rate value field is `Rate`; unit-of-measure is
represented via `RateUnitOfMeasureId`/`RateUnitOfMeasureName`, not a free-text `RateUnit` string.
Tiering (quantity ranges) is not stored on `RateCardEntry` itself — it's modeled on
`RateAdjustmentByTier` (`LowerBound`/`UpperBound`). Source: Ch.6 › RateCardEntry (printed pp.930–935).

---

## PriceBookRateCard

Links a RateCard to a Pricebook2.

| Field | Type | Description |
|---|---|---|
| `PriceBookId` | Reference → Pricebook2 | Required. Master-detail. Relationship name `PriceBook`. For Quote/Order/Contract, this identifies the associated rate cards. |
| `RateCardId` | Reference → RateCard | Required. Master-detail. |
| `RateCardType` | Picklist | `Attribute` \| `Base` \| `Tier` |

**Correction (v68):** The lookup field name is `PriceBookId` (not `Pricebook2Id`), and there is no
`IsActive` field on this junction object — both `PriceBookId` and `RateCardId` are master-detail
relationships. Source: Ch.6 › PriceBookRateCard (printed pp.917–919).

---

## RateAdjustmentByAttribute

Applies a rate adjustment to a `RateCardEntry` when an attribute-based rule (defined in the
Pricing object model) matches. **This object holds the adjustment type/value directly** — it does
not have its own child condition/adjustment objects. It references the shared
`AttributeBasedAdjRule` object from Chapter 5 (Salesforce Pricing).

| Field | Type | Description |
|---|---|---|
| `RateCardEntryId` | Reference → RateCardEntry | Required. Master-detail. |
| `AttributeBasedAdjRuleId` | Reference → AttributeBasedAdjRule | The attribute-based rule (Ch.5 Pricing object) that drives this adjustment |
| `AdjustmentType` | Picklist | `Amount` \| `Override` \| `Percentage` |
| `AdjustmentValue` | Double | Value of the adjustment based on the selected type |
| `ProductId` | Reference → Product2 | |
| `ProductSellingModelId` | Reference → ProductSellingModel | |
| `RateCardId` | Reference → RateCard | |
| `RateCardEntryStatus` | Picklist | `Active` \| `Draft` \| `Inactive`. Available in API 63.0+ |
| `RateUnitOfMeasureId` | Reference → UnitOfMeasure | |
| `RateUnitOfMeasureName` | String | |

**Correction (v68):** The pre-v68 version of this document modeled `RateAdjustmentByAttribute` as a
bare header object with `AttributeAdjustmentCondition`/`AttributeBasedAdjustment` as its children via
a `RateAdjustmentByAttributeId` lookup. That field does not exist. `AttributeAdjustmentCondition` and
`AttributeBasedAdjustment` are **shared objects defined in Chapter 5 (Salesforce Pricing)** — they
carry a `UsageType` picklist (`Pricing` \| `Rating`) and link back to `AttributeBasedAdjRule` via
`AttributeBasedAdjRuleId`, not to `RateAdjustmentByAttribute`. See the corrected entries below.
Source: Ch.6 › RateAdjustmentByAttribute (printed pp.919–923).

---

## AttributeAdjustmentCondition (shared with Ch.5 Salesforce Pricing)

Defines the attribute + value condition for an `AttributeBasedAdjRule`. Documented once, in
Chapter 5, and reused for both pricing and rating via the `UsageType` field.

| Field | Type | Description |
|---|---|---|
| `AttributeBasedAdjRuleId` | Reference → AttributeBasedAdjRule | Required |
| `AttributeDefinitionId` | Reference → AttributeDefinition | |
| `ProductId` | Reference → Product2 | |
| `Operator` | Picklist | `doesnotexistin` \| `equals` \| `existsin` \| `greaterorequal` \| `greaterthan` \| `lessorequal` \| `lessthan` \| `matches` \| `notequals`. Default `equals` |
| `BooleanValue` / `DateTimeValue` / `DateValue` / `DoubleValue` / `IntegerValue` / `StringValue` | (typed) | The comparison value, typed per the attribute's data type |
| `UsageType` | Picklist | `Pricing` \| `Rating` — set to `Rating` for rate-management conditions |

**Correction (v68):** No `RateAdjustmentByAttributeId` field exists on this object; the link to the
attribute rule is `AttributeBasedAdjRuleId`. Source: Ch.5 Salesforce Pricing › AttributeAdjustmentCondition
(printed pp.666–669); reuse for rating confirmed via the `UsageType` field (`Pricing` \| `Rating`).

---

## AttributeBasedAdjustment (shared with Ch.5 Salesforce Pricing)

Defines the adjustment amount/type/term for an `AttributeBasedAdjRule`. Documented once, in
Chapter 5, and reused for rating via `UsageType`.

| Field | Type | Description |
|---|---|---|
| `AttributeBasedAdjRuleId` | Reference → AttributeBasedAdjRule | Required |
| `PriceAdjustmentScheduleId` | Reference → PriceAdjustmentSchedule | (Pricing usage) |
| `ProductId` | Reference → Product2 | |
| `ProductSellingModelId` | Reference → ProductSellingModel | |
| `AdjustmentType` | Picklist | `Amount` \| `Override` \| `Percentage` |
| `AdjustmentValue` | Double | The amount; negative for discounts (percentage: `-15` = 15% off) |
| `SellingModelType` | Picklist | `Evergreen` \| `OneTime` \| `TermDefined` |
| `UsageType` | Picklist | `Pricing` \| `Rating` |

**Correction (v68):** No `RateAdjustmentByAttributeId` field exists on this object either — the link
is `AttributeBasedAdjRuleId`. Source: Ch.5 Salesforce Pricing › AttributeBasedAdjustment (printed
pp.671–675).

---

## RateAdjustmentByTier

Step-function rate adjustment based on quantity ranges, linked directly to a `RateCardEntry`.

| Field | Type | Description |
|---|---|---|
| `RateCardEntryId` | Reference → RateCardEntry | Required. Master-detail. |
| `AdjustmentType` | Picklist | `Amount` \| `Override` \| `Percentage` |
| `AdjustmentValue` | Double | Value of the adjustment based on the selected type |
| `LowerBound` | Double | Minimum quantity the tier applies to |
| `UpperBound` | Double | Maximum quantity the tier applies to |
| `ProductId` | Reference → Product2 | |
| `ProductSellingModelId` | Reference → ProductSellingModel | |
| `RateCardId` | Reference → RateCard | |
| `RateCardEntryStatus` | Picklist | `Active` \| `Draft` \| `Inactive`. Default `Draft`. Available in API 63.0+ |
| `RateUnitOfMeasureId` | Reference → UnitOfMeasure | |
| `RateUnitOfMeasureName` | String | |

**Correction (v68):** `RateAdjustmentByTier` is master-detail to `RateCardEntry` (`RateCardEntryId`),
not to a bare `RateCard.Name`/`IsActive` header as previously documented. Source: Ch.6 ›
RateAdjustmentByTier (printed pp.924–927).

---

## BindingObjectRateCardEntry

Binds a rate card entry to a target object (an `Account`, `Contract`, or `BindingObjectCustomExt`
record) — the "binding object" — during rating. This is the master object for
`BindingObjectRateAdjustment`.

| Field | Type | Description |
|---|---|---|
| `BindingObjectId` | Reference → Account, BindingObjectCustomExt, Contract | Polymorphic. The object bound to the entitlements granted with the sellable product |
| `RateCardEntryId` | Reference → RateCardEntry | |
| `RateCardId` | Reference → RateCard | |
| `RateCardType` | Picklist | `Attribute` \| `Base` \| `Tier` |
| `UsageResourceId` | Reference → UsageResource | |
| `SourceAssetId` | Reference → Asset | The asset used to create this binding entry |
| `RateUnitOfMeasureId` | Reference → UnitOfMeasure | |
| `NegotiatedRate` | Double | The rate negotiated for the associated binding object |
| `EffectiveFrom` / `EffectiveTo` | DateTime | Effective dating for this entry |
| `BindingObjectRateOrder` | Double | Order that determines the applicable rate when multiple rates are defined for an anchor target within an effective period. Available in API 65.0+ |
| `BindingObjectUsageResourceKey` | String | Auto-generated composite key: `BindingObjectId_UsageResourceId` (≤18 chars). Available in API 66.0+ |
| `OwnerId` | Reference → Group, User | |

**Correction (v68):** The field is `BindingObjectId` (polymorphic to `Account`/`BindingObjectCustomExt`/
`Contract`), not a generic `ReferenceObjectId` string, and there is no `Quantity` field on this
object. Source: Ch.6 › BindingObjectRateCardEntry (printed pp.912–916).

---

## BindingObjectRateAdjustment

Binds a rate adjustment to a `BindingObjectRateCardEntry`. Master-detail child.

| Field | Type | Description |
|---|---|---|
| `BindingObjectRateCardEntryId` | Reference → BindingObjectRateCardEntry | Required. Master-detail. |
| `AdjustmentType` | Picklist | `Amount` \| `Override` \| `Percentage` |
| `AdjustmentValue` | Double | The value of the rate adjustment based on the adjustment type |
| `LowerBound` / `UpperBound` | Double | Quantity bounds this adjustment applies to |

**Correction (v68):** No `RateAdjustmentId` or `ReferenceObjectId` field exists — this object is
master-detail under `BindingObjectRateCardEntry` and stores the adjustment type/value/bounds
directly. Source: Ch.6 › BindingObjectRateAdjustment (printed pp.910–912).

---

## BindingObjectCustomExt

Represents the **external or custom target object itself** that's bound to the entitlements
granted with a sellable product (i.e., this is one of the valid targets of
`BindingObjectRateCardEntry.BindingObjectId` when the target isn't a standard `Account` or
`Contract`). It is largely a marker/extension object — any business-specific data lives in custom
fields you add to it.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Name of the binding custom object record |
| `OwnerId` | Reference → Group, User | |

**Correction (v68):** There is no documented standard `BindingObjectId` or `ExtensionData` field on
`BindingObjectCustomExt` itself — those were an incorrect assumption in the pre-v68 version of this
doc. `BindingObjectCustomExt` *is* the extension target, referenced *from*
`BindingObjectRateCardEntry.BindingObjectId`, not the other way around. Add org-specific custom
fields to this object as needed. Source: Ch.6 › BindingObjectCustomExt (printed pp.909–910).

---

## RatingFrequencyPolicy

Defines the cadence for rating calculations.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `RatingPeriod` | Picklist | `Daily` \| `Monthly` — period for which the usage of a product + usage-resource combination is rated |
| `RatingDelayDuration` | Integer | Duration of delay (in the unit below) post-billing-period after which rating is triggered |
| `RatingDelayDurationUnit` | Picklist | `Days` \| `Hours`. Available in API 65.0+ |
| `ProductId` | Reference → Product2 | **Deprecated** — will be retired in a future release |
| `OwnerId` | Reference → Group, User | |

**Correction (v68):** The frequency field is `RatingPeriod` with only two valid values (`Daily`,
`Monthly`) — not a 5-value `Frequency` picklist (`Daily`/`Weekly`/`Monthly`/`Quarterly`/`Annually`).
There is no `FrequencyStartDay` field; delay is controlled via `RatingDelayDuration` +
`RatingDelayDurationUnit`. Source: Ch.6 › RatingFrequencyPolicy (printed pp.936–938).

---

## RatingRequest

Represents the common run-time parameters (context definition and rating procedure) for rating a
set of records in the rateable summary table.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Auto-generated identifier |
| `ContextDefinition` | String | Context definition used for context-instance creation, encapsulating all aggregated records stamped for the rating request |
| `ContextMapping` | String | Context mapping used for context-instance creation. If not provided, the default context mapping is used |
| `RatingProcedureName` | String | Procedure used to rate the aggregated records stamped for this request |
| `DoesExcludeWaterfall` | Boolean | If `true`, no waterfall is generated for this request. Default `false`. Available in API 64.0+ |
| `Status` | Picklist | `Failed` \| `Pending` \| `RatingComplete` \| `RatingInProgress` \| `ReadyForRating` |
| `OwnerId` | Reference → Group, User | |

**Correction (v68):** There is no `RatingFrequencyPolicyId`, `EffectiveStartDate`, or
`EffectiveEndDate` field on `RatingRequest` — those effective-dating/frequency concerns live on
`RatingFrequencyPolicy` and the rateable summary records themselves, not on `RatingRequest`. The
`Status` picklist values are `Failed`/`Pending`/`RatingComplete`/`RatingInProgress`/`ReadyForRating`
(not `Pending`/`InProgress`/`Completed`/`Failed`). Source: Ch.6 › RatingRequest (printed pp.938–940).

---

## RatingRequestBatchJob

Junction between `RatingRequest` and `BatchJob`, representing bulk processing.

| Field | Type | Description |
|---|---|---|
| `RatingRequestId` | Reference → RatingRequest | Required. Master-detail. |
| `BatchJobId` | Reference → BatchJob | The batch job that triggered the rating request on the aggregated records |
| `ErrorCode` | Picklist | `BadRequest` \| `InternalError` — defines the batch job failure type |
| `ErrorMessage` | String | Describes the cause of the batch job failure |
| `Name` | String | |

**Correction (v68):** There is no `Status`, `StartTime`, `EndTime`, or `RecordsProcessed` field on
`RatingRequestBatchJob` — job-level progress lives on the referenced `BatchJob` record; this junction
object's own fields are limited to `BatchJobId`, `ErrorCode`, and `ErrorMessage`. Source: Ch.6 ›
RatingRequestBatchJob (printed pp.940–942).

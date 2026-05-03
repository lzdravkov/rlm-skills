# Rate Management — Object Reference

All objects require Rate Management permission set license.

---

## RateCard

Top-level container for rate data.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `CurrencyIsoCode` | String | ISO currency code |
| `EffectiveStartDate` | Date | When the rate card becomes effective |
| `EffectiveEndDate` | Date | When the rate card expires |
| `Description` | String | |
| `IsActive` | Boolean | |

---

## RateCardEntry

Individual rate entry within a RateCard.

| Field | Type | Description |
|---|---|---|
| `RateCardId` | Reference → RateCard | Required |
| `UnitPrice` | Currency | Price per unit |
| `StartQuantity` | Decimal | Tier start quantity |
| `EndQuantity` | Decimal | Tier end quantity |
| `RateUnit` | String | Unit label (e.g., "GB", "Hour") |
| `CurrencyIsoCode` | String | |

---

## PriceBookRateCard

Links a RateCard to a Pricebook2.

| Field | Type | Description |
|---|---|---|
| `RateCardId` | Reference → RateCard | Required |
| `Pricebook2Id` | Reference → Pricebook2 | Required |
| `IsActive` | Boolean | Must be `true` for rating to use this link |

---

## RateAdjustmentByAttribute

Applies a rate adjustment when an attribute matches a specific value.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `RateCardId` | Reference → RateCard | Required |
| `IsActive` | Boolean | |

---

## AttributeAdjustmentCondition

Defines the attribute + value condition for a RateAdjustmentByAttribute.

| Field | Type | Description |
|---|---|---|
| `RateAdjustmentByAttributeId` | Reference → RateAdjustmentByAttribute | Required |
| `AttributeDefinitionId` | Reference → AttributeDefinition | Required |
| `AttributeValue` | String | Required — the value that triggers this condition |

---

## AttributeBasedAdjustment

Defines the adjustment amount/type for a RateAdjustmentByAttribute.

| Field | Type | Description |
|---|---|---|
| `RateAdjustmentByAttributeId` | Reference → RateAdjustmentByAttribute | Required |
| `AdjustmentType` | Picklist | `Amount` \| `Override` \| `Percentage` |
| `AdjustmentValue` | Decimal | The amount; negative for discounts (percentage: -15 = 15% off) |

---

## RateAdjustmentByTier

Step-function rate adjustment based on quantity ranges.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `RateCardId` | Reference → RateCard | Required |
| `IsActive` | Boolean | |

---

## BindingObjectRateCardEntry

Binds a transaction line item to a RateCardEntry during rating.

| Field | Type | Description |
|---|---|---|
| `RateCardEntryId` | Reference → RateCardEntry | Required |
| `ReferenceObjectId` | String | ID of the bound transaction line item |
| `Quantity` | Decimal | Quantity used in rating calculation |

---

## BindingObjectRateAdjustment

Binds a transaction line item to a rate adjustment.

| Field | Type | Description |
|---|---|---|
| `RateAdjustmentId` | String | ID of the rate adjustment record |
| `ReferenceObjectId` | String | ID of the bound transaction line item |

---

## BindingObjectCustomExt

Stores custom extension data for a bound object.

| Field | Type | Description |
|---|---|---|
| `BindingObjectId` | String | Reference to the binding object |
| `ExtensionData` | LongTextArea | Custom JSON extension data |

---

## RatingFrequencyPolicy

Defines the cadence for rating calculations.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `Frequency` | Picklist | `Daily` \| `Weekly` \| `Monthly` \| `Quarterly` \| `Annually` |
| `FrequencyStartDay` | Integer | Day of month/week to start (for Monthly: 1–28) |

---

## RatingRequest

Triggers a rating calculation for a time period.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `RatingFrequencyPolicyId` | Reference → RatingFrequencyPolicy | Required |
| `EffectiveStartDate` | Date | Start of the rating period |
| `EffectiveEndDate` | Date | End of the rating period |
| `Status` | Picklist | `Pending` \| `InProgress` \| `Completed` \| `Failed` |

---

## RatingRequestBatchJob

Processes rating requests in bulk.

| Field | Type | Description |
|---|---|---|
| `RatingRequestId` | Reference → RatingRequest | Required |
| `Status` | Picklist | `Pending` \| `Processing` \| `Completed` \| `Failed` |
| `StartTime` | DateTime | When the batch job started |
| `EndTime` | DateTime | When the batch job completed |
| `RecordsProcessed` | Integer | Number of records processed |
| `ErrorMessage` | LongTextArea | Error details if failed |

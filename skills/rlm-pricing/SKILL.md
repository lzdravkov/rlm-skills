---
name: rlm-pricing
description: Configure and debug Salesforce Revenue Cloud pricing including price books, price adjustment schedules, attribute-based adjustments, bundle discounts, pricing recipes, rate cards, and headless pricing invocable actions (RLM v68). Use when setting up PriceBookEntry, PriceAdjustmentSchedule, AttributeBasedAdjRule, PricingRecipe, or running pricing waterfalls. Do NOT use for saving product attribute configurations (use rlm-product-configurator) or creating quotes (use rlm-transaction-management). Triggers on: "pricing", "price waterfall", "price book", "price adjustment", "discount", "rate card", "pricing recipe", "procedure plan", "headless pricing", "invoke rating service", "get pricing", "prorate".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Salesforce Pricing

## Instructions

### Step 1: Identify the pricing task
- **Setup / configuration**: PriceBook2, PriceBookEntry, PriceAdjustmentSchedule, AttributeBasedAdjRule, PricingRecipe
- **Runtime pricing**: Salesforce Pricing Business API or `Run Salesforce Headless Pricing Action` invocable
- **Rate-based pricing**: RateCard, RateCardEntry, RatingFrequencyPolicy, `Invoke Rating Service Action`
- **Reporting / debugging**: PricingAPIExecution, PricingProcessExecution logs

### Step 2: Deployment sequence for pricing objects
Deploy in this order (foreign key dependencies):

1. `ProductSellingModel`
2. `ProductSellingModelOption` (→ ProductSellingModel, Product2)
3. `Pricebook2`
4. `CostBook`
5. `PriceBookEntry` (→ Pricebook2, Product2, ProductSellingModel)
6. `CostBookEntry` (→ CostBook, Product2)
7. `PriceAdjustmentSchedule` (→ Pricebook2)
8. `PriceAdjustmentTier` (→ PriceAdjustmentSchedule, ProductSellingModel, Product2)
9. `PriceBookEntryDerivedPrice`
10. `BundleBasedAdjustment` (→ PriceAdjustmentSchedule, Product2, ProductSellingModel)
11. `AttributeBasedAdjRule`
12. `AttributeAdjustmentCondition` (→ AttributeBasedAdjRule, AttributeDefinition)
13. `AttributeBasedAdjustment` (→ PriceAdjustmentSchedule, ProductSellingModel, AttributeBasedAdjRule)
50. `PricingRecipe` (metadata — requires ExpressionSetDefinition)
90. `ProductPriceRange`

**CRITICAL**: `AttributeBasedAdjRule` (seq 11) must exist before `AttributeAdjustmentCondition` (seq 12). Decision Tables must be deployed before `PricingRecipe`.

### Step 3: Run headless pricing via invocable action
Use the `Run Salesforce Headless Pricing Action` invocable (actionName `runSalesforceHeadlessPricing`,
URI `/services/data/v68.0/actions/standard/runSalesforceHeadlessPricing`) in a Flow when you need
pricing outside a full quote save — it creates and hydrates a context instance and returns the
priced result in a single call:

Input fields (v68):
- `contextDefinitionId` (required), `contextMappingId` (required) — the context definition/mapping used to build the pricing context
- `pricingProcedureId` (required) — the pricing procedure to run
- `pricingData` (required) — JSON string of the records/line items to price
- `effectiveDate`, `isHighVolumeLineItems`, `isSkipWaterfall`, `persistContext`, `useSessionScopedContext`, `taggedData`, `discoveryProcedure`, `skipDiscovery` — optional tuning parameters

Output fields (v68): `contextDetails`, `executionId`, `pricingProcessErrors`, `pricingProcessStatus`, `pricingResult`

**v68 correction:** The pre-v68 version of this step documented `pricingContext`/`pricingFlow`/
`lineItems` as inputs and a single `pricingResult` output — those field names don't match the
documented invocable-action schema above. Source: RLM Developer Guide v68.0, Ch.5 Salesforce
Pricing › Standard Invocable Actions › Run Salesforce Headless Pricing Action (printed pp.854–859).

For pricing a record that already has a context instance (e.g., a Quote already associated with a
`PricingRecipe`), use `Run Salesforce Pricing Action` instead (actionName `runSalesforcePricing`,
URI `/services/data/v68.0/actions/standard/runSalesforcePricing`) — a lighter-weight action that
takes `contextInstanceId` (required) and `pricingProcedureName` (required) and returns just an
`executionId`. This action was not covered in the pre-v68 skill; added here as v68 in-domain
coverage. Source: Ch.5 › Standard Invocable Actions › Run Salesforce Pricing Action (printed
pp.861–863).

### Step 4: Invoke rating service for usage-based pricing
For subscription/usage products, use the `Invoke Rating Service Action` invocable
(actionName `invokeRatingService`, URI `/services/data/v68.0/actions/standard/invokeRatingService`)
in a Flow. Its inputs are `contextDefinitionId` (required), `recordId` (required),
`procedureName`, `contextMappingID`, `baseRateCardID`, `attributeRateCardID`, `tierRateCardID`, and
`isSkipWaterfall`; it has no documented output variables.

**v68 correction:** The `RevSignaling` Apex namespace does **not** contain a `RatingRequest` class
or a `RatingService.invokeRatingService()` method — that Apex pattern from the pre-v68 version of
this skill does not exist in the v68 Dev Guide. `RevSignaling` (Ch.5 Salesforce Pricing › Apex
Reference, printed pp.848–853) is scoped to **pricing procedure orchestration hooks** —
`SignalingApexProcessor` (an interface you implement to intercept/extend a pricing procedure's
execution, via `execute(TransactionRequest): TransactionResponse`), plus its supporting classes
`ProcedurePlan`, `TransactionRequest`, `TransactionResponse`, and the `TransactionStatus` enum. It
is enabled per-org via the "Procedure Plan Orchestration for Pricing" toggle and has no rating
API surface. There is no documented Apex entry point to invoke the rating service directly —
use the Flow invocable action above, or the Rate Management Business API
(`GET /connect/core-rating/rate-plan`, see `references/pricing-api-reference.md`).

### Step 5: Attribute-based pricing pattern
To apply different prices based on product attribute values (e.g., kW rating changes price):

1. Create `AttributeBasedAdjRule` with rule logic
2. Create `AttributeAdjustmentCondition` records for each attribute + value combination (set `UsageType = 'Pricing'`)
3. Create `AttributeBasedAdjustment` linking to `PriceAdjustmentSchedule`
4. Associate the schedule to the product's `Pricebook2` via `PriceAdjustmentSchedule.Pricebook2Id`

At runtime, PST evaluates conditions and applies the matching adjustment tier.

**v68 correction:** `PriceAdjustmentSchedule` links to `Pricebook2` directly via its own
`Pricebook2Id` field — there is no `PriceAdjustmentScheduleId` lookup field on `PriceBookEntry` to
associate the schedule "to the product's PriceBookEntry." The attribute-based adjustment chain
(`AttributeBasedAdjustment.PriceAdjustmentScheduleId` / `.ProductId` / `.ProductSellingModelId`)
resolves the applicable product without going through `PriceBookEntry`. `AttributeAdjustmentCondition`
also carries a `UsageType` picklist (`Pricing`|`Rating`) since it's shared with the Rate Management
object model (`rlm-rate-management`) — use `Pricing` here. Source: Ch.5 Salesforce Pricing ›
Standard Objects › PriceAdjustmentSchedule (printed pp.694–697), AttributeAdjustmentCondition
(pp.666–669).

### Step 6: Pricing Recipe and Procedure Plans
`PricingRecipe` is a metadata type backed by an `ExpressionSetDefinition`. It defines the sequence of pricing steps.

`ProcedurePlanDefinition` → `ProcedurePlanSection` → `ProcedurePlanOption` defines evaluation branching. Enable via `RevenueManagementSettings.enableRevUnifiedSetup = true`.

### Step 7: RevenueManagementSettings for pricing features
Key settings to enable (deploy via `revenuemanagement.settings`), all confirmed in the v68
`RevenueManagementSettings` metadata type (Ch.2 Revenue Management Settings, printed pp.4–9):
- `enableDeltaPricing` = true — reprices only changed items (faster). Available in API 63.0+
- `enableRevUnifiedSetup` = true — enables usage of a procedure plan for price calculation
- `enableRampDeal` = true — enables ramp segments. Available in API 62.0+
- `enableGroupRampPref` = true — enables group ramp segments across products. Available in API 65.0+
- `skipOrgSttPricing` = true — skip the default pricing procedure/procedure set for a sales transaction; requires `enableRevUnifiedSetup = true` first

## Common Issues

### Price not updating after attribute change
Cause: PST called `runConfigRules` only — does not trigger pricing.
Solution: Full `PlaceSalesTransactionExecutor.execute()` call triggers both config rules and pricing in one transaction.

### Number attribute overridden by Picklist attribute in single PST call
Cause: BOM-restructuring Picklist attribute conflicts with Number attribute in same atomic call.
Solution: Two-step PST sequencing — call `executePst(numberSelections)` first, then `executePst(picklistSelections)`. See `references/pst-two-step-pattern.md` for a reusable implementation template.

### PricingAPIExecution shows "internalSuccess: true" but price unchanged
Cause: Pricing procedure matched no active rules, or `PriceBookEntry.IsActive = false`.
Solution: Check `PricingProcessExecution` child records for step-level results. Verify PriceBookEntry has `IsActive = true` and correct `ProductSellingModelId`.

### Error: "ExpressionSet not found" when running PricingRecipe
Cause: ExpressionSetDefinition metadata not deployed before PricingRecipe.
Solution: Deploy ExpressionSetDefinition first; then PricingRecipe references it by name.

## Examples

### Example 1: Get the pricing waterfall for a quote line item
User says: "Show me the pricing for quote line item X"

1. Query `PricingAPIExecution` WHERE `QuoteLineItemId = :qliId` ORDER BY `CreatedDate DESC` LIMIT 1
2. Query `PricingProcessExecution` WHERE `PricingAPIExecutionId = :paeId` for step-level detail
3. Report: base price, each adjustment step name + amount, final net price

### Example 2: Apply a 10% volume discount for quantities > 100
1. Create `PriceAdjustmentSchedule` (`ScheduleType = 'Volume'`, linked to `Pricebook2Id`)
2. Create `PriceAdjustmentTier` with `LowerBound = 100`, `TierType = 'AdjustmentPercentage'`, `TierValue = 10`
3. Link `PriceAdjustmentSchedule.Pricebook2Id` to the target `Pricebook2`

**v68 correction:** `PriceAdjustmentTier`'s tier-unit/value fields are `TierType`
(`AdjustmentAmount`|`AdjustmentPercentage`|`OverrideAmount`) and `TierValue` — there is no
`AdjustmentType = 'PercentageDiscount'`/`AdjustmentValue` combination on this object, and no
`PriceAdjustmentScheduleId` field on `PriceBookEntry` (see Step 5 correction above). Source: Ch.5 ›
PriceAdjustmentTier (printed pp.698–701).

### Example 3: Configure attribute-based pricing for kW rating
1. `AttributeBasedAdjRule` — Name: "kW Pricing Rule"
2. `AttributeAdjustmentCondition` — `AttributeDefinitionId`: requiredKW, `Operator = 'greaterorequal'`, `DoubleValue = 1000`, `UsageType = 'Pricing'`
3. `AttributeBasedAdjustment` — `AdjustmentType = 'Override'`, `AdjustmentValue = 45000`
4. Link via `AttributeBasedAdjustment.PriceAdjustmentScheduleId` to the schedule on the product's `Pricebook2`

**v68 correction:** `Operator` is a lowercase, no-space picklist (`greaterorequal`, not
"GreaterThanOrEqual"); valid values are `doesnotexistin`/`equals`/`existsin`/`greaterorequal`/
`greaterthan`/`lessorequal`/`lessthan`/`matches`/`notequals`. `AdjustmentType` has no `FixedPrice`
value — use `Override` to replace the price outright. Source: Ch.5 › AttributeAdjustmentCondition
(printed pp.666–669), AttributeBasedAdjustment (pp.671–675).

## See Also

| Skill | Why |
|---|---|
| `rlm-product-configurator` | PST (`PlaceSalesTransactionExecutor`) triggers pricing at the same time it applies BOM rules; attribute changes reprice the line item |
| `rlm-rate-management` | Rate cards are an alternative/complementary pricing path for usage-based and tiered products — both skills contribute to the pricing waterfall |
| `rlm-transaction-management` | Quotes and orders are the transactions pricing runs against; headless pricing operates on `QuoteLineItem` records |
| `rlm-billing` | Tax engine is configured under billing but is evaluated during invoice posting, which depends on pricing data |
| `rlm-deployment` | `PriceBookEntry`, `PriceAdjustmentSchedule`, and `PricingRecipe` have specific deployment order requirements |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 2.0.0 | 2026-09-11 | v68.0 (Winter '27) re-baseline. Corrected `Run Salesforce Headless Pricing Action` and `Invoke Rating Service Action` input/output field names to match the v68 Dev Guide; added coverage for `Run Salesforce Pricing Action` (previously undocumented); removed the fabricated `RevSignaling.RatingRequest`/`RevSignaling.RatingService.invokeRatingService()` Apex pattern and clarified `RevSignaling`'s real scope (pricing procedure orchestration hooks via `SignalingApexProcessor`); corrected `PriceAdjustmentSchedule`/`PriceAdjustmentTier`/`AttributeAdjustmentCondition`/`AttributeBasedAdjustment` field names and enum casing in Step 5 and Examples 2–3; added `enableGroupRampPref` to Step 7; replaced page-number citations with section-title citations; bumped compatibility to API v68.0+ |
| 1.1.0 | 2026-05-02 | Added See Also table; expanded pricing-api-reference.md with full request/response bodies and error codes |
| 1.0.0 | 2026-04-01 | Initial skill — price books, adjustment schedules, attribute-based pricing, headless pricing, rating service |

---

## References
- See `references/pricing-api-reference.md` for REST API endpoints and request/response schemas
- RLM Developer Guide v68.0 (Winter '27), Chapter 5: Salesforce Pricing — Standard Objects, Business APIs, Apex Reference (RevSignaling), Standard Invocable Actions, Metadata API (printed pp.663–906)
- RLM Developer Guide v68.0, Chapter 6: Rate Management — Standard Objects, Business APIs, Standard Invocable Actions (printed pp.907–954)
- See `references/pst-two-step-pattern.md` for the two-step PST sequencing implementation

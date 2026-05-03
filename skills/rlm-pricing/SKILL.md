---
name: rlm-pricing
description: Configure and debug Salesforce Revenue Cloud pricing including price books, price adjustment schedules, attribute-based adjustments, bundle discounts, pricing recipes, rate cards, and headless pricing invocable actions (RLM v66). Use when setting up PriceBookEntry, PriceAdjustmentSchedule, AttributeBasedAdjRule, PricingRecipe, or running pricing waterfalls. Do NOT use for saving product attribute configurations (use rlm-product-configurator) or creating quotes (use rlm-transaction-management). Triggers on: "pricing", "price waterfall", "price book", "price adjustment", "discount", "rate card", "pricing recipe", "procedure plan", "headless pricing", "invoke rating service", "get pricing", "prorate".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
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
Use the `Run Salesforce Headless Pricing Action` invocable in a Flow when you need pricing outside a full quote save:

Input fields:
- `pricingContext` — JSON with `quoteId` or `orderId`
- `pricingFlow` — the pricing recipe/procedure plan name
- `lineItems` — list of line item records to price

Output: `pricingResult` with updated `UnitPrice`, `TotalPrice`, `Adjustments[]`

### Step 4: Invoke rating service for usage-based pricing
For subscription/usage products, use the `Invoke Rating Service Action` invocable or `RevSignaling` Apex namespace:

```apex
// Apex — invoke rating waterfall
RevSignaling.RatingRequest req = new RevSignaling.RatingRequest();
req.quoteLineItemId = qliId;
// ... populate fields
RevSignaling.RatingService.invokeRatingService(new List<RevSignaling.RatingRequest>{req});
```

In a Flow, use the `Invoke Rating Service` standard invocable action.

### Step 5: Attribute-based pricing pattern
To apply different prices based on product attribute values (e.g., kW rating changes price):

1. Create `AttributeBasedAdjRule` with rule logic
2. Create `AttributeAdjustmentCondition` records for each attribute + value combination
3. Create `AttributeBasedAdjustment` linking to `PriceAdjustmentSchedule`
4. Associate the schedule to the product's `PriceBookEntry`

At runtime, PST evaluates conditions and applies the matching adjustment tier.

### Step 6: Pricing Recipe and Procedure Plans
`PricingRecipe` is a metadata type backed by an `ExpressionSetDefinition`. It defines the sequence of pricing steps.

`ProcedurePlanDefinition` → `ProcedurePlanSection` → `ProcedurePlanOption` defines evaluation branching. Enable via `RevenueManagementSettings.enableRevUnifiedSetup = true`.

### Step 7: RevenueManagementSettings for pricing features
Key settings to enable (deploy via `revenuemanagement.settings`):
- `enableDeltaPricing` = true — reprices only changed items (faster)
- `enableRevUnifiedSetup` = true — enables procedure plan pricing
- `enableRampDeal` = true — enables ramp segments
- `skipOrgSttPricing` = true — skip default pricing procedure for custom pricing

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
1. Create `PriceAdjustmentSchedule` (linked to Pricebook2)
2. Create `PriceAdjustmentTier` with `LowerBound = 100`, `AdjustmentType = PercentageDiscount`, `AdjustmentValue = 10`
3. Link schedule to `PriceBookEntry.PriceAdjustmentScheduleId`

### Example 3: Configure attribute-based pricing for kW rating
1. `AttributeBasedAdjRule` — Name: "kW Pricing Rule", AttributeDefinition: requiredKW
2. `AttributeAdjustmentCondition` — Operator: GreaterThanOrEqual, Value: 1000
3. `AttributeBasedAdjustment` — AdjustmentType: FixedPrice, AdjustmentValue: 45000
4. Link to `PriceAdjustmentSchedule` on the product's pricebook entry

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
| 1.1.0 | 2026-05-02 | Added See Also table; expanded pricing-api-reference.md with full request/response bodies and error codes |
| 1.0.0 | 2026-04-01 | Initial skill — price books, adjustment schedules, attribute-based pricing, headless pricing, rating service |

---

## References
- See `references/pricing-api-reference.md` for REST API endpoints and request/response schemas
- RLM Developer Guide Chapter 5: Salesforce Pricing (p. 586)
- RLM Developer Guide Chapter 6: Rate Management (p. 826)
- See `references/pst-two-step-pattern.md` for the two-step PST sequencing implementation

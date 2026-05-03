# Salesforce Pricing — REST API Reference

Base URL: `https://{instance}.salesforce.com/services/data/v66.0`

---

## Headless Pricing — Business API

### Price a quote or order
```
POST /commerce/pricing/actions/price
Body:
{
  "pricingFlow": "DefaultPricingProcedure",
  "recordId": "0Q0...",
  "recordType": "Quote",
  "lineItems": [
    {
      "lineItemId": "0QL...",
      "productId": "01t...",
      "quantity": 1,
      "sellingModelId": "0PG..."
    }
  ]
}
```
Response:
```json
{
  "pricingResults": [
    {
      "lineItemId": "0QL...",
      "unitPrice": 45000.00,
      "totalPrice": 45000.00,
      "adjustments": [
        { "adjustmentType": "AttributeAdjustment", "adjustmentAmount": -5000.00, "adjustmentName": "kW Rule" }
      ]
    }
  ]
}
```

### Run Salesforce Headless Pricing (Invocable Action — Flow)
Action API Name: `RunSalesforceHeadlessPricingAction`

Input variables:
- `pricingContext` (Text) — JSON: `{"quoteId": "0Q0..."}`
- `pricingFlow` (Text) — name of pricing recipe/procedure plan
- `lineItemIds` (Text Collection) — QuoteLineItem IDs to price

Output variables:
- `pricingResults` (Text) — JSON array of pricing results per line item

---

## Headless Pricing — Full Request/Response Reference

### Request body — all supported fields

```json
POST /commerce/pricing/actions/price
{
  "pricingFlow": "DefaultPricingProcedure",
  "recordId": "0Q0...",
  "recordType": "Quote",
  "priceBookId": "01s...",
  "currencyCode": "USD",
  "lineItems": [
    {
      "lineItemId": "0QL...",
      "productId": "01t...",
      "quantity": 10,
      "sellingModelId": "0PG...",
      "attributes": [
        { "name": "requiredKW", "value": "1500", "dataType": "Number" }
      ],
      "startDate": "2026-01-01",
      "endDate": "2026-12-31"
    }
  ]
}
```

| Field | Required | Description |
|---|---|---|
| `pricingFlow` | Required | Name of the `PricingRecipe` or procedure plan |
| `recordId` | Required | Quote or Order ID |
| `recordType` | Required | `Quote` or `Order` |
| `priceBookId` | Optional | Defaults to the record's current pricebook |
| `currencyCode` | Optional | ISO currency; defaults to record currency |
| `lineItems[].lineItemId` | Required | `QuoteLineItem` or `OrderItem` ID |
| `lineItems[].quantity` | Required | Quantity to price |
| `lineItems[].attributes` | Optional | Attribute values to use during pricing evaluation |
| `lineItems[].startDate` / `endDate` | Optional | Term dates for proration calculation |

### Full response body

```json
{
  "pricingResults": [
    {
      "lineItemId": "0QL...",
      "unitPrice": 45000.00,
      "totalPrice": 450000.00,
      "listPrice": 50000.00,
      "adjustments": [
        {
          "adjustmentType": "AttributeAdjustment",
          "adjustmentName": "kW Pricing Rule",
          "adjustmentAmount": -5000.00,
          "adjustmentPercentage": -10.0,
          "sequence": 1
        },
        {
          "adjustmentType": "VolumeDiscount",
          "adjustmentName": "Qty 10+ Tier",
          "adjustmentAmount": 0.00,
          "adjustmentPercentage": -5.0,
          "sequence": 2
        }
      ],
      "priceWaterfallSteps": [
        { "stepName": "ListPrice",          "price": 50000.00 },
        { "stepName": "AttributeAdjustment","price": 45000.00 },
        { "stepName": "VolumeDiscount",     "price": 42750.00 }
      ]
    }
  ],
  "errors": []
}
```

### Error response (pricing rule not found)

```json
{
  "pricingResults": [],
  "errors": [
    {
      "errorCode": "PRICING_RULE_NOT_FOUND",
      "message": "No active PriceBookEntry found for product 01t... in pricebook 01s...",
      "lineItemId": "0QL..."
    }
  ]
}
```

Common error codes:
| Code | Cause |
|---|---|
| `PRICING_RULE_NOT_FOUND` | No active `PriceBookEntry` for the product/pricebook combination |
| `EXPRESSION_SET_NOT_FOUND` | `PricingRecipe` references an `ExpressionSetDefinition` that is not deployed |
| `INVALID_PRICING_FLOW` | `pricingFlow` name does not match an active `PricingRecipe` |
| `PROCEDURE_PLAN_DISABLED` | `enableRevUnifiedSetup` not set to `true` in `RevenueManagementSettings` |

---

## Rating Service — Business API

### Get rate plan for a product

```
GET /commerce/rates/products/{productId}/ratePlans
```

Response:
```json
{
  "ratePlans": [
    {
      "ratePlanId": "0RCxx...",
      "rateCardId": "0RDxx...",
      "rateCardName": "Data Usage Rate Card 2026",
      "entries": [
        {
          "rateCardEntryId": "0RExx...",
          "startQuantity": 0,
          "endQuantity": 1000,
          "unitPrice": 0.05,
          "rateUnit": "GB"
        },
        {
          "rateCardEntryId": "0RExx...",
          "startQuantity": 1001,
          "endQuantity": null,
          "unitPrice": 0.04,
          "rateUnit": "GB"
        }
      ],
      "adjustments": [
        {
          "adjustmentType": "Percentage",
          "adjustmentValue": -15,
          "condition": "AccountTier = Enterprise"
        }
      ]
    }
  ]
}
```

### Invoke rating waterfall (Invocable Action — Flow)
Action API Name: `InvokeRatingServiceAction`

Input variables:
- `quoteLineItemIds` (Text Collection)
- `ratingDate` (Date)
- `quantity` (Number)

Output variables:
- `ratingResults` (Text) — JSON with rated amounts per line item

### Apex: Invoke rating service directly
```apex
RevSignaling.RatingRequest req = new RevSignaling.RatingRequest();
req.quoteLineItemId = '0QL...';
req.ratingDate = Date.today();
req.quantity = 1;
RevSignaling.RatingService.invokeRatingService(
    new List<RevSignaling.RatingRequest>{ req }
);
```

---

## Pricing Execution Logs — SOQL Queries

### Get latest pricing execution for a quote line item
```soql
SELECT Id, Status, StartTime, EndTime, TotalAdjustmentAmount
FROM PricingAPIExecution
WHERE QuoteLineItemId = '0QL...'
ORDER BY CreatedDate DESC
LIMIT 1
```

### Get step-level detail for a pricing execution
```soql
SELECT Id, StepName, StepType, InputPrice, OutputPrice, AdjustmentAmount
FROM PricingProcessExecution
WHERE PricingAPIExecutionId = '...'
ORDER BY Sequence ASC
```

---

## RevenueManagementSettings — Pricing-Related Flags

Deploy via `force-app/main/default/settings/revenuemanagement.settings`:

| Field | Type | Effect |
|---|---|---|
| `enableDeltaPricing` | boolean | Reprices only changed items — faster for large quotes |
| `enableRevUnifiedSetup` | boolean | Enables ProcedurePlan-based pricing |
| `enableRampDeal` | boolean | Enables ramp deal segments per line item |
| `enableGroupRampPref` | boolean | Enables group ramp segments across products |
| `skipOrgSttPricing` | boolean | Skips default pricing procedure for custom pricing |

---

## Pricing Objects — Key Relationships

```
Pricebook2
  └── PriceBookEntry (→ Product2, ProductSellingModel)
        └── PriceAdjustmentSchedule (→ Pricebook2)
              └── PriceAdjustmentTier (→ ProductSellingModel, Product2)
                    └── BundleBasedAdjustment
AttributeBasedAdjRule
  └── AttributeAdjustmentCondition (→ AttributeDefinition, Product2)
        └── AttributeBasedAdjustment (→ PriceAdjustmentSchedule)
PricingRecipe (metadata, → ExpressionSetDefinition)
  └── ProcedurePlanDefinition
        └── ProcedurePlanSection → ProcedurePlanOption → ProcedurePlanCriterion
```

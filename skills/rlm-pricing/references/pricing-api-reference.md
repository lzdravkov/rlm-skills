# Salesforce Pricing — REST API Reference

Base URL: `https://{instance}.salesforce.com/services/data/v68.0`

> **v68 verification note (2026-09-11):** This file previously documented a `/commerce/pricing/...`
> and `/commerce/rates/...` endpoint family. Those paths do not exist in the RLM Developer Guide.
> The real Salesforce Pricing and Rate Management Business API base paths are `/connect/core-pricing/...`
> and `/connect/core-rating/...`, confirmed against Ch.5 Salesforce Pricing › Business APIs (printed
> pp.748–767) and Ch.6 Rate Management › Business APIs (printed pp.945–946). Request/response shapes
> and the two pricing invocable actions' input/output field names have also been corrected below —
> see the inline "v68 correction" notes for citations.

---

## Headless Pricing — Business API

### Price a record (create + hydrate a context instance and price in one call)
```
POST /connect/core-pricing/pricing
Body:
{
  "contextDefinitionId": "context def developer name or ID",
  "contextMappingId": "context mapping developer name or ID",
  "pricingProcedureId": "pricing procedure developer name or ID",
  "jsonDataString": "{...serialized records/line items to price...}",
  "configurationOverrides": {
    "skipWaterfall": false,
    "useSessionScopedContext": false,
    "persistContext": true,
    "referenceKey": "optional caller-supplied correlation key",
    "displayContext": "optional UI display context",
    "taggedData": "optional tagged passthrough data",
    "isHighVolumeLineItems": false
  }
}
```

**v68 correction:** The pre-v68 version of this doc used `POST /commerce/pricing/actions/price`
with a `pricingFlow`/`recordId`/`recordType`/`lineItems[]` body — that resource and body shape do
not exist. The real endpoint is `POST /connect/core-pricing/pricing`, and its request body is keyed
on `contextDefinitionId`/`contextMappingId`/`pricingProcedureId`/`jsonDataString` plus a
`configurationOverrides` object, matching the fields also exposed on the
`Run Salesforce Headless Pricing Action` invocable (below). Source: Ch.5 Salesforce Pricing ›
Business APIs (printed pp.748–751).

Other confirmed `/connect/core-pricing/...` resources (Ch.5, printed pp.748–767):
| Resource | Method | Purpose |
|---|---|---|
| `/connect/core-pricing/pricing` | POST | Create + hydrate a context instance and price in one call |
| `/connect/core-pricing/price-contexts/{contextid}` | POST | Run a pricing request against an existing context instance ID |
| `/connect/core-pricing/sync/{pricingSyncOrigin}` | GET | Sync status/details for a pricing origin |
| `/connect/core-pricing/recipe` | GET | Retrieve a `PricingRecipe` definition |
| `/connect/core-pricing/revenue/pricing-recipe/valid-elements` | GET | Valid elements for a pricing recipe |
| `/connect/core-pricing/revenue/pricing-recipe/clone` | POST | Clone a `PricingRecipe` |
| `/connect/core-pricing/recipe/mapping` | POST | Create/update a recipe's context mapping |
| `/connect/core-pricing/versioned-revise-details` | POST | Revise-quote/version pricing details |
| `/connect/core-pricing/waterfall` | POST | Generate a pricing waterfall |
| `/connect/core-pricing/waterfall/{lineItemId}/{executionId}` | GET | Retrieve a generated waterfall for a line item + execution |
| `/connect/core-pricing/pbeDerivedPricingSourceProduct` | POST | Resolve a `PriceBookEntryDerivedPrice` source product |
| `/connect/core-pricing/apiexecutionlogs/{executionId}` | GET | Execution log detail for a pricing API call |
| `/connect/core-pricing/pricing-process-execution/{executionId}` | GET | `PricingProcessExecution` detail for an execution |
| `/connect/core-pricing/pricing-process-execution/lineitems/{executionId}/{executionType}` | GET | Line-item-level execution detail |
| `/connect/core-pricing/simulationInputVariablesWithData` | GET | Simulation input variables with sample data |

### Run Salesforce Headless Pricing (Invocable Action — Flow)
Action API Name (actionName): `runSalesforceHeadlessPricing`
URI: `/services/data/v68.0/actions/standard/runSalesforceHeadlessPricing`

Input variables (v68):
- `contextDefinitionId` (Text, **required**)
- `contextMappingId` (Text, **required**)
- `pricingProcedureId` (Text, **required**)
- `pricingData` (Text, **required**) — JSON string of the records/line items to price
- `effectiveDate` (Date, optional)
- `isHighVolumeLineItems` (Boolean, optional)
- `isSkipWaterfall` (Boolean, optional)
- `persistContext` (Boolean, optional)
- `useSessionScopedContext` (Boolean, optional)
- `taggedData` (Text, optional)
- `discoveryProcedure` / `skipDiscovery` (optional) — control automatic procedure discovery

Output variables (v68):
- `contextDetails` (Text)
- `executionId` (Text)
- `pricingProcessErrors` (Text)
- `pricingProcessStatus` (Text)
- `pricingResult` (Text) — JSON pricing result

**v68 correction:** The pre-v68 version of this doc listed `pricingContext`/`pricingFlow`/
`lineItemIds` as inputs and `pricingResults` as the only output. Those names do not match the
documented invocable-action schema. Source: Ch.5 › Standard Invocable Actions › Run Salesforce
Headless Pricing Action (printed pp.855–859).

### Run Salesforce Pricing (Invocable Action — Flow)
**New in this reference (v68 gap-fill; the action itself has existed since API 60.0 but was not
previously documented in this skill).**

Action API Name (actionName): `runSalesforcePricing`
URI: `/services/data/v68.0/actions/standard/runSalesforcePricing`

Use this action instead of `runSalesforceHeadlessPricing` when a context instance already exists
(e.g., the record was hydrated by a prior call) — it's a lighter-weight re-price call.

Input variables (v68):
- `contextInstanceId` (Text, **required**)
- `pricingProcedureName` (Text, **required**)
- `effectiveDate` (Date, optional)
- `isDeveloperName` (Boolean, optional)
- `isSkipWaterfall` (Boolean, optional)
- `discoveryProcedure` / `skipDiscovery` (optional)

Output variables (v68):
- `executionId` (Text)

Source: Ch.5 › Standard Invocable Actions › Run Salesforce Pricing Action (printed pp.861–863).

---

## Pricing Execution / Error Reference

Common error codes surfaced via `pricingProcessErrors` and the `apiexecutionlogs`/
`pricing-process-execution` resources above:
| Code | Cause |
|---|---|
| `PRICING_RULE_NOT_FOUND` | No active `PriceBookEntry` for the product/pricebook combination |
| `EXPRESSION_SET_NOT_FOUND` | `PricingRecipe` references an `ExpressionSetDefinition` that is not deployed |
| `INVALID_PRICING_FLOW` | `pricingProcedureId`/`pricingProcedureName` does not match an active `PricingRecipe` |
| `PROCEDURE_PLAN_DISABLED` | `enableRevUnifiedSetup` not set to `true` in `RevenueManagementSettings` |

> **Annotation:** The exact JSON shape of `pricingResult`/`pricingProcessErrors` (nested field
> names beyond the top-level keys listed above) was not fully captured from the Dev Guide's
> Business API resource pages during this pass. Treat the top-level output field names above as
> confirmed; treat any deeper nested-field claims as unverified until checked directly against
> Ch.5 printed pp.748–767 (Business APIs) or pp.855–863 (Invocable Actions response examples).

---

## Rating Service — Business API

**v68 correction:** `GET /commerce/rates/products/{productId}/ratePlans` does not exist. The
confirmed Rate Management Business API resource is `GET /connect/core-rating/rate-plan`, and the
rating waterfall reuses the Ch.5 Pricing waterfall resource with a rating-specific usage type.
Source: Ch.6 Rate Management › Business APIs (printed pp.945–946).

### Get a rate plan for a context

```
GET /connect/core-rating/rate-plan?contextId={contextId}&procedureApiName={procedureApiName}
```

Retrieves the rate plan (rate card entries + adjustments) resolved for the given rating context
and rating procedure. The exact response body's nested field names were not fully captured from
the Dev Guide's Business API resource page during this pass — treat the resource path and query
parameters above as confirmed, and the response shape as **unverified/annotated** pending a closer
read of Ch.6 printed pp.945–946.

### Rating waterfall

```
GET /connect/core-pricing/waterfall/{lineItemId}/{executionId}
POST /connect/core-pricing/waterfall
```

Rating shares the Ch.5 pricing waterfall resource (`/connect/core-pricing/waterfall...`) rather
than having its own dedicated waterfall endpoint — pass a rating-scoped `executionId` (produced by
a `RatingRequest`/`Invoke Rating Service Action` run) to retrieve the rating waterfall steps.

### Invoke Rating Service (Invocable Action — Flow)
Action API Name (actionName): `invokeRatingService`
URI: `/services/data/v68.0/actions/standard/invokeRatingService`

Input variables (v68):
- `contextDefinitionId` (Text, **required**)
- `recordId` (Text, **required**)
- `procedureName` (Text, optional)
- `contextMappingID` (Text, optional)
- `baseRateCardID` (Text, optional)
- `attributeRateCardID` (Text, optional)
- `tierRateCardID` (Text, optional)
- `isSkipWaterfall` (Boolean, optional)

Output variables: none documented.

**v68 correction:** The pre-v68 version of this doc named the action `InvokeRatingServiceAction`
with inputs `quoteLineItemIds`/`ratingDate`/`quantity` and an output `ratingResults`. The real
actionName is `invokeRatingService`, and its input/output schema is as shown above — there is no
documented output variable at all. Source: Ch.6 › Standard Invocable Actions › Invoke Rating
Service Action (printed pp.951–953).

### Apex: there is no documented direct Apex entry point to invoke rating
The pre-v68 version of this doc showed an `Apex: Invoke rating service directly` snippet using
`RevSignaling.RatingRequest`/`RevSignaling.RatingService.invokeRatingService(...)`. **Neither class
exists.** `RevSignaling` (Ch.5 Salesforce Pricing › Apex Reference, printed pp.848–853) contains
only `ProcedurePlan`, `SignalingApexProcessor` (interface), `TransactionRequest`,
`TransactionResponse`, and the `TransactionStatus` enum — all scoped to **pricing** procedure
orchestration hooks (implement `SignalingApexProcessor.execute(TransactionRequest):
TransactionResponse` to intercept a pricing procedure run), not to invoking the rating service.
To trigger rating from Apex, either:
- call the `Invoke Rating Service Action` invocable programmatically via
  `Invocable.Action.createCustomAction(...)` / the standard Flow-action Apex invocation pattern, or
- call the Business API resource above via an authenticated HTTP callout.
There is no `RevSignaling`-namespace (or other) Apex class documented for direct rating
invocation as of v68.

---

## Pricing Execution Logs — SOQL Queries

> **Annotation:** The `PricingAPIExecution`/`PricingProcessExecution` field names below were carried
> over from the pre-v68 version of this doc. During this pass I confirmed the *objects themselves*
> are real (referenced in Ch.5's Business API resource inventory as
> `/connect/core-pricing/apiexecutionlogs/{executionId}` and
> `/connect/core-pricing/pricing-process-execution/...`), but did not re-verify every individual
> field name (`Status`, `StartTime`, `EndTime`, `TotalAdjustmentAmount`, `QuoteLineItemId`,
> `StepName`, `StepType`, `InputPrice`, `OutputPrice`, `AdjustmentAmount`, `Sequence`) against the
> Ch.5 Standard Objects field listing (printed pp.747+). Treat these SOQL examples as illustrative
> rather than confirmed until checked directly against that section.

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

Deploy via `force-app/main/default/settings/revenuemanagement.settings`. All confirmed in the v68
`RevenueManagementSettings` metadata type (Ch.2 Revenue Management Settings, printed pp.4–9):

| Field | Type | Effect |
|---|---|---|
| `enableDeltaPricing` | boolean | Reprices only changed items — faster for large quotes. Available in API 63.0+ |
| `enableRevUnifiedSetup` | boolean | Enables usage of a procedure plan for price calculation |
| `enableRampDeal` | boolean | Enables ramp deal segments per line item. Available in API 62.0+ |
| `enableGroupRampPref` | boolean | Enables group ramp segments across products. Available in API 65.0+ |
| `skipOrgSttPricing` | boolean | Skips the default pricing procedure/procedure set for a sales transaction. Requires `enableRevUnifiedSetup = true` |

---

## Pricing Objects — Key Relationships

```
Pricebook2
  ├── PriceBookEntry (→ Product2, ProductSellingModel)
  └── PriceAdjustmentSchedule (→ Pricebook2, directly — NOT through PriceBookEntry)
        └── PriceAdjustmentTier (→ PriceAdjustmentSchedule, ProductSellingModel, Product2)
        └── BundleBasedAdjustment (→ PriceAdjustmentSchedule, Product2, ProductSellingModel)
AttributeBasedAdjRule
  └── AttributeAdjustmentCondition (→ AttributeBasedAdjRule, AttributeDefinition, Product2;
  │                                   UsageType: Pricing | Rating)
  └── AttributeBasedAdjustment (→ AttributeBasedAdjRule, PriceAdjustmentSchedule,
                                   ProductSellingModel; UsageType: Pricing | Rating)
PricingRecipe (metadata, → ExpressionSetDefinition)
  └── ProcedurePlanDefinition
        └── ProcedurePlanSection → ProcedurePlanOption → ProcedurePlanCriterion
```

**v68 correction:** `PriceAdjustmentSchedule` links to `Pricebook2` directly via its own
`Pricebook2Id` field — there is no FK path through `PriceBookEntry`. `AttributeAdjustmentCondition`
and `AttributeBasedAdjustment` both link back to `AttributeBasedAdjRule` (not to each other in a
strict parent/child chain) and both carry a `UsageType` picklist (`Pricing`|`Rating`) since they're
shared with the `rlm-rate-management` object model. Source: Ch.5 Salesforce Pricing › Standard
Objects — PriceAdjustmentSchedule (printed pp.694–697), AttributeAdjustmentCondition (pp.666–669),
AttributeBasedAdjustment (pp.671–675).

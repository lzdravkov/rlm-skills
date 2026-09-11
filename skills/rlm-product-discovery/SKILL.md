---
name: rlm-product-discovery
description: Search and browse product catalogs, categories, and products using the Product Discovery Business APIs (/connect/cpq/ POST endpoints), Standard Invocable Actions, and Apex Reference. Use when finding products by catalog/category hierarchy, running full-text or faceted search, executing guided selection, running qualification procedures, or fetching bulk product details with pricing. Do NOT use for writing product catalog data (use rlm-product-catalog) or configuring product attributes after selection (use rlm-product-configurator). Triggers on: "find product", "browse catalog", "product search", "catalog list", "category products", "guided selection", "qualification procedure", "bulk product details", "product discovery", "connect/cpq", "search term", "faceted search", "product eligibility".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Product Discovery

## Instructions

### Step 1: Choose the right API path

| Task | API |
|---|---|
| Browse all catalogs | `POST /connect/cpq/catalogs` |
| Get catalog details | `POST /connect/cpq/catalogs/{catalogId}` |
| List categories in a catalog | `POST /connect/cpq/categories` |
| Get category details | `POST /connect/cpq/categories/{categoryId}` |
| List products in a catalog/category | `POST /connect/cpq/products` |
| Get single product details + attributes | `POST /connect/cpq/products/{productId}` |
| Get multiple products at once | `POST /connect/cpq/products/bulk` |
| Full-text or faceted search | `POST /connect/cpq/products/search` |
| Guided selection (Q&A product matching) | `POST /connect/cpq/products/guided-selection` |
| Run qualification procedure on product IDs | `POST /connect/cpq/qualification` |
| Get product recommendations (Constraint Rule Engine) | `POST /revenue/product-discovery/products/recommendations` |

All APIs are composite POST APIs. All available from API v60.0 unless noted. The product
recommendations endpoint is a `/revenue/...` resource (not `/connect/cpq/...`) — it backs the
**Get Product Recommendations Action** standard invocable action (see
`references/product-discovery-invocable-actions.md`).

### Step 2: Request body structure

Every request body accepts:
- `correlationId` (String, optional) — UUID for tracing requests across system boundaries
- `userContext` (Object, optional) — `{ "accountId": "...", "contactId": "..." }` for account-specific pricing/qualification

Most product-returning endpoints also accept:
- `enablePricing` (Boolean, default `true`) — return price data; overridden by Setup toggle
- `enableQualification` (Boolean, default `true`) — run qualification rules; overridden by Setup toggle
- `priceBookId` (String) — price book to fetch prices from (standard pricebook if omitted)
- `catalogId` / `categoryId` — scope results to a catalog or category
- `filter` — filter by `name` using operators `eq`, `in`, `contains`, `gt`, `lt`, `gte`, `lte`
- `limit` (Integer, default 10) / `cursor` (String) — pagination
- `orderBy` (String[], default `asc`) — sort e.g. `["name:asc", "id:desc"]`
- `additionalFields` — request extra Product2 or ProductAttributeDefinition fields in the response
- `usePromotions` (Boolean, API v66.0) — fetch eligible Global Promotion Management (GPM) promotions

### Step 3: Search patterns

**Text search** (full-text against indexed product names):
```json
POST /connect/cpq/products/search
{
  "query": { "textQuery": { "searchPhrase": "laptop" } },
  "catalogId": "0ZSxx...",
  "categoryId": "0ZGT...",
  "limit": 10,
  "userContext": { "accountId": "001xx..." }
}
```

**Simple name filter** (non-indexed, works without index build):
```json
POST /connect/cpq/products/search
{
  "searchTerm": "Laptop",
  "catalogId": "0ZSxx..."
}
```

**Filter by commercial products only** (uses `relatedObjectFilter`):
```json
POST /connect/cpq/products
{
  "catalogId": "0ZSxx...",
  "relatedObjectFilters": [
    {
      "objectName": "ProductSpecificationRecType",
      "criteria": [{ "property": "IsCommercial", "operator": "eq", "value": true }]
    }
  ]
}
```

### Step 4: Guided selection

Guided selection captures user requirements (search terms with tags) to match suitable products. Requires `catalogId`. Either `guidedSelectionResponseId` OR `searchTerms` must be provided.

```json
POST /connect/cpq/products/guided-selection
{
  "catalogId": "0ZSxx...",
  "priceBookId": "01sxx...",
  "guidedSelectionResponseId": "ABCxx...",
  "searchTerms": [
    { "term": "IPhone", "tags": ["deviceType", "mobile"] },
    { "term": "4GB",    "tags": ["RAM"] },
    { "term": "64GB",   "tags": ["Storage"] }
  ],
  "enableQualification": true,
  "enablePricing": true,
  "userContext": { "accountId": "accId" }
}
```

If both `guidedSelectionResponseId` and `searchTerms` are provided, `searchTerms` takes precedence.

### Step 5: Bulk product details

Use when you already have a list of product IDs and need their details + pricing in one call:

```json
POST /connect/cpq/products/bulk
{
  "productData": [
    { "productId": "01txx...", "productSellingModelId": "0jPxx..." },
    { "productId": "01txx...", "productSellingModelId": "0jPxx..." }
  ],
  "priceBookId": "01sxx...",
  "correlationId": "...",
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
```

Available from API v61.0.

### Step 6: Qualification endpoint

Run a qualification procedure on a known list of product IDs (without returning full product details):

```json
POST /connect/cpq/qualification
{
  "productIds": ["01txx...", "01txx...", "01txx..."],
  "userContext": { "accountId": "001xx..." }
}
```

Custom qualification procedure: add `"qualificationProcedure": "MyQualProc"`. Default procedure is used if omitted.

### Step 7: Additional fields pattern

Request additional Product2 or ProductAttributeDefinition fields inline:

```json
"additionalFields": {
  "Product2": {
    "fields": ["ProductCode", "CanRamp", "DecompositionScope", "CustomField1__c"]
  },
  "ProductAttributeDefinition": {
    "fields": ["field3", "field4"]
  },
  "ProductSellingModelOption": {
    "additionalFields": {
      "ProrationPolicy": {
        "fields": ["ArePartialPeriodsAllowed", "ProrationPolicyType"]
      }
    }
  }
}
```

### Step 8: Metadata API types

These control Product Catalog Management feature settings and product specification types:

**ProductCatalogManagementSettings** (API v64.0+)
- File: `settings/ProductCatalogManagementSettings.settings`
- Fields: `productDeepCloneContextDefOrgValue`, `productDeepCloneExpressionSetOrgValue`
- Deploy: `sf project deploy start --metadata "Settings:ProductCatalogManagement" --target-org <alias>`

**ProductSpecificationType** (API v60.0+)
- Suffix: `.productSpecificationType` | Folder: `productSpecificationTypes/`
- Defines industry-specific product terminology (e.g., "Offer", "Bundle", "Plan")
- Fields (required): `masterLabel`, `description`
- Deploy with wildcard: `<members>*</members><name>ProductSpecificationType</name>`

**ProductSpecificationRecType** (API v60.0+)
- Suffix: `.productSpecificationRecType` | Folder: `productSpecificationRecTypes/`
- Associates a ProductSpecificationType with a Product2 record type
- Fields (required): `masterLabel`, `productSpecificationType`, `recordType`, `isCommercial` (boolean, default `true`)
- Both types require Product Catalog Management to be enabled

```xml
<ProductSpecificationRecType xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>sample</masterLabel>
    <recordType>Product2.Offer</recordType>
    <productSpecificationType>Placeholder</productSpecificationType>
    <isCommercial>true</isCommercial>
</ProductSpecificationRecType>
```

## Common Issues

### Product Discovery APIs return "Not Found" for all endpoints
Cause: Product Catalog Management is not enabled in the org.
Solution: Enable via Setup → Revenue Cloud → Product Catalog Management → Enable. Then deploy `ProductCatalogManagementSettings` metadata.

### Index rebuild does not trigger after catalog changes
Cause: No index build has been triggered since the catalog data changes were made.
Solution: Trigger a build via the PCM index API:
```
POST /connect/pcm/index/deploy
```
Poll the response/`GET /connect/pcm/index/snapshots` until `indexBuildStatus = COMPLETED`. Adjust
indexing behavior (e.g., what gets indexed, incremental vs. full) via `GET`/`PATCH /connect/pcm/index/setting`.
*Annotated (v68 re-baseline):* the previous guidance to create a `RuntimeCatalogIndexSetting`
record with a `CatalogId` field is not supported by the v68 guide — no such sObject appears in the
PCM Standard Objects section (Ch.4, printed pp.70–118), and `POST /commerce/management/catalogs/{id}/index`
is not a documented v68 resource path (PCM uses `/connect/pcm/...`, not `/commerce/...`).

### getSessionId() returns null in Agentforce execution context
Cause: When Apex runs inside a GenAiFunction invoked by an Agentforce agent, `UserInfo.getSessionId()` returns null — HTTP callouts to `/connect/cpq/` endpoints cannot be authenticated.
Solution: Use SOQL directly against `Product2`, `ProductClassificationAttr`, `AttributePicklistValue` etc. (see `rlm-product-catalog` for query patterns), or use Standard Invocable Actions via Flow (these do not require a session ID). See `references/product-discovery-invocable-actions.md`.

### No products returned despite correct catalogId
Cause: Product index not built or stale.
Solution: Rebuild the index — `POST /connect/pcm/index/deploy`. Check `indexBuildStatus: IN_PROGRESS | FAILED | COMPLETED | COMPLETED_WITH_ERRORS` in the response, or inspect `GET /connect/pcm/index/error` for failure detail.

### `enablePricing: true` but `prices` is empty
Cause: The **Pricing Procedure** toggle in Setup → Product Discovery Settings is disabled, which overrides the API parameter.
Solution: Enable the toggle in Setup or confirm `priceBookId` is provided.

### `enableQualification: true` but `qualificationContext` absent from response
Cause: The **Qualification Procedure** toggle in Setup → Product Discovery Settings is disabled.
Solution: Enable the toggle in Setup.

### Faceted search returns no `facets` array
Cause: `Use Indexed Data For Product Listing and Search` toggle is disabled. Faceted search requires the indexed data path.
Solution: Enable the toggle and ensure index is built.

### `searchTerm` with `contains` operator silently ignored
Cause: `contains` is not supported when the **Use Indexed Data** toggle is enabled.
Solution: Use `textQuery.searchPhrase` instead when indexed data is enabled.

## Examples

### Example 1: Find all products in a catalog for an account
```json
POST /connect/cpq/products
{
  "catalogId": "0ZSxx...",
  "priceBookId": "01sxx...",
  "limit": 20,
  "userContext": { "accountId": "001xx..." },
  "enableQualification": true,
  "enablePricing": true
}
```

### Example 2: Search for a product by name
```json
POST /connect/cpq/products/search
{
  "searchTerm": "FESBA",
  "catalogId": "0ZSxx...",
  "priceBookId": "01sxx...",
  "userContext": { "accountId": "001xx..." }
}
```

### Example 3: Get full attribute details for a specific product
```json
POST /connect/cpq/products/01txx0000006j08AAA
{
  "catalogId": "0ZSxx...",
  "priceBookId": "01sxx...",
  "productSellingModelId": "0jPxx...",
  "enablePricing": true,
  "enableQualification": true,
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
```
Response includes attributes, hierarchy, cardinality, and price data.

## See Also

| Skill | Why |
|---|---|
| `rlm-product-catalog` | Product catalog data (products, categories, attributes) must be deployed and indexed before discovery APIs return results; index rebuild is required after any catalog change |
| `rlm-product-configurator` | After discovering and selecting a product, use the configurator to set attribute values on the resulting QuoteLineItem |
| `rlm-transaction-management` | After qualifying and selecting a product, the next step is creating a quote and adding the product as a line item |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 2.0.0 | 2026-09-11 | v68.0 (Winter '27) re-baseline: bumped compatibility to v68.0+; replaced unverified `RuntimeCatalogIndexSetting`/`/commerce/management/...` index guidance with the documented `/connect/pcm/index/*` resources; corrected Chapter citation (Product Discovery is a section of Chapter 4, not Chapter 5) and moved to section-title citations; noted `executeConfigurationRules`/`transactionContextId`/`transactionId` (v67.0+) fields now covered in `product-discovery-api-patterns.md` |
| 1.1.0 | 2026-05-02 | Added See Also table; added Setup-level Common Issues (PCM not enabled, RuntimeCatalogIndexSetting, getSessionId null) |
| 1.0.0 | 2026-04-29 | Initial skill — 9 /connect/cpq/ endpoints, guided selection, bulk product details, qualification, metadata types |

---

## References
- See `references/product-discovery-api-patterns.md` for full request/response body examples for every endpoint
- See `references/product-discovery-invocable-actions.md` for all Standard Invocable Actions
- RLM Developer Guide (v68, Winter '27) — Chapter 4: Product Catalog Management › Product Discovery › Business APIs
- RLM Developer Guide (v68, Winter '27) — Chapter 4: Product Catalog Management › Product Discovery › Metadata API Types: ProductSpecificationType, ProductSpecificationRecType, ProductCatalogManagementSettings

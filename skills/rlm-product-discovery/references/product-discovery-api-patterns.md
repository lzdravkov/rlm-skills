# Product Discovery — API Patterns Reference

Base path: `/services/data/v66.0/connect/cpq/`
All methods: POST (composite API)
Available: Enterprise, Unlimited, Developer Editions of Revenue Cloud

---

## Common Request Fields (all endpoints)

| Field | Type | Required | Description |
|---|---|---|---|
| `correlationId` | String | Optional | UUID for tracing; auto-generated if omitted |
| `userContext` | Object | Optional | `{ "accountId": "...", "contactId": "..." }` |

---

## Catalog Endpoints

### Catalog Details
`POST /connect/cpq/catalogs/{catalogId}` — API v60.0

```json
// Request
{
  "correlationId": "9cbb9650-48c5-11ed-96d1-0afcf185843b",
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
// Response: CPQ Base Details
```

### Catalog List
`POST /connect/cpq/catalogs` — API v60.0

```json
// Request
{
  "correlationId": "...",
  "limit": 10,
  "offset": 0,
  "orderBy": ["name:asc", "id:desc"],
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
// Response: CPQ Base List
```

| Field | Type | Description |
|---|---|---|
| `limit` | Integer | Items to return |
| `offset` | Integer | Offset for pagination |
| `orderBy` | String[] | Sort order e.g. `["name:asc"]` |

---

## Category Endpoints

### Categories List
`POST /connect/cpq/categories` — API v60.0

```json
// Request
{
  "catalogId": "0ZSxx...",
  "correlationId": "...",
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
// Request with promotions
{
  "catalogId": "0ZSxx...",
  "usePromotions": true,
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
// Response: CPQ Base List
```

**Key fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `catalogId` | String | Optional | If specified, returns categories of that catalog |
| `customFields` | String[] | Optional | Category fields to include |
| `enableQualification` | Boolean | Optional (default `true`) | Run qualification on categories |
| `filter` | FilterInput | Optional | Filter by `name`; operators: `eq`, `in`, `contains`, `gt`, `lt`, `gte`, `lte` |
| `qualificationProcedure` | String | Optional | Custom qualification procedure API name |
| `usePromotions` | Boolean | Optional (v66.0) | Fetch GPM promotions |

### Category Details
`POST /connect/cpq/categories/{categoryId}` — API v60.0

```json
// Request
{
  "correlationId": "...",
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
// Response: CPQ Base Details
```

---

## Product Endpoints

### Products List
`POST /connect/cpq/products` — API v60.0

```json
// Comprehensive request example
{
  "correlationId": "eeaa1db2-f371-4227-a886-c77e2f66ce1d",
  "limit": 60,
  "cursor": "MTAwMDAwMDAwNg==",
  "orderBy": ["name:asc"],
  "catalogId": "0ZSDU...",
  "categoryId": "0ZGDU...",
  "priceBookId": "01sDU...",
  "productClassificationId": "11BDU...",
  "currencyCode": "USD",
  "userContext": { "accountId": "001DU..." },
  "includeCatalogDetails": true,
  "enableQualification": true,
  "enablePricing": true,
  "qualificationProcedure": "ProductQualification",
  "pricingProcedure": "pricingProcedure",
  "contextDefinition": "BrowseContextDefinitionExt",
  "contextMapping": "ProductDiscoveryMapping",
  "filter": {
    "criteria": [{ "property": "name", "operator": "eq", "value": "Laptop Pro Bundle" }]
  },
  "relatedObjectFilters": [
    {
      "objectName": "ProductSpecificationRecType",
      "criteria": [{ "property": "IsCommercial", "operator": "eq", "value": true }]
    }
  ],
  "additionalContextData": [
    { "nodeName": "Account", "nodeData": { "id": "001DU...", "name": "Cloud Kicks" } }
  ],
  "additionalFields": {
    "Product2": { "fields": ["CanRamp", "DecompositionScope", "ProductCode"] }
  },
  "executeConfigurationRules": false,
  "transactionContextId": "a1b2c3d4e5f6",
  "transactionId": "trans789",
  "usePromotions": true
}
// Response: CPQ Base List
```

**Key fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `catalogId` | String | Optional | Scope to catalog; also returns catalog pricing details |
| `categoryId` | String | Optional | Scope to category (includes all child categories) |
| `priceBookId` | String | Optional | Standard pricebook if omitted |
| `productClassificationId` | String | Optional | Filter by product classification |
| `currencyCode` | String | Optional | Required if multi-currency enabled |
| `filter` | FilterInput | Optional | Filter by `name`: `eq`, `in`, `contains` (not for indexed data) |
| `relatedObjectFilters` | RelatedObjectFilterInput[] | Optional | Filter by `ProductSpecificationRecType.IsCommercial` |
| `includeCatalogDetails` | Boolean | Optional (v61.0) | Include catalog info in response |
| `additionalFields` | Map<String, AdditionalFieldsInput> | Optional (v61.0) | Extra Product2 fields |
| `usePromotions` | Boolean | Optional (v66.0) | GPM promotions |

### Product Details
`POST /connect/cpq/products/{productId}` — API v60.0

```json
{
  "correlationId": "...",
  "catalogId": "0ZSxx...",
  "priceBookId": "01s260...",
  "productSellingModelId": "0jP1Q...",
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." },
  "enablePricing": true,
  "enableQualification": true,
  "qualificationProcedure": "QualificationProcedure",
  "pricingProcedure": "Preview",
  "contextDefinition": "TestDefinition",
  "contextMapping": "TestDefinitionNode",
  "additionalFields": {
    "Product2": { "fields": ["field1", "field2"] },
    "ProductAttributeDefinition": { "fields": ["field3", "field4"] },
    "ProductSellingModelOption": {
      "additionalFields": {
        "ProrationPolicy": { "fields": ["ArePartialPeriodsAllowed", "ProrationPolicyType"] }
      }
    }
  },
  "additionalContextData": [
    { "nodeName": "Contract", "nodeData": { "id": "xxxxx231", "name": "Contract1" } }
  ]
}
// Response: CPQ Base Details (includes attributes, hierarchy, cardinality, prices)
```

`additionalFields` supported objects for Product Details:
- `Product2` — standard/custom Product2 fields
- `ProductAttributeDefinition` — attribute definition fields (if unavailable on ProductClassificationAttr, API fails)
- `ProductSellingModelOption.ProrationPolicy` — proration policy fields (v66.0)

### Bulk Product Details
`POST /connect/cpq/products/bulk` — API v61.0

```json
{
  "productData": [
    { "productId": "01txx...", "productSellingModelId": "0jPxx..." },
    { "productId": "01txx...", "productSellingModelId": "0jPxx..." }
  ],
  "correlationId": "de9a674c-1807-438c-ac78-2c96f4655325",
  "priceBookId": "01sxx...",
  "currencyCode": "USD",
  "enablePricing": true,
  "enableQualification": true,
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}
// Response: Bulk Product Details
```

`productData` (required): Array of `{ "productId": "...", "productSellingModelId": "..." }`.

### Global Search
`POST /connect/cpq/products/search` — API v60.0

```json
// Text query (full-text, requires index)
{
  "query": { "textQuery": { "searchPhrase": "firstproduct" } },
  "catalogId": "0ZSxx...",
  "categoryId": "0ZGT...",
  "correlationId": "...",
  "limit": 10,
  "cursor": "MTAw==",
  "orderBy": ["name:asc", "id:desc"],
  "userContext": { "accountId": "001xx...", "contactId": "003xx..." }
}

// Simple string match (v62.0, no index required)
{
  "searchTerm": "Laptop",
  "catalogId": "0ZSxx...",
  "limit": 10,
  "userContext": { "accountId": "001DU..." }
}

// With additional custom fields
{
  "searchTerm": "Laptop",
  "catalogId": "0ZSxx...",
  "additionalFields": {
    "Product2": { "fields": ["CustomField1__c", "CustomField2__c", "StandardField1"] }
  },
  "usePromotions": true
}
```

**Key request fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `query` | Map<String, Object> | One of these required | `textQuery.searchPhrase` for full-text search |
| `searchTerm` | String | One of these required (v62.0) | Product name contains search |
| `catalogId` | String | Optional | Scope to catalog |
| `categoryId` | String | Optional | Scope to category (includes all child categories) |
| `productClassificationId` | String | Optional | Filter by classification |
| `cursor` | String | Optional | Pagination cursor |
| `enablePricing` | Boolean | Optional (default `true`) | |
| `enableQualification` | Boolean | Optional (default `true`) | |
| `pricingProcedure` | String | Optional | Custom pricing procedure API name |
| `qualificationProcedure` | String | Optional | Custom qualification procedure API name |
| `usePromotions` | Boolean | Optional (v66.0) | GPM promotions |

Note: `contains` filter operator is NOT supported when **Use Indexed Data** toggle is enabled.

### Guided Selection
`POST /connect/cpq/products/guided-selection` — API v62.0

```json
{
  "correlationId": "corrId",
  "catalogId": "0ZSxx...",   // Required
  "priceBookId": "pricebookId",
  "limit": 10,
  "cursor": "MTAw==",
  "userContext": { "accountId": "accId" },
  "guidedSelectionResponseId": "ABCxx...",  // Required if searchTerms not provided
  "searchTerms": [                           // Required if guidedSelectionResponseId not provided
    { "term": "IPhone", "tags": ["deviceType", "mobile"] },
    { "term": "4GB", "tags": ["RAM"] },
    { "term": "64GB", "tags": ["Storage"] }
  ],
  "enableQualification": true,
  "enablePricing": true,
  "includeCatalogDetails": false
}
```

If both `guidedSelectionResponseId` and `searchTerms` are provided, `searchTerms` wins.

### Qualification
`POST /connect/cpq/qualification` — API v60.0

```json
{
  "productIds": ["01txx...", "01txx...", "01txx..."],
  "userContext": { "accountId": "001xx..." }
}
```

Custom procedure: add `"qualificationProcedure": "MyProcApiName"`. Default procedure runs if omitted.

---

## Pagination Pattern

All list responses use cursor-based pagination:
```json
// Request
{ "limit": 10, "cursor": null }

// Response includes (in CPQ Base List)
{ "nextPageToken": "MTAw==", "records": [...] }

// Next page
{ "limit": 10, "cursor": "MTAw==" }
```

---

## Filter Operators Reference

| Operator | Supported on | Notes |
|---|---|---|
| `eq` | All data types | Exact match |
| `in` | All data types | Array of values |
| `contains` | String | NOT supported when Use Indexed Data toggle is enabled |
| `gt` | Number, Date, Datetime | v63.0+ |
| `lt` | Number, Date, Datetime | v63.0+ |
| `gte` | Number, Date, Datetime | v63.0+ |
| `lte` | Number, Date, Datetime | v63.0+ |

Multiple criteria are combined with `AND`.

---

## Catalog Index Management

After deploying or updating products, rebuild the runtime catalog index:
```bash
# Create RuntimeCatalogIndexSetting record to trigger rebuild
sf data create record \
  --sobject RuntimeCatalogIndexSetting \
  --values "RebuildIndex=true" \
  --target-org <alias>
```

Index build types:
- `FULL` — complete rebuild
- `INCREMENTAL` — partial update (v63.0+)

Index build statuses: `IN_PROGRESS`, `FAILED`, `COMPLETED`, `COMPLETED_WITH_ERRORS`

Snapshot activation statuses: `NONE`, `ACTIVE`, `EXPIRED`
Activation types: `IMMEDIATE` — snapshot activates immediately after a successful build.

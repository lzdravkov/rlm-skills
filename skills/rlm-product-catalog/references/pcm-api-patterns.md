# Product Catalog Management — REST API Patterns

Base URL: `https://{instance}.salesforce.com/services/data/v66.0/commerce`

## Authentication
All REST calls require a Bearer token. In Apex running in an agent context, `UserInfo.getSessionId()` returns null — never use it for callouts. Use SOQL for all data access from Apex in agent context.

---

## Product Discovery APIs

### Search products by term
```
GET /commerce/catalog/search?q={term}&catalogId={catalogId}&language=en_US
```
Response:
```json
{
  "products": [
    { "id": "01t...", "name": "...", "productCode": "...", "fields": {} }
  ],
  "total": 10,
  "pageSize": 25
}
```

### Get product detail with attributes and selling models
```
GET /commerce/catalog/products/{productId}?fields=id,name,attributes,sellingModels
```
Response includes:
- `attributes[]` — list of attribute definitions with `name`, `dataType`, `picklistValues`
- `sellingModels[]` — list of `ProductSellingModel` options
- `mediaGroups[]` — product images

### Browse catalog categories
```
GET /commerce/catalog/{catalogId}/categories
```
Returns tree of `ProductCategory` nodes with `id`, `name`, `parentCategoryId`, `productCount`.

### Get products in a category
```
GET /commerce/catalog/{catalogId}/categories/{categoryId}/products
```

### Get qualification procedure results
```
POST /commerce/catalog/qualificationprocedures/{procedureId}/execute
Body: { "contextMap": { "accountId": "001...", "opportunityId": "006..." } }
```
Returns eligible product IDs based on qualification rules.

---

## Product Catalog Business API (CRUD)

### Create a product
```
POST /commerce/management/products
Body:
{
  "name": "FESBA Generator 1500kW",
  "productCode": "FESBA-1500",
  "type": "Product",
  "isActive": true,
  "productClassificationId": "0HV..."
}
```

### Get product selling model options
```
GET /commerce/management/products/{productId}/sellingModelOptions
```

### Associate product to category
```
POST /commerce/management/categories/{categoryId}/products
Body: { "productId": "01t..." }
```

---

## Product Index

After any catalog changes, rebuild the product index:
```
POST /commerce/management/catalogs/{catalogId}/index
```
Or via Setup UI: Revenue Cloud > Product Discovery > Rebuild Index.

Index rebuild is async — poll status:
```
GET /commerce/management/catalogs/{catalogId}/indexStatus
```

---

## Common Response Codes

| Code | Meaning |
|---|---|
| 200 | Success |
| 201 | Created |
| 400 | Bad request — check required fields |
| 404 | Record not found — verify ID |
| 500 | Server error — check debug logs |

---

## Product Discovery — Standard Invocable Actions

Standard invocable actions are available in Flow Builder under the **Product Discovery** category. They call the same `/connect/cpq/` APIs without requiring an HTTP callout or session ID.

| Action Label | Description |
|---|---|
| Get Product Catalogs | Returns list of product catalogs |
| Get Product Categories | Returns categories/subcategories of a catalog |
| Get Product Category Details | Returns details of a specific category |
| Get Product Details | Returns full product details (attributes, hierarchy, cardinality) |
| Get Products | Returns products for a catalog/category |
| Get Bulk Products | Returns details for multiple product IDs |
| Search Products | Returns products matching a search query or term |
| Guided Selection | Returns products based on guided selection search terms |
| Run Qualification | Runs a qualification procedure on a list of product IDs |

**Agentforce context**: `getSessionId()` returns null in the agent execution context — use SOQL or Standard Invocable Actions via Flow instead of direct REST callouts.

See `skills/rlm-product-discovery/references/product-discovery-invocable-actions.md` for Apex (`ConnectApi.ProductDiscovery`) usage and the full invocable action input/output reference.

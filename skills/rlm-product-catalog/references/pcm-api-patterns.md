# Product Catalog Management — REST API Patterns

Base URL: `https://{instance}.salesforce.com/services/data/v68.0/connect/pcm`

*Correction (v68 re-baseline, 2026-09-11):* the v66-era base path used `/commerce/...`, which is not
a documented PCM resource family in the v68 Revenue Management Developer Guide. PCM Business APIs
are Connect REST resources under `/connect/pcm/...` (with a handful of `/revenue/...` resources for
classification details, config-rule execution, and product recommendations). Product Discovery's
composite search/browse APIs are a separate family under `/connect/cpq/...` — see
`rlm-product-discovery/references/product-discovery-api-patterns.md`. Source: RLM Developer Guide
(v68, Winter '27) — Chapter 4: Product Catalog Management › Business APIs (printed pp.128–276).

## Authentication
All REST calls require a Bearer token. In Apex running in an agent context, `UserInfo.getSessionId()` returns null — never use it for callouts. Use SOQL for all data access from Apex in agent context.

---

## Product Catalog Management Business APIs (CRUD)

### Create a product
```
POST /connect/pcm/products
Body:
{
  "name": "FESBA Generator 1500kW",
  "productCode": "FESBA-1500",
  "type": "Product",
  "isActive": true,
  "productClassificationId": "0HV..."
}
```

### Get product detail with attributes and selling models
```
GET /connect/pcm/products/{productId}
```

### Get bulk product / variant records
```
POST /connect/pcm/products/bulk
POST /connect/pcm/products/variants
```

### Browse catalogs and categories
```
POST /connect/pcm/catalogs                        # create a catalog
GET  /connect/pcm/catalogs/{catalogId}             # catalog detail
GET  /connect/pcm/catalogs/{catalogId}/categories  # category tree for a catalog
GET  /connect/pcm/categories/{categoryId}          # category detail
```

### Product classification details
```
POST /revenue/product-catalog-management/product-classifications/details
```

### Deep clone a catalog/product/classification record
```
POST /connect/pcm/deep-clone
```

### Unit of measure info / rounding
```
GET  /connect/pcm/unit-of-measure/info
POST /connect/pcm/unit-of-measure/rounded-data
```

*Annotated:* the v66-era "get product selling model options" (`GET .../sellingModelOptions`) and
"associate product to category" (`POST .../categories/{categoryId}/products`) endpoints are **not**
present in the v68 PCM Business API resource inventory reviewed for this re-baseline. Selling model
options are exposed as related records on `Product2`/`ProductSellingModelOption` (query via SOQL, or
request via Product Discovery's `additionalFields`), and category-product association is performed
by creating a `ProductCategoryProduct` junction record (DML/SOQL), not a dedicated REST call. If a
newer PCM resource for either of these exists elsewhere in the Business APIs section (printed
pp.128–276), it wasn't found in the pages sampled for this pass — treat this note as provisional
and verify directly against Setup if you rely on a REST-only integration path.

Product qualification-procedure execution is a **Product Discovery** capability, not PCM:
`POST /connect/cpq/qualification` (see `rlm-product-discovery`).

---

## Product Index Management

Index build/config/settings live under `/connect/pcm/index/...` — there is no
`/commerce/.../index` resource in v68, and index settings are **not** managed through a queryable
custom-settings-style sObject (see annotation under Product Index below).

### Build (deploy) an index for the current catalog snapshot
```
POST /connect/pcm/index/deploy
```
Response fields include `catalogSnapshotTime`, `completionTime`, `createdById`, `indexBuildStatus`,
`indexBuildType` (`FULL` | `INCREMENTAL`, `INCREMENTAL` avail. API v63.0+), `indexId`, `message`,
`numberOfChanges`.

### Retrieve / persist index configuration
```
GET, PUT /connect/pcm/index/configurations
```

### List created snapshots and their snapshot indexes
```
GET /connect/pcm/index/snapshots
```

### Fetch / update indexing & search settings
```
GET, PATCH /connect/pcm/index/setting
```

### Count / inspect indexing errors
```
GET /connect/pcm/index/error
```

Or via Setup UI: Revenue Cloud > Product Discovery > Rebuild Index.

*Annotated:* a `RuntimeCatalogIndexSetting` standard sObject was searched for in the v68 PCM
Standard Objects section (Ch.4, printed pp.70–118) and not found — the alphabetical listing runs
from `AttributeCategory` through `ProductSpecificationType` with no `Runtime*` object anywhere in
between, immediately followed by the "Fields on Standard Objects" section (p.119). Index settings
are managed exclusively through the `GET`/`PATCH /connect/pcm/index/setting` REST resource above.

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

For the corrected v68 action names (`Find Products Action`, `Get Catalogs Action`, `Get Catalog
Details Action`, `Get Categories Action`, `Get Category Details Action`, `Get Multiple Product
Details Action`, `Get Products Action`, `Get Product Details Action`, `Search Product with Guided
Selection Action`, `Get Product Recommendations Action`, `Execute Qualification Procedure Action`)
and the corrected Apex reference (`runtime_industries_cpq` namespace, `Invocable.Action` pattern —
**not** a `ConnectApi.ProductDiscovery` class), see
`skills/rlm-product-discovery/references/product-discovery-invocable-actions.md`.

**Agentforce context**: `getSessionId()` returns null in the agent execution context — use SOQL or Standard Invocable Actions via Flow instead of direct REST callouts.

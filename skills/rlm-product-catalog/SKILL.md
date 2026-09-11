---
name: rlm-product-catalog
description: Create, query, and manage Salesforce Revenue Cloud product catalogs including product classifications, attribute definitions, attribute picklists, selling models, product bundles, and category structures (RLM v68). Use when working with Product2, ProductClassification, AttributeDefinition, ProductSellingModel, ProductCatalog, or product discovery APIs. Do NOT use for saving attribute values on quote line items (use rlm-product-configurator) or pricing setup (use rlm-pricing). Triggers on: "add product", "create product", "product catalog", "product classification", "attribute definition", "selling model", "product bundle", "configure catalog", "product discovery", "product eligibility", "qualification rule", "product category".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Product Catalog Management

## Instructions

### Step 1: Identify the catalog task
Determine which layer the user is working in:
- **Product Definition**: Product2, ProductClassification, AttributeDefinition, AttributePicklist, ProductSellingModel
- **Bundle / BOM**: ProductRelatedComponent, ProductComponentGroup, ProductRelationshipType
- **Catalog / Discovery**: ProductCatalog, ProductCategory, ProductCategoryProduct, qualification rules
- **Pricing data**: PriceBookEntry, ProductSellingModelOption — cross-references Salesforce Pricing skill

### Step 2: Apply the correct deployment sequence
Product Catalog objects must be deployed in this order (critical — violations cause foreign key errors):

1. ProductSpecificationType (metadata)
2. ProductSpecification Record Type (metadata)
3. AttributePicklist → AttributePicklistValue
4. UnitOfMeasureClass → UnitOfMeasure
5. AttributeDefinition
6. AttributeCategory → AttributeCategoryAttribute
7. ProductClassification → ProductClassificationAttr
8. TaxPolicy
9. Product2
10. ProductAttributeDefinition
11. ProductSellingModel → ProductSellingModelOption
12. ProductRelationshipType → ProductComponentGroup → ProductRelatedComponent
13. ProductCatalog → ProductCategory → ProductCategoryProduct
14. Qualification/disqualification records (ProductQualification, ProductDisqualification)

### Step 3: Work with Product Catalog Business APIs
Use REST APIs at `/services/data/v68.0/connect/pcm/` for catalog operations. The base path is
`/connect/pcm/...` (a Connect REST resource family) — **not** `/commerce/...`, which is not a
documented v68 PCM resource path.

Key endpoints:
- `GET /connect/pcm/products/{productId}` — retrieve product with attributes and selling models
- `POST /connect/pcm/products` — create product
- `GET /connect/pcm/catalogs/{catalogId}/categories` — browse category tree
- Qualification-procedure execution is not a PCM Business API — it's a **Product Discovery**
  capability: `POST /connect/cpq/qualification` (see `rlm-product-discovery`). *Annotated:* no
  dedicated PCM "qualification procedure" REST resource was found in the v68 Business APIs section
  (Ch.4 › Product Catalog Management, printed pp.128–276).

**Never use getSessionId() in Apex for callouts** — it returns null in agent context. Use SOQL instead.

### Step 4: Query pattern for attributes
To retrieve configurable attributes for a product in Apex:
```apex
List<ProductClassificationAttr> attrs = [
    SELECT AttributeDefinition.DeveloperName,
           AttributeDefinition.DataType,
           AttributePicklist.Id,
           (SELECT Id, Value FROM AttributePicklist.AttributePicklistValues)
    FROM ProductClassificationAttr
    WHERE ProductClassification.Id IN (
        SELECT ProductClassificationId FROM Product2
        WHERE Id = :productId
    )
    ORDER BY Sequence
];
```
`Sequence` (type `int`) is a confirmed standard field on `ProductClassificationAttr` — "the display
sequence of the attribute when configuring the product during run time" (Ch.4 › Product Catalog
Management Standard Objects, printed p.96). It has no `__c` suffix; `Sequence__c` was incorrect —
that naming would imply a custom field, and no such custom field is part of the standard object.

### Step 5: Bundle / BOM structure
A bundle product has child `ProductRelatedComponent` records:
- `ParentProductId` → the bundle product
- `ChildProductId` → the component
- `ProductComponentGroup` → groups components (e.g., "Power", "Cooling")
- `Quantity`, `MinQuantity`, `MaxQuantity` — configure selection rules
- BOM rules are enforced at runtime by the PST API (PlaceSalesTransactionExecutor), not SOQL

### Step 6: Selling Models
`ProductSellingModel` defines One-Time, Evergreen, or Term-Defined subscription types. (v68 `SellingModelType` picklist values: `OneTime` | `Evergreen` | `TermDefined` — note `TermDefined`, not `Term`.)
`ProductSellingModelOption` links a selling model to a Product2.

Minimum setup for a configurable product:
1. Create `ProductSellingModel` with `Name`, `SellingModelType` (OneTime | Evergreen | TermDefined)
2. Create `ProductSellingModelOption` linking to Product2 + ProductSellingModel
3. Create `PriceBookEntry` linking Product2 + Pricebook2 + ProductSellingModel

## Common Issues

### Error: "INVALID_CROSS_REFERENCE_KEY on ProductClassificationAttr"
Cause: ProductClassification deployed before AttributeDefinition.
Solution: Follow the deployment sequence above — AttributeDefinition (seq 7) must precede ProductClassification (seq 10).

### Error: Attribute picklist values not appearing in configurator
Cause: AttributePicklistValue records not linked to AttributePicklist, or `IsActive = false`.
Solution: Verify `AttributePicklistValue.AttributePicklistId` and ensure `IsActive = true`.

### Error: Bundle BOM not updating after PST call
Cause: Using `runConfigRules` alone instead of `PlaceSalesTransactionExecutor`.
Solution: Always use `RevSalesTrxn.PlaceSalesTransactionExecutor.execute(graph, SYSTEM, SYSTEM, configOptions, null)` for attribute saves that must trigger BOM restructuring.

### Product discovery returns no results
Cause: Product index not built, or the index configuration/settings are stale.
Solution: After deploying catalog changes, rebuild the product index via Setup > Revenue Cloud > Product Discovery,
or programmatically via `POST /connect/pcm/index/deploy` (build a new index for the current catalog
snapshot). Check/update indexing settings with `GET`/`PATCH /connect/pcm/index/setting`, and inspect
`GET /connect/pcm/index/error` for indexing failures. *Annotated:* `RuntimeCatalogIndexSetting`
does not appear as a standard sObject anywhere in the v68 PCM Standard Objects section (Ch.4,
printed pp.70–118 — the section runs alphabetically from `AttributeCategory` through
`ProductSpecificationType` with no `Runtime*` object in between); index configuration is managed
through the `/connect/pcm/index/*` REST resources instead of a queryable custom-settings-style object.

## Examples

### Example 1: Find all configurable attributes for a product
User says: "Get the attributes for product X"

1. Query ProductClassificationAttr via SOQL (see Step 4)
2. For each attr, check `AttributeDefinition.DataType` (Picklist | Number | Text | Boolean)
3. For Picklist type, join AttributePicklistValue for valid options
4. Return structured list: `[{name, dataType, picklistValues: [...]}]`

### Example 2: Create a new product with a selling model
1. Insert `ProductSellingModel` (OneTime)
2. Insert `Product2` with `ProductClassificationId`, `Name`, `IsActive = true`
3. Insert `ProductSellingModelOption` (Product2 → ProductSellingModel)
4. Insert `PriceBookEntry` (Product2 → standard Pricebook → ProductSellingModel, `UnitPrice`)

### Example 3: Add a product to a catalog category
1. Verify `ProductCatalog` record exists
2. Verify `ProductCategory` exists under the catalog
3. Insert `ProductCategoryProduct` linking `ProductId` + `ProductCategoryId`

## See Also

| Skill | Why |
|---|---|
| `rlm-product-discovery` | After catalog changes, the product index must be rebuilt; Product Discovery APIs browse and search this catalog |
| `rlm-pricing` | `PriceBookEntry` and `ProductSellingModelOption` are deployed after catalog objects and are required for pricing to work |
| `rlm-product-configurator` | Attribute definitions (`ProductClassificationAttr`, `AttributePicklistValue`) defined here are used by the configurator to present and save attribute choices |
| `rlm-deployment` | Full PCM 45-object deployment sequence is covered in the deployment skill's reference files |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 2.0.0 | 2026-09-11 | v68.0 (Winter '27) re-baseline: corrected Business API base path from `/commerce/` to `/connect/pcm/`; fixed `Sequence__c` → standard field `Sequence` on `ProductClassificationAttr`; replaced unverified `RuntimeCatalogIndexSetting` guidance with the documented `/connect/pcm/index/*` resources; converted page-number citations to section-title citations |
| 1.1.0 | 2026-05-02 | Added See Also table; pcm-api-patterns.md updated with Product Discovery Invocable Actions section |
| 1.0.0 | 2026-04-01 | Initial skill — product classification, attributes, selling models, bundles, catalog/category structure |

---

## References
- See `references/pcm-api-patterns.md` for Product Discovery REST API patterns
- See `references/pcm-object-sequences.md` for full 45-object deployment sequence table
- RLM Developer Guide (v68, Winter '27) — Chapter 4: Product Catalog Management › Standard Objects, Fields on Standard Objects, Business APIs
- RLM Developer Guide (v68, Winter '27) — Chapter 4: Product Catalog Management › Product Discovery

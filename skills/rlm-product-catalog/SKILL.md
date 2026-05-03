---
name: rlm-product-catalog
description: Create, query, and manage Salesforce Revenue Cloud product catalogs including product classifications, attribute definitions, attribute picklists, selling models, product bundles, and category structures (RLM v66). Use when working with Product2, ProductClassification, AttributeDefinition, ProductSellingModel, ProductCatalog, or product discovery APIs. Do NOT use for saving attribute values on quote line items (use rlm-product-configurator) or pricing setup (use rlm-pricing). Triggers on: "add product", "create product", "product catalog", "product classification", "attribute definition", "selling model", "product bundle", "configure catalog", "product discovery", "product eligibility", "qualification rule", "product category".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
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
Use REST APIs at `/services/data/vXX.X/commerce/` for catalog operations.

Key endpoints:
- `GET /products/{productId}` — retrieve product with attributes and selling models
- `POST /products` — create product
- `GET /catalogs/{catalogId}/categories` — browse category tree
- `GET /qualificationprocedures/{procedureId}` — get qualification logic

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
    ORDER BY Sequence__c
];
```

### Step 5: Bundle / BOM structure
A bundle product has child `ProductRelatedComponent` records:
- `ParentProductId` → the bundle product
- `ChildProductId` → the component
- `ProductComponentGroup` → groups components (e.g., "Power", "Cooling")
- `Quantity`, `MinQuantity`, `MaxQuantity` — configure selection rules
- BOM rules are enforced at runtime by the PST API (PlaceSalesTransactionExecutor), not SOQL

### Step 6: Selling Models
`ProductSellingModel` defines One-Time, Evergreen, or Term subscription types.
`ProductSellingModelOption` links a selling model to a Product2.

Minimum setup for a configurable product:
1. Create `ProductSellingModel` with `Name`, `SellingModelType` (OneTime | Evergreen | Term)
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
Cause: Product index not built, or `RuntimeCatalogIndexSetting` not configured.
Solution: After deploying catalog changes, rebuild the product index via Setup > Revenue Cloud > Product Discovery.

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
| 1.1.0 | 2026-05-02 | Added See Also table; pcm-api-patterns.md updated with Product Discovery Invocable Actions section |
| 1.0.0 | 2026-04-01 | Initial skill — product classification, attributes, selling models, bundles, catalog/category structure |

---

## References
- See `references/pcm-api-patterns.md` for Product Discovery REST API patterns
- See `references/pcm-object-sequences.md` for full 45-object deployment sequence table
- RLM Developer Guide Chapter 4: Product Catalog Management (p. 68)
- RLM Developer Guide Chapter 4: Product Discovery (p. 279)

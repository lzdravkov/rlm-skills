---
name: rlm-deployment
description: Plan and execute Salesforce Revenue Cloud deployments between dev, sandbox, and production orgs including metadata sequencing, GUID strategy, component state management, and post-deployment steps (RLM v66). Use when deploying RLM components across orgs, setting up a new org, or troubleshooting deployment failures. Do NOT use for product catalog data changes (use rlm-product-catalog) or active quote/order operations (use rlm-transaction-management). Triggers on: "deploy", "deployment", "migration", "move to production", "sandbox refresh", "new org setup", "deployment sequence", "GUID", "post-deployment", "metadata deployment", "data migration", "org setup", "activate component".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Revenue Cloud Deployment

## Instructions

### Step 1: Determine deployment type
- **Full deployment**: First setup of a new org, major release, or complete org sync
- **Incremental deployment**: Ongoing DevOps — only changed metadata/data since last deployment

For incremental: use a version control system to track deltas. Plan change tracking, dependency analysis, and sequencing before every deployment.

### Step 2: Establish GUID strategy before any deployment
A Global Unique ID (GUID) field on every object is mandatory for Revenue Cloud DevOps. Salesforce record IDs are org-specific; without GUIDs you cannot reliably upsert records across orgs.

**Create a GUID field on every RLM object**:
1. Setup → Object Manager → select object
2. New Field → Text, length 255
3. Mark **Unique** and **External ID**
4. Repeat for all objects in your deployment plan

**Good GUID design**: Immutable, globally unique, non-translatable, single key, generated programmatically (e.g., UUID v4).

**Poor GUID design**: Record Name (mutable), concatenated keys (Name + Version), conditional keys (Pricebook + Product).

For non-extensible objects (cannot add fields): create an external reference table mapping Salesforce IDs to your GUIDs.

Use the GUID as the `externalIdField` in all upsert operations:
```bash
sf data upsert bulk --sobject Product2 --file products.csv --external-id GUID__c --target-org targetOrg
```

### Step 3: Deploy metadata first, then data
**Always deploy metadata before data records** — data records reference metadata types.

Order of operations per module:
1. Deploy metadata (object definitions, record types, flows, settings)
2. Deploy configuration data (product catalog, pricing config)
3. Verify and activate components
4. Run post-deployment steps

### Step 4: Product Catalog Management deployment sequence
Deploy configuration data in this exact order (foreign key dependencies):

| Seq | Object | API Name |
|---|---|---|
| 1 | Product Specification Type | ProductSpecificationType |
| 2 | Product Specification Record Type | ProductSpecification RecordType |
| 3 | Attribute Picklist | AttributePicklist |
| 4 | Attribute Picklist Value | AttributePicklistValue |
| 5 | Unit of Measure Class | UnitOfMeasureClass |
| 6 | Unit of Measure | UnitOfMeasure |
| 7 | Attribute Definition | AttributeDefinition |
| 8 | Attribute Category | AttributeCategory |
| 9 | Attribute Category Attribute | AttributeCategoryAttribute |
| 10 | Product Classification | ProductClassification |
| 11 | Product Classification Attribute | ProductClassificationAttr |
| 12 | Tax Policy | TaxPolicy |
| 13 | Product | Product2 |
| 16 | Product Attribute Definition | ProductAttributeDefinition |
| 20 | Product Selling Model | ProductSellingModel |
| 21 | Product Selling Model Option | ProductSellingModelOption |
| 25 | Product Related Component | ProductRelatedComponent |
| 28 | Catalog | ProductCatalog |
| 29 | Category | ProductCategory |
| 30 | Product Category Product | ProductCategoryProduct |

For full 45-object sequence, see `references/pcm-deploy-sequence.md`.

### Step 5: Salesforce Pricing deployment sequence

| Seq | Object | API Name |
|---|---|---|
| 1 | Product Selling Model | ProductSellingModel |
| 2 | Product Selling Model Option | ProductSellingModelOption |
| 3 | Price Book | Pricebook2 |
| 4 | Cost Book | CostBook |
| 5 | Price Book Entry | PriceBookEntry |
| 7 | Price Adjustment Schedule | PriceAdjustmentSchedule |
| 8 | Price Adjustment Tier | PriceAdjustmentTier |
| 11 | Attribute Based Adj Rule | AttributeBasedAdjRule |
| 12 | Attribute Adjustment Condition | AttributeAdjustmentCondition |
| 13 | Attribute Based Adjustment | AttributeBasedAdjustment |
| 50 | Pricing Recipe (metadata) | PricingRecipe |

**CRITICAL**: Decision Tables must be deployed before PricingRecipe. AttributeBasedAdjRule must exist before AttributeAdjustmentCondition.

### Step 6: RevenueManagementSettings — deploy via settings file
All RLM feature flags are in `revenuemanagement.settings`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<RevenueManagementSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableCoreCPQ>true</enableCoreCPQ>
    <enableDeltaPricing>true</enableDeltaPricing>
    <enableTransactionProcessor>true</enableTransactionProcessor>
    <enableAutoAddDerivedAsset>true</enableAutoAddDerivedAsset>
    <enableRampDeal>true</enableRampDeal>
    <enableRevUnifiedSetup>true</enableRevUnifiedSetup>
    <groupsEnabled>true</groupsEnabled>
    <enableTransactionCloning>true</enableTransactionCloning>
</RevenueManagementSettings>
```

package.xml entry:
```xml
<types>
    <members>RevenueManagement</members>
    <name>Settings</name>
</types>
<version>66.0</version>
```

**WARNING**: Once `enableTransactionProcessor` is turned on, it cannot be turned off.

### Step 7: Managing component states
Components have Active / Inactive / Draft states that affect deployment:

- **Deploy new component**: deploy along with all its versions
- **Deploy component updates**: deactivate in target org first, deploy, then reactivate
- **Components with dependencies**: migrate dependent elements (decision matrices, subexpressions, context definitions) independently before migrating the parent component version

Post-deployment: always activate components in the correct order — dependencies before dependents.

### Step 8: Post-deployment checklist
After every deployment to a target org:

- [ ] Refresh decision tables
- [ ] Sync pricing data (rebuild PriceBookEntry derived prices if needed)
- [ ] Rebuild the product index (Setup → Revenue Cloud → Product Discovery → Rebuild Index)
- [ ] Manually create any elements that cannot be deployed via API
- [ ] Create or activate user accounts for testing
- [ ] Run regression test quotes to validate pricing and BOM rules
- [ ] Verify `RevenueManagementSettings` feature flags are correct for target environment

### Step 9: Deployment scenarios — common patterns

**New product launch** (incremental):
1. Deploy: product record type metadata, page layouts
2. Data: Product2, ProductClassificationAttr, AttributePicklistValues, PriceBookEntry, ProductSellingModelOption
3. Validate: create test quote, confirm price flows, validate subscription billing cycle

**Bundle creation** (incremental):
1. Data: bundle Product2, child products, ProductRelatedComponent, ProductComponentGroup, bundle pricing
2. Prereq: attributes, picklists, child products, price book must exist in target
3. Validate: configure bundle in quote, test configuration options, confirm pricing rollup

**Pricing update** (incremental):
1. Data: update PriceBookEntry.UnitPrice, adjust PriceAdjustmentTier values
2. Prereq: no dependent active contracts referencing old pricing
3. Validate: generate test quote, confirm new price, confirm no impact to active contracts

**New org setup** (full deployment):
1. Enable RLM: deploy `RevenueManagementSettings`
2. Deploy metadata: all object/field customizations, flows, Apex
3. Deploy configuration data: full PCM sequence (Steps 4-5 above)
4. Run post-deployment checklist (Step 8)

## Common Issues

### Error: "INVALID_CROSS_REFERENCE_KEY" on data load
Cause: Parent record not yet deployed — deployment sequence violated.
Solution: Check the object's foreign keys (see deployment tables above). Deploy the parent object first.

### Error: "Cannot deploy active version"
Cause: Trying to update a component version that is Active in the target org.
Solution: Deactivate the version in the target org, deploy the update, reactivate.

### Circular dependency in deployment
Cause: Object A depends on B and B depends on A.
Solution: Deploy A first (without the B reference), then deploy B, then redeploy A with the B reference populated.

### Product index not reflecting new products after deployment
Cause: Product index must be manually rebuilt after catalog changes.
Solution: Setup → Revenue Cloud → Product Discovery → Rebuild Index. Or trigger via API: `POST /commerce/catalogs/{id}/index`.

### Feature not working in target org after deployment
Cause: `RevenueManagementSettings` feature flag not enabled in target.
Solution: Verify the settings file was included in the deployment package. Check org settings via `sf org display --target-org <alias>` and query `RevenueManagementSettings`.

### GUID field missing on some objects
Cause: GUID field not created on all objects before first data load.
Solution: Add GUID field (Text 255, Unique, External ID) immediately. Backfill existing records before next deployment cycle.

## Examples

### Example 1: Deploy a new product to staging
User says: "Deploy the FESBA Generator product to the staging org"

1. Export from source: Product2, ProductClassificationAttr, AttributePicklistValues, PriceBookEntry, ProductSellingModelOption, ProductRelatedComponent
2. Verify all parent records (AttributePicklist, ProductClassification, Pricebook2, ProductSellingModel) exist in target
3. Upsert data using GUID__c as external ID
4. Post-deploy: rebuild product index, run test quote
5. Report: N records deployed, validation passed

### Example 2: Set up a new demo org from scratch
1. Deploy `RevenueManagementSettings` (enable all required flags)
2. Deploy metadata package
3. Follow PCM deployment sequence (Step 4) — load all 45 catalog objects in order
4. Deploy pricing objects (Step 5)
5. Run post-deployment checklist (Step 8)
6. Create test quote to validate end-to-end

### Example 3: Update pricing for existing products
1. Export updated PriceBookEntry records from source org
2. Verify no active contracts reference the old pricing
3. Upsert PriceBookEntry using GUID__c external ID
4. Run `sf data upsert bulk --sobject PriceBookEntry --file pricing.csv --external-id GUID__c`
5. Validate: create test quote, confirm new price reflects

## See Also

| Skill | Why |
|---|---|
| `rlm-product-catalog` | Product catalog objects (PCM sequence) are deployed as part of every full deployment |
| `rlm-pricing` | Pricing objects (PriceBookEntry, PriceAdjustmentSchedule) must be deployed after catalog objects |
| `rlm-transaction-management` | Transaction metadata (SalesTransactionType, AppUsageAssignment) is part of full deployment |
| `rlm-billing` | Billing objects (AccountingPeriod, BillingPolicy, TaxEngine) need org-specific post-deploy activation |
| `rlm-dynamic-revenue-orchestrator` | DRO settings and FulfillmentStepDefinition are deployed as part of full deployment |
| `rlm-usage-management` | Usage Management settings (IndustriesUsageSettings) and catalog objects are deployed before runtime |
| `rlm-advanced-approvals` | Approval permission sets and orchestration Flows are part of the metadata deployment package |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.1.0 | 2026-05-02 | Added See Also table; added scripts/backfill-guids.apex, verify-deployment.apex, rollback-data-load.apex |
| 1.0.0 | 2026-04-01 | Initial skill — GUID strategy, PCM/pricing deployment sequences, RevenueManagementSettings, post-deploy checklist |

---

## References
- See `references/deploy-sequence-full.md` for complete all-module deployment sequence table
- See `references/guid-patterns.md` for GUID field creation and backfill scripts
- RLM Developer Guide Chapter 3: Revenue Cloud Deployment (p. 9)
- RLM Developer Guide: Additional Deployment Information (p. 45)
- See `references/deploy-cli-runbook.md` for a phase-by-phase CLI deployment runbook

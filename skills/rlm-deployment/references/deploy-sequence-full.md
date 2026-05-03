# Revenue Cloud — Full Multi-Module Deployment Sequence

Deploy modules in this order. Within each module, follow the object sequence table.

Source: RLM Developer Guide v66.0, Chapter 3 (p. 19–30).

---

## Phase 1: Settings & Metadata

### 1a. RevenueManagementSettings
File: `force-app/main/default/settings/revenuemanagement.settings`

Minimum fields to enable:
```xml
<enableCoreCPQ>true</enableCoreCPQ>
<enableTransactionProcessor>true</enableTransactionProcessor>
<enableDeltaPricing>true</enableDeltaPricing>
<enableRevUnifiedSetup>true</enableRevUnifiedSetup>
<enableAutoAddDerivedAsset>true</enableAutoAddDerivedAsset>
<groupsEnabled>true</groupsEnabled>
<enableTransactionCloning>true</enableTransactionCloning>
```

Deploy command:
```bash
sf project deploy start --metadata Settings:RevenueManagement --target-org <alias>
```

### 1b. Transaction Management Metadata
```
SalesTransactionType    (→ PricingProcedure)
TransactionProcessingType
AppUsageAssignment
QuoteTemplateRichTextData
```

### 1c. Product Configurator Metadata
```
ProductConfigurationRule
ProductConfigurationFlow
ExpressionSetConstraintObj
ProductConfigFlowAssignment
```

### 1d. Salesforce Pricing Metadata
```
PricingRecipe           (requires ExpressionSetDefinition first)
IndustriesPricingSettings
PricingActionParameters
ProcedureOutputResolution
```

### 1e. Billing Metadata
```
BillingSettings
Flow for Billing
PaymentsSharingSettings
```

### 1f. Dynamic Revenue Orchestrator Metadata
```
DynamicFulfillmentOrchestratorSettings
```

### 1g. Usage Management Metadata
```
Flow for Usage Management
IndustriesUsageSettings
```

---

## Phase 2: Product Catalog Management Data
See `references/pcm-object-sequences.md` for full 45-object table.

Key objects (abbreviated):
1. AttributePicklist → AttributePicklistValue
2. AttributeDefinition
3. ProductClassification → ProductClassificationAttr
4. Product2
5. ProductSellingModel → ProductSellingModelOption
6. ProductRelatedComponent (BOM)
7. ProductCatalog → ProductCategory → ProductCategoryProduct

---

## Phase 3: Salesforce Pricing Data

| Seq | Object | API Name |
|---|---|---|
| 1 | Product Selling Model | ProductSellingModel |
| 2 | Product Selling Model Option | ProductSellingModelOption |
| 3 | Price Book | Pricebook2 |
| 4 | Cost Book | CostBook |
| 5 | Price Book Entry | PriceBookEntry |
| 6 | Cost Book Entry | CostBookEntry |
| 7 | Price Adjustment Schedule | PriceAdjustmentSchedule |
| 8 | Price Adjustment Tier | PriceAdjustmentTier |
| 9 | Price Book Entry Derived Price | PriceBookEntryDerivedPrice |
| 10 | Bundle Based Adjustment | BundleBasedAdjustment |
| 11 | Attribute Based Adj Rule | AttributeBasedAdjRule |
| 12 | Attribute Adjustment Condition | AttributeAdjustmentCondition |
| 13 | Attribute Based Adjustment | AttributeBasedAdjustment |
| 30 | Index Rate | IndexRate |
| 50 | Pricing Recipe (metadata) | PricingRecipe |
| 90 | Product Price Range | ProductPriceRange |

---

## Phase 4: Product Configurator Data

| Seq | Object | API Name |
|---|---|---|
| 1 | Product Configuration Rule | ProductConfigurationRule |
| 1 | Product Configuration Flow | ProductConfigurationFlow |
| 1 | Expression Set Constraint Obj | ExpressionSetConstraintObj |
| 2 | Product Config Flow Assignment | ProductConfigFlowAssignment |

---

## Phase 5: Transaction Management Data

| Seq | Object | API Name |
|---|---|---|
| 1 | App Usage Assignment (metadata) | AppUsageAssignment |
| 1 | Sales Transaction Type (metadata) | SalesTransactionType |

---

## Phase 6: Dynamic Revenue Orchestrator Data

| Seq | Object | API Name |
|---|---|---|
| 1 | Fulfillment Step Definition Group | FulfillmentStepDefinitionGroup |
| 2 | Fulfillment Step Definition | FulfillmentStepDefinition |
| 3 | Product Fulfillment Scenario | ProductFulfillmentScenario |
| 4 | Fulfillment Plan | FulfillmentPlan |
| 5 | Fulfillment Step | FulfillmentStep |

---

## Phase 7: Billing Data

| Seq | Object | API Name |
|---|---|---|
| 1 | Accounting Period | AccountingPeriod |
| 2 | Billing Policy | BillingPolicy |
| 3 | Billing Treatment | BillingTreatment |
| 4 | Billing Treatment Item | BillingTreatmentItem |
| 5 | Tax Engine | TaxEngine |
| 6 | Tax Policy | TaxPolicy |
| 7 | Tax Treatment | TaxTreatment |
| 8 | Payment Term | PaymentTerm |
| 9 | Payment Schedule Policy | PaymentSchedulePolicy |

---

## Post-Deployment Checklist (Every Deployment)

- [ ] Refresh decision tables (Expression Sets)
- [ ] Rebuild product index: `POST /commerce/management/catalogs/{id}/index`
- [ ] Sync pricing data (run headless pricing on a test quote)
- [ ] Activate all flows and component versions
- [ ] Create/activate test user accounts
- [ ] Run regression test quote: Opportunity → Quote → QuoteLineItem → Configure → Price → Order
- [ ] Verify `RevenueManagementSettings` flags match target environment expectations

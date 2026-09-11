# Revenue Cloud — Full Multi-Module Deployment Sequence

Deploy modules in this order. Within each module, follow the object sequence table.

Source: RLM Developer Guide (v68.0, Winter '27) — Chapter 3: Revenue Management Deployment › Object Deployment Reference (Product Catalog Management Objects, Salesforce Pricing Objects, Product Configurator Objects, Transaction Management Objects, Dynamic Revenue Orchestrator Objects, Usage Management Objects, Billing Objects).

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

v67.0 addition: `<enableGroupRampTrialSegmentPref>true</enableGroupRampTrialSegmentPref>` — enables trial pricing segments within group ramp deals (see SKILL.md Step 6 for full field notes).

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

**Corrected for v68** — the prior version of this table listed `FulfillmentPlan`/`FulfillmentStep` at seq 4–5, but those are *runtime execution* records, not configuration objects, and don't appear in the v68 Object Deployment Reference's Dynamic Revenue Orchestrator Objects table. The verified deployment-configuration sequence is:

| Seq | Object | API Name |
|---|---|---|
| 1 | Fulfillment Step Definition Group | FulfillmentStepDefinitionGroup |
| 2 | Fulfillment Step Definition | FulfillmentStepDefinition |
| 3 | Fulfillment Step Dependency Definition | FulfillmentStepDependencyDef |
| 4 | Product Fulfillment Scenario | ProductFulfillmentScenario |
| 5 | Fulfillment Workspace | FulfillmentWorkspace |
| 6 | Fulfillment Workspace Item | FulfillmentWorkspaceItem |
| 7 | Fulfillment Fallout Rule | FulfillmentFalloutRule |
| 8 | Fulfillment Step Jeopardy Rule | FulfillmentStepJeopardyRule |
| 9 | Fulfillment Task Assignment Rule | FulfillmentTaskAssignmentRule |

Decomposition/enrichment objects use a separate sequence (also starting at 1, per the v68 guide — these aren't FK-dependent on the table above):

| Seq | Object | API Name |
|---|---|---|
| 1 | Product Fulfillment Decomposition Rule | ProductFulfillmentDecompRule |
| 2 | Value Transformation Group | ValTfrmGrp |
| 3 | Value Transformation | ValTfrm |
| 4 | Product Decomposition Enrichment Rule | ProductDecompEnrichmentRule |
| 5 | Product Decomposition Enrichment Variable Mapping | ProdtDecompEnrchVarMap |

*Note (v67.0+): `FulfillmentStepDefinition` and related RuleSet-backed objects (`ProductFulfillmentScenario`, `ProductFulfillmentDecompRule`, `FulfillmentTaskAssignmentRule`) now use global-key (UUID) API naming decoupled from the parent record ID, removing the pre-commit dependency on record IDs. Legacy record-ID-based names still work and coexist in the same org — no forced migration required.*

---

## Phase 7: Billing Data

**Corrected for v68** — the prior version of this table had AccountingPeriod first and omitted several objects. The verified v68 Object Deployment Reference sequence for Billing Objects is:

| Seq | Object | API Name |
|---|---|---|
| 1 | Profile | Profile |
| 2 | User | User |
| 3 | User Role | UserRole |
| 4 | Legal Entity | LegalEntity |
| 5 | Billing Policy | BillingPolicy |
| 6 | Billing Treatment | BillingTreatment |
| 7 | Billing Treatment Item | BillingTreatmentItem |
| 8 | Tax Engine Provider | TaxEngineProvider |
| 9 | Tax Engine | TaxEngine |
| 10 | Tax Policy | TaxPolicy |
| 11 | Tax Treatment | TaxTreatment |
| 12 | Tax Treatment Item | TaxTreatmentItem |
| 13 | Payment Term | PaymentTerm |
| 14 | Payment Term Item | PaymentTermItem |
| 15 | Accounting Period | AccountingPeriod |
| 16 | Legal Entity Accounting Period | LegalEntityAccountingPeriod |
| 17 | General Ledger Account | GeneralLedgerAccount |
| 18 | General Ledger Account Assignment Rules | GeneralLedgerAcctAsgntRule |
| 19 | Payment Schedule Policy | PaymentSchedulePolicy |
| 20 | Payment Schedule Treatment | PaymentScheduleTreatment |
| 21 | Payment Schedule Treatment Detail | PaymentScheduleTreatmentDtl |
| 22 | Payment Schedule Distribution Method | PymtSchdDistributionMethod |
| 23 | Billing Milestone Plan | BillingMilestonePlan |
| 24 | Billing Milestone Plan Item | BillingMilestonePlanItem |
| 25 | General Ledger Journal Entry Rule | GeneralLedgerJrnlEntryRule |
| 26 | Payment Retry Rule | PaymentRetryRule |
| 27 | Payment Retry Rule Set | PaymentRetryRuleSet |
| 28 | Billing Arrangement | BillingArrangement |
| 29 | Billing Arrangement Line | BillingArrangementLine |

Activation-order notes (per Billing Additional Information): activate Billing Treatment Item before Billing Policy; activate Tax Treatment before Tax Policy; activate Payment Term Item before Payment Term; activate Payment Schedule Treatment before Payment Schedule Policy.

---

## Phase 8: Salesforce Contracts Data

*New in this reference (surgical v68 addition — previously undocumented in this skill).*

| Seq | Object | API Name |
|---|---|---|
| 1 | Clause Category Configuration (metadata) | ClauseCatgConfiguration |
| 2 | Document Clause Set | DocumentClauseSet |
| 3 | Document Clause | DocumentClause |

Source: RLM Developer Guide (v68.0) — Chapter 3 › Object Deployment Reference › Salesforce Contracts Objects.

---

## Post-Deployment Checklist (Every Deployment)

- [ ] Refresh decision tables (Expression Sets)
- [ ] Rebuild product index: `POST /connect/pcm/index/deploy` (corrected — `/commerce/management/catalogs/{id}/index` is not a real v68 resource). Use Full Index Rebuild when enabling the feature for the first time or changing index settings; use Partial Index Rebuild for routine product/category changes.
- [ ] Sync pricing data (run headless pricing on a test quote)
- [ ] Activate all flows and component versions
- [ ] Create/activate test user accounts
- [ ] Run regression test quote: Opportunity → Quote → QuoteLineItem → Configure → Price → Order
- [ ] Verify `RevenueManagementSettings` flags match target environment expectations

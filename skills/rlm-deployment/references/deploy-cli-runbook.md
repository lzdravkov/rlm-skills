# Revenue Cloud Deployment — CLI Runbook

CLI: Salesforce CLI v2 (`sf` commands only — never `sfdx`)
API Version: 66.0
Target org alias: set via `--target-org <alias>`

---

## Phase 0: Prerequisites

```bash
# Verify org connection
sf org display --target-org <alias>

# Confirm API version
sf config get apiVersion

# Verify you are on API v66.0
# If not: sf config set apiVersion=66.0
```

---

## Phase 1: Deploy RevenueManagementSettings

```bash
sf project deploy start \
  --metadata "Settings:RevenueManagement" \
  --target-org <alias>
```

Verify in target org: Setup → Revenue Cloud → Revenue Cloud Settings → confirm flags enabled.

---

## Phase 2: Deploy Metadata Package

```bash
# Deploy all custom metadata, objects, flows, Apex in one pass
sf project deploy start \
  --source-dir force-app \
  --target-org <alias> \
  --wait 30

# Check deploy status
sf project deploy report --target-org <alias>
```

If specific components fail, deploy them individually:
```bash
sf project deploy start \
  --metadata "ApexClass:ProductAttributeSaveService" \
  --target-org <alias>
```

---

## Phase 3: Deploy Product Catalog Management Data

Deploy objects in sequence order (see `deploy-sequence-full.md`, Phase 2).

```bash
# Example: upsert AttributePicklist records
sf data upsert bulk \
  --sobject AttributePicklist \
  --file data/attribute-picklists.csv \
  --external-id GUID__c \
  --target-org <alias> \
  --wait 10

# Example: upsert AttributePicklistValue
sf data upsert bulk \
  --sobject AttributePicklistValue \
  --file data/attribute-picklist-values.csv \
  --external-id GUID__c \
  --target-org <alias> \
  --wait 10

# Continue for each object in sequence: AttributeDefinition,
# ProductClassification, ProductClassificationAttr, Product2, etc.
```

---

## Phase 4: Deploy Pricing Data

```bash
# ProductSellingModel
sf data upsert bulk \
  --sobject ProductSellingModel \
  --file data/selling-models.csv \
  --external-id GUID__c \
  --target-org <alias> --wait 10

# Pricebook2
sf data upsert bulk \
  --sobject Pricebook2 \
  --file data/pricebooks.csv \
  --external-id GUID__c \
  --target-org <alias> --wait 10

# PriceBookEntry
sf data upsert bulk \
  --sobject PriceBookEntry \
  --file data/pricebook-entries.csv \
  --external-id GUID__c \
  --target-org <alias> --wait 10

# PriceAdjustmentSchedule → PriceAdjustmentTier
# AttributeBasedAdjRule → AttributeAdjustmentCondition → AttributeBasedAdjustment
```

---

## Phase 5: Activate Components

After data load, activate components that require explicit activation:

```bash
# Activate ProductConfigurationFlow (via Apex or UI)
sf apex run \
  --file scripts/activate-config-flows.apex \
  --target-org <alias>

# Verify activation
sf data query \
  --query "SELECT Id, Name, Status FROM ProductConfigurationFlow WHERE Status != 'Active'" \
  --target-org <alias>
```

---

## Phase 6: Post-Deployment Verification

```bash
# Rebuild product index
sf data create record \
  --sobject RuntimeCatalogIndexSetting \
  --values "RebuildIndex=true" \
  --target-org <alias>

# Verify no failed flows
sf data query \
  --query "SELECT Id, Label, Status FROM Flow WHERE Status = 'InvalidDraft'" \
  --use-tooling-api \
  --target-org <alias>

# Run regression test quote
sf apex run \
  --file scripts/regression-test-quote.apex \
  --target-org <alias>
```

---

## Useful Diagnostic Queries

```bash
# Check RevenueManagementSettings
sf data query \
  --query "SELECT enableCoreCPQ, enableDeltaPricing, enableTransactionProcessor FROM RevenueManagementSettings" \
  --target-org <alias>

# Check failed deployment jobs
sf data query \
  --query "SELECT Id, Status, NumberRecordsFailed, ErrorMessage FROM BulkApiJob2 ORDER BY CreatedDate DESC LIMIT 10" \
  --target-org <alias>

# Check Apex errors
sf data query \
  --query "SELECT Id, ExceptionMessage, StackTrace FROM ApexLog ORDER BY StartTime DESC LIMIT 5" \
  --target-org <alias>
```

---

## Rollback Procedure

If a deployment must be rolled back:

1. Do NOT use `sf project deploy cancel` on a completed deploy — Salesforce has no automatic rollback
2. Restore from your version-controlled source of truth:
   ```bash
   git checkout <last-good-tag>
   sf project deploy start --source-dir force-app --target-org <alias>
   ```
3. For data: use the GUID-based upsert with the previous CSV export
4. For settings: redeploy the previous `revenuemanagement.settings`

Pre-fix archives: keep a `archive/` directory with timestamped exports before each deployment.

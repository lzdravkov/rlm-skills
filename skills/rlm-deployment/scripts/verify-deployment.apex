/**
 * verify-deployment.apex
 *
 * Post-deployment verification script for Salesforce Revenue Cloud.
 * Runs a series of SOQL assertions to confirm critical configuration is present.
 * Run via:
 *   sf apex run --file skills/rlm-deployment/scripts/verify-deployment.apex --target-org <alias>
 *
 * Each check logs PASS or FAIL with details. Review the debug output after execution.
 */

Integer passCount = 0;
Integer failCount = 0;

// ── Helper ───────────────────────────────────────────────────────────────────
void check(String label, Boolean condition, String failDetail) {
    if (condition) {
        System.debug('PASS  ' + label);
        passCount++;
    } else {
        System.debug('FAIL  ' + label + ' — ' + failDetail);
        failCount++;
    }
}

// ── 1. RevenueManagementSettings ─────────────────────────────────────────────
List<RevenueManagementSettings__c> rmsList = [
    SELECT enableCoreCPQ__c, enableTransactionProcessor__c, enableRevUnifiedSetup__c
    FROM RevenueManagementSettings__c LIMIT 1
];
check('RevenueManagementSettings record exists', !rmsList.isEmpty(),
    'RevenueManagementSettings__c has no records — deploy settings file first');

// ── 2. Active Product Selling Model ──────────────────────────────────────────
Integer psmCount = [SELECT COUNT() FROM ProductSellingModel WHERE IsActive = true];
check('At least one active ProductSellingModel', psmCount > 0,
    'No active ProductSellingModel found — deploy catalog data before testing');

// ── 3. Active Pricebook ───────────────────────────────────────────────────────
Integer pbCount = [SELECT COUNT() FROM Pricebook2 WHERE IsActive = true AND IsStandard = false];
check('At least one active custom Pricebook', pbCount > 0,
    'No active non-standard Pricebook2 — expected at least one RLM-specific pricebook');

// ── 4. Active Products with PriceBookEntry ───────────────────────────────────
Integer pbeCount = [SELECT COUNT() FROM PriceBookEntry WHERE IsActive = true];
check('At least one active PriceBookEntry', pbeCount > 0,
    'No active PriceBookEntry records — products cannot be priced');

// ── 5. ProductCatalog + at least one ProductCategory ─────────────────────────
Integer catalogCount = [SELECT COUNT() FROM ProductCatalog];
Integer categoryCount = [SELECT COUNT() FROM ProductCategory];
check('ProductCatalog exists', catalogCount > 0, 'No ProductCatalog records');
check('ProductCategory exists', categoryCount > 0, 'No ProductCategory records');

// ── 6. AttributeDefinition records ───────────────────────────────────────────
Integer attrDefCount = [SELECT COUNT() FROM AttributeDefinition WHERE IsActive = true];
check('Active AttributeDefinition records exist', attrDefCount > 0,
    'No active AttributeDefinition — configurable products cannot present attributes');

// ── 7. GUID__c fields populated on Product2 ──────────────────────────────────
Integer missingGuids = [SELECT COUNT() FROM Product2 WHERE GUID__c = null AND IsActive = true];
check('No active Product2 records missing GUID__c', missingGuids == 0,
    missingGuids + ' active Product2 records have null GUID__c — run backfill-guids.apex');

// ── 8. IndustriesUsageSettings (if Usage Management is in scope) ──────────────
// Comment out this block if Usage Management is not deployed in this org.
try {
    Integer usageResourceCount = [SELECT COUNT() FROM UsageResource WHERE IsActive = true];
    check('Active UsageResource records exist', usageResourceCount > 0,
        'No active UsageResource — deploy Usage Management catalog objects');
} catch (Exception e) {
    System.debug('SKIP  UsageResource check: ' + e.getMessage()
        + ' (Usage Management may not be enabled)');
}

// ── 9. DRO Settings (if DRO is in scope) ─────────────────────────────────────
// Comment out this block if DRO is not deployed.
try {
    Integer stepDefCount = [SELECT COUNT() FROM FulfillmentStepDefinition WHERE IsActive = true];
    check('Active FulfillmentStepDefinition records exist', stepDefCount > 0,
        'No active FulfillmentStepDefinition — DRO fulfillment steps not deployed');
} catch (Exception e) {
    System.debug('SKIP  FulfillmentStepDefinition check: ' + e.getMessage()
        + ' (DRO may not be enabled)');
}

// ── 10. Apex class availability ───────────────────────────────────────────────
List<ApexClass> pstClass = [
    SELECT Id FROM ApexClass
    WHERE Name IN ('ProductAttributeSaveService', 'EnsureOpportunityService')
];
check('Key Apex classes deployed (ProductAttributeSaveService, EnsureOpportunityService)',
    pstClass.size() == 2,
    'Missing Apex classes: ' + (2 - pstClass.size()) + ' not found — deploy Apex before testing');

// ── Summary ───────────────────────────────────────────────────────────────────
System.debug('');
System.debug('=== VERIFICATION COMPLETE ===');
System.debug('PASS: ' + passCount);
System.debug('FAIL: ' + failCount);
if (failCount > 0) {
    System.debug('Review FAIL entries above and resolve before running end-to-end tests.');
} else {
    System.debug('All checks passed — org is ready for end-to-end testing.');
}

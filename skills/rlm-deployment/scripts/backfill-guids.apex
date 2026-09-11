/**
 * backfill-guids.apex
 *
 * Backfills GUID__c (Text 255, Unique, External ID) on existing records
 * for all standard RLM objects. Run via:
 *   sf apex run --file skills/rlm-deployment/scripts/backfill-guids.apex --target-org <alias>
 *
 * Prerequisites:
 *   - GUID__c field must already exist on each object (Text 255, Unique, External ID)
 *   - Run in batches if orgs have >10k records per object (see note below)
 *
 * v68 verification note: every sObject API name in the objectNames list below was
 * checked against the RLM Developer Guide (v68.0, Winter '27) Chapter 3 Object
 * Deployment Reference (Product Catalog Management Objects, Salesforce Pricing
 * Objects, Usage Management Objects) and confirmed unchanged in v68.0.
 */

// UUID v4 generator — pure Apex, no callouts required
public static String generateUUID() {
    Blob b = Crypto.generateAesKey(128);
    String hex = EncodingUtil.convertToHex(b);
    return hex.substring(0, 8) + '-'
         + hex.substring(8, 12) + '-'
         + '4' + hex.substring(13, 16) + '-'
         + hex.substring(16, 20) + '-'
         + hex.substring(20, 32);
}

// ── Objects to backfill ──────────────────────────────────────────────────────
// Add or remove sObject types as needed for your org's deployment scope.
List<String> objectNames = new List<String>{
    // Product Catalog
    'Product2',
    'ProductClassification',
    'AttributeDefinition',
    'AttributePicklist',
    'AttributePicklistValue',
    'AttributeCategory',
    'ProductSellingModel',
    'ProductSellingModelOption',
    'ProductRelatedComponent',
    'ProductCatalog',
    'ProductCategory',
    'ProductCategoryProduct',
    // Pricing
    'Pricebook2',
    'PriceBookEntry',
    'PriceAdjustmentSchedule',
    'PriceAdjustmentTier',
    'AttributeBasedAdjRule',
    'AttributeAdjustmentCondition',
    'AttributeBasedAdjustment',
    // Usage Management
    'UsageResource',
    'ProductUsageResource',
    'ProductUsageGrant',
    'UsageGrantRenewalPolicy',
    'UsageGrantRolloverPolicy',
    'UsageOveragePolicy'
};

Integer totalUpdated = 0;

for (String objName : objectNames) {
    // Query records missing a GUID (null or empty)
    String soql = 'SELECT Id, GUID__c FROM ' + objName
        + ' WHERE GUID__c = null LIMIT 9500';

    List<SObject> records;
    try {
        records = Database.query(soql);
    } catch (Exception e) {
        System.debug('SKIP ' + objName + ': ' + e.getMessage());
        continue;
    }

    if (records.isEmpty()) {
        System.debug('OK ' + objName + ': no records need backfill');
        continue;
    }

    for (SObject rec : records) {
        rec.put('GUID__c', generateUUID());
    }

    List<Database.SaveResult> results = Database.update(records, false);
    Integer successCount = 0;
    for (Database.SaveResult sr : results) {
        if (sr.isSuccess()) {
            successCount++;
        } else {
            System.debug('ERROR on ' + objName + ': '
                + sr.getErrors()[0].getMessage());
        }
    }

    System.debug('UPDATED ' + objName + ': ' + successCount + '/' + records.size());
    totalUpdated += successCount;
}

System.debug('=== BACKFILL COMPLETE: ' + totalUpdated + ' records updated ===');

// NOTE: This script uses LIMIT 9500 to stay within governor limits.
// If an object has >9500 records without GUIDs, schedule a Batchable Apex job instead:
//
//   Database.executeBatch(new GuidBackfillBatch('Product2'), 200);
//
// Where GuidBackfillBatch is a simple Database.Batchable<SObject> that iterates
// records with GUID__c = null and assigns generateUUID() to each.

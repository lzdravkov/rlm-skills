/**
 * rollback-data-load.apex
 *
 * Rolls back a failed or incorrect data load for a specific sObject type.
 * Uses GUID__c (External ID) to identify and delete records that were
 * inserted in the current or last load cycle.
 *
 * Run via:
 *   sf apex run --file skills/rlm-deployment/scripts/rollback-data-load.apex --target-org <alias>
 *
 * BEFORE RUNNING:
 *   1. Set OBJECT_TO_ROLLBACK to the API name of the object to clean up.
 *   2. Set GUID_PREFIX to match the GUID prefix used in your source CSV
 *      (or use a date prefix if your GUIDs are timestamped).
 *   3. Set DRY_RUN = true first to preview what would be deleted.
 *   4. Set DRY_RUN = false only after confirming the preview is correct.
 *
 * SAFETY:
 *   - DRY_RUN mode logs what would be deleted but does NOT delete anything.
 *   - Always run DRY_RUN first.
 *   - Never run on a production org without confirming in sandbox first.
 *   - This script respects governor limits (max 10k records per run).
 */

// ── CONFIGURATION ─────────────────────────────────────────────────────────────

// Object to roll back (API name)
String OBJECT_TO_ROLLBACK = 'PriceBookEntry';  // Change me

// Match GUIDs that start with this prefix (leave blank to delete ALL records
// with a GUID__c — use with extreme caution).
// Example: 'LOAD-2026-06-01-' to match only records loaded on that date.
String GUID_PREFIX = 'LOAD-2026-06-01-';       // Change me

// Set to false to actually delete (preview first with true)
Boolean DRY_RUN = true;

// Max records to process in one run (stay within governor limits)
Integer MAX_RECORDS = 9500;

// ── EXECUTION ─────────────────────────────────────────────────────────────────

if (DRY_RUN) {
    System.debug('=== DRY RUN MODE — no deletes will occur ===');
} else {
    System.debug('=== LIVE MODE — records WILL be deleted ===');
}

// Build SOQL to find target records
String soql;
if (String.isNotBlank(GUID_PREFIX)) {
    soql = 'SELECT Id, GUID__c FROM ' + OBJECT_TO_ROLLBACK
        + ' WHERE GUID__c LIKE \'' + GUID_PREFIX + '%\''
        + ' LIMIT ' + MAX_RECORDS;
} else {
    soql = 'SELECT Id, GUID__c FROM ' + OBJECT_TO_ROLLBACK
        + ' WHERE GUID__c != null'
        + ' LIMIT ' + MAX_RECORDS;
}

List<SObject> records;
try {
    records = Database.query(soql);
} catch (Exception e) {
    System.debug('ERROR querying ' + OBJECT_TO_ROLLBACK + ': ' + e.getMessage());
    return;
}

System.debug('FOUND ' + records.size() + ' records to roll back on ' + OBJECT_TO_ROLLBACK);

if (records.isEmpty()) {
    System.debug('Nothing to delete. Check OBJECT_TO_ROLLBACK and GUID_PREFIX.');
    return;
}

// Log first 10 records for preview
Integer previewCount = Math.min(10, records.size());
System.debug('--- Preview (first ' + previewCount + ' records) ---');
for (Integer i = 0; i < previewCount; i++) {
    System.debug('  ' + records[i].Id + '  GUID__c=' + records[i].get('GUID__c'));
}
if (records.size() > 10) {
    System.debug('  ... and ' + (records.size() - 10) + ' more');
}

if (DRY_RUN) {
    System.debug('');
    System.debug('=== DRY RUN COMPLETE: ' + records.size() + ' records would be deleted ===');
    System.debug('Set DRY_RUN = false to execute the delete.');
    return;
}

// ── EXECUTE DELETE ────────────────────────────────────────────────────────────
List<Database.DeleteResult> results = Database.delete(records, false);

Integer successCount = 0;
Integer errorCount = 0;
for (Database.DeleteResult dr : results) {
    if (dr.isSuccess()) {
        successCount++;
    } else {
        errorCount++;
        System.debug('DELETE ERROR: ' + dr.getErrors()[0].getStatusCode()
            + ' — ' + dr.getErrors()[0].getMessage());
    }
}

System.debug('');
System.debug('=== ROLLBACK COMPLETE ===');
System.debug('Deleted: ' + successCount);
System.debug('Errors:  ' + errorCount);

if (errorCount > 0) {
    System.debug('Review DELETE ERROR lines above. Common causes:');
    System.debug('  - Child records exist (delete children first)');
    System.debug('  - Record is referenced by an active component');
    System.debug('  - Insufficient permissions');
}

if (records.size() == MAX_RECORDS) {
    System.debug('WARNING: Hit MAX_RECORDS limit (' + MAX_RECORDS + ').');
    System.debug('Re-run to delete the next batch, or increase MAX_RECORDS.');
}

/**
 * setup-test-data.apex
 *
 * Creates a minimal end-to-end Revenue Cloud test chain:
 *   Account → Opportunity → Quote → QuoteLineItem
 *   (with a configured Product2, ProductSellingModel, and PriceBookEntry)
 *
 * Run via:
 *   sf apex run --file skills/rlm-transaction-management/scripts/setup-test-data.apex --target-org <alias>
 *
 * After running, the debug log contains:
 *   - accountId, opportunityId, quoteId, quoteLineItemId
 *   - The product name used (first active configurable product found)
 *
 * PREREQUISITES (must exist in org before running):
 *   - At least one active Product2 with a ProductSellingModel and PriceBookEntry
 *   - Standard pricebook active (always present)
 *   - AttributeDefinition records (for configuration testing)
 *
 * WHAT THIS DOES NOT DO:
 *   - Configure product attributes (run PST separately after getting quoteLineItemId)
 *   - Submit for approval or convert to order
 *   - Create billing schedules
 */

// ── 1. Find or create a test Account ─────────────────────────────────────────
Account acct;
List<Account> existing = [
    SELECT Id FROM Account WHERE Name = 'RLM Test Account' LIMIT 1
];
if (!existing.isEmpty()) {
    acct = existing[0];
    System.debug('REUSE Account: ' + acct.Id);
} else {
    acct = new Account(Name = 'RLM Test Account');
    insert acct;
    System.debug('CREATED Account: ' + acct.Id);
}

// ── 2. Find the standard pricebook ───────────────────────────────────────────
Pricebook2 stdPb = [
    SELECT Id FROM Pricebook2 WHERE IsStandard = true AND IsActive = true LIMIT 1
];

// Find a custom active pricebook (preferred for RLM)
List<Pricebook2> customPbs = [
    SELECT Id, Name FROM Pricebook2
    WHERE IsStandard = false AND IsActive = true
    LIMIT 1
];
Pricebook2 pb = customPbs.isEmpty() ? stdPb : customPbs[0];
System.debug('USING Pricebook: ' + pb.Id + ' (' + pb.Name + ')');

// ── 3. Find an active product with a PriceBookEntry ──────────────────────────
List<PriceBookEntry> pbes = [
    SELECT Id, Product2Id, Product2.Name, UnitPrice, ProductSellingModelId
    FROM PriceBookEntry
    WHERE Pricebook2Id = :pb.Id
      AND IsActive = true
      AND Product2.IsActive = true
    ORDER BY Product2.Name ASC
    LIMIT 1
];

if (pbes.isEmpty()) {
    // Fallback: try standard pricebook
    pbes = [
        SELECT Id, Product2Id, Product2.Name, UnitPrice, ProductSellingModelId
        FROM PriceBookEntry
        WHERE Pricebook2Id = :stdPb.Id
          AND IsActive = true
          AND Product2.IsActive = true
        LIMIT 1
    ];
}

if (pbes.isEmpty()) {
    System.debug('ABORT: No active PriceBookEntry found. Deploy catalog data first.');
    return;
}

PriceBookEntry pbe = pbes[0];
System.debug('USING Product: ' + pbe.Product2.Name + ' (Id: ' + pbe.Product2Id + ')');
System.debug('USING PriceBookEntry: ' + pbe.Id + ' UnitPrice: ' + pbe.UnitPrice);

// ── 4. Create Opportunity ─────────────────────────────────────────────────────
Opportunity opp = new Opportunity(
    Name         = 'RLM Test Opportunity - ' + DateTime.now().format('yyyy-MM-dd HH:mm'),
    AccountId    = acct.Id,
    StageName    = 'Qualification',
    CloseDate    = Date.today().addMonths(3),
    Pricebook2Id = pb.Id
);
insert opp;
System.debug('CREATED Opportunity: ' + opp.Id);

// ── 5. Create Quote ───────────────────────────────────────────────────────────
Quote q = new Quote(
    Name          = 'RLM Test Quote - ' + DateTime.now().format('yyyy-MM-dd HH:mm'),
    OpportunityId = opp.Id,
    Pricebook2Id  = pb.Id,
    Status        = 'Draft',
    ExpirationDate = Date.today().addMonths(1)
);
insert q;
System.debug('CREATED Quote: ' + q.Id);

// ── 6. Create QuoteLineItem ───────────────────────────────────────────────────
QuoteLineItem qli = new QuoteLineItem(
    QuoteId          = q.Id,
    PricebookEntryId = pbe.Id,
    Quantity         = 1,
    UnitPrice        = pbe.UnitPrice
);
// Set ProductSellingModelId if available (required for RLM subscription products)
if (pbe.ProductSellingModelId != null) {
    qli.ProductSellingModelId = pbe.ProductSellingModelId;
}
insert qli;
System.debug('CREATED QuoteLineItem: ' + qli.Id);

// ── 7. Summary ───────────────────────────────────────────────────────────────
System.debug('');
System.debug('=== TEST DATA READY ===');
System.debug('accountId:       ' + acct.Id);
System.debug('opportunityId:   ' + opp.Id);
System.debug('quoteId:         ' + q.Id);
System.debug('quoteLineItemId: ' + qli.Id);
System.debug('productId:       ' + pbe.Product2Id);
System.debug('productName:     ' + pbe.Product2.Name);
System.debug('');
System.debug('Next steps:');
System.debug('  1. Run attribute configuration via PST (see pst-template.cls)');
System.debug('     with quoteId=' + q.Id + ' and quoteLineItemId=' + qli.Id);
System.debug('  2. Check Quote.GrandTotal after PST completes');
System.debug('  3. Submit for approval (optional) → convert to order');

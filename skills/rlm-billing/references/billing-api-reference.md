# Billing — REST API Reference & Key Patterns

Base URL: `https://{instance}.salesforce.com/services/data/v66.0/commerce/billing`

---

## Billing Schedules

### Create billing schedules from an order
```
POST /commerce/billing/billing-schedules
Body: { "billingTransactionId": "801..." }
```
Response: `{ "billingScheduleIds": ["0BS...", "0BS..."] }`

### Invocable (Flow): Create Billing Schedules From Billing Transaction Action
- Input: `billingTransactionId` (Text) — Order or OrderItem ID
- Output: `billingScheduleIds` (Text Collection)

---

## Invoices

### Post a draft invoice
```
POST /commerce/billing/invoices/{invoiceId}/post
```

### Void a posted invoice
```
POST /commerce/billing/invoices/{invoiceId}/void
Body: { "voidReason": "Incorrect billing" }
```
Note: Can only void if no payments have been applied. Unapply payments first.

### Generate invoice document
Invocable (Flow): `GenerateInvoiceDocumentsAction`
- Input: `invoiceIds` (Text Collection)
- Output: `contentDocumentIds` (Text Collection)

### Post Draft Invoice Batch Run (Invocable)
Action: `PostDraftInvoiceBatchRunAction`
- Input: `invoiceBatchRunId` (Text)
- Output: `postedInvoiceIds` (Text Collection)

---

## Credit Memos

### Issue a credit memo from an invoice
Invocable (Flow): `IssueCreditMemoAction`
- Input: `invoiceId` (Text), `creditReason` (Text), optional `lines[]`
- Output: `creditMemoId` (Text)

### Post a draft credit memo
Invocable (Flow): `PostDraftCreditMemoAction`
- Input: `creditMemoId` (Text)

### Apply a credit memo to invoices
Invocable (Flow): `ApplyCreditAction`
- Input: `creditMemoId` (Text), `invoiceIds` (Text Collection)
- Output: `applicationIds` (Text Collection)

### Void a posted credit memo
Invocable (Flow): `VoidPostedCreditMemoAction`
- Input: `creditMemoId` (Text)

---

## Payments

### Apply payments and credits by rules
Invocable (Flow): `ApplyPaymentsAndCreditsByRulesAction`
- Input: `paymentId` (Text), `invoiceIds` (Text Collection)
- Output: `paymentLineInvoiceIds` (Text Collection)

### Unapply a payment
Invocable (Flow): `UnapplyPaymentAction`
- Input: `paymentLineInvoiceId` (Text)

### Unapply a credit
Invocable (Flow): `UnapplyCreditAction`
- Input: `creditMemoInvApplicationId` (Text)

---

## Write-offs

### Write off uncollectible invoices
Invocable (Flow): `WriteOffInvoicesAction`
- Input: `invoiceIds` (Text Collection), `writeOffReason` (Text), `accountingPeriodId` (Text)
- Creates `GeneralLedgerAcctAsgntRule` entries

---

## Grand Total vs. Unit Price — Why It Matters

After PST saves a product configuration, always report `Quote.GrandTotal` to customers:

```apex
Quote q = [
    SELECT GrandTotal, TotalPrice, LineItemCount
    FROM Quote
    WHERE Id = :quoteId
];
// GrandTotal = all BOM component prices + taxes + discounts
// TotalPrice = subtotal before tax
// Do NOT use QuoteLineItem.UnitPrice — it is only the primary product price
```

| Field | Includes |
|---|---|
| `Quote.GrandTotal` | All BOM components + taxes + discounts applied at quote level |
| `Quote.TotalPrice` | Sum of all line item prices before quote-level adjustments and tax |
| `QuoteLineItem.UnitPrice` | Unit price of the primary product only |

---

## Key SOQL Queries

### Outstanding invoices for an account
```soql
SELECT Id, InvoiceNumber, Status, TotalAmount, Balance, DueDate
FROM Invoice
WHERE AccountId = '001...'
  AND Status = 'Posted'
  AND Balance > 0
ORDER BY DueDate ASC
```

### Billing schedules for an order
```soql
SELECT Id, Status, BillingPeriodStartDate, BillingPeriodEndDate, Amount
FROM BillingSchedule
WHERE OrderId = '801...'
ORDER BY BillingPeriodStartDate ASC
```

### Tax interaction log for debugging
```soql
SELECT Id, TaxEngineId, RequestPayload, ResponsePayload, Status, ErrorMessage
FROM TaxEngineInteractionLog
WHERE InvoiceId = '0BL...'
ORDER BY CreatedDate DESC
LIMIT 5
```

---

## Tax Engine Integration — Wiring Guide

Revenue Cloud supports external tax calculation engines. The engine is invoked automatically at invoice posting time.

### Step 1: Create TaxEngine record

```apex
TaxEngine te = new TaxEngine();
te.Name = 'Avalara AvaTax';
te.TaxEngineProviderId = '0BE...';     // ID of the TaxEngineProvider (Apex adapter)
te.MerchantId = 'MY_MERCHANT_001';    // External account identifier
te.IsActive = true;
insert te;
```

### Step 2: Implement TaxEngineAdapter interface (Apex)

```apex
global class AvalaraTaxAdapter implements TaxEngineAdaptor {

    global TaxEngineAdaptor.TaxResponse calculate(
        TaxEngineAdaptor.TaxRequest request
    ) {
        // Build the external API request from request.lines[]
        // Each line has: amount, productCode, quantity, shipFromAddress, shipToAddress
        HttpRequest req = buildAvalaraRequest(request);
        HttpResponse res = new Http().send(req);

        TaxEngineAdaptor.TaxResponse taxResp = new TaxEngineAdaptor.TaxResponse();
        // Parse res.getBody(), populate taxResp.lines[]
        // Each line: taxAmount, taxCode, taxRateApplied
        return taxResp;
    }
}
```

Register the Apex class by creating a `TaxEngineProvider` metadata record:
```bash
sf project deploy start --metadata "ApexClass:AvalaraTaxAdapter" --target-org <alias>
```

### Step 3: Link TaxTreatment to products

```apex
// Create a TaxTreatment for the applicable tax jurisdiction
TaxTreatment tt = new TaxTreatment();
tt.Name = 'US Standard Sales Tax';
tt.TaxPolicyId = taxPolicy.Id;
tt.TaxCode = 'P0000000';              // Tax code passed to the external engine
tt.IsDefault = false;
insert tt;

// Link treatment to a product via TaxTreatmentItem
TaxTreatmentItem tti = new TaxTreatmentItem();
tti.TaxTreatmentId = tt.Id;
tti.ProductId = product.Id;
insert tti;
```

### Step 4: Link TaxEngine to BillingPolicy

```apex
BillingPolicy bp = [SELECT Id FROM BillingPolicy WHERE Name = 'Standard Billing' LIMIT 1];
bp.TaxEngineId = te.Id;
update bp;
```

At invoice posting time, Revenue Cloud invokes `TaxEngineAdapter.calculate()` for each invoice line and stamps the returned tax amounts onto `InvoiceLine.TaxAmount`. The result is visible in `TaxEngineInteractionLog`.

### Debugging tax issues

```soql
SELECT Id, TaxEngineId, RequestPayload, ResponsePayload, Status, ErrorMessage
FROM TaxEngineInteractionLog
WHERE InvoiceId = '0BL...'
ORDER BY CreatedDate DESC
LIMIT 5
```

If `Status = Failed`, check `ErrorMessage` and `RequestPayload` to diagnose what was sent to the external engine.

---

## Common Billing Error Codes

| Error | Cause | Fix |
|---|---|---|
| `BILLING_SCHEDULE_NOT_FOUND` | Order not activated before creating schedules | Activate order first |
| `ACCOUNTING_PERIOD_NOT_ACTIVE` | No active AccountingPeriod for billing date | Create/activate AccountingPeriod |
| `CANNOT_VOID_INVOICE` | Payment applied to invoice | Unapply payment, then void |
| `CREDIT_MEMO_NOT_DRAFT` | Trying to post an already-posted credit memo | Check CreditMemo.Status before posting |
| `SINGLE_EMAIL_LIMIT_EXCEEDED` | Dev/trial org 15 email/day limit | Use sandbox for volume testing |

# Billing — REST API Reference & Key Patterns

> **v68 re-baseline note (2026-09-11):** This file was re-verified against RLM Developer Guide v68.0
> (Winter '27), Ch. 12 → Billing → Standard Invocable Actions (printed pp. 2531–2577) and Business APIs
> (printed pp. 2578+). The prior version assumed a single `/commerce/billing` base path and several
> fabricated action input/output parameter names; both are corrected below.

There is **no single Base URL** for Billing Business APIs — resources are split across four base
paths depending on the resource:
- `/services/data/v68.0/commerce/invoicing/...` — billing schedules, invoices, invoice schedulers,
  most credit-memo operations (the majority of resources).
- `/services/data/v68.0/commerce/billing/...` — credit-memo void, invoice batch-run draft-to-posted,
  invoice batch document generation.
- `/services/data/v68.0/revenue/billing/...` — billing-transaction apply, document generation,
  account statements, unreferenced-refund processing.
- `/services/data/v68.0/connect/sequences/...` — sequence policy, sequence assignment, gap
  reconciliation (invoice/credit-memo numbering).

Always confirm the exact resource path against Ch. 12 → Business APIs before wiring an integration;
do not assume a resource lives under `/commerce/billing` by default.

---

## Billing Schedules

### Create billing schedules from a billing transaction (Business API)
```
POST /services/data/v68.0/commerce/invoicing/billing-schedules/actions/create
Body: { "billingTransactionId": "801..." }
```
This is an **asynchronous** action. Response: `{ "requestId": "...", "statusUrl": "/services/data/v68.0/..." }`
— poll `statusUrl` for completion; the created `BillingSchedule` records are not returned directly in
the initial response.

### Invocable (Flow): Create Billing Schedules From Billing Transaction Action
- URI: `standard/createBillingSchedulesFromBillingTransaction`
- Input: `billingTransactionId` (Text), `executeAsync` (Boolean)
- Output: `requestId` (Text), `statusUrl` (Text)

> **Correction:** The prior version showed a synchronous `billingScheduleIds` (Text Collection)
> output. The action is async — it returns a `requestId`/`statusUrl` pair, not the created schedule
> IDs directly.

### Invocable (Flow): Create Standalone Billing Schedules Action (new coverage)
- URI: `standard/createBillingSchedulesFromTrxn`
- Creates billing schedules directly from a billing transaction without going through the async
  request/status pattern above. Confirmed to exist in the v68 Standard Invocable Actions list;
  exact input/output parameter names were not individually re-verified this pass — consult Ch. 12 →
  Standard Invocable Actions before using it in production Flows.

---

## Invoices

### Post draft invoices (Business API — collection-based)
```
POST /services/data/v68.0/commerce/invoicing/invoices/collection/actions/post
Body: { "invoiceIds": ["0BL...", "0BL..."] }
```
> **Correction:** The prior version showed a per-invoice-ID path
> (`/commerce/billing/invoices/{invoiceId}/post`). The real resource posts a **collection** of draft
> invoices in one call, and lives under `/commerce/invoicing`, not `/commerce/billing`.

### Invocable (Flow): Post Draft Invoice Action
- URI: `standard/postDraftInvoice`
- Input: `invoiceId` (Text)
- This action's exact output parameter names were not independently re-confirmed this pass (the
  batch-run variant below was). Given the async pattern used by its sibling actions, expect a
  `requestIdentifier`/`statusUrl`-style response — verify against Ch. 12 → Standard Invocable Actions
  before relying on a specific output field name.

### Void a posted invoice (Business API)
```
POST /services/data/v68.0/commerce/invoicing/invoices/{invoiceId}/actions/void
```
> **Correction:** Confirmed real resource path uses `/actions/void` (not bare `/void`) and lives under
> `/commerce/invoicing`, not `/commerce/billing`. The request body shape (e.g., a `voidReason` field)
> was not independently verified this pass — annotate as unconfirmed rather than asserting a specific
> body schema.

Note: You generally can't void an invoice with payments applied — unapply payments first via
**Unapply Payment Action** (see Payments section below).

### Generate invoice documents (Business API)
```
POST /services/data/v68.0/commerce/billing/invoices/invoice-batch-docgen/{invoiceBatchRunId}/actions/generate
```

### Invocable (Flow): Generate Invoice Documents Action
- URI: `standard/generateInvoiceDocuments`
- Input: `invoiceBatchRunId` (Text) — NOT a collection of individual invoice IDs
- Output: `requestId` (Text), `requestStatus` (Text)

> **Correction:** The prior version had this action taking an `invoiceIds` collection and returning
> `contentDocumentIds`. The real action operates on an `InvBatchDraftToPostedRun`-style batch run
> (`invoiceBatchRunId`) and returns an async `requestId`/`requestStatus` pair, not content document
> IDs directly.

### Post Draft Invoice Batch Run (Business API)
```
POST /services/data/v68.0/commerce/billing/invoices/invoice-batch-runs/{invoiceBatchRunId}/actions/draft-to-posted
```

### Invocable (Flow): Post Draft Invoice(Batch Run) Action
- URI: `standard/postDraftInvoiceBatchRun`
- Input: `invoiceBatchRunId` (Text)
- Output: `invBatchDraftToPostedRunId` (Text) — a **single** ID referencing the `InvBatchDraftToPostedRun`
  tracking record, not a collection of posted invoice IDs.

> **Correction:** The prior version's output name `postedInvoiceIds` (Text Collection) does not match
> the documented API — the action returns one `invBatchDraftToPostedRunId`, and the individual posted
> invoices are tracked via that run record, not returned inline.

---

## Credit Memos

### Issue a credit memo from an invoice
Invocable (Flow): **Issue Credit Memo Action**
- URI: `standard/blngDsptIssueCreditMemo`
- Input: `creditRequestList` — an **Apex-defined** collection type (see Apex Reference, `IssueCreditMemo`
  class, printed p. 2923), not simple scalars
- Output: `creditResponse` — also Apex-defined (success/message shape)

> **Correction:** The prior version documented simple scalar inputs (`invoiceId`, `creditReason`,
> `lines[]`) and a scalar `creditMemoId` output. The real action's input/output are Apex-defined types
> from the `IssueCreditMemo` Apex class, not ad hoc scalars — the exact sub-field names of
> `creditRequestList`/`creditResponse` were not individually re-confirmed this pass; consult the Apex
> Reference class before building a Flow/Apex call against this action.

### Post a draft credit memo
Invocable (Flow): **Post Draft Credit Memo Action**
- URI: `standard/postDraftCreditMemo`
- Input: `correlationId` (Text), `creditMemoId` (Text)
- Output: `requestIdentifier` (Text), `statusUrl` (Text) — async, same pattern as invoice posting

> **Correction:** The prior version showed only a `creditMemoId` input with no output. This is an
> asynchronous action; it also accepts a `correlationId` and returns a `requestIdentifier`/`statusUrl`
> pair to poll.

### Apply a credit memo to invoices
Invocable (Flow): **Apply Credit Action**
- URI: `standard/applyCredit`
- Input: `appliedCreditAmount` (Number), `creditSourceRecordId` (Text), `creditTargetRecordId` (Text),
  `description` (Text), `effectiveDate` (Date)
- Output: `recordId` (Text)

> **Correction:** The prior version documented a bulk `creditMemoId` + `invoiceIds` (collection) shape
> returning `applicationIds` (collection). The real action applies a single credit amount from one
> source record (e.g., a `CreditMemo`) to one target record (e.g., an `Invoice`) per call, and returns
> a single `recordId` (the resulting application record) — it is not a bulk apply-to-many-invoices
> action.

### Void a posted credit memo
Business API:
```
POST /services/data/v68.0/commerce/billing/credit-memos/{creditMemoId}/actions/void
```
Invocable (Flow): **Void Posted Credit Memo Action**
- URI: `standard/voidPostedCreditMemo`
- Input: `creditMemoId` (Text)
- Output: `debitMemoId` (Text), `statusUrl` (Text)

> **Correction:** The prior version listed no output. Voiding a posted credit memo generates an
> offsetting `DebitMemo` — the action returns that new `debitMemoId` plus a `statusUrl` for the
> underlying async operation.
>
> **Disambiguation:** Do not confuse this with voiding an **invoice** (see Invoices section above,
> `/commerce/invoicing/invoices/{invoiceId}/actions/void`) — they are separate resources for separate
> object types (`Invoice` vs `CreditMemo`).

---

## Payments

### Apply payments and credits by rules
Invocable (Flow): **Apply Payments and Credits by Rules Action**
- URI: `standard/applyPaymentsAndCreditsByRules`
- Input: `accountId` (Text), `targetDate` (Date)
- Output: `rulesApplicationResponse` — Apex-defined (see Apex Reference, `RulesAppln` class, printed
  p. 2931)

> **Correction:** The prior version documented `paymentId` + `invoiceIds` (collection) inputs
> returning `paymentLineInvoiceIds` (collection). The real action operates at the **account** level
> for a given target date — Salesforce's rules engine determines which payments/credits apply to
> which invoices, rather than the caller specifying a payment ID and invoice list directly. The
> response is an Apex-defined `rulesApplicationResponse`, not a plain ID collection.

### Unapply a payment
Invocable (Flow): **Unapply Payment Action**
- URI: `standard/unapplyPayment`
- Input: `description` (Text), `effectiveDateTime` (DateTime), `recordId` (Text — ID of the
  `PaymentLineInvoice`/`PaymentLineInvoiceLine` application record to unapply)
- Output: `recordId` (Text), `unappliedDateTime` (DateTime)

> **Correction:** The prior version's input name `paymentLineInvoiceId` does not match the documented
> parameter name `recordId`, and no output was documented — the action returns the same `recordId`
> plus the `unappliedDateTime`.

### Unapply a credit
Invocable (Flow): **Unapply Credit Action**
- URI: `standard/unapplyCredit`
- Input: `effectiveDate` (Date), `description` (Text), `recordId` (Text — ID of the credit application
  record to unapply)
- Output: `recordId` (Text)

> **Correction:** The prior version's input name `creditMemoInvApplicationId` does not match the
> documented parameter name `recordId`.

---

## Write-offs

### Write off uncollectible invoices
Invocable (Flow): **Write Off Invoices Action**
- URI: `standard/writeOffInvoices`
- **HTTP Method: GET** — unusual for an action with inputs; confirmed as documented rather than the
  POST used by the other actions in this file. Double-check this against your org's actual metadata
  before assuming it's not a documentation quirk.
- Input: `writeOffInvoiceInputList` — Apex-defined collection type (see Apex Reference,
  `InvoiceWriteOff` class, printed p. 2914), not simple scalars
- Output: `writeOffInvoiceResponseList` — also Apex-defined

> **Correction:** The prior version documented scalar inputs (`invoiceIds` collection, `writeOffReason`,
> `accountingPeriodId`) and claimed the action "creates `GeneralLedgerAcctAsgntRule` entries." Neither
> the scalar input shape nor the `GeneralLedgerAcctAsgntRule`-creation claim was found in this action's
> own documented description — the real input/output are Apex-defined types from the
> `InvoiceWriteOff` class. The `GeneralLedgerAcctAsgntRule` claim is **annotated as unverified** rather
> than repeated; if your org relies on that side effect, confirm it against your own testing/release
> notes rather than this reference.

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

> **Annotation (unverified this pass):** The `Invoice` and `BillingSchedule` field names below
> (`InvoiceNumber`, `Balance`, `BillingPeriodStartDate`, `BillingPeriodEndDate`, etc.) were carried
> over from the prior version of this file and were **not independently re-verified** against the
> Ch. 12 → Fields on Standard Objects tables during this v68 pass (unlike `TaxEngineInteractionLog`
> below, which was fully re-verified and is corrected). Treat these two queries as illustrative until
> confirmed against RLM Developer Guide v68.0, Ch. 12 → Standard Objects → Invoice / BillingSchedule.

### Outstanding invoices for an account (illustrative — see annotation above)
```soql
SELECT Id, InvoiceNumber, Status, TotalAmount, Balance, DueDate
FROM Invoice
WHERE AccountId = '001...'
  AND Status = 'Posted'
  AND Balance > 0
ORDER BY DueDate ASC
```

### Billing schedules for an order (illustrative — see annotation above)
```soql
SELECT Id, Status, BillingPeriodStartDate, BillingPeriodEndDate, Amount
FROM BillingSchedule
WHERE OrderId = '801...'
ORDER BY BillingPeriodStartDate ASC
```

### Tax interaction log for debugging (corrected — see Tax Engine Wiring Guide below for field verification)
```soql
SELECT Id, TaxEngineId, DocumentCode, ReferenceEntity, ResultCode, RequestBody, RequestContentType
FROM TaxEngineInteractionLog
WHERE ReferenceEntity = '0BL...'
ORDER BY CreatedDate DESC
LIMIT 5
```

---

## Tax Engine Integration — Wiring Guide

Revenue Cloud supports external tax calculation engines. The engine is invoked automatically at invoice posting time.

> **v68 re-baseline note:** This section was re-verified field-by-field against RLM Developer Guide
> v68.0, Ch. 12 → Standard Objects → TaxEngine, TaxEngineProvider, TaxPolicy, TaxTreatment,
> TaxTreatmentItem, TaxEngineInteractionLog (printed pp. 2454–2472), and Ch. 12 → Apex Reference →
> TaxEngineAdapter Interface (printed p. 2940). Several field names below were fabricated in the
> prior version and are corrected; `TaxEngineAdaptor` is renamed to `TaxEngineAdapter` throughout
> (contradiction #4 in the v68 grounding memo).

### Step 1: Create TaxEngine record

```apex
TaxEngine te = new TaxEngine();
te.TaxEngineName = 'Avalara AvaTax';      // NOT Name — the field is TaxEngineName
te.TaxEngineProviderId = provider.Id;      // ID of the TaxEngineProvider record
te.MerchantCredentialId = namedCredential.Id;  // NOT a string MerchantId — this is a reference
                                                 // field to a Named Credential (merchant setup)
te.Status = 'Active';                      // NOT a boolean IsActive — Status is a picklist
                                            // (Active | Inactive)
insert te;
```

> **Correction:** `TaxEngine` has no `Name`, `MerchantId`, or `IsActive` field. The real fields are
> `TaxEngineName` (string), `MerchantCredentialId` (reference to `NamedCredential`, relationship name
> `MerchantCredential`), and `Status` (restricted picklist: `Active`/`Inactive`). `TaxEngine` also has
> a `Type` picklist (`CommerceTaxExtension` | `RevenueCloudTaxExtension` | `StandardTaxEngine` |
> `RevenueStandardTaxEngine` | `StripeNative`) that isn't set in this minimal sample but is required
> for real deployments — set it to match your integration approach.

### Step 2: Implement TaxEngineAdapter interface (Apex)

```apex
global class AvalaraTaxAdapter implements TaxEngineAdapter {

    global TaxEngineAdapter.TaxResponse calculate(
        TaxEngineAdapter.TaxRequest request
    ) {
        // Build the external API request from request.lines[]
        // Each line has: amount, productCode, quantity, shipFromAddress, shipToAddress
        HttpRequest req = buildAvalaraRequest(request);
        HttpResponse res = new Http().send(req);

        TaxEngineAdapter.TaxResponse taxResp = new TaxEngineAdapter.TaxResponse();
        // Parse res.getBody(), populate taxResp.lines[]
        // Each line: taxAmount, taxCode, taxRateApplied
        return taxResp;
    }
}
```

> **Correction:** Renamed `TaxEngineAdaptor` → `TaxEngineAdapter` throughout (the v68 guide's Apex
> Reference titles it "TaxEngineAdapter Interface," printed p. 2940 — see grounding memo
> contradiction #4). The inner `TaxRequest`/`TaxResponse` type names and the `lines[]` sub-field names
> (`amount`, `productCode`, `quantity`, `shipFromAddress`, `shipToAddress`, `taxAmount`, `taxCode`,
> `taxRateApplied`) were not individually re-confirmed against the interface's own member list this
> pass — verify signatures against the Apex Reference page before implementing.

Register the Apex class with a `TaxEngineProvider` record so the platform knows which adapter to invoke:
```apex
TaxEngineProvider provider = new TaxEngineProvider();
provider.DeveloperName = 'Avalara_AvaTax_Provider';
provider.MasterLabel = 'Avalara AvaTax Provider';
provider.ApexAdapterId = [SELECT Id FROM ApexClass WHERE Name = 'AvalaraTaxAdapter'].Id;
insert provider;
```
```bash
sf project deploy start --metadata "ApexClass:AvalaraTaxAdapter" --target-org <alias>
```

> **Correction:** The prior version said to "register the Apex class by creating a `TaxEngineProvider`
> metadata record" but didn't show the actual link. The real wiring field is
> `TaxEngineProvider.ApexAdapterId` — a reference field to `ApexClass` (relationship name
> `ApexAdapter`). Deploying the class alone does not register it; you must also set this field on a
> `TaxEngineProvider` record.

### Step 3: Link TaxTreatment to products

```apex
// Create a TaxTreatment for the applicable tax jurisdiction
TaxTreatment tt = new TaxTreatment();
tt.Name = 'US Standard Sales Tax';
tt.TaxPolicyId = taxPolicy.Id;
tt.TaxCode = 'P0000000';              // Tax code passed to the external engine
tt.IsTaxable = true;                  // Required field — determines whether CalculateTax is invoked
                                       // for order items covered by this treatment
tt.TaxEngineId = te.Id;               // The tax engine used when calculating tax for this treatment
                                       // (see Step 4 correction below — this is where TaxEngine links in,
                                       // NOT on BillingPolicy)
insert tt;

// Link treatment to a product via TaxTreatmentItem
TaxTreatmentItem tti = new TaxTreatmentItem();
tti.Name = 'US Standard Sales Tax — Widget';
tti.TaxTreatmentId = tt.Id;
tti.ProductCode = product.ProductCode;
insert tti;
```

> **Correction:** `TaxTreatment` has no `IsDefault` field — that concept lives on `TaxPolicy`
> (`TaxPolicy.DefaultTaxTreatmentId`, a reference *to* a `TaxTreatment`), not as a flag *on*
> `TaxTreatment` itself. The required field to set instead is `IsTaxable` (boolean). Also,
> `TaxTreatmentItem`'s confirmed fields in the pages read this pass are `Description`,
> `LastReferencedDate`, `LastViewedDate`, `Name`, and `ProductCode` — its field table continues past
> the page range read this session, so a direct `TaxTreatmentItem.ProductId` reference field (used in
> the prior version) is **plausible but not independently confirmed**; `ProductCode` (string) is
> confirmed and used above instead. Verify `ProductId`/`TaxTreatmentId` against Ch. 12 → Standard
> Objects → Tax Treatment Item (printed p. 2470 onward) before relying on either field name.

### Step 4: Link TaxEngine to TaxTreatment

```apex
TaxTreatment tt2 = [SELECT Id FROM TaxTreatment WHERE Name = 'US Standard Sales Tax' LIMIT 1];
tt2.TaxEngineId = te.Id;
update tt2;
```

> **Correction:** The prior version of this step set a `BillingPolicy.TaxEngineId` field —
> **no such field was found on `BillingPolicy`** in the v68 Standard Objects section. The confirmed,
> documented linkage is `TaxTreatment.TaxEngineId` (a real reference field on `TaxTreatment`, refers
> to `TaxEngine`) — the tax engine is selected per tax treatment, not per billing policy. This step
> has been rewritten accordingly; if your org's `BillingPolicy` object does carry a custom or
> newer-than-verified `TaxEngineId`-style field, confirm it directly rather than relying on this file.

At invoice posting time, Revenue Cloud invokes `TaxEngineAdapter.calculate()` for each invoice line (via
the order item's `TaxTreatment.TaxEngineId`) and stamps the returned tax amounts onto the invoice line.
The result of each callout is logged to `TaxEngineInteractionLog`.

### Debugging tax issues

```soql
SELECT Id, TaxEngineId, DocumentCode, ReferenceEntity, ResultCode, InteractionHttpStatusCode
FROM TaxEngineInteractionLog
WHERE ReferenceEntity = '0BL...'
ORDER BY CreatedDate DESC
LIMIT 5
```

If `ResultCode` is not `Success` (valid values: `AdapterException`, `ReferenceDocumentCodeMissing`,
`Success`, `TaxEngineError`, `ValidationError`), decode the base64 `RequestBody` field and check
`InteractionHttpStatusCode` to diagnose what was sent to the external engine and how it responded.

> **Correction:** `TaxEngineInteractionLog` has no `RequestPayload`, `ResponsePayload`, `Status`, or
> `ErrorMessage` field, and no `InvoiceId` field to filter on. The real fields are `RequestBody`
> (base64, not `RequestPayload`), `ResultCode` (restricted picklist, not a free-text `Status`/
> `ErrorMessage`), `ReferenceEntity` (string — "the record on which tax was calculated," used in place
> of a relationship field like `InvoiceId`), `DocumentCode`, and `InteractionHttpStatusCode`. There is
> no dedicated `ErrorMessage` field — diagnosing a failure means inspecting `ResultCode` plus the
> base64-encoded `RequestBody`/response content type fields.

---

## Common Billing Error Codes

> **Annotation (unverified this pass):** The error codes below are illustrative examples carried over
> from the prior version of this file. A specific "Billing error codes" reference table was not
> located in RLM Developer Guide v68.0, Ch. 12 during this pass (error/fault information for these
> APIs is more likely surfaced as generic REST/Connect API fault codes at call time). Treat this table
> as indicative of common failure scenarios, not as a verified, exhaustive, or exact-string API
> contract — confirm exact error codes against your org's actual API responses.

| Error | Cause | Fix |
|---|---|---|
| `BILLING_SCHEDULE_NOT_FOUND` | Order not activated before creating schedules | Activate order first |
| `ACCOUNTING_PERIOD_NOT_ACTIVE` | No active AccountingPeriod for billing date | Create/activate AccountingPeriod |
| `CANNOT_VOID_INVOICE` | Payment applied to invoice | Unapply payment, then void |
| `CREDIT_MEMO_NOT_DRAFT` | Trying to post an already-posted credit memo | Check CreditMemo.Status before posting |
| `SINGLE_EMAIL_LIMIT_EXCEEDED` | Dev/trial org 15 email/day limit | Use sandbox for volume testing |

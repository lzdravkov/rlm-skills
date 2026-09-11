# Transaction Management — API Patterns

Base URL: `https://{instance}.salesforce.com/services/data/v68.0`

> **v68 re-baseline note:** every `/commerce/sales-transactions`, `/commerce/orders/fromQuote`, and
> `/commerce/assets/{id}/{amendment|renewal|cancellation|transfer|rollback}` path in the previous
> version of this file was fabricated — none of those resources exist in the v68 Business API
> resource inventory. All paths below have been corrected against RLM Developer Guide (v68,
> Winter '27) — Chapter 8: Transaction Management › Business API Resources and › Standard Invocable
> Actions.

---

## Place Sales Transaction — Business API

### Create or update a sales transaction (quote/order)
```
POST /connect/rev/sales-transaction/actions/place
Body:
{
  "salesTransaction": {
    "id": "0Q0...",           // existing quote ID (omit for new)
    "type": "Quote",
    "opportunityId": "006...",
    "priceBookId": "01s...",
    "lineItems": [
      {
        "id": "0QL...",       // existing line item ID (omit for new)
        "productId": "01t...",
        "quantity": 1,
        "sellingModelId": "0PG...",
        "attributes": [
          {
            "name": "requiredKW",
            "value": "1500",
            "dataType": "Number"
          },
          {
            "name": "DutyRating",
            "value": "Data Center Continuous (DCC)",
            "picklistValueId": "0UZ...",
            "dataType": "Picklist"
          }
        ]
      }
    ]
  },
  "options": {
    "applyBomRules": true,
    "applyPricing": true
  }
}
```

**Important**: PST does NOT return created record IDs. Query for them after the call.

Related "Place" family resources (v68 confirmed, not yet exercised by this skill's examples —
annotated for completeness rather than fully worked through):
- `POST /connect/rev/sales-transaction/actions/clone` — Clone Sales Transaction
- `POST /connect/rev/sales-transaction/actions/place-supplemental-transaction` — Place Supplemental Transaction
- `POST /connect/revenue/transaction-management/sales-transactions/actions/read` — Read Sales Transaction
- `POST /commerce/sales-orders/actions/place` — Place Order
- `POST /commerce/quotes/actions/place` — Place Quote

### quoteLineItemId Retrieval After PST
```apex
QuoteLineItem qli = [
    SELECT Id
    FROM QuoteLineItem
    WHERE QuoteId = :quoteId
    AND Product2.Name LIKE :productNamePattern
    ORDER BY CreatedDate DESC
    LIMIT 1
];
String quoteLineItemId = qli.Id; // 0QL...
```

---

## Quote-to-Order — Standard Invocable Action

There is no dedicated `/commerce/orders/fromQuote` Business API — quote-to-order conversion is a
Standard Invocable Action, reachable via the generic Actions REST API.

### Create Orders From Quote (current, non-deprecated)
```
POST /services/data/v68.0/actions/standard/createOrdersFromQuote
Body:
{
  "inputs": [
    {
      "quoteId": "0Q0DU0000005tJc0AI",
      "quoteLineItemIds": ["0QLDU000000ay2G4AQ"],   // optional — omit to convert all lines
      "orderCreationMethod": "CreateSingleOrder"     // or CreateOrderByGroup | CreateOrderByField
    }
  ]
}
```
Response: `outputValues: { "orderIds": ["801..."], "requestId": "...", "statusUrl": "..." }`
(order header created synchronously; line items async when splitting into multiple orders)

Requires the **Advanced Order Creation From Quote** toggle in Revenue Settings
(`RevenueManagementSettings.enableAdvCreateOrdersFromQuote`). Avail API v65.0+.

### Create Order From Quote (Invocable Action — legacy, deprecated v65.0+)
```
POST /services/data/v68.0/actions/standard/createOrderFromQuote
Body: { "inputs": [ { "quoteRecordId": "0Q0D200000000DhKAI" } ] }
```
Response: `outputValues: { "orderId": "801...", "orderNumber": "00000122" }`

> **Deprecated as of API v65.0** — "In API version 65.0 and later, use the Create Orders From Quote
> Action." Keep only for orgs pinned below v65.0.

---

## Asset Lifecycle — Standard Invocable Actions + Business API

| Action | Invocable Action (`/actions/standard/<name>`) | Business API |
|---|---|---|
| Amendment | `initiateAmendment` | `POST /connect/revenue-management/assets/actions/amend` |
| Renewal | `initiateRenewal` | `POST /connect/revenue-management/assets/actions/renew` |
| Cancellation | `initiateCancellation` | `POST /connect/revenue-management/assets/actions/cancel` |
| Transfer | `initiateTransfer` | *(none found — invocable action only)* |
| Rollback | `initiateRollBackLastAction` | *(none found — invocable action only)* |

All actions return a `Quote` or `Order` record ID (per the action's `*OutputType`/`outputType`
input) for the resulting amendment/renewal/cancellation/transfer/rollback transaction — **not** a
flat `quoteId` field as previously documented.

### Initiate Amendment — request body
```json
{
  "inputs": [
    {
      "amendAssetIds": ["02iI8000000HPzXIAW"],
      "amendStartDate": "2023-10-21T00:00:00.000Z",
      "quantityChange": 5,
      "amendOutputType": "Quote",
      "amendContractId": "800DU0000001Z1YAI",
      "amendOpportunityId": "006DU0000025AanYAE",
      "skipPricing": false
    }
  ]
}
```
Response: `outputValues: { "record_id": "0Q0...", "requestIdentifier": "16P..." }`

> For usage products, creating an order directly (`amendOutputType: "Order"`) is **not supported** —
> it can create Order Products without required Rate Card Entry records, which can cause order
> activation to fail. Use the 2-step flow: amend to `Quote`, then convert the amendment quote to
> an order.

### Initiate Renewal — request body
```json
{
  "inputs": [
    {
      "renewAssetIds": ["02ixx0000004LMwAAM"],
      "renewOutputType": "Quote",
      "renewContractId": "800DU00000001Z1YAI",
      "renewOpportunityId": "006DU0000025AanYAE",
      "renewStartDate": "2023-10-21T00:00:00.000Z",
      "renewEndDate": "2024-10-21T00:00:00.000Z",
      "skipPricing": false,
      "rampOptionsDetails": { "segmentType": "Custom", "duration": 40, "numberOfSegments": 10 }
    }
  ]
}
```
Response: `outputValues: { "renewRecordId": "0Q0...", "requestIdentifier": "16P..." }`

### Initiate Cancellation — request body
```json
{
  "inputs": [
    {
      "cancelAssetIds": ["02iI8000000Lc5fIAC"],
      "cancelStartDate": "2023-11-09T00:00:00",
      "cancelOutputType": "Quote",
      "cancelContractId": "800DU00000001Z1YAI",
      "cancelOpportunityId": "006DU0000025AanYAE",
      "skipPricing": false
    }
  ]
}
```
Response: `outputValues: { "record_id": "0Q0...", "requestIdentifier": "16P..." }`

### Initiate Transfer — request body
Generates **2** quotes/orders: a negative-quantity source transaction and a positive-quantity
target transaction. Transfer completes once both are assetized.
```json
{
  "inputs": [
    {
      "transferRecords": [ { "assetId": "02ixx0000004HZbAAM", "transferQuantity": 1 } ],
      "transferDate": "2025-10-21T00:00:00.000Z",
      "targetAccountId": "001xx000003GbeXAAS",
      "targetContractId": "800DU00000001Z1YAI",
      "outputRecordType": "Quote"
    }
  ]
}
```
Response: `outputValues: { "assetTransferSourceId": "0Q0...", "assetTransferTargetId": "0Q0..." }`

### Initiate Rollback on Last Action — request body
Reverts the last amendment or renewal only (not cancellation or transfer); future-dated
transactions only; not supported for legacy assets.
```json
{
  "inputs": [
    { "assetIds": ["02iDU0000006UisYAE"], "outputType": "Quote" }
  ]
}
```
Response: `outputValues: { "recordId": "0Q0..." }`

### Get Renewable Assets Summary (Invocable — Flow / Actions REST)
```
POST /services/data/v68.0/actions/standard/getRenewableAssetsSummary
Body: { "inputs": [ { "orderId": "801xx000003GZ39AAG" } ] }
```
Response `outputValues.renewableAssetsSummary[]` entries (Apex-defined, backed by
`renew_assets_summary.RenewalOpptyDetail`):
```json
{
  "startDate": "2025-07-22",
  "endDate": "2025-08-21",
  "assetId": "02ixx0000004HKwAAM",
  "account": "001xx000003GZ1XAAW",
  "productId": "01txx0000006i3DAAQ",
  "priceBookId": "01sxx0000005ptpAAA",
  "priceBookEntryId": "01uxx0000008yXCAAY",
  "orderItem": "802xx000001nb1LAAQ",
  "opportunityProductId": null,
  "lastAssetActionSubtype": null,
  "lastAssetAction": "Initial Sale",
  "rootAssetOpportunity": null,
  "renewalPriceDetails": [ { "quantity": 1, "netUnitPrice": 0 } ]
}
```
> **Correction:** there is no `productName`, `currentTermEndDate`, or `renewalStatus` field — those
> were fabricated in the prior version of this file. Use `startDate`/`endDate`/`lastAssetAction`.

---

## Platform Events — Subscription Patterns

### Subscribe via Apex Trigger
```apex
trigger QuoteSaveEventTrigger on QuoteSaveEvent (after insert) {
    for (QuoteSaveEvent event : Trigger.new) {
        String quoteId = event.QuoteId;
        // Post-processing logic here
    }
}
```

### Subscribe via Flow
Use `Platform Event–Triggered Flow` with entry object = `QuoteSaveEvent`.

### Available Events (field lists confirmed against v68 Platform Events reference)

| Event | When Fired | Key Fields |
|---|---|---|
| `QuoteSaveEvent` (60.0+) | After every quote save | `CorrelationIdentifier`, `EventUuid`, `HasErrors`, `QuoteId`, `ReplayId`, `RequestIdentifier` |
| `PlaceOrderCompletedEvent` (63.0+) | After order created from quote | `AppUsageTypes`, `CorrelationIdentifier`, `EventUuid`, `HasErrors`, `OrderId`, `ReplayId`, `RequestIdentifier` |
| `QuoteToOrderCompletedEvent` (56.0+) | After quote-to-order conversion | `CorrelationIdentifier`, `EventUuid`, `HasErrors`, `OrderId`, `OrderNumber`, `ReplayId`, `RequestIdentifier` |
| `CreateAssetOrderEvent` (55.0+) | After asset creation from order | `AssetDetails` (nested `CreateAssetOrderDtlEvent[]`), `CorrelationIdentifier`, `EventUuid`, `IsLastEvent` (62.0+), `OrderIdentifier` (64.0+), `ReplayId`, `RequestIdentifier` |

> **Correction:** `CreateAssetOrderEvent` does **not** have flat `AssetId`/`OrderId` fields as
> previously documented — the per-asset detail (`AssetId`, `OrderItemId`, `IsSuccess`, `ErrorCode`,
> `ErrorMessage`) lives on the nested `CreateAssetOrderDtlEvent` records inside `AssetDetails`, and
> the order-level field is named `OrderIdentifier`, not `OrderId`. See
> `rlm-assets/references/asset-object-reference.md`.

---

## RevSalesTrxn Apex Namespace — Key Classes

| Class / Enum | Purpose |
|---|---|
| `RevSalesTrxn.PlaceSalesTransactionExecutor` | Execute PST (save attributes, BOM, pricing) — multiple `execute()` overloads accept `GraphRequest`, `PricingPreferenceEnum`, `ConfigurationExecutionEnum`, `ConfigurationOptionsInput`, and optionally `TaxPreferenceEnum`/`PersistPreferenceEnum`/`GroupRampActionEnum` |
| `RevSalesTrxn.GraphRequest` | Container for the full quote/order graph (replaces `SalesTransactionGraph`, which was not found as a real class name) |
| `RevSalesTrxn.PlaceSalesTransactionResponse` | Response wrapper returned by `execute()` |
| `RevSalesTrxn.RecordResource` / `RecordWithReferenceRequest` | Record-level input/output shapes within the graph |
| `RevSalesTrxn.PricingPreferenceEnum` | `Force` \| `Skip` \| `System` |
| `RevSalesTrxn.ConfigurationExecutionEnum` | `Force` \| `Skip` \| `System` |
| `RevSalesTrxn.CatalogRatesPreferenceEnum` | `Fetch` \| `Skip` |
| `RevSalesTrxn.TaxPreferenceEnum` | avail 65.0+ |
| `RevSalesTrxn.PersistPreferenceEnum` | `Skip`; avail 65.0+ |
| `RevSalesTrxn.GroupRampActionEnum` | `AddProducts` \| `DeleteProducts` \| `EditGroup` \| `EditRampSchedule` \| `DeleteSegment` \| `ConvertToNonRampedGroup` |

> **Correction:** the previous `RevSalesTrxn.SalesTransactionMode` (`SYSTEM`/`USER`/`API`) class was
> not found in the v68 Apex Reference — real execution-mode control is via the enum parameters above
> (`PricingPreferenceEnum`, `ConfigurationExecutionEnum`, etc.), not a single mode class. Annotated
> rather than silently deleted in case it exists under a name not covered by the sections reviewed.
>
> **Deprecation note:** `CommerceOrders` and `PlaceQuote` namespaces are deprecated as of API v63.0
> in favor of `RevSalesTrxn` — do not use them for new code.

See RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Apex Reference ›
RevSalesTrxn Namespace for the full namespace reference.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Use SOQL to retrieve quoteLineItemId after PST | PST does not return created record IDs |
| Use Quote.GrandTotal not QuoteLineItem.UnitPrice | GrandTotal includes full BOM, discounts, taxes |
| Two-step PST for mixed Number+Picklist attributes | Single call silently overrides Number values |
| versionString: "1.0.0" for generateAiAgentResponse | "2.0.0" requires dataTypeMappings, unsupported by legacy Bots |
| Use `createOrdersFromQuote` over `createOrderFromQuote` | Latter deprecated as of API v65.0 |

# Transaction Management — API Patterns

Base URL: `https://{instance}.salesforce.com/services/data/v66.0`

---

## Place Sales Transaction — Business API

### Create or update a sales transaction (quote/order)
```
POST /commerce/sales-transactions
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

## Quote-to-Order — Business API

### Convert quote to order
```
POST /commerce/orders/fromQuote
Body: { "quoteId": "0Q0..." }
```
Response: `{ "orderId": "801..." }`

### Create Order From Quote (Invocable Action — Flow)
Action API Name: `CreateOrderFromQuoteAction`

Input: `quoteId` (Text)
Output: `orderId` (Text)

---

## Asset Lifecycle — Business API

| Action | Endpoint |
|---|---|
| Amendment | `POST /commerce/assets/{assetId}/amendment` |
| Renewal | `POST /commerce/assets/{assetId}/renewal` |
| Cancellation | `POST /commerce/assets/{assetId}/cancellation` |
| Transfer | `POST /commerce/assets/{assetId}/transfer` |
| Rollback | `POST /commerce/assets/{assetId}/rollback` |

All lifecycle endpoints return a new `quoteId` for the resulting amendment/renewal/cancellation quote.

### Renewal request body
```json
{
  "renewalTerm": 12,
  "renewalTermUnit": "Months",
  "startDate": "2027-01-01"
}
```

### Get Renewable Assets Summary (Invocable — Flow)
Action API Name: `GetRenewableAssetsSummaryAction`

Input: `accountId` (Text) or `assetIds` (Text Collection)
Output: JSON array of `{ assetId, productName, currentTermEndDate, renewalStatus }`

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

### Available Events

| Event | When Fired | Key Fields |
|---|---|---|
| `QuoteSaveEvent` | After every quote save | `QuoteId`, `AccountId`, `OpportunityId` |
| `PlaceOrderCompletedEvent` | After order created from quote | `OrderId`, `QuoteId` |
| `QuoteToOrderCompletedEvent` | After quote-to-order conversion | `OrderId`, `QuoteId` |
| `CreateAssetOrderEvent` | After asset creation from order | `AssetId`, `OrderId` |

---

## RevSalesTrxn Apex Namespace — Key Classes

| Class | Purpose |
|---|---|
| `RevSalesTrxn.PlaceSalesTransactionExecutor` | Execute PST (save attributes, BOM, pricing) |
| `RevSalesTrxn.SalesTransactionGraph` | Container for the full quote/order graph |
| `RevSalesTrxn.SalesTransactionMode` | SYSTEM, USER, API modes for execution context |

See RLM Developer Guide p. 1615 for full namespace reference.

---

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Use SOQL to retrieve quoteLineItemId after PST | PST does not return created record IDs |
| Use Quote.GrandTotal not QuoteLineItem.UnitPrice | GrandTotal includes full BOM, discounts, taxes |
| Two-step PST for mixed Number+Picklist attributes | Single call silently overrides Number values |
| versionString: "1.0.0" for generateAiAgentResponse | "2.0.0" requires dataTypeMappings, unsupported by legacy Bots |

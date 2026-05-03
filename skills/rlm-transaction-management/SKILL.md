---
name: rlm-transaction-management
description: Create and manage Salesforce Revenue Cloud quotes, orders, and asset lifecycle actions including amendment, renewal, cancellation, transfer, and rollback (RLM v66). Use when creating quotes, adding line items, converting quotes to orders, or managing asset subscriptions. Do NOT use for product attribute configuration (use rlm-product-configurator) or invoice generation (use rlm-billing). Triggers on: "create quote", "add line item", "convert to order", "create order", "asset", "amendment", "renewal", "cancellation", "transfer", "rollback", "quote line item", "sales transaction", "place order", "quote save", "subscription lifecycle".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Transaction Management

## Instructions

### Step 1: Identify the transaction task
- **Quote creation**: Create Opportunity → Quote → QuoteLineItem via APIs or Apex
- **Order creation**: Convert Quote to Order via `Create Order From Quote Action` or Business API
- **Asset lifecycle**: Amendment, Renewal, Cancellation, Transfer, Rollback of existing assets
- **PST / quoting API**: Use `RevSalesTrxn` namespace for atomic quote operations
- **Event-driven**: Subscribe to `QuoteSaveEvent`, `PlaceOrderCompletedEvent` platform events

### Step 2: Create a quote and add a line item
Standard object path: `Opportunity → Quote → QuoteLineItem`

Key fields on Quote:
- `OpportunityId` (required lookup)
- `Status` — Draft, Needs Review, Approved, Rejected, Presented, Accepted
- `Pricebook2Id` — must match the PriceBookEntry used by line items
- `ExpirationDate`

Key fields on QuoteLineItem:
- `QuoteId`, `PricebookEntryId`, `Quantity`, `UnitPrice`
- `ProductSellingModelId` — links to the selling model (One-Time, Term, Evergreen)

After inserting a QuoteLineItem for a configurable product, use PST to apply attributes and BOM. See `rlm-product-configurator` skill.

### Step 3: Use the PST Business API to place a sales transaction
For complex quote operations (attribute configuration, BOM, pricing), use the Transaction Management Business API:

```
POST /services/data/v66.0/commerce/sales-transactions
```

Request body includes the full sales transaction graph: quote header + line items + attributes.

Or via Apex (`RevSalesTrxn` namespace):
```apex
RevSalesTrxn.PlaceSalesTransactionExecutor.execute(graph, SYSTEM, SYSTEM, options, null);
```

### Step 4: Convert a quote to an order
Use the `Create Order From Quote Action` invocable action in a Flow:

Input: `quoteId`
Output: `orderId`

Or use the Business API:
```
POST /services/data/v66.0/commerce/orders/fromQuote
Body: { "quoteId": "0Q0..." }
```

For advanced multi-order scenarios, enable `RevenueManagementSettings.enableAdvCreateOrdersFromQuote = true`.

### Step 5: Asset lifecycle actions
After an order is fulfilled, assets are created from order items. Manage asset lifecycle via invocable actions or Business API:

| Action | Invocable | Business API |
|---|---|---|
| Amendment | `Initiate Amendment Action` | `POST /commerce/assets/{id}/amendment` |
| Renewal | `Initiate Renewal Action` | `POST /commerce/assets/{id}/renewal` |
| Cancellation | `Initiate Cancellation Action` | `POST /commerce/assets/{id}/cancellation` |
| Transfer | `Initiate Transfer Action` | `POST /commerce/assets/{id}/transfer` |
| Rollback | `Initiate Rollback on Last Action` | `POST /commerce/assets/{id}/rollback` |

Each lifecycle action creates a new Quote with the appropriate `QuoteAction` record (Amendment, Renewal, etc.).

### Step 6: Get renewable assets summary
Before initiating a renewal, use `Get Renewable Assets Summary Action` to check asset status:

Input: `accountId` or list of `assetIds`
Output: `renewableAssets[]` with `AssetId`, `CurrentTermEndDate`, `RenewalStatus`

### Step 7: Platform events for quote lifecycle
Subscribe to these events in Flows or Apex triggers for post-processing:

- `QuoteSaveEvent` — fired after every quote save; contains `quoteId`, `accountId`
- `PlaceOrderCompletedEvent` — fired after order creation from quote
- `QuoteToOrderCompletedEvent` — fired when quote-to-order conversion finishes
- `CreateAssetOrderEvent` — fired when asset creation from order completes

### Step 8: quoteLineItemId retrieval after PST
`PlaceSalesTransaction` does NOT return created record IDs in its response. To get the `QuoteLineItemId` (0QL...) after adding a line item via PST:

```apex
// Query immediately after PST completes
QuoteLineItem qli = [
    SELECT Id FROM QuoteLineItem
    WHERE QuoteId = :quoteId
    AND Product2.Name LIKE :productNamePattern
    ORDER BY CreatedDate DESC
    LIMIT 1
];
String quoteLineItemId = qli.Id;
```

### Step 9: Transaction Management object deployment sequence
```
1. AppUsageAssignment     (metadata)
1. SalesTransactionType   (metadata → PricingProcedure)
1. QuoteTemplateRichTextData (metadata)
1. TransactionProcessingType (metadata)
```
Enable `RevenueManagementSettings.enableTransactionProcessor = true` for transaction type routing.

## Common Issues

### Quote line item price not calculated after insert
Cause: Pricing not triggered — PST or headless pricing action not called.
Solution: After inserting the QuoteLineItem, call `RevSalesTrxn.PlaceSalesTransactionExecutor.execute()` or the `Run Salesforce Headless Pricing Action` invocable to trigger pricing.

### Asset lifecycle action fails with "No active assets found"
Cause: Asset `Status` is not `Purchased` or asset `LifecycleEndDate` has passed.
Solution: Verify `Asset.Status = 'Purchased'` and `Asset.LifecycleEndDate > TODAY`.

### Error: "DML on QuoteLineItemAttribute not allowed"
Cause: Standard `insert` / `delete` used on QuoteLineItemAttribute.
Solution: Use `Database.insertImmediate()` / `Database.deleteImmediate()`. See `rlm-product-configurator` skill.

### QuoteSaveEvent not firing
Cause: Platform event subscription (trigger or Flow) not active, or the quote save bypassed the standard save path.
Solution: Verify trigger/Flow is active. Programmatic PST calls do fire `QuoteSaveEvent`.

### Error: "versionString must be 1.0.0" (generateAiAgentResponse)
Cause: Using `versionString: 2.0.0` with a legacy Bot agent invoked via `generateAiAgentResponse`.
Solution: Always pass `versionString: 1.0.0` for legacy Bot agents. The `2.0.0` path requires `dataTypeMappings` and is not supported by legacy Bot/BotVersion agents.

## Examples

### Example 1: Create a fully configured quote from scratch
User says: "Create a quote for Opportunity X with product Y configured as Z"

1. Query Opportunity to get `AccountId`, `Pricebook2Id`
2. Insert `Quote` (OpportunityId, Pricebook2Id, Status = 'Draft')
3. Query `PriceBookEntry` for the product (Product2.Name LIKE '%Y%', Pricebook2Id = ...)
4. Insert `QuoteLineItem` (QuoteId, PricebookEntryId, Quantity = 1, UnitPrice = 0)
5. Call PST to apply attribute configuration Z → BOM + pricing applied
6. Query `QuoteLineItem.UnitPrice` + `Quote.GrandTotal`
7. Return: quote created, configured, Grand Total = $X

### Example 2: Initiate a renewal for an expiring asset
1. Call `Get Renewable Assets Summary Action` for the account
2. Find assets with `RenewalStatus = Eligible`
3. Call `Initiate Renewal Action` with the `assetId`
4. Return the new renewal `quoteId` to the user

### Example 3: Convert an approved quote to an order
1. Verify `Quote.Status = 'Approved'`
2. Call `Create Order From Quote Action` with `quoteId`
3. Verify returned `orderId` exists
4. Return: order created, orderId = 801...

## See Also

| Skill | Why |
|---|---|
| `rlm-product-configurator` | After creating a QuoteLineItem, use PST to apply attribute configurations and trigger BOM/pricing |
| `rlm-pricing` | Headless pricing and PST pricing both operate on QuoteLineItem records created by transaction management |
| `rlm-billing` | Order activation triggers billing schedule creation; quote Grand Total is the basis for invoice amounts |
| `rlm-advanced-approvals` | Quotes require approval before conversion to order; approval work items reference QuoteId |
| `rlm-dynamic-revenue-orchestrator` | Order activation triggers DRO fulfillment plans via `SalesTrxnDecompositionEvent` |
| `rlm-product-discovery` | Product discovery is the step that identifies which product to add as a QuoteLineItem |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.1.0 | 2026-05-02 | Added See Also table; added scripts/setup-test-data.apex |
| 1.0.0 | 2026-04-01 | Initial skill — quote/order creation, asset lifecycle, PST Business API, platform events |

---

## References
- See `references/trxn-api-patterns.md` for PST Business API request/response schemas
- See `references/asset-lifecycle-patterns.md` for amendment/renewal flow patterns
- RLM Developer Guide Chapter 8: Transaction Management (p. 1118)
- RLM Developer Guide: RevSalesTrxn Namespace Apex Reference (p. 1615)
- RLM Developer Guide: PlaceQuote Namespace (p. 1587)
- See `references/trxn-api-patterns.md` for quoteLineItemId retrieval pattern and other design decisions

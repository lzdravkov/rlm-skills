---
name: rlm-transaction-management
description: Create and manage Salesforce Revenue Cloud quotes, orders, and asset lifecycle actions including amendment, renewal, cancellation, transfer, and rollback (RLM v68). Use when creating quotes, adding line items, converting quotes to orders, or managing asset subscriptions. Do NOT use for product attribute configuration (use rlm-product-configurator) or invoice generation (use rlm-billing). Triggers on: "create quote", "add line item", "convert to order", "create order", "asset", "amendment", "renewal", "cancellation", "transfer", "rollback", "quote line item", "sales transaction", "place order", "quote save", "subscription lifecycle".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Transaction Management

## Instructions

### Step 1: Identify the transaction task
- **Quote creation**: Create Opportunity → Quote → QuoteLineItem via APIs or Apex
- **Order creation**: Convert Quote to Order via `Create Orders From Quote Action` (`createOrderFromQuote` is deprecated as of v65.0)
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
POST /services/data/v68.0/connect/rev/sales-transaction/actions/place
```

> **Correction (v68 re-baseline):** the previous `POST /commerce/sales-transactions` path does not
> exist in the v68 Business API resource inventory — it was a fabricated shape. The real "Place Sales
> Transaction" resource lives under `/connect/rev/sales-transaction/actions/place`. Related resources:
> `/connect/rev/sales-transaction/actions/clone` (Clone Sales Transaction) and
> `/connect/rev/sales-transaction/actions/place-supplemental-transaction` (Place Supplemental
> Transaction). Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management ›
> Business API Resources.

Request body includes the full sales transaction graph: quote header + line items + attributes.

Or via Apex (`RevSalesTrxn` namespace):
```apex
RevSalesTrxn.PlaceSalesTransactionResponse resp = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
    graph,
    RevSalesTrxn.PricingPreferenceEnum.System,
    RevSalesTrxn.ConfigurationExecutionEnum.System,
    new RevSalesTrxn.ConfigurationOptionsInput(),
    null    // contextId
);
```

> **Correction (v68 re-baseline):** the previous example (`execute(graph, SYSTEM, SYSTEM, options, null)`)
> used bare enum literals that aren't valid Apex — enum values must be fully qualified
> (`RevSalesTrxn.PricingPreferenceEnum.System`, `RevSalesTrxn.ConfigurationExecutionEnum.System`).
> Additional confirmed `RevSalesTrxn` enums useful for surgical scenarios: `CatalogRatesPreferenceEnum`
> (Fetch/Skip), `TaxPreferenceEnum` (avail 65.0+), `PersistPreferenceEnum` (Skip; avail 65.0+), and
> `GroupRampActionEnum` (AddProducts/DeleteProducts/EditGroup/EditRampSchedule/DeleteSegment/
> ConvertToNonRampedGroup) — pass these via additional `execute()` overloads where ramp-deal or
> tax/persist behavior needs to be controlled.
>
> **Note:** the older `CommerceOrders` and `PlaceQuote` Apex namespaces (previously cited in this
> skill's References) are **deprecated as of API v63.0** — Salesforce's guidance is "use the new
> RevSalesTrxn namespace." `RevSalesTrxn` is the only namespace to use for new v68 work.
> Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Apex Reference ›
> CommerceOrders Namespace / PlaceQuote Namespace / RevSalesTrxn Namespace.

### Step 4: Convert a quote to an order
Use the **`Create Orders From Quote Action`** (`createOrdersFromQuote`) invocable action — the
current, non-deprecated action for quote-to-order conversion:

Input: `quoteId` (required), `quoteLineItemIds` (optional — omit to convert the whole quote),
`orderCreationMethod` (`CreateSingleOrder` | `CreateOrderByGroup` | `CreateOrderByField`, default
`CreateSingleOrder`), `orderCreationParameters` (Apex-defined `ConnectApi.OrderCreationParametersInputRepresentation`,
e.g. `splitFieldName` for `CreateOrderByField`)
Output: `orderIds[]`, `requestId`, `statusUrl` (order headers are created synchronously; line items
asynchronously when creating multiple orders)

REST (Actions API): `POST /services/data/v68.0/actions/standard/createOrdersFromQuote`

> **Correction (v68 re-baseline):** the previous `POST /commerce/orders/fromQuote` Business API path
> does not exist — it was fabricated. Quote-to-order conversion is exposed only via the Standard
> Invocable Actions layer (Actions REST API), not a dedicated `/commerce/...` Connect resource.
>
> The older **`Create Order From Quote Action`** (`createOrderFromQuote`, input `quoteRecordId` →
> output `orderId`/`orderNumber`/`requestId`) is **deprecated as of API v65.0** — Salesforce's
> guidance is "use the Create Orders From Quote Action." Keep `createOrderFromQuote` only for
> orgs pinned below v65.0.
>
> Requires the **Advanced Order Creation From Quote** toggle in Revenue Settings — this is the same
> flag as `RevenueManagementSettings.enableAdvCreateOrdersFromQuote`, confirmed in the action's
> Special Access Rules. Available in API version 65.0 and later.
>
> Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard
> Invocable Actions › Create Order From Quote Action / Create Orders From Quote Action.

### Step 5: Asset lifecycle actions
After an order is fulfilled, assets are created from order items. Manage asset lifecycle via
Standard Invocable Actions (Actions REST API, `/services/data/v68.0/actions/standard/<name>`) and,
for Amendment/Cancellation/Renewal only, a parallel Connect Business API surface:

| Action | Invocable Action (`actionName`) | Business API |
|---|---|---|
| Amendment | `initiateAmendment` | `POST /connect/revenue-management/assets/actions/amend` |
| Renewal | `initiateRenewal` | `POST /connect/revenue-management/assets/actions/renew` |
| Cancellation | `initiateCancellation` | `POST /connect/revenue-management/assets/actions/cancel` |
| Transfer | `initiateTransfer` | *(no dedicated Connect resource found in v68 — invocable action only)* |
| Rollback | `initiateRollBackLastAction` | *(no dedicated Connect resource found in v68 — invocable action only)* |

> **Correction (v68 re-baseline):** the previous `POST /commerce/assets/{id}/{amendment|renewal|
> cancellation|transfer|rollback}` shapes do not exist — they were fabricated. Real key inputs/outputs
> per action (all POST, JSON/XML, Bearer auth):
> - **`initiateAmendment`** — `amendAssetIds` (required), `amendStartDate` (required, datetime),
>   `amendOutputType` (required: `Quote`|`Order`), `quantityChange` (required, double),
>   `amendContractId`, `amendOpportunityId`, `skipPricing` (avail 64.0+) → outputs `amendRecordId`,
>   `requestIdentifier`. For usage products, direct `amendOutputType = Order` is **not supported**
>   (can create Order Products without required Rate Card Entry records, causing activation to
>   fail) — use the 2-step flow: amend to `Quote`, then convert.
> - **`initiateCancellation`** — `cancelAssetIds` (required; all assets in one request must share a
>   price book), `cancelStartDate` (required, datetime), `cancelOutputType` (required),
>   `cancelContractId`, `cancelOpportunityId`, `skipPricing` → outputs `cancelRecordId`,
>   `requestIdentifier`.
> - **`initiateRenewal`** — `renewAssetIds` (required), `renewOutputType` (required),
>   `renewStartDate`/`renewEndDate` (avail 62.0+), `renewContractId`, `renewOpportunityId`,
>   `skipPricing`, `rampOptionsDetails` (Apex-defined `RampOptionInputRepresentation` — segment
>   type/duration/count for group ramp schedules, avail 67.0+) → outputs `renewRecordId`,
>   `requestIdentifier`.
> - **`initiateTransfer`** — `transferRecords` (required, Apex-defined list of
>   `connectapi__TransferRecordInputRepresentation` — `assetId` + `transferQuantity`),
>   `targetAccountId` (required), `transferDate` (required), `outputRecordType` (required),
>   `targetContractId`, `shouldSkipPricing` → outputs `assetTransferSourceId`,
>   `assetTransferTargetId`, `requestIdentifier`. Generates **2** quotes/orders — a negative-quantity
>   source transaction and a positive-quantity target transaction; transfer completes once both are
>   assetized. Avail 65.0+.
> - **`initiateRollBackLastAction`** — `assetIds` (required), `outputType` (required: `Quote`|`Order`)
>   → output `recordId`. Constraints (confirmed): rollback only on **future-dated** transactions;
>   **not supported for legacy assets**; supported for **amendment and renewal only** (not
>   cancellation or transfer). Avail 65.0+.
>
> Also new in v66.0+ and currently uncovered by this skill: **Initiate Swap / Upgrade / Downgrade**
> Business APIs (`POST /revenue/transaction-management/assets/actions/{swap|upgrade|downgrade}`),
> which create linked `AssetAction` records categorized Swaps/Upgrades/Downgrades. See
> `rlm-assets/references/asset-object-reference.md` for the `AssetAction` field model these produce.
>
> The prior claim that each lifecycle action creates a `QuoteAction` record could **not be confirmed**
> against the v68 Standard Objects section reviewed for this re-baseline — `QuoteAction` was not
> found as a real queryable object in the sections read. Treat `QuoteAction` as **unverified**; the
> confirmed mechanism is that these actions create a **Quote or Order** record directly (per the
> `*OutputType`/`outputType` input) plus an `AssetAction` history record once assetized.
>
> Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Business API
> Resources; › Standard Invocable Actions › Initiate Amendment/Cancellation/Renewal/Transfer Action,
> Initiate Rollback on Last Action.

### Step 6: Get renewable assets summary
Before initiating a renewal, use `Get Renewable Assets Summary Action` (`getRenewableAssetsSummary`)
to check asset status:

Input: `orderId` (required — ID of the order related to the assets to check for renewal opportunities)
Output: `renewableAssetsSummary[]` (Apex-defined, backed by the `renew_assets_summary.RenewalOpptyDetail`
class), each entry containing: `assetId`, `account`, `productId`, `priceBookId`, `priceBookEntryId`,
`orderItem`, `opportunityProductId`, `startDate`, `endDate`, `lastAssetAction` (values confirmed:
`Initial Sale` | `Upsell` | `Downsell` | `Renewal` | `Cancellation`), `lastAssetActionSubtype`,
`rootAssetOpportunity`, `renewalPriceDetails[]` (`netUnitPrice`, `quantity`).

> **Correction (v68 re-baseline):** the input is keyed on `orderId`, not `accountId`/`assetIds` — the
> action retrieves renewal opportunities for the assets tied to a given order. The output fields
> `CurrentTermEndDate` and `RenewalStatus` claimed previously do **not exist** on the real
> `RenewalOpptyDetail` shape; use `startDate`/`endDate` and `lastAssetAction` instead. This action
> gets pricing data from the `OrderEntitiesMapping` context mapping within the `SalesTransactionContext`
> context definition — edit that mapping before use if your org customizes pricing procedure objects/
> fields. It doesn't support procedure plans (renewal line items may return a price of zero in that
> case). Avail API v64.0+.
> Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard
> Invocable Actions › Get Renewable Assets Summary Action; › Apex Reference › renew_assets_summary
> Namespace.

### Step 7: Platform events for quote lifecycle
Subscribe to these events in Flows or Apex triggers for post-processing:

- `QuoteSaveEvent` (avail 60.0+) — fired after every quote save; fields: `CorrelationIdentifier`,
  `EventUuid`, `HasErrors`, `QuoteId`, `ReplayId`, `RequestIdentifier`
- `PlaceOrderCompletedEvent` (avail 63.0+) — fired after order creation from quote; fields:
  `AppUsageTypes`, `CorrelationIdentifier`, `EventUuid`, `HasErrors`, `OrderId`, `ReplayId`,
  `RequestIdentifier`
- `QuoteToOrderCompletedEvent` (avail 56.0+) — fired when quote-to-order conversion finishes; fields:
  `CorrelationIdentifier`, `EventUuid`, `HasErrors`, `OrderId`, `OrderNumber`, `ReplayId`,
  `RequestIdentifier`
- `CreateAssetOrderEvent` (avail 55.0+) — fired when asset creation from order completes; **the field
  shape is nested, not flat**: top-level fields are `AssetDetails` (list of `CreateAssetOrderDtlEvent`),
  `CorrelationIdentifier`, `EventUuid`, `IsLastEvent` (62.0+), `OrderIdentifier` (Revenue Cloud 64.0+),
  `ReplayId`, `RequestIdentifier`. There is no top-level `AssetId`/`OrderId` field — per-asset
  `AssetId`, `OrderItemId` (61.0+), `IsSuccess` (61.0+), `ErrorCode`, `ErrorMessage` live on the nested
  `CreateAssetOrderDtlEvent` records inside `AssetDetails`. See
  `rlm-assets/references/asset-object-reference.md` for the full corrected shape.

### Step 7a: New in v68 — Sync Quote to Opportunity Action
`syncQuoteOpportunity` (avail **68.0+**, new this release) syncs quote line items to matching
opportunity line items so forecasts stay current. Requires the **Asynchronous Opportunity Sync**
toggle in Revenue Settings.

Input: `quoteId` (required, single quote only)
Output: `aotId` (async operation tracker ID), `isSuccess`, `errorCode`, `errorMessage`

Also new: **Deep Clone Sales Transaction** (`deepCloneSalesTransaction`, avail 67.0+) clones a quote
or order including its full object graph (related objects, selected lines/groups) —
`POST /services/data/v68.0/actions/standard/deepCloneSalesTransaction`. Inputs: `salesTransactionId`
(required), `recordIds` (single record ID to clone), `options` (`lineScope`: `AllLines` |
`RampedLinesOnly`, for cloning ramp segments). Output: `newRecordId`.

Source: RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard
Invocable Actions › Sync Quote to Opportunity Action, Deep Clone Sales Transaction.

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

> **Annotation (v68 re-baseline):** this deployment sequence and the `enableTransactionProcessor`
> flag name were **not independently re-verified** against Ch.3 (Deployment) or Ch.2
> (RevenueManagementSettings) in this pass — those sections were out of scope for the Ch.8-focused
> read performed here. No contradicting evidence was found; left as-is. Recommend a follow-up
> pass cross-checking Ch.2 (printed p.4–9) and Ch.3 Object/Metadata Deployment Reference (printed
> p.20–31) before relying on this sequence verbatim.

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
1. Call `Get Renewable Assets Summary Action` (`getRenewableAssetsSummary`) with the asset's `orderId`
2. Inspect `renewableAssetsSummary[]` entries — e.g. filter by upcoming `endDate`
3. Call `Initiate Renewal Action` (`initiateRenewal`) with `renewAssetIds` and `renewOutputType`
4. Return the new renewal record ID (`renewRecordId`) to the user

### Example 3: Convert an approved quote to an order
1. Verify `Quote.Status = 'Approved'`
2. Call `Create Orders From Quote Action` (`createOrdersFromQuote`) with `quoteId`
3. Verify returned `orderIds[]` is non-empty (async via `statusUrl`/`requestId` for multi-order splits)
4. Return: order(s) created, orderIds = [801...]

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
| 2.0.0 | 2026-09-11 | **v68 (Winter '27) re-baseline.** Corrected fabricated `/commerce/...` Business API paths to the real v68 inventory (`/connect/rev/sales-transaction/actions/place`, `/connect/revenue-management/assets/actions/{amend,cancel,renew}`, `/services/data/v68.0/actions/standard/<name>`); fixed the `RevSalesTrxn.PlaceSalesTransactionExecutor.execute()` example to use fully-qualified enums; documented `CommerceOrders`/`PlaceQuote` namespace deprecation (v63.0) in favor of `RevSalesTrxn`; replaced `createOrderFromQuote` (deprecated v65.0) with `createOrdersFromQuote` as the primary quote→order path; corrected Get Renewable Assets Summary input/output to the real `orderId` → `renewableAssetsSummary[]`/`RenewalOpptyDetail` shape (removed fabricated `RenewalStatus`/`CurrentTermEndDate`); corrected asset lifecycle action I/O for amend/cancel/renew/transfer/rollback against confirmed Standard Invocable Actions; added surgical coverage for new v67/v68 actions (Deep Clone Sales Transaction, Sync Quote to Opportunity Action) and v66 Swap/Upgrade/Downgrade Business APIs; corrected platform event field shapes (notably `CreateAssetOrderEvent`'s nested `AssetDetails`); flagged `QuoteAction` as unverified; bumped compatibility to API v68.0+. |
| 1.1.0 | 2026-05-02 | Added See Also table; added scripts/setup-test-data.apex |
| 1.0.0 | 2026-04-01 | Initial skill — quote/order creation, asset lifecycle, PST Business API, platform events |

---

## References
- See `references/trxn-api-patterns.md` for PST Business API request/response schemas
- See `references/asset-lifecycle-patterns.md` for amendment/renewal flow patterns
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Apex Reference › RevSalesTrxn Namespace
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Apex Reference › PlaceQuote Namespace (deprecated as of API v63.0 — use RevSalesTrxn Namespace)
- RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard Invocable Actions
- See `references/trxn-api-patterns.md` for quoteLineItemId retrieval pattern and other design decisions

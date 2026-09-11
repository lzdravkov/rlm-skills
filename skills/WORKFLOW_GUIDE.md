# Revenue Cloud — End-to-End Workflow Guide

This guide shows how the 13 RLM skills map to the full quote-to-cash lifecycle.
Each box names the skill responsible. Arrows show data flow and dependencies.

---

## Quote-to-Cash Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  SETUP (one-time per org)                                                   │
│                                                                             │
│  rlm-deployment          ← deploy ALL metadata + data in dependency order  │
│    ├── rlm-product-catalog    (catalog, attributes, selling models)         │
│    ├── rlm-pricing            (price books, adjustment schedules)           │
│    ├── rlm-rate-management    (rate cards — requires Rate Mgmt PSL)         │
│    ├── rlm-usage-management   (usage resources, grants, policies)           │
│    ├── rlm-billing            (billing policies, tax engine)                │
│    └── rlm-dynamic-revenue-orchestrator  (fulfillment step definitions)     │
└─────────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼  (runtime, per-deal)

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 1: PRODUCT DISCOVERY                    skill: rlm-product-discovery │
│                                                                            │
│  • Search / browse catalog by name, category, or guided selection          │
│  • Run qualification procedure to filter eligible products                 │
│  • Fetch bulk product details + pricing in one call                        │
│  • Endpoints: POST /connect/cpq/products, /search, /guided-selection, etc  │
│                                                                            │
│  Output: productId, productSellingModelId to use in Step 2                │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 2: TRANSACTION CREATION                skill: rlm-transaction-management │
│                                                                            │
│  • Create Opportunity → Quote → QuoteLineItem                              │
│  • Use PST Business API or RevSalesTrxn Apex namespace                     │
│  • IMPORTANT: PST does NOT return created record IDs — SOQL after insert   │
│                                                                            │
│  Output: quoteId, quoteLineItemId (0QL...)                                 │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 3: PRODUCT CONFIGURATION               skill: rlm-product-configurator │
│                                                                            │
│  • Read configurable attributes from ProductClassificationAttr (SOQL)     │
│  • Save attribute selections via PlaceSalesTransactionExecutor (PST)       │
│  • TWO-STEP SEQUENCING: Number attributes first, then Picklist             │
│  • PST atomically: saves QuoteLineItemAttribute + applies BOM + re-prices  │
│  • Always read back from DB — PST returns internalSuccess:true on failure  │
│                                                                            │
│  Output: configured QuoteLineItem, updated Quote.GrandTotal                │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 4: PRICING                             skill: rlm-pricing            │
│                                                                            │
│  • Standard: PriceBookEntry + PriceAdjustmentSchedule + AttributeBasedAdj  │
│  • Rate-based: RateCard + RateCardEntry via Invoke Rating Service Action   │
│  • Debug: PricingAPIExecution → PricingProcessExecution (step-level)       │
│  • PST triggers pricing automatically — headless pricing for standalone    │
│                                                                            │
│  ↳ If rate cards: see rlm-rate-management (requires Rate Mgmt PSL)        │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 5: APPROVAL (optional)                skill: rlm-advanced-approvals  │
│                                                                            │
│  • Submit quote for approval: ApprovalSubmission record created            │
│  • Approver receives ApprovalWorkItem                                      │
│  • Actions: reviewApprovalWorkItem (approve/reject)                        │
│             overrideApprovalWorkItem (admin override)                      │
│             recallApprovalSubmission / cancelApprovalSubmission            │
│  • approvalDecision must be lowercase: 'approve' | 'reject'               │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 6: ORDER CREATION                     skill: rlm-transaction-management │
│                                                                            │
│  • Convert approved quote to order: Create Orders From Quote Action        │
│  • POST .../actions/standard/createOrdersFromQuote                         │
│  • Platform event: PlaceOrderCompletedEvent                                │
│  • Platform event: SalesTrxnDecompositionEvent → triggers DRO              │
└──────────────────────────────────────────────────────────────────────────┘

          │                                          │
          ▼                                          ▼

┌─────────────────────────────┐       ┌────────────────────────────────────┐
│  STEP 7A: FULFILLMENT       │       │  STEP 7B: USAGE GRANT PROVISIONING │
│  skill: rlm-dynamic-revenue-│       │  skill: rlm-usage-management       │
│  orchestrator               │       │                                    │
│                             │       │  • TransactionUsageEntitlement     │
│  • FulfillmentPlan created  │       │    created from order line item    │
│  • FulfillmentStep[] execute│       │  • UsageEntitlementAccount +       │
│  • Callouts wired via       │       │    UsageEntitlementBucket created  │
│    IntegrationProviderDef   │       │  • Drawdown order is internal      │
│    (HTTP / Apex / ExtSvc)   │       │    (no DrawdownOrder field in v68) │
│  • State → InProgress then  │       │  • Overage: OverageChargeable=Yes  │
│    Completed (202 = async)  │       │    (no OverageType field)          │
└─────────────────────────────┘       └────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 8: ASSET CREATION                     skill: rlm-assets             │
│                                                                            │
│  • Assets created from Order Items after fulfillment                       │
│  • CreateAssetOrderEvent fires when assets are created                     │
│  • Asset.Status = 'Purchased', LifecycleEndDate set from term              │
│  • AssetStatePeriod tracks state changes over subscription lifetime        │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 9: BILLING                            skill: rlm-billing             │
│                                                                            │
│  • Create billing schedules from order                                     │
│  • Run billing batch → Draft invoices                                      │
│  • Post invoices → tax engine called at post time                          │
│  • Apply payments / credit memos                                           │
│  • Usage billing: UsageBillingPeriodItem → InvoiceLine                    │
│  • Report Grand Total: Quote.GrandTotal (all BOM + tax + discounts)        │
└──────────────────────────────────────────────────────────────────────────┘

                              │
                              ▼

┌──────────────────────────────────────────────────────────────────────────┐
│  STEP 10: ASSET LIFECYCLE (amendment/renewal/cancellation)                 │
│                            skill: rlm-assets (+ rlm-transaction-management) │
│                                                                            │
│  • Initiate Amendment / Renewal / Cancellation / Transfer / Rollback       │
│  • Each creates a new Quote with appropriate QuoteAction                   │
│  • Amendment uses delta pricing — only changed items repriced              │
│  • Loop back to Step 3 (configurator) for attribute changes                │
│  • Loop back to Step 9 (billing) for prorated charges                      │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Skill Quick Reference

| Skill | Domain | Key Trigger Phrases |
|---|---|---|
| `rlm-deployment` | DevOps | deploy, GUID, migration, new org setup |
| `rlm-product-catalog` | Setup | product, attribute, selling model, bundle |
| `rlm-product-discovery` | Discovery | find product, search, browse catalog, guided selection |
| `rlm-product-configurator` | Configuration | configure, PST, BOM, attribute values, QuoteLineItemAttribute |
| `rlm-pricing` | Pricing | price book, adjustment, discount, pricing recipe, waterfall |
| `rlm-rate-management` | Pricing | rate card, rating request, tiered rate, binding object |
| `rlm-transaction-management` | Transactions | quote, order, asset lifecycle, amendment, renewal |
| `rlm-advanced-approvals` | Approvals | approve, reject, recall, override, ApprovalWorkItem |
| `rlm-dynamic-revenue-orchestrator` | Fulfillment | fulfillment plan, DRO, callout provider, provisioning |
| `rlm-usage-management` | Usage | usage grant, entitlement bucket, drawdown, overage |
| `rlm-billing` | Billing | invoice, billing schedule, credit memo, payment, tax |
| `rlm-assets` | Asset Lifecycle | asset, amendment, renewal, cancellation, AssetStatePeriod |
| `rlm-agentforce` | AI/Agents | GenAiFunction, Agentforce, BotVersion, GenAiPlugin, sessionId |

---

## Data Object Handoffs Between Steps

| From Step | Object Produced | Consumed By |
|---|---|---|
| Product Discovery | `productId`, `productSellingModelId` | Transaction (QuoteLineItem insert) |
| Transaction Creation | `quoteId`, `quoteLineItemId` | Configurator (PST), Pricing |
| Configuration (PST) | Updated `QuoteLineItemAttribute`, `Quote.GrandTotal` | Pricing, Billing |
| Order Creation | `orderId` | DRO (FulfillmentPlan), Usage (TransactionUsageEntitlement), Billing |
| Fulfillment | `FulfillmentStep.Status = Completed` | Asset creation |
| Asset Creation | `assetId` | Billing (BillingSchedule), Asset Lifecycle |
| Billing | `Invoice`, `InvoiceLine` | Payment, Credit Memo |
| Amendment | new `quoteId` | Configurator loop, Billing (proration) |

---

## Critical Cross-Cutting Rules

1. **PST is the only correct path for attribute saves** — `runConfigRules` alone does not update BOM. Always use `RevSalesTrxn.PlaceSalesTransactionExecutor.execute()`.
2. **Two-step PST sequencing** — Number attributes before Picklist attributes. Single call silently overrides Number values.
3. **`getSessionId()` returns null in Agentforce** — never use for HTTP callouts in GenAiFunction Apex. Use SOQL or Standard Invocable Actions.
4. **PST does not return created IDs** — always SOQL after PST to get `quoteLineItemId`.
5. **Report `Quote.GrandTotal`, not `QuoteLineItem.UnitPrice`** — Grand Total includes full BOM, discounts, and taxes.
6. **Deploy metadata before data** — data records reference metadata types; sequence violations produce `INVALID_CROSS_REFERENCE_KEY`.
7. **GUID__c is mandatory for DevOps** — Salesforce record IDs are org-specific; without GUID__c you cannot upsert across orgs.
8. **Rate Management requires PSL** — Rate Management objects return "Object not found" without the Rate Management Permission Set License.

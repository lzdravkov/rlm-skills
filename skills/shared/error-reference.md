# Revenue Cloud — Cross-Cutting Error Reference

Errors organized by domain. Each entry: symptom → root cause → fix → which skill to consult.

---

## PST / Product Configuration Errors

### `internalSuccess: true` but BOM not updated / attribute value reverts
**Domain**: rlm-product-configurator
**Root cause 1**: Number attribute and Picklist attribute submitted in a single PST call. Picklist's BOM rules lock the component structure, silently overriding the Number value.
**Fix 1**: Two-step PST sequencing — `executePst(numberAttrs)` first, then `executePst(picklistAttrs)`.
**Root cause 2**: Picklist attribute submitted without `AttributePicklistValueId`.
**Fix 2**: Always include both `AttributeValue` (display text) and `AttributePicklistValueId` in the PST payload for Picklist attributes.
**Root cause 3**: `applyBomRules: false` in configOptions.
**Fix 3**: Set `applyBomRules: true` in configOptions map.

### `internalSuccess: true` but price not updated after PST
**Domain**: rlm-pricing, rlm-product-configurator
**Root cause**: `applyPricing: false` in configOptions, or no active `PriceBookEntry` for the product/pricebook combination.
**Fix**: Set `applyPricing: true`. Verify `PriceBookEntry.IsActive = true` and correct `ProductSellingModelId`.

### `DML on QuoteLineItemAttribute not allowed` / `Argument must be of internal sObject type`
**Domain**: rlm-product-configurator
**Root cause**: Standard `insert` / `delete` DML used on `QuoteLineItemAttribute` or `OrderItemAttribute`.
**Fix**: Replace with `Database.insertImmediate()` / `Database.deleteImmediate()`.

### `runConfigRules` does not update BOM
**Domain**: rlm-product-configurator
**Root cause**: `Run Config Rules Action` evaluates constraint rules only — does not trigger BOM restructuring or pricing.
**Fix**: Use `RevSalesTrxn.PlaceSalesTransactionExecutor.execute()` for any save that must update BOM or price.

---

## Deployment Errors

### `INVALID_CROSS_REFERENCE_KEY` on data load
**Domain**: rlm-deployment
**Root cause**: Parent record not yet deployed — foreign key dependency violated.
**Fix**: Check the object's foreign keys against the deployment sequence. Deploy the parent object first. See `rlm-deployment/references/deploy-sequence-full.md`.

### `Cannot deploy active version`
**Domain**: rlm-deployment
**Root cause**: Trying to update a component version that is `Active` in the target org.
**Fix**: Deactivate the version in the target org, deploy the update, then reactivate.

### Circular dependency during deployment
**Domain**: rlm-deployment
**Root cause**: Object A depends on B and B depends on A.
**Fix**: Deploy A first (without the B reference), then B, then redeploy A with the B reference.

### Product index not reflecting new products after deployment
**Domain**: rlm-product-discovery, rlm-deployment
**Root cause**: Product index must be manually rebuilt after catalog changes.
**Fix**: Setup → Revenue Cloud → Product Discovery → Rebuild Index, or `POST /commerce/management/catalogs/{id}/index`.

### Feature flag missing in target org after deployment
**Domain**: rlm-deployment
**Root cause**: `RevenueManagementSettings` metadata not included in deployment package, or settings file targeted wrong org alias.
**Fix**: Verify settings file was in package.xml. Re-deploy: `sf project deploy start --metadata "Settings:RevenueManagement" --target-org <alias>`.

---

## Pricing Errors

### `ExpressionSet not found` when running PricingRecipe
**Domain**: rlm-pricing
**Root cause**: `ExpressionSetDefinition` metadata not deployed before `PricingRecipe`.
**Fix**: Deploy `ExpressionSetDefinition` first; `PricingRecipe` references it by name.

### `PRICING_RULE_NOT_FOUND` in headless pricing response
**Domain**: rlm-pricing
**Root cause**: No active `PriceBookEntry` for the product/pricebook combination, or `PriceBookEntry.IsActive = false`.
**Fix**: Verify `PriceBookEntry` exists with `IsActive = true`, correct `Pricebook2Id`, `Product2Id`, and `ProductSellingModelId`.

### `INVALID_PRICING_FLOW` in headless pricing response
**Domain**: rlm-pricing
**Root cause**: `pricingFlow` name does not match an active `PricingRecipe`.
**Fix**: Confirm the exact API name of the deployed `PricingRecipe`. Check `RevenueManagementSettings.enableRevUnifiedSetup = true` if using procedure plans.

### Price not updating after attribute change
**Domain**: rlm-pricing, rlm-product-configurator
**Root cause**: PST called with `runConfigRules` only — does not trigger pricing.
**Fix**: Full `PlaceSalesTransactionExecutor.execute()` with `applyPricing: true`.

---

## Billing Errors

### `BILLING_SCHEDULE_NOT_FOUND`
**Domain**: rlm-billing
**Root cause**: Order not activated before creating billing schedules.
**Fix**: Verify `Order.Status = 'Activated'` before calling `Create Billing Schedules From Billing Transaction Action`.

### `ACCOUNTING_PERIOD_NOT_ACTIVE`
**Domain**: rlm-billing
**Root cause**: No active `AccountingPeriod` record covers the billing date.
**Fix**: Create or activate an `AccountingPeriod` that covers the billing run date range.

### `CANNOT_VOID_INVOICE`
**Domain**: rlm-billing
**Root cause**: A payment has already been applied to the invoice.
**Fix**: Call `Unapply Payment Action` first, then void the invoice.

### Tax not calculated on invoice — `TaxEngineInteractionLog.Status = Failed`
**Domain**: rlm-billing
**Root cause**: `TaxEngine` not connected to `BillingPolicy`, or `TaxTreatmentItem.ProductId` doesn't match the invoiced product, or `TaxEngineAdapter` Apex class has a bug.
**Fix**: Check `TaxEngineInteractionLog.ErrorMessage` and `RequestPayload`. Verify `BillingPolicy.TaxEngineId` is set and `TaxTreatmentItem` links the correct product.

### `SINGLE_EMAIL_LIMIT_EXCEEDED` in Apex logs
**Domain**: rlm-billing, rlm-agentforce
**Root cause**: Developer/trial org 15 single-email/day limit hit. Email is silently dropped.
**Fix**: Use a sandbox or full org for volume testing. Monitor `Messaging.SingleEmailMessage` call count.

---

## Transaction Management Errors

### Quote line item price not calculated after insert
**Domain**: rlm-transaction-management
**Root cause**: No pricing trigger — PST or headless pricing action not called after `QuoteLineItem` insert.
**Fix**: Call `RevSalesTrxn.PlaceSalesTransactionExecutor.execute()` or `Run Salesforce Headless Pricing Action` after insert.

### `versionString must be 1.0.0` in `generateAiAgentResponse`
**Domain**: rlm-agentforce, rlm-transaction-management
**Root cause**: Using `versionString: 2.0.0` with a Legacy Bot agent.
**Fix**: Always pass `versionString: "1.0.0"` for Legacy Bot/BotVersion agents.

### `QuoteSaveEvent` not firing
**Domain**: rlm-transaction-management
**Root cause**: Trigger or Flow subscribed to the event is not active, or the quote save bypassed the standard save path.
**Fix**: Verify trigger is deployed and active. Verify Flow is activated. Note: programmatic PST calls do fire `QuoteSaveEvent`.

---

## Asset Lifecycle Errors

### `No active assets found` on lifecycle action
**Domain**: rlm-assets
**Root cause**: `Asset.Status != 'Purchased'` or `Asset.LifecycleEndDate` has already passed.
**Fix**: Verify `Asset.Status = 'Purchased'` and `LifecycleEndDate > TODAY`. For Evergreen (null `LifecycleEndDate`), only verify Status.

### Amendment effective date rejected
**Domain**: rlm-assets
**Root cause**: `effectiveDate` outside `LifecycleStartDate`–`LifecycleEndDate` range, or a conflicting in-progress lifecycle action exists.
**Fix**: Check `Asset.LifecycleStartDate`/`EndDate`. Query `QuoteAction WHERE AssetId = :id AND Status IN ('Draft','In Progress')`.

### `Cannot rollback billed asset`
**Domain**: rlm-assets
**Root cause**: An invoice for the new term period has already been posted.
**Fix**: Void or credit the invoice first. If already paid, issue a credit memo instead of rollback.

---

## Dynamic Revenue Orchestrator Errors

### FulfillmentStep remains `Running` indefinitely
**Domain**: rlm-dynamic-revenue-orchestrator
**Root cause**: External service returned HTTP 202 (async accepted) but never called back.
**Fix**: Implement a timeout policy or callback monitoring via `FulfillmentSourceChangeEvent`. Add manual step completion logic if no callback arrives.

### `ProcessIntegrationProvider` interface not recognized
**Domain**: rlm-dynamic-revenue-orchestrator
**Root cause**: `industriesintegrationfwk` namespace not available — Industries Integration Framework package not installed.
**Fix**: `sf data query --query "SELECT Id FROM ApexClass WHERE NamespacePrefix = 'industriesintegrationfwk'" --target-org <alias>`. Install the package if missing.

---

## Usage Management Errors

### `UsageEntitlementBucket` not created after subscription activation
**Domain**: rlm-usage-management
**Root cause**: `ProductUsageGrant.IsActive = false` or `EffectiveStartDate` is in the future.
**Fix**: Confirm the grant is active and `EffectiveStartDate <= TODAY`.

### DrawdownOrder has no effect
**Domain**: rlm-usage-management
**Root cause**: Only one active `UsageEntitlementBucket` exists — drawdown order only matters with multiple active buckets.
**Fix**: Check `SELECT COUNT() FROM UsageEntitlementBucket WHERE UsageEntitlementAccountId = :id AND Status = 'Active'`.

### Overage charges not appearing on invoice
**Domain**: rlm-usage-management, rlm-billing
**Root cause**: `UsageOveragePolicy.OverageType = 'Allow'` (not `Chargeable`), or the overage rate is not linked to a `RateCardEntry`.
**Fix**: Set `OverageType = 'Chargeable'`. Link the overage rate to an active rate card.

---

## Rate Management Errors

### Rate Management objects not visible in SOQL / `Object not found`
**Domain**: rlm-rate-management
**Root cause**: Rate Management Permission Set License not assigned to the running user.
**Fix**: Setup → Permission Set Licenses → assign Rate Management PSL.

### `AdjustmentType` invalid value error
**Domain**: rlm-rate-management
**Root cause**: Wrong casing or wrong value. Must be exactly `Amount`, `Override`, or `Percentage`.
**Fix**: Do not use `Discount`, `Fixed`, `percent`, etc. — these will fail.

---

## Agentforce Errors

### `getSessionId()` returns null — HTTP callout fails
**Domain**: rlm-agentforce
**Root cause**: Running inside Agentforce execution context.
**Fix**: Use SOQL or Standard Invocable Actions. See `rlm-agentforce/SKILL.md`.

### GenAiFunction deploy fails: `Action not found`
**Domain**: rlm-agentforce
**Root cause**: Referenced Flow not yet deployed or API name mismatch.
**Fix**: Deploy Flows before GenAiFunctions. Verify `actionName` matches Flow API name exactly.

### GenAiPlugin deploy fails: `Developer name already exists`
**Domain**: rlm-agentforce
**Root cause**: Inline developer names must be globally unique — prior BotVersion used same name.
**Fix**: Suffix new names with version number (e.g., `_v4`).

### Agent session context lost between email turns
**Domain**: rlm-agentforce
**Root cause**: `AgentSessionId__c` null (not stored) or session expired (~24h TTL).
**Fix**: Store `generateAiAgentResponse.sessionId` output on Case after Turn 1. Clear and restart if expired.

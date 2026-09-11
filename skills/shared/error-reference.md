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
**Root cause 3**: Configuration rules not requested on the PST call. (v68: there is no `applyBomRules` map key — config-rule execution is a typed property on `RevSalesTrxn.ConfigurationOptionsInput`.)
**Fix 3**: Set `configOptions.executeConfigurationRules = true` on the `RevSalesTrxn.ConfigurationOptionsInput` passed to `PlaceSalesTransactionExecutor.execute()`.

### `internalSuccess: true` but price not updated after PST
**Domain**: rlm-pricing, rlm-product-configurator
**Root cause**: PST invoked with a non-pricing `PricingPreferenceEnum` (v68: pricing is controlled by the `RevSalesTrxn.PricingPreferenceEnum` positional argument to `execute()`, not an `applyPricing` map key), or no active `PriceBookEntry` for the product/pricebook combination.
**Fix**: Pass `RevSalesTrxn.PricingPreferenceEnum.SYSTEM` to `PlaceSalesTransactionExecutor.execute()`. Verify `PriceBookEntry.IsActive = true` and correct `ProductSellingModelId`.

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
**Fix**: Setup → Revenue Cloud → Product Discovery → Rebuild Index, or build the index via `POST /connect/pcm/index/deploy` (PCM index API; see `rlm-product-catalog/references/pcm-api-patterns.md`).

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
**Fix**: Full `PlaceSalesTransactionExecutor.execute()` with `RevSalesTrxn.PricingPreferenceEnum.SYSTEM`.

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

### Tax not calculated on invoice — `TaxEngineInteractionLog.ResultCode != Success`
**Domain**: rlm-billing
**Root cause**: `TaxEngine` not linked to the applicable `TaxTreatment` (v68: the link is `TaxTreatment.TaxEngineId` — there is no `BillingPolicy.TaxEngineId` field), or the `TaxTreatment`/`TaxTreatmentItem` doesn't match the invoiced product, or the registered `TaxEngineAdapter` Apex class has a bug.
**Fix**: Query `TaxEngineInteractionLog` and inspect `ResultCode` (valid values: `AdapterException`, `ReferenceDocumentCodeMissing`, `Success`, `TaxEngineError`, `ValidationError`) plus the base64 `RequestBody`. Verify `TaxTreatment.TaxEngineId` is set and that a `TaxTreatmentItem` links the correct product. (v68: `TaxEngineInteractionLog` has no `Status`/`ErrorMessage`/`RequestPayload`/`InvoiceId` fields — use `ResultCode`/`RequestBody`/`ReferenceEntity`.)

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
**Root cause**: `Asset.Status != 'Purchased'` (confirmed v68 value), or the asset's term has passed.
**Fix**: Verify `Asset.Status = 'Purchased'`. Prefer the **Get Renewable Assets Summary Action** (`renewableAssetsSummary[]`) to confirm eligibility over querying date fields. (v68: `Asset.LifecycleStartDate`/`LifecycleEndDate` are UNVERIFIED — not found in the Standard Objects sections reviewed; do not filter on them without confirming they exist in your org.)

### Amendment effective date rejected
**Domain**: rlm-assets
**Root cause**: `effectiveDate` outside the asset's term, or a conflicting in-progress lifecycle action exists.
**Fix**: Confirm eligibility via the **initiateAmendment** invocable action rather than a date/`QuoteAction` query. (v68: `Asset.LifecycleStartDate`/`LifecycleEndDate` and the `QuoteAction` object could **not be confirmed** in the v68 guide — the prior `QuoteAction WHERE AssetId = :id AND Status IN (...)` query is unverified; use the invocable action's response to detect conflicting actions.)

### `Cannot rollback billed asset`
**Domain**: rlm-assets
**Root cause**: An invoice for the new term period has already been posted.
**Fix**: Void or credit the invoice first. If already paid, issue a credit memo instead of rollback.

---

## Dynamic Revenue Orchestrator Errors

### FulfillmentStep remains `InProgress` indefinitely
**Domain**: rlm-dynamic-revenue-orchestrator
**Root cause**: External service returned HTTP 202 (async accepted) but never called back. (v68: `FulfillmentStep.State` uses `InProgress` — there is no `Running` state value.)
**Fix**: Implement a timeout policy or callback monitoring via `FulfillmentSourceChangeEvent`. Add manual step completion logic if no callback arrives.

### `ProcessIntegrationProvider` interface not recognized
**Domain**: rlm-dynamic-revenue-orchestrator
**Root cause**: `industriesintegrationfwk` namespace not available — Industries Integration Framework package not installed.
**Fix**: `sf data query --query "SELECT Id FROM ApexClass WHERE NamespacePrefix = 'industriesintegrationfwk'" --target-org <alias>`. Install the package if missing.

---

## Usage Management Errors

### `UsageEntitlementBucket` not created after subscription activation
**Domain**: rlm-usage-management
**Root cause**: `ProductUsageGrant.Status != 'Active'` (v68: `ProductUsageGrant` has no `IsActive` field — use `Status`, values `Active | Draft | Inactive`), or the entitlement-creation process has not run.
**Fix**: Confirm `ProductUsageGrant.Status = 'Active'`. If still missing, run the **Retrigger Entitlement Creation Process Action**.

### Drawdown consumes buckets in an unexpected order
**Domain**: rlm-usage-management
**Root cause**: The v68 guide's Usage Standard Objects section (printed pp. 1989–2072) documents no `DrawdownOrder` field/picklist (`ExpiringFirst`/`GrantedFirst`) on `ProductUsageGrant` or `UsageEntitlementBucket` — drawdown ordering appears to be internal platform behavior, not a configurable queryable field.
**Fix**: Do not rely on setting a `DrawdownOrder` field. Verify grant `EffectiveStartDate`/`EffectiveEndDate` windows to influence which entitlements are consumed first, and confirm behavior against your org. See `rlm-usage-management/references/usage-invocable-actions.md` (annotated).

### Overage charges not appearing on invoice
**Domain**: rlm-usage-management, rlm-billing
**Root cause**: `UsageOveragePolicy.OverageChargeable = 'No'` (v68: this is the policy's only functional field — there is no `OverageType`/`OverageRate` field), or the policy is not linked to the resource via `UsageResourcePolicy`/`ProductUsageResourcePolicy.UsageOveragePolicyId`.
**Fix**: Set `OverageChargeable = 'Yes'`, confirm the resource-policy link, then run the **Process Consumption Overages Action** to (re)calculate `UsageRatableSummary`/`UsageBillingPeriodItem`.

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

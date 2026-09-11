---
name: rlm-product-configurator
description: Save and read product attribute configurations on Revenue Cloud quotes and orders using the Place Sales Transaction (PST) API, including BOM bundle rule application and CML constraint rules (RLM v68). Use when configuring attributes on QuoteLineItems or OrderItems, applying BOM rules, or working with PlaceSalesTransactionExecutor. Do NOT use for product catalog setup (use rlm-product-catalog) or pricing-only changes (use rlm-pricing). Triggers on: "configure product", "save configuration", "product attributes", "attribute values", "BOM", "bundle rules", "PST", "Place Sales Transaction", "PlaceSalesTransactionExecutor", "config rules", "constraint model", "QuoteLineItemAttribute".
compatibility: Salesforce Revenue Cloud (Revenue Management), API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Product Configurator

## Instructions

### Step 1: Identify the configuration task
- **Read attributes**: Retrieve current `QuoteLineItemAttribute` values for a line item
- **Save attributes**: Write new attribute selections and trigger BOM/pricing via PST
- **Config rules only**: Run constraint/eligibility rules without saving via `Run Config Rules Action`
- **CML authoring**: Write or debug Constraint Modeling Language rules

### Step 2: Read saved attribute values
To get the current attribute configuration on a QuoteLineItem:

```apex
List<QuoteLineItemAttribute> attrs = [
    SELECT AttributeDefinition.DeveloperName,
           AttributeDefinition.DataType,
           AttributeValue,
           AttributePicklistValueId
    FROM QuoteLineItemAttribute
    WHERE QuoteLineItemId = :qliId
    ORDER BY AttributeDefinition.Sequence__c
];
```

For a human-readable summary, format as: `"AttributeName: Value (PicklistLabel)"`.

> **Annotation (unverified field, v68):** `Sequence__c` reads as an org-specific custom
> field — the `__c` suffix means it isn't a guaranteed standard field. The v68 Product Catalog
> Management standard-object fields (Ch.4, printed p.119) do not show a standard `Sequence`
> field on `AttributeDefinition` itself; the closest confirmed standard ordering field in the
> same chapter is `ProductClassificationAttr.Sequence` (int — "The display sequence of the
> attribute when configuring the product during run time"), which orders attributes at the
> classification level rather than on the queried `QuoteLineItemAttribute.AttributeDefinition`
> relationship. If your org queries `AttributeDefinition.Sequence__c` today, confirm it's a
> real field in your org (it may be a legacy/managed-package field not documented in Ch.4) —
> otherwise consider ordering via the `ProductClassificationAttr` relationship or dropping the
> `ORDER BY` and sorting client-side by `ProductClassificationAttr.Sequence`.

### Step 3: Save attributes via PST API (ONLY correct path for BOM changes)
`PlaceSalesTransactionExecutor` is the only API that atomically:
1. Saves `QuoteLineItemAttribute` records
2. Applies BOM bundle rules (swaps child components)
3. Re-runs pricing

**Never use standard DML** on `QuoteLineItemAttribute` — it fails with "Argument must be of internal sObject type".

> **Corrected for v68 (RLM Developer Guide, Chapter 8 › RevSalesTrxn Namespace, printed
> p.1737):** the `RevSalesTrxn` namespace does **not** contain `SalesTransactionGraph`,
> `SalesTransactionMode`, `SalesTransactionQuote`, `SalesTransactionItem`, or
> `SalesTransactionAttribute` — none of those classes/enums exist in the documented v68
> namespace class list. The real graph is built from `RecordResource` +
> `RecordWithReferenceRequest` objects wrapped in a `GraphRequest`, and `execute()` takes a
> `PricingPreferenceEnum`, a `ConfigurationExecutionEnum`, and a typed
> `ConfigurationOptionsInput` (Boolean properties `addDefaultConfiguration`,
> `executeConfigurationRules`, `validateAmendRenewCancel`, `validateProductCatalog` — there is
> no `applyBomRules`/`applyPricing` map). The pattern below is adapted from the guide's own
> `PlaceSalesTransactionTest` worked example (printed pp.1751–1756).

```apex
// Build one RecordResource per QuoteLineItemAttribute to create/update, wrap each in a
// RecordWithReferenceRequest, and collect them into a single GraphRequest.
List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>();
Integer refIdx = 0;
for (AttributeInput attr : attributeInputs) {
    RevSalesTrxn.RecordResource attrResource =
        new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.getSobjectType(), 'POST');
    Map<String, Object> fieldValues = new Map<String, Object>();
    fieldValues.put('QuoteLineItemId', quoteLineItemId);
    fieldValues.put('AttributeValue', attr.value);
    if (attr.dataType == 'Picklist') {
        // Both fields are required for Picklist types — see Step 5.
        fieldValues.put('AttributePicklistValueId', attr.picklistValueId);
    }
    attrResource.fieldValues = fieldValues;
    records.add(new RevSalesTrxn.RecordWithReferenceRequest('refAttr' + refIdx, attrResource));
    refIdx++;
}

RevSalesTrxn.GraphRequest graphRequest = new RevSalesTrxn.GraphRequest('attrGraph', records);

RevSalesTrxn.ConfigurationOptionsInput configOptions = new RevSalesTrxn.ConfigurationOptionsInput();
configOptions.executeConfigurationRules = true;  // adhere to BOM/config rules
configOptions.validateProductCatalog    = true;
configOptions.addDefaultConfiguration   = false;
configOptions.validateAmendRenewCancel  = false;

RevSalesTrxn.PlaceSalesTransactionResponse response = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
    graphRequest,
    RevSalesTrxn.PricingPreferenceEnum.SYSTEM,
    RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM,
    configOptions,
    null   // contextId — not required when starting a new transaction
);
```
> Field names on `QuoteLineItemAttribute` (`QuoteLineItemId`, `AttributeValue`,
> `AttributePicklistValueId`) match the existing skill assumptions and Step 5's payload rule;
> they were not independently re-verified against the Ch.8 Transaction Management field list in
> this pass — confirm against your org if you see field-not-found errors.

### Step 4: Two-step PST sequencing (CRITICAL for mixed attribute types)
When saving both Number attributes (e.g., `requiredKW`) and Picklist attributes (e.g., `DutyRating`) in a single transaction, a conflict occurs: the Picklist's BOM rules lock the component structure, preventing the Number attribute from swapping components.

**Fix**: Split into two sequential PST calls:
1. `executePst(numberSelections)` — BOM freely restructures to correct kW component
2. `executePst(picklistSelections)` — Picklist rules evaluate against settled BOM

See `references/pst-two-step-pattern.md` for a reusable implementation template of this pattern.

### Step 5: Picklist attribute payload requirements
For Picklist-type attributes, the PST PATCH payload MUST include BOTH:
- `AttributeValue` — the display text (e.g., "Data Center Continuous (DCC)")
- `AttributePicklistValueId` — the ID of the `AttributePicklistValue` record

Missing `AttributePicklistValueId` causes silent failure: PST returns `internalSuccess: true` but the attribute reverts to its previous value.

### Step 6: DML for QuoteLineItemAttribute records
If you must insert/delete `QuoteLineItemAttribute` records directly (rare — prefer PST):

```apex
// Must use Database.insertImmediate / deleteImmediate
Database.insertImmediate(attrList);
Database.deleteImmediate(oldAttrList);
// Standard insert/delete fails: "Argument must be of internal sObject type"
```

### Step 7: Config Rules without saving (Run Config Rules Action)
Use the `Run Config Rules Action` standard invocable action in a Flow when you only need to evaluate rules and get eligibility results without committing changes. Confirmed against v68 (RLM Developer Guide, Chapter 7 › Run Config Rules Action, printed p.1088; URI `/services/data/v68.0/actions/standard/runConfigRules`):

Input: `transactionContextId`, `transactionId`
Output: `configRuleResult` (Apex-defined type `runtime_industries_cpq.ConfigRuleResult`), `transactionContextId`

> **Corrected for v68:** the action does not take `quoteId`/`quoteLineItemId`/a list of proposed
> attribute values as inputs, and its output field is `configRuleResult`, not `configResults`.
> The transaction context (quote, line item, and proposed attribute values) is resolved from
> the `transactionContextId`/`transactionId` inputs rather than passed directly.

This does NOT update BOM or prices. Use PST for full save.

### Step 8: Constraint Modeling Language (CML)
CML is a declarative rule language for expressing product configuration constraints without Apex. It's authored as `type`/`relation` declarations plus function-style rule statements (confirmed against v68, RLM Developer Guide, Chapter 7 › Constraint Modeling Language › Core Concepts, printed pp.1093–1146). Key rule keywords:

- **`require(condition, relation[type]{...}, message)`**: Forces a component/attribute state into the relationship when the condition is met
- **`exclude(...)`**: Automatically removes a type from a relationship when a condition is true (the one rule type allowed to override a user's prior selection)
- **`constraint(condition, message)`**: Validates a logical condition; displays an error if it can't be satisfied
- **Ranges**: expressed as a variable domain, e.g. `int requiredKW = [100..3000];`, not a separate `RANGE` block
- **`setdefault(condition, expression, message)`**: Sets a default value/selection when the condition is met
- **`preference(condition, message)`**: Encourages (but doesn't enforce) a condition
- **`recommend`**: Surfaces a suggested product/relation to the user

> **Corrected for v68:** the previous `REQUIRES`/`EXCLUDES`/`RANGE`/`DEFAULT`/`VISIBLE` uppercase
> block-keyword syntax shown in earlier revisions of this skill does not match any CML syntax
> found in the v68 guide. CML in v68 is function-call style (lowercase keywords, parentheses),
> declared inside `type`/`relation` blocks. See `references/cml-patterns.md` for corrected,
> doc-grounded examples.

CML rules are stored in `ProductConfigurationRule` records (`ConfigurationRuleDefinition` textarea field holds the rule text) and evaluated by the configurator engine at runtime. See `references/cml-patterns.md` for examples.

### Step 9: Object deployment sequence
```
1. ProductConfigurationRule    (no dependencies)
1. ProductConfigurationFlow    (→ UserFlowIdentifier)
1. ExpressionSetConstraintObj  (→ ExpressionSetId, ReferenceObjectId)
2. ProductConfigFlowAssignment (→ User, ProductId, ProductClassificationId, ProductConfigurationFlow)
```

## Common Issues

### PST returns internalSuccess: true but BOM not updated
Cause: `ConfigurationOptionsInput.executeConfigurationRules` not set to `true`, or attributes submitted in conflicting order (Number + Picklist in same call).
Solution: Set `executeConfigurationRules = true` on the `ConfigurationOptionsInput` passed to `PlaceSalesTransactionExecutor.execute()`. Use two-step sequencing for mixed attribute types.

### QuoteLineItemAttribute insert fails
Cause: Standard DML (`insert attrList`) used instead of `Database.insertImmediate()`.
Solution: Always use `Database.insertImmediate()` / `Database.deleteImmediate()` for QuoteLineItemAttribute.

### Config rules not evaluating
Cause: `ProductConfigFlowAssignment` missing for the product/classification combination, or Flow not activated.
Solution: Verify `ProductConfigFlowAssignment.ProductId` matches the quote line's product. Activate the associated Flow.

### Attribute value reverts after save
Cause: `AttributePicklistValueId` missing from PST payload for a Picklist attribute.
Solution: Always include both `AttributeValue` and `AttributePicklistValueId` in the PST PATCH for Picklist types.

## Examples

### Example 1: Read the current configuration of a QuoteLineItem
User says: "Show me the configuration for quote line item 0QL..."

1. Query `QuoteLineItemAttribute` (see Step 2)
2. For each attr, format: `AttributeDefinition.DeveloperName: AttributeValue`
3. Return structured summary to the user

### Example 2: Save attribute selections and get updated price
User says: "Set requiredKW to 1500 and DutyRating to DCC"

1. Build `numberSelections` = [{name: "requiredKW", value: "1500", dataType: "Number"}]
2. Build `picklistSelections` = [{name: "DutyRating", value: "DCC", picklistValueId: "xxx"}]
3. Call `executePst(numberSelections)` — BOM settles to 1500kW component
4. Call `executePst(picklistSelections)` — DCC Picklist rules applied
5. Query updated `QuoteLineItem.UnitPrice` + `Quote.GrandTotal`
6. Report: configuration saved, BOM = N components, Unit Price = $X, Grand Total = $Y

### Example 3: Check if a configuration is valid before saving
1. Call `Run Config Rules Action` invocable with `transactionContextId`/`transactionId`
2. Check `configRuleResult` for violations
3. Report any constraint failures to the user before committing

## See Also

| Skill | Why |
|---|---|
| `rlm-product-catalog` | Attribute definitions (`ProductClassificationAttr`, `AttributePicklistValue`) must exist before the configurator can read or save them |
| `rlm-pricing` | PST triggers pricing in the same call as BOM rule application; attribute changes reprice the line item automatically |
| `rlm-transaction-management` | The `QuoteLineItem` that holds attribute values is created by transaction management; configurator operates on an already-created line item |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 2.0.0 | 2026-09-11 | v68 (Winter '27) re-baseline: corrected PST Apex pattern to the real `RevSalesTrxn` namespace (`GraphRequest`/`RecordResource`/`RecordWithReferenceRequest`/`ConfigurationOptionsInput`/`PricingPreferenceEnum`/`ConfigurationExecutionEnum` — the previous `SalesTransactionGraph`/`SalesTransactionMode`/map-based `configOptions` pattern does not exist in the documented namespace); corrected `Run Config Rules Action` inputs/outputs; corrected CML rule syntax to the documented function-call style (`require()`/`exclude()`/`constraint()`/`setdefault()`/`preference()`); corrected `ProductConfigurationRule` field reference; annotated `AttributeDefinition.Sequence__c` as unverified; replaced page-number citations with section-title citations |
| 1.2.0 | 2026-05-02 | Added See Also table; added scripts/pst-template-order.cls for Order/OrderItem variant |
| 1.1.0 | 2026-04-30 | Added two-step PST sequencing (fix for Number+Picklist conflict); added scripts/pst-template.cls |
| 1.0.0 | 2026-04-01 | Initial skill — PST API, QuoteLineItemAttribute DML rules, CML patterns |

---

## References
- See `references/pst-api-patterns.md` for PST graph construction and common payloads
- See `references/cml-patterns.md` for Constraint Modeling Language examples
- See `references/pst-two-step-pattern.md` for PST sequencing and all critical patterns
- See `scripts/pst-template.cls` for a drop-in Apex starting point for Quote/QuoteLineItem — copy, rename, implement `buildGraph()`, done
- See `scripts/pst-template-order.cls` for the Order/OrderItem variant — used for asset amendment workflows
- RLM Developer Guide (v68.0, Winter '27) — Chapter 7: Product Configurator › Standard Objects, Business APIs, Std Invocable Actions
- RLM Developer Guide (v68.0, Winter '27) — Chapter 7: Product Configurator › Constraint Modeling Language (CML) › Core Concepts
- RLM Developer Guide (v68.0, Winter '27) — Chapter 8: Transaction Management › RevSalesTrxn Namespace

---
name: rlm-product-configurator
description: Save and read product attribute configurations on Revenue Cloud quotes and orders using the Place Sales Transaction (PST) API, including BOM bundle rule application and CML constraint rules (RLM v66). Use when configuring attributes on QuoteLineItems or OrderItems, applying BOM rules, or working with PlaceSalesTransactionExecutor. Do NOT use for product catalog setup (use rlm-product-catalog) or pricing-only changes (use rlm-pricing). Triggers on: "configure product", "save configuration", "product attributes", "attribute values", "BOM", "bundle rules", "PST", "Place Sales Transaction", "PlaceSalesTransactionExecutor", "config rules", "constraint model", "QuoteLineItemAttribute".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
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

### Step 3: Save attributes via PST API (ONLY correct path for BOM changes)
`PlaceSalesTransactionExecutor` is the only API that atomically:
1. Saves `QuoteLineItemAttribute` records
2. Applies BOM bundle rules (swaps child components)
3. Re-runs pricing

**Never use standard DML** on `QuoteLineItemAttribute` — it fails with "Argument must be of internal sObject type".

```apex
// Build the PST graph
RevSalesTrxn.SalesTransactionGraph graph = new RevSalesTrxn.SalesTransactionGraph();
// ... populate graph with quote + line item + attributes

Map<String, Object> configOptions = new Map<String, Object>();
configOptions.put('applyBomRules', true);
configOptions.put('applyPricing', true);

RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
    graph,
    RevSalesTrxn.SalesTransactionMode.SYSTEM,
    RevSalesTrxn.SalesTransactionMode.SYSTEM,
    configOptions,
    null
);
```

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
Use the `Run Config Rules Action` invocable action in a Flow when you only need to evaluate rules and get eligibility results without committing changes:

Input: `quoteId`, `quoteLineItemId`, list of proposed attribute values
Output: `configResults` with valid/invalid attribute values, constraint violations

This does NOT update BOM or prices. Use PST for full save.

### Step 8: Constraint Modeling Language (CML)
CML is a declarative rule language for expressing product configuration constraints without Apex. Key concepts:

- **Requires**: If attribute A = X, then attribute B must = Y
- **Excludes**: Attribute A = X is incompatible with attribute B = Y
- **Ranges**: Number attribute must be between min/max
- **Defaults**: Set default value for an attribute based on context

CML rules are stored in `ProductConfigurationRule` records and evaluated by the configurator engine at runtime. See `references/cml-patterns.md` for examples.

### Step 9: Object deployment sequence
```
1. ProductConfigurationRule    (no dependencies)
1. ProductConfigurationFlow    (→ UserFlowIdentifier)
1. ExpressionSetConstraintObj  (→ ExpressionSetId, ReferenceObjectId)
2. ProductConfigFlowAssignment (→ User, ProductId, ProductClassificationId, ProductConfigurationFlow)
```

## Common Issues

### PST returns internalSuccess: true but BOM not updated
Cause: `applyBomRules` option not set, or attributes submitted in conflicting order (Number + Picklist in same call).
Solution: Set `applyBomRules: true` in configOptions. Use two-step sequencing for mixed attribute types.

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
1. Call `Run Config Rules Action` invocable with proposed attribute values
2. Check `configResults` for violations
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
- RLM Developer Guide Chapter 7: Product Configurator (p. 874)
- RLM Developer Guide: Constraint Modeling Language (p. 993)

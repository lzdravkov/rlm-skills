# PST API Patterns — PlaceSalesTransactionExecutor

## Overview
`RevSalesTrxn.PlaceSalesTransactionExecutor` is the only correct path for saving product attribute configurations that trigger BOM restructuring and repricing in Revenue Cloud. Never use standard DML on `QuoteLineItemAttribute`.

---

## Apex: Full PST Save Pattern

```apex
/**
 * Saves attribute selections for a QuoteLineItem via PST.
 * Splits Number and Picklist attributes into two sequential calls
 * to avoid BOM-lock conflict (see Two-Step Sequencing below).
 */
public static void saveAttributes(
    String quoteId,
    String quoteLineItemId,
    List<AttributeInput> attributeInputs
) {
    List<AttributeInput> numberSelections = new List<AttributeInput>();
    List<AttributeInput> picklistSelections = new List<AttributeInput>();

    for (AttributeInput attr : attributeInputs) {
        if (attr.dataType == 'Picklist') {
            picklistSelections.add(attr);
        } else {
            numberSelections.add(attr);
        }
    }

    // Step 1: Numbers first — BOM restructures freely
    if (!numberSelections.isEmpty()) {
        executePst(quoteId, quoteLineItemId, numberSelections);
    }

    // Step 2: Picklist rules evaluate against settled BOM
    if (!picklistSelections.isEmpty()) {
        executePst(quoteId, quoteLineItemId, picklistSelections);
    }
}

private static void executePst(
    String quoteId,
    String quoteLineItemId,
    List<AttributeInput> attrs
) {
    // Build the sales transaction graph
    RevSalesTrxn.SalesTransactionGraph graph = buildGraph(quoteId, quoteLineItemId, attrs);

    Map<String, Object> configOptions = new Map<String, Object>{
        'applyBomRules' => true,
        'applyPricing'  => true
    };

    RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
        graph,
        RevSalesTrxn.SalesTransactionMode.SYSTEM,
        RevSalesTrxn.SalesTransactionMode.SYSTEM,
        configOptions,
        null
    );
}
```

---

## Two-Step PST Sequencing (CRITICAL)

**Problem**: When Number attributes (e.g., `requiredKW = 1500`) and BOM-restructuring Picklist attributes (e.g., `DutyRating = DCC`) are submitted in a single atomic PST call, PST silently overrides the Number value. It returns `internalSuccess: true` with no error, but the Number attribute reverts.

**Root cause**: The Picklist's BOM rules lock the component structure, preventing the Number attribute from swapping components in the same transaction.

**Fix**:
1. `executePst(numberSelections)` — BOM freely swaps to the correct component (e.g., FESBA_900kW → FESBA_1500kW)
2. `executePst(picklistSelections)` — Picklist rules now evaluate against the already-settled BOM

**Validated**: Quote line item with `requiredKW = 1500.0` and `DutyRating = Data Center Continuous (DCC)` — both saved correctly; BOM expanded to 24 components.

---

## Picklist Attribute Payload Requirements

For Picklist-type attributes, the PST PATCH payload MUST include BOTH fields:

| Field | Description | Example |
|---|---|---|
| `AttributeValue` | Display text of the selected option | `"Data Center Continuous (DCC)"` |
| `AttributePicklistValueId` | ID of the `AttributePicklistValue` record | `"0UZ..."` |

Missing `AttributePicklistValueId` causes a **silent failure**: PST returns `internalSuccess: true` but the attribute reverts to its prior value on the next read.

---

## DML on QuoteLineItemAttribute

Standard DML fails on `QuoteLineItemAttribute`:
```
// ERROR: "Argument must be of internal sObject type"
insert attrList;  // DO NOT USE
delete oldAttrList;  // DO NOT USE
```

Use `Database.insertImmediate` / `Database.deleteImmediate` only when direct DML is unavoidable (prefer PST):
```apex
Database.insertImmediate(attrList);
Database.deleteImmediate(oldAttrList);
```

---

## PST Response Validation

PST does not throw exceptions on logical failures. Always validate:
```apex
// internalSuccess: true does NOT mean attributes were saved correctly.
// Perform a post-save SOQL readback to confirm actual persisted values.
List<QuoteLineItemAttribute> saved = [
    SELECT AttributeDefinition.DeveloperName, AttributeValue, AttributePicklistValueId
    FROM QuoteLineItemAttribute
    WHERE QuoteLineItemId = :quoteLineItemId
];
// Compare saved values against submitted values to detect silent overrides.
```

---

## AttributeInput Helper Class

```apex
public class AttributeInput {
    public String developerName;
    public String dataType;         // 'Picklist' | 'Number' | 'Text' | 'Boolean'
    public String value;            // display text or number string
    public String picklistValueId;  // required for Picklist type
}
```

# PST API Patterns — PlaceSalesTransactionExecutor

## Overview
`RevSalesTrxn.PlaceSalesTransactionExecutor` is the only correct path for saving product attribute configurations that trigger BOM restructuring and repricing in Revenue Cloud. Never use standard DML on `QuoteLineItemAttribute`.

---

## Apex: Full PST Save Pattern

> **Corrected for v68 (RLM Developer Guide, Chapter 8 › RevSalesTrxn Namespace, printed
> p.1737):** the `RevSalesTrxn` namespace does **not** contain `SalesTransactionGraph` or
> `SalesTransactionMode` — neither exists in the documented v68 namespace class list, and
> `ConfigurationOptionsInput` is a typed class (Boolean properties `addDefaultConfiguration`,
> `executeConfigurationRules`, `validateAmendRenewCancel`, `validateProductCatalog`), not a
> `Map<String, Object>` with `applyBomRules`/`applyPricing` keys. The graph is built from
> `RecordResource` + `RecordWithReferenceRequest` objects wrapped in a `GraphRequest`, and
> `execute()` takes a `PricingPreferenceEnum` and a `ConfigurationExecutionEnum` (not two
> `SalesTransactionMode` values). The pattern below is adapted from the guide's own
> `PlaceSalesTransactionTest.callPSTAPI_Post()` worked example (printed pp.1751–1756).

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
    // Build one RecordResource per attribute to create, wrap each in a
    // RecordWithReferenceRequest, and collect them into a single GraphRequest.
    List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>();
    Integer refIdx = 0;
    for (AttributeInput attr : attrs) {
        RevSalesTrxn.RecordResource attrResource =
            new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.getSobjectType(), 'POST');
        Map<String, Object> fieldValues = new Map<String, Object>();
        fieldValues.put('QuoteLineItemId', quoteLineItemId);
        fieldValues.put('AttributeValue', attr.value);
        if (attr.dataType == 'Picklist') {
            // Both fields are required for Picklist types — see Payload Requirements below.
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

    RevSalesTrxn.PlaceSalesTransactionResponse response = RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
        graphRequest,
        RevSalesTrxn.PricingPreferenceEnum.SYSTEM,
        RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM,
        configOptions,
        null   // contextId — not required when starting a new transaction
    );
}
```
> Field names on `QuoteLineItemAttribute` match the existing skill assumptions and the Payload
> Requirements section below; they were not independently re-verified against the Ch.8
> Transaction Management field list in this pass — confirm against your org if you see
> field-not-found errors.

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

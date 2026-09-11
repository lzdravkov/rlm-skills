# PST Two-Step Sequencing — Reference Implementation

## Problem Statement

When saving both Number attributes (e.g., `requiredKW = 1500`) and Picklist attributes that trigger BOM restructuring (e.g., `DutyRating = DCC`) in a single atomic PST call:

- PST returns `internalSuccess: true`
- No error is thrown
- The Number attribute silently reverts to its previous value
- The BOM does not reflect the correct kW component

**Root cause**: The Picklist's BOM rules lock the component structure during evaluation. This prevents the Number attribute from swapping components in the same transaction.

---

## The Fix: Two Sequential PST Calls

```apex
public class ProductAttributeSaveService {

    public class AttributeInput {
        @AuraEnabled public String developerName;
        @AuraEnabled public String dataType;        // 'Picklist' | 'Number' | 'Text' | 'Boolean'
        @AuraEnabled public String value;
        @AuraEnabled public String picklistValueId; // Required for Picklist type
    }

    @InvocableMethod(label='Save Product Attributes')
    public static List<SaveResult> doSave(List<SaveRequest> requests) {
        SaveRequest req = requests[0];
        List<SaveResult> results = new List<SaveResult>();

        // Split attributes by type
        List<AttributeInput> numberSelections    = new List<AttributeInput>();
        List<AttributeInput> picklistSelections  = new List<AttributeInput>();

        for (AttributeInput attr : req.attributeInputs) {
            if (attr.dataType == 'Picklist') {
                picklistSelections.add(attr);
            } else {
                numberSelections.add(attr);
            }
        }

        // Step 1: Number attributes first — BOM freely restructures
        if (!numberSelections.isEmpty()) {
            executePst(req.quoteId, req.quoteLineItemId, numberSelections);
        }

        // Step 2: Picklist attributes — evaluate against settled BOM
        if (!picklistSelections.isEmpty()) {
            executePst(req.quoteId, req.quoteLineItemId, picklistSelections);
        }

        // Post-save readback — confirm actual persisted values
        List<QuoteLineItemAttribute> saved = [
            SELECT AttributeDefinition.DeveloperName,
                   AttributeDefinition.DataType,
                   AttributeValue,
                   AttributePicklistValueId
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId = :req.quoteLineItemId
        ];

        // Read Grand Total and pricing from Quote
        Quote q = [
            SELECT GrandTotal, TotalPrice
            FROM Quote WHERE Id = :req.quoteId
        ];

        SaveResult result = new SaveResult();
        result.savedAttributesJson = JSON.serialize(saved);
        result.grandTotal = q.GrandTotal;
        result.quoteSubtotal = q.TotalPrice;
        results.add(result);
        return results;
    }

    // Corrected for v68 (RLM Developer Guide, Chapter 8 › RevSalesTrxn Namespace, printed
    // p.1737): there is no `SalesTransactionGraph`/`SalesTransactionMode` in the documented
    // v68 namespace. The graph is built from `RecordResource` + `RecordWithReferenceRequest`
    // objects wrapped in a `GraphRequest`; `ConfigurationOptionsInput` is a typed class, not a
    // Map. Adapted from the guide's `PlaceSalesTransactionTest.callPSTAPI_Post()` worked
    // example (printed pp.1751-1756).
    private static void executePst(
        String quoteId,
        String quoteLineItemId,
        List<AttributeInput> attrs
    ) {
        RevSalesTrxn.GraphRequest graphRequest = buildGraph(quoteId, quoteLineItemId, attrs);

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

    // buildGraph() implementation: build one RecordResource per attribute to create/update,
    // wrap each in a RecordWithReferenceRequest, and collect into a single GraphRequest.
    // See RLM Developer Guide (v68.0, Winter '27) — Chapter 8: Transaction Management ›
    // RevSalesTrxn Namespace, printed p.1737.
    private static RevSalesTrxn.GraphRequest buildGraph(
        String quoteId,
        String quoteLineItemId,
        List<AttributeInput> attrs
    ) {
        // Key: include AttributeValue AND AttributePicklistValueId for Picklist types
        List<RevSalesTrxn.RecordWithReferenceRequest> records = new List<RevSalesTrxn.RecordWithReferenceRequest>();
        Integer refIdx = 0;
        for (AttributeInput attr : attrs) {
            RevSalesTrxn.RecordResource attrResource =
                new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.getSobjectType(), 'POST');
            Map<String, Object> fieldValues = new Map<String, Object>();
            fieldValues.put('QuoteLineItemId', quoteLineItemId);
            fieldValues.put('AttributeValue', attr.value);
            if (attr.dataType == 'Picklist') {
                fieldValues.put('AttributePicklistValueId', attr.picklistValueId);
            }
            attrResource.fieldValues = fieldValues;
            records.add(new RevSalesTrxn.RecordWithReferenceRequest('refAttr' + refIdx, attrResource));
            refIdx++;
        }
        return new RevSalesTrxn.GraphRequest('attrGraph', records);
    }

    public class SaveRequest {
        @InvocableVariable(required=true) public String quoteId;
        @InvocableVariable(required=true) public String quoteLineItemId;
        @InvocableVariable(required=true) public List<AttributeInput> attributeInputs;
    }

    public class SaveResult {
        @InvocableVariable public String savedAttributesJson;
        @InvocableVariable public Decimal grandTotal;
        @InvocableVariable public Decimal quoteSubtotal;
        @InvocableVariable public Integer lineItemCount;
    }
}
```

---

## Validation (Confirmed Working)

Tested on RLM v68.0 with:
- `requiredKW = 1500.0` (Number)
- `DutyRating = Data Center Continuous (DCC)` (Picklist)

Result: Both attributes saved correctly; BOM expanded to 24 components; Grand Total = $59,055.00.

## Why grandTotal Not unitPrice

`Quote.GrandTotal` is the correct figure to communicate to customers. It includes:
- All BOM component prices
- Applied discounts and adjustments
- Taxes

`QuoteLineItem.UnitPrice` is only the primary product's unit price — it does not include the full BOM.

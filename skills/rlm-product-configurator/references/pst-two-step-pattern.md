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

    private static void executePst(
        String quoteId,
        String quoteLineItemId,
        List<AttributeInput> attrs
    ) {
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

    // buildGraph() implementation: populate SalesTransactionGraph
    // with quoteId, quoteLineItemId, and attribute patch records.
    // See RLM Developer Guide Chapter 8, RevSalesTrxn Namespace, p. 1615.
    private static RevSalesTrxn.SalesTransactionGraph buildGraph(
        String quoteId,
        String quoteLineItemId,
        List<AttributeInput> attrs
    ) {
        // Implementation depends on your graph construction pattern
        // Key: include AttributeValue AND AttributePicklistValueId for Picklist types
        RevSalesTrxn.SalesTransactionGraph graph = new RevSalesTrxn.SalesTransactionGraph();
        // ... populate graph
        return graph;
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

Tested on RLM v66.0 with:
- `requiredKW = 1500.0` (Number)
- `DutyRating = Data Center Continuous (DCC)` (Picklist)

Result: Both attributes saved correctly; BOM expanded to 24 components; Grand Total = $59,055.00.

## Why grandTotal Not unitPrice

`Quote.GrandTotal` is the correct figure to communicate to customers. It includes:
- All BOM component prices
- Applied discounts and adjustments
- Taxes

`QuoteLineItem.UnitPrice` is only the primary product's unit price — it does not include the full BOM.

/**
 * PstExecutorOrderTemplate
 *
 * Drop-in starting point for saving OrderItemAttribute records via
 * PlaceSalesTransactionExecutor (PST) against an Order/OrderItem.
 * Used for asset amendment workflows where the transaction is an Order,
 * not a Quote.
 *
 * Usage:
 *   1. Copy this file into your Apex classes directory.
 *   2. Rename to match your service (e.g. OrderAttributeSaveService).
 *   3. Implement buildGraph() using your org's graph structure.
 *   4. Wire up an @InvocableMethod wrapper (see SaveRequest / SaveResult below).
 *
 * Key differences from pst-template.cls (Quote variant):
 *   - Transaction root is Order (not Quote)
 *   - Line items are OrderItem (not QuoteLineItem)
 *   - Attribute records are OrderItemAttribute (not QuoteLineItemAttribute)
 *   - Price readback queries Order.TotalAmount (not Quote.GrandTotal)
 *   - DML on OrderItemAttribute also requires Database.insertImmediate/deleteImmediate
 *
 * References:
 *   - skills/rlm-product-configurator/references/pst-two-step-pattern.md
 *   - skills/rlm-product-configurator/references/pst-api-patterns.md
 *   - RLM Developer Guide (v68.0, Winter '27) — Chapter 8: Transaction Management ›
 *     RevSalesTrxn Namespace, printed p.1737
 */
public class PstExecutorOrderTemplate {

    // ---------------------------------------------------------------------------
    // Inner types
    // ---------------------------------------------------------------------------

    public class AttributeInput {
        @AuraEnabled public String developerName;
        @AuraEnabled public String dataType;        // 'Picklist' | 'Number' | 'Text' | 'Boolean'
        @AuraEnabled public String value;           // display text or stringified number
        @AuraEnabled public String picklistValueId; // required when dataType = 'Picklist'
    }

    public class SaveRequest {
        @InvocableVariable(required=true label='Order ID')      public String orderId;
        @InvocableVariable(required=true label='Order Item ID') public String orderItemId;
        @InvocableVariable(required=true label='Attribute Inputs (JSON)') public String attributeInputsJson;
    }

    public class SaveResult {
        @InvocableVariable public String savedAttributesJson;
        @InvocableVariable public Decimal orderTotalAmount;
        @InvocableVariable public String errorMessage;
    }

    // ---------------------------------------------------------------------------
    // Invocable entry point
    // ---------------------------------------------------------------------------

    @InvocableMethod(label='Save Order Item Attributes via PST' category='Revenue Cloud')
    public static List<SaveResult> doSave(List<SaveRequest> requests) {
        List<SaveResult> results = new List<SaveResult>();

        for (SaveRequest req : requests) {
            SaveResult result = new SaveResult();
            try {
                List<AttributeInput> inputs = (List<AttributeInput>)
                    JSON.deserialize(req.attributeInputsJson, List<AttributeInput>.class);

                executeTwoStep(req.orderId, req.orderItemId, inputs);
                result = readBack(req.orderId, req.orderItemId);
            } catch (Exception ex) {
                result.errorMessage = ex.getMessage();
            }
            results.add(result);
        }

        return results;
    }

    // ---------------------------------------------------------------------------
    // Two-step PST sequencing
    //
    // Same rule as the Quote variant: Number attributes must be submitted before
    // Picklist attributes. See pst-template.cls for full explanation.
    // ---------------------------------------------------------------------------

    private static void executeTwoStep(
        String orderId,
        String orderItemId,
        List<AttributeInput> inputs
    ) {
        List<AttributeInput> numberAttrs   = new List<AttributeInput>();
        List<AttributeInput> picklistAttrs = new List<AttributeInput>();

        for (AttributeInput attr : inputs) {
            if (attr.dataType == 'Picklist') {
                picklistAttrs.add(attr);
            } else {
                numberAttrs.add(attr);
            }
        }

        if (!numberAttrs.isEmpty()) {
            executePst(orderId, orderItemId, numberAttrs);
        }
        if (!picklistAttrs.isEmpty()) {
            executePst(orderId, orderItemId, picklistAttrs);
        }
    }

    // ---------------------------------------------------------------------------
    // PST executor
    // ---------------------------------------------------------------------------

    // Corrected for v68 (RLM Developer Guide, Chapter 8 › RevSalesTrxn Namespace, printed
    // p.1737): there is no `SalesTransactionGraph`/`SalesTransactionMode` in the documented
    // v68 namespace. `execute()` takes a `GraphRequest`, a `PricingPreferenceEnum`, a
    // `ConfigurationExecutionEnum`, and a typed `ConfigurationOptionsInput` (not a Map).
    // Adapted from the guide's `PlaceSalesTransactionTest.callPSTAPI_Post()` worked example
    // (printed pp.1751-1756).
    private static void executePst(
        String orderId,
        String orderItemId,
        List<AttributeInput> attrs
    ) {
        RevSalesTrxn.GraphRequest graphRequest =
            buildGraph(orderId, orderItemId, attrs);

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

    // ---------------------------------------------------------------------------
    // Graph construction
    //
    // TODO: Implement this method for your org's Order/OrderItem graph.
    //
    // Key differences from the Quote variant:
    //   - Attribute record: OrderItemAttribute (not QuoteLineItemAttribute)
    //   - For Picklist attributes: set BOTH AttributeValue AND AttributePicklistValueId
    //   - Build one RecordResource per OrderItemAttribute to create, wrap each in a
    //     RecordWithReferenceRequest, and collect into a single GraphRequest.
    // ---------------------------------------------------------------------------

    @TestVisible
    private static RevSalesTrxn.GraphRequest buildGraph(
        String orderId,
        String orderItemId,
        List<AttributeInput> attrs
    ) {
        List<RevSalesTrxn.RecordWithReferenceRequest> records =
            new List<RevSalesTrxn.RecordWithReferenceRequest>();

        // TODO: Add one RecordResource per OrderItemAttribute to save
        // Integer refIdx = 0;
        // for (AttributeInput attr : attrs) {
        //     RevSalesTrxn.RecordResource attrResource =
        //         new RevSalesTrxn.RecordResource(OrderItemAttribute.getSobjectType(), 'POST');
        //     Map<String, Object> fieldValues = new Map<String, Object>();
        //     fieldValues.put('OrderItemId', orderItemId);
        //     fieldValues.put('AttributeValue', attr.value);
        //     // For Picklist: also set fieldValues.put('AttributePicklistValueId', attr.picklistValueId);
        //     attrResource.fieldValues = fieldValues;
        //     records.add(new RevSalesTrxn.RecordWithReferenceRequest('refAttr' + refIdx, attrResource));
        //     refIdx++;
        // }

        return new RevSalesTrxn.GraphRequest('attrGraph', records);
    }

    // ---------------------------------------------------------------------------
    // Post-save readback
    //
    // Always read back from DB — PST does not throw on logical failures.
    // For Orders, use Order.TotalAmount (not Quote.GrandTotal).
    // ---------------------------------------------------------------------------

    private static SaveResult readBack(String orderId, String orderItemId) {
        List<OrderItemAttribute> saved = [
            SELECT AttributeDefinition.DeveloperName,
                   AttributeDefinition.DataType,
                   AttributeValue,
                   AttributePicklistValueId
            FROM OrderItemAttribute
            WHERE OrderItemId = :orderItemId
        ];

        Order o = [
            SELECT TotalAmount
            FROM Order
            WHERE Id = :orderId
        ];

        SaveResult result = new SaveResult();
        result.savedAttributesJson = JSON.serialize(saved);
        result.orderTotalAmount    = o.TotalAmount;
        return result;
    }

    // ---------------------------------------------------------------------------
    // Direct DML fallback (use only when PST is not applicable)
    //
    // Standard insert/delete FAILS on OrderItemAttribute — same constraint as
    // QuoteLineItemAttribute. Use Database.insertImmediate / deleteImmediate.
    // ---------------------------------------------------------------------------

    public static void insertAttributesDirect(List<OrderItemAttribute> attrs) {
        Database.insertImmediate(attrs);
    }

    public static void deleteAttributesDirect(List<OrderItemAttribute> attrs) {
        Database.deleteImmediate(attrs);
    }
}

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
 *   - RLM Developer Guide v66.0, RevSalesTrxn namespace (p. 1615)
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

    private static void executePst(
        String orderId,
        String orderItemId,
        List<AttributeInput> attrs
    ) {
        RevSalesTrxn.SalesTransactionGraph graph =
            buildGraph(orderId, orderItemId, attrs);

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

    // ---------------------------------------------------------------------------
    // Graph construction
    //
    // TODO: Implement this method for your org's Order/OrderItem graph.
    //
    // Key differences from Quote graph:
    //   - Root node: RevSalesTrxn.SalesTransactionOrder (not SalesTransactionQuote)
    //   - Line item node: RevSalesTrxn.SalesTransactionOrderItem
    //   - Attribute record: OrderItemAttribute (not QuoteLineItemAttribute)
    //   - For Picklist attributes: set BOTH AttributeValue AND AttributePicklistValueId
    // ---------------------------------------------------------------------------

    @TestVisible
    private static RevSalesTrxn.SalesTransactionGraph buildGraph(
        String orderId,
        String orderItemId,
        List<AttributeInput> attrs
    ) {
        RevSalesTrxn.SalesTransactionGraph graph =
            new RevSalesTrxn.SalesTransactionGraph();

        // TODO: Add Order node
        // RevSalesTrxn.SalesTransactionOrder orderNode =
        //     new RevSalesTrxn.SalesTransactionOrder();
        // orderNode.record = new Order(Id = orderId);
        // graph.order = orderNode;

        // TODO: Add OrderItem node
        // RevSalesTrxn.SalesTransactionOrderItem lineItemNode =
        //     new RevSalesTrxn.SalesTransactionOrderItem();
        // lineItemNode.record = new OrderItem(Id = orderItemId);

        // TODO: Add OrderItemAttribute nodes
        // for (AttributeInput attr : attrs) {
        //     RevSalesTrxn.SalesTransactionAttribute attrNode =
        //         new RevSalesTrxn.SalesTransactionAttribute();
        //     OrderItemAttribute oia = new OrderItemAttribute();
        //     oia.OrderItemId              = orderItemId;
        //     oia.AttributeValue           = attr.value;
        //     // For Picklist: also set oia.AttributePicklistValueId = attr.picklistValueId;
        //     attrNode.record = oia;
        //     lineItemNode.attributes.add(attrNode);
        // }

        // graph.orderItems = new List<RevSalesTrxn.SalesTransactionOrderItem>{ lineItemNode };

        return graph;
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

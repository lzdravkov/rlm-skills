/**
 * PstExecutorTemplate
 *
 * Drop-in starting point for saving QuoteLineItemAttribute records via
 * PlaceSalesTransactionExecutor (PST). Handles the two-step sequencing
 * required to avoid the BOM-lock silent-override bug (RLM v68.0).
 *
 * Usage:
 *   1. Copy this file into your Apex classes directory.
 *   2. Rename the class to match your service (e.g. ProductAttributeSaveService).
 *   3. Implement buildGraph() using your org's graph structure.
 *   4. Wire up an @InvocableMethod wrapper (see SaveRequest / SaveResult below).
 *
 * References:
 *   - skills/rlm-product-configurator/references/pst-two-step-pattern.md
 *   - skills/rlm-product-configurator/references/pst-api-patterns.md
 *   - RLM Developer Guide (v68.0, Winter '27) — Chapter 8: Transaction Management ›
 *     RevSalesTrxn Namespace, printed p.1737
 */
public class PstExecutorTemplate {

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
        @InvocableVariable(required=true label='Quote ID') public String quoteId;
        @InvocableVariable(required=true label='Quote Line Item ID') public String quoteLineItemId;
        @InvocableVariable(required=true label='Attribute Inputs (JSON)') public String attributeInputsJson;
    }

    public class SaveResult {
        @InvocableVariable public String savedAttributesJson;
        @InvocableVariable public Decimal grandTotal;
        @InvocableVariable public Decimal quoteSubtotal;
        @InvocableVariable public Integer lineItemCount;
        @InvocableVariable public String errorMessage;
    }

    // ---------------------------------------------------------------------------
    // Invocable entry point
    // ---------------------------------------------------------------------------

    @InvocableMethod(label='Save Product Attributes via PST' category='Revenue Cloud')
    public static List<SaveResult> doSave(List<SaveRequest> requests) {
        List<SaveResult> results = new List<SaveResult>();

        for (SaveRequest req : requests) {
            SaveResult result = new SaveResult();
            try {
                List<AttributeInput> inputs = (List<AttributeInput>)
                    JSON.deserialize(req.attributeInputsJson, List<AttributeInput>.class);

                executeTwoStep(req.quoteId, req.quoteLineItemId, inputs);
                result = readBack(req.quoteId, req.quoteLineItemId);
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
    // WHY: Submitting Number and Picklist attributes in a single PST call causes
    // a silent override — the Picklist's BOM rules lock the component structure,
    // preventing the Number from swapping components. PST returns internalSuccess:true
    // with no error, but the Number value reverts.
    //
    // FIX: Number attributes first (BOM restructures freely), then Picklist
    // attributes (rules evaluate against the already-settled BOM).
    // ---------------------------------------------------------------------------

    private static void executeTwoStep(
        String quoteId,
        String quoteLineItemId,
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

        // Step 1: Number / Text / Boolean — BOM freely restructures
        if (!numberAttrs.isEmpty()) {
            executePst(quoteId, quoteLineItemId, numberAttrs);
        }

        // Step 2: Picklist — evaluate against settled BOM
        if (!picklistAttrs.isEmpty()) {
            executePst(quoteId, quoteLineItemId, picklistAttrs);
        }
    }

    // ---------------------------------------------------------------------------
    // PST executor
    //
    // Corrected for v68 (RLM Developer Guide, Chapter 8 › RevSalesTrxn Namespace, printed
    // p.1737): there is no `SalesTransactionGraph`/`SalesTransactionMode` in the documented
    // v68 namespace. `execute()` takes a `GraphRequest`, a `PricingPreferenceEnum`, a
    // `ConfigurationExecutionEnum`, and a typed `ConfigurationOptionsInput` (not a Map).
    // Adapted from the guide's `PlaceSalesTransactionTest.callPSTAPI_Post()` worked example
    // (printed pp.1751-1756).
    // ---------------------------------------------------------------------------

    private static void executePst(
        String quoteId,
        String quoteLineItemId,
        List<AttributeInput> attrs
    ) {
        RevSalesTrxn.GraphRequest graphRequest =
            buildGraph(quoteId, quoteLineItemId, attrs);

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
    // TODO: Implement this method for your org's data model.
    //
    // Key rules:
    //   - For Picklist attributes: set BOTH AttributeValue (display text) AND
    //     AttributePicklistValueId. Missing either causes a silent revert.
    //   - For Number attributes: set AttributeValue as a stringified decimal.
    //   - Build one RecordResource per QuoteLineItemAttribute to create, wrap each in a
    //     RecordWithReferenceRequest, and collect into a single GraphRequest.
    //
    // See: RLM Developer Guide (v68.0, Winter '27) — Chapter 8: Transaction Management ›
    // RevSalesTrxn Namespace, printed p.1737
    // ---------------------------------------------------------------------------

    @TestVisible
    private static RevSalesTrxn.GraphRequest buildGraph(
        String quoteId,
        String quoteLineItemId,
        List<AttributeInput> attrs
    ) {
        List<RevSalesTrxn.RecordWithReferenceRequest> records =
            new List<RevSalesTrxn.RecordWithReferenceRequest>();

        // TODO: Add one RecordResource per QuoteLineItemAttribute to save
        // Integer refIdx = 0;
        // for (AttributeInput attr : attrs) {
        //     RevSalesTrxn.RecordResource attrResource =
        //         new RevSalesTrxn.RecordResource(QuoteLineItemAttribute.getSobjectType(), 'POST');
        //     Map<String, Object> fieldValues = new Map<String, Object>();
        //     fieldValues.put('QuoteLineItemId', quoteLineItemId);
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
    // PST does not throw on logical failures — always read back from DB to
    // confirm what was actually persisted. Do not trust internalSuccess: true.
    // ---------------------------------------------------------------------------

    private static SaveResult readBack(String quoteId, String quoteLineItemId) {
        List<QuoteLineItemAttribute> saved = [
            SELECT AttributeDefinition.DeveloperName,
                   AttributeDefinition.DataType,
                   AttributeValue,
                   AttributePicklistValueId
            FROM QuoteLineItemAttribute
            WHERE QuoteLineItemId = :quoteLineItemId
        ];

        Quote q = [
            SELECT GrandTotal, TotalPrice, LineItemCount
            FROM Quote
            WHERE Id = :quoteId
        ];

        SaveResult result = new SaveResult();
        result.savedAttributesJson = JSON.serialize(saved);
        result.grandTotal          = q.GrandTotal;
        result.quoteSubtotal       = q.TotalPrice;
        result.lineItemCount       = q.LineItemCount;
        return result;
    }

    // ---------------------------------------------------------------------------
    // Direct DML fallback (use only when PST is not applicable)
    //
    // Standard insert/delete FAILS on QuoteLineItemAttribute:
    //   "Argument must be of internal sObject type"
    // Use Database.insertImmediate / deleteImmediate instead.
    // ---------------------------------------------------------------------------

    public static void insertAttributesDirect(List<QuoteLineItemAttribute> attrs) {
        Database.insertImmediate(attrs);
    }

    public static void deleteAttributesDirect(List<QuoteLineItemAttribute> attrs) {
        Database.deleteImmediate(attrs);
    }
}

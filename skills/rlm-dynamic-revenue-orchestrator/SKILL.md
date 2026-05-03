---
name: rlm-dynamic-revenue-orchestrator
description: Design and implement fulfillment workflows using Salesforce Revenue Cloud's Dynamic Revenue Orchestrator (DRO). Use when creating fulfillment plans, defining fulfillment steps and step definitions, wiring callout providers (Standard HTTP, Apex Type, or External Services), handling async fulfillment callbacks, or subscribing to DRO platform events. Do NOT use for billing or payment processing (use rlm-billing) or product configuration (use rlm-product-configurator). Triggers on: "fulfillment", "fulfillment plan", "fulfillment step", "orchestrator", "DRO", "callout provider", "FulfillmentPlan", "FulfillmentStep", "FulfillmentStepDefinition", "SalesTrxnDecompositionEvent", "FulfillmentSourceChangeEvent", "provisioning", "async fulfillment", "Named Credential fulfillment", "industriesintegrationfwk".
compatibility: Salesforce Revenue Cloud, API v66.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Dynamic Revenue Orchestrator (DRO)

## Object Hierarchy

```
FulfillmentStepDefinitionGroup     (groups step definitions — no dependencies)
  └── FulfillmentStepDefinition[]  (defines what a step does — callout provider, input/output)
       └── ProductFulfillmentScenario  (maps a product to a fulfillment scenario)

FulfillmentPlan                    (top-level fulfillment plan)
  └── FulfillmentStep[]            (individual steps in the plan)
       └── BindingObjectCustomExt  (custom metadata for a step)
```

Deployment sequence:
```
1. FulfillmentStepDefinitionGroup
2. FulfillmentStepDefinition      (→ FulfillmentStepDefinitionGroup)
3. ProductFulfillmentScenario     (→ Product2, FulfillmentStepDefinition)
4. FulfillmentPlan                (→ Quote or Order)
5. FulfillmentStep                (→ FulfillmentPlan, FulfillmentStepDefinition)
```

---

## Instructions

### Step 1: Define Fulfillment Step Groups and Definitions

```apex
// Create step definition group
FulfillmentStepDefinitionGroup group = new FulfillmentStepDefinitionGroup();
group.Name = 'Network Provisioning';
group.DeveloperName = 'Network_Provisioning';
insert group;

// Create step definition
FulfillmentStepDefinition stepDef = new FulfillmentStepDefinition();
stepDef.Name = 'Provision VPN';
stepDef.DeveloperName = 'Provision_VPN';
stepDef.FulfillmentStepDefinitionGroupId = group.Id;
stepDef.CalloutType = 'StandardFulfillmentProvider';  // see Step 2
insert stepDef;
```

### Step 2: Callout Provider Types

DRO supports three callout provider patterns:

#### Type 1: Standard Fulfillment Provider (Named Credential + HTTP)

Uses a Named Credential to make an HTTP callout. No Apex code required.

```apex
FulfillmentStepDefinition stepDef = new FulfillmentStepDefinition();
stepDef.CalloutType = 'StandardFulfillmentProvider';
stepDef.NamedCredentialId = namedCredential.Id;
stepDef.HttpMethod = 'POST';
stepDef.Endpoint = '/api/provision';
stepDef.RequestBodyTemplate = '{"orderId": "{OrderId}", "productCode": "{ProductCode}"}';
insert stepDef;
```

**Async behavior**: If the external service returns HTTP 202, the step remains in `Running` status until the service calls back. If it returns HTTP 200, the step immediately moves to `Completed`.

#### Type 2: Apex Type Provider

Implements `industriesintegrationfwk.ProcessIntegrationProvider` interface for custom Apex logic.

```apex
global class DROSampleOrderAdapter
    implements industriesintegrationfwk.ProcessIntegrationProvider {

    global static industriesintegrationfwk.IntegrationCalloutResponse executeCallout(
        String requestGuid,
        String inputRecordId,
        String payload,
        Map<String, Object> attributes
    ) {
        // Your custom provisioning logic here
        Boolean success = doProvisioning(inputRecordId, payload);

        industriesintegrationfwk.IntegrationCalloutResponse icr =
            new industriesintegrationfwk.IntegrationCalloutResponse(success);

        if (!success) {
            icr.setResponseCode(500);
            icr.setErrorMessage('Provisioning failed: external system unavailable.');
        }
        return icr;
    }

    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return new List<industriesintegrationfwk.ApexProviderAttr>{
            new industriesintegrationfwk.ApexProviderAttr('endpoint', 'https://api.example.com', false),
            new industriesintegrationfwk.ApexProviderAttr('apiKey', '', true)  // true = required
        };
    }
}
```

Then reference the Apex class in the step definition:
```apex
stepDef.CalloutType = 'ApexTypeProvider';
stepDef.ApexClassName = 'DROSampleOrderAdapter';
```

#### Type 3: External Services Defined Provider

Uses a registered External Service (OpenAPI spec imported into Salesforce) to call an external API. No custom Apex required.

```apex
stepDef.CalloutType = 'ExternalServicesDefinedProvider';
stepDef.ExternalServiceName = 'ProvisioningService';
stepDef.ExternalServiceOperationName = 'provisionResource';
```

### Step 3: Map Products to Fulfillment Scenarios

```apex
ProductFulfillmentScenario scenario = new ProductFulfillmentScenario();
scenario.Product2Id = product.Id;
scenario.FulfillmentStepDefinitionId = stepDef.Id;
scenario.Name = 'VPN Product Provisioning';
scenario.IsActive = true;
insert scenario;
```

### Step 4: Create and Execute Fulfillment Plans

Fulfillment plans are typically created by the platform automatically when an Order is placed. To create manually:

```apex
FulfillmentPlan plan = new FulfillmentPlan();
plan.OrderId = order.Id;
plan.Status = 'Draft';
insert plan;

FulfillmentStep step = new FulfillmentStep();
step.FulfillmentPlanId = plan.Id;
step.FulfillmentStepDefinitionId = stepDef.Id;
step.Status = 'Pending';
step.Sequence = 1;
insert step;
```

### Step 5: Subscribe to DRO Platform Events

DRO publishes two platform events for async fulfillment tracking:

#### FulfillmentSourceChangeEvent (API v66.0)

Published when a fulfillment source record changes state.

**Channel**: `/event/FulfillmentSourceChangeEvent`

| Field | Type | Description |
|---|---|---|
| `EventUuid` | String | Unique event ID |
| `RecordIdentifier` | String | ID of the changed fulfillment source record |
| `ReplayId` | String | CometD replay ID |

**Supported subscribers**: Apex Triggers ✓, Flows ✓, Pub/Sub API ✓, Streaming API ✓

```apex
trigger FulfillmentSourceChangeTrigger on FulfillmentSourceChangeEvent (after insert) {
    for (FulfillmentSourceChangeEvent evt : Trigger.new) {
        String recordId = evt.RecordIdentifier;
        // Handle fulfillment source state change
        FulfillmentStep step = [SELECT Id, Status FROM FulfillmentStep WHERE Id = :recordId];
        if (step.Status == 'Running') {
            // External callback indicates completion — update step
        }
    }
}
```

#### SalesTrxnDecompositionEvent (API v66.0)

Published when a sales transaction decomposition completes or fails.

**Channel**: `/event/SalesTrxnDecompositionEvent`

| Field | Type | Description |
|---|---|---|
| `EventUuid` | String | Unique event ID |
| `ReplayId` | String | CometD replay ID |
| `SalesTransactionIdentifier` | String | ID of the sales transaction being decomposed |
| `Status` | String | Final status: `Completed` \| `Failed` |
| `ErrorCode` | String | Error code if Status = `Failed` |

**Supported subscribers**: Apex Triggers ✓, Flows ✓, Pub/Sub API ✓, Streaming API ✓

```apex
trigger SalesTrxnDecompositionTrigger on SalesTrxnDecompositionEvent (after insert) {
    for (SalesTrxnDecompositionEvent evt : Trigger.new) {
        if (evt.Status == 'Failed') {
            // Alert on failure, create a case, retry logic, etc.
            System.debug('Decomposition failed: ' + evt.ErrorCode
                + ' for transaction: ' + evt.SalesTransactionIdentifier);
        }
    }
}
```

---

## FulfillmentStep Status Lifecycle

```
Pending → Running → Completed
                  → Failed
                  → Skipped
```

- **202 response** from external provider: step stays `Running`
- **200 response** from external provider: step moves to `Completed`
- External service calls back with failure: step moves to `Failed`

---

## Common Issues

### Step remains in `Running` indefinitely
Cause: External service returned 202 (async accepted) but never called back.
Solution: Add a timeout policy or monitor via `FulfillmentSourceChangeEvent`. Implement a retry mechanism or manual step completion.

### Apex Provider not found
Cause: `ApexClassName` is spelled wrong or Apex class is not deployed.
Solution: Verify with `sf data query --query "SELECT Id, Name FROM ApexClass WHERE Name = 'DROSampleOrderAdapter'" --target-org <alias>`

### `ProcessIntegrationProvider` interface not recognized
Cause: The `industriesintegrationfwk` namespace is not available if the Industries Integration Framework package is not installed.
Solution: Verify via `sf data query --query "SELECT Id FROM ApexClass WHERE NamespacePrefix = 'industriesintegrationfwk'" --target-org <alias>`

### Platform events not firing
Cause: Trigger or Flow on the platform event is not activated.
Solution: Ensure the Flow is active or the Apex trigger is deployed. Check that DynamicFulfillmentOrchestratorSettings is enabled.

---

## Deployment Checklist

```
1. Deploy DynamicFulfillmentOrchestratorSettings metadata
2. Deploy Apex callout provider classes (if using Apex Type Provider)
3. Deploy External Service registration (if using External Services provider)
4. Deploy Named Credentials (if using Standard Provider)
5. Deploy FulfillmentStepDefinitionGroup records
6. Deploy FulfillmentStepDefinition records
7. Deploy ProductFulfillmentScenario records
8. Activate all Flows subscribed to platform events
9. Deploy Apex triggers on FulfillmentSourceChangeEvent / SalesTrxnDecompositionEvent
```

---

## See Also

| Skill | Why |
|---|---|
| `rlm-transaction-management` | `SalesTrxnDecompositionEvent` fires when an order is decomposed; DRO fulfillment is triggered on order activation |
| `rlm-deployment` | `DynamicFulfillmentOrchestratorSettings`, Named Credentials, and `FulfillmentStepDefinition` records must be deployed before fulfillment can run |
| `rlm-product-catalog` | `ProductFulfillmentScenario` links a `Product2` to a fulfillment step — product must exist before scenario can be created |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.1.0 | 2026-05-02 | Added See Also table |
| 1.0.0 | 2026-04-29 | Initial skill — three callout provider types, FulfillmentStep lifecycle, platform events |

---

## References
- See `references/dro-objects-reference.md` for full field-level reference
- See `references/dro-callout-patterns.md` for all three callout provider patterns with complete code
- See `references/dro-platform-events.md` for platform event subscription patterns
- RLM Developer Guide v66.0, Chapter 10: Dynamic Revenue Orchestrator (p. 1690)

---
name: rlm-dynamic-revenue-orchestrator
description: Design and implement fulfillment workflows using Salesforce Revenue Cloud's Dynamic Revenue Orchestrator (DRO). Use when creating fulfillment plans, defining fulfillment steps and step definitions, wiring callout providers (Standard HTTP, Apex Type, or External Services), handling async fulfillment callbacks, or subscribing to DRO platform events. Do NOT use for billing or payment processing (use rlm-billing) or product configuration (use rlm-product-configurator). Triggers on: "fulfillment", "fulfillment plan", "fulfillment step", "orchestrator", "DRO", "callout provider", "FulfillmentPlan", "FulfillmentStep", "FulfillmentStepDefinition", "SalesTrxnDecompositionEvent", "FulfillmentSourceChangeEvent", "provisioning", "async fulfillment", "Named Credential fulfillment", "industriesintegrationfwk".
compatibility: Salesforce Revenue Cloud, API v68.0+, Enterprise/Unlimited/Developer Edition
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Dynamic Revenue Orchestrator (DRO)

## Object Hierarchy

**Corrected for v68.0.** `BindingObjectCustomExt` is **not a DRO object** — it does not appear in the RLM Developer Guide's DRO Standard Objects inventory (printed pp. 1830–1831), so it has been removed from the DRO object hierarchy below where the prior version wrongly listed it as "custom metadata for a step." (`BindingObjectCustomExt` *is* a real v68 standard object, but it belongs to **Rate Management** — RLM Developer Guide, Ch.6 Rate Management Standard Objects, printed p.909 — where it is a supported binding target; see `rlm-rate-management`. It has no role in DRO fulfillment steps.) The `ProductFulfillmentScenario` → step-definition relationship also pointed at the wrong granularity (it links to the step-definition *group*, not an individual step definition).

```
FulfillmentStepDefinitionGroup       (groups step definitions — no dependencies)
  └── FulfillmentStepDefinition[]    (defines what a step does; StepDefinitionGroupId → this group)
       └── ProductFulfillmentScenario  (maps a product to a fulfillment step definition GROUP,
                                         via FulfillmentStepDefnGroupId — not to a single definition)

FulfillmentPlan                      (top-level fulfillment plan; State: NotStarted | InProgress | Completed)
  └── FulfillmentStep[]              (individual steps in the plan; State: Pending | Ready | Scheduled |
                                       InProgress | Completed | Failed | FatallyFailed | Skipped)
```

Deployment sequence:
```
1. FulfillmentStepDefinitionGroup
2. FulfillmentStepDefinition      (→ FulfillmentStepDefinitionGroup via StepDefinitionGroupId)
3. ProductFulfillmentScenario     (→ Product2 via ProductId, → FulfillmentStepDefinitionGroup via FulfillmentStepDefnGroupId)
4. FulfillmentPlan                (source-agnostic: linked via SourceIdentifier/SourceType, not a direct Order lookup)
5. FulfillmentStep                (→ FulfillmentPlan, FulfillmentStepDefinition)
```

---

## Instructions

### Step 1: Define Fulfillment Step Groups and Definitions

**Corrected for v68.0**: `FulfillmentStepDefinitionGroup` and `FulfillmentStepDefinition` have no `DeveloperName` field, and the group-lookup field on the definition is `StepDefinitionGroupId` (not `FulfillmentStepDefinitionGroupId`). `CalloutType` isn't a real field — see Step 2 for the corrected callout-wiring mechanism. Source: RLM Developer Guide, Ch.10 DRO Standard Objects.

```apex
// Create step definition group
FulfillmentStepDefinitionGroup group = new FulfillmentStepDefinitionGroup();
group.Name = 'Network Provisioning';
insert group;

// Create step definition
FulfillmentStepDefinition stepDef = new FulfillmentStepDefinition();
stepDef.Name = 'Provision VPN';
stepDef.StepDefinitionGroupId = group.Id;
stepDef.StepType = 'Callout';  // see Step 2 for how the callout itself is configured
insert stepDef;
```

### Step 2: Callout Provider Types

DRO supports three callout provider patterns. **Corrected for v68.0**: callout configuration (Named Credential, HTTP method/path, Apex class, External Service) is not stored on `FulfillmentStepDefinition` fields — it lives on a separate **Integration Definition** record (object `IntegrationProviderDef`), referenced from the step definition via `IntegrationDefinitionNameId`. Full detail and corrected code samples are in `references/dro-callout-patterns.md`; summary below. Source: RLM Developer Guide, Ch.10 DRO › Callouts in Dynamic Revenue Orchestrator, printed pp. 1967–1983.

#### Type 1: Standard Fulfillment Provider (Named Credential + HTTP)

Configure a Named Credential, then create an Integration Definition of Standard Provider type `CalloutIntegrationProvider` with attributes for the Named Credential, path, timeout, and (for async) a callback URI. Point the step definition at it:

```apex
stepDef.StepType = 'Callout';
stepDef.IntegrationDefinitionNameId = integrationDef.Id;  // → IntegrationProviderDef (Standard type)
```

**Async behavior**: If the external service returns HTTP 202, the fulfillment step's `State` moves to `InProgress` until the service calls back (`FulfillmentStep(id=stepId, State='Completed'); upsert;`). If it returns HTTP 200 (also 201/203–206/302/304), the step immediately moves to `Completed`. Any other outcome moves the step to `FatallyFailed`.

#### Type 2: Apex Type Provider

Implements `industriesintegrationfwk.ProcessIntegrationProvider` interface for custom Apex logic. This interface shape is confirmed accurate against the v68.0 guide.

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

Then reference the Apex class from an **Integration Definition** (Apex Defined type) — not from a field on the step definition — and point the step definition at that Integration Definition:
```apex
// stepDef.ApexClassName does not exist; the Apex class is set on the Integration Definition record.
stepDef.StepType = 'Callout';
stepDef.IntegrationDefinitionNameId = integrationDef.Id;  // → IntegrationProviderDef referencing DROSampleOrderAdapter
```

#### Type 3: External Services Defined Provider

Uses a registered External Service (OpenAPI spec imported into Salesforce) to call an external API. No custom Apex required. Create an Integration Definition of type External Services Defined referencing the External Service and operation, then point the step definition at it:

```apex
// stepDef.ExternalServiceName / ExternalServiceOperationName do not exist; both are selected
// when configuring the Integration Definition, not on the step definition record.
stepDef.StepType = 'Callout';
stepDef.IntegrationDefinitionNameId = integrationDef.Id;  // → IntegrationProviderDef (External Services Defined)
```

### Step 3: Map Products to Fulfillment Scenarios

**Corrected for v68.0**: `ProductFulfillmentScenario` links to `Product2` via `ProductId` (not `Product2Id`, renamed v64.0+) and to the fulfillment step definition **group** via `FulfillmentStepDefnGroupId` (not `FulfillmentStepDefinitionId` — the relationship is at the group level, not the individual step). There's no `IsActive` field; applicability is instead driven by the `Action`/`ConditionData` fields. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › ProductFulfillmentScenario, printed pp. 1905–1908.

```apex
ProductFulfillmentScenario scenario = new ProductFulfillmentScenario();
scenario.ProductId = product.Id;
scenario.FulfillmentStepDefnGroupId = group.Id;
scenario.Name = 'VPN Product Provisioning';
insert scenario;
```

### Step 4: Create and Execute Fulfillment Plans

Fulfillment plans are typically created by the platform automatically when an Order is placed. **Corrected for v68.0**: `FulfillmentPlan` has no `OrderId` or `Status` field — DRO plans are source-agnostic and link back via `SourceIdentifier`/`SourceType`, and the status field is `State` with values `NotStarted`|`InProgress`|`Completed` (no `Draft`). `FulfillmentStep` likewise uses `State` (no `Sequence` field). Source: RLM Developer Guide, Ch.10 DRO Standard Objects › FulfillmentPlan / FulfillmentStep.

```apex
FulfillmentPlan plan = new FulfillmentPlan();
plan.Name = 'VPN Provisioning Plan';
plan.SourceIdentifier = order.Id;
plan.SourceType = 'Order';
plan.State = 'NotStarted';
insert plan;

FulfillmentStep step = new FulfillmentStep();
step.Name = 'Provision VPN';
step.FulfillmentPlanId = plan.Id;
step.FulfillmentStepDefinitionId = stepDef.Id;
step.State = 'Pending';
insert step;
```

### Step 5: Subscribe to DRO Platform Events

DRO publishes two platform events for async fulfillment tracking. See `references/dro-platform-events.md` for the full field reference; both events are confirmed accurate under the v68.0 baseline (RLM Developer Guide, Ch.10 › Dynamic Revenue Orchestrator Platform Events, printed pp. 1984–1985).

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
// Corrected: the real field is `State` (not `Status`), and there's no `Running` value —
// use `InProgress`. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › FulfillmentStep.
trigger FulfillmentSourceChangeTrigger on FulfillmentSourceChangeEvent (after insert) {
    for (FulfillmentSourceChangeEvent evt : Trigger.new) {
        String recordId = evt.RecordIdentifier;
        // Handle fulfillment source state change
        FulfillmentStep step = [SELECT Id, State FROM FulfillmentStep WHERE Id = :recordId];
        if (step.State == 'InProgress') {
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

## FulfillmentStep State Lifecycle

**Corrected for v68.0**: the field is `State` (not `Status`); there is no `Running` value (in-progress steps are `InProgress`), no plain `Failed` value (the terminal failure value is `FatallyFailed`), and `Pending`/`Ready`/`Scheduled` are all valid pre-execution states. Source: RLM Developer Guide, Ch.10 DRO › Callouts in Dynamic Revenue Orchestrator, printed pp. 1968–1983.

```
Pending / Ready / Scheduled → InProgress → Completed
                                         → FatallyFailed
             (conditional skip logic) → Skipped
```

- **202 response** from external provider: step's `State` moves to `InProgress`, awaiting an external callback
- **200 response** (also 201/203–206/302/304) from external provider: step moves to `Completed`
- Any other/unrecoverable outcome: step moves to `FatallyFailed`, with detail in `ExecutionMessage`

---

## Common Issues

### Step remains in `InProgress` indefinitely
Cause: External service returned 202 (async accepted) but never called back.
Solution: Add a timeout policy or monitor via `FulfillmentSourceChangeEvent`. Implement a retry mechanism or manual step completion.

### Apex Provider not found
Cause: The Apex class name configured on the Integration Definition (Apex Defined type) is spelled wrong or the class is not deployed.
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
| 2.0.0 | 2026-09-11 | v68.0 re-baseline. Removed `BindingObjectCustomExt` from the DRO object hierarchy (it is not a DRO object — it is a real **Rate Management** standard object, Ch.6 p.909, with no role in DRO steps; the prior version mislabeled it "custom metadata for a step") and all fictional callout-configuration fields on `FulfillmentStepDefinition` (`CalloutType`, `NamedCredentialId`, `HttpMethod`, `Endpoint`, `RequestBodyTemplate`, `ApexClassName`, `ExternalServiceName`, `ExternalServiceOperationName`, `IsActive`, `DeveloperName`); documented the real Integration-Definition-based callout wiring (`IntegrationDefinitionNameId` → `IntegrationProviderDef`). Corrected `FulfillmentStepDefinitionGroupId`→`StepDefinitionGroupId`, `ProductFulfillmentScenario.Product2Id`→`ProductId` and its group-level relationship (`FulfillmentStepDefnGroupId`, not an individual step definition), and `FulfillmentPlan`/`FulfillmentStep` `Status`→`State` with the real value sets (no `Draft`/`Active`/`Cancelled`/`Running`). Renamed "FulfillmentStep Status Lifecycle" to "State Lifecycle" with corrected transitions. Bumped compatibility to API v68.0+. |
| 1.1.0 | 2026-05-02 | Added See Also table |
| 1.0.0 | 2026-04-29 | Initial skill — three callout provider types, FulfillmentStep lifecycle, platform events |

---

## References
- See `references/dro-objects-reference.md` for full field-level reference
- See `references/dro-callout-patterns.md` for all three callout provider patterns with complete code
- See `references/dro-platform-events.md` for platform event subscription patterns
- RLM Developer Guide (v68.0, Winter '27) — Chapter 10: Dynamic Revenue Orchestrator › DRO Standard Objects & Callouts in Dynamic Revenue Orchestrator

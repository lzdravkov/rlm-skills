# DRO — Object Reference

---

## FulfillmentStepDefinitionGroup

Groups related fulfillment step definitions.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `DeveloperName` | String | API name |
| `Description` | String | |
| `IsActive` | Boolean | |

---

## FulfillmentStepDefinition

Defines the execution logic for a fulfillment step.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `DeveloperName` | String | API name |
| `FulfillmentStepDefinitionGroupId` | Reference → FulfillmentStepDefinitionGroup | Required |
| `CalloutType` | Picklist | `StandardFulfillmentProvider` \| `ApexTypeProvider` \| `ExternalServicesDefinedProvider` |
| `NamedCredentialId` | Reference → NamedCredential | For `StandardFulfillmentProvider` |
| `HttpMethod` | String | `GET` \| `POST` \| `PUT` \| `PATCH` \| `DELETE` |
| `Endpoint` | String | Relative path for the HTTP callout |
| `RequestBodyTemplate` | LongTextArea | JSON template with merge fields |
| `ApexClassName` | String | For `ApexTypeProvider` — must implement `industriesintegrationfwk.ProcessIntegrationProvider` |
| `ExternalServiceName` | String | For `ExternalServicesDefinedProvider` |
| `ExternalServiceOperationName` | String | Operation name from the External Service |
| `IsActive` | Boolean | |

---

## ProductFulfillmentScenario

Maps a product to the fulfillment step definition that should execute when it is ordered.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `Product2Id` | Reference → Product2 | Required |
| `FulfillmentStepDefinitionId` | Reference → FulfillmentStepDefinition | Required |
| `IsActive` | Boolean | |
| `Sequence` | Integer | Execution order when multiple scenarios exist for a product |

---

## FulfillmentPlan

Top-level container for fulfillment execution against an order.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `OrderId` | Reference → Order | The order being fulfilled |
| `Status` | Picklist | `Draft` \| `Active` \| `Completed` \| `Failed` \| `Cancelled` |
| `PlannedStartDate` | DateTime | |
| `PlannedEndDate` | DateTime | |
| `ActualStartDate` | DateTime | Set when first step executes |
| `ActualEndDate` | DateTime | Set when plan completes |

---

## FulfillmentStep

Individual step within a FulfillmentPlan.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `FulfillmentPlanId` | Reference → FulfillmentPlan | Required |
| `FulfillmentStepDefinitionId` | Reference → FulfillmentStepDefinition | Required |
| `Status` | Picklist | `Pending` \| `Running` \| `Completed` \| `Failed` \| `Skipped` |
| `Sequence` | Integer | Order of execution within the plan |
| `InputPayload` | LongTextArea | JSON input sent to the callout provider |
| `OutputPayload` | LongTextArea | JSON response from the callout provider |
| `ErrorMessage` | LongTextArea | Set if Status = `Failed` |
| `StartTime` | DateTime | When this step started executing |
| `EndTime` | DateTime | When this step completed |

**Status transitions:**
- `Pending` → `Running` (when the step begins execution)
- `Running` → `Completed` (200 response or successful callback)
- `Running` → `Failed` (non-200/non-202 response or failed callback)
- `Pending` → `Skipped` (conditional skip logic)

---

## DynamicFulfillmentOrchestratorSettings

Settings metadata to enable DRO features.

File: `force-app/main/default/settings/DynamicFulfillmentOrchestrator.settings-meta.xml`

```xml
<DynamicFulfillmentOrchestratorSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableDynamicFulfillmentOrchestrator>true</enableDynamicFulfillmentOrchestrator>
</DynamicFulfillmentOrchestratorSettings>
```

Deploy: `sf project deploy start --metadata "Settings:DynamicFulfillmentOrchestrator" --target-org <alias>`

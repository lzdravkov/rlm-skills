# DRO — Object Reference

---

## FulfillmentStepDefinitionGroup

Groups related fulfillment step definitions. Available in API version 61.0 and later.

*(Corrected — the real object has no `DeveloperName`, `Description`, or `IsActive` field. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › FulfillmentStepDefinitionGroup, printed p. 1879.)*

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required. The name of the fulfillment step definition group. |
| `OwnerId` | Reference → Group, User | Polymorphic. The ID of the user who created the record. |
| `UsageType` | Picklist | The business vertical that uses fulfillment orchestration. Valid values: `IntegrationOrchestrator` \| `OrderFulfillment` |
| `LastReferencedDate` / `LastViewedDate` | DateTime | Standard tracking fields |

---

## FulfillmentStepDefinition

Defines the execution logic for a fulfillment step. Available in API version 61.0 and later.

**Corrected — important divergence from prior skill content.** `FulfillmentStepDefinition` has **no** `DeveloperName`, `CalloutType`, `NamedCredentialId`, `HttpMethod`, `Endpoint`, `RequestBodyTemplate`, `ApexClassName`, `ExternalServiceName`, `ExternalServiceOperationName`, or `IsActive` field. Callout configuration (Named Credential, HTTP method/path, Apex class, External Service) is **not** stored inline on this object — it lives on a separate **Integration Definition** record (object `IntegrationProviderDef`), which this object references via `IntegrationDefinitionNameId`. See `references/dro-callout-patterns.md` for the corrected callout-configuration pattern. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › FulfillmentStepDefinition, printed pp. 1871–1879; and Ch.10 › Callouts in Dynamic Revenue Orchestrator, printed pp. 1967–1983.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required. The name of the fulfillment step definition. |
| `StepDefinitionGroupId` | Reference → FulfillmentStepDefinitionGroup (master-detail) | Required. **Renamed** from the previously-documented `FulfillmentStepDefinitionGroupId` — the real relationship field is `StepDefinitionGroupId`. |
| `StepType` | Picklist | The kind of step this definition executes. Valid values: `AutoTask` \| `Callout` \| `ManualTask` \| `Milestone` \| `Pause` \| `StagedAssetize` |
| `IntegrationDefinitionNameId` | Reference → IntegrationProviderDef | Used when `StepType = Callout`. Points to the Integration Definition that holds the actual Named Credential / Apex class / External Service configuration. |
| `FlowDefinitionName` | String | The name of the associated Flow, used when `StepType = AutoTask`. |
| `TaskAllocationType` | Picklist | The method of assigning a `ManualTask` step. Valid values: `ContextBased` \| `LeastLoaded` \| `RoundRobin` (available API v62.0/63.0+; the guide shows both version numbers for this field — annotated as a minor doc inconsistency) |
| `Scope` | Picklist | The scope of the step definition, e.g. `Bundle`, `CrossPlan`, `LineItem`, `Plan`. Default `Plan`. |
| `ExecuteOn` | Picklist | When to execute the step. Valid values include `PreviousStepsStartDate` \| `SourceLineStartDate`. |
| `ExecuteOnConditionData` / `ExecuteOnRuleId` | Textarea / Reference → ExpressionSet | JSON rule condition / expression set that gates execution (v66.0+ for `ExecuteOnConditionData`). |
| `ResumeOnConditionData` / `ResumeOnRuleId` | Textarea / Reference → ExpressionSet | JSON rule condition / expression set that resumes a paused step (v66.0+ for `ResumeOnConditionData`). |
| `PointOfNoReturn` | Multipicklist | Valid value: `Changes Denied` (v62.0+) |
| `ForcePlanFreezeDuringExecution` | Picklist | Whether to freeze the plan while the step runs. Valid values: `Never` \| `YesButForcefullyCompleteStep`. Default `Never`. (v63.0+) |
| `DelayOf` / `DelayUnit` | Int / Picklist | Delay value and unit (`Days` \| `Hours` \| `Minutes`) for `Pause` steps. (v63.0+) |
| `IsSkipBranch` | Boolean | Skips remaining steps in the group when the Execute On Rule condition is set. Default `false`. (v62.0+) |
| `AssignedToId` | Reference → Queue, User (polymorphic) | The user or queue associated with the step definition. |
| `AmendGroupId` / `CancelledGroupId` | Reference → FulfillmentStepDefinitionGroup | The step group added to the plan when the step is amended / canceled. (v62.0+) |
| `CustomConfigParameter` / `CustomBaseExecutionDate` / `CustomFulfillmentScope` | String / String / String | Designer-supplied custom context passed to steps for flow reusability. (`CustomBaseExecutionDate` and `CustomFulfillmentScope` are v65.0+) |
| `Description` | Textarea | Shown to admins in the orchestration plan. (v68.0+) |
| `RunAsUserId` | Reference → User | Overrides the default autoproc user context for step execution. |
| `UsageType` | Picklist | `IntegrationOrchestrator` \| `OrderFulfillment` |
| `OmniscriptName` | String | For internal use only. |

---

## ProductFulfillmentScenario

Maps a product to the corresponding **group** of fulfillment steps necessary to fulfill it. Available in API version 61.0 and later.

*(Corrected — the real relationship is to `FulfillmentStepDefinitionGroup`, not an individual `FulfillmentStepDefinition`; there's no `IsActive` or `Sequence` field. Instead, an `Action` + `ConditionData` pair drives which scenario applies. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › ProductFulfillmentScenario, printed pp. 1905–1908.)*

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `ProductId` | Reference → Product2 | The product associated with the scenario. (v64.0+; renamed from the previously-documented `Product2Id` — the real field is `ProductId`) |
| `FulfillmentStepDefnGroupId` | Reference → FulfillmentStepDefinitionGroup | The fulfillment step definition **group** associated with the scenario. (renamed from the previously-documented `FulfillmentStepDefinitionId`) |
| `Action` | Multipicklist | For internal use only. Valid values: `Add` \| `Amend` \| `Cancel` \| `NoChange` \| `Renew` |
| `ConditionData` | Textarea | JSON rule/condition that determines when the scenario executes. (v66.0+) |
| `ProductClassificationId` | Reference → ProductClassification | The product classification associated with the scenario. |
| `UsageType` | Picklist | `Fulfillment` \| `Generic` \| `InsuranceRuleAction` \| `IntegrationOrchestrator` \| `StageManagement` |

---

## FulfillmentPlan

Top-level container for fulfillment execution. Available in API version 61.0 and later.

*(Corrected — the real field for plan status is `State`, not `Status`, and it has none of `Draft`/`Active`/`Cancelled` as values. There's also no `OrderId`, `PlannedStartDate`, `PlannedEndDate`, `ActualStartDate`, or `ActualEndDate` field on this object — DRO plans aren't order-specific; the generic linkage is via `SourceIdentifier`/`SourceType`. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › FulfillmentPlan.)*

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `State` | Picklist | Valid values: `Completed` \| `InProgress` \| `NotStarted` |
| `SourceIdentifier` | String | The identifier of the source record (e.g., an order or fulfillment order) driving this plan. |
| `SourceType` | Picklist | The type of the source record. (v62.0+) |
| `Priority` | Picklist | `Default` \| `High` \| `Bulk` (v63.0+) |
| `UsageType` | Picklist | `IntegrationOrchestrator` \| `Generic` \| `StageManagement` |
| `ExecutionUserId` | Reference → User | The user context the plan executes as. |

---

## FulfillmentStep

Individual step within a FulfillmentPlan. Available in API version 61.0 and later.

*(Corrected — the real status field is `State`, not `Status`, and there's no `Running` value (in-progress steps are `InProgress`), no `Sequence`, and no `InputPayload`/`OutputPayload`/`ErrorMessage`/`StartTime`/`EndTime` field. The execution message for a failed callout is stored in `ExecutionMessage`. Source: RLM Developer Guide, Ch.10 DRO Standard Objects › FulfillmentStep.)*

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `FulfillmentPlanId` | Reference → FulfillmentPlan | Required |
| `FulfillmentStepDefinitionId` | Reference → FulfillmentStepDefinition | Required |
| `State` | Picklist | Valid values: `Completed` \| `Failed` \| `FatallyFailed` \| `InProgress` \| `Pending` \| `Ready` \| `Scheduled` \| `Skipped` |
| `StepType` | Picklist | `AutoTask` \| `Callout` \| `ManualTask` \| `Milestone` \| `Pause` \| `StagedAssetize` |
| `AssignedToId` | Reference → Queue, User (polymorphic) | Assignee for `ManualTask` steps. |
| `RetryAttempts` | Integer | Number of retry attempts for a callout step. |
| `ExecutionMessage` | Textarea | Error/status detail — the field surfaced in the UI when a step is `FatallyFailed` (e.g., "Retry attempts limit exceeded"). |
| `FalloutQueueId` | Reference → Queue | Queue a step routes to on fallout. |
| `FlowDefinitionName` / `FlowInterviewId` | String / Reference | Used for `AutoTask` steps. |
| `JeopardyStatus` / `JeopardyThreshold` / `JeopardyThresholdUnit` | — | Tracking for at-risk steps per the associated `FulfillmentStepJeopardyRule`. |
| `ActualStartDate` / `ActualCompletionDate` | DateTime | When the step actually started/completed. |
| `PlannedStartDate` / `PlannedCompletionDate` | DateTime | Planned execution window. |
| `RequestedStartDate` / `RequestedCompletionDate` | DateTime | Requested execution window. |
| `NextEarliestRunTime` | DateTime | Earliest time this step is eligible to run next. |
| `PointOfNoReturn` | — | Inherited/derived from the step definition. |
| `CompensatedStepId` | Reference | The step this step compensates, if applicable. |
| `DelayOf` / `DelayUnit` | Int / Picklist | For `Pause` steps. |
| `ExecuteOn` / `ExecuteOnRuleId` | Picklist / Reference | Conditional-execution configuration. |
| `IsSkipBranch` | Boolean | |
| `ForcePlanFreezeDuringExecution` | Picklist | |
| `ResumeOnRuleId` | Reference | |
| `RunAsUserId` | Reference → User | |
| `ScopeIdentifierText` | String | |
| `TaskAllocationType` | Picklist | `ContextBased` \| `LeastLoaded` \| `RoundRobin` (v63.0+) |
| `TaskId` | Reference → Task | The task assigned for a manual step. (v63.0+) |
| `UsageType` | Picklist | `Fulfillment` \| `InsuranceRuleAction` \| `IntegrationOrchestrator` \| `OrderFulfillment` |

**`State` transitions (per the Callouts documentation, printed pp. 1968–1983):**
- `Pending`/`Ready`/`Scheduled` → `InProgress` (informally described in some provider-callback docs as the step "running")
- `InProgress` → `Completed` (HTTP 200 response, or a successful async callback)
- `InProgress` → `FatallyFailed` (non-successful response the platform can't recover from, e.g., a retry-limit breach)
- Conditional skip logic → `Skipped`

---

## DynamicFulfillmentOrchestratorSettings

Settings metadata to enable DRO features.

*(Annotated — this metadata type name, its file suffix, and the `enableDynamicFulfillmentOrchestrator` field were not independently re-confirmed against the Ch.10 Metadata API section (printed pp. 1955–1960) during this v68 pass; the section wasn't in scope for this update's page budget. Verify the exact metadata type/field name against that section before relying on this snippet.)*

File: `force-app/main/default/settings/DynamicFulfillmentOrchestrator.settings-meta.xml`

```xml
<DynamicFulfillmentOrchestratorSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableDynamicFulfillmentOrchestrator>true</enableDynamicFulfillmentOrchestrator>
</DynamicFulfillmentOrchestratorSettings>
```

Deploy: `sf project deploy start --metadata "Settings:DynamicFulfillmentOrchestrator" --target-org <alias>`

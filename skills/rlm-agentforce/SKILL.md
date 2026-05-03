---
name: rlm-agentforce
description: Build and configure Salesforce Agentforce agents integrated with Revenue Cloud (RLM). Use when creating GenAiFunctions, GenAiPlugins (topics), BotVersion planner bundles, wiring invocable actions to agent topics, handling multi-turn email agent sessions, or debugging agent execution failures. Do NOT use for standard Flow authoring (use rlm-transaction-management) or product catalog setup (use rlm-product-catalog). Triggers on: "Agentforce", "GenAiFunction", "GenAiPlugin", "BotVersion", "planner bundle", "agent topic", "agent action", "generateAiAgentResponse", "sessionId", "lightning:type", "InvocableMethod", "agent context", "email agent", "guided selling agent", "NGA", "legacy bot".
compatibility: Salesforce Revenue Cloud, API v66.0+, Agentforce (Einstein Platform), Enterprise/Unlimited/Developer Edition
metadata:
  version: 1.0.0
  author: skunkworks-rca
---

# RLM Agentforce Integration

## Agent Types

| Type | Format | Invocable via `generateAiAgentResponse` |
|---|---|---|
| **Legacy Bot** (BotVersion) | `.bot` metadata | ✓ Yes |
| **NGA Agent** | `.agent` metadata | ✗ No — not supported |

**Critical**: `generateAiAgentResponse` invocable action only supports Legacy Bot/BotVersion agents. If you need to invoke an agent from a Flow or Apex, use a Legacy Bot.

---

## GenAiPlugin (Topic) — Authoring Rules

A `GenAiPlugin` defines a topic: the agent's instructions, scope, and which functions it can call.

```xml
<!-- force-app/main/default/genAiPlugins/MyPlugin.genAiPlugin-meta.xml -->
<GenAiPlugin xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>My Plugin</masterLabel>
    <pluginType>Topic</pluginType>
    <description>What this topic does and when to use it</description>
    <instructions>
        <!-- Step-by-step behavioral instructions for the agent -->
        1. When the user asks about X, call Get_X_Function.
        2. Always confirm before creating records.
        ...
    </instructions>
    <genAiFunctions>
        <genAiFunction>Get_X_Function</genAiFunction>
    </genAiFunctions>
</GenAiPlugin>
```

**Developer name uniqueness**: Inline topic and action developer names must be **globally unique** across the entire org. If deploying multiple agent versions, prefix names with a version suffix (e.g., `Configure_Product_v4`).

**Deploy GenAiPlugin before GenAiFunction**: The plugin references functions by developer name; if the function doesn't exist at deploy time, the plugin deploy fails.

---

## GenAiFunction — Schema Format

GenAiFunction input/output parameters **must** use `lightning:type` format, not JSON Schema draft-07.

**Correct** (`lightning:type`):
```xml
<parameters>
    <parameter>
        <masterLabel>Quote ID</masterLabel>
        <developerName>quoteId</developerName>
        <parameterType>lightning__textType</parameterType>
        <isRequired>true</isRequired>
    </parameter>
    <parameter>
        <masterLabel>Attribute Inputs</masterLabel>
        <developerName>attributeInputsJson</developerName>
        <parameterType>lightning__textType</parameterType>
        <isRequired>true</isRequired>
    </parameter>
</parameters>
```

**Wrong** (JSON Schema — will fail at runtime):
```json
{ "type": "object", "properties": { "quoteId": { "type": "string" } } }
```

### `lightning:type` values

| lightning:type | Equivalent |
|---|---|
| `lightning__textType` | String / Text |
| `lightning__numberType` | Number / Decimal |
| `lightning__booleanType` | Boolean |
| `lightning__objectType` | Structured JSON object |
| `lightning__listType` | List / Array |
| `lightning__dateType` | Date |
| `lightning__dateTimeType` | DateTime |

---

## GenAiFunction → Flow → Apex wiring

The standard pattern for an agent action that accesses Salesforce data:

```
GenAiFunction (defines schema, invocable name)
  └── Flow (Auto-launched, no trigger)
        └── Apex @InvocableMethod (actual data access / DML / callout)
```

**Why Flow as the intermediary**: GenAiFunctions call invocable actions, not Apex directly. The Flow receives the GenAiFunction inputs, calls the `@InvocableMethod`, and returns outputs back to the agent.

```apex
// Apex @InvocableMethod pattern
public class MyService {
    public class Request {
        @InvocableVariable(required=true) public String quoteId;
    }
    public class Result {
        @InvocableVariable public String resultJson;
        @InvocableVariable public String errorMessage;
    }

    @InvocableMethod(label='My Service Action' category='Revenue Cloud')
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            Result r = new Result();
            try {
                // Do work
                r.resultJson = JSON.serialize(doWork(req.quoteId));
            } catch (Exception e) {
                r.errorMessage = e.getMessage();
            }
            results.add(r);
        }
        return results;
    }
}
```

---

## Critical: `getSessionId()` Returns Null in Agent Context

`UserInfo.getSessionId()` returns `null` when Apex runs inside a GenAiFunction execution context. This means you **cannot** make HTTP callouts to Salesforce REST APIs (including `/connect/cpq/` Product Discovery endpoints) from Apex invoked by an agent.

**Workarounds** (in order of preference):
1. **Use SOQL directly** — query `Product2`, `ProductClassificationAttr`, `AttributePicklistValue` etc. This is proven and works in all agent contexts.
2. **Use Standard Invocable Actions via Flow** — Product Discovery, Usage Management, and other standard invocable actions do not require a session ID.
3. **Named Credentials** — if you must make an HTTP callout, use a Named Credential with `Merge Fields in HTTP Body = Enabled`. Named Credentials bypass the session ID requirement.

```apex
// WRONG — returns null in agent context
String sessionId = UserInfo.getSessionId();
Http http = new Http();
HttpRequest req = new HttpRequest();
req.setHeader('Authorization', 'Bearer ' + sessionId); // null!

// CORRECT — use SOQL instead
List<Product2> products = [
    SELECT Id, Name, ProductCode
    FROM Product2
    WHERE Name LIKE :searchTerm
    AND IsActive = true
    LIMIT 20
];
```

---

## BotVersion Planner Bundle — Locking Behavior

The active `BotVersion`'s planner bundle is **locked** after activation. You cannot modify topics or instructions in-place on an active version.

**To update agent topics or instructions**:
1. In Setup → Agents, open the agent
2. Create a new BotVersion (this generates a new planner bundle name, e.g., `MyAgent_v2_v3_v4`)
3. Add/update `GenAiPlugin` topics and `GenAiFunction` actions in the new version
4. Test and activate the new version

**Note**: The new planner bundle name is auto-generated and must be updated in any deployment references.

---

## `generateAiAgentResponse` — Invocable Action

Used to invoke a Legacy Bot agent from a Flow. Key parameters:

| Parameter | Type | Notes |
|---|---|---|
| `botId` | String | The Bot record ID |
| `versionString` | String | **Must be `"1.0.0"`** — `"2.0.0"` requires `dataTypeMappings` and is not supported by Legacy Bots |
| `sessionId` | String | Pass the stored session ID for multi-turn conversations; omit for Turn 1 |
| `inputText` | String | The user message or structured context block |
| `language` | String | e.g., `"en_US"` |

**Outputs**:
| Parameter | Type | Notes |
|---|---|---|
| `sessionId` | String | Store on Case or related record for multi-turn continuity |
| `outputText` | String | The agent's response |
| `status` | String | `Success` \| `Error` |

**Multi-turn session management**:
```apex
// Turn 1: no sessionId, build CONTEXT block
String contextBlock = 'CONTEXT: AccountId=' + accountId
    + ', ContactId=' + contactId + ', CaseId=' + caseId;

// After Turn 1: store returned sessionId on Case
caseRecord.AgentSessionId__c = returnedSessionId;
update caseRecord;

// Turn 2+: pass stored sessionId + customer message
String message = 'CUSTOMER REPLY: ' + customerEmailBody;
// Call generateAiAgentResponse with sessionId = caseRecord.AgentSessionId__c
```

**Session TTL**: Platform sessions expire after ~24 hours. If a customer replies after expiry, clear `AgentSessionId__c` to force a fresh Turn 1.

---

## DML / Callout Boundary in Agent-Triggered Flows

When a Flow is triggered by an agent action that also performs DML, and that Flow later needs to make an HTTP callout (e.g., `generateAiAgentResponse`), a transaction boundary is required.

**Problem**: Salesforce blocks HTTP callouts after uncommitted DML in the same transaction.

**Solution**: Split into sync and async paths using `AsyncAfterCommit`:
1. **Sync path** (same transaction): perform all DML operations and commit
2. **Async path** (new transaction, `AsyncAfterCommit`): perform callouts

```
RecordAfterSave Flow
  ├── [Sync] DML operations (e.g., EnsureOpportunityService → insert Opportunity)
  │    ← DML commits here →
  └── [Async, AsyncAfterCommit] Callout path
        └── generateAiAgentResponse → EmailQuoteInquiry agent
```

This pattern is implemented in `RC_Email_Config_Quote` flow (see `email_config_agent.md`).

---

## Deployment Order for Agent Metadata

Deploy in this sequence to avoid reference errors:

```
1. Apex classes (@InvocableMethod services)
2. Flows (Auto-launched, referencing Apex invocable actions)
3. GenAiFunction metadata (references Flows by API name)
4. GenAiPlugin metadata (references GenAiFunctions by developer name)
5. BotVersion / planner bundle (references GenAiPlugins)
6. Activate the new BotVersion
```

---

## Common Issues

### Agent returns "I can't help with that" unexpectedly
Cause: The GenAiPlugin topic instructions don't cover the user's phrasing, or the function's output schema doesn't match what the agent expects.
Solution: Review topic instructions — ensure they explicitly describe when to call each function. Check output `lightning:type` fields match the data the Apex returns.

### `getSessionId()` returns null — callout fails silently
Cause: Running in Agentforce execution context. See [Critical section above](#critical-getsessionid-returns-null-in-agent-context).
Solution: Replace HTTP callout with SOQL or Standard Invocable Action.

### GenAiFunction deploy fails: "Action not found"
Cause: The Flow referenced by the GenAiFunction is not yet deployed or has a different API name.
Solution: Deploy Flows before GenAiFunctions. Confirm the Flow API name exactly matches the `actionName` in the GenAiFunction metadata.

### GenAiPlugin deploy fails: "Developer name already exists"
Cause: Inline topic/function developer names must be globally unique — a prior version used the same name.
Solution: Suffix new names with the version number (e.g., `Get_Product_Attributes_v4`). Never reuse a developer name across BotVersions.

### `versionString: 2.0.0` causes error in `generateAiAgentResponse`
Cause: The `2.0.0` path requires `dataTypeMappings` which Legacy Bot agents don't support.
Solution: Always pass `versionString: "1.0.0"` for Legacy Bot agents.

### Session context lost between email turns
Cause: `AgentSessionId__c` field is empty or the session expired (~24h TTL).
Solution: Store the `sessionId` output from `generateAiAgentResponse` on the Case record after Turn 1. Check `Case.AgentSessionId__c` before each turn. If null, start a fresh Turn 1 with the full CONTEXT block.

### Attribute value not saved after PST called from agent
Cause: The PST two-step sequencing issue — Number and Picklist attributes submitted in a single call.
Solution: Use two-step PST sequencing (Number first, then Picklist). See `rlm-product-configurator` skill and `ProductAttributeSaveService` implementation in `email_config_agent.md`.

---

## See Also

| Skill | Why |
|---|---|
| `rlm-product-configurator` | PST API is the critical path for agent-driven attribute configuration; two-step sequencing is required |
| `rlm-product-discovery` | Product Discovery Standard Invocable Actions are the correct callout-free path for finding products in agent context |
| `rlm-transaction-management` | Quote and order creation Flows are wired as GenAiFunctions; `generateAiAgentResponse` session pattern lives here |
| `rlm-pricing` | Headless pricing invocable actions work from agent context without session ID |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-05-02 | Initial skill — GenAiPlugin/Function authoring, lightning:type schema, getSessionId null fix, BotVersion locking, generateAiAgentResponse, DML/callout boundary, deployment order |

---

## References
- See `references/agentforce-metadata-reference.md` for GenAiPlugin, GenAiFunction, and BotVersion metadata field reference
- Project documentation: `CLAUDE.md` — Phase 3 components and critical technical findings
- Project documentation: `email_config_agent.md` — full email agent architecture, multi-turn session pattern, DML/callout boundary solution
- RLM Developer Guide v66.0: Agentforce for Revenue Cloud (p. 1841)

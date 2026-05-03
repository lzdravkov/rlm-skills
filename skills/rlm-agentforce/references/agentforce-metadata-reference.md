# Agentforce — Metadata Reference

---

## GenAiPlugin (Topic)

**Metadata type**: `GenAiPlugin`
**File suffix**: `.genAiPlugin-meta.xml`
**Folder**: `force-app/main/default/genAiPlugins/`

| Field | Type | Description |
|---|---|---|
| `masterLabel` | String | Display name in Setup UI |
| `pluginType` | Picklist | `Topic` — the only value for agent topics |
| `description` | String | When the agent should invoke this topic (used by planner) |
| `instructions` | LongTextArea | Numbered behavioral instructions; guides the agent's reasoning within this topic |
| `genAiFunctions` | List | Developer names of `GenAiFunction` records this topic can call |
| `scope` | LongTextArea | Optional — further narrows when the topic applies |

**Deploy order**: GenAiPlugin must be deployed **after** all referenced GenAiFunctions exist.

**Example**:
```xml
<GenAiPlugin xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>Product Configuration</masterLabel>
    <pluginType>Topic</pluginType>
    <description>Configure product attributes on a quote line item and report the updated price.</description>
    <instructions>
        1. When the user asks to configure or set attributes, call Get_Product_Attribute_Options to retrieve available options.
        2. Present each attribute with its valid values to the user.
        3. When the user provides selections, call Configure_Product_Attributes with the quoteLineItemId and all selected values.
        4. After saving, call Save_Product_Configuration and report the Grand Total to the user.
        5. Never invent attribute values — only use values returned by Get_Product_Attribute_Options.
    </instructions>
    <genAiFunctions>
        <genAiFunction>Get_Product_Attribute_Options</genAiFunction>
        <genAiFunction>Configure_Product_Attributes</genAiFunction>
        <genAiFunction>Save_Product_Configuration</genAiFunction>
    </genAiFunctions>
</GenAiPlugin>
```

---

## GenAiFunction (Agent Action)

**Metadata type**: `GenAiFunction`
**File suffix**: `.genAiFunction-meta.xml`
**Folder**: `force-app/main/default/genAiFunctions/`

| Field | Type | Description |
|---|---|---|
| `masterLabel` | String | Display name |
| `description` | String | What this function does — used by the agent to decide when to call it |
| `functionType` | Picklist | `FlowAction` (calls a Flow), `DataCloudQuery`, `Prompt` |
| `actionName` | String | API name of the Flow (for `FlowAction` type) |
| `parameters` | List | Input parameters — use `lightning:type` format (see below) |
| `outputSchema` | LongTextArea | JSON describing the output structure; can include instructions for the agent |

### Parameter fields

| Field | Type | Description |
|---|---|---|
| `masterLabel` | String | Human-readable parameter label |
| `developerName` | String | API name used in Flow input variables |
| `parameterType` | String | `lightning__textType` \| `lightning__numberType` \| etc. |
| `isRequired` | Boolean | Whether the parameter is required |
| `description` | String | Guidance for the agent on what value to pass |

**Full `lightning:type` reference**:

| parameterType | Salesforce equivalent |
|---|---|
| `lightning__textType` | Text / String |
| `lightning__numberType` | Number / Decimal |
| `lightning__booleanType` | Boolean (Checkbox) |
| `lightning__objectType` | Structured JSON object (passed as Text and parsed in Apex) |
| `lightning__listType` | List / Collection |
| `lightning__dateType` | Date |
| `lightning__dateTimeType` | Date/Time |
| `lightning__currencyType` | Currency |
| `lightning__percentType` | Percent |
| `lightning__phoneType` | Phone |
| `lightning__emailType` | Email |
| `lightning__urlType` | URL |

**Example**:
```xml
<GenAiFunction xmlns="http://soap.sforce.com/2006/04/metadata">
    <masterLabel>Configure Product Attributes</masterLabel>
    <description>Saves attribute selections on a QuoteLineItem and returns the updated Grand Total.</description>
    <functionType>FlowAction</functionType>
    <actionName>Configure_Product_Attributes_Flow</actionName>
    <parameters>
        <parameter>
            <masterLabel>Quote Line Item ID</masterLabel>
            <developerName>quoteLineItemId</developerName>
            <parameterType>lightning__textType</parameterType>
            <isRequired>true</isRequired>
            <description>The 0QL... ID of the QuoteLineItem to configure</description>
        </parameter>
        <parameter>
            <masterLabel>Attribute Inputs JSON</masterLabel>
            <developerName>attributeInputsJson</developerName>
            <parameterType>lightning__textType</parameterType>
            <isRequired>true</isRequired>
            <description>JSON array of {developerName, dataType, value, picklistValueId} objects</description>
        </parameter>
    </parameters>
    <outputSchema>{
  "grandTotal": "Decimal — the Quote Grand Total after configuration. Always report this to the user.",
  "savedAttributesJson": "String — JSON array of saved QuoteLineItemAttribute records.",
  "errorMessage": "String — present if configuration failed."
}</outputSchema>
</GenAiFunction>
```

---

## BotVersion (Planner Bundle)

The active `BotVersion` is the container for all agent topics, actions, and instructions. Each version has an auto-generated planner bundle name.

| Field | Type | Description |
|---|---|---|
| `BotId` | Reference → Bot | The parent agent |
| `VersionNumber` | Integer | Auto-incremented version |
| `Status` | Picklist | `Draft` \| `Active` \| `Inactive` |
| `ReasonForChange` | String | Reason for creating this version |

**Key rule**: Active BotVersion planner bundle is locked. To update topics or instructions, create a new BotVersion in Setup UI. The new version generates a new planner bundle name (e.g., `AgentName_v2_v3_v4`).

**Query active version**:
```soql
SELECT Id, VersionNumber, Status, BotId
FROM BotVersion
WHERE Status = 'Active'
  AND Bot.DeveloperName = 'MyAgent'
LIMIT 1
```

---

## generateAiAgentResponse — Full Input/Output Reference

**Invocable Action API name**: `generateAiAgentResponse`

### Inputs

| Field | Type | Required | Notes |
|---|---|---|---|
| `botId` | String | Required | Bot record ID (starts with `0Xx...`) |
| `botVersionId` | String | Optional | Specific BotVersion ID; omit to use active version |
| `versionString` | String | Required | **Must be `"1.0.0"`** |
| `sessionId` | String | Optional | Existing session ID for Turn 2+; omit for Turn 1 |
| `inputText` | String | Required | User message or CONTEXT block |
| `language` | String | Optional | Default `en_US` |
| `sObjectType` | String | Optional | Object type context (e.g., `Case`) |
| `sObjectId` | String | Optional | Record ID context |

### Outputs

| Field | Type | Notes |
|---|---|---|
| `sessionId` | String | Store for multi-turn continuity; expires ~24h |
| `outputText` | String | Agent's text response (may be wrapped in JSON by bot runtime — see below) |
| `status` | String | `Success` \| `Error` |
| `errorMessage` | String | Present if status = `Error` |

**OutputText JSON wrapping**: The bot runtime may wrap the agent's response in a JSON envelope: `{"type":"Text","value":"actual message here"}`. Unwrap before sending to the end user:

```apex
public static String unwrapBotOutput(String raw) {
    if (raw == null) return '';
    try {
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(raw);
        if (parsed.containsKey('value')) {
            return (String) parsed.get('value');
        }
    } catch (Exception e) { /* not JSON — return raw */ }
    return raw;
}
```

---

## Agentforce Execution Context Summary

| Behavior | In Agent Context | Outside Agent Context |
|---|---|---|
| `UserInfo.getSessionId()` | Returns `null` | Returns valid session ID |
| Standard SOQL | ✓ Works | ✓ Works |
| HTTP callout via Named Credential | ✓ Works | ✓ Works |
| HTTP callout using `getSessionId()` | ✗ Fails (null) | ✓ Works |
| `Database.insertImmediate()` | ✓ Required for `QuoteLineItemAttribute` | ✓ Also required |
| Standard `insert` on `QuoteLineItemAttribute` | ✗ Fails | ✗ Also fails |
| Standard Invocable Actions | ✓ Works (no session needed) | ✓ Works |
| `RevSalesTrxn.PlaceSalesTransactionExecutor` | ✓ Works | ✓ Works |

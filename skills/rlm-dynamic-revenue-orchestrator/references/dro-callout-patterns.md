# DRO — Callout Provider Patterns

Three callout provider types are available. Choose based on complexity and external system requirements.

**Corrected for v68.0 — read before using.** None of `CalloutType`, `NamedCredentialId`, `HttpMethod`, `Endpoint`, `RequestBodyTemplate`, `ApexClassName`, `ExternalServiceName`, or `ExternalServiceOperationName` are real fields on `FulfillmentStepDefinition`. Callout configuration is **not** set inline on the step definition — it's configured as a separate **Integration Definition** record (object `IntegrationProviderDef`, of sub-type Standard / Apex Defined / External Services Defined), which the step definition references via its `IntegrationDefinitionNameId` field, with `StepType = 'Callout'`. Source: RLM Developer Guide, Ch.10 Dynamic Revenue Orchestrator › Callouts in Dynamic Revenue Orchestrator, printed pp. 1967–1983.

---

## Type 1: Standard Fulfillment Provider

**Use when:** External system has a REST API and you want zero-code callout configuration via Named Credentials.

The Standard Fulfillment Provider (internally `CalloutIntegrationProvider`) sends a **predefined payload** built from sales-transaction/fulfillment-transaction context — you configure endpoint/auth/encoding behavior, you don't write a request body template.

**Async contract:**
- HTTP 202 → the fulfillment step's `State` moves to `InProgress` (informally described as the step "running" in some provider-callback docs); the external system must call back to complete it
- HTTP 200 (also 201/203/204/205/206/302/304) → the step immediately moves to `Completed`
- Any other/undefined status in the response → the step moves to `FatallyFailed`

**Step 1 — Configure prerequisites (Setup, not Apex):**
1. Create a Named Credential (and, if using the newer auth model, an External Credential) pointing at the external system's endpoint.
2. Create an **Integration Definition** with **Standard Provider** type `CalloutIntegrationProvider`, and set its attributes:

| Attribute | Purpose |
|---|---|
| Named Credentials | API name of the Named Credential to call |
| Path | String appended to the Named Credential's endpoint URL |
| Timeout (ms) | HTTP timeout (default 5s, max 120s) |
| Callback URI | Required for async callouts — the URI the external system calls back to complete the step |
| Input Processor / Output Processor | Optional OmniStudio Integration Procedures (`Type_Subtype` or `Id`) to pre/post-process the payload |
| Item Encoding Style | `Flat` (default) or `Structure` — whether nested line-item hierarchy is included |
| Attribute Encoding Style | `Flat` or `Structure` (default) — key-value vs. granular attribute detail |
| Send Empty Attributes / Send Payload | Payload-shaping toggles |

3. On the `FulfillmentStepDefinition` record, set `StepType = 'Callout'` and `IntegrationDefinitionNameId` to the Integration Definition you just created:

```apex
FulfillmentStepDefinition stepDef = new FulfillmentStepDefinition();
stepDef.Name = 'Provision Fiber Service';
stepDef.StepDefinitionGroupId = group.Id;   // real field name (not FulfillmentStepDefinitionGroupId)
stepDef.StepType = 'Callout';
stepDef.IntegrationDefinitionNameId = integrationDef.Id;  // → IntegrationProviderDef
insert stepDef;
```

The request payload size limit is 12 MB. Maximum request payload size, timeouts, and body shape are controlled entirely by the Integration Definition attributes above — there's no `RequestBodyTemplate` merge-field mechanism to author.

**Named Credential setup** (deploy via metadata — this part is unchanged and standard Salesforce metadata):
```xml
<!-- force-app/main/default/namedCredentials/FiberAPI.namedCredential-meta.xml -->
<NamedCredential xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>FiberAPI</fullName>
    <label>Fiber Provisioning API</label>
    <endpoint>https://api.fiberprovider.com</endpoint>
    <principalType>NamedUser</principalType>
    <protocol>NoAuthentication</protocol>
</NamedCredential>
```

**Completing an async step from the external system's callback** (the callback endpoint you build updates the step directly):
```apex
FulfillmentStep step = new FulfillmentStep(id = stepId, State = 'Completed');
upsert step;
```

---

## Type 2: Apex Type Provider

**Use when:** You need custom Apex logic for the callout (transformations, retry logic, conditional routing).

**Interface:** `industriesintegrationfwk.ProcessIntegrationProvider` — this part of the original pattern is confirmed accurate against the v68.0 guide (printed pp. 1976–1979), including the `executeCallout` signature and `IntegrationCalloutResponse` usage below.

```apex
global class DROSampleOrderAdapter
    implements industriesintegrationfwk.ProcessIntegrationProvider {

    // Called by DRO for each step execution
    global static industriesintegrationfwk.IntegrationCalloutResponse executeCallout(
        String requestGuid,    // Unique GUID for this callout instance
        String inputRecordId,  // Salesforce ID of the FulfillmentStep or triggering record
        String payload,        // JSON payload built from step definition template
        Map<String, Object> attributes  // Provider attributes defined in getProviderAttributes()
    ) {
        String endpoint = (String) attributes.get('endpoint');
        String apiKey   = (String) attributes.get('apiKey');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint + '/provision');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + apiKey);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(payload);

        Http http = new Http();
        HttpResponse res = http.send(req);

        industriesintegrationfwk.IntegrationCalloutResponse icr;

        if (res.getStatusCode() == 200 || res.getStatusCode() == 202) {
            icr = new industriesintegrationfwk.IntegrationCalloutResponse(true);
        } else {
            icr = new industriesintegrationfwk.IntegrationCalloutResponse(false);
            icr.setResponseCode(res.getStatusCode());
            icr.setErrorMessage('Provisioning failed: ' + res.getBody());
        }

        return icr;
    }

    // Defines configurable attributes shown in the Integration Definition UI
    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return new List<industriesintegrationfwk.ApexProviderAttr>{
            new industriesintegrationfwk.ApexProviderAttr('endpoint', 'https://api.example.com', false),
            new industriesintegrationfwk.ApexProviderAttr('apiKey', '', true)  // true = required
        };
    }
}
```

**Wire to the step definition — corrected.** `ApexClassName` is **not** a field on `FulfillmentStepDefinition`. Instead, create an Integration Definition of type **Apex Defined**, point it at this Apex class, then reference the Integration Definition from the step definition:

```apex
// Integration Definition (Setup, or via its supporting metadata) references DROSampleOrderAdapter
// as its Apex class. The step definition then points at the Integration Definition:
stepDef.StepType = 'Callout';
stepDef.IntegrationDefinitionNameId = integrationDef.Id;  // Integration Definition referencing DROSampleOrderAdapter
```

**IntegrationCalloutResponse constructor:**
```apex
// Success
industriesintegrationfwk.IntegrationCalloutResponse icr =
    new industriesintegrationfwk.IntegrationCalloutResponse(true);

// Failure
industriesintegrationfwk.IntegrationCalloutResponse icr =
    new industriesintegrationfwk.IntegrationCalloutResponse(false);
icr.setResponseCode(500);
icr.setErrorMessage('Unable to process request: timeout');
```

**Async pattern for Apex Type Provider:** add a `Callback URL` attribute (via `ApexProviderAttr`) to the Integration Definition, return response code `202` from `executeCallout` to signal async acceptance, and have your callback endpoint update the step directly once the external system finishes:
```apex
FulfillmentStep step = new FulfillmentStep(id = 'stepId', State = 'Completed');
upsert step;
```

**Advanced interface:** for logging or an `HttpBaseProvider`-mediated HTTP client, implement `industriesintegrationfwk.ProcessIntegrationProviderAdvanced` instead, whose `executeCallout` takes an additional `industriesintegrationfwk.HttpBaseProvider` parameter.

---

## Type 3: External Services Defined Provider

**Use when:** External system has an OpenAPI spec that has been registered as an External Service in Salesforce.

**Setup:** Import the OpenAPI spec in Setup → External Services (this generates the Apex-callable operation contract), then create an Integration Definition of type **External Services Defined** referencing that External Service and the specific operation. Point the step definition at the Integration Definition:

```apex
stepDef.StepType = 'Callout';
stepDef.IntegrationDefinitionNameId = integrationDef.Id;  // Integration Definition of type External Services Defined
```

`ExternalServiceName` and `ExternalServiceOperationName` are **not** fields on `FulfillmentStepDefinition` — the External Service and operation are selected when configuring the Integration Definition itself, not on the step definition record. Omnistudio Admin and Omnistudio Runtime permissions are required to configure Integration Procedures for request/response transformation on this provider type.

No custom Apex is required. The platform generates the callout from the OpenAPI spec.

---

## Error Handling (all provider types)

To verify a Standard Fulfillment Provider callout succeeded, check the `status` value in the payload. If `status` is undefined, these HTTP codes count as success: `200`, `201`, `202`, `203`, `204`, `205`, `206`, `302`, `304`. Any other outcome moves the fulfillment step's `State` to `FatallyFailed`, with detail captured in the step's `ExecutionMessage` field.

---

## Comparison Matrix

| Feature | Standard Fulfillment Provider | Apex Type Provider | External Services Defined Provider |
|---|---|---|---|
| Code required | None | Yes (Apex) | None |
| Custom logic | No | Yes | No |
| Configuration surface | Integration Definition (Standard/`CalloutIntegrationProvider`) attributes | Integration Definition (Apex Defined) + Apex class implementing `ProcessIntegrationProvider` | Integration Definition (External Services Defined) + External Service/OpenAPI spec |
| Authentication | Named Credential (+ External Credential) | Custom (via provider attributes, e.g. API key) | External Service credentials |
| Retry control | Platform (fallout rules) | Custom, integrates with fallout rules | Platform |
| 202 async | Yes — step `State` → `InProgress` | Yes — return response code 202 from `executeCallout` | Yes |
| Suitable for | Simple REST callouts with a predefined payload | Complex business logic, request/response transformation | OpenAPI-defined services |

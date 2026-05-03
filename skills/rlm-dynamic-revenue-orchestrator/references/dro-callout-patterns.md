# DRO — Callout Provider Patterns

Three callout provider types are available. Choose based on complexity and external system requirements.

---

## Type 1: Standard Fulfillment Provider

**Use when:** External system has a REST API and you want zero-code callout configuration via Named Credentials.

**Async contract:**
- HTTP 202 → step stays `Running`; external system must call back to Salesforce to complete
- HTTP 200 → step immediately moves to `Completed`

```apex
FulfillmentStepDefinition stepDef = new FulfillmentStepDefinition();
stepDef.Name = 'Provision Fiber Service';
stepDef.DeveloperName = 'Provision_Fiber_Service';
stepDef.FulfillmentStepDefinitionGroupId = group.Id;
stepDef.CalloutType = 'StandardFulfillmentProvider';
stepDef.NamedCredentialId = [SELECT Id FROM NamedCredential WHERE DeveloperName = 'FiberAPI' LIMIT 1].Id;
stepDef.HttpMethod = 'POST';
stepDef.Endpoint = '/orders/provision';
// Template supports merge fields from the order/quote context
stepDef.RequestBodyTemplate = '{"orderId": "{OrderId}", "productCode": "{ProductCode__c}"}';
insert stepDef;
```

**Named Credential setup** (deploy via metadata):
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

---

## Type 2: Apex Type Provider

**Use when:** You need custom Apex logic for the callout (transformations, retry logic, conditional routing).

**Interface:** `industriesintegrationfwk.ProcessIntegrationProvider`

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

    // Defines configurable attributes shown in the step definition UI
    global static List<industriesintegrationfwk.ApexProviderAttr> getProviderAttributes() {
        return new List<industriesintegrationfwk.ApexProviderAttr>{
            new industriesintegrationfwk.ApexProviderAttr('endpoint', 'https://api.example.com', false),
            new industriesintegrationfwk.ApexProviderAttr('apiKey', '', true)  // true = required
        };
    }
}
```

**Wire to step definition:**
```apex
stepDef.CalloutType = 'ApexTypeProvider';
stepDef.ApexClassName = 'DROSampleOrderAdapter';
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

---

## Type 3: External Services Defined Provider

**Use when:** External system has an OpenAPI spec that has been registered as an External Service in Salesforce.

**Setup:** Import the OpenAPI spec in Setup → External Services. This generates Apex classes you can reference.

```apex
stepDef.CalloutType = 'ExternalServicesDefinedProvider';
stepDef.ExternalServiceName = 'ProvisioningService';        // External Service name in Setup
stepDef.ExternalServiceOperationName = 'provisionResource'; // Operation from the OpenAPI spec
```

No custom Apex required. The platform generates the callout from the OpenAPI spec.

---

## Comparison Matrix

| Feature | Standard HTTP | Apex Type | External Services |
|---|---|---|---|
| Code required | None | Yes (Apex) | None |
| Custom logic | No | Yes | No |
| Authentication | Named Credential | Custom | External Service credentials |
| Retry control | Platform | Custom | Platform |
| 202 async | Yes | Yes (return `true` with async signal) | Yes |
| Suitable for | Simple REST callouts | Complex business logic | OpenAPI-defined services |

# DRO — Platform Events Reference

Both events are available from API v66.0 and support the same subscriber types.

**Supported subscribers:** Apex Triggers ✓, Flows ✓, Processes ✗, Pub/Sub API ✓, Streaming API ✓

---

## FulfillmentSourceChangeEvent

Published when a fulfillment source record changes state (e.g., a FulfillmentStep moves from Running to Completed or Failed).

**Streaming channel:** `/event/FulfillmentSourceChangeEvent`

### Fields

| Field | Type | Description |
|---|---|---|
| `EventUuid` | String | Platform-generated unique ID for this event instance |
| `RecordIdentifier` | String | Salesforce ID of the changed fulfillment source record (e.g., FulfillmentStep ID) |
| `ReplayId` | String | CometD replay ID for resuming missed events |

### Apex Trigger Example

```apex
trigger FulfillmentSourceChangeTrigger on FulfillmentSourceChangeEvent (after insert) {
    List<Id> changedStepIds = new List<Id>();

    for (FulfillmentSourceChangeEvent evt : Trigger.new) {
        changedStepIds.add(evt.RecordIdentifier);
    }

    // Query current state of affected steps
    Map<Id, FulfillmentStep> steps = new Map<Id, FulfillmentStep>([
        SELECT Id, Status, FulfillmentPlanId, FulfillmentStepDefinition.Name
        FROM FulfillmentStep
        WHERE Id IN :changedStepIds
    ]);

    for (FulfillmentStep step : steps.values()) {
        if (step.Status == 'Failed') {
            // Create a case, send an alert, trigger retry
        } else if (step.Status == 'Completed') {
            // Advance to next step, notify downstream systems
        }
    }
}
```

### Flow: Subscribe to FulfillmentSourceChangeEvent

In Flow Builder, create an **Autolaunched Flow** triggered by the platform event:
- Trigger: Platform Event Message
- Platform Event: `FulfillmentSourceChangeEvent`
- Access the event fields via `$Record.RecordIdentifier`, `$Record.EventUuid`

---

## SalesTrxnDecompositionEvent

Published when a sales transaction decomposition job completes or fails. Decomposition is the process of breaking a sales transaction (Quote/Order) into fulfillment records.

**Streaming channel:** `/event/SalesTrxnDecompositionEvent`

### Fields

| Field | Type | Description |
|---|---|---|
| `EventUuid` | String | Platform-generated unique ID |
| `ReplayId` | String | CometD replay ID |
| `SalesTransactionIdentifier` | String | ID of the sales transaction (Quote or Order) being decomposed |
| `Status` | String | `Completed` \| `Failed` |
| `ErrorCode` | String | Error code if Status = `Failed`; null if Completed |

### Apex Trigger Example

```apex
trigger SalesTrxnDecompositionTrigger on SalesTrxnDecompositionEvent (after insert) {
    for (SalesTrxnDecompositionEvent evt : Trigger.new) {
        String trxnId = evt.SalesTransactionIdentifier;

        if (evt.Status == 'Completed') {
            // Decomposition succeeded — trigger next workflow
            // e.g., activate the order, notify rep
        } else if (evt.Status == 'Failed') {
            // Log the failure and alert
            String errCode = evt.ErrorCode;
            // Query the Order/Quote for context
            Order o = [SELECT Id, Status, AccountId FROM Order WHERE Id = :trxnId LIMIT 1];
            // Create a case or send alert
        }
    }
}
```

### Pub/Sub API Subscription (Node.js example)

```javascript
// Subscribe to SalesTrxnDecompositionEvent via Pub/Sub API
const { PubSubApiClient } = require('salesforce-pubsub-api-client');

const client = new PubSubApiClient();
await client.connect();

const subscription = await client.subscribe(
    '/event/SalesTrxnDecompositionEvent',
    (event) => {
        const payload = event.payload;
        console.log('Transaction:', payload.SalesTransactionIdentifier);
        console.log('Status:', payload.Status);
        if (payload.Status === 'Failed') {
            console.error('Error code:', payload.ErrorCode);
        }
    }
);
```

---

## Replay ID Usage

To resume event consumption from where you left off (avoiding missed events during downtime):

```apex
// In an Apex trigger, the ReplayId is available but managed by the platform.
// For Pub/Sub API clients, store and resume:
Map<String, String> replayOptions = new Map<String, String>{
    '/event/SalesTrxnDecompositionEvent' => lastKnownReplayId
};
```

---

## CometD Streaming API Subscription

```javascript
const CometD = require('cometd');
const cometd = new CometD.CometD();

cometd.configure({ url: instanceUrl + '/cometd/66.0/', requestHeaders: { Authorization: 'Bearer ' + accessToken } });

cometd.handshake((handshakeReply) => {
    if (handshakeReply.successful) {
        cometd.subscribe('/event/SalesTrxnDecompositionEvent', (message) => {
            console.log(JSON.stringify(message.data.payload));
        });
    }
});
```

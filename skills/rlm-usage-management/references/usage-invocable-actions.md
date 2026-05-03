# Usage Management — Standard Invocable Actions

These actions are available in Flows and Apex for Usage Management operations.

---

## Available Actions

| Action Label | Category | Description |
|---|---|---|
| Create Usage Summary | Usage Management | Creates a UsageSummary record for an account/period |
| Get Usage Entitlements | Usage Management | Returns active UsageEntitlementBucket records for an account |
| Process Usage | Usage Management | Processes a batch of usage events against entitlement buckets |
| Calculate Usage Billing | Usage Management | Calculates billable amounts from UsageRatableSummary records |
| Renew Usage Grants | Usage Management | Triggers grant renewal per the UsageGrantRenewalPolicy |
| Apply Usage Rollover | Usage Management | Applies rollover of unused grants per UsageGrantRolloverPolicy |

---

## Usage in Flow

Each action is a **Salesforce-provided Action** in Flow Builder under the **Usage Management** category.

---

## IndustriesUsageSettings Metadata

Enable Usage Management features:

File: `force-app/main/default/settings/IndustriesUsage.settings-meta.xml`

```xml
<IndustriesUsageSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableUsageManagement>true</enableUsageManagement>
    <enableUsageEntitlements>true</enableUsageEntitlements>
</IndustriesUsageSettings>
```

Deploy: `sf project deploy start --metadata "Settings:IndustriesUsage" --target-org <alias>`

---

## Apex: Process Usage Events

```apex
// Submit usage events for processing
List<Map<String, Object>> usageEvents = new List<Map<String, Object>>{
    new Map<String, Object>{
        'accountId'          => '001xx...',
        'usageResourceId'    => '0rrxx...',
        'consumedQuantity'   => 5.5,
        'consumptionDate'    => DateTime.now().format()
    }
};

// Call via invocable method or direct service
// Platform will deduct from appropriate buckets per DrawdownOrder policy
```

---

## Apex: Query Grant Balance

```apex
public static Decimal getRemainingBalance(Id accountId, Id usageResourceId) {
    AggregateResult[] result = [
        SELECT SUM(RemainingQuantity) total
        FROM UsageEntitlementBucket
        WHERE UsageEntitlementAccount.AccountId = :accountId
          AND UsageEntitlementAccount.UsageResourceId = :usageResourceId
          AND Status = 'Active'
          AND ExpirationDate >= TODAY
    ];
    return (Decimal) result[0].get('total');
}
```

---

## Platform Events for Usage

Usage Management uses the DRO platform events indirectly:
- `SalesTrxnDecompositionEvent` — fires when an order containing usage-based products is decomposed
- Subscribe to confirm `TransactionUsageEntitlement` records were created

See `rlm-dynamic-revenue-orchestrator/references/dro-platform-events.md` for subscription patterns.

---

## DrawdownOrder Processing Logic

When multiple `UsageEntitlementBucket` records exist for an account:

**ExpiringFirst** (recommended):
1. Sort active buckets by `ExpirationDate ASC`
2. Consume from the soonest-expiring bucket first
3. When exhausted, move to next bucket

**GrantedFirst**:
1. Sort active buckets by `CreatedDate DESC`
2. Consume from the most recently granted bucket first
3. When exhausted, move to previous bucket

**GrantedLast** (deprecated):
- Do not use; scheduled for removal in future releases

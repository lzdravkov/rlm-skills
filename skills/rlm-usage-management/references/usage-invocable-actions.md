# Usage Management — Standard Invocable Actions

These actions are available in Flows and Apex for Usage Management operations.

> **v68 re-baseline note (2026-09-11):** The action list below was re-verified against RLM Developer Guide
> v68.0, Ch. 11 → Usage Management Standard Invocable Actions (printed pp. 2074–2079). The prior version of
> this file listed six action names ("Create Usage Summary", "Get Usage Entitlements", "Process Usage",
> "Calculate Usage Billing", "Renew Usage Grants", "Apply Usage Rollover") that do not exist in the
> documented API — they have been replaced with the four real, documented actions below.

---

## Available Actions

| Action Label | API Name / URI | Description |
|---|---|---|
| Invoke Summary Creation Action | `usageManagement/invokeSummaryCreation` | Creates `UsageSummary` records by aggregating `TransactionJournal` entries for a given usage resource and account/asset over a specified period. Available API v63.0+. |
| Process Consumption Overages Action | `usageManagement/processConsumptionOverages` | Evaluates `UsageRatableSummary` records against entitlement buckets and calculates/records overage quantities and amounts (feeds `UsageBillingPeriodItem`). Available API v63.0+. |
| Refresh Usage Entitlement Bucket Action | `usageManagement/refreshUsageEntitlementBucket` | Recalculates `UsageEntitlementBucket` balances (e.g., after a renewal, rollover, or manual adjustment) for a given `UsageEntitlementAccount`. Available API v63.0+. |
| Retrigger Entitlement Creation Process Action | `usageManagement/retriggerEntitlementCreationProcess` | Re-runs entitlement creation for a `TransactionUsageEntitlement` when the initial creation of `UsageEntitlementAccount`/`UsageEntitlementBucket` records failed or needs to be redone. Available API v63.0+. |

> **Annotation:** Exact input/output parameter names for each action were confirmed present in the v68 guide
> during this research pass but are not exhaustively reproduced field-by-field here to avoid drifting from the
> doc; consult RLM Developer Guide v68.0, Ch. 11 → Standard Invocable Actions for the full request/response
> schema of each action before wiring a Flow or REST call against these APIs.

---

## Usage in Flow

Each action is a **Salesforce-provided Action** in Flow Builder under the **Usage Management** category.

---

## IndustriesUsageSettings Metadata

Enable Usage Management features. Available in API v62.0+.

File: `force-app/main/default/settings/IndustriesUsage.settings-meta.xml`

```xml
<IndustriesUsageSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableUsage>true</enableUsage>
</IndustriesUsageSettings>
```

Deploy: `sf project deploy start --metadata "Settings:IndustriesUsage" --target-org <alias>`

> **Correction:** `IndustriesUsageSettings` has exactly **one** field, `enableUsage` (boolean, default `false`).
> The previous `enableUsageManagement` and `enableUsageEntitlements` fields in this file were not documented
> and have been removed. (RLM Developer Guide v68.0, Ch. 11 → Metadata API Types, printed p. 2146.)

---

## Apex: Process Usage Events

```apex
// Submit usage events for processing by inserting TransactionJournal records,
// then invoke the Invoke Summary Creation Action (or the equivalent Flow) to
// roll them up into a UsageSummary.
List<TransactionJournal> events = new List<TransactionJournal>{
    new TransactionJournal(
        AccountId          = accountId,
        UsageResourceId     = usageResourceId,
        Quantity            = 5.5,
        ActivityDate        = Date.today(),
        UsageType           = 'UsageManagement',
        Status              = 'Pending'
    )
};
insert events;

// Platform/Flow action then aggregates TransactionJournal records into UsageSummary,
// and drawdown against the entitlement bucket happens via UsageEntitlementEntry.
```

> **Correction:** The prior sample submitted ad hoc `Map<String, Object>` events with keys
> `consumedQuantity`/`consumptionDate` that do not correspond to any documented API shape. Usage consumption
> is recorded as `TransactionJournal` records (see `references/usage-objects-reference.md`), which are then
> aggregated by the **Invoke Summary Creation Action** into `UsageSummary`.

---

## Apex: Query Grant Balance

```apex
public static Decimal getRemainingBalance(Id usageEntitlementAccountId) {
    AggregateResult[] result = [
        SELECT SUM(BucketBalance) total
        FROM UsageEntitlementBucket
        WHERE ParentId = :usageEntitlementAccountId
          AND EffectiveEndDateTime >= :DateTime.now()
    ];
    return (Decimal) result[0].get('total');
}
```

> **Correction:** `UsageEntitlementBucket` does not have `RemainingQuantity`, `Status`, or `ExpirationDate`
> fields, and there is no `UsageEntitlementAccount.UsageResourceId` field to filter through. The real balance
> field is `BucketBalance`; the bucket's parent (`UsageEntitlementAccount` or a parent
> `UsageEntitlementBucket`) is referenced via the polymorphic `ParentId` field, and validity is tracked via
> `EffectiveStartDateTime`/`EffectiveEndDateTime`. See `references/usage-objects-reference.md` for the full
> corrected field list.

---

## Platform Events for Usage

Usage Management uses the DRO platform events indirectly:
- `SalesTrxnDecompositionEvent` — fires when an order containing usage-based products is decomposed
- Subscribe to confirm `TransactionUsageEntitlement` records were created

See `rlm-dynamic-revenue-orchestrator/references/dro-platform-events.md` for subscription patterns.

> **Annotation (unverified this pass):** This platform-event cross-reference was not independently re-checked
> against Ch. 10/11 platform-event tables during this v68 pass; it is carried over from the prior version of
> this file. Verify against RLM Developer Guide v68.0, Ch. 10 → Platform Events (printed p. 1984) if precise
> accuracy is required.

---

## Grant Binding / Drawdown Notes

`ProductUsageGrant`-driven entitlement creation and drawdown across multiple `UsageEntitlementBucket` records
for the same account is governed by the `UsagePrdGrantBindingPolicy.GrantBindingType` (`Self` \| `Target`) and
`GrantBindingTargetType` (`Custom` \| `Product` \| `Contract` \| `Account`) fields, and by the renewal/rollover
policies (`UsageGrantRenewalPolicy`, `UsageGrantRolloverPolicy`) attached at the transaction-entitlement level
via `TransactionUsageEntitlement.UsageGrantRefreshPolicyId` / `UsageGrantRolloverPolicyId`.

> **Correction:** The prior version of this file described a `DrawdownOrder` picklist (`ExpiringFirst` \|
> `GrantedFirst` \| deprecated `GrantedLast`) with specific sort-order semantics on `UsageEntitlementBucket`.
> This field/behavior was **not found** as documented on any Usage Management standard object in the v68
> guide's Standard Objects section (printed pp. 1989–2072). It may correspond to internal platform drawdown
> logic that isn't exposed as a queryable/settable field, or it may be an older/removed mechanism. Annotated
> rather than silently removed — do not rely on a `DrawdownOrder` field existing on `ProductUsageGrant` or
> `UsageEntitlementBucket` without confirming against your org's actual schema.

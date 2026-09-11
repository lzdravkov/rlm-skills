# Asset Lifecycle — Object Reference

> **v68 (Winter '27) re-baseline note (2026-09-11):** this file was substantially corrected against
> RLM Developer Guide (v68, Winter '27) — Chapter 8: Transaction Management › Standard Objects
> (Asset* cluster). Fields that could not be confirmed as real in that section are marked
> **UNVERIFIED** and kept only as annotations, not assertions. `AssetActionSource` and
> `AssetContractRelationship` are new coverage — real v68 standard objects that had no entry in the
> v1.0.0 version of this file. `QuoteAction` has been removed as a documented object (could not be
> confirmed as real) and replaced with a note.

---

## Asset

The primary subscription record created from an OrderItem after order activation (via the
**Create or Update Asset From Order Action**).

| Field | Type | Description |
|---|---|---|
| `Id` | ID | Record ID (standard) |
| `Name` | String | Auto-generated, or set to the order line item's custom product name if present |
| `AccountId` | Reference → Account | Account that owns the asset |
| `Product2Id` | Reference → Product2 | Product this asset represents |
| `Quantity` | Decimal | Current active quantity |
| `Status` | Picklist | Confirmed values: `Purchased` \| `Shipped` \| `Installed` \| `Registered` \| `Obsolete` |
| `ParentId` | Reference → Asset | Direct parent asset (for bundle children) |
| `RootAssetId` | Reference → Asset | Root asset in a bundle hierarchy |
| `SerialNumber` | String | Optional hardware serial number |
| `InstallDate` | Date | Physical install date |
| `UsageEndDate` | Date | When usage entitlements expire |
| `Price` | Currency | Current unit price of the asset |

> **Corrections (v68 re-baseline):**
> - `Status` values `Cancelled`, `Expired`, `Lost/Stolen` could **not be confirmed** — replaced with
>   the confirmed values `Registered` and `Obsolete`, which were not previously documented.
> - `LifecycleStartDate`, `LifecycleEndDate`, `RenewalStatus`, `TotalLifecycleAmount`, `CurrentMrr`,
>   `OrderId`, `OrderItemId`, and `IsCompetitorProduct` could **not be confirmed** as real `Asset`
>   fields in the Standard Objects section reviewed for this re-baseline. They are **UNVERIFIED** —
>   removed from the table above rather than left asserting incorrect field names. If your org has
>   fields by these names, confirm whether they are managed-package/custom additions before relying
>   on them in SOQL or validation logic.
> - There is no confirmed direct link from `Asset` back to `Order`/`OrderItem` as a field on `Asset`
>   itself — the link is tracked via `AssetAction`/`AssetActionSource` (see below) and the
>   `CreateAssetOrderEvent` platform event's nested detail records.

---

## AssetStatePeriod

Tracks the quantity and status of an asset across its lifecycle. A new period is created whenever
an amendment, renewal, or cancellation changes the asset's state. Used as the authoritative source
for proration calculations.

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | Parent asset |
| `StartDate` | Date | Start of this state period |
| `EndDate` | Date | End of this state period (null = current active period) |
| `Quantity` | Decimal | Quantity during this period |
| `Mrr` | Currency | Monthly recurring revenue during this period |

> **Corrections (v68 re-baseline):** the field is **`Mrr`**, not `MrrAmount`. `Status`, `ChangeType`,
> `OrderId`, and `ProratedMrrAmount` could **not be confirmed** as real `AssetStatePeriod` fields in
> the Standard Objects section reviewed — removed from the table above. `AssetStatePeriodAttribute`
> is a confirmed related object (Asset* cluster) for period-level attribute values, but its field
> shape was not verified in this pass — annotated as a pointer for future coverage rather than
> documented in detail here.

**Usage for proration**:
```apex
// Get the current active period for billing
AssetStatePeriod current = [
    SELECT StartDate, EndDate, Quantity, Mrr
    FROM AssetStatePeriod
    WHERE AssetId = :assetId
      AND EndDate = null
    LIMIT 1
];

// Get all periods for audit/history
List<AssetStatePeriod> history = [
    SELECT StartDate, EndDate, Quantity, Mrr
    FROM AssetStatePeriod
    WHERE AssetId = :assetId
    ORDER BY StartDate ASC
];
```
> Note: the `Status = 'Active'` filter from the prior version of this file was removed — `Status` is
> not a confirmed field on this object. Use `EndDate = null` to identify the current period instead.

---

## AssetAction

Records each lifecycle action taken against an asset (one per amendment, renewal, cancellation,
swap, upgrade, downgrade, transfer, or rollback).

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | Asset the action was taken on |
| `AssetActionNumber` | String | Auto-generated action number |
| `ActionDate` | Date | When the lifecycle change takes effect |
| `Type` | Picklist | Confirmed values: `Cancel` \| `Change` \| `Convert` \| `Generate` (describes the REST API operation that generated the action, **not** a business label like "Amend") |
| `Subtype` | Picklist | Confirmed values: `DowngradeFrom`, `DowngradeTo`, `FieldAmendment`, `Rollback`, `StartDateAdjustment`, `SwapIn`, `SwapOut`, `TransferFrom`, `TransferTo`, `UpgradeFrom`, `UpgradeTo` |
| `CategoryEnum` | Picklist | Business category of the action — confirmed values include `Downgrades`, `Swaps`, `Upgrades`, `Transfers` (populated by the v66+ Swap/Upgrade/Downgrade Business APIs and Initiate Transfer Action) |
| `CanRollBack` | Boolean | Whether this action is eligible for `initiateRollBackLastAction` |
| `RolledbackAssetAction` | Reference → AssetAction | Set when this action reverses a prior one |
| `QuantityChange` | Decimal | Net quantity change from this action |
| `Amount` / `TotalAmount` | Currency | Total dollar amount(s) associated with the action (also `SubtotalChange`, `AdjustmentAmountChange`, `ProductAmountChange`, `EstimatedTaxChange`, `ActualTaxChange`, `MrrChange`, `TotalMrr`, `TotalQuantity`) | 

> **Corrections (v68 re-baseline):** `Type` values `Amend`/`Renew`/`Cancel`/`Transfer`/`Rollback`
> (prior version) do **not match** the confirmed picklist — real `Type` values are `Cancel` |
> `Change` | `Convert` | `Generate` (these describe the underlying REST operation, not the business
> action). The business-facing lifecycle label lives in `Subtype`/`CategoryEnum` instead. `Status`,
> `EffectiveDate`, `OrderId`, `QuoteId`, and `Comments` could **not be confirmed** as real
> `AssetAction` fields — replaced with `ActionDate`, `AssetActionNumber`, and the various
> `*Amount`/`*Change` financial fields, all confirmed real. Use `AssetActionSource` (below) to trace
> an `AssetAction` back to the order/quote line that generated it, rather than a direct `OrderId`/
> `QuoteId` field on `AssetAction` itself.

---

## AssetActionSource *(new coverage — v68 re-baseline)*

Links an `AssetAction` back to the order or quote line item that generated it. Previously absent
from this skill's documentation entirely.

| Field | Type | Description |
|---|---|---|
| `AssetActionId` | Reference → AssetAction | The action this source record supports |

> **Annotation:** the full field list for `AssetActionSource` (and its child
> `AssetActionSrcPriceAdjustment`) was not exhaustively read in this pass beyond confirming the
> object's existence and its role (source-tracing for an `AssetAction`). Treat the table above as a
> minimal, conservative starting point — expand it once the full field list is verified. A related
> confirmed field of interest for usage-billing scenarios is `AssetActionSource.BillingTerm`
> (referenced in the Chapter 8 material but not independently field-type-verified here).

---

## AssetContractRelationship *(new coverage — v68 re-baseline)*

Links an `Asset` to the `Contract` that governs it. Previously absent from this skill's
documentation entirely.

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | The asset |
| `ContractId` | Reference → Contract | The governing contract |

> **Annotation:** confirmed as a real v68 standard object in the Asset* cluster (Chapter 8 Standard
> Objects); its full field list was not exhaustively read in this pass — table above is a minimal,
> conservative starting point pending a dedicated field-level read.

---

## AssetRelationship

Links two assets together.

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | Primary asset in the relationship |
| `RelatedAssetId` | Reference → Asset | Related asset |
| `RelationshipType` | Picklist | Confirmed values: `Crossgrade` \| `Replacement` \| `Upgrade` (default: `Replacement`) |

> **Corrections (v68 re-baseline):** `RelationshipType` values `Component` and `Reference` (prior
> version) could **not be confirmed** — replaced with the confirmed `Crossgrade`/`Replacement`/
> `Upgrade`. `IsActive`, `FromDate`, `ToDate` could **not be confirmed** as real fields on this
> object — removed. This object is understood to back the v66+ **Initiate Swap / Upgrade /
> Downgrade** Business APIs (`POST /revenue/transaction-management/assets/actions/
> {swap|upgrade|downgrade}`), which create `AssetRelationship` records alongside `AssetAction`
> records categorized via `CategoryEnum` (Swaps/Upgrades/Downgrades). For bundle parent/child
> hierarchy, use `Asset.ParentId`/`RootAssetId` directly rather than `AssetRelationship`.

---

## QuoteAction — removed (unverified)

The v1.0.0 version of this file documented a `QuoteAction` object linking lifecycle quotes back to
assets. **This could not be confirmed as a real v68 standard object** in the Standard Objects
sections reviewed for this re-baseline. The confirmed mechanism for tracking in-flight lifecycle
actions is the `AssetAction` object (and, for order/quote line provenance, `AssetActionSource`) —
each Standard Invocable Action (`initiateAmendment`, `initiateRenewal`, `initiateCancellation`,
`initiateTransfer`, `initiateRollBackLastAction`) directly creates a `Quote` or `Order` record (per
its `*OutputType`/`outputType` input), not a `QuoteAction` junction record.

If your org has a genuine `QuoteAction` object (e.g. via a managed package), do not assume it
matches the field shape previously documented here — verify independently.

To check for in-flight lifecycle actions, prefer:
```apex
List<AssetAction> inProgress = [
    SELECT Id, AssetActionNumber, ActionDate, Type, Subtype, CategoryEnum
    FROM AssetAction
    WHERE AssetId = :assetId
    ORDER BY ActionDate DESC
];
```

---

## Platform Event: CreateAssetOrderEvent

Fires when assets are created from an activated order. Available API v55.0+.

**Channel**: `/event/CreateAssetOrderEvent`

| Field | Type | Description |
|---|---|---|
| `AssetDetails` | List\<CreateAssetOrderDtlEvent\> | Nested per-asset detail records (see below) |
| `CorrelationIdentifier` | String | Correlation ID for the originating request |
| `EventUuid` | String | Unique event ID |
| `IsLastEvent` | Boolean | Whether this is the last event in the batch (avail 62.0+) |
| `OrderIdentifier` | String | ID of the order associated with this event (Revenue Cloud, avail 64.0+) |
| `ReplayId` | String | Standard platform event replay ID |
| `RequestIdentifier` | String | ID of the originating request |

### Nested: CreateAssetOrderDtlEvent (not directly subscribable — access via `AssetDetails`)

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | ID of the created/updated asset |
| `ErrorCode` | String | Error code, if any |
| `ErrorMessage` | String | Error description, if any |
| `EventUuid` | String | Unique ID for this detail record |
| `IsSuccess` | Boolean | Whether asset creation succeeded for this line (default `false`; avail 61.0+) |
| `OrderItemId` | Reference → OrderItem | The order item this asset was created from (avail 61.0+) |
| `ReplayId` | String | Standard platform event replay ID |

> **Correction (v68 re-baseline):** the previous flat shape (`EventUuid`, `AssetId`, `OrderId`
> directly on `CreateAssetOrderEvent`) is **wrong** — there is no top-level `AssetId` or `OrderId`
> field on this event. Per-asset detail (`AssetId`, `OrderItemId`, `IsSuccess`, `ErrorCode`,
> `ErrorMessage`) lives on the nested `CreateAssetOrderDtlEvent` records inside `AssetDetails`, and
> the order-level identifier is named `OrderIdentifier` (avail 64.0+), not `OrderId`. Subscribers
> must iterate `AssetDetails` to get per-asset outcomes.

```apex
trigger CreateAssetOrderTrigger on CreateAssetOrderEvent (after insert) {
    for (CreateAssetOrderEvent evt : Trigger.new) {
        for (CreateAssetOrderDtlEvent detail : evt.AssetDetails) {
            if (detail.IsSuccess) {
                String assetId = detail.AssetId;
                // e.g., trigger DRO provisioning, create usage entitlements
            } else {
                System.debug('Asset creation failed: ' + detail.ErrorCode + ' - ' + detail.ErrorMessage);
            }
        }
    }
}
```

---

## Key SOQL Patterns

### Full lifecycle history for an asset
```soql
SELECT Id, AssetActionNumber, ActionDate, Type, Subtype, CategoryEnum, CanRollBack
FROM AssetAction
WHERE AssetId = '02ixx...'
ORDER BY ActionDate ASC
```
> **Correction:** the prior query selected `Status, EffectiveDate, OrderId, QuoteId` — none of
> which are confirmed `AssetAction` fields. Replaced with the confirmed field set above.

### Bundle hierarchy (parent + all children)
```soql
SELECT Id, Name, Status, Quantity, ParentId, RootAssetId
FROM Asset
WHERE RootAssetId = '02ixx...'
ORDER BY ParentId NULLS FIRST
```

### Renewal opportunities for an order's assets
Prefer the **Get Renewable Assets Summary Action** (`getRenewableAssetsSummary`, input `orderId`)
over a direct SOQL filter — there is no confirmed `Asset.RenewalStatus` field to query on. See
`rlm-transaction-management/references/asset-lifecycle-patterns.md` for the full invocable-action
pattern and the real `RenewalOpptyDetail` output shape (`assetId`, `startDate`, `endDate`,
`lastAssetAction`, `renewalPriceDetails[]`, etc.).

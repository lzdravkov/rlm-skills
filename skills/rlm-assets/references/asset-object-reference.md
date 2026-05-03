# Asset Lifecycle — Object Reference

---

## Asset

The primary subscription record created from an OrderItem after order activation.

| Field | Type | Description |
|---|---|---|
| `Id` | ID | Record ID (standard) |
| `Name` | String | Auto-generated or custom asset name |
| `AccountId` | Reference → Account | Account that owns the asset |
| `Product2Id` | Reference → Product2 | Product this asset represents |
| `Quantity` | Decimal | Current active quantity |
| `Status` | Picklist | `Purchased` \| `Shipped` \| `Installed` \| `Cancelled` \| `Expired` \| `Lost/Stolen` |
| `LifecycleStartDate` | Date | When the subscription started |
| `LifecycleEndDate` | Date | When the subscription ends (null for Evergreen) |
| `RenewalStatus` | Picklist | `Draft` \| `Eligible` \| `InProgress` \| `Renewed` \| `Expired` |
| `Price` | Currency | Current unit price of the asset |
| `TotalLifecycleAmount` | Currency | Total value over the full subscription term |
| `CurrentMrr` | Currency | Current monthly recurring revenue |
| `OrderId` | Reference → Order | Order that created this asset |
| `OrderItemId` | Reference → OrderItem | OrderItem that created this asset |
| `RootAssetId` | Reference → Asset | Root asset in a bundle hierarchy |
| `ParentId` | Reference → Asset | Direct parent asset (for bundle children) |
| `IsCompetitorProduct` | Boolean | Whether this is a competitive displacement asset |
| `SerialNumber` | String | Optional hardware serial number |
| `InstallDate` | Date | Physical install date |
| `UsageEndDate` | Date | When usage entitlements expire |

---

## AssetStatePeriod

Tracks the quantity, price, and status of an asset across its lifecycle. A new period is created whenever an amendment, renewal, or cancellation changes the asset's state. Used as the authoritative source for proration calculations.

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | Parent asset |
| `StartDate` | Date | Start of this state period |
| `EndDate` | Date | End of this state period (null = current active period) |
| `Quantity` | Decimal | Quantity during this period |
| `MrrAmount` | Currency | Monthly recurring revenue during this period |
| `Status` | Picklist | `Active` \| `Cancelled` \| `Expired` |
| `ChangeType` | Picklist | `Created` \| `Amended` \| `Renewed` \| `Cancelled` \| `Transferred` |
| `OrderId` | Reference → Order | Order that created this period |
| `ProratedMrrAmount` | Currency | Prorated MRR for partial periods |

**Usage for proration**:
```apex
// Get the current active period for billing
AssetStatePeriod current = [
    SELECT StartDate, EndDate, Quantity, MrrAmount
    FROM AssetStatePeriod
    WHERE AssetId = :assetId
      AND Status = 'Active'
      AND EndDate = null
    LIMIT 1
];

// Get all periods for audit/history
List<AssetStatePeriod> history = [
    SELECT StartDate, EndDate, Quantity, MrrAmount, ChangeType
    FROM AssetStatePeriod
    WHERE AssetId = :assetId
    ORDER BY StartDate ASC
];
```

---

## AssetAction

Records each lifecycle action taken against an asset. One `AssetAction` per amendment, renewal, cancellation, etc.

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | Asset the action was taken on |
| `Type` | Picklist | `Amend` \| `Renew` \| `Cancel` \| `Transfer` \| `Rollback` |
| `Status` | Picklist | `Pending` \| `InProgress` \| `Completed` \| `Failed` \| `Rolled Back` |
| `EffectiveDate` | Date | When the lifecycle change takes effect |
| `OrderId` | Reference → Order | Order that completed this action |
| `QuoteId` | Reference → Quote | Quote generated for this action |
| `Comments` | LongTextArea | Notes on the action |

---

## AssetRelationship

Links two assets together. Commonly used for bundle parent/child, upgrade/replacement, or account transfer tracking.

| Field | Type | Description |
|---|---|---|
| `AssetId` | Reference → Asset | Primary asset in the relationship |
| `RelatedAssetId` | Reference → Asset | Related asset |
| `RelationshipType` | Picklist | `Component` \| `Replacement` \| `Reference` |
| `IsActive` | Boolean | Whether this relationship is currently active |
| `FromDate` | Date | When the relationship started |
| `ToDate` | Date | When the relationship ended (null = active) |

---

## QuoteAction

Links a lifecycle quote back to the originating asset and action type. Created automatically when a lifecycle action is initiated.

| Field | Type | Description |
|---|---|---|
| `QuoteId` | Reference → Quote | The lifecycle quote |
| `AssetId` | Reference → Asset | Asset being modified |
| `Type` | Picklist | `Amendment` \| `Renewal` \| `Cancellation` \| `Transfer` \| `Rollback` |
| `Status` | Picklist | `Draft` \| `In Progress` \| `Completed` \| `Cancelled` |
| `EffectiveDate` | Date | Lifecycle action effective date |

Query to check for in-flight lifecycle actions:
```apex
List<QuoteAction> inProgress = [
    SELECT Id, Type, Status, EffectiveDate
    FROM QuoteAction
    WHERE AssetId = :assetId
      AND Status IN ('Draft', 'In Progress')
];
```

---

## Platform Event: CreateAssetOrderEvent

Fires when assets are created from an activated order.

**Channel**: `/event/CreateAssetOrderEvent`

| Field | Type | Description |
|---|---|---|
| `EventUuid` | String | Unique event ID |
| `AssetId` | String | ID of the created asset |
| `OrderId` | String | ID of the originating order |

Subscribe via Apex trigger or Flow to trigger downstream processes (DRO provisioning, usage grant creation, notification).

```apex
trigger CreateAssetOrderTrigger on CreateAssetOrderEvent (after insert) {
    for (CreateAssetOrderEvent evt : Trigger.new) {
        String assetId = evt.AssetId;
        // e.g., trigger DRO provisioning, create usage entitlements
    }
}
```

---

## Key SOQL Patterns

### Assets expiring in next 90 days (renewal pipeline)
```soql
SELECT Id, Name, AccountId, Product2.Name,
       Quantity, LifecycleEndDate, RenewalStatus, CurrentMrr
FROM Asset
WHERE Status = 'Purchased'
  AND LifecycleEndDate <= NEXT_N_DAYS:90
  AND LifecycleEndDate != null
ORDER BY LifecycleEndDate ASC
```

### Full lifecycle history for an asset
```soql
SELECT Id, Type, Status, EffectiveDate, OrderId, QuoteId
FROM AssetAction
WHERE AssetId = '02ixx...'
ORDER BY EffectiveDate ASC
```

### Bundle hierarchy (parent + all children)
```soql
SELECT Id, Name, Status, Quantity, ParentId, RootAssetId
FROM Asset
WHERE RootAssetId = '02ixx...'
ORDER BY ParentId NULLS FIRST
```

# Usage Management — Object Reference

All 22+ objects that make up the Usage Management module.

---

## Setup/Catalog Objects (deployed)

### UnitOfMeasureClass
Groups units of measure.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `DeveloperName` | String | API name |
| `Description` | String | |

### UnitOfMeasure
Defines a unit of measure (e.g., GB, Hour, Seat).

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `UnitCode` | String | Abbreviated code (e.g., "GB") |
| `UnitOfMeasureClassId` | Reference → UnitOfMeasureClass | Required |
| `RoundingMethod` | Picklist | `Up` \| `Down` \| `Nearest` |
| `Scale` | Integer | Decimal precision for quantities |

### UsageResource
Catalog entry for a trackable usage resource.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `DeveloperName` | String | API name |
| `UnitOfMeasureId` | Reference → UnitOfMeasure | Required |
| `IsActive` | Boolean | |
| `Description` | String | |

### ProductUsageResource
Links a Product2 to a UsageResource.

| Field | Type | Description |
|---|---|---|
| `Product2Id` | Reference → Product2 | Required |
| `UsageResourceId` | Reference → UsageResource | Required |
| `IsActive` | Boolean | |

### ProductUsageResourcePolicy
Policies governing a ProductUsageResource (overage, renewal, rollover).

| Field | Type | Description |
|---|---|---|
| `ProductUsageResourceId` | Reference → ProductUsageResource | Required |
| `UsageOveragePolicyId` | Reference → UsageOveragePolicy | |
| `UsageGrantRenewalPolicyId` | Reference → UsageGrantRenewalPolicy | |
| `UsageGrantRolloverPolicyId` | Reference → UsageGrantRolloverPolicy | |

### ProductUsageGrant
Defines the quantity and terms of usage granted when a product is sold.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `Product2Id` | Reference → Product2 | Required |
| `ProductUsageResourceId` | Reference → ProductUsageResource | Required |
| `ProductSellingModelId` | Reference → ProductSellingModel | Required |
| `Quantity` | Decimal | Amount of usage granted per period |
| `DrawdownOrder` | Picklist | `ExpiringFirst` \| `GrantedFirst` \| `GrantedLast` (deprecated) |
| `EffectiveStartDate` | DateTime | When the grant becomes effective |
| `EffectiveEndDate` | DateTime | When the grant expires |
| `IsActive` | Boolean | |

### UsagePrdGrantBindingPolicy
Binding policy for a product usage grant.

| Field | Type | Description |
|---|---|---|
| `ProductUsageGrantId` | Reference → ProductUsageGrant | Required |
| `BindingType` | Picklist | `PerAccount` \| `PerSubscription` |

### UsageCommitmentPolicy
Minimum commitment terms for usage products.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `CommitmentQuantity` | Decimal | Minimum committed usage |
| `CommitmentPeriod` | Picklist | `Monthly` \| `Quarterly` \| `Annually` |
| `UsageResourceId` | Reference → UsageResource | Required |

### UsageGrantRenewalPolicy
How grants refresh at end of period.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `RenewalType` | Picklist | `Fixed` (same quantity each period) \| `Cumulative` (adds to previous) |
| `RenewalPeriod` | Picklist | `Monthly` \| `Quarterly` \| `Annually` |

### UsageGrantRolloverPolicy
What happens to unused grant balances.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `RolloverType` | Picklist | `None` \| `FullRollover` \| `CappedRollover` |
| `RolloverCap` | Decimal | Max rollover quantity (for `CappedRollover`) |

### UsageOveragePolicy
Behavior when usage exceeds the granted amount.

| Field | Type | Description |
|---|---|---|
| `Name` | String | Required |
| `OverageType` | Picklist | `Chargeable` \| `Block` \| `Allow` |
| `OverageRate` | Decimal | Rate per unit for `Chargeable` overage |
| `UsageResourceId` | Reference → UsageResource | Required |

---

## Runtime Objects (created by platform)

### UsageEntitlementAccount
Per-account container for all usage entitlements.

| Field | Type | Description |
|---|---|---|
| `AccountId` | Reference → Account | Required |
| `UsageResourceId` | Reference → UsageResource | |
| `Status` | Picklist | `Active` \| `Inactive` |

### UsageEntitlementBucket
Individual grant bucket for a specific entitlement period.

| Field | Type | Description |
|---|---|---|
| `UsageEntitlementAccountId` | Reference → UsageEntitlementAccount | Required |
| `GrantedQuantity` | Decimal | Total quantity originally granted |
| `ConsumedQuantity` | Decimal | Quantity used so far |
| `RemainingQuantity` | Decimal | `GrantedQuantity - ConsumedQuantity` |
| `ExpirationDate` | Date | When this bucket expires |
| `Status` | Picklist | `Active` \| `Expired` \| `Exhausted` |
| `DrawdownOrder` | Integer | Sort order for drawdown (from `ProductUsageGrant.DrawdownOrder`) |

### UsageEntitlementEntry
Individual consumption record against a bucket.

| Field | Type | Description |
|---|---|---|
| `UsageEntitlementBucketId` | Reference → UsageEntitlementBucket | Required |
| `ConsumedQuantity` | Decimal | Quantity consumed in this entry |
| `ConsumptionDate` | DateTime | When consumption occurred |
| `SourceRecordId` | String | Source record that generated this consumption |

### UsageSummary
Aggregated usage record per billing period per account.

| Field | Type | Description |
|---|---|---|
| `AccountId` | Reference → Account | |
| `UsageResourceId` | Reference → UsageResource | |
| `ConsumedQuantity` | Decimal | Total consumption in the period |
| `BillingPeriodStartDate` | Date | |
| `BillingPeriodEndDate` | Date | |

### UsageRatableSummary
Rating-ready usage summary for billing calculations.

| Field | Type | Description |
|---|---|---|
| `UsageSummaryId` | Reference → UsageSummary | |
| `TotalQuantity` | Decimal | Total usage in period |
| `BillableQuantity` | Decimal | Quantity that should be billed (after grants applied) |
| `OverageQuantity` | Decimal | Usage above the granted amount |
| `RateCardEntryId` | Reference → RateCardEntry | Rate to apply |

### UsageBillingPeriodItem
Billing period-level usage data for invoice generation.

| Field | Type | Description |
|---|---|---|
| `BillingPeriodStartDate` | Date | |
| `BillingPeriodEndDate` | Date | |
| `BillableAmount` | Currency | Calculated billable amount |
| `UsageRatableSummaryId` | Reference → UsageRatableSummary | |

### TransactionUsageEntitlement
Links a transaction line item to a usage entitlement.

| Field | Type | Description |
|---|---|---|
| `TransactionLineItemId` | String | ID of the order/quote line item |
| `UsageEntitlementAccountId` | Reference → UsageEntitlementAccount | |
| `ProductUsageGrantId` | Reference → ProductUsageGrant | |

### UsageCmtAssetRelatedObj
Links a usage commitment asset to related objects.

| Field | Type | Description |
|---|---|---|
| `CommitmentAssetId` | String | ID of the commitment asset |
| `RelatedObjectId` | String | ID of the related record |
| `RelatedObjectType` | String | API name of the related object |

### UsageRatableSumCmtAssetRt
Rate information for a ratable summary tied to a commitment asset.

| Field | Type | Description |
|---|---|---|
| `UsageRatableSummaryId` | Reference → UsageRatableSummary | |
| `CommitmentAssetId` | String | |
| `RateCardEntryId` | Reference → RateCardEntry | |

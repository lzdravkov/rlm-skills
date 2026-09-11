# Asset Lifecycle — Patterns Reference

## Asset Lifecycle Overview

After an order is fulfilled, assets are created automatically from order items. Asset lifecycle actions allow customers to modify, renew, cancel, or transfer existing subscriptions.

```
Order (Activated)
  └── Create or Update Asset From Order Action
        └── Asset (Status: Purchased)
              ├── Amendment → new Quote or Order (initiateAmendment)
              ├── Renewal   → new Quote or Order (initiateRenewal)
              ├── Cancellation → new Quote or Order (initiateCancellation)
              ├── Transfer  → 2 new Quotes/Orders — source (negative qty) + target (positive qty) (initiateTransfer)
              └── Rollback  → reverts last amendment/renewal only (initiateRollBackLastAction)
```

> **Correction (v68 re-baseline):** the prior diagram showed each action creating a `QuoteAction`
> record (`QuoteAction.Type = Amendment` etc.). `QuoteAction` could **not be confirmed** as a real
> v68 standard object in the Standard Objects sections reviewed for this re-baseline — treat it as
> **unverified**. The confirmed mechanism (from the Standard Invocable Actions reference) is that
> each action directly creates a `Quote` or `Order` record, selected via the action's output-type
> input (`amendOutputType` / `renewOutputType` / `cancelOutputType` / `outputRecordType` /
> `outputType`).

---

## Asset Prerequisites

Before any lifecycle action:
1. `Asset.Status = 'Purchased'`
2. `Asset.LifecycleEndDate > TODAY` (for renewal/amendment — not required for cancellation)
3. No pending in-flight lifecycle action on the asset
4. For renewal: confirm eligibility via the **Get Renewable Assets Summary Action**'s `lastAssetAction`
   / `endDate` output rather than a `RenewalStatus` field (see note below — `Asset.RenewalStatus`
   could not be confirmed as a real field; see `rlm-assets/references/asset-object-reference.md`).

---

## Amendment Flow

```
1. Call: Initiate Amendment Action (initiateAmendment)
2. Returns: amendRecordId (0Q0... quote, or 801... order, per amendOutputType)
3. If Quote: open it → modify quantity, attributes, or pricing
4. Approve and convert to order (if not already an order)
5. Activate order → updates Asset record + creates AssetAction history
```

### Invocable (Flow / Actions REST):
Action: `initiateAmendment` — `POST /services/data/v68.0/actions/standard/initiateAmendment`
- Inputs: `amendAssetIds` (required), `amendStartDate` (required, datetime), `amendOutputType`
  (required: `Quote` | `Order`), `quantityChange` (required, double — add to or reduce from the
  asset's existing quantity), `amendContractId`, `amendOpportunityId`, `skipPricing` (avail 64.0+)
- Outputs: `amendRecordId`, `requestIdentifier`

> **Correction:** the previous input/output names (`assetId` → `amendmentQuoteId`) and the
> `POST /commerce/assets/{assetId}/amendment` Business API path were fabricated. The real Business
> API equivalent is `POST /connect/revenue-management/assets/actions/amend`.
>
> For **usage products**, use a two-step flow: (1) `initiateAmendment` with `amendOutputType: Quote`,
> then (2) convert that amendment quote to an order. Creating the order directly
> (`amendOutputType: Order`) is not supported for usage products — it can create Order Products
> without required Rate Card Entry records, causing order activation to fail.

---

## Renewal Flow

```
1. Call: Get Renewable Assets Summary Action (getRenewableAssetsSummary) with orderId
2. Inspect renewableAssetsSummary[] — e.g. filter by endDate approaching, or lastAssetAction
3. Call: Initiate Renewal Action (initiateRenewal) with renewAssetIds
4. Returns: renewRecordId
5. Review and approve renewal quote (if renewOutputType = Quote)
6. Convert to order → extends the asset's term; new AssetAction history created
```

### Invocable (Flow / Actions REST):
Action: `getRenewableAssetsSummary` — `POST /services/data/v68.0/actions/standard/getRenewableAssetsSummary`
- Input: `orderId` (required)
- Output: `renewableAssetsSummary[]` — Apex-defined (`renew_assets_summary.RenewalOpptyDetail`):
  `assetId`, `account`, `productId`, `priceBookId`, `priceBookEntryId`, `orderItem`,
  `opportunityProductId`, `startDate`, `endDate`, `lastAssetAction` (`Initial Sale` | `Upsell` |
  `Downsell` | `Renewal` | `Cancellation`), `lastAssetActionSubtype`, `rootAssetOpportunity`,
  `renewalPriceDetails[]` (`netUnitPrice`, `quantity`)

Action: `initiateRenewal` — `POST /services/data/v68.0/actions/standard/initiateRenewal`
- Inputs: `renewAssetIds` (required), `renewOutputType` (required), `renewStartDate`/`renewEndDate`
  (avail 62.0+), `renewContractId`, `renewOpportunityId`, `skipPricing` (64.0+),
  `rampOptionsDetails` (Apex-defined `RampOptionInputRepresentation` — segment type/duration/count
  for group ramp schedules, avail 67.0+)
- Outputs: `renewRecordId`, `requestIdentifier`

> **Correction:** the previous input (`accountId` to Get Renewable Assets Summary; `assetId`/
> `renewalTerm`/`renewalTermUnit` to Initiate Renewal) and output (`renewalStatus` filter,
> `renewalQuoteId`) names were fabricated or wrong. Get Renewable Assets Summary takes an `orderId`,
> not an `accountId`, and there is no `renewalTerm`/`renewalTermUnit` input on Initiate Renewal —
> term length is implied by `renewStartDate`/`renewEndDate`. The real Business API path for renewal
> is `POST /connect/revenue-management/assets/actions/renew`.

---

## Cancellation Flow

```
1. Call: Initiate Cancellation Action (initiateCancellation)
2. Returns: cancelRecordId
3. Approve cancellation quote (if cancelOutputType = Quote)
4. Convert to order → activates the cancellation; asset lifecycle ends/reduces per quantity
```

### Invocable (Flow / Actions REST):
Action: `initiateCancellation` — `POST /services/data/v68.0/actions/standard/initiateCancellation`
- Inputs: `cancelAssetIds` (required — all assets in a request must belong to the same price book),
  `cancelStartDate` (required, datetime), `cancelOutputType` (required), `cancelContractId`,
  `cancelOpportunityId`, `skipPricing` (64.0+)
- Outputs: `cancelRecordId`, `requestIdentifier`

> **Correction:** previous input/output names (`assetId`/`cancellationDate` → `cancellationQuoteId`)
> were fabricated, as was the claim that cancellation directly sets `Asset.Status = 'Cancelled'` —
> the real `Asset.Status` picklist (confirmed against the Standard Objects section) is `Purchased` |
> `Shipped` | `Installed` | `Registered` | `Obsolete`; there is no confirmed `Cancelled` value. The
> real Business API path is `POST /connect/revenue-management/assets/actions/cancel`.

---

## Transfer Flow

Transfer ownership of an asset (or multiple assets) to another account. This action generates
**2** quotes/orders: one for the source account (negative quantity, reduces the existing asset)
and one for the target account (positive quantity, creates a new asset). The transfer is complete
once both are assetized.

```
1. Call: Initiate Transfer Action (initiateTransfer)
2. Returns: assetTransferSourceId, assetTransferTargetId
3. Approve both → source asset quantity reduced, target account gets a new asset
```

### Invocable (Flow / Actions REST):
Action: `initiateTransfer` — `POST /services/data/v68.0/actions/standard/initiateTransfer` (avail 65.0+)
- Inputs: `transferRecords` (required, Apex-defined list of
  `connectapi__TransferRecordInputRepresentation` — `assetId` + `transferQuantity`),
  `targetAccountId` (required), `transferDate` (required), `outputRecordType` (required: `Quote` |
  `Order`), `targetContractId`, `shouldSkipPricing`
- Outputs: `assetTransferSourceId`, `assetTransferTargetId`, `requestIdentifier`

> **Correction:** no dedicated Business API (`/commerce/assets/{id}/transfer` or otherwise) was
> found for Transfer in the v68 Business API Resources inventory — this action is available only
> via the Standard Invocable Actions / Actions REST layer. The source/target quantities must be
> equal and opposite (e.g. source `-5`, target `5`); if you change one, update the other manually.

---

## Rollback

Reverts the last amendment or renewal on a particular asset, restoring it to its previous state.
**Not** supported for cancellation or transfer.

```
1. Call: Initiate Rollback on Last Action (initiateRollBackLastAction)
2. Returns: recordId (reversal Quote or Order)
3. Approve → restores previous asset state
```

### Invocable (Flow / Actions REST):
Action: `initiateRollBackLastAction` — `POST /services/data/v68.0/actions/standard/initiateRollBackLastAction`
(avail 65.0+)
- Inputs: `assetIds` (required), `outputType` (required: `Quote` | `Order`)
- Output: `recordId`

Confirmed constraints:
- You can roll back only **future-dated** transactions.
- Rollback is **not supported for legacy assets**.
- The rollback operation is supported for **amendment and renewal only** — not cancellation or transfer.

> **Correction:** no dedicated Business API path was found for Rollback either — same as Transfer,
> it's Standard Invocable Action / Actions REST only. Use only when a lifecycle action was
> processed incorrectly.

---

## Renewable Assets — Getting Renewal Candidates

There is no confirmed `Asset.RenewalStatus` field to filter on directly (see
`rlm-assets/references/asset-object-reference.md` for the annotation). To find renewal candidates,
call **Get Renewable Assets Summary Action** with the relevant `orderId` and inspect the returned
`endDate`/`lastAssetAction` values, rather than running a SOQL filter on a `RenewalStatus` picklist:

```apex
// Preferred v68 pattern — invoke the action, don't rely on an unverified Asset.RenewalStatus field
Map<String, Object> summaryInputs = new Map<String, Object>{ 'orderId' => orderId };
// ... invoke getRenewableAssetsSummary via Invocable.Action, inspect renewableAssetsSummary[]
```

If you still need a general "assets expiring soon" query for triage before calling the action:
```soql
SELECT Id, Name, Status, LifecycleEndDate,
       Product2.Name, AccountId, Quantity
FROM Asset
WHERE AccountId = '001...'
  AND Status = 'Purchased'
  AND LifecycleEndDate <= NEXT_N_DAYS:90
ORDER BY LifecycleEndDate ASC
```
`RenewalStatus` has been removed from this query — it could not be confirmed as a real field.

---

## Asset Status Values

| Status | Meaning |
|---|---|
| `Purchased` | Active, in service |
| `Shipped` | Ordered but not yet activated |
| `Installed` | Installed but not yet active |
| `Registered` | Confirmed v68 value — asset has been registered (exact semantics not detailed in the sections reviewed) |
| `Obsolete` | Confirmed v68 value — asset is no longer in active use |

> **Correction (v68 re-baseline):** `Cancelled`, `Expired`, and `Lost/Stolen` were **not confirmed**
> as real `Asset.Status` picklist values in the Standard Objects section reviewed for this
> re-baseline; `Registered` and `Obsolete` were confirmed and have been added. If your org's page
> layouts show different values, it may reflect org-specific picklist customization — verify against
> your own Asset.Status field metadata before relying on this list for validation logic.

# Asset Lifecycle — Patterns Reference

## Asset Lifecycle Overview

After an order is fulfilled, assets are created automatically from order items. Asset lifecycle actions allow customers to modify, renew, cancel, or transfer existing subscriptions.

```
Order (Activated)
  └── Create or Update Asset From Order Action
        └── Asset (Status: Purchased)
              ├── Amendment → new Quote (QuoteAction.Type = Amendment)
              ├── Renewal   → new Quote (QuoteAction.Type = Renewal)
              ├── Cancellation → new Quote (QuoteAction.Type = Cancellation)
              ├── Transfer  → new Quote (QuoteAction.Type = Transfer)
              └── Rollback  → reverts last lifecycle action
```

---

## Asset Prerequisites

Before any lifecycle action:
1. `Asset.Status = 'Purchased'`
2. `Asset.LifecycleEndDate > TODAY` (for renewal/amendment — not required for cancellation)
3. No pending in-flight lifecycle action on the asset
4. For renewal: `Asset.RenewalStatus != 'InProgress'`

---

## Amendment Flow

```
1. Call: Initiate Amendment Action (assetId)
2. Returns: amendmentQuoteId (0Q0...)
3. Open Quote → modify quantity, attributes, or pricing
4. Approve and convert to order
5. Activate order → updates Asset record
```

### Invocable (Flow):
Action: `InitiateAmendmentAction`
- Input: `assetId` (Text)
- Output: `amendmentQuoteId` (Text)

### Business API:
```
POST /commerce/assets/{assetId}/amendment
Body: { "effectiveDate": "2026-06-01" }
Response: { "quoteId": "0Q0..." }
```

---

## Renewal Flow

```
1. Call: Get Renewable Assets Summary Action (accountId)
2. Filter: RenewalStatus = "Eligible"
3. Call: Initiate Renewal Action (assetId)
4. Returns: renewalQuoteId
5. Review and approve renewal quote
6. Convert to order → extends LifecycleEndDate
```

### Invocable (Flow):
Action: `InitiateRenewalAction`
- Input: `assetId` (Text), optional `renewalTerm` (Number), `renewalTermUnit` (Text)
- Output: `renewalQuoteId` (Text)

---

## Cancellation Flow

```
1. Call: Initiate Cancellation Action (assetId)
2. Returns: cancellationQuoteId
3. Approve cancellation quote
4. Convert to order → sets Asset.Status = Cancelled
```

### Invocable (Flow):
Action: `InitiateCancellationAction`
- Input: `assetId` (Text), `cancellationDate` (Date)
- Output: `cancellationQuoteId` (Text)

---

## Transfer Flow

Transfer ownership of an asset to another account:
```
1. Call: Initiate Transfer Action (assetId, targetAccountId)
2. Returns: transferQuoteId
3. Approve → moves asset to new account
```

---

## Rollback

Reverts the most recent lifecycle action (amendment, renewal, or cancellation):
```
1. Call: Initiate Rollback on Last Action (assetId)
2. Returns: rollbackQuoteId
3. Approve → restores previous asset state
```

Use only when a lifecycle action was processed incorrectly. Cannot roll back an asset that has been billed for the new term.

---

## Renewable Assets — SOQL Query

```soql
SELECT Id, Name, Status, LifecycleEndDate, RenewalStatus,
       Product2.Name, AccountId, Quantity
FROM Asset
WHERE AccountId = '001...'
  AND Status = 'Purchased'
  AND LifecycleEndDate <= NEXT_N_DAYS:90
ORDER BY LifecycleEndDate ASC
```

---

## Asset Status Values

| Status | Meaning |
|---|---|
| `Purchased` | Active, in service |
| `Shipped` | Ordered but not yet activated |
| `Installed` | Installed but not yet active |
| `Cancelled` | Lifecycle ended by cancellation |
| `Expired` | Term ended without renewal |
| `Lost/Stolen` | Reported missing |

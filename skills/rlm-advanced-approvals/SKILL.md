---
name: rlm-advanced-approvals
description: Submit, review, reassign, override, and recall approval work items in Salesforce Revenue Cloud using the 6 Advanced Approvals Standard Invocable Actions. Use when integrating with the Advanced Approvals approval workflow — canceling submissions, overriding decisions, reassigning approvers, recalling submissions, reviewing work items, or retrieving related record details from previous approval instances. Do NOT use for Salesforce standard approvals (different API). Triggers on: "approval", "approve", "reject", "approval work item", "submit for approval", "recall approval", "reassign approver", "override approval", "ApprovalWorkItem", "approvalSubmissionId", "approvalWorkItemId", "smart approval", "channelType".
compatibility: Salesforce Revenue Cloud, API v68.0+, Advanced Approvals enabled
metadata:
  version: 2.0.0
  author: skunkworks-rca
---

# RLM Advanced Approvals

## Overview

Advanced Approvals provides 6 standard invocable actions. All are callable via:
- Flow Builder (Salesforce-provided action elements)
- Apex (`actions/standard/` REST endpoint)
- `System.invoke()` in Apex

**Important**: These actions work with Revenue Cloud's **Advanced Approvals** framework — not the standard Salesforce approval processes. The objects are `ApprovalSubmission` and `ApprovalWorkItem`, which are distinct from Salesforce's standard `ProcessInstance` and `ProcessInstanceWorkItem`.

---

## The 6 Invocable Actions

### 1. cancelApprovalSubmission

Cancels an active approval submission.

**REST URI**: `POST /services/data/v68.0/actions/standard/cancelApprovalSubmission`

**Inputs:**

| Field | Type | Required | Description |
|---|---|---|---|
| `approvalSubmissionId` | String | Required | ID of the `ApprovalSubmission` record |
| `comments` | String | Optional | Reason for cancellation |

**Outputs:** none (check for errors in response)

**When to use:** When a quote/order is recalled before any approver has acted.

---

### 2. getPreviousRelaRecDetails *(available since API v66.0)*

Retrieves related record details from a previous approval orchestration instance. Used to carry forward context (e.g., related Account or Order) when re-submitting after a recall.

**REST URI**: `POST /services/data/v68.0/actions/standard/getPreviousRelaRecDetails`

**Inputs:**

| Field | Type | Required | Description |
|---|---|---|---|
| `flowOrchestrationInstanceId` | String | Required | ID of the completed `FlowOrchestrationInstance` |
| `stepApiNamesList` | String | Required | A comma-delimited list of orchestration step API names to retrieve related records for. *(Annotated: the RLM Developer Guide's action-reference table states the input `Type` as `string` with a "comma-delimited list" description, but the guide's own JSON example for this action shows array/list syntax. Verify the exact shape — comma-delimited string vs. array — against your org's action metadata before relying on this in production.)* |

**Outputs:**

| Field | Type | Description |
|---|---|---|
| `previousRelatedRecordDetails` | sObject | Related record data from the previous orchestration instance |

**Note:** This action is available in API version 66.0 and later — it is not restricted to *only* v66.0. It remains available and fully supported under the v68.0 baseline used by this skill. (Corrected from a prior "v66.0 only" mislabel; source: RLM Developer Guide, Chapter 9: Advanced Approvals — Standard Invocable Actions — Get Previous Related Record Details, printed p. 1809.)

---

### 3. overrideApprovalWorkItem

Approves or rejects a work item on behalf of the assigned approver, bypassing the normal approval flow.

**REST URI**: `POST /services/data/v68.0/actions/standard/overrideApprovalWorkItem`

**Inputs:**

| Field | Type | Required | Description |
|---|---|---|---|
| `approvalWorkItemId` | String | Required | ID of the `ApprovalWorkItem` record |
| `approvalDecision` | String | Required | `approve` or `reject` |
| `channelType` | String | Optional | `InvocableAction` \| `Slack` \| `ApprovalRecord` |
| `comments` | String | Optional | Reason for override |

**Outputs:** none

**Permission required:** User must have the "Override Approval Work Items" permission.

---

### 4. reassignApprovalWorkItem

Reassigns an approval work item from its current assignee to a different user.

**REST URI**: `POST /services/data/v68.0/actions/standard/reassignApprovalWorkItem`

**Inputs:**

| Field | Type | Required | Description |
|---|---|---|---|
| `approvalWorkItemId` | String | Required | ID of the `ApprovalWorkItem` record |
| `assigneeId` | String | Required | User ID of the new assignee |
| `comments` | String | Optional | Reason for reassignment |

**Outputs:** none

---

### 5. recallApprovalSubmission

Recalls an active approval submission, returning it to the submitter for modification.

**REST URI**: `POST /services/data/v68.0/actions/standard/recallApprovalSubmission`

**Inputs:**

| Field | Type | Required | Description |
|---|---|---|---|
| `approvalSubmissionId` | String | Required | ID of the `ApprovalSubmission` record |
| `comments` | String | Optional | Reason for recall |

**Outputs:** none

**Difference from cancel:** Recall is initiated by the submitter and returns the record for editing. Cancel is a hard stop with no intent to re-submit.

---

### 6. reviewApprovalWorkItem

The primary action used by approvers to approve or reject a work item assigned to them.

**REST URI**: `POST /services/data/v68.0/actions/standard/reviewApprovalWorkItem`

**Inputs:**

| Field | Type | Required | Description |
|---|---|---|---|
| `approvalWorkItemId` | String | Required | ID of the `ApprovalWorkItem` record |
| `approvalDecision` | String | Required | `approve` or `reject` |
| `channelType` | String | Optional | `InvocableAction` \| `Slack` \| `ApprovalRecord` |
| `comments` | String | Optional | Comments from the approver |

**Outputs:** none

**Difference from override:** `reviewApprovalWorkItem` is for the assigned approver acting on their own work item. `overrideApprovalWorkItem` allows a user with override permissions to act on any work item.

---

## REST API Usage Pattern

All 6 actions use the same REST pattern:

```bash
curl -X POST \
  https://yourInstance.salesforce.com/services/data/v68.0/actions/standard/reviewApprovalWorkItem \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": [{
      "approvalWorkItemId": "04axx000000...",
      "approvalDecision": "approve",
      "channelType": "InvocableAction",
      "comments": "Looks good, approved."
    }]
  }'
```

---

## Apex Usage Pattern

```apex
// Using standard invocable action from Apex
Map<String, Object> inputs = new Map<String, Object>{
    'approvalWorkItemId' => '04axx...',
    'approvalDecision'   => 'approve',
    'channelType'        => 'InvocableAction',
    'comments'           => 'Approved via automation'
};

List<Object> results = (List<Object>) System.invoke(
    'reviewApprovalWorkItem',
    new List<Map<String, Object>>{ inputs }
);
```

---

## Flow Usage Pattern

In Flow Builder, add a **Salesforce-provided Action** element and search for the action name (e.g., "Review Approval Work Item"). Map input/output variables directly.

---

## Preview Approval Business API (v67.0+ coverage)

In addition to the 6 Standard Invocable Actions, Advanced Approvals exposes a Connect REST **Business API** for previewing an approval submission before actually submitting it:

**REST URI**: `POST /services/data/v68.0/connect/advanced-approvals/approval-submission/preview`

This resource lets a caller simulate what approval steps/approvers would be generated for a record without creating a real `ApprovalSubmission`. Starting in **API v67.0**, the request body supports an `inputParameters` field, letting callers pass additional context values into the preview evaluation (useful for previewing approval outcomes under "what-if" field values before committing a real submission).

*(Annotated: this skill's core focus is the 6 Standard Invocable Actions; the exact full request/response schema for this Business API is documented under RLM Developer Guide, Chapter 9: Advanced Approvals › Business APIs [printed pp. 1817–1819] — consult that section directly before building against it in production.)*

---

## ApprovalWorkItem Smart Approval Fields

_Fields confirmed in the v68 guide (RLM Developer Guide, Ch.9 Advanced Approvals → Fields on Standard Objects, ApprovalWorkItem)._

| Field | Type | Description |
|---|---|---|
| `IsAutoReviewed` | Boolean | Whether this work item was auto-approved/rejected by smart approval rules |
| `IsEligibleForSmartApproval` | Boolean | Whether this work item qualifies for smart approval processing |
| `SmartApprovalBasisWorkItemId` | String | ID of the reference work item that established the smart approval basis |

Smart approval automatically carries forward a prior approval decision when the same approver reviews a similar record, reducing manual review effort.

---

## channelType Values

| Value | Description |
|---|---|
| `InvocableAction` | Triggered from Flow or Apex invocable action |
| `Slack` | Triggered from the Salesforce Slack integration |
| `ApprovalRecord` | Triggered from the standard Approval Record UI |

---

## Object Reference

| Object | Description |
|---|---|
| `ApprovalSubmission` | Represents a submitted approval request; `Status` picklist values are Approved, Canceled, Errored, InProgress, Recalled, Rejected, Suspended (corrected — the base object has no "Active"/"Cancelled"/"Completed" values; source: Salesforce Object Reference, ApprovalSubmission) |
| `ApprovalWorkItem` | A single step in an approval process, assigned to a user; `Status` picklist values are Approved, Assigned, Canceled, Errored, Recalled, Rejected, Withdrawn (corrected — there is no "Pending"/"Reassigned" value; source: Salesforce Object Reference, ApprovalWorkItem) |
| `FlowOrchestrationInstance` | Records an execution instance of a Flow Orchestration (used by `getPreviousRelaRecDetails`) |

---

## Common Issues

### Action fails with "Insufficient Privileges"
Cause: Running user lacks permission for the specific action (e.g., override requires "Override Approval Work Items" custom permission).
Solution: Assign the appropriate permission set that grants the required custom permission.

### `getPreviousRelaRecDetails` returns "Invalid API version"
Cause: Called against an API version earlier than this action's introduction version (v66.0).
Solution: This skill targets API v68.0+; confirm `sf config get apiVersion` returns `68.0` (or later) and that it is at least `66.0`, since that is this specific action's minimum supported version.

### `approvalDecision` case sensitivity
Cause: Values must be lowercase: `approve` and `reject`.
Solution: Ensure exact lowercase values; `Approve` or `APPROVE` will fail.

---

## Deployment

Advanced Approvals is metadata-only (invocable actions + permission sets). No data object deployment sequence is required. Ensure the following are deployed before use:
- Advanced Approvals feature enabled in org setup
- Permission sets granting "Override Approval Work Items" custom permission to approver override users
- Apex triggers or Flows consuming `ApprovalWorkItem` and `ApprovalSubmission` records

---

## See Also

| Skill | Why |
|---|---|
| `rlm-transaction-management` | Quotes must be approved before converting to order; `Submit for Approval` is a common pre-order step |
| `rlm-deployment` | Deploying approval permission sets and Flow orchestration metadata across orgs |

---

## Changelog

| Version | Date | Change |
|---|---|---|
| 2.0.0 | 2026-09-11 | v68.0 re-baseline: bumped compatibility and all REST URIs to API v68.0; corrected the `getPreviousRelaRecDetails` "v66.0 only" mislabel — it's available in v66.0 **and later**, including v68.0; corrected `ApprovalSubmission`/`ApprovalWorkItem` `Status` picklist values in Object Reference; updated Common Issues version framing; replaced page-number citation with a section-title citation; annotated a possible doc inconsistency in `stepApiNamesList`'s documented type |
| 1.1.0 | 2026-05-02 | Added Deployment section; added See Also table; `getPreviousRelaRecDetails` v66.0-only note |
| 1.0.0 | 2026-04-01 | Initial skill — 6 invocable actions, REST pattern, Apex pattern, smart approval fields |

---

## References
- RLM Developer Guide (v68.0, Winter '27) — Chapter 9: Advanced Approvals › Standard Invocable Actions & Business APIs
- See `references/approvals-flow-patterns.md` for Flow and FlowActionCall metadata examples

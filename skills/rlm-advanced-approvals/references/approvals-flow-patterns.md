# Advanced Approvals — Flow & FlowActionCall Patterns

---

## FlowActionCall Metadata for Each Action

Use these in Flow metadata XML to invoke the 6 Advanced Approvals actions.

### reviewApprovalWorkItem

```xml
<actionCalls>
    <name>Review_Work_Item</name>
    <label>Review Approval Work Item</label>
    <locationX>176</locationX>
    <locationY>386</locationY>
    <actionName>reviewApprovalWorkItem</actionName>
    <actionType>apex</actionType>
    <inputParameters>
        <name>approvalWorkItemId</name>
        <value><elementReference>workItemId</elementReference></value>
    </inputParameters>
    <inputParameters>
        <name>approvalDecision</name>
        <value><stringValue>approve</stringValue></value>
    </inputParameters>
    <inputParameters>
        <name>channelType</name>
        <value><stringValue>InvocableAction</stringValue></value>
    </inputParameters>
    <inputParameters>
        <name>comments</name>
        <value><elementReference>approverComments</elementReference></value>
    </inputParameters>
</actionCalls>
```

### overrideApprovalWorkItem

```xml
<actionCalls>
    <name>Override_Work_Item</name>
    <label>Override Approval Work Item</label>
    <actionName>overrideApprovalWorkItem</actionName>
    <actionType>apex</actionType>
    <inputParameters>
        <name>approvalWorkItemId</name>
        <value><elementReference>workItemId</elementReference></value>
    </inputParameters>
    <inputParameters>
        <name>approvalDecision</name>
        <value><stringValue>approve</stringValue></value>
    </inputParameters>
    <inputParameters>
        <name>comments</name>
        <value><stringValue>Overriding per manager request</stringValue></value>
    </inputParameters>
</actionCalls>
```

### recallApprovalSubmission

```xml
<actionCalls>
    <name>Recall_Submission</name>
    <label>Recall Approval Submission</label>
    <actionName>recallApprovalSubmission</actionName>
    <actionType>apex</actionType>
    <inputParameters>
        <name>approvalSubmissionId</name>
        <value><elementReference>submissionId</elementReference></value>
    </inputParameters>
    <inputParameters>
        <name>comments</name>
        <value><stringValue>Recalled to update pricing</stringValue></value>
    </inputParameters>
</actionCalls>
```

### cancelApprovalSubmission

```xml
<actionCalls>
    <name>Cancel_Submission</name>
    <label>Cancel Approval Submission</label>
    <actionName>cancelApprovalSubmission</actionName>
    <actionType>apex</actionType>
    <inputParameters>
        <name>approvalSubmissionId</name>
        <value><elementReference>submissionId</elementReference></value>
    </inputParameters>
</actionCalls>
```

### reassignApprovalWorkItem

```xml
<actionCalls>
    <name>Reassign_Work_Item</name>
    <label>Reassign Approval Work Item</label>
    <actionName>reassignApprovalWorkItem</actionName>
    <actionType>apex</actionType>
    <inputParameters>
        <name>approvalWorkItemId</name>
        <value><elementReference>workItemId</elementReference></value>
    </inputParameters>
    <inputParameters>
        <name>assigneeId</name>
        <value><elementReference>newAssigneeUserId</elementReference></value>
    </inputParameters>
    <inputParameters>
        <name>comments</name>
        <value><stringValue>Reassigned due to OOO</stringValue></value>
    </inputParameters>
</actionCalls>
```

### getPreviousRelaRecDetails (v66.0 only)

```xml
<actionCalls>
    <name>Get_Previous_Related_Records</name>
    <label>Get Previous Related Record Details</label>
    <actionName>getPreviousRelaRecDetails</actionName>
    <actionType>apex</actionType>
    <inputParameters>
        <name>flowOrchestrationInstanceId</name>
        <value><elementReference>orchInstanceId</elementReference></value>
    </inputParameters>
    <inputParameters>
        <name>stepApiNamesList</name>
        <value><elementReference>stepApiNames</elementReference></value>
    </inputParameters>
    <storeOutputAutomatically>true</storeOutputAutomatically>
</actionCalls>
```

---

## SOQL: Find ApprovalWorkItems for a Quote

```apex
List<ApprovalWorkItem> workItems = [
    SELECT Id, Status, ActorId, Actor.Name,
           IsAutoReviewed, IsEligibleForSmartApproval,
           SmartApprovalBasisWorkItemId
    FROM ApprovalWorkItem
    WHERE TargetObjectId = :quoteId
      AND Status = 'Pending'
    ORDER BY CreatedDate ASC
];
```

---

## SOQL: Find Active ApprovalSubmissions for a Record

```apex
List<ApprovalSubmission> subs = [
    SELECT Id, Status, SubmittedById, SubmittedDate
    FROM ApprovalSubmission
    WHERE TargetObjectId = :quoteId
      AND Status = 'Active'
];
```

---

## Typical Flow: Quote Approval with Recall Support

```
Trigger (Quote field change)
  └─→ Get ApprovalSubmission (SOQL lookup on quoteId)
       └─→ [If active submission exists] recallApprovalSubmission
            └─→ Update Quote fields
                 └─→ Submit for Approval (platform standard or custom)
                      └─→ reviewApprovalWorkItem (from approver screen action)
```

# Pave Operations Reference

Every operation lives at the query root. This file documents the key operations with their input signatures. For the complete list, see the raw schema dump.

---

## Quick Reference: All Operations by Category

### Create Operations
`createAccount`, `createAce`, `createComment`, `createContact`, `createCostCode`, `createCostCodeMapping`, `createCostGroup`, `createCostItem`, `createCostType`, `createCostTypeMapping`, `createCustomField`, `createCustomFieldMapping`, `createDailyLog`, `createDashboard`, `createDataView`, `createDocument`, `createDocumentPayment`, `createDocumentRecipient`, `createDocumentReference`, `createDocumentTemplate`, `createFile`, `createFileTag`, `createJob`, `createLocation`, `createMembership`, `createPayment`, `createPlan`, `createRole`, `createSelectionAssignment`, `createTask`, `createTasksFromBudget`, `createTaskTemplate`, `createTaskType`, `createTaskTypeMapping`, `createTimeEntry`, `createUnit`, `createUnitMapping`, `createUploadRequest`, `createWebForm`, `createWebhook`, `createWorkflow`, `createWorkflowRun`

### Update Operations
`updateAccount`, `updateComment`, `updateCommentFile`, `updateContact`, `updateCostCode`, `updateCostGroup`, `updateCostItem`, `updateCostType`, `updateCustomField`, `updateDailyLog`, `updateDashboard`, `updateDataView`, `updateDocument`, `updateDocumentPayment`, `updateDocumentRecipient`, `updateDocumentTemplate`, `updateFile`, `updateFileTag`, `updateGrant`, `updateJob`, `updateJobArea`, `updateJobContact`, `updateLineItemFile`, `updateLocation`, `updateMembership`, `updatePayment`, `updatePlan`, `updateRole`, `updateSelectionAssignment`, `updateTask`, `updateTaskAssignment`, `updateTaskTemplate`, `updateTaskType`, `updateTimeEntry`, `updateUnit`, `updateUploadRequest`, `updateWebForm`, `updateWorkflow`

### Delete Operations
`deleteAccount`, `deleteAce`, `deleteComment`, `deleteContact`, `deleteCostCode`, `deleteCostCodeMapping`, `deleteCostGroup`, `deleteCostItem`, `deleteCostType`, `deleteCostTypeMapping`, `deleteCustomField`, `deleteCustomFieldMapping`, `deleteDailyLog`, `deleteDashboard`, `deleteDataView`, `deleteDocument`, `deleteDocumentPayment`, `deleteDocumentRecipient`, `deleteDocumentReference`, `deleteDocumentTemplate`, `deleteFile`, `deleteFileTag`, `deleteJob`, `deleteJobArea`, `deleteLocation`, `deletePayment`, `deletePlan`, `deleteRole`, `deleteSelectionAssignment`, `deleteTask`, `deleteTaskTemplate`, `deleteTaskType`, `deleteTaskTypeMapping`, `deleteTimeEntry`, `deleteUnit`, `deleteUnitMapping`, `deleteWebForm`, `deleteWebhook`, `deleteWorkflow`

### Other
`can` (permission check), `copyTaskTemplateToTarget`, `notifyTaskAssignees`, `pdf` (generate PDF), `renameFolder`, `sendDocument`, `signQuery`, `submitWebForm`

---

## Key Operations — Detailed Signatures

### createCostItem

Creates a cost item in a job budget, document, org catalog, or cost group.

| Input | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string (max 250) | Item name |
| `costCodeId` | No (nullable) | jobtreadId | |
| `costTypeId` | No (nullable) | jobtreadId | |
| `unitId` | No (nullable) | jobtreadId | |
| `quantity` | No (nullable) | number | |
| `unitCost` | No (nullable) | number | |
| `unitPrice` | No (nullable) | number | |
| `unitCostFormula` | No (nullable) | string | References job parameters |
| `unitPriceFormula` | No (nullable) | string | References job parameters |
| `quantityFormula` | No (nullable) | string | References job parameters |
| `description` | No (nullable) | string (max 4096) | |
| **`allowanceType`** | No (nullable) | allowanceType | `cost`, `costAndFee`, or `price` |
| `isTaxable` | No | boolean | Default: true |
| `isEditable` | No | boolean | Default: false |
| `isSelected` | No | boolean | Default: false |
| `isSpecification` | No | boolean | Default: false |
| `hasFinalActualCost` | No | boolean | Default: false |
| `requireSpecificationApproval` | No | boolean | Default: true |
| `showDescription` | No | boolean | Default: true |
| `showQuantity` | No | boolean | Default: true |
| `jobArea` | No (nullable) | string | |
| `jobCostItemId` | No (nullable) | jobtreadId | Link to job-level cost item |
| `organizationCostItemId` | No (nullable) | jobtreadId | Link to org catalog item |
| `sourceCostItemId` | No (nullable) | jobtreadId | Source item reference |
| `globalId` | No (nullable) | string (max 100) | External system ID |
| `customFieldValues` | No (nullable) | object | `{ fieldId: value }` |
| `files` | No | array (max 10) | Attachments |

**Placement (one of these):**
| Input | Type | Notes |
|---|---|---|
| `jobId` | nullable jobtreadId | Add to job budget |
| `documentId` | nullable jobtreadId | Add to document |
| `organizationId` | nullable jobtreadId | Add to org catalog |
| `costGroupId` | nullable jobtreadId | Add inside a cost group |
| `positionAfter` | nullable object | `{ type: "costGroup"/"costItem", id: "..." }` |

Returns: `createdCostItem` with basic fields.

---

### updateCostItem

Updates an existing cost item. Every field except `id` is optional.

| Input | Required | Type | Notes |
|---|---|---|---|
| `id` | Yes | jobtreadId | Cost item to update |
| `name` | No | string (max 250) | |
| `costCodeId` | No | jobtreadId | |
| `costTypeId` | No | jobtreadId | |
| `unitId` | No (nullable) | jobtreadId | |
| `quantity` | No (nullable) | number | |
| `unitCost` | No (nullable) | number | |
| `unitPrice` | No (nullable) | number | |
| `unitCostFormula` | No (nullable) | string | |
| `unitPriceFormula` | No (nullable) | string | |
| `quantityFormula` | No (nullable) | string | |
| `description` | No (nullable) | string (max 4096) | |
| **`allowanceType`** | No (nullable) | allowanceType | `cost`, `costAndFee`, `price`, or null to clear |
| `isTaxable` | No | boolean | |
| `isEditable` | No | boolean | |
| `isSelected` | No | boolean | |
| `isSpecification` | No | boolean | |
| `hasFinalActualCost` | No | boolean | |
| `requireSpecificationApproval` | No | boolean | |
| `showDescription` | No | boolean | |
| `showQuantity` | No | boolean | |
| `jobArea` | No (nullable) | string | |
| `jobCostItemId` | No | jobtreadId | |
| `organizationCostItemId` | No (nullable) | jobtreadId | |
| `sourceCostItemId` | No (nullable) | jobtreadId | |
| `globalId` | No (nullable) | string | |
| `customFieldValues` | No | object | |
| `files` | No | array (max 10) | |
| `costGroupId` | No (nullable) | jobtreadId | Move to different group |
| `positionAfter` | No (nullable) | object | Reposition |

Returns: empty `{}`.

---

### createCostGroup

Creates a cost group (budget section/folder). Can contain nested groups and cost items via the `lineItems` array.

| Input | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string (max 250) | Group name |
| `description` | No (nullable) | string (max 4096) | |
| `quantity` | No (nullable) | number | |
| `quantityFormula` | No (nullable) | string | |
| `unitId` | No (nullable) | jobtreadId | |
| `isSelected` | No | boolean | Default: false |
| `isSimpleSelection` | No | boolean | Default: false |
| `showChildren` | No | boolean | Default: true |
| `showChildCosts` | No | boolean | Default: true |
| `showChildDeltas` | No | boolean | Default: false |
| `showDescription` | No | boolean | Default: true |
| `minSelectionsRequired` | No (nullable) | int (≥0) | |
| `maxSelectionsAllowed` | No (nullable) | int (≥1) | |
| `lineItems` | No | array (max 1500) | Nested groups/items (recursive) |
| `files` | No | array (max 10) | |

**Placement:** `jobId`, `documentId`, `organizationId`, `parentCostGroupId`, `positionAfter`

**lineItems entries** can be: `newCostItem`, `newCostGroup`, `existingCostItem`, or `existingCostGroup` — distinguished by `_type` field.

---

### updateCostGroup

Same optional fields as create, plus `id` (required). Also accepts `lineItems` to restructure children. Returns empty `{}`.

---

### createJob

| Input | Required | Type | Notes |
|---|---|---|---|
| `locationId` | Yes | jobtreadId | Must create location first |
| `name` | No (nullable) | string (max 30) | |
| `number` | No (nullable) | jobNumber (max 16) | Auto-generated if omitted |
| `description` | No (nullable) | string (max 32768) | |
| `parameters` | No (nullable) | parameters array | Job parameters for formulas |
| `priceType` | No (nullable) | `fixed` or `costPlus` | Default: `fixed` |
| `areas` | No | string array | Default: `["General"]` |
| `closedOn` | No (nullable) | date | |
| `customFieldValues` | No (nullable) | object | `{ fieldId: value }` |
| `lineItems` | No | array (max 1500) | Initial budget |
| `copyCostsFromJobId` | No (nullable) | jobtreadId | Copy budget from another job |
| `copyTasksFromJobId` | No (nullable) | jobtreadId | Copy tasks from another job |
| `scheduleIsPublished` | No | boolean | |
| `useSimpleSelections` | No (nullable) | boolean | |

---

### createDocument

| Input | Required | Type | Notes |
|---|---|---|---|
| `jobId` | Yes | jobtreadId | |
| `type` | Yes | documentType | `customerOrder`, `customerInvoice`, `vendorOrder`, `vendorBill`, `bidRequest` |
| `name` | No | string (max 128) | Document title |
| `accountId` | No (nullable) | jobtreadId | Required for vendor docs, auto-detected for customer |
| `documentTemplateId` | No | jobtreadId | Provides branding, settings |
| `lineItems` | No | array (max 1500) | Cost items for the doc |
| `description` | No (nullable) | string (max 32768) | Header text |
| `footer` | No (nullable) | string (max 65536) | |
| `issueDate` | No (nullable) | date | |
| `dueDate` | No (nullable) | date | |
| `taxRate` | No | number (0-1) | |
| `requireSignature` | No | boolean | Default: false |
| `allowPartialPayments` | No | boolean | Default: false |
| `includeInBudget` | No | boolean | Default: true |
| `showQuantity` | No | boolean | Default: true |
| `showChildCosts` | No | boolean | Default: true |
| `showProfit` | No | boolean | Default: false |
| `showProgress` | No | boolean | Default: false |

---

### createAccount

| Input | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string | |
| `type` | Yes | accountType | `customer` or `vendor` |
| `organizationId` | Yes | jobtreadId | |
| `isTaxable` | No | boolean | Default: true |
| `customFieldValues` | No (nullable) | object | `{ fieldId: value }` |
| `notify` | No | boolean | Default: true |
| `suffixIfNecessary` | No | boolean | Append number to keep name unique. Default: false |

> **GOTCHA:** In practice, `createAccount` may not accept `customFieldValues` for all field types. If it fails, use `updateAccount` immediately after.

---

### createTask

| Input | Required | Type | Notes |
|---|---|---|---|
| `name` | Yes | string | |
| `targetId` | No (nullable) | jobtreadId | Job, account, or org ID |
| `targetType` | No (nullable) | `job`, `account`, `organization`, `taskTemplate` | |
| `isToDo` | No | boolean | Default: true. `true` = checklist, `false` = calendar. |
| `isGroup` | No | boolean | Default: false. Creates folder/header. |
| `description` | No (nullable) | string (max 4096) | |
| `startDate` | No (nullable) | date | |
| `endDate` | No (nullable) | date | |
| `startTime` | No (nullable) | time | |
| `endTime` | No (nullable) | time | |
| `progress` | No (nullable) | number (0-1) | |
| `assignees` | No | array (max 20) | `{ role: { roleId } }`, `{ membership: { membershipId } }`, or `{ user: { emailAddress, name } }` |
| `notify` | No | boolean | Default: true |
| `subtasks` | No | array (max 50) | `{ name, isComplete }` |
| `parentTaskId` | No (nullable) | jobtreadId | Nest under another task |
| `recurrenceRule` | No (nullable) | string | iCal RRULE format |

---

### createTimeEntry

| Input | Required | Type | Notes |
|---|---|---|---|
| `startedAt` | No (nullable) | datetime | ISO 8601 with timezone |
| `endedAt` | No (nullable) | datetime | ISO 8601 with timezone |
| `type` | Yes | string | `work`, `travel`, `break`, etc. |
| `jobId` | No (nullable) | jobtreadId | |
| `userId` | No (nullable) | jobtreadId | |
| `organizationId` | No (nullable) | jobtreadId | |
| `costItemId` | No (nullable) | jobtreadId | Link to budget line item |
| `notes` | No (nullable) | string | |
| `isApproved` | No | boolean | Default: false |

---

### createPayment

| Input | Required | Type | Notes |
|---|---|---|---|
| `amount` | Yes | number (>0, 2 decimal places) | |
| `paidAt` | Yes | datetime | |
| `type` | Yes | `credit` or `debit` | |
| `organizationId` | Yes | jobtreadId | |
| `accountId` | No (nullable) | string | |
| `description` | No (nullable) | string | |
| `source` | No (nullable) | string (max 100) | |
| `externalId` | No (nullable) | string (max 128) | |
| `attemptAutoMatch` | No | boolean | Default: false |

---

### createDailyLog

| Input | Required | Type | Notes |
|---|---|---|---|
| `jobId` | Yes | jobtreadId | |
| `date` | Yes | date | |
| `notes` | No (nullable) | string (max 10000) | |
| `customFieldValues` | No (nullable) | object | |
| `files` | No | array (max 100) | |
| `notify` | No | boolean | Default: true |

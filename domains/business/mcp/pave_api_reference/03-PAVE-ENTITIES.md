# Pave Entity Types

Every entity in JobTread with its readable fields. This is the "data dictionary" — what you can query for on each record type.

---

## Core Business Entities

### costItem

The fundamental unit of budgeting. Represents a line item in a job budget, document, or org catalog.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `description` | nullable string (max 4096) | |
| **`allowanceType`** | nullable allowanceType | `cost`, `costAndFee`, `price`, or null |
| `cost` | number | Total cost (qty × unitCost) |
| `price` | number | Total price (qty × unitPrice) |
| `priceWithTax` | number | |
| `quantity` | nullable number | |
| `quantityFormula` | nullable string | |
| `unitCost` | nullable number | |
| `unitCostFormula` | nullable string | |
| `unitPrice` | nullable number | |
| `unitPriceFormula` | nullable string | |
| `isTaxable` | boolean | |
| `isEditable` | boolean | |
| `isSelected` | boolean | |
| `isSpecification` | boolean | |
| `hasFinalActualCost` | boolean | |
| `requireSpecificationApproval` | boolean | |
| `showDescription` | boolean | |
| `showQuantity` | boolean | |
| `jobArea` | nullable string | |
| `globalId` | nullable string | |
| `position` | nullable string | Sort position (do not trim) |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `costCode` | costCode | |
| `costType` | costType | |
| `unit` | nullable unit | |
| `costGroup` | nullable costGroup | Parent group |
| `job` | nullable job | |
| `document` | nullable document | |
| `organization` | organization | |
| `jobCostItem` | nullable costItem | Link to job-level item |
| `organizationCostItem` | nullable costItem | Link to org catalog item |
| `sourceCostItem` | nullable costItem | |
| `customFieldValues` | paginated customFieldValue | |
| `documentCostItems` | paginated costItem | Items on documents |
| `jobCostItems` | paginated costItem | |
| `files` | paginated lineItemFile | |
| `timeEntries` | paginated timeEntry | |

---

### costGroup

Budget section/folder. Can contain cost items and nested cost groups.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `description` | nullable string (max 4096) | |
| `quantity` | nullable number | |
| `quantityFormula` | nullable string | |
| `isSelected` | boolean | |
| `isSimpleSelection` | boolean | |
| `showChildren` | boolean | |
| `showChildCosts` | boolean | |
| `showChildDeltas` | boolean | |
| `showDescription` | boolean | |
| `maxSelectionsAllowed` | nullable int | |
| `minSelectionsRequired` | nullable int | |
| `position` | nullable string | |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `unit` | nullable unit | |
| `job` | nullable job | |
| `document` | nullable document | |
| `organization` | organization | |
| `parentCostGroup` | nullable costGroup | |
| `descendentCostGroups` | paginated costGroup | |
| `descendentCostItems` | paginated costItem | |
| `files` | paginated lineItemFile | |

---

### job

A project/job record.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `number` | string | Human-readable job number |
| `description` | nullable string | |
| `closedOn` | nullable date | |
| `priceType` | nullable jobPriceType | `fixed` or `costPlus` |
| `defaultRetainagePercentage` | number | |
| `scheduleIsPublished` | boolean | |
| `useSimpleSelections` | boolean | |
| `lineItemsUpdatedAt` | nullable datetime | |
| `areas` | string array | Budget areas |
| `folders` | string array | File folders |
| `parameters` | nullable array | Job parameters for formulas |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `location` | location | Job site |
| `organization` | organization | |
| `costGroups` | paginated costGroup | Budget groups |
| `costItems` | paginated costItem | Budget items |
| `documents` | paginated document | |
| `tasks` | paginated task | |
| `dailyLogs` | paginated dailyLog | |
| `timeEntries` | paginated timeEntry | |
| `comments` | paginated comment | |
| `files` | paginated file | |
| `events` | paginated event | Activity log |
| `customFieldValues` | paginated customFieldValue | |
| `plans` | paginated plan | Uploaded plan drawings |
| `selectionAssignments` | paginated selectionAssignment | |
| `startTask` | nullable task | |
| `endTask` | nullable task | |
| `taskSummary` | object | Roll-up: dates, progress, counts |
| **Computed:** | | |
| `actualCost` | nullable number | Input: `documentEndDate`, `timeEntryEndAt` |
| `projectedCost` | nullable number | |
| `projectedPrice` | nullable number | |
| `projectedPriceWithTax` | nullable number | |
| `coverPhotoUrl` | nullable url | |
| `calendar` | nullable object | |

---

### document

An estimate, invoice, PO, bill, or bid request.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `fullName` | string | Includes number prefix |
| `number` | int | Sequential document number |
| `type` | documentType | `customerOrder`, `customerInvoice`, `vendorOrder`, `vendorBill`, `bidRequest` |
| `status` | documentStatus | `draft`, `pending`, `approved`, `denied` |
| `cost` | number | |
| `price` | number | |
| `priceWithTax` | number | |
| `tax` | number | |
| `taxRate` | number | |
| `taxName` | nullable string | |
| `balance` | number | |
| `amountPaid` | number | |
| `issueDate` | nullable date | |
| `dueDate` | nullable date | |
| `description` | nullable string | Header text |
| `footer` | nullable string | |
| `subject` | nullable string | |
| `emailMessage` | nullable string | |
| `includeInBudget` | boolean | |
| `requireSignature` | boolean | |
| `allowPartialPayments` | boolean | |
| `signedAt` | nullable datetime | |
| `closedAt` | nullable datetime | |
| `closeMessage` | nullable string | |
| `createdAt` | datetime | |
| **Allowance fields:** | | |
| `allowanceCostItem` | nullable costItem | The allowance line item |
| `allowanceDeductionCostItem` | nullable costItem | The deduction line item |
| **Relationships:** | | |
| `job` | job | |
| `account` | account | |
| `organization` | organization | |
| `costGroups` | paginated costGroup | |
| `costItems` | paginated costItem | |
| `documentPayments` | paginated documentPayment | |
| `documentRecipients` | paginated documentRecipient | |
| `comments` | paginated comment | |
| `files` | paginated file | |
| `events` | paginated event | |
| `scheduledDocuments` | paginated scheduledDocument | |
| `task` | nullable task | Linked task |
| `signedByUser` | nullable user | |
| `closedByUser` | nullable user | |
| `sourceOrganization` | nullable organization | For vendor-to-vendor docs |

---

### account

A customer or vendor.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `type` | accountType | `customer` or `vendor` |
| `isTaxable` | boolean | |
| `archivedAt` | nullable datetime | |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `organization` | organization | |
| `primaryContact` | nullable contact | |
| `primaryLocation` | nullable location | |
| `contacts` | paginated contact | |
| `locations` | paginated location | |
| `jobs` | paginated job | |
| `documents` | paginated document | |
| `tasks` | paginated task | |
| `comments` | paginated comment | |
| `files` | paginated file | |
| `customFieldValues` | paginated customFieldValue | |

---

### location

A physical address tied to an account.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `address` | nullable string | |
| `street` | nullable string | |
| `city` | nullable string | |
| `state` | nullable string | |
| `postalCode` | nullable string | |
| `county` | nullable string | |
| `country` | nullable string | |
| `formattedAddress` | nullable string | |
| `latitude` | nullable number | |
| `longitude` | nullable number | |
| `taxRate` | nullable number | |
| `customTaxRate` | nullable number | |
| `timeZone` | nullable timeZone | |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `account` | account | |
| `contact` | nullable contact | |
| `jobs` | paginated job | |
| `customFieldValues` | paginated customFieldValue | |
| `files` | paginated file | |

---

### task

A to-do item or scheduled task.

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `name` | string | |
| `description` | nullable string | |
| `isToDo` | boolean | true = checklist, false = calendar |
| `isGroup` | boolean | Folder/header task |
| `progress` | nullable number | 0-1 |
| `startDate` | nullable date | |
| `endDate` | nullable date | |
| `startTime` | nullable time | |
| `endTime` | nullable time | |
| `startsAt` | nullable datetime | |
| `endsAt` | nullable datetime | |
| `baselineStartDate/Time` | nullable date/time | |
| `baselineEndDate/Time` | nullable date/time | |
| `position` | string | |
| `targetType` | taskTargetType | `job`, `account`, `organization`, `taskTemplate` |
| `completed` | int | |
| `started` | int | |
| `unstarted` | int | |
| `recurrenceRule` | nullable string | |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `job` | nullable job | |
| `account` | nullable account | |
| `organization` | organization | |
| `parentTask` | nullable task | |
| `childTasks` | paginated task | |
| `taskAssignments` | paginated taskAssignment | |
| `assignedMemberships` | paginated membership | |
| `taskDependencies` | paginated taskDependency | |
| `dependsOnTasks` | paginated task | |
| `dependentTasks` | paginated task | |
| `taskType` | nullable taskType | |
| `taskTemplate` | nullable taskTemplate | |
| `subtasks` | subtask array | `{ name, isComplete }` |
| `comments` | paginated comment | |
| `files` | paginated file | |
| `documents` | paginated document | |
| `location` | nullable location | |

---

### timeEntry

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `startedAt` | datetime | |
| `endedAt` | nullable datetime | |
| `minutes` | int | |
| `hourlyRate` | number | |
| `cost` | number | |
| `type` | string | |
| `notes` | nullable string | |
| `isApproved` | boolean | |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `user` | user | |
| `job` | nullable job | |
| `organization` | organization | |
| `costItem` | nullable costItem | |
| `comments` | paginated comment | |
| `referencedDocuments` | paginated document | |
| `startCoordinates` | nullable coordinates | |
| `endCoordinates` | nullable coordinates | |

---

### dailyLog

| Field | Type | Notes |
|---|---|---|
| `id` | jobtreadId | |
| `date` | date | |
| `notes` | nullable string (max 10000) | |
| `weatherCondition` | nullable weatherCondition | |
| `minTemperature` | nullable number | |
| `maxTemperature` | nullable number | |
| `windSpeed` | nullable number | |
| `rainfallAmount` | nullable number | |
| `snowfallAmount` | nullable number | |
| `createdAt` | datetime | |
| **Relationships:** | | |
| `job` | job | |
| `user` | user | |
| `organization` | organization | |
| `comments` | paginated comment | |
| `files` | paginated file | |
| `customFieldValues` | paginated customFieldValue | |

---

## Supporting Entities

### costCode
`id`, `name`, `number` (nullable), `fullName`, `isActive`, `parentCostCode` (nullable), `organization`, `createdAt`

### costType
`id`, `name`, `isActive`, `isTaxable`, `isTimeTrackable`, `margin` (nullable number <1), `organization`, `createdAt`

### unit
`id`, `name`, `isActive`, `organization`, `createdAt`

### contact
`id`, `firstName`, `lastName`, `name`, `title`, `account`, `locations` (paginated), `customFieldValues`, `files`, `createdAt`

### comment
`id`, `message` (max 4096), `name` (nullable, max 128), `isPinned`, `isFromEmail`, visibility flags, `createdByUser`, `parentComment`, `rootComment`, `replies` (paginated), `files` (commentFile), `targetType`, `createdAt`

### file
`id`, `name`, `type`, `size`, `folder`, `description`, `url` (with size/download options), `storageId`, `createdByUser`, `fileTags` (paginated), `annotations`, `createdAt`. Linked to: `job`, `account`, `document`, `dailyLog`, `task`, `location`, `contact`.

### payment
`id`, `amount`, `type` (credit/debit), `paidAt`, `description`, `source`, `externalId`, `amountApplied`, `amountUnapplied`, `account`, `organization`, `documentPayments` (paginated), `createdAt`

### customField
`id`, `name`, `type` (customFieldType), `targetType`, `options` (nullable string array), `defaultValue`, `minValuesRequired`, `maxValuesAllowed`, `showOnSpecifications`, `position`, `organization`, `createdAt`

### customFieldValue
`id`, `customField`, `value` (dynamic), typed value fields: `booleanValue`, `dateValue`, `datetimeValue`, `numberValue`, `timeValue`. Linked to: `job`, `account`, `contact`, `costItem`, `location`.

### workflow
`id`, `name`, `isActive`, `triggerTypeId`, `triggerInput`, `actions` (array), `customTriggerFields`, `nextRunAt`, `url`, `organization`, `createdAt`

### webhook
`id`, `url`, `eventTypes` (array), `error` (nullable), `organization`, `createdAt`

### membership
`id`, `user`, `organization`, `role`, `account`, `accountType`, `isInternal`, `contact`, `lastActiveAt`, notification subscriptions, default data views, time entry settings, `createdAt`

### role
`id`, `name`, `type` (customer/internal/vendor), `permissions` (array), visibility defaults, default data views, `organization`, `createdAt`

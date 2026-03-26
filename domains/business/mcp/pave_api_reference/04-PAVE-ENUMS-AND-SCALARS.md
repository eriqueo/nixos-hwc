# Pave Enums & Scalar Types

---

## Enums (Pick-One Lists)

### allowanceType
`cost` | `costAndFee` | `price`

Used on `costItem.allowanceType`. Controls how the allowance amount flows through estimates and invoices.

### accountType
`customer` | `vendor`

### documentType
`bidRequest` | `customerInvoice` | `customerOrder` | `vendorBill` | `vendorOrder`

- `customerOrder` = Estimate/Proposal
- `customerInvoice` = Invoice
- `vendorOrder` = Purchase Order
- `vendorBill` = Bill (receipt from vendor)
- `bidRequest` = Bid Request to vendor

### documentStatus
`draft` | `pending` | `approved` | `denied`

### jobStatus
`created` | `pending` | `approved` | `paid` | `closed`

### jobPriceType
`fixed` | `costPlus`

### taskTargetType
`job` | `account` | `organization` | `taskTemplate`

### roleType
`customer` | `internal` | `vendor`

### paymentType
`credit` | `debit`

- `credit` = customer pays you
- `debit` = you pay vendor

### paymentMethod
`ach` | `card`

### costTrackingType
`costCode` | `costItem`

### customFieldType
`address` | `boolean` | `date` | `datetime` | `emailAddress` | `number` | `option` | `phoneNumber` | `text` | `time` | `url`

### customFieldTargetType
`costItem` | `customer` | `customerContact` | `dailyLog` | `job` | `location` | `vendor` | `vendorContact`

### fileTargetType
`dailyLog` | `document` | `task` | `job` | `location` | `contact` | `account` | `organization`

### aceTargetType
`comment` | `dailyLog` | `file` | `fileTag` | `document` | `job` | `location` | `account`

### commentTargetType
`file` | `dailyLog` | `timeEntry` | `task` | `document` | `job` | `account` | `organization`

### dashboardType
`organization`

### dataViewType
`costItem` | `costGroup` | `customer` | `dailyLog` | `document` | `event` | `job` | `jobBudget` | `location` | `membership` | `organization` | `payment` | `task` | `timeEntry` | `user` | `vendor` | `visitor`

### weatherCondition
`blizzard` | `blowingDust` | `blowingSnow` | `breezy` | `clear` | `cloudy` | `drizzle` | `flurries` | `foggy` | `freezingDrizzle` | `freezingRain` | `frigid` | `hail` | `haze` | `heavyRain` | `heavySnow` | `hot` | `hurricane` | `isolatedThunderstorms` | `mostlyClear` | `mostlyCloudy` | `partlyCloudy` | `rain` | `scatteredThunderstorms` | `sleet` | `smoky` | `snow` | `strongStorms` | `sunFlurries` | `sunShowers` | `thunderstorms` | `tropicalStorm` | `windy` | `wintryMix`

### permission
`all` | `createDailyLogs` | `createTimeEntries` | `createVendorBills` | `draftBidRequests` | `draftCustomerInvoices` | `draftCustomerOrders` | `draftVendorOrders` | `exportDocuments` | `exportJobs` | `readAccountTasks` | `readBidRequests` | `readCatalog` | `readCatalogCosts` | `readCatalogPrices` | `readComments` | `readCustomerInvoices` | `readCustomerOrders` | `readCustomers` | `readDailyLogs` | `readFiles` | `readJobBudgets` | `readJobFinancialSummaries` | `readJobs` | `readJobSpecifications` | `readJobTasks` | `readLocations` | `readTimeEntries` | `readVendorBills` | `readVendorOrders` | `readVendors` | `updateAccountTasks` | `updateBidRequests` | `updateCatalog` | `updateCustomerInvoices` | `updateCustomerOrders` | `updateCustomers` | `updateJobs` | `updateJobTasks` | `updateLocations` | `updateTimeEntries` | `updateVendorBills` | `updateVendorOrders` | `updateVendors` | ... (many more)

### eventType
`accountCreated` | `accountDeleted` | `accountUpdated` | `commentCreated` | `commentDeleted` | `commentUpdated` | `contactCreated` | `contactDeleted` | `contactUpdated` | `dailyLogCreated` | `dailyLogDeleted` | `dailyLogUpdated` | `documentCreated` | `documentDeleted` | `documentPaymentCreated` | `documentPaymentDeleted` | `documentPaymentUpdated` | `documentRecipientCreated` | `documentRecipientDeleted` | `documentRecipientUpdated` | `documentSent` | `documentUpdated` | `fileCreated` | `fileUpdated` | `fileDeleted` | `jobCreated` | `jobDeleted` | `jobUpdated` | `locationCreated` | `locationDeleted` | `locationUpdated` | `paymentCreated` | `paymentDeleted` | `paymentUpdated` | `taskCreated` | `taskDeleted` | `taskUpdated` | `timeEntryCreated` | `timeEntryDeleted` | `timeEntryUpdated`

---

## Scalar Types

| Type | Description | Validation |
|---|---|---|
| `string` | Text | `maxLength` (default 1024), `minLength`, `trim` (default true), `collapseSpace` |
| `number` | Decimal number | `gt`, `gte`, `lt`, `lte`, `places` (decimal places) |
| `int` | Integer | `gt`, `gte`, `lt`, `lte` |
| `boolean` | `true` or `false` | |
| `date` | Date only | ISO format: `2026-03-26` |
| `datetime` | Date + time | ISO 8601: `2026-03-26T14:30:00-07:00` |
| `time` | Time only | `HH:MM:SS` |
| `duration` | Duration string | ISO 8601 duration format |
| `jobtreadId` | String UUID | JT's internal ID format: `22PU9Q8DpCmq` |
| `jobNumber` | String (max 16) | Human-readable job number |
| `emailAddress` | Email string | Validated format |
| `phoneNumber` | Phone string | E.164 format |
| `url` | URL string | |
| `color` | Hex color | `#rrggbb` format, e.g. `#123abc` |
| `timeZone` | IANA timezone | e.g. `America/Denver`, `UTC` |
| `countryCode` | ISO 3166-1 alpha-2 | `US`, `CA`, `GB`, etc. |
| `currencyCode` | ISO 4217 | `USD`, `CAD`, `EUR`, etc. |
| `languageCode` | ISO 639-1 | `en`, `es`, `fr`, etc. |
| `uuid` | UUID string | |
| `base64url` | Base64url string | |
| `cron` | Cron expression | |
| `recurrenceRule` | iCal RRULE | |
| `captchaToken` | String | Required for some public operations |
| `query` | Pave query object | Used in `signQuery` |
| `path` | Array of nullable ints | Drawing paths: x/y with null gaps. Values 0-10000, length 2-2000. |
| `expression` | Complex type | Where clause / formula system. See `01-PAVE-FUNDAMENTALS.md`. |
| `coordinates` | Object | `{ latitude: number (-90 to 90), longitude: number (-180 to 180) }` |
| `parameters` | Array (max 1000) | Job parameters: `formula`, `option`, `number`, and measurement types (`area`, `linear`, `count`, etc.) |

---

## The `assignee` Union Type

Used in task assignment, ACE creation, and document recipients. Can be one of:

```json
// Existing role:
{ "role": { "roleId": "ROLE_ID" } }

// Existing membership:
{ "membership": { "membershipId": "MEMBERSHIP_ID" } }

// New or existing user (by email):
{ "user": {
  "emailAddress": "user@example.com",
  "name": "User Name",
  "accountType": "customer",    // nullable
  "phoneNumber": "+14065551234" // nullable
}}
```

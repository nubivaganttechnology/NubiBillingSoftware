# Firestore Staff Salary server rules proposal

**Approval state: draft only. Do not deploy directly.** The repository has no
`firestore.rules` file and `firebase.json` configures only `firestore.indexes`.
The app calls Firestore through the REST API, so deployed Firestore rules remain
the server-side boundary. A read-only Rules API query for the configured default
project `test1-bcebe` found the active `cloud.firestore` release
`projects/test1-bcebe/releases/cloud.firestore`, ruleset
`3c9501fe-b18a-42a9-9b62-6cc32cc6d3f5`, timestamped
`2021-03-06T12:30:01.992858Z`. Its source grants unconditional read and write
access to every document (`allow read, write: if true`). That includes
unauthenticated callers and salary records. This is a critical production
security blocker. No Firestore document data was queried and no rules were
changed. The active open catchall must be replaced as part of a complete,
reviewed policy; adding a narrower salary match cannot override it because
matching Firestore `allow` expressions are combined with OR.

The isolated emulator smoke test used temporary restrictive rules and passed
an owner read plus cross-owner denial. Those test rules are not the deployed
rules and are not a complete production replacement. The Rules proposal below
must be integrated into a complete policy, tested, and separately approved
before deployment.

## Findings from the client/schema audit

- Salary records use the existing employee document ID and include
  `tenantId` (the owner UID), `businessId`, and `employeeId`.
- Rate, outlet-allocation and period writes use the existing REST transaction
  service and SQLite outbox. Khata and financial records are created atomically.
- The app checks salary permissions, but UI and client repository checks do not
  protect Firestore from a modified client. Rules must independently check them.
- Employee documents store `ownerUid`, `uid`, `businessIds`, `outletIds`, and
  `permissionIds`. The proposed self-read check uses those fields. Verify that
  the deployed role-to-permission calculation is copied to `permissionIds` for
  every employee who should see payroll; role documents cannot be safely
  traversed by generic Firestore rules.
- Broad existing `financial_transactions` grants can override a narrower salary
  rule because Firestore combines matching `allow` expressions with OR. The
  current financial transaction match must be amended so ordinary billing roles
  cannot read `SALARY_PAYMENT` or `STAFF_ADVANCE` rows.
- Firestore rules cannot validate the sum of an arbitrary map's values. The app
  stores allocation percentages in basis points and enforces a total of 10,000
  in the atomic repository; server-side validation requires a fixed-size/list
  representation or trusted server function if rules must independently verify
  the arithmetic.
- Phase 2 adds `staff_attendance` records and POS `STORE_PURCHASE` khata entries.
  Attendance reads and writes need separate `ATTENDANCE_MANAGE` and
  `ATTENDANCE_APPROVE` permissions. POS charge-to-khata validates employee
  business/outlet assignment and atomically writes the normal invoice, stock
  movements, and one receivable event. Staff invoice payments create a cash-in
  financial event; authorized salary offsets are non-cash. Rules must authorize
  these linked writes while preventing billing roles from reading salary
  profiles, periods, advances, or salary payments.
- Phase 3 adds immutable `staff_attendance_events` for check-in/out audit
  events. This collection uses the existing generic SQLite document table and
  attendance-scoped REST outbox only; no rule deployment occurred. A complete
  Rules implementation must authorize event creation by an approved kiosk or
  attendance operator, validate employee business/outlet assignment and event
  linkage, and deny event update/delete. Biometric templates, embeddings,
  liveness frames, and consent payloads must never enter this collection.

## Merge-only rules excerpt

This is a rules fragment for review, not a complete ruleset. Insert helper
functions into the existing `service cloud.firestore` block and merge the
collection clauses into existing matches. Do not add parallel permissive
matches.

```firestore
function signedIn() {
  return request.auth != null;
}

function employee(employeeId) {
  return get(/databases/$(database)/documents/employees/$(employeeId)).data;
}

function salaryOwner(data) {
  return signedIn() && request.auth.uid == data.tenantId;
}

function employeeHasSalaryPermission(employeeId, tenantId, businessId, outletId, keys) {
  let e = employee(employeeId);
  return signedIn()
    && e.ownerUid == tenantId
    && e.uid == request.auth.uid
    && e.businessIds.hasAny([businessId])
    && (outletId == null || e.outletIds.hasAny([outletId]))
    && e.permissionIds.hasAny(keys);
}

function mayReadSalary(data) {
  return salaryOwner(data)
    || employeeHasSalaryPermission(data.employeeId, data.tenantId,
      data.businessId, data.get('outletId', null), ['SALARY_VIEW', 'SALARY_REPORT', 'SALARY_MANAGE',
        'SALARY_APPROVE', 'SALARY_PAY']);
}

function mayManageSalary(data) {
  return salaryOwner(data)
    || employeeHasSalaryPermission(data.employeeId, data.tenantId,
      data.businessId, data.get('outletId', null), ['SALARY_MANAGE']);
}

function mayApproveSalary(data) {
  return salaryOwner(data)
    || employeeHasSalaryPermission(data.employeeId, data.tenantId,
      data.businessId, data.get('outletId', null), ['SALARY_APPROVE']);
}

function mayPaySalary(data) {
  return salaryOwner(data)
    || employeeHasSalaryPermission(data.employeeId, data.tenantId,
      data.businessId, data.get('outletId', null), ['SALARY_PAY']);
}

function salaryScopeUnchanged() {
  return request.resource.data.tenantId == resource.data.tenantId
    && request.resource.data.businessId == resource.data.businessId
    && request.resource.data.employeeId == resource.data.employeeId;
}

match /employee_salary_profiles/{recordId} {
  allow get, list: if mayReadSalary(resource.data);
  allow create: if mayManageSalary(request.resource.data)
    && request.resource.data.profileId == recordId;
  allow update: if mayManageSalary(resource.data) && salaryScopeUnchanged();
  allow delete: if false;
}

match /employee_outlet_allocations/{recordId} {
  allow get, list: if mayReadSalary(resource.data);
  allow create: if mayManageSalary(request.resource.data)
    && request.resource.data.allocationId == recordId
    && request.resource.data.allocationTotalBasisPoints == 10000;
  allow update: if mayManageSalary(resource.data) && salaryScopeUnchanged();
  allow delete: if false;
}

match /staff_khata_transactions/{recordId} {
  allow get, list: if mayReadSalary(resource.data);
  allow create: if (request.resource.data.transactionType == 'ADVANCE_ADJUSTMENT'
      ? mayApproveSalary(request.resource.data)
      : mayPaySalary(request.resource.data))
    && request.resource.data.recordId == recordId
    && request.resource.data.status == 'POSTED';
  allow update, delete: if false;
}

match /salary_periods/{recordId} {
  allow get, list: if mayReadSalary(resource.data);
  allow create: if mayApproveSalary(request.resource.data)
    && request.resource.data.periodId == recordId
    && request.resource.data.status == 'APPROVED'
    && request.resource.data.outletBasisPoints is map
    && request.resource.data.outletExpensesPaise is map;
  allow update: if (mayManageSalary(resource.data)
      || mayPaySalary(resource.data) || mayApproveSalary(resource.data))
    && salaryScopeUnchanged()
    && request.resource.data.periodId == recordId;
  allow delete: if false;
}

match /staff_attendance_events/{eventId} {
  allow get, list: if mayReadAttendance(resource.data);
  allow create: if mayManageAttendance(request.resource.data)
    && request.resource.data.eventId == eventId
    && request.resource.data.recordId is string
    && request.resource.data.eventType in ['CHECK_IN', 'CHECK_OUT']
    && request.resource.data.immutable == true;
  allow update, delete: if false;
}
```

`mayReadAttendance` and `mayManageAttendance` are illustrative helper names;
the complete policy must derive them from the authoritative permission and
outlet assignment records. The Phase 3 emulator fixture uses owner-only rules
for its disposable test identities and is not a production authorization
policy.

For the existing `/financial_transactions/{id}` match, add an explicit salary
branch that permits reads and creates only to `salaryOwner` or an authorized
salary payment role, checks `partyType == 'EMPLOYEE'`, the referenced employee,
tenant/business/outlet, positive `amountPaise`, and the `SALARY_PERIOD` or
`STAFF_KHATA` reference. Preserve existing non-payroll branches. A general
billing permission must not satisfy the payroll branch.

## Before approval to deploy

1. Obtain and review the complete deployed ruleset and identify every overlapping
   match for employees, financial transactions, and the four salary collections.
2. Confirm whether employee permission IDs are authoritative and present on
   Firestore employee records, including role-derived permissions.
3. Decide whether temporary employees may have `uid == ''` (the app proposal
   sets `loginEnabled: false`; only owner/managers should access them).
4. Add an independently verifiable 100% allocation representation or trusted
   server validation if rules-level arithmetic enforcement is required.
5. Add emulator tests for owner, salary manager, approver, payroll payer,
   authorized self-read, billing-only employee, cross-business/outlet access,
   create/update/delete, and salary-versus-general-finance visibility.
6. Review composite indexes in `firestore.indexes.json` and run Firebase Rules
   tests in an isolated emulator project.
7. Submit the integrated ruleset and test report for separate approval. No rules
   deployment has been performed.
8. Include `staff_attendance_events` in the attendance access matrix; test
   cross-tenant/outlet reads, unauthorized creation, immutable update/delete
   denials, and linked attendance-record scope.

## Phase 2 rule coverage still required

The emulator fixture and production rules must also test attendance scope and
approval transitions, invalid employee/outlet references, duplicate dates, POS
staff charge batch writes, partial invoice payments and their one cash-in event,
and salary purchase offsets with no cash or expense posting. Staff khata events
should be immutable after creation, and salary-period changes should be limited
to the relevant approver or payer. The currently deployed public catchall makes
all these checks ineffective until a complete replacement is approved and
deployed.

# Staff Salary Khata: SQLite and Firestore REST Verification

**Audit date:** 2026-10-20
**Scope:** Phase 1 client architecture, local persistence, sync, financial posting, authorization boundary, and disposable SQLite compatibility. Deployed Rules metadata was fetched read-only. The end-to-end REST write/read was run only against Firestore/Auth emulators with a disposable SQLite file. No production documents were read or written; no migration, Rules deployment, or Git operation was performed.

## Executive finding

The Staff Salary Khata client uses the established per-account SQLite document store and durable `sync_outbox`; the runtime cloud database transport is Firestore REST over HTTPS, not a Firestore database SDK. I found and fixed a local reporting visibility gap: cached salary periods and staff cash events were included in reports without checking the active user's salary permission. Salary components in detail and audit reports are now included only when `canViewStaffSalary()` is true. A single-outlet employee now receives a 10,000-basis-point allocation when a salary profile is saved without an explicit allocation.

**Critical production blocker: deployed Firestore Rules are fully open.** A read-only Rules API query for the `.firebaserc` default project `test1-bcebe` found the active release `projects/test1-bcebe/releases/cloud.firestore`, ruleset `3c9501fe-b18a-42a9-9b62-6cc32cc6d3f5`, timestamped `2021-03-06T12:30:01.992858Z`. Its complete source is an unconditional `allow read, write: if true` on every document. Anyone, including an unauthenticated caller, can read or alter Firestore documents. Salary confidentiality and all other server-side data isolation are absent in this deployed project. Do not use this deployment for confidential salary data until a complete, reviewed Rules replacement is separately approved and deployed. No document data was queried and no rules were changed.

The isolated emulator round trip passed through the existing authenticated REST client and restrictive emulator-only rules. It proves the client/outbox path can perform a real Firestore REST write/read and that restrictive rules can deny another identity. It does **not** prove the deployed project is secure; production document writes were intentionally not attempted.

## Dependency and direct-access audit

- Searched `pubspec.yaml`, `pubspec.lock`, `.dart_tool/package_config.json`, `lib/`, and `test/` for `cloud_firestore`, `firebase_database`, `FirebaseFirestore.instance`, `FirebaseDatabase.instance`, and `firebase_admin`: no matches.
- `pubspec.yaml` includes SQLite packages (`sqflite`, `sqflite_common`, `sqflite_common_ffi`, and web FFI) and `http`. No Firebase database SDK dependency is present. Authentication is also REST-based through `FirebaseAuthRestService`; it is not a Firebase database SDK.
- Production Firestore access is centralized in `FirestoreRestService` via `ApiClient`. I found no Firestore SDK calls in the salary UI or repository.

## Local entity and operation mapping

`LocalDatabaseTables.tables` maps canonical REST collections to the existing generic local document tables. SQLite stores the full REST document in `payloadJson`; this phase adds no salary-specific SQL schema or columns.

| Salary operation / entity | Firestore collection | SQLite table | Repository operation |
| --- | --- | --- | --- |
| Employee identity (including temporary worker) | `employees` | `local_employees` | `EmployeeRepository.createTemporaryWorker`; existing employee IDs are reused |
| Effective-dated salary rates | `employee_salary_profiles` | `local_employee_salary_profiles` | `StaffSalaryRepository.saveSalaryProfile`, `getSalaryProfiles` |
| Effective-dated outlet weights | `employee_outlet_allocations` | `local_employee_outlet_allocations` | `saveSalaryProfile`, `saveOutletAllocation`; approval reads the effective allocation |
| Earned/approved salary period and accrual snapshot | `salary_periods` | `local_salary_periods` | `approveSalaryPeriod`, `getSalaryPeriods`, `acknowledgeSalaryStatement` |
| Advances, adjustments, payments and passbook | `staff_khata_transactions` | `local_staff_khata_transactions` | `recordAdvance`, `adjustAdvanceAgainstSalary`, `recordSalaryPayment`, `getKhataTransactions` |
| Actual advance/payment cash event | `financial_transactions` | `local_financial_transactions` | Created in the same repository operation as its staff khata event; existing transaction model is reused |
| General non-payroll expenses | `expenses` | `local_expenses` | Existing `ExpenseRepository`; accruals are not duplicated into this collection |

The local schema is generic and is initialized by `LocalDatabase.migrate` / `_createDocumentTable`; current `LocalDatabase.schemaVersion` is 13. Existing common infrastructure tables include `sync_outbox`, `sync_queries`, `sync_conflicts`, and `sync_lease`. No migration was deployed or run against an installed database.

### Salary write/read path

Application wiring in `main.dart` constructs `StaffSalaryRepository(firestore, firestore)`, where `firestore` is the existing `OfflineFirestoreService`. Its `runAtomicOperation` creates a `LocalTransactionContext` inside one SQLite transaction. `SyncOutboxRepository.enqueue` writes each local document and its outbox row using that same executor/transaction. If a write fails, the SQLite transaction rolls back both document and outbox changes. The local result is returned before cloud synchronization.

`StaffSalaryRepository` write methods and their financial effect:

- `saveSalaryProfile`: writes a rate version and, when supplied or when the employee has exactly one assigned outlet, an effective-dated allocation. Allocations are integer basis points and validated to total exactly 10,000.
- `saveOutletAllocation`: writes a complete effective-dated allocation set, rejects nonpositive or non-10,000 totals and overlapping effective intervals.
- `calculate` / `previewPeriodCalculation`: calculate in integer paise; period approval stores an outlet allocation snapshot and the earned amount once.
- `approveSalaryPeriod`: deterministic period ID, employee/business/profile checks, historical effective-date checks, exactly-100% allocation validation, outlet checks, and one approved accrual. It does not create a cash transaction or general expense row.
- `recordAdvance`: deterministic request-derived IDs; atomically creates a khata advance and one `STAFF_ADVANCE` financial cash event.
- `adjustAdvanceAgainstSalary`: updates the protected salary period and creates an immutable non-cash adjustment. It does not create a second financial cash event.
- `recordSalaryPayment`: checks approved remaining payable, supports partial amounts, and atomically updates the period, adds one khata payment, and creates one `SALARY_PAYMENT` financial cash event.
- `acknowledgeSalaryStatement`: adds an employee acknowledgment to the salary-period audit record; repeats are rejected.
- Read methods `getSalaryProfiles`, `getSalaryPeriods`, and `getKhataTransactions` query the `FirestoreDataService` interface, which is the offline wrapper in runtime wiring and reads from local SQLite.

`SyncOutboxRepository` stores one outbox row per document and one `batchId` per original local operation. This means the advance/payment khata record and corresponding finance event are replayed as one REST batch. Stable request/period IDs prevent duplicate user submissions. `financial_transactions` and `staff_khata_transactions` are immutable for updates/deletes in the outbox.

## Authenticated REST transport and sync

- Endpoint base: `https://firestore.googleapis.com/v1/projects/{EnvironmentConfig.projectId}/databases/(default)/documents`, from `FirebaseConstants.firestore` and `FirestoreRestService._documents`.
- Reads use Firestore REST document GETs and `:runQuery` structured queries. Writes use `:commit` with REST-encoded writes and update-time preconditions. `FirestoreRestService.readSyncPage` orders by `updatedAt` and `__name__`, uses a read-time-pinned page, and bounds pages to 200 documents; `SyncEngine` bounds collection pulls to 500 pages.
- Auth source: `AuthRepository.ensureValidSession` refreshes the existing end-user Firebase ID token through `FirebaseAuthRestService` when online. `main.dart` passes that provider to `SyncEngine`; sync requires a nonexpired session whose UID matches the local account. REST methods put the ID token in `Authorization: Bearer …`. No service-account key is used in the client.
- HTTP client maps HTTP 401/403 and network/timeouts into application errors. Auth failure is recorded in sync control; the pending outbox remains. Auth cooldown is one hour, and `SyncEngine.retry()` clears that cooldown so a user can retry after session recovery.
- On REST success only, `_push` marks local document revisions synchronized and removes the confirmed outbox batch in a SQLite transaction. On transient or authorization failure it restores outbox status to `PENDING`; conflicts are retained as `FAILED` plus an audit conflict record. An acknowledgement-lost retry reads the complete batch by stable ID and `_syncMutationId` before reposting.
- Remote pulls are applied by `LocalDataSource.upsertRemote` to SQLite in a transaction before repositories/UI read them. Sync-query cursors are advanced in the same transaction as accepted page data.

The REST client has optional token parameters for generic reads, but salary repository methods require a token and `OfflineFirestoreService._source` verifies its project audience and account identity before selecting the account SQLite file. Sync also rejects missing, expired, or wrong-user sessions. This is client-side validation; it does not replace Firestore Rules. The deployed rules fetched for this audit do not inspect the token at all.

## Offline, finance, and access findings

- Local write plus outbox atomicity is established by code and exercised with disposable SQLite plus a fake REST service.
- Salary expenses are recognized from approved salary-period records for P&L/audit reports, using the outlet allocation snapshot. Cash-flow reports use actual `STAFF_ADVANCE` and `SALARY_PAYMENT` financial events. This prevents payment settlement from recording another salary expense. Advance adjustments are non-cash. Partial payments update actual paid amount and do not mark a period paid until the amount is settled.
- `OfflineFirestoreService.setScope` subscribes to payroll collections only when `salaryAccess` is true and filters an employee's records by their `employeeId` when applicable. Existing non-payroll financial transaction queries omit salary cash event types for users without salary access.
- Fixed locally: Reports detail and complete-audit calls now pass `includeSalaryData: controller.canViewStaffSalary()`. Without this permission they do not read cached payroll-period accruals or staff cash-event details. Single-outlet profiles now default to 100% allocation; multi-outlet workers must save an explicit, complete 100% set before approval.
- The salary UI also checks salary permission. However, client-side visibility and SQLite scope filtering are not server-side security. Cached rows are not deleted when access changes, so server Rules and local account/device protection remain critical. The deployed ruleset was fetched read-only and is an unconditional public read/write grant. `docs/firestore-staff-salary-rules-proposal.md` is a merge-only draft, not deployable or verified Rules.
- SQLite files use the existing project/user-per-account architecture; this audit did not find a database encryption layer in the existing schema path.
- Actual local-emulator REST round trip: passed. The test created throwaway Auth emulator users, created employee and outlet documents through Firestore REST, read them through REST into a disposable SQLite account, staged a salary profile and approved accrual through the production repository/outbox, pushed via `SyncEngine` and the production REST service, read both records through REST, verified amounts and 100% allocation, and confirmed outbox acknowledgment. A second authenticated identity was denied by temporary emulator rules. No production data was touched.
- The emulator rules are an isolated test fixture under `/private/tmp/nubibill_salary_emulator/firestore.rules`; they are not the deployed rules and are not a production-ready replacement. The deployed project's open rules would permit the second identity.

## Dependency and migration compatibility results

- Disposable v12 fixture opened under schema v13. Existing product data and a pending financial outbox row were preserved; the four salary generic document tables were present afterward.
- Disposable close/reopen test verified a salary-period document and pending outbox batch survived reopening the SQLite file.
- No existing production SQLite database was opened or changed. No sync cursor or outbox was reset.

## Tests and verification

Passing targeted checks:

- `flutter test test/staff_salary_repository_test.dart test/staff_salary_sqlite_upgrade_test.dart test/salary_document_service_test.dart test/temporary_employee_model_test.dart test/complete_audit_report_test.dart --reporter expanded` — 13 tests passed (salary arithmetic, allocation, accrual idempotency, advances, partial payments, acknowledgment, migration/reopen, multilingual PDFs, temporary workers, and report integration).
- `flutter test test/offline_sync_test.dart --plain-name 'salary outbox survives REST authorization failure and retries without duplicate posting' --reporter expanded` — passed. A REST authorization failure left both local finance and khata rows pending. On retry, the fake accepted the atomic batch but lost its acknowledgment; the next retry detected the already-applied batch, with only one commit and one record per event.
- Earlier isolated offline sync test `staff advance stays in the SQLite outbox offline and synchronizes once after reconnect` passed; two queued local records synchronized once each through the fake REST implementation.
- `flutter analyze --no-pub` on the changed report, repository, sync, and test files — no errors; 10 informational brace-style lints remain in `staff_salary_repository.dart`.

The two reported timing-sensitive tests were investigated and now pass individually and in the full offline-sync suite. The quota test raced a debounced scope-change pull; its fixture now drains that pull before inducing quota. Production sync also allowed manual pulls to bypass persisted quota cooldown, contrary to the sync design; it now applies quota cooldown consistently, while explicit retry still clears transient failure backoff. The resume test backdated the global pull timestamp but left per-collection freshness timestamps current; its fixture now makes both layers stale. Three other tests also made ordinary sync calls while transient backoff was active; their recovery steps now use the supported explicit retry path. `flutter test test/offline_sync_test.dart --reporter expanded` passed all 36 tests.

Actual Firestore cloud round trip: **not performed**. The REST round trip was against local emulators only. Production Rules metadata was retrieved read-only. Mock REST regression tests do not establish deployed security or production service behavior.

## Server-side Rules proposal and blockers

`docs/firestore-staff-salary-rules-proposal.md` contains a draft merge-only excerpt, but the active deployed rules are an unconditional public read/write grant. A restrictive salary submatch alone cannot fix this: overlapping `allow` grants combine with OR, so the broad catchall must be removed or replaced as part of a complete policy. Before Rules approval/deployment:

1. Replace the active unconditional catchall with a complete least-privilege policy and review every match for `employees`, `financial_transactions`, `expenses`, and salary collections. Firestore `allow` clauses combine with OR, so any remaining broad grant defeats narrower salary restrictions.
2. Verify owner, salary-view/report/manage/approve/pay roles and authorized self-read against real stored employee claims and permissions. Confirm temporary workers with no login are owner/manager-only.
3. Decide a server-verifiable representation for the 100% allocation invariant; Rules do not conveniently sum arbitrary map values. Current client validation is not authoritative against a modified client.
4. Run Firestore Rules Emulator cases for authorized and unauthorized users, cross-employee, cross-business and cross-outlet access, finance-ledger filtering, and create/update/delete restrictions.
5. Review existing indexes for the added salary queries, then request separate approval before any Rules/index deployment or live Firestore verification.

The app does not establish server-enforced salary confidentiality under the currently deployed rules. Emulator coverage proved the profile and salary-period REST flow using test rules, but did not validate every rule required for employee, allocation, khata, and financial-transaction writes in a combined batch. Production use must wait for an approved complete Rules replacement and full emulator authorization matrix.

## Modified source and test files

- `lib/data/repositories/staff_salary_repository.dart` — default single-outlet allocation and allocation-total validation.
- `lib/data/repositories/reports_repository.dart`, `lib/presentation/reports/reports_page.dart` — gate payroll accrual/cash details by salary permission.
- `lib/data/sync/sync_engine.dart` — enforce persisted quota cooldown for manual pulls and preserve quota cooldown on explicit retry.
- `test/staff_salary_repository_test.dart`, `test/staff_salary_sqlite_upgrade_test.dart`, `test/offline_sync_test.dart` — allocation, restart, retry-precondition and authorization-failure coverage.
- `tool/staff_salary_firestore_emulator_smoke.dart`, `test/staff_salary_firestore_emulator_test.dart` — opt-in SQLite/outbox/Firestore REST emulator round trip.
- `docs/firestore-staff-salary-rules-proposal.md` — record the verified deployed Rules exposure and deployment blocker.
- `STAFF_SALARY_SQLITE_FIRESTORE_REST_VERIFICATION.md` — this report.

No Firebase SDK, deployed schema, live Firestore data, production SQLite file, migration state, product catalogue release, or Git history was modified.

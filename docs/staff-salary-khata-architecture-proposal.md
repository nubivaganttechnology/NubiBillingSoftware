# Staff Salary Khata: architecture and schema proposal

## Existing architecture mapped

| Concern | Existing implementation | Compatibility notes |
| --- | --- | --- |
| Employee identity | `EmployeeModel` and `EmployeeRepository` use the canonical `employees` collection and `employeeId`; employee rows carry `ownerUid`, business/outlet assignments, roles, and permissions. | Existing IDs are reused. `createTemporaryWorker` creates a row in the same collection with `loginEnabled: false`, empty auth identity fields, and no Auth provisioning. |
| Business/outlet scope | `AppController.appContext`, `currentOutlet`, and repository arguments scope operations by owner (`tenantId`), business, and outlet. | Payroll profiles can be business-wide with explicit outlet allocations; every attendance, disbursement, and outlet expense posting must identify its business and outlet. |
| Local database | `LocalDatabase` stores Firestore documents as JSON in generic `local_*` tables. `LocalDatabaseTables` maps collection names to tables. Current schema version is 13; document tables are created on open. | Salary collections use the generic table pattern. A disposable v12-to-v13 fixture upgrade preserved a product row and pending outbox row while recreating salary tables. No live DB was opened or changed. |
| Offline writes and sync | `OfflineFirestoreService`, `LocalDataSource`, `FirestoreTransactionService`, `SyncQueryRegistry`, and `SyncOutboxRepository` commit local document writes plus outbox rows transactionally. Stable document IDs and read-set checks support idempotent conflict-aware sync. | All payroll writes must use the existing transaction service and outbox. Never write SQLite or Firestore directly from screens, reset sync cursors, or delete pending outbox rows. New collections also need business/outlet query registration in scope activation. |
| Expenses | `ExpenseModel` and `ExpenseRepository` write `expenses` records with paise, date, payment method, and outlet. Reports read expenses as operational outflows. | This record shape represents a paid expense/outflow; using it for accrued unpaid salary would make reports treat an obligation as cash spent and could count it again at payment. Salary accrual and later cash payment need distinct, linked events. |
| Existing financial events | `FinancialTransactionModel` and `financial_transactions` represent immutable cash movements; supplier refunds create a linked event in the same transaction. Sync protects existing financial event documents from silent remote replacement. | Reuse for actual staff advances and salary disbursements, with `partyType: EMPLOYEE` and stable references. Do not create cash events for non-cash advance adjustments or purchase offsets. |
| POS and inventory | `SalesRepository` posts invoice, payment/customer ledger, inventory deductions, and related records atomically. Invoice currently has no employee/staff receivable identity. | Phase 2 must extend the existing invoice flow for “Charge to Staff Khata”; it must not create a parallel checkout or stock deduction path. |
| Permissions and navigation | `PermissionCatalog`, `PermissionIdMatcher`, and `AppController` enforce app-level module/action permissions. The dashboard routes Expenses and Employees as separate modules; employee management is currently owner-only. | Add the proposed salary and attendance permissions at UI/controller boundaries and backend rules. Expenses > Staff Salary Khata can be an Expenses subview; employee detail needs a route from the Employees register. Owner overview shortcut needs a permission-gated dashboard card. |
| Backend authorization | No Firestore security rules file is checked into this workspace. `firebase.json` configures indexes only. | A merge-only rules draft is in `firestore-staff-salary-rules-proposal.md`. It is not deployable alone; deployed rules and overlapping grants remain to be audited. |
| Reporting | `ReportsRepository` includes approved salary period expense allocations in P&L and includes actual advance/payment finance transactions in cash-flow reports. | Accrual expense is recognized once on approval; later salary disbursement is cash flow only and does not make a second expense. |

## Proposed Phase 1 logical entities

These are logical records mapped to the approved generic offline-first architecture. `tenantId` is the existing owner UID convention. Amounts use integer paise, timestamps use UTC, IDs are stable, and offline metadata is carried by the existing outbox.

| Logical entity | Proposed role and key relationships |
| --- | --- |
| `employee_salary_profiles` | Effective-dated rate versions linked to existing `employeeId`, `businessId`, and one or more outlet allocations. Holds salary type, rate, cycle, payment preference, status, and effective dates. A new version supersedes a prior rate; historical versions remain immutable. |
| `staff_khata_transactions` | Immutable employee passbook entries: advances, approved bonuses/overtime/incentives/deductions, adjustments, and controlled reversals. Include employee/business/outlet, transaction type, amount paise, payment method when cash moved, actor/approver, time, notes/reference, and links to source records. Maintain advance and recoverable/purchase balances separately. |
| `salary_periods` | One employee/business/pay-period approved calculation snapshot, including historical profile reference, approved earnings, deductions, outlet split, actual paid total and advance adjustment total. Draft preview is currently in memory; approved-period changes use auditable adjustment/payment operations. |
| `salary_settlements` | No separate collection is added. A partial/full payment is an immutable `staff_khata_transactions` row linked to its salary period and one `financial_transactions` cash event; stable request-derived IDs prevent replays. |
| `staff_attendance` (Phase 2) | One employee/date/outlet register record, with check-in/out, work units, approval/correction history, status, and source mode. Manual entry first; face recognition remains disabled and outside Phase 1. |
| `staff_biometric_enrollments` (Phase 3) | Deferred. Requires approved privacy/security/legal design, platform capability validation, consent and deletion lifecycle, and a separately validated recognition/liveness solution. Not part of this schema approval. |

### Financial event handling

- Record real cash/UPI/bank advances and salary payments as `financial_transactions`, using `partyType: EMPLOYEE`, linked to the relevant khata/settlement record. Reuse the existing cash event and offline sync path.
- Record non-cash adjustments, salary accruals, and authorized staff-purchase offsets as payroll ledger events only; they must not create cash outflow.
- Salary accrual is kept on the approved salary-period document and read once by P&L using outlet allocations. It is not also written as a paid `expenses` row. The matching salary payment is a cash event only.
- Phase 2 staff purchases remain normal POS invoices and inventory transactions, linked to `employeeId` and a staff receivable; no direct inventory removal.

### Offline mapping and migration approach

1. After approval, add the selected collection constants and mappings in `FirebaseConstants` and `LocalDatabaseTables`; the generic local-document shape can store the records without a bespoke SQL table.
2. Extend scope activation/query registration only for authorized payroll users and the selected business/outlet. Ensure permissions do not activate salary pulls for billing-only roles.
3. Add repository/model methods that transact related documents, financial events, and outbox records atomically. Use stable idempotency keys and append-only reversal records for confirmed financial entries.
4. Add schema version migration only if dedicated indexes or SQL structures are approved. Otherwise rely on the existing generic table creation-on-open path; do not reset cursors or alter existing pending outbox rows.
5. Before any production deployment, separately review Firestore rules, indexes, data-retention behavior, and a migration/rollback plan. This proposal makes no remote or live database changes.

## Approved decisions and Phase 1 status

The approved design reuses employee IDs, the existing financial transaction stream and generic Firestore/SQLite document sync. Approved salary is recognized as expense when earned and approved. Advances and payments remain separate cash-flow events. Outlet allocations use effective-dated integer basis points and repository validation requires exactly 10,000 (100%); single-outlet UI profiles default to 100%.

Phase 1 code includes effective-dated salary profiles and allocations, monthly/daily calculations, advances and passbook entries, partial salary payments, approved accrual reporting, multilingual PDF salary slips/statements, share-sheet handoff, acknowledgment metadata, and temporary no-login employees. Salary-period acknowledgments are first-write-only. WhatsApp availability depends on the user's installed platform share targets; the app does not claim delivery.

Focused automated tests cover salary arithmetic, allocation totals, advance and payment request replay, partial/full payment balances, acknowledgment immutability, English/Bengali/Hindi PDF generation, offline outbox replay, and disposable SQLite v12-to-v13 compatibility. Phase 2 attendance/POS and Phase 3 biometrics are not started.

No live Firestore rules or data, production SQLite database, or deployed migration has been modified. No commit or push has been made. Rules review and deployment are separate approval items. Firestore Rules cannot sum a variable-size map of allocation weights; if rules must independently enforce the arithmetic total, change the allocation representation or add a trusted backend validator before deployment.

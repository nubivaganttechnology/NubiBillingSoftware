# Staff Salary Khata Phase 2

**State:** Implemented locally; not deployed. The existing per-account SQLite
document store, atomic outbox, and authenticated Firestore REST client remain
the persistence and synchronization path. `staff_attendance` maps to the
generic `local_staff_attendance` table, which is created by the existing
non-destructive table-open path. No production migration was run.

## Attendance and wage integration

- Manual entries support present, absent, half-day, paid/unpaid leave, weekly
  off, and holiday. Entries can include check-in/check-out and are uniquely
  identified per employee, outlet, and date.
- Entries remain pending until approval. Approval validates employee, business,
  and outlet assignments, and records payable units, configured standard shift
  length, half-day units, overtime rate/multiplier, approver, and computed
  overtime in paise. A worked weekly off/holiday requires explicit selection.
- Salary preview imports approved attendance for the selected salary period.
  Daily/shift wages use approved payable units; hourly wages use approved
  working minutes. Approved overtime is included in earned salary. Monthly
  periods show leave records; unpaid-leave deductions require an explicitly
  entered per-day amount and are zero by default. No automatic penalty is
  applied.
- Salary period approval validates attendance status, scope, date, computed
  work units and overtime, snapshots record IDs, and rejects reuse in another
  period.

## POS staff khata and settlement

- The existing Sales invoice repository remains the sole sale and inventory
  posting path. An authorized cashier can select an employee instead of a
  customer. One atomic SQLite/outbox batch writes the usual invoice, inventory
  batch/stock movements, and a stable `STORE_PURCHASE` khata event.
- Staff invoice partial payments update that invoice's outstanding amount and
  payment status, add one immutable payment and khata adjustment, and record one
  incoming `STAFF_PURCHASE_PAYMENT` financial transaction. Request IDs make
  retries idempotent. Sales History exposes the same partial-payment flow to
  authorized Khata cashiers and displays the employee name on the invoice.
- Authorized salary offsets reduce employee receivables and salary payable in
  one transaction. They create no cash event and no additional salary expense.
  Salary payments now account for both advance and purchase offsets when
  validating the remaining payable.

## Access and verification

- `ATTENDANCE_MANAGE`, `ATTENDANCE_APPROVE`, and `STAFF_KHATA_CHARGE` are
  separate permission keys. Attendance collection pulls are registered only
  for attendance or salary-authorized scopes and are filtered by business and
  selected outlet. A cashier can enqueue a staff-purchase event without pulling
  confidential salary transactions.
- Targeted tests cover attendance/overtime, salary attendance snapshots and
  duplicate prevention, duplicate staff payment/offset requests, POS stock
  deduction, staff receivable creation, and offline SQLite/outbox persistence.
  Focused attendance, salary, POS posting, and outlet-scoped sync tests passed
  locally. Flutter analysis reports no errors; its output contains existing
  style-only info lints.
- Deployed Firestore Rules currently allow unauthenticated read/write to all
  documents. Client permission checks cannot secure these new Phase 2 writes.
  Production use remains blocked pending a complete Rules replacement and
  emulator authorization matrix; no Rules or database deployment was performed.

## Files

- `lib/data/repositories/staff_attendance_repository.dart`
- `lib/data/repositories/staff_salary_repository.dart`
- `lib/data/repositories/sales_repository.dart`
- `lib/data/services/offline_firestore_service.dart`
- `lib/presentation/staff_salary/staff_attendance_page.dart`
- `lib/presentation/staff_salary/staff_salary_page.dart`
- `lib/presentation/sales/sales_entry_page.dart`
- `lib/presentation/billing/bill_search_page.dart`
- `lib/presentation/app_controller.dart`
- `test/staff_attendance_repository_test.dart`
- `test/staff_salary_repository_test.dart`
- `test/sales_posting_repository_test.dart`
- `test/offline_sync_test.dart`

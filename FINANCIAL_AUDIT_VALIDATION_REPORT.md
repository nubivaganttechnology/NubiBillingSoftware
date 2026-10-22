# Financial reconciliation engine validation and change report

Date: 2026-10-21. This is engineering validation of an automated internal reporting engine, not a professional audit opinion or verification of production accounts.

## Result

Implemented a replacement for the former estimated audit calculations inside the existing `ReportsRepository`. The UI, PDF, Excel and generic report-detail adapter consume the same evidence schedules. Missing accounting amounts are nullable and displayed as **INSUFFICIENT DATA**. Measured inconsistencies produce **NOT RECONCILED**. Neither output is a statutory audit or filing approval.

**84 tests passed across the relevant suites: 34 final financial tests and 50 existing regression tests.** The full-project analyzer is not clean; see the explicit results below. No original business database or live Firestore transaction was modified or used for testing.

## Reference evidence

The original two-page PDF was located on the Desktop at `/Users/sksuman/Desktop/Financial_Audit_Report_suman_enterprises_1792494282687.pdf`. Both pages were rendered and inspected; the original remains unchanged. The root-cause report records page-specific evidence. Its opening/purchase/closing figures imply COGS of INR -7,449,068.64, while it reports INR 4,420.00; the difference is INR 7,453,488.64. This arithmetic is reproduced in a regression test. The original PDF cannot establish the correct replacement amounts without its source transaction history.

The delivered sample is **a disposable test fixture**, visibly labelled on every page. Its INR 6,800 revenue, tax, inventory and other figures come from fabricated test records in isolated SQLite files, not from Suman Enterprises' actual accounts. It must not be mistaken for a regenerated actual business report.

## Implemented behavior

| Area | Result and evidence |
|---|---|
| Source access | Optional `FinancialReportSnapshotReader` implemented by the existing offline service. Existing document tables and scope indexes are used inside a read-only snapshot transaction. Queries, sync checkpoints, outbox entries and conflicts are read without registering a query or changing cursors. |
| Authorization | Authenticated UID/project plus cached active account, active employee assignment, active roles and active permission definitions. Business and outlet membership is enforced before financial reads. Scope options use the same authorization checks. |
| Scope | Selected outlet, selected outlets, all active/historical outlets in one business, and explicitly selected authorized businesses. Historical outlets can be selected directly. Included/excluded outlets and reasons are printed. INR compatibility is enforced; different GST identities retain separate business tax schedules and are not netted as one GST registration. |
| Dates | Inclusive India calendar dates, UTC+05:30, with an exclusive next-day boundary including the final microsecond. Missing transaction dates are exceptions. Post-period invoice edits/cancellations block reliable historical revenue. |
| Sales | Saved net taxable value excludes GST and already includes discount treatment. No second discount deduction. Header/line totals are reconciled. Explicit sales returns reverse once. Internal transfer revenue is excluded, while its persisted GST remains in separate classifications. |
| Purchases | Only approved bills are accounting purchases. Actual `taxableAmount`, `cgstAmount`, `sgstAmount`, `igstAmount`, charges and round-off fields are used. Approved returns need saved taxable credit and tax components. Purchase GST is observed tax, never automatically eligible ITC. |
| Inventory / COGS | Immutable batch history, approved receipt cost and persisted base quantities are checked independently. Purchase quantities in thousandths are normalized by their contract; invoice base quantities are compared to linked batch movements. Negative history, duplicates, orphans, corrections without historical valuation, missing receipt/invoice references, transfer cost gaps and current-stock/batch disagreements are disclosed. No 85% opening-stock or 65% revenue fallback survives. |
| Trading / P&L | Independent batch cost is compared to opening + net purchases + direct inward cost - closing. A difference prevents a clean trading conclusion. Known trading costs remain available when an unrelated operating-rent allocation is missing. Operating, salary and non-operating amounts are separated; unsupported depreciation, income adjustments and final profit before tax remain unavailable. |
| Expenses | Known existing expense categories and explicitly saved classification evidence are used. Ambiguous classifications are disclosed. Business overhead is included once only in a full-business scope and stays visibly unallocated; no arbitrary outlet percentage is invented. Capital/drawings and linked salary accruals are excluded from operating expenses. |
| Payroll | Approved earning periods and historical `outletExpensesPaise` allocations recognize expense once. Cash payments are distinct. Dated settlements determine supported business salary liabilities; expense shares are not reused to invent outlet liability allocations. Advances remain receivables until adjusted. Missing staff/profile/accrual coverage and partial earning periods are not assumed zero. Business payroll aggregates are owner-only; ordinary report access does not disclose individual salaries. |
| Cash | Actual payment/financial/expense/refund records, not invoice.paidPaise percentages. Void events cannot suppress real payments. PAY-SP / FIN-SPAY identities are reconciled so Staff Khata store-purchase repayments are counted once. Salary advances, payroll cash payments and noncash purchase offsets remain distinct. Cancellation of an invoice does not erase an actual receipt. Opening/closing cash is unavailable without supported balances. |
| GST / HSN | Embedded invoice snapshots are used first; authorized linked line records are the fallback, without broad unscoped item scans or duplicate counting. Rate, HSN/SAC, UQC, quantity, taxable value, CGST, SGST, IGST and cess stay visible. Missing rate/classification does not become zero/18%. Intra/interstate conflicts and line/header differences are exceptions. Observed totals are shown, including missing-classification rows. |
| Receivables / payables | Observed current invoice/bill dues and actual date-based age buckets are shown. Internal transfer obligations are excluded from external trade schedules. Current snapshots are not misrepresented as historical as-of balances; receipt allocation gaps and verified MSME status remain NOT_VERIFIED. |
| Balance sheet | Shows supported components separately from missing balances. Fixed assets, depreciation, capital, retained earnings, complete cash/bank and complete opening balances are not invented. Total assets, equity/liabilities and balance difference remain unavailable when evidence is incomplete. |
| Scoring | Ten disclosed criteria total 100 points. Only PASS earns its weight. Missing evidence earns zero; failed numeric reconciliation blocks a clean result. The score describes internal data quality, not statutory or CA certification. |
| Exports | English report headings, existing Noto fonts, A4 pages, repeated headers, explicit scope on every page, page numbers, source evidence, exceptions and limitations. Shared schedules drive screen/PDF/workbook. Native file URIs are handled correctly rather than treating `file://` as a filesystem path. |

## Validation results

| Check | Status | Result |
|---|---|---|
| `flutter test test/complete_audit_report_test.dart --reporter expanded` | **Passed** | 34 tests; isolated SQLite databases; remote access throws immediately. |
| Existing `offline_sync_test.dart`, `staff_salary_repository_test.dart`, `staff_salary_sqlite_upgrade_test.dart`, `salary_document_service_test.dart`, `invoice_print_service_test.dart` | **Passed** | 50 tests, run with concurrency 1. Controlled clients and disposable databases only. |
| Targeted `flutter analyze --no-fatal-infos` on reporting files and financial tests | **Passed with style information** | No errors or warnings. Nonfatal brace-style information remains. |
| Requested full `flutter analyze` | **Failed on existing repository issues** | Last full log: 747 diagnostics, including 527 errors and 27 warnings. Errors are outside this change: OCR plugin subpackage dependency/analysis failures and stale `postSalesInvoice` overrides in `dashboard_navigation_test.dart` and `sales_hub_multilingual_test.dart` missing `chargeToEmployeeId`. No security/configuration changes were made to suppress them. |
| Original PDF inspection | **Passed** | Both original A4 pages rendered and reviewed with PDFKit; complete relevant page text inspected. Poppler is unavailable on this machine. |
| Updated PDF rendering | **Passed** | 16 A4 pages including an added 180-row evidence fixture. Repeated scope/fixture labels and all 180 reference IDs verified. Contact sheets and detailed pages inspected; column widths corrected for reference/status wrapping. No clipped or overlapping content observed. |
| Workbook bytes | **Passed** | The same schedules export successfully to an XLSX workbook; validated in financial tests. |
| Live data / actual account regeneration | **Not run** | No sanitized source database accompanied the reference PDF. The actual corrected business balances are not asserted. |
| Native save/print dialogs and macOS application build | **Not run** | PDF/workbook generation tested; no live account or application launch was used. |
| Full multilingual financial typography | **Not run** | Existing fonts are reused, but Hindi/Bengali shaping has not been independently certified for this report. Financial headings remain English. The existing invoice PDF test passes with its pre-existing font warnings. |
| Complete historical balance sheet / statutory eligibility | **Blocked by missing evidence/contracts** | Requires the records and decisions below; not replaced with estimates. |

Financial tests cover the supplied COGS/trading defect; complete and incomplete GST/HSN; zero sales; missing opening history; negative and zero stock; sales/purchase returns; earning versus cash salary; partial payments/advances/offsets; 60/40 outlet salary snapshots; one/all/selected outlets; historical outlets; combined businesses; access denial; internal transfers; deleted/pending outbox records; limited downloads; byte-for-byte database preservation; and large PDF tables.

Persisted test/analyzer/render logs are under `docs/financial_audit_validation/`. Every report read preservation test compares the local document tables, sync queries, outbox and conflict rows before and after reporting. This demonstrates that the reporting path does not silently repair source transactions.

## Changed files

- `lib/data/repositories/reports_repository.dart`: audit entry point and generic detail adapter; shared authorized scope-options API.
- `lib/data/repositories/financial_reconciliation.dart`: replacement calculations, authorized source joins, reconciliation, evidence and schedules, as part of the existing repository library.
- `lib/data/services/firestore_data_service.dart`: optional read-only snapshot contract.
- `lib/data/services/offline_firestore_service.dart`: implementation using existing SQLite tables, including pending deletions, limited-query coverage and conflicts.
- `lib/domain/reports/audit_report_models.dart`: nullable financial results, scope choices, schedules and transparent validations.
- `lib/domain/reports/report_models.dart`: accurate report labels.
- `lib/presentation/reports/reports_page.dart`: explicit scope picker and removal of unsupported readiness claims.
- `lib/presentation/reports/audit_report_dialog.dart`: shared evidence schedules and incomplete-result display.
- `lib/presentation/reports/report_export_service.dart`: shared A4 PDF/XLSX output, column/pagination fixes, accurate export naming and URI handling.
- `lib/l10n/app_en.arb`, `app_bn.arb`, `app_hi.arb` and generated localization files: removal of automatic audit/certification claims; regenerated with `flutter gen-l10n`.
- `test/complete_audit_report_test.dart`: replaces tests that expected synthetic 44AD/profit values with source-contract and disposable SQLite regressions.
- `FINANCIAL_AUDIT_ROOT_CAUSE_REPORT.md`, this report and `output/pdf/financial_reconciliation_disposable_fixture.pdf`: review and validation deliverables.

Earlier staff-role edits in this conversation were preserved. They are separate from this financial reporting change.

## Remaining evidence and decisions requiring approval

1. **Opening accounting records:** verified opening trial balance, asset/depreciation register, capital/drawings, retained earnings, cash/bank statements and supporting reconciliation. Without these, a complete balance sheet, closing cash and final profit before tax cannot be safely produced. Creating/importing new accounting contracts requires explicit approval; none was deployed.
2. **Historical inventory:** original receipt costs, consistent base units, missing batch movements, revision history for corrections, and linked transfer costs. The operational billing code contains a quantity-threshold scaling heuristic; this report flags incompatible history and does not rewrite it. Any future posting or migration correction needs its own reviewed change and must preserve historical evidence.
3. **Business expense and salary allocations:** an approved allocation policy and persisted snapshots for business-level overhead and outlet salary liabilities; supported accrual splits for partial earning periods. No invented daily proration or expense percentage was added. Optional accounting classifications are consumed only when actually present; unclassified records remain exceptions.
4. **Receivable/payable history and offsets:** complete dated receipt allocations, opening balances, POS links for staff offsets, and an identifiable inter-business/inter-outlet obligation ledger. Unsupported eliminations and historical due balances remain NOT_VERIFIED.
5. **Tax and legal evidence:** original tax snapshots, verified registration/MSME facts and independent GST/ITC/portal/legal review. Cash limits, MSME obligations, invoice continuity and presumptive-tax eligibility are not automatically certified.
6. **Actual account confirmation:** an authorized sanitized, consistent source snapshot is needed to determine the real corrected Suman Enterprises figures. The current sample is exclusively a test fixture.

## Safety record

No live Firestore writes, production SQLite access/modification, employee salary changes, historical transaction edits, schema deployment, migrations to production, outbox clearing, cursor resetting, Firestore rule changes, catalogue release changes, Git commits or pushes were performed. Existing REST synchronization remains in place; no `cloud_firestore` or `firebase_database` dependency was introduced.

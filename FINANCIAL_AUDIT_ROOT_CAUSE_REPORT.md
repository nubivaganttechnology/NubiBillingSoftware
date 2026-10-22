# Financial reconciliation engine: root cause review

Inspected 2026-10-21, before calculation changes. No live database was opened, queried, or modified. The reference PDF was subsequently located at `/Users/sksuman/Desktop/Financial_Audit_Report_suman_enterprises_1792494282687.pdf`. Both original pages were rendered and inspected without modifying the file. Its displayed figures are report evidence, not proof of underlying transactions; validation uses disposable transaction fixtures.

## Entry points and actual storage contracts

- Screen: `lib/presentation/reports/reports_page.dart::_openCompleteAuditDialog`; display: `audit_report_dialog.dart`.
- Calculation: `lib/data/repositories/reports_repository.dart::loadCompleteAuditReport`; detail adapter: `_buildCompleteAuditDetailReport`.
- PDF and workbook: `lib/presentation/reports/report_export_service.dart::generateAuditPdf/exportAuditExcel`.
- Runtime source: `OfflineFirestoreService` implements `FirestoreDataService`. SQLite tables in `LocalDatabaseTables.tables` retain encoded REST documents in `payloadJson`, scope columns, sync status, and revisions. REST synchronization is handled by the existing sync engine; no Firebase database SDK is needed.
- Sales: `invoices`, `invoice_items`, `payments`, `customer_balances`, `customer_ledger_entries`. `BillingRepository` saves header `taxablePaise`, `cgstPaise`, `sgstPaise`, `igstPaise`, grand total after discount, and embedded `items`. Payment documents can lack scope but link to invoice IDs. Invoice item snapshots are also embedded in each invoice; these must not be counted twice.
- Procurement: `purchase_bills`, `purchase_bill_items`, `purchase_returns`, `supplier_payments`, `supplier_refunds`, `supplier_ledger_entries`, `financial_transactions`. Approved purchase fields are `taxableAmount`, `cgstAmount`, `sgstAmount`, `igstAmount`, `chargesAmount`, `outstandingAmount`; money is integer paise.
- Inventory: `stock_balances`, `stock_movements`, `inventory_batches`, `inventory_batch_movements`, `inventory_transactions`, `product_variants`, `product_costs`. Purchase quantities use thousandths; stock service/billing have inconsistent whole-unit/thousandth conventions. `inventory_transactions.unitCost` is historically sometimes a whole line cost. Current stock/variant rates are not historical valuations. Batch movements have immutable IDs, directions, references, and occurredAt, but do not universally save valuation costs.
- Expenses: `expenses`, amountPaise/expenseDate/outletId; null outlet is business-level, not an expense repeated in every outlet. Category alone is not authoritative capital/direct/operating accounting classification.
- Payroll: `salary_periods`, `employee_salary_profiles`, `employee_outlet_allocations`, `staff_khata_transactions`. Approved periods save `expenseAmountPaise` (gross earnings), `netEarnedPaise`, historical `outletExpensesPaise`, and allocation basis points. Advances/payment events have matching financial transaction IDs. Adjustments and purchase offsets are noncash. Mutable period settlement totals cannot establish historical as-of balances without dated events.
- Operational entities: `user`, `employees`, `roles`, `permissions`, `businesses`, `outlets`, `business_settings`. Authorization must precede report data access; active and historical outlets must be considered.
- Sync evidence: `sync_queries` (filters, lastSyncedAt, cursor, lastError), `sync_outbox`, `sync_conflicts`. An empty local query is not proof of synchronized zero activity. Reports must read these without registering queries, clearing outbox entries, or changing cursors.

## Reproduced defects and root causes

| ID | Source behavior before changes | Effect |
|---|---|---|
| AUDIT-001 | Opening stock = closing stock x 0.85; if computed COGS <= 0, replace with sales x 0.65. Stock value = current quantity x current variant purchaseRate with no scale conversion. | Invented opening/COGS; quantity scale and cost scope mismatch. Given INR 42,505,950 + 51,981.36 - 50,007,000 = -7,449,068.64, not reported 4,420. |
| AUDIT-002 | Trading statement uses the invented opening value and unrelated fallback COGS/profit. | Difference INR 7,453,488.64; risk score does not check trading balance. |
| AUDIT-003 | Header tax reads taxPaise/taxAmount instead of saved CGST/SGST/IGST; missing rates default to 18%; header-only fallback synthesizes an 18% bucket. | Wrong tax totals and unsupported classifications. Header grand total is already discounted and includes GST but discount is subtracted again for revenue. |
| AUDIT-004 | Queries invoice_items even though sync does not universally download that collection; ignores embedded snapshots; fallback performs unscoped list/query and swallows errors. HSN quantity is line count and UQC always NOS. | Missing rows, scope exposure risk, incomplete HSN and GST coverage concealed. |
| AUDIT-005 | Ignores nonpositive/malformed expenses; business expenses appear in every outlet; salary is optional without coverage disclosure. | Zero expense can mean missing data; consolidation duplicates overheads. |
| AUDIT-006 | Stock opening/inward/outward = current quantity x 0.9/0.4/0.3. | Item history fabricated; no movements, transfers, batch costing, historical valuations, or quantity reconciliation. |
| AUDIT-007 | Automatic statutory opinion, system certification, filing readiness, and 44AD eligibility based only on turnover. | Unsupported professional and legal claims. |

Additional failures: fixed assets have invented minimum/maximum values; cash/bank are guessed percentages with minima; capital is a balancing plug; current ratio has invented fallbacks; debtor aging is 60/25/10/5 percent; supplier MSME status is inferred from age alone; months are weighted synthetic annual rows; duplicate-number detection claims sequence continuity; no risk ever becomes critical; missing inputs start at a perfect score.

## Period, scope, and evidence gaps

Old queries use createdAt for invoices, invoiceDate for purchases, expenseDate for expenses, periodEnd for salary, and current snapshots for receivables/inventory. Missing dates are included. End-of-day uses millisecond precision and device timezone. Aging is measured at generation time rather than period end. Only the currently selected outlet is queried; customers and some invoice-line fallback reads are business-wide/unscoped. No all-outlet authorization/coverage check exists.

Corrections will use inclusive India calendar dates with an exclusive next-day UTC boundary, source document dates with declared fallbacks, saved salary allocation snapshots, and transaction dates for cash events. Period-crossing salary accruals will be marked insufficient unless supported by a saved split. No proportional daily salary estimate will be invented.

The existing contracts do not establish a complete opening trial balance, fixed-asset register/depreciation, capital/drawings history, verified ITC eligibility, or consistent historical inventory value snapshots. Reliable complete balance sheets and COGS cannot be manufactured from these records. Unsupported outputs must remain unavailable, with partial observed schedules and reconciliation exceptions. A future accounting contract extension requires explicit approval; this task introduces no schema migration.

Tax invoice evidence reference: CBIC Rule 46 requires taxable value, classification and tax components; automatic legal conclusions remain NOT_VERIFIED: https://taxinformation.cbic.gov.in/content-page/explore-rules/1000136/1000001 .

## Change safety

Use read-only local snapshots and existing repository contracts. Do not run the app against a production account, modify source transactions, deploy migrations/rules, alter catalogue releases, commit, or push. Tests use disposable SQLite files and blocked remote clients.

## Reference PDF evidence verified

Both original A4 pages were visually inspected and their complete text extracted with macOS PDFKit (Poppler was unavailable). Page 1 confirms the 1-20 October 2026 Suman Enterprises / Kolkata Hardware Shop scope, opening stock INR 42,505,950.00, purchases INR 51,981.36, closing stock INR 50,007,000.00, fallback COGS INR 4,420.00, and trading subtotals INR 42,560,311.36 versus INR 50,013,800.00. Their difference is INR 7,453,488.64. The displayed assets INR 150,000, cash INR 5,000 and bank INR 10,000 exactly match the code's fabricated minimums; displayed capital is a residual balancing amount.

Page 2 confirms that the only visible GST rate/HSN row accounts for INR 1,800 against the displayed INR 6,800 total, with a blank HSN and quantity derived from a line count. It labels the entire INR 51,981.36 purchase amount as input credit in a taxable-value column, despite missing demonstrated input-tax evidence. The inventory section is an eight-SKU aggregate and incorrectly describes its source values as verified/FIFO. The repeated certification and CA exemption statements have no supporting audit evidence.

No original transaction export or sanitized account database accompanied the PDF. Therefore the exact correct historical revenue, cost, payroll, asset and tax balances cannot be asserted from this PDF. The replacement engine must regenerate them from authorized persisted snapshots and disclose unsupported histories; this task does not edit PDF figures to match expected values.

## Additional persisted identity contracts used in the correction

`StaffSalaryRepository` records a store-purchase cash repayment in both `payments/PAY-SP-<request>` and `financial_transactions/FIN-SPAY-<request>`; the latter references the invoice, not the payment ID. These exact saved identities must be reconciled to prevent counting the collection twice. Salary purchase offsets with NON_CASH mode remain excluded from cash flow. Invoice cancellation changes revenue status but must not erase an actual dated receipt or invent a refund. Post-period edits require an original revision trail before historical revenue can be verified.

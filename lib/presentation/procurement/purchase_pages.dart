import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/models/purchase_bill_model.dart';
import '../../data/services/purchase_document_service.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/custom_date_range_dialog.dart';
import 'purchase_entry_page.dart';
import 'supplier_pages.dart' show showSupplierRefundEntry;
import '../app_controller.dart';

const advancedCorrectionMessage =
    'This field affects inventory, valuation, supplier payable, tax, or payment history and requires the advanced correction workflow.';

class PurchaseManagementPage extends StatefulWidget {
  const PurchaseManagementPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<PurchaseManagementPage> createState() => _PurchaseManagementPageState();
}

class _PurchaseManagementPageState extends State<PurchaseManagementPage> {
  final _search = TextEditingController();
  final _purchaseDocuments = const PurchaseDocumentService();
  String? _supplierFilter;
  DateTimeRange? _dateRange;
  String _statusFilter = 'ALL';
  bool _creatingPurchase = false;
  PurchaseBillModel? _editingDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadPurchases();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  Future<void> _pickDateRange(AppLocalizations? l10n) async {
    final range = await showCustomDateRangePicker(
      context: context,
      initialStart:
          _dateRange?.start ??
          DateTime.now().subtract(const Duration(days: 30)),
      initialEnd: _dateRange?.end ?? DateTime.now(),
      title: l10n?.purchaseDateRange ?? 'Purchase Date Range',
    );
    if (range != null && mounted) {
      setState(() => _dateRange = range);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);

      if (!c.canManagePurchases()) {
        return const Center(child: Text('You do not have purchase access.'));
      }
      if (_creatingPurchase) {
        return PurchaseEntryPage(
          controller: c,
          onClose: _returnToPurchaseList,
          draftToEdit: _editingDraft,
        );
      }
      final query = _search.text.trim().toLowerCase();
      final bills = c.purchaseBills
          .where((bill) => _matchesBill(bill, query))
          .toList();
      final total = c.purchaseBills.fold<int>(
        0,
        (sum, bill) => sum + bill.grandTotal,
      );
      final paid = c.purchaseBills.fold<int>(
        0,
        (sum, bill) => sum + bill.paidAmount,
      );
      final due = c.purchaseBills.fold<int>(
        0,
        (sum, bill) => sum + bill.outstandingAmount,
      );
      final partialCount = c.purchaseBills
          .where(
            (b) =>
                b.paymentStatus == 'PARTIAL' ||
                b.paymentStatus == 'PARTIALLY_PAID',
          )
          .length;

      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header Bar
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final heading = Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF132B45).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: Color(0xFF132B45),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.purchases ?? 'Purchases',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Procurement records, inward inventory stock, supplier invoices & settlements',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final actions = Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: compact ? WrapAlignment.end : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton.outlined(
                    tooltip: 'Refresh',
                    onPressed: c.loadPurchases,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF132B45),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: c.purchaseSaving || !c.canCreatePurchases()
                        ? null
                        : _createDraft,
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: Text(
                      l10n?.newPurchase ?? 'New Purchase',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [heading, const SizedBox(height: 10), actions],
                    )
                  : Row(
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    );
            },
          ),
          const SizedBox(height: 18),

          // Executive KPI Cards
          LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 960;
              final kpi1 = _PurchaseKpiCard(
                title: l10n?.totalPurchases ?? 'Total Purchases',
                value: '₹${_money(total)}',
                icon: Icons.shopping_bag_outlined,
                accentColor: const Color(0xFF132B45),
                badgeText: 'Gross Procurement',
              );
              final kpi2 = _PurchaseKpiCard(
                title: l10n?.totalPaid ?? 'Total Paid',
                value: '₹${_money(paid)}',
                icon: Icons.check_circle_outline_rounded,
                accentColor: const Color(0xFF059669),
                badgeText: 'Settled to Vendors',
              );
              final kpi3 = _PurchaseKpiCard(
                title: l10n?.outstandingDue ?? 'Outstanding',
                value: '₹${_money(due)}',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: const Color(0xFFDC2626),
                badgeText: 'Pending Payables',
              );
              final kpi4 = _PurchaseKpiCard(
                title: l10n?.partiallyPaid ?? 'Partially Paid',
                value: '$partialCount',
                icon: Icons.pie_chart_outline_rounded,
                accentColor: const Color(0xFFD97706),
                badgeText: 'Active Partial Inward',
              );

              if (isDesktop) {
                return Row(
                  children: [
                    Expanded(child: kpi1),
                    const SizedBox(width: 14),
                    Expanded(child: kpi2),
                    const SizedBox(width: 14),
                    Expanded(child: kpi3),
                    const SizedBox(width: 14),
                    Expanded(child: kpi4),
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: (constraints.maxWidth - 12) / 2, child: kpi1),
                  SizedBox(width: (constraints.maxWidth - 12) / 2, child: kpi2),
                  SizedBox(width: (constraints.maxWidth - 12) / 2, child: kpi3),
                  SizedBox(width: (constraints.maxWidth - 12) / 2, child: kpi4),
                ],
              );
            },
          ),
          const SizedBox(height: 18),

          // Search & Filter Console
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Status Filter Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterChip(
                      'ALL',
                      'All Purchases',
                      Icons.all_inbox_rounded,
                    ),
                    _filterChip(
                      'APPROVED',
                      l10n?.approved ?? 'Approved',
                      Icons.verified_outlined,
                      const Color(0xFF059669),
                    ),
                    _filterChip(
                      'DRAFT',
                      l10n?.draft ?? 'Draft',
                      Icons.edit_note_outlined,
                      const Color(0xFFD97706),
                    ),
                    _filterChip(
                      'PAID',
                      'Paid In Full',
                      Icons.check_circle_outline,
                      const Color(0xFF059669),
                    ),
                    _filterChip(
                      'PARTIAL',
                      l10n?.partiallyPaid ?? 'Partially Paid',
                      Icons.hourglass_top_outlined,
                      const Color(0xFF2563EB),
                    ),
                    _filterChip(
                      'UNPAID',
                      'Unpaid / Due',
                      Icons.warning_amber_rounded,
                      const Color(0xFFDC2626),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Search, Supplier & Date Range Inputs Row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final searchField = TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _search.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _search.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        hintText: l10n?.searchPurchases ?? 'Search purchase no, supplier invoice, supplier or product...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    );

                    final supplierDropdown = DropdownButtonFormField<String?>(
                      key: ValueKey('supplier_filter_$_supplierFilter'),
                      initialValue: _supplierFilter,
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(
                          Icons.business_outlined,
                          size: 18,
                        ),
                        labelText:
                            l10n?.filterBySupplier ?? 'Filter by supplier',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n?.allSuppliers ?? 'All suppliers'),
                        ),
                        ...c.suppliers.map(
                          (supplier) => DropdownMenuItem<String?>(
                            value: supplier.supplierId,
                            child: Text(
                              supplier.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _supplierFilter = value),
                    );

                    final dateRangeButton = OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(
                          color: _dateRange != null
                              ? const Color(0xFF132B45)
                              : const Color(0xFFCBD5E1),
                          width: _dateRange != null ? 1.5 : 1,
                        ),
                        backgroundColor: _dateRange != null
                            ? const Color(0xFF132B45).withValues(alpha: 0.04)
                            : Colors.transparent,
                      ),
                      onPressed: () => _pickDateRange(l10n),
                      icon: Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                        color: _dateRange != null
                            ? const Color(0xFF132B45)
                            : const Color(0xFF64748B),
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dateRange == null
                                ? (l10n?.purchaseDateRange ??
                                      'Purchase date range')
                                : '${_formatDate(_dateRange!.start)} – ${_formatDate(_dateRange!.end)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _dateRange != null
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _dateRange != null
                                  ? const Color(0xFF132B45)
                                  : const Color(0xFF475569),
                            ),
                          ),
                          if (_dateRange != null) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => setState(() => _dateRange = null),
                              child: const Icon(
                                Icons.cancel,
                                size: 16,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );

                    if (constraints.maxWidth >= 950) {
                      return Row(
                        children: [
                          Expanded(flex: 5, child: searchField),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: supplierDropdown),
                          const SizedBox(width: 12),
                          dateRangeButton,
                          if (_dateRange != null ||
                              _supplierFilter != null ||
                              _statusFilter != 'ALL') ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Clear filters',
                              onPressed: () => setState(() {
                                _dateRange = null;
                                _supplierFilter = null;
                                _statusFilter = 'ALL';
                                _search.clear();
                              }),
                              icon: const Icon(
                                Icons.filter_alt_off_outlined,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchField,
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(width: 260, child: supplierDropdown),
                            dateRangeButton,
                            if (_dateRange != null ||
                                _supplierFilter != null ||
                                _statusFilter != 'ALL')
                              TextButton.icon(
                                onPressed: () => setState(() {
                                  _dateRange = null;
                                  _supplierFilter = null;
                                  _statusFilter = 'ALL';
                                  _search.clear();
                                }),
                                icon: const Icon(Icons.clear_all, size: 16),
                                label: const Text('Clear all'),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Purchases List / State Feedback
          if (c.purchasesLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (c.purchasesError != null)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFFECACA)),
              ),
              color: const Color(0xFFFEF2F2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.purchasesError!,
                        style: const TextStyle(color: Color(0xFF991B1B)),
                      ),
                    ),
                    TextButton(
                      onPressed: c.loadPurchases,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (bills.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 24,
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n?.noPurchasesFound ??
                          'No purchases found matching criteria.',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Create your first purchase manually or import a supplier bill.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < bills.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _PurchaseTile(
                    bill: bills[i],
                    busy: c.purchaseSaving,
                    onApprove: () => _approve(context, bills[i]),
                    onPay: () => _recordPayment(context, bills[i]),
                    onEditDraft: () => setState(() {
                      _editingDraft = bills[i];
                      _creatingPurchase = true;
                    }),
                    onCorrect: () => _correctPurchase(context, bills[i]),
                    onView: () => _viewPurchase(context, bills[i]),
                    onPrint: () => _printOrDownloadPurchase(context, bills[i]),
                    onPaymentHistory: () =>
                        _showPaymentHistory(context, bills[i]),
                  ),
                ],
              ],
            ),
        ],
      );
    },
  );

  Widget _filterChip(String code, String label, IconData icon, [Color? color]) {
    final isSelected = _statusFilter == code;
    final activeColor = color ?? const Color(0xFF132B45);

    return InkWell(
      onTap: () => setState(() => _statusFilter = code),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesBill(PurchaseBillModel bill, String query) {
    if (_statusFilter != 'ALL') {
      if (_statusFilter == 'APPROVED' && bill.status != 'APPROVED') {
        return false;
      }
      if (_statusFilter == 'DRAFT' && bill.status != 'DRAFT') {
        return false;
      }
      if (_statusFilter == 'CANCELLED' && bill.status != 'CANCELLED') {
        return false;
      }
      if (_statusFilter == 'PAID' && bill.paymentStatus != 'PAID') {
        return false;
      }
      if (_statusFilter == 'PARTIAL' &&
          (bill.paymentStatus != 'PARTIAL' &&
              bill.paymentStatus != 'PARTIALLY_PAID')) {
        return false;
      }
      if (_statusFilter == 'UNPAID' &&
          (bill.paymentStatus != 'UNPAID' && bill.outstandingAmount <= 0)) {
        return false;
      }
    }
    if (_supplierFilter != null && bill.supplierId != _supplierFilter) {
      return false;
    }
    final range = _dateRange;
    if (range != null) {
      final date = bill.purchaseDate ?? bill.invoiceDate;
      final day = DateTime(date.year, date.month, date.day);
      final start = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final end = DateTime(range.end.year, range.end.month, range.end.day);
      if (day.isBefore(start) || day.isAfter(end)) return false;
    }
    if (query.isEmpty) return true;

    return [
      bill.purchaseNumber ?? '',
      bill.purchaseDate?.toIso8601String() ?? '',
      bill.businessId,
      bill.outletId,
      bill.supplierInvoiceNumber,
      bill.supplierName ?? '',
      ...bill.items.map((line) => line.productName),
      ...bill.items.map((line) => line.variantName ?? ''),
      ...bill.items.expand(
        (line) => [
          line.barcodeSnapshot ?? '',
          line.internalBatchNo ?? '',
          line.supplierLotNo ?? '',
          line.variantId,
          line.expiryDate?.toIso8601String() ?? '',
        ],
      ),
    ].any((value) => value.toLowerCase().contains(query));
  }

  void _createDraft() {
    setState(() {
      _editingDraft = null;
      _creatingPurchase = true;
    });
  }

  void _returnToPurchaseList() {
    if (!mounted) return;
    setState(() {
      _creatingPurchase = false;
      _editingDraft = null;
    });
    widget.controller.loadPurchases();
  }

  Future<void> _viewPurchase(
    BuildContext context,
    PurchaseBillModel bill,
  ) async {
    final corrections = await widget.controller.loadPurchaseCorrections(bill);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${bill.purchaseNumber ?? bill.purchaseBillId} details'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Supplier: ${bill.supplierName ?? bill.supplierId}'),
                Text('Supplier invoice: ${bill.supplierInvoiceNumber}'),
                Text('Invoice date: ${_formatDisplayDate(bill.invoiceDate)}'),
                Text(
                  'Purchase date: ${_formatDisplayDate(bill.purchaseDate ?? bill.invoiceDate)}',
                ),
                Text('Status: ${bill.status} · ${bill.paymentStatus}'),
                Text(
                  'Subtotal ₹${_money(bill.subtotal)} · Taxable ₹${_money(bill.taxableAmount)}',
                ),
                Text(
                  'CGST ₹${_money(bill.cgstAmount)} · SGST ₹${_money(bill.sgstAmount)} · IGST ₹${_money(bill.igstAmount)}',
                ),
                Text(
                  'Total ₹${_money(bill.grandTotal)} · Paid ₹${_money(bill.paidAmount)} · Due ₹${_money(bill.outstandingAmount)}',
                ),
                const Divider(),
                for (final item in bill.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${item.productName} · ${item.variantName ?? item.variantId}\n'
                      'Qty ${_qtyDisplay(item.quantity)} · Rate ₹${_money(item.rate)} · GST ${item.gstRateBps / 100}% · '
                      'MRP ₹${_money(item.mrp ?? 0)} · Selling ₹${_money(item.sellingPrice ?? 0)}\n'
                      'Barcode ${item.barcodeSnapshot ?? '—'} · Internal batch ${item.internalBatchNo ?? '—'} · '
                      'Supplier lot ${item.supplierLotNo ?? '—'} · Expiry ${item.expiryDate == null ? '—' : _formatDisplayDate(item.expiryDate!)}',
                    ),
                  ),
                if (corrections.isNotEmpty) ...[
                  const Divider(),
                  const Text(
                    'Correction Audit',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  for (final correction in corrections)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Correction #${correction.correctionNumber} · ${correction.correctedAt.toLocal()} · ${correction.correctedByUid}\n'
                        'Reason: ${correction.reason}\nChanged: ${correction.changedFields.join(', ')}',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _correctPurchase(
    BuildContext context,
    PurchaseBillModel bill,
  ) async {
    final correctionContext = await widget.controller
        .loadAdvancedPurchaseCorrectionContext(bill);
    if (!context.mounted) return;
    final invoice = TextEditingController(text: bill.supplierInvoiceNumber);
    final invoiceDate = TextEditingController(
      text: _dateOnly(bill.invoiceDate),
    );
    final purchaseDate = TextEditingController(
      text: _dateOnly(bill.purchaseDate ?? bill.invoiceDate),
    );
    final reason = TextEditingController();
    final correctionScrollController = ScrollController(initialScrollOffset: 0);
    final lineControllers = <String, Map<String, TextEditingController>>{
      for (final item in bill.items)
        item.goodsReceiptItemId: {
          'quantity': TextEditingController(
            text: _quantityLabel(item.quantity),
          ),
          'rate': TextEditingController(text: _paiseLabel(item.rate)),
          'gstRateBps': TextEditingController(
            text: (item.gstRateBps / 100)
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), ''),
          ),
          'mrp': TextEditingController(text: _paiseLabel(item.mrp ?? 0)),
          'sellingPrice': TextEditingController(
            text: _paiseLabel(item.sellingPrice ?? 0),
          ),
          'supplierLotNo': TextEditingController(
            text: item.supplierLotNo ?? '',
          ),
          'manufacturingDate': TextEditingController(
            text: item.manufacturingDate == null
                ? ''
                : _dateOnly(item.manufacturingDate!),
          ),
          'expiryDate': TextEditingController(
            text: item.expiryDate == null ? '' : _dateOnly(item.expiryDate!),
          ),
        },
    };
    ModalRoute<dynamic>? correctionDialogRoute;
    final submit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        correctionDialogRoute = ModalRoute.of(dialogContext);
        final viewport = MediaQuery.sizeOf(dialogContext);
        final width = viewport.width - 48;
        final height = viewport.height - 48;
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width < 760 ? width : 760,
            height: height < 760 ? height : 760,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Correct Purchase',
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Only approved Phase 1 metadata fields can be corrected here.',
                              style: Theme.of(dialogContext).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: correctionScrollController,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _correctionSectionHeading(
                          dialogContext,
                          'Invoice Details',
                        ),
                        const SizedBox(height: 8),
                        _correctionField(
                          'Supplier Invoice No.',
                          bill.supplierInvoiceNumber,
                          invoice,
                        ),
                        _correctionDateField(
                          dialogContext,
                          'Invoice Date (YYYY-MM-DD)',
                          _dateOnly(bill.invoiceDate),
                          invoiceDate,
                          originalDate: bill.invoiceDate,
                        ),
                        _correctionDateField(
                          dialogContext,
                          'Purchase Date (YYYY-MM-DD)',
                          _dateOnly(bill.purchaseDate ?? bill.invoiceDate),
                          purchaseDate,
                          originalDate: bill.purchaseDate ?? bill.invoiceDate,
                        ),
                        const SizedBox(height: 8),
                        _correctionSectionHeading(
                          dialogContext,
                          'Item Corrections',
                        ),
                        const SizedBox(height: 8),
                        if (bill.items.isNotEmpty)
                          Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionPanelList.radio(
                              elevation: 0,
                              expandedHeaderPadding: EdgeInsets.zero,
                              initialOpenPanelValue:
                                  bill.items.first.goodsReceiptItemId,
                              children: [
                                for (final item in bill.items)
                                  ExpansionPanelRadio(
                                    value: item.goodsReceiptItemId,
                                    canTapOnHeader: true,
                                    headerBuilder: (context, isExpanded) =>
                                        ListTile(
                                          dense: true,
                                          title: Text(
                                            item.productName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            item.variantName ?? item.variantId,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    body: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        12,
                                      ),
                                      child: Column(
                                        children: [
                                          _correctionNumberField(
                                            'Quantity',
                                            _quantityLabel(item.quantity),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['quantity']!,
                                            enabled:
                                                correctionContext[item
                                                    .goodsReceiptItemId]?['verified'] ==
                                                true,
                                            additionalHelper:
                                                correctionContext[item
                                                        .goodsReceiptItemId]?['verified'] ==
                                                    true
                                                ? 'Consumed ${_quantityLabel(correctionContext[item.goodsReceiptItemId]?['consumedBaseQuantity'] as int? ?? 0)} · Available ${_quantityLabel(correctionContext[item.goodsReceiptItemId]?['availableBaseQuantity'] as int? ?? 0)}'
                                                : correctionContext[item
                                                              .goodsReceiptItemId]?['blockedReason']
                                                          as String? ??
                                                      'Batch movement history is not verified.',
                                          ),
                                          _correctionNumberField(
                                            'Purchase Rate (₹)',
                                            _paiseLabel(item.rate),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['rate']!,
                                          ),
                                          _correctionNumberField(
                                            'GST %',
                                            (item.gstRateBps / 100)
                                                .toStringAsFixed(2),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['gstRateBps']!,
                                          ),
                                          _correctionNumberField(
                                            'MRP (₹)',
                                            _paiseLabel(item.mrp ?? 0),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['mrp']!,
                                          ),
                                          _correctionNumberField(
                                            'Selling Price (₹)',
                                            _paiseLabel(item.sellingPrice ?? 0),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['sellingPrice']!,
                                          ),
                                          _correctionField(
                                            'Supplier Lot',
                                            item.supplierLotNo ?? '—',
                                            lineControllers[item
                                                .goodsReceiptItemId]!['supplierLotNo']!,
                                          ),
                                          _correctionDateField(
                                            dialogContext,
                                            'Manufacturing Date (YYYY-MM-DD)',
                                            item.manufacturingDate == null
                                                ? '—'
                                                : _dateOnly(
                                                    item.manufacturingDate!,
                                                  ),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['manufacturingDate']!,
                                            originalDate:
                                                item.manufacturingDate,
                                          ),
                                          _correctionDateField(
                                            dialogContext,
                                            'Expiry Date (YYYY-MM-DD)',
                                            item.expiryDate == null
                                                ? '—'
                                                : _dateOnly(item.expiryDate!),
                                            lineControllers[item
                                                .goodsReceiptItemId]!['expiryDate']!,
                                            originalDate: item.expiryDate,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 14),
                        _advancedCorrectionImpactPreview(
                          bill,
                          lineControllers,
                          correctionContext,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: colorScheme.onTertiaryContainer,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Product, variant, barcode, and internal batch number remain immutable. Current selling price outside this purchase snapshot is not changed.',
                                  style: Theme.of(dialogContext)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: colorScheme.onTertiaryContainer,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Quantity changes require verified batch movement coverage and sufficient remaining stock. Payment allocations cannot exceed the corrected bill total.',
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: reason,
                          decoration: const InputDecoration(
                            labelText: 'Reason for correction',
                            hintText: 'Enter why this correction is required',
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 24, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Save Correction'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    await correctionDialogRoute?.completed;
    if (submit == true && context.mounted) {
      final parsedInvoiceDate = _parseCorrectionDate(invoiceDate.text.trim());
      final parsedPurchaseDate = _parseCorrectionDate(purchaseDate.text.trim());
      if (reason.text.trim().isEmpty ||
          parsedInvoiceDate == null ||
          parsedPurchaseDate == null) {
        _toast(
          context,
          'Enter a correction reason and valid dates as YYYY-MM-DD.',
        );
      } else {
        final metadata = <String, Map<String, dynamic>>{};
        var valid = true;
        for (final item in bill.items) {
          final fields = lineControllers[item.goodsReceiptItemId]!;
          final quantity = _parseCorrectionQuantity(fields['quantity']!.text);
          final rate = _parseCorrectionPaise(fields['rate']!.text);
          final gst = _parseCorrectionPercent(fields['gstRateBps']!.text);
          final mrp = _parseCorrectionPaise(fields['mrp']!.text);
          final sellingPrice = _parseCorrectionPaise(
            fields['sellingPrice']!.text,
          );
          final mfgText = fields['manufacturingDate']!.text.trim();
          final expiryText = fields['expiryDate']!.text.trim();
          final mfg = mfgText.isEmpty ? null : _parseCorrectionDate(mfgText);
          final expiry = expiryText.isEmpty
              ? null
              : _parseCorrectionDate(expiryText);
          if (quantity == null ||
              quantity <= 0 ||
              rate == null ||
              rate < 0 ||
              gst == null ||
              gst < 0 ||
              gst > 2800 ||
              mrp == null ||
              mrp < 0 ||
              sellingPrice == null ||
              sellingPrice < 0 ||
              (mfgText.isNotEmpty && mfg == null) ||
              (expiryText.isNotEmpty && expiry == null) ||
              (mfg != null && expiry != null && expiry.isBefore(mfg))) {
            valid = false;
          }
          metadata[item.goodsReceiptItemId] = {
            'quantity': quantity,
            'rate': rate,
            'gstRateBps': gst,
            'mrp': mrp,
            'sellingPrice': sellingPrice,
            'supplierLotNo': fields['supplierLotNo']!.text.trim().isEmpty
                ? null
                : fields['supplierLotNo']!.text.trim(),
            'manufacturingDate': mfg,
            'expiryDate': expiry,
          };
        }
        if (!valid) {
          _toast(
            context,
            'Enter valid manufacturing and expiry dates; expiry cannot be before manufacturing.',
          );
        } else if (await _confirmAllocationReleaseIfNeeded(
              context,
              bill,
              metadata,
            ) &&
            await widget.controller.correctPurchaseMetadata(
              bill: bill,
              reason: reason.text,
              supplierInvoiceNumber: invoice.text.trim(),
              invoiceDate: parsedInvoiceDate,
              purchaseDate: parsedPurchaseDate,
              lineMetadata: metadata,
            )) {
          if (context.mounted) {
            _toast(context, 'Purchase metadata corrected and queued for sync.');
            final correctedTotal = _correctedPurchaseTotal(bill, metadata);
            if (bill.paidAmount > correctedTotal) {
              final recordRefund = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Supplier Advance Available'),
                  content: const Text(
                    'The excess allocation is now available as supplier advance. Keep it for a future purchase or explicitly record money returned by the supplier.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Keep as Supplier Advance'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Record Supplier Refund'),
                    ),
                  ],
                ),
              );
              if (recordRefund == true && context.mounted) {
                await showSupplierRefundEntry(
                  context,
                  widget.controller,
                  bill.supplierId,
                );
              }
            }
          }
        } else if (context.mounted) {
          _toast(
            context,
            widget.controller.error.isEmpty
                ? 'Correction could not be saved.'
                : widget.controller.error,
          );
        }
      }
    }
    invoice.dispose();
    invoiceDate.dispose();
    purchaseDate.dispose();
    reason.dispose();
    for (final fields in lineControllers.values) {
      for (final controller in fields.values) {
        controller.dispose();
      }
    }
    correctionScrollController.dispose();
  }

  Future<bool> _confirmAllocationReleaseIfNeeded(
    BuildContext context,
    PurchaseBillModel bill,
    Map<String, Map<String, dynamic>> metadata,
  ) async {
    final correctedTotal = _correctedPurchaseTotal(bill, metadata);
    final preview = await widget.controller.loadPurchasePaymentReleasePreview(
      bill,
    );
    if (!context.mounted) return false;
    if (preview == null) {
      _toast(
        context,
        widget.controller.error.isEmpty
            ? 'Unable to verify the purchase payment allocation.'
            : widget.controller.error,
      );
      return false;
    }
    final allocated = preview['allocatedAmount'] ?? 0;
    final excess = allocated - correctedTotal;
    if (excess <= 0 && bill.paidAmount <= correctedTotal) return true;
    if (allocated != bill.paidAmount || excess <= 0) {
      _toast(
        context,
        'Payment allocation records do not match the purchase paid amount. Reconcile payment history before correcting.',
      );
      return false;
    }
    final advanceAfter = (preview['unallocatedAdvance'] ?? 0) + excess;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excess payment will become Supplier Advance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current purchase total: ₹${_money(bill.grandTotal)}'),
            Text('Corrected purchase total: ₹${_money(correctedTotal)}'),
            Text('Amount currently applied: ₹${_money(allocated)}'),
            Text('Excess amount: ₹${_money(excess)}'),
            Text('Supplier advance after correction: ₹${_money(advanceAfter)}'),
            const SizedBox(height: 12),
            const Text(
              'The excess payment will remain with the supplier as advance credit for future purchases. No cash refund is recorded.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apply Correction'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showPaymentHistory(
    BuildContext context,
    PurchaseBillModel bill,
  ) async {
    final payments = await widget.controller.loadPurchasePaymentHistory(bill);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Payment History'),
        content: SizedBox(
          width: 520,
          child: payments.isEmpty
              ? const Text('No payments are recorded against this purchase.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final payment in payments)
                      ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(
                          '₹${_money((payment['amount'] as num?)?.toInt() ?? 0)} · ${payment['paymentMode'] ?? 'Payment'}',
                        ),
                        subtitle: Text(
                          '${payment['paymentDate'] ?? 'Date unavailable'} · ${payment['status'] ?? ''}\nReference: ${payment['transactionReference'] ?? '—'}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _printOrDownloadPurchase(
    BuildContext context,
    PurchaseBillModel bill,
  ) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Purchase document'),
        content: const Text('Print or save a PDF copy of this purchase.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, 'download'),
            child: const Text('Download PDF'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'print'),
            child: const Text('Print'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    try {
      if (action == 'print') {
        await _purchaseDocuments.print(bill);
      } else {
        final location = await getSaveLocation(
          acceptedTypeGroups: [
            const XTypeGroup(label: 'PDF', extensions: ['pdf']),
          ],
          suggestedName:
              'Purchase_${bill.purchaseNumber ?? bill.purchaseBillId}.pdf',
          confirmButtonText: 'Save',
        );
        if (location == null) return;
        final bytes = await _purchaseDocuments.buildPdf(bill);
        final path = location.path.toLowerCase().endsWith('.pdf')
            ? location.path
            : '${location.path}.pdf';
        await XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'application/pdf',
          name: 'Purchase.pdf',
        ).saveTo(path);
      }
      if (context.mounted) {
        _toast(
          context,
          action == 'print'
              ? 'Purchase sent to printer.'
              : 'Purchase PDF saved.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _toast(
          context,
          'Could not ${action == 'print' ? 'print' : 'save'} purchase: $error',
        );
      }
    }
  }

  Widget _advancedCorrectionImpactPreview(
    PurchaseBillModel bill,
    Map<String, Map<String, TextEditingController>> controllers,
    Map<String, Map<String, dynamic>> correctionContext,
  ) {
    final inputs = controllers.values
        .expand(
          (fields) => [
            fields['quantity']!,
            fields['rate']!,
            fields['gstRateBps']!,
          ],
        )
        .toList();
    return AnimatedBuilder(
      animation: Listenable.merge(inputs),
      builder: (context, _) {
        final rawTaxable = <String, int>{};
        for (final item in bill.items) {
          final fields = controllers[item.goodsReceiptItemId]!;
          final quantity =
              _parseCorrectionQuantity(fields['quantity']!.text) ??
              item.quantity;
          final rate = _parseCorrectionPaise(fields['rate']!.text) ?? item.rate;
          rawTaxable[item.goodsReceiptItemId] = quantity * rate ~/ 1000;
        }
        final subtotal = rawTaxable.values.fold<int>(0, (a, b) => a + b);
        var allocatedDiscount = 0;
        var newTax = 0;
        for (var i = 0; i < bill.items.length; i++) {
          final item = bill.items[i];
          final value = rawTaxable[item.goodsReceiptItemId]!;
          final discount = i == bill.items.length - 1
              ? bill.discountAmount - allocatedDiscount
              : subtotal == 0
              ? 0
              : (bill.discountAmount * value + subtotal ~/ 2) ~/ subtotal;
          allocatedDiscount += discount;
          final gst =
              _parseCorrectionPercent(
                controllers[item.goodsReceiptItemId]!['gstRateBps']!.text,
              ) ??
              item.gstRateBps;
          final lineTaxable = value - discount;
          newTax += (lineTaxable * gst + 5000) ~/ 10000;
        }
        final newTotal =
            subtotal -
            bill.discountAmount +
            newTax +
            bill.chargesAmount +
            bill.roundOff;
        final newBaseByLine = <String, int>{};
        for (final item in bill.items) {
          final quantity =
              _parseCorrectionQuantity(
                controllers[item.goodsReceiptItemId]!['quantity']!.text,
              ) ??
              item.quantity;
          newBaseByLine[item.goodsReceiptItemId] =
              (quantity * item.conversionFactor + 500) ~/ 1000;
        }
        final color = Theme.of(context).colorScheme;
        return Card(
          margin: EdgeInsets.zero,
          color: color.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Impact Preview',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'Purchase total: ₹${_money(bill.grandTotal)} → ₹${_money(newTotal)}',
                ),
                Text(
                  'GST: ₹${_money(bill.cgstAmount + bill.sgstAmount + bill.igstAmount)} → ₹${_money(newTax)}',
                ),
                Text(
                  'Supplier payable: ₹${_money(bill.outstandingAmount)} → ₹${_money(newTotal - bill.paidAmount)} · Paid ₹${_money(bill.paidAmount)}',
                ),
                for (final item in bill.items)
                  Builder(
                    builder: (context) {
                      final facts =
                          correctionContext[item.goodsReceiptItemId] ??
                          const {};
                      final available =
                          (facts['availableBaseQuantity'] as int?) ?? 0;
                      final consumed =
                          (facts['consumedBaseQuantity'] as int?) ?? 0;
                      final stockBefore =
                          (facts['stockQuantityOnHand'] as int?) ?? 0;
                      final delta =
                          newBaseByLine[item.goodsReceiptItemId]! -
                          item.baseQuantity;
                      final fields = controllers[item.goodsReceiptItemId]!;
                      final correctedRate =
                          _parseCorrectionPaise(fields['rate']!.text) ??
                          item.rate;
                      final correctedGst =
                          _parseCorrectionPercent(fields['gstRateBps']!.text) ??
                          item.gstRateBps;
                      final correctedMrp =
                          _parseCorrectionPaise(fields['mrp']!.text) ??
                          item.mrp ??
                          0;
                      final correctedSelling =
                          _parseCorrectionPaise(fields['sellingPrice']!.text) ??
                          item.sellingPrice ??
                          0;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.productName}: qty ${_quantityLabel(item.quantity)} → ${_quantityLabel(_parseCorrectionQuantity(fields['quantity']!.text) ?? item.quantity)} · consumed ${_quantityLabel(consumed)} · available ${_quantityLabel(available)} → ${_quantityLabel(available + delta)} · outlet stock ${_quantityLabel(stockBefore)} → ${_quantityLabel(stockBefore + delta)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Rate ₹${_money(item.rate)} → ₹${_money(correctedRate)} · GST ${item.gstRateBps / 100}% → ${correctedGst / 100}% · MRP ₹${_money(item.mrp ?? 0)} → ₹${_money(correctedMrp)} · Selling ₹${_money(item.sellingPrice ?? 0)} → ₹${_money(correctedSelling)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 4),
                Text(
                  'Rate and GST values are recalculated from the entered line values. The final transaction rechecks batch coverage, stock, and payment allocations before saving.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: color.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _correctionField(
    String label,
    String original,
    TextEditingController controller,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        helperText: 'Original: $original',
        helperStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
        isDense: true,
      ),
    ),
  );

  Widget _correctionNumberField(
    String label,
    String original,
    TextEditingController controller, {
    bool enabled = true,
    String? additionalHelper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: [
          'Original: $original',
          ?additionalHelper,
        ].join(' · '),
        helperStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
        isDense: true,
      ),
    ),
  );

  Widget _correctionDateField(
    BuildContext context,
    String label,
    String original,
    TextEditingController controller, {
    required DateTime? originalDate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'YYYY-MM-DD',
        helperText: 'Original: $original',
        helperStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: 'Choose $label',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () async {
            final focusedDate =
                _parseCorrectionDate(controller.text.trim()) ??
                originalDate ??
                DateTime.now();
            final boundedDate = focusedDate.isBefore(DateTime(1900))
                ? DateTime(1900)
                : focusedDate.isAfter(DateTime(2100, 12, 31))
                ? DateTime(2100, 12, 31)
                : focusedDate;
            final selected = await showDatePicker(
              context: context,
              initialDate: boundedDate,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100, 12, 31),
            );
            if (selected != null) controller.text = _dateOnly(selected);
          },
        ),
      ),
    ),
  );

  Widget _correctionSectionHeading(BuildContext context, String title) => Text(
    title,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(fontWeight: FontWeight.w700),
  );

  Future<void> _approve(BuildContext context, PurchaseBillModel bill) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve purchase?'),
        content: Text(
          'This will receive stock and post ₹${_money(bill.grandTotal)} to the supplier ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (yes == true &&
        context.mounted &&
        await widget.controller.approvePurchase(bill.purchaseBillId)) {
      if (context.mounted) {
        _toast(context, 'Purchase approved and stock received.');
      }
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    PurchaseBillModel bill,
  ) async {
    final amount = TextEditingController(text: _money(bill.outstandingAmount));
    final reference = TextEditingController();
    var mode = 'CASH';
    final result = await showDialog<(int, String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Pay ${bill.supplierName ?? 'supplier'}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Outstanding: ₹${_money(bill.outstandingAmount)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Amount (₹)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey('pay_mode_$mode'),
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Payment mode'),
                  items:
                      const ['CASH', 'UPI', 'BANK_TRANSFER', 'CHEQUE', 'CARD']
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.replaceAll('_', ' ')),
                            ),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => mode = v ?? 'CASH'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Transaction reference (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final cents = _parseMoney(amount.text);
                if (cents != null &&
                    cents > 0 &&
                    cents <= bill.outstandingAmount) {
                  Navigator.pop(context, (cents, mode, reference.text.trim()));
                }
              },
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    reference.dispose();
    if (result == null || !context.mounted) return;
    if (await widget.controller.recordSupplierPayment(
      bill: bill,
      amount: result.$1,
      paymentMode: result.$2,
      reference: result.$3,
    )) {
      if (context.mounted) _toast(context, 'Supplier payment recorded.');
    }
  }

  void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
}

class _PurchaseKpiCard extends StatelessWidget {
  const _PurchaseKpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
    required this.badgeText,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            badgeText,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({
    required this.bill,
    required this.busy,
    required this.onApprove,
    required this.onPay,
    required this.onEditDraft,
    required this.onCorrect,
    required this.onView,
    required this.onPrint,
    required this.onPaymentHistory,
  });
  final PurchaseBillModel bill;
  final bool busy;
  final VoidCallback onApprove, onPay;
  final VoidCallback onEditDraft, onCorrect, onView;
  final VoidCallback onPrint, onPaymentHistory;

  @override
  Widget build(BuildContext context) {
    final isApproved = bill.status == 'APPROVED';
    final isDraft = bill.status == 'DRAFT';
    final date = bill.purchaseDate ?? bill.invoiceDate;
    final formattedDate = _formatDisplayDate(date);

    final (statusColor, statusBg, statusText) = switch (bill.status) {
      'APPROVED' => (
        const Color(0xFF166534),
        const Color(0xFFDCFCE7),
        'APPROVED',
      ),
      'DRAFT' => (const Color(0xFF92400E), const Color(0xFFFEF3C7), 'DRAFT'),
      'CANCELLED' => (
        const Color(0xFF991B1B),
        const Color(0xFFFEE2E2),
        'CANCELLED',
      ),
      _ => (const Color(0xFF475569), const Color(0xFFF1F5F9), bill.status),
    };

    final (payColor, payBg, payText) = switch (bill.paymentStatus) {
      'PAID' => (const Color(0xFF065F46), const Color(0xFFECFDF5), 'PAID'),
      'PARTIAL' || 'PARTIALLY_PAID' => (
        const Color(0xFFB45309),
        const Color(0xFFFFFBEB),
        'PARTIAL',
      ),
      'UNPAID' => (const Color(0xFFB91C1C), const Color(0xFFFEF2F2), 'UNPAID'),
      _ => (
        const Color(0xFF475569),
        const Color(0xFFF1F5F9),
        bill.paymentStatus,
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Bill #, Inv #, Date, and Badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bill Number & Supplier Inv
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF132B45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        bill.purchaseNumber ?? bill.purchaseBillId,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    if (bill.supplierInvoiceNumber.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_outlined,
                              size: 13,
                              color: Color(0xFF64748B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Inv: ${bill.supplierInvoiceNumber}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status Badges
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: payBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: payColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      payText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: payColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Supplier and Outlet Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 16,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bill.supplierName ?? 'Supplier',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (bill.outletId.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Outlet: ${bill.outletId}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Items Preview Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF1F5F9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${bill.items.length} item(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final line in bill.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '• ${line.productName}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                        if (line.variantName != null &&
                            line.variantName != line.productName)
                          Text(
                            '(${line.variantName})',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Qty ${_qtyDisplay(line.quantity)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '₹${_money(line.rate)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        if (line.supplierLotNo?.isNotEmpty == true)
                          Text(
                            'Lot: ${line.supplierLotNo}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        _ExpiryBadge(date: line.expiryDate),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Bar: Financials & Action Buttons
          Row(
            children: [
              // Financial Summary
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '₹${_money(bill.grandTotal)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (bill.outstandingAmount > 0)
                      Text(
                        'Due: ₹${_money(bill.outstandingAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    if (bill.paidAmount > 0)
                      Text(
                        'Paid: ₹${_money(bill.paidAmount)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF059669),
                        ),
                      ),
                  ],
                ),
              ),
              // Action Buttons
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (isDraft)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: busy ? null : onApprove,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text(
                        'Approve',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (isApproved && bill.outstandingAmount > 0)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF132B45),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: busy ? null : onPay,
                      icon: const Icon(Icons.payment, size: 16),
                      label: const Text(
                        'Pay',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    onPressed: onView,
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 16,
                      color: Color(0xFF334155),
                    ),
                    label: const Text(
                      'View',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Purchase actions',
                    icon: const Icon(Icons.more_vert, color: Color(0xFF64748B)),
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          onView();
                        case 'edit':
                          onEditDraft();
                        case 'correct':
                          onCorrect();
                        case 'print':
                          onPrint();
                        case 'payments':
                          onPaymentHistory();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(
                              Icons.visibility_outlined,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 8),
                            Text('View Details'),
                          ],
                        ),
                      ),
                      if (bill.status == 'DRAFT')
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 8),
                              Text('Edit Draft'),
                            ],
                          ),
                        ),
                      if (bill.status == 'APPROVED')
                        const PopupMenuItem(
                          value: 'correct',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_note,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 8),
                              Text('Correct Purchase'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'print',
                        child: Row(
                          children: [
                            Icon(
                              Icons.print_outlined,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 8),
                            Text('Print / Download'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'payments',
                        child: Row(
                          children: [
                            Icon(
                              Icons.history,
                              size: 18,
                              color: Color(0xFF64748B),
                            ),
                            SizedBox(width: 8),
                            Text('Payment History'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpiryBadge extends StatelessWidget {
  const _ExpiryBadge({required this.date});
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = date
        ?.difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final label = date == null
        ? 'No Expiry'
        : days! < 0
        ? 'Expired'
        : days <= 90
        ? 'Expiring Soon'
        : 'Normal';
    final color = switch (label) {
      'Expired' => Theme.of(context).colorScheme.error,
      'Expiring Soon' => Colors.orange.shade800,
      _ => Theme.of(context).colorScheme.primary,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        child: Text(
          date == null ? label : '$label · ${_formatDisplayDate(date!)}',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _formatDisplayDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

DateTime? _parseCorrectionDate(String value) {
  final slashMatch = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$')
      .firstMatch(value.trim());
  if (slashMatch != null) {
    final day = int.parse(slashMatch.group(1)!);
    final month = int.parse(slashMatch.group(2)!);
    final year = int.parse(slashMatch.group(3)!);
    try {
      final parsed = DateTime(year, month, day);
      if (parsed.year == year && parsed.month == month && parsed.day == day) {
        return parsed;
      }
    } catch (_) {}
  }
  final isoMatch = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$')
      .firstMatch(value.trim());
  if (isoMatch != null) {
    final year = int.parse(isoMatch.group(1)!);
    final month = int.parse(isoMatch.group(2)!);
    final day = int.parse(isoMatch.group(3)!);
    try {
      final parsed = DateTime(year, month, day);
      if (parsed.year == year && parsed.month == month && parsed.day == day) {
        return parsed;
      }
    } catch (_) {}
  }
  return null;
}

int? _parseMoney(String raw) {
  final value = raw.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts[0]) * 100 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(2, '0'));
}

int _correctedPurchaseTotal(
  PurchaseBillModel bill,
  Map<String, Map<String, dynamic>> metadata,
) {
  int roundHalfUp(int value, int divisor) => (value + divisor ~/ 2) ~/ divisor;
  final rawTaxable = [
    for (final item in bill.items)
      roundHalfUp(
        (metadata[item.goodsReceiptItemId]?['quantity'] as int? ??
                item.quantity) *
            (metadata[item.goodsReceiptItemId]?['rate'] as int? ?? item.rate),
        1000,
      ),
  ];
  final subtotal = rawTaxable.fold<int>(0, (sum, value) => sum + value);
  var allocatedDiscount = 0;
  var tax = 0;
  for (var index = 0; index < bill.items.length; index++) {
    final item = bill.items[index];
    final lineSubtotal = rawTaxable[index];
    final discount = index == bill.items.length - 1
        ? bill.discountAmount - allocatedDiscount
        : subtotal == 0
        ? 0
        : roundHalfUp(bill.discountAmount * lineSubtotal, subtotal);
    allocatedDiscount += discount;
    final gstRateBps =
        metadata[item.goodsReceiptItemId]?['gstRateBps'] as int? ??
        item.gstRateBps;
    tax += roundHalfUp((lineSubtotal - discount) * gstRateBps, 10000);
  }
  return subtotal -
      bill.discountAmount +
      tax +
      bill.chargesAmount +
      bill.roundOff;
}

String _quantityLabel(int value) =>
    (value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 3);

String _paiseLabel(int value) => (value / 100).toStringAsFixed(2);

int? _parseCorrectionQuantity(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts.first) * 1000 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(3, '0'));
}

int? _parseCorrectionPaise(String raw) => _parseMoney(raw);

int? _parseCorrectionPercent(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts.first) * 100 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(2, '0'));
}

String _qtyDisplay(int value) =>
    (value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 3);
String _money(int paise) => (paise / 100).toStringAsFixed(2);

import 'package:flutter/material.dart';

import '../../data/models/supplier_ledger_entry_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_payment_receipt_model.dart';
import '../../data/services/supplier_statement_export_service.dart';
import '../app_controller.dart';
import '../widgets/custom_date_range_dialog.dart';
import 'widgets/supplier_due_payment_dialog.dart';
import 'widgets/supplier_ledger_localizations.dart';
import 'widgets/supplier_payment_voucher_dialog.dart';

enum _DatePreset { allTime, thisMonth, last30Days, last90Days, custom }

enum _LedgerTypeFilter { all, purchases, payments }

class SupplierLedgerDashboardPage extends StatefulWidget {
  const SupplierLedgerDashboardPage({
    super.key,
    required this.controller,
    this.initialSupplierId,
  });

  final AppController controller;
  final String? initialSupplierId;

  @override
  State<SupplierLedgerDashboardPage> createState() =>
      _SupplierLedgerDashboardPageState();
}

class _SupplierLedgerDashboardPageState
    extends State<SupplierLedgerDashboardPage> {
  final _searchController = TextEditingController();
  final _tableScrollController = ScrollController();
  SupplierModel? _selectedSupplier;
  SupplierPaymentReceiptModel? _lastPaymentReceipt;
  List<SupplierModel> _suppliers = [];
  List<SupplierLedgerEntryModel> _allEntries = [];
  List<SupplierLedgerEntryModel> _filteredEntries = [];

  bool _loading = false;
  String? _error;

  _DatePreset _activePreset = _DatePreset.allTime;
  DateTimeRange? _selectedDateRange;
  _LedgerTypeFilter _typeFilter = _LedgerTypeFilter.all;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _searchController.addListener(_applyFilters);
    _initData();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController.dispose();
    _tableScrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initData() async {
    setState(() => _loading = true);
    await widget.controller.loadSuppliers();
    if (!mounted) return;

    _suppliers = widget.controller.suppliers;
    if (_suppliers.isNotEmpty) {
      if (widget.initialSupplierId != null) {
        _selectedSupplier = _suppliers.firstWhere(
          (s) => s.supplierId == widget.initialSupplierId,
          orElse: () => _suppliers.first,
        );
      } else {
        _selectedSupplier = _suppliers.first;
      }
      await _loadLedgerForSupplier(_selectedSupplier!);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadLedgerForSupplier(SupplierModel supplier) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final context = widget.controller.appContext;
    final token = widget.controller.idToken;

    if (context?.businessId == null || token == null) {
      setState(() {
        _loading = false;
        _error = 'Session unavailable. Please sign in again.';
      });
      return;
    }

    try {
      final entries = await widget.controller.supplierRepository.getSupplierLedger(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        supplierId: supplier.supplierId,
        token: token,
      );

      if (!mounted) return;
      setState(() {
        _allEntries = entries;
        _loading = false;
        if (_lastPaymentReceipt == null) {
          final paymentEntries = entries.where((e) => e.isPayment).toList();
          if (paymentEntries.isNotEmpty) {
            final lastP = paymentEntries.last;
            final biz = widget.controller.businesses
                .where((b) => b.businessId == widget.controller.appContext?.businessId)
                .firstOrNull;
            final outlet = widget.controller.outlets
                .where((o) => o.outletId == widget.controller.appContext?.outletId)
                .firstOrNull;
            _lastPaymentReceipt = SupplierPaymentReceiptModel(
              paymentId: lastP.referenceId ?? lastP.voucherNumber ?? lastP.ledgerEntryId,
              voucherNumber: lastP.voucherNumber,
              paymentDate: lastP.transactionDate,
              supplierId: supplier.supplierId,
              supplierName: supplier.name,
              supplierPhone: supplier.mobile,
              businessName: biz?.businessName ?? 'Business',
              outletName: outlet?.outletName,
              paymentMode: lastP.paymentMode ?? 'CASH',
              referenceNo: lastP.referenceNo,
              previousDuePaise: lastP.runningBalancePaise + lastP.debitPaise,
              amountPaidPaise: lastP.debitPaise,
              remainingDuePaise: lastP.runningBalancePaise,
            );
          }
        }
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();

    List<SupplierLedgerEntryModel> list = List.from(_allEntries);

    // 1. Date filter
    if (_selectedDateRange != null) {
      final start = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final end = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
        23,
        59,
        59,
      );
      list = list.where((e) {
        return e.transactionDate.isAfter(start.subtract(const Duration(seconds: 1))) &&
            e.transactionDate.isBefore(end.add(const Duration(seconds: 1)));
      }).toList();
    }

    // 2. Type filter
    if (_typeFilter == _LedgerTypeFilter.purchases) {
      list = list.where((e) => e.isPurchase || e.isOpening).toList();
    } else if (_typeFilter == _LedgerTypeFilter.payments) {
      list = list.where((e) => e.isPayment || e.isRefund).toList();
    }

    // 3. Search query
    if (query.isNotEmpty) {
      list = list.where((e) {
        final particulars = (e.particulars ?? '').toLowerCase();
        final vch = (e.voucherNumber ?? '').toLowerCase();
        final ref = (e.referenceNo ?? '').toLowerCase();
        final mode = (e.paymentMode ?? '').toLowerCase();
        final items = (e.itemsSummary ?? '').toLowerCase();
        return particulars.contains(query) ||
            vch.contains(query) ||
            ref.contains(query) ||
            mode.contains(query) ||
            items.contains(query);
      }).toList();
    }

    setState(() {
      _filteredEntries = list;
    });
  }

  void _setDatePreset(_DatePreset preset) {
    final now = DateTime.now();
    DateTimeRange? range;

    switch (preset) {
      case _DatePreset.allTime:
        range = null;
        break;
      case _DatePreset.thisMonth:
        range = DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
        break;
      case _DatePreset.last30Days:
        range = DateTimeRange(
          start: now.subtract(const Duration(days: 30)),
          end: now,
        );
        break;
      case _DatePreset.last90Days:
        range = DateTimeRange(
          start: now.subtract(const Duration(days: 90)),
          end: now,
        );
        break;
      case _DatePreset.custom:
        _showCustomDateRangePicker();
        return;
    }

    setState(() {
      _activePreset = preset;
      _selectedDateRange = range;
    });
    _applyFilters();
  }

  Future<void> _showCustomDateRangePicker() async {
    final picked = await showCustomDateRangePicker(
      context: context,
      initialStart: _selectedDateRange?.start ??
          DateTime.now().subtract(const Duration(days: 30)),
      initialEnd: _selectedDateRange?.end ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _activePreset = _DatePreset.custom;
        _selectedDateRange = picked;
      });
      _applyFilters();
    }
  }

  // --- Computations ---
  int get _openingBalancePaise {
    final opening = _allEntries.where((e) => e.isOpening);
    if (opening.isNotEmpty) {
      return opening.first.creditPaise;
    }
    return 0;
  }

  int get _totalPurchasesPaise {
    return _filteredEntries
        .where((e) => e.isPurchase)
        .fold(0, (sum, e) => sum + e.creditPaise);
  }

  int get _totalPaymentsPaise {
    return _filteredEntries
        .where((e) => e.isPayment)
        .fold(0, (sum, e) => sum + e.debitPaise);
  }

  int get _closingBalancePaise {
    if (_filteredEntries.isNotEmpty) {
      return _filteredEntries.last.runningBalancePaise;
    }
    return _openingBalancePaise;
  }

  Map<String, int> get _paymentModeBreakdown {
    final map = <String, int>{};
    for (final e in _filteredEntries.where((e) => e.isPayment)) {
      final mode = e.paymentMode?.toUpperCase() ?? 'OTHER';
      map[mode] = (map[mode] ?? 0) + e.debitPaise;
    }
    return map;
  }

  Future<void> _openDuePaymentDialog() async {
    if (_selectedSupplier == null) return;
    final receipt = await showDialog<SupplierPaymentReceiptModel>(
      context: context,
      builder: (ctx) => SupplierDuePaymentDialog(
        supplierId: _selectedSupplier!.supplierId,
        supplierName: _selectedSupplier!.name,
        currentPayablePaise: _closingBalancePaise,
        controller: widget.controller,
      ),
    );

    if (receipt != null && mounted) {
      setState(() => _lastPaymentReceipt = receipt);
      await widget.controller.loadSuppliers();
      if (_selectedSupplier != null && mounted) {
        final updatedSupplier = widget.controller.suppliers
            .where((s) => s.supplierId == _selectedSupplier!.supplierId)
            .firstOrNull;
        if (updatedSupplier != null) {
          _selectedSupplier = updatedSupplier;
        }
        await _loadLedgerForSupplier(_selectedSupplier!);
      }
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => SupplierPaymentVoucherDialog(receipt: receipt),
        );
      }
    }
  }

  void _openVoucherForEntry(SupplierLedgerEntryModel entry) {
    if (_selectedSupplier == null) return;
    final biz = widget.controller.businesses
        .where((b) => b.businessId == widget.controller.appContext?.businessId)
        .firstOrNull;

    final outlet = widget.controller.outlets
        .where((o) => o.outletId == widget.controller.appContext?.outletId)
        .firstOrNull;

    // Previous due before this payment = running balance after + paid amount
    final prevDuePaise = entry.runningBalancePaise + entry.debitPaise;
    final receipt = SupplierPaymentReceiptModel(
      paymentId: entry.referenceId ?? entry.voucherNumber ?? entry.ledgerEntryId,
      voucherNumber: entry.voucherNumber,
      paymentDate: entry.transactionDate,
      supplierId: _selectedSupplier!.supplierId,
      supplierName: _selectedSupplier!.name,
      supplierPhone: _selectedSupplier!.mobile,
      businessName: biz?.businessName ?? 'Business',
      outletName: outlet?.outletName,
      paymentMode: entry.paymentMode ?? 'CASH',
      referenceNo: entry.referenceNo,
      previousDuePaise: prevDuePaise,
      amountPaidPaise: entry.debitPaise,
      remainingDuePaise: entry.runningBalancePaise,
    );
    showDialog(
      context: context,
      builder: (_) => SupplierPaymentVoucherDialog(receipt: receipt),
    );
  }

  Widget _buildRecentPaymentBanner(SupplierLedgerStrings s) {
    if (_lastPaymentReceipt == null) return const SizedBox.shrink();

    final r = _lastPaymentReceipt!;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle_rounded, color: Colors.green.shade800, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.lastPaymentBanner,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF166534)),
                ),
                Text(
                  '₹${(r.amountPaidPaise / 100).toStringAsFixed(2)} • ${s.voucherNo}: ${r.voucherNumber ?? r.paymentId} • ${s.remainingDue}: ₹${(r.remainingDuePaise / 100).toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade900),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => SupplierPaymentVoucherDialog(receipt: r),
              );
            },
            icon: const Icon(Icons.receipt_long_rounded, size: 16),
            label: Text(s.viewSlip),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: s.dismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () => setState(() => _lastPaymentReceipt = null),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    if (_selectedSupplier == null) return;
    final business = widget.controller.businesses
        .where((b) => b.businessId == widget.controller.appContext?.businessId)
        .firstOrNull;

    final fromDate = _selectedDateRange?.start ??
        (_filteredEntries.isNotEmpty
            ? _filteredEntries.first.transactionDate
            : DateTime.now());
    final toDate = _selectedDateRange?.end ??
        (_filteredEntries.isNotEmpty
            ? _filteredEntries.last.transactionDate
            : DateTime.now());

    final s = SupplierLedgerStrings.of(context, widget.controller);

    await SupplierStatementExportService.sharePdf(
      businessName: business?.businessName ?? 'Business Name',
      businessAddress: business?.address,
      businessPhone: business?.phone,
      businessGstin: business?.gstin,
      supplier: _selectedSupplier!,
      entries: _filteredEntries,
      fromDate: fromDate,
      toDate: toDate,
      openingBalancePaise: _openingBalancePaise,
      totalPurchasesPaise: _totalPurchasesPaise,
      totalPaymentsPaise: _totalPaymentsPaise,
      closingBalancePaise: _closingBalancePaise,
      strings: s,
    );
  }

  Future<void> _printStatement() async {
    if (_selectedSupplier == null) return;
    final business = widget.controller.businesses
        .where((b) => b.businessId == widget.controller.appContext?.businessId)
        .firstOrNull;

    final fromDate = _selectedDateRange?.start ??
        (_filteredEntries.isNotEmpty
            ? _filteredEntries.first.transactionDate
            : DateTime.now());
    final toDate = _selectedDateRange?.end ??
        (_filteredEntries.isNotEmpty
            ? _filteredEntries.last.transactionDate
            : DateTime.now());

    final s = SupplierLedgerStrings.of(context, widget.controller);

    await SupplierStatementExportService.printStatement(
      businessName: business?.businessName ?? 'Business Name',
      businessAddress: business?.address,
      businessPhone: business?.phone,
      businessGstin: business?.gstin,
      supplier: _selectedSupplier!,
      entries: _filteredEntries,
      fromDate: fromDate,
      toDate: toDate,
      openingBalancePaise: _openingBalancePaise,
      totalPurchasesPaise: _totalPurchasesPaise,
      totalPaymentsPaise: _totalPaymentsPaise,
      closingBalancePaise: _closingBalancePaise,
      strings: s,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SupplierLedgerStrings.of(context, widget.controller);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeaderBar(theme, wide, s),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      )
                    : _suppliers.isEmpty
                        ? const Center(
                            child: Text('No suppliers found. Please add a supplier.'),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildSupplierSelectorCard(theme, wide, s),
                                const SizedBox(height: 16),
                                _buildKpiCards(theme, wide, s),
                                const SizedBox(height: 16),
                                _buildFiltersAndSearch(theme, wide, s),
                                const SizedBox(height: 16),
                                _buildRecentPaymentBanner(s),
                                _buildLedgerTableCard(theme, s),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(ThemeData theme, bool wide, SupplierLedgerStrings s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4338CA).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Color(0xFF4338CA),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.ledgerTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  s.ledgerSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          // Language selector dropdown
          PopupMenuButton<String>(
            tooltip: 'Language / ভাষা / भाषा',
            onSelected: (code) => widget.controller.setLocale(Locale(code)),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'en', child: Text('🇬🇧 English')),
              PopupMenuItem(value: 'bn', child: Text('🇮🇳 বাংলা (Bengali)')),
              PopupMenuItem(value: 'hi', child: Text('🇮🇳 हिंदी (Hindi)')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.translate_rounded, size: 16, color: Color(0xFF4338CA)),
                  const SizedBox(width: 6),
                  Text(
                    switch (widget.controller.currentLocale.languageCode) {
                      'bn' => 'বাংলা',
                      'hi' => 'हिंदी',
                      _ => 'English',
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_selectedSupplier != null) ...[
            FilledButton.icon(
              onPressed: _openDuePaymentDialog,
              icon: const Icon(Icons.payment_rounded, size: 16),
              label: Text(s.payDue),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: const Color(0xFF16A34A),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: _printStatement,
              icon: const Icon(Icons.print_outlined, size: 16),
              label: Text(s.print),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: Text(s.exportPdf),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: const Color(0xFF4338CA),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: s.refresh,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: () {
                if (_selectedSupplier != null) {
                  _loadLedgerForSupplier(_selectedSupplier!);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSupplierSelectorCard(ThemeData theme, bool wide, SupplierLedgerStrings s) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.business_outlined, color: Color(0xFF4338CA), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.selectSupplier,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<SupplierModel>(
                      value: _selectedSupplier,
                      isDense: true,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      items: _suppliers.map((sup) {
                        return DropdownMenuItem<SupplierModel>(
                          value: sup,
                          child: Text(
                            '${sup.name}${sup.mobile != null && sup.mobile!.isNotEmpty ? ' (${sup.mobile})' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        );
                      }).toList(),
                      onChanged: (newSupplier) {
                        if (newSupplier != null && newSupplier != _selectedSupplier) {
                          setState(() => _selectedSupplier = newSupplier);
                          _loadLedgerForSupplier(newSupplier);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_selectedSupplier != null && wide) ...[
              const SizedBox(width: 20),
              Container(
                height: 40,
                width: 1,
                color: Colors.grey.shade300,
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.gstin,
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  Text(
                    _selectedSupplier!.gstin?.isNotEmpty == true
                        ? _selectedSupplier!.gstin!
                        : s.unregistered,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.contactPerson,
                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade600),
                  ),
                  Text(
                    _selectedSupplier!.contactPerson?.isNotEmpty == true
                        ? _selectedSupplier!.contactPerson!
                        : '—',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCards(ThemeData theme, bool wide, SupplierLedgerStrings s) {
    final closing = _closingBalancePaise;
    final isPayable = closing >= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = wide
            ? (constraints.maxWidth - 36) / 4
            : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _kpiCard(
                label: s.openingBalance,
                amountPaise: _openingBalancePaise,
                icon: Icons.history_edu_rounded,
                color: const Color(0xFF64748B),
                tag: s.broughtForward,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _kpiCard(
                label: s.totalPurchases,
                amountPaise: _totalPurchasesPaise,
                icon: Icons.shopping_bag_outlined,
                color: const Color(0xFF4338CA),
                tag: s.billsCount(_filteredEntries.where((e) => e.isPurchase).length),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _kpiCard(
                label: s.totalPayments,
                amountPaise: _totalPaymentsPaise,
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF059669),
                tag: s.paymentsCount(_filteredEntries.where((e) => e.isPayment).length),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _kpiCard(
                label: s.currentBalance,
                amountPaise: closing.abs(),
                icon: isPayable
                    ? Icons.account_balance_wallet_rounded
                    : Icons.check_circle_rounded,
                color: isPayable
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF059669),
                tag: isPayable ? s.netPayable : s.advanceBalance,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String label,
    required int amountPaise,
    required IconData icon,
    required Color color,
    required String tag,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹${_formatMoney(amountPaise)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tag,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersAndSearch(ThemeData theme, bool wide, SupplierLedgerStrings s) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _presetChip(s.allTime, _DatePreset.allTime),
              _presetChip(s.thisMonth, _DatePreset.thisMonth),
              _presetChip(s.last30Days, _DatePreset.last30Days),
              _presetChip(s.last90Days, _DatePreset.last90Days),
              _presetChip(
                _activePreset == _DatePreset.custom && _selectedDateRange != null
                    ? '${_formatDisplayDate(_selectedDateRange!.start)} - ${_formatDisplayDate(_selectedDateRange!.end)}'
                    : s.customRange,
                _DatePreset.custom,
                icon: Icons.calendar_today_outlined,
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            children: [
              // Search input
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: s.searchPlaceholder,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Segmented Type Filter
              SegmentedButton<_LedgerTypeFilter>(
                segments: [
                  ButtonSegment(
                    value: _LedgerTypeFilter.all,
                    label: Text(s.all),
                  ),
                  ButtonSegment(
                    value: _LedgerTypeFilter.purchases,
                    label: Text(s.purchasesCr),
                  ),
                  ButtonSegment(
                    value: _LedgerTypeFilter.payments,
                    label: Text(s.paymentsDr),
                  ),
                ],
                selected: {_typeFilter},
                onSelectionChanged: (set) {
                  setState(() => _typeFilter = set.first);
                  _applyFilters();
                },
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_paymentModeBreakdown.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${s.paymentSettledByMode} ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ..._paymentModeBreakdown.entries.map((entry) {
                  final label = s.localizedPaymentMode(entry.key);
                  final rs = _formatMoney(entry.value);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '$label: ₹$rs',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  );
                }),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _presetChip(String label, _DatePreset preset, {IconData? icon}) {
    final isSelected = _activePreset == preset;
    return ChoiceChip(
      avatar: icon != null ? Icon(icon, size: 14) : null,
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setDatePreset(preset),
      selectedColor: const Color(0xFF4338CA).withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? const Color(0xFF4338CA) : Colors.black87,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildLedgerTableCard(ThemeData theme, SupplierLedgerStrings s) {
    if (_filteredEntries.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.history_outlined, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                s.noRecordsFound,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Scrollbar(
            controller: _tableScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _tableScrollController,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                horizontalMargin: 14,
                columnSpacing: 16,
              columns: [
                DataColumn(label: Text(s.dateCol, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(s.particularsCol, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(s.vchTypeCol, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(s.vchNoCol, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text(s.paidDrCol, style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text(s.billedCrCol, style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(label: Text(s.runningBalCol, style: const TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                DataColumn(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 125),
                    child: Text(
                      s.viewVoucher,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
              rows: _filteredEntries.map((entry) {
                final dateStr = _formatDisplayDate(entry.transactionDate);
                String vchNo;
                final vch = entry.voucherNumber?.trim() ?? '';
                final ref = entry.referenceNo?.trim() ?? '';
                final refId = entry.referenceId?.trim() ?? '';
                if (vch.isNotEmpty && ref.isNotEmpty && vch != ref) {
                  vchNo = '$vch / $ref';
                } else if (vch.isNotEmpty) {
                  vchNo = vch;
                } else if (ref.isNotEmpty) {
                  vchNo = ref;
                } else if (refId.isNotEmpty) {
                  vchNo = refId;
                } else {
                  vchNo = '—';
                }

                String particulars;
                if (entry.particulars != null && entry.particulars!.trim().isNotEmpty) {
                  particulars = entry.particulars!.trim();
                } else if (entry.itemsSummary != null && entry.itemsSummary!.trim().isNotEmpty) {
                  particulars = entry.itemsSummary!.trim();
                } else if (entry.isPurchase) {
                  particulars = vch.isNotEmpty
                      ? '${s.localizedEntryType(entry.entryType)} #$vch'
                      : s.localizedEntryType(entry.entryType);
                } else if (entry.isPayment) {
                  final mode = entry.paymentMode != null ? s.localizedPaymentMode(entry.paymentMode!) : '';
                  if (mode.isNotEmpty && ref.isNotEmpty) {
                    particulars = '${s.localizedEntryType(entry.entryType)} ($mode) Ref: $ref';
                  } else if (mode.isNotEmpty) {
                    particulars = '${s.localizedEntryType(entry.entryType)} ($mode)';
                  } else {
                    particulars = s.localizedEntryType(entry.entryType);
                  }
                } else {
                  particulars = s.localizedEntryType(entry.entryType);
                }

                final debitText = entry.debitPaise > 0 ? '₹${_formatMoney(entry.debitPaise)}' : '—';
                final creditText = entry.creditPaise > 0 ? '₹${_formatMoney(entry.creditPaise)}' : '—';
                final bal = entry.runningBalancePaise;
                final balText = '₹${_formatMoney(bal.abs())} ${bal >= 0 ? s.crLabel : s.drLabel}';

                final isPaymentRow = entry.isPayment;

                return DataRow(
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    if (isPaymentRow) {
                      return const Color(0xFFF0FDF4).withValues(alpha: 0.5);
                    }
                    return null;
                  }),
                  cells: [
                    DataCell(Text(dateStr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Text(
                          particulars,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: entry.isPurchase
                              ? const Color(0xFFE0E7FF)
                              : entry.isPayment
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s.localizedEntryType(entry.entryType),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: entry.isPurchase
                                ? const Color(0xFF4338CA)
                                : entry.isPayment
                                    ? const Color(0xFF15803D)
                                    : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(vchNo, style: const TextStyle(fontSize: 13))),
                    DataCell(
                      Text(
                        debitText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: entry.debitPaise > 0 ? FontWeight.bold : FontWeight.normal,
                          color: entry.debitPaise > 0 ? const Color(0xFF047857) : Colors.grey,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        creditText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: entry.creditPaise > 0 ? FontWeight.bold : FontWeight.normal,
                          color: entry.creditPaise > 0 ? const Color(0xFF4338CA) : Colors.grey,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        balText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: bal > 0 ? const Color(0xFFB91C1C) : const Color(0xFF047857),
                        ),
                      ),
                    ),
                    DataCell(
                      isPaymentRow
                          ? Tooltip(
                              message: 'View & Print Payment Voucher / WhatsApp Slip',
                              child: OutlinedButton.icon(
                                onPressed: () => _openVoucherForEntry(entry),
                                icon: const Icon(Icons.receipt_long_rounded, size: 15),
                                label: Text(
                                  s.viewSlip,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4338CA),
                                  side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
                                  backgroundColor: const Color(0xFFEEF2FF),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                              ),
                            )
                          : const Text('—', style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
          // Closing summary footer inside the card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${s.totalRecords} ${_filteredEntries.length}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${s.netClosingBalance} ₹${_formatMoney(_closingBalancePaise.abs())} ${_closingBalancePaise >= 0 ? s.payableSuffix : s.advanceSuffix}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _closingBalancePaise > 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDisplayDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
  }

  static String _formatMoney(int paise) {
    final rs = paise / 100.0;
    return rs.toStringAsFixed(2);
  }
}

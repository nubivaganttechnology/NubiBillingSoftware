import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/expense_model.dart';
import '../../data/repositories/expense_repository.dart';
import '../staff_salary/staff_salary_page.dart';
import '../staff_salary/staff_attendance_page.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';

enum _ExpenseViewMode { table, cards }

enum _ExpenseSortOption { dateDesc, dateAsc, amountDesc, amountAsc, titleAsc }

class ExpenseManagementPage extends StatefulWidget {
  const ExpenseManagementPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ExpenseManagementPage> createState() => _ExpenseManagementPageState();
}

class _ExpenseManagementPageState extends State<ExpenseManagementPage> {
  List<ExpenseModel> _expenses = const [];
  bool _loading = false;
  String? _error;

  final _searchController = TextEditingController();
  String _selectedCategory = 'ALL';
  String _selectedPaymentMode = 'ALL';
  String _dateFilter =
      'THIS_MONTH'; // TODAY, THIS_WEEK, THIS_MONTH, THIS_QUARTER, ALL, CUSTOM
  String _statusFilter = 'ALL'; // ALL, ACTIVE, VOID
  _ExpenseSortOption _sortOption = _ExpenseSortOption.dateDesc;
  _ExpenseViewMode _viewMode = _ExpenseViewMode.table;
  DateTimeRange? _customDateRange;

  final _currencyFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹ ',
    decimalDigits: 2,
  );
  final _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
  final _shortDateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void didUpdateWidget(covariant ExpenseManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.appContext?.businessId !=
            widget.controller.appContext?.businessId ||
        oldWidget.controller.currentOutlet?.outletId !=
            widget.controller.currentOutlet?.outletId) {
      _loadExpenses();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AppController get controller => widget.controller;

  DateTime? get _startDate {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'TODAY':
        return DateTime(now.year, now.month, now.day);
      case 'THIS_WEEK':
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - 1));
      case 'THIS_MONTH':
        return DateTime(now.year, now.month, 1);
      case 'THIS_QUARTER':
        final currentQuarterMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTime(now.year, currentQuarterMonth, 1);
      case 'CUSTOM':
        return _customDateRange?.start;
      default:
        return null;
    }
  }

  DateTime? get _endDate {
    if (_dateFilter == 'CUSTOM' && _customDateRange != null) {
      return DateTime(
        _customDateRange!.end.year,
        _customDateRange!.end.month,
        _customDateRange!.end.day,
        23,
        59,
        59,
      );
    }
    return null;
  }

  Future<void> _loadExpenses() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repo = controller.expenseRepository;

    if (appContext?.businessId == null || token == null || repo == null) {
      if (mounted) {
        setState(() {
          _expenses = const [];
          _error = 'Please select a business to view expenses.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await repo.getExpenses(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        token: token,
      );
      if (mounted) setState(() => _expenses = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddExpenseDialog() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repo = controller.expenseRepository;
    if (appContext?.businessId == null || token == null || repo == null) return;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExpenseFormDialog(controller: controller),
    );

    if (created == true) {
      _loadExpenses();
    }
  }

  Future<void> _showExpenseDetails(ExpenseModel expense) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExpenseDetailsDialog(
        expense: expense,
        currencyFormat: _currencyFormat,
        dateFormat: _dateFormat,
        onVoidRequested: () {
          Navigator.pop(ctx);
          _voidExpense(expense);
        },
      ),
    );
  }

  Future<void> _voidExpense(ExpenseModel expense) async {
    final token = controller.idToken;
    final repo = controller.expenseRepository;
    final l10n = AppLocalizations.of(context);
    if (token == null || repo == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade700,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n?.voidExpenseConfirmTitle ?? 'Void Expense Voucher?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.voidExpenseConfirmMessage ?? 'Are you sure you want to void this expense? This action will mark it as VOIDED and exclude it from active totals.',
              style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          expense.category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _currencyFormat.format(expense.amountRupees),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.block, size: 18),
            label: Text(l10n?.voidExpense ?? 'Void Expense'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await repo.voidExpense(expenseId: expense.expenseId, token: token);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n?.expenseVoidedSuccess ??
                    'Expense voucher voided successfully.',
              ),
              backgroundColor: const Color(0xFF0F172A),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _loadExpenses();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to void expense: $e'),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _exportCsv(List<ExpenseModel> items) async {
    final l10n = AppLocalizations.of(context);
    final buffer = StringBuffer();
    buffer.writeln(
      'Voucher ID,Date,Title,Category,Amount (INR),Payment Mode,Payee,Reference Number,Status,Created By,Notes',
    );

    for (final exp in items) {
      buffer.writeln(
        [
          _csvSafe(exp.expenseId),
          _csvSafe(_dateFormat.format(exp.expenseDate)),
          _csvSafe(exp.title),
          _csvSafe(exp.category),
          exp.amountRupees.toStringAsFixed(2),
          _csvSafe(exp.paymentMode),
          _csvSafe(exp.payeeName ?? ''),
          _csvSafe(exp.referenceNumber ?? ''),
          _csvSafe(exp.status),
          _csvSafe(exp.createdBy ?? ''),
          _csvSafe(exp.notes ?? ''),
        ].join(','),
      );
    }

    final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final fileName = 'expenses_export_$dateStr.csv';

    try {
      final path = await FilePicker.saveFile(
        dialogTitle: l10n?.exportCsv ?? 'Export CSV',
        fileName: fileName,
        bytes: utf8.encode(buffer.toString()),
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.exportCsv ?? "Export CSV"}: $fileName'),
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _csvSafe(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _selectedCategory = 'ALL';
      _selectedPaymentMode = 'ALL';
      _dateFilter = 'ALL';
      _statusFilter = 'ALL';
      _customDateRange = null;
      _sortOption = _ExpenseSortOption.dateDesc;
    });
  }

  bool get _hasActiveFilters {
    return _searchController.text.trim().isNotEmpty ||
        _selectedCategory != 'ALL' ||
        _selectedPaymentMode != 'ALL' ||
        _dateFilter != 'THIS_MONTH' ||
        _statusFilter != 'ALL';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appContext = controller.appContext;
    if (appContext?.businessId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.business_outlined,
                size: 56,
                color: Color(0xFF94A3B8),
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.selectBusiness ??
                    'Select a business to view and manage expenses.',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF334155),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final query = _searchController.text.trim().toLowerCase();
    final start = _startDate;
    final end = _endDate;

    final filtered = _expenses.where((exp) {
      if (start != null && exp.expenseDate.isBefore(start)) return false;
      if (end != null && exp.expenseDate.isAfter(end)) return false;
      if (_selectedCategory != 'ALL' && exp.category != _selectedCategory) {
        return false;
      }
      if (_selectedPaymentMode != 'ALL' &&
          exp.paymentMode != _selectedPaymentMode) {
        return false;
      }
      if (_statusFilter == 'ACTIVE' && !exp.isActive) return false;
      if (_statusFilter == 'VOID' && exp.isActive) return false;

      if (query.isNotEmpty) {
        final titleMatch = exp.title.toLowerCase().contains(query);
        final payeeMatch =
            exp.payeeName?.toLowerCase().contains(query) ?? false;
        final refMatch =
            exp.referenceNumber?.toLowerCase().contains(query) ?? false;
        final notesMatch = exp.notes?.toLowerCase().contains(query) ?? false;
        final idMatch = exp.expenseId.toLowerCase().contains(query);
        if (!titleMatch &&
            !payeeMatch &&
            !refMatch &&
            !notesMatch &&
            !idMatch) {
          return false;
        }
      }
      return true;
    }).toList();

    // Sorting
    filtered.sort((a, b) {
      switch (_sortOption) {
        case _ExpenseSortOption.dateDesc:
          return b.expenseDate.compareTo(a.expenseDate);
        case _ExpenseSortOption.dateAsc:
          return a.expenseDate.compareTo(b.expenseDate);
        case _ExpenseSortOption.amountDesc:
          return b.amountPaise.compareTo(a.amountPaise);
        case _ExpenseSortOption.amountAsc:
          return a.amountPaise.compareTo(b.amountPaise);
        case _ExpenseSortOption.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      }
    });

    // KPI Metrics calculation
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    int todayTotalPaise = 0;
    int todayCashPaise = 0;
    int todayCount = 0;

    int monthTotalPaise = 0;
    int monthCount = 0;

    int digitalTotalPaise = 0;
    int activeVouchersCount = 0;
    int voidedVouchersCount = 0;

    final Map<String, int> categoryTotals = {};

    for (final exp in _expenses) {
      if (exp.isActive) {
        activeVouchersCount++;
        final isToday = !exp.expenseDate.isBefore(todayStart);
        final isThisMonth = !exp.expenseDate.isBefore(monthStart);

        if (isToday) {
          todayTotalPaise += exp.amountPaise;
          todayCount++;
          if (exp.paymentMode == 'CASH') {
            todayCashPaise += exp.amountPaise;
          }
        }

        if (isThisMonth) {
          monthTotalPaise += exp.amountPaise;
          monthCount++;
          categoryTotals[exp.category] =
              (categoryTotals[exp.category] ?? 0) + exp.amountPaise;
          if (exp.paymentMode != 'CASH') {
            digitalTotalPaise += exp.amountPaise;
          }
        }
      } else {
        voidedVouchersCount++;
      }
    }

    final isWide = MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: RefreshIndicator(
        onRefresh: _loadExpenses,
        color: const Color(0xFF0F172A),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
            vertical: MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
          ),
          children: [
            // 1. TOP HEADER & MULTI-LANGUAGE BAR
            _buildExecutiveHeader(context, l10n, filtered),

            const SizedBox(height: 20),

            // 2. 5 INTERACTIVE KPI CARDS
            _buildKpiMetrics(
              context: context,
              l10n: l10n,
              todayTotalPaise: todayTotalPaise,
              todayCount: todayCount,
              monthTotalPaise: monthTotalPaise,
              monthCount: monthCount,
              todayCashPaise: todayCashPaise,
              digitalTotalPaise: digitalTotalPaise,
              activeCount: activeVouchersCount,
              voidedCount: voidedVouchersCount,
            ),

            const SizedBox(height: 20),

            // 3. SPENDING BY CATEGORY ANALYTICS BAR
            if (categoryTotals.isNotEmpty)
              _buildCategoryAnalyticsCard(
                context,
                l10n,
                categoryTotals,
                monthTotalPaise,
              ),

            const SizedBox(height: 20),

            // 4. ADVANCED TOOLBAR (SEARCH + FILTERS + VIEW TOGGLE)
            _buildFilterToolbar(context, l10n, filtered.length),

            const SizedBox(height: 16),

            // 5. MAIN CONTENT (TABLE OR CARDS OR EMPTY)
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0F172A)),
                ),
              )
            else if (_error != null)
              _buildErrorBanner(context)
            else if (filtered.isEmpty)
              _buildEmptyState(context, l10n)
            else if (_viewMode == _ExpenseViewMode.table && isWide)
              _buildModernTableView(context, l10n, filtered)
            else
              _buildCardGridView(context, l10n, filtered),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. EXECUTIVE HEADER
  // ---------------------------------------------------------------------------
  Widget _buildExecutiveHeader(
    BuildContext context,
    AppLocalizations? l10n,
    List<ExpenseModel> currentFiltered,
  ) {
    final isMobile = MediaQuery.sizeOf(context).width < 680;
    final outlet = controller.currentOutlet;
    final currentLocaleCode = controller.currentLocale.languageCode;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF334155).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Badge
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E3A8A), Color(0xFF0F172A)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        Text(
                          l10n?.expensesDashboardTitle ?? 'Expenses & Outflows',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (outlet != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.storefront_outlined,
                                  size: 13,
                                  color: Color(0xFF475569),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  outlet.outletName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n?.expensesDashboardSubtitle ?? 'Track operational overheads, store upkeep, utilities, salaries, and petty cash',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),

          // Action Toolbar & Multi-Language Switcher Row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // In-Place Multi-Language Selector
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.translate_rounded,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 6),
                      Text(
                        '${l10n?.languageSelector ?? "Language"}:',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: currentLocaleCode,
                        isDense: true,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'en',
                            child: Text('🇬🇧 English'),
                          ),
                          DropdownMenuItem(
                            value: 'hi',
                            child: Text('🇮🇳 हिंदी'),
                          ),
                          DropdownMenuItem(
                            value: 'bn',
                            child: Text('🇮🇳 বাংলা'),
                          ),
                        ],
                        onChanged: (newCode) {
                          if (newCode != null) {
                            controller.setLocale(Locale(newCode));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Export CSV & Record Expense buttons
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (controller.canManageStaffAttendance())
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              StaffAttendancePage(controller: controller),
                        ),
                      ),
                      icon: const Icon(Icons.fact_check_outlined, size: 17),
                      label: const Text('Staff Attendance'),
                    ),
                  if (controller.canViewStaffSalary())
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              StaffSalaryPage(controller: controller),
                        ),
                      ),
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 17,
                      ),
                      label: const Text('Staff Salary Khata'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _exportCsv(currentFiltered),
                    icon: const Icon(Icons.file_download_outlined, size: 17),
                    label: Text(l10n?.exportCsv ?? 'Export CSV'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _openAddExpenseDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      l10n?.recordExpense ?? 'Record Expense',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. FIVE INTERACTIVE KPI METRIC CARDS
  // ---------------------------------------------------------------------------
  Widget _buildKpiMetrics({
    required BuildContext context,
    required AppLocalizations? l10n,
    required int todayTotalPaise,
    required int todayCount,
    required int monthTotalPaise,
    required int monthCount,
    required int todayCashPaise,
    required int digitalTotalPaise,
    required int activeCount,
    required int voidedCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1100
            ? 5
            : w >= 700
            ? 3
            : 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Card 1: Today's Expense (tap filters by TODAY)
            _buildKpiCard(
              title: l10n?.todayExpenses ?? "Today's Expense",
              value: _currencyFormat.format(todayTotalPaise / 100.0),
              subtitle:
                  '$todayCount ${l10n?.activeDisbursementsToday ?? "Disbursements today"}',
              icon: Icons.today_rounded,
              accentColor: const Color(0xFF2563EB),
              isSelected: _dateFilter == 'TODAY',
              width: _calculateKpiWidth(w, cols),
              onTap: () {
                setState(() {
                  _dateFilter = _dateFilter == 'TODAY' ? 'ALL' : 'TODAY';
                });
              },
            ),

            // Card 2: This Month's Total (tap filters by THIS_MONTH)
            _buildKpiCard(
              title: l10n?.thisMonthExpenses ?? "This Month's Total",
              value: _currencyFormat.format(monthTotalPaise / 100.0),
              subtitle:
                  '$monthCount ${l10n?.currentBillingPeriod ?? "Current billing period"}',
              icon: Icons.calendar_month_rounded,
              accentColor: const Color(0xFF7C3AED),
              isSelected: _dateFilter == 'THIS_MONTH',
              width: _calculateKpiWidth(w, cols),
              onTap: () {
                setState(() {
                  _dateFilter = _dateFilter == 'THIS_MONTH'
                      ? 'ALL'
                      : 'THIS_MONTH';
                });
              },
            ),

            // Card 3: Cash Outflow Today (tap filters by CASH)
            _buildKpiCard(
              title: l10n?.cashOutflow ?? 'Cash Outflow',
              value: _currencyFormat.format(todayCashPaise / 100.0),
              subtitle: l10n?.disbursedFromTill ?? 'From cash till today',
              icon: Icons.payments_rounded,
              accentColor: const Color(0xFF059669),
              isSelected: _selectedPaymentMode == 'CASH',
              width: _calculateKpiWidth(w, cols),
              onTap: () {
                setState(() {
                  _selectedPaymentMode = _selectedPaymentMode == 'CASH'
                      ? 'ALL'
                      : 'CASH';
                });
              },
            ),

            // Card 4: Digital & Bank (tap filters by non-cash)
            _buildKpiCard(
              title: l10n?.digitalOutflow ?? 'Digital & Bank',
              value: _currencyFormat.format(digitalTotalPaise / 100.0),
              subtitle:
                  l10n?.digitalAndBankSubtitle ?? 'UPI, Bank, Card & Cheque',
              icon: Icons.account_balance_rounded,
              accentColor: const Color(0xFF0284C7),
              isSelected:
                  _selectedPaymentMode == 'UPI' ||
                  _selectedPaymentMode == 'BANK_TRANSFER',
              width: _calculateKpiWidth(w, cols),
              onTap: () {
                setState(() {
                  _selectedPaymentMode = _selectedPaymentMode == 'UPI'
                      ? 'ALL'
                      : 'UPI';
                });
              },
            ),

            // Card 5: Active Records (tap toggles ACTIVE/VOID)
            _buildKpiCard(
              title: l10n?.activeVouchers ?? 'Active Records',
              value: '$activeCount',
              subtitle: voidedCount > 0
                  ? '$voidedCount ${l10n?.statusVoided ?? "Voided"}'
                  : (l10n?.totalExpenseVouchers ?? 'Total vouchers'),
              icon: Icons.verified_user_rounded,
              accentColor: const Color(0xFFD97706),
              isSelected: _statusFilter == 'ACTIVE',
              width: _calculateKpiWidth(w, cols),
              onTap: () {
                setState(() {
                  _statusFilter = _statusFilter == 'ACTIVE' ? 'ALL' : 'ACTIVE';
                });
              },
            ),
          ],
        );
      },
    );
  }

  double _calculateKpiWidth(double totalWidth, int cols) {
    const spacing = 12.0;
    return (totalWidth - (spacing * (cols - 1))) / cols;
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isSelected,
    required double width,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? accentColor : const Color(0xFFE2E8F0),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? accentColor.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: isSelected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: accentColor, size: 18),
                  ),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        AppLocalizations.of(context)?.filtered ?? 'Filtered',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. SPENDING BY CATEGORY ANALYTICS BAR
  // ---------------------------------------------------------------------------
  Widget _buildCategoryAnalyticsCard(
    BuildContext context,
    AppLocalizations? l10n,
    Map<String, int> categoryTotals,
    int totalMonthPaise,
  ) {
    if (totalMonthPaise <= 0) return const SizedBox.shrink();

    // Sort categories descending by amount
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.pie_chart_outline_rounded,
                    size: 18,
                    color: Color(0xFF475569),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n?.spendingByCategory ?? 'Spending by Category',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Text(
                'Total: ${_currencyFormat.format(totalMonthPaise / 100.0)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Multi-Segment Visual Distribution Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: sortedCategories.map((entry) {
                  final ratio = entry.value / totalMonthPaise;
                  return Flexible(
                    flex: (ratio * 1000).toInt().clamp(1, 1000),
                    child: Container(color: _getCategoryColor(entry.key)),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Category Chips Row (Interactive: clicking filters by category)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sortedCategories.take(6).map((entry) {
              final cat = entry.key;
              final amountRupees = entry.value / 100.0;
              final percent = (entry.value / totalMonthPaise * 100)
                  .toStringAsFixed(1);
              final isCurrent = _selectedCategory == cat;
              final color = _getCategoryColor(cat);

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategory = isCurrent ? 'ALL' : cat;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? color.withValues(alpha: 0.15)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent ? color : const Color(0xFFE2E8F0),
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          cat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isCurrent ? color : const Color(0xFF334155),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$percent% (${_formatCompactRupees(amountRupees)})',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. ADVANCED FILTER TOOLBAR
  // ---------------------------------------------------------------------------
  Widget _buildFilterToolbar(
    BuildContext context,
    AppLocalizations? l10n,
    int filteredCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Search Input + Refresh Button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText:
                        l10n?.searchExpensesPlaceholder ??
                        'Search by title, payee, voucher #, notes...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF0F172A),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: l10n?.refresh ?? 'Refresh',
                onPressed: _loadExpenses,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: Color(0xFF334155),
                ),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(11),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Filters Row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Period Preset Dropdown
              _buildFilterDropdown<String>(
                label: l10n?.periodFilter ?? 'Period',
                icon: Icons.calendar_today_rounded,
                value: _dateFilter,
                items: [
                  DropdownMenuItem(
                    value: 'TODAY',
                    child: Text(l10n?.filterPeriodToday ?? 'Today'),
                  ),
                  DropdownMenuItem(
                    value: 'THIS_WEEK',
                    child: Text(l10n?.filterPeriodThisWeek ?? 'This Week'),
                  ),
                  DropdownMenuItem(
                    value: 'THIS_MONTH',
                    child: Text(l10n?.filterPeriodThisMonth ?? 'This Month'),
                  ),
                  DropdownMenuItem(
                    value: 'THIS_QUARTER',
                    child: Text(
                      l10n?.filterPeriodThisQuarter ?? 'This Quarter',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Text(l10n?.filterPeriodAllTime ?? 'All Time'),
                  ),
                  DropdownMenuItem(
                    value: 'CUSTOM',
                    child: Text(l10n?.customDateRange ?? 'Custom range'),
                  ),
                ],
                onChanged: (val) async {
                  if (val == 'CUSTOM') {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange:
                          _customDateRange ??
                          DateTimeRange(
                            start: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            end: DateTime.now(),
                          ),
                    );
                    if (picked != null) {
                      setState(() {
                        _customDateRange = picked;
                        _dateFilter = 'CUSTOM';
                      });
                    }
                  } else if (val != null) {
                    setState(() => _dateFilter = val);
                  }
                },
              ),

              // 2. Category Dropdown
              _buildFilterDropdown<String>(
                label: l10n?.categoryFilter ?? 'Category',
                icon: Icons.category_rounded,
                value: _selectedCategory,
                items: [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Text(l10n?.allCategories ?? 'All Categories'),
                  ),
                  ...ExpenseRepository.defaultCategories.map(
                    (cat) => DropdownMenuItem(value: cat, child: Text(cat)),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),

              // 3. Payment Mode Dropdown
              _buildFilterDropdown<String>(
                label: l10n?.paymentModeFilter ?? 'Mode',
                icon: Icons.payment_rounded,
                value: _selectedPaymentMode,
                items: [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Text(l10n?.allPaymentModes ?? 'All Modes'),
                  ),
                  DropdownMenuItem(
                    value: 'CASH',
                    child: Text(l10n?.paymentModeCash ?? 'Cash'),
                  ),
                  DropdownMenuItem(
                    value: 'UPI',
                    child: Text(l10n?.paymentModeUpi ?? 'UPI'),
                  ),
                  DropdownMenuItem(
                    value: 'BANK_TRANSFER',
                    child: Text(
                      l10n?.paymentModeBankTransfer ?? 'Bank Transfer',
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'CHEQUE',
                    child: Text(l10n?.paymentModeCheque ?? 'Cheque'),
                  ),
                  DropdownMenuItem(
                    value: 'CARD',
                    child: Text(l10n?.paymentModeCard ?? 'Card'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPaymentMode = val);
                },
              ),

              // 4. Status Dropdown
              _buildFilterDropdown<String>(
                label: l10n?.statusFilter ?? 'Status',
                icon: Icons.tune_rounded,
                value: _statusFilter,
                items: [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Text(l10n?.statusAll ?? 'All Status'),
                  ),
                  DropdownMenuItem(
                    value: 'ACTIVE',
                    child: Text(l10n?.statusActive ?? 'Active'),
                  ),
                  DropdownMenuItem(
                    value: 'VOID',
                    child: Text(l10n?.statusVoided ?? 'Voided'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _statusFilter = val);
                },
              ),

              // 5. Sort Dropdown
              _buildFilterDropdown<_ExpenseSortOption>(
                label: l10n?.sortBy ?? 'Sort',
                icon: Icons.sort_rounded,
                value: _sortOption,
                items: [
                  DropdownMenuItem(
                    value: _ExpenseSortOption.dateDesc,
                    child: Text(l10n?.sortDateNewest ?? 'Date: Newest'),
                  ),
                  DropdownMenuItem(
                    value: _ExpenseSortOption.dateAsc,
                    child: Text(l10n?.sortDateOldest ?? 'Date: Oldest'),
                  ),
                  DropdownMenuItem(
                    value: _ExpenseSortOption.amountDesc,
                    child: Text(l10n?.sortAmountHighLow ?? 'Amount: High-Low'),
                  ),
                  DropdownMenuItem(
                    value: _ExpenseSortOption.amountAsc,
                    child: Text(l10n?.sortAmountLowHigh ?? 'Amount: Low-High'),
                  ),
                  DropdownMenuItem(
                    value: _ExpenseSortOption.titleAsc,
                    child: Text(l10n?.sortTitleAz ?? 'Title: A to Z'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _sortOption = val);
                },
              ),

              // 6. View Mode Toggle (Table / Card)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      tooltip: l10n?.viewModeTable ?? 'Table View',
                      color: _viewMode == _ExpenseViewMode.table
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                      onPressed: () =>
                          setState(() => _viewMode = _ExpenseViewMode.table),
                    ),
                    IconButton(
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      tooltip: l10n?.viewModeCards ?? 'Card View',
                      color: _viewMode == _ExpenseViewMode.cards
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                      onPressed: () =>
                          setState(() => _viewMode = _ExpenseViewMode.cards),
                    ),
                  ],
                ),
              ),

              // 7. Reset Filters Button
              if (_hasActiveFilters)
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: Text(l10n?.clearAllFilters ?? 'Clear Filters'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // 8. Result Count Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$filteredCount ${l10n?.records ?? 'records'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isDense: true,
                isExpanded: true,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. MODERN TABLE VIEW (DESKTOP / WIDE)
  // ---------------------------------------------------------------------------
  Widget _buildModernTableView(
    BuildContext context,
    AppLocalizations? l10n,
    List<ExpenseModel> items,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Column Headers
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _tableHeader(l10n?.dateTime ?? 'Date & Time'),
                ),
                Expanded(
                  flex: 4,
                  child: _tableHeader(
                    l10n?.titleOrDescription ?? 'Title / Description',
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _tableHeader(l10n?.categoryFilter ?? 'Category'),
                ),
                Expanded(flex: 3, child: _tableHeader(l10n?.payee ?? 'Payee')),
                Expanded(
                  flex: 2,
                  child: _tableHeader(l10n?.paymentModeFilter ?? 'Mode'),
                ),
                Expanded(
                  flex: 2,
                  child: _tableHeader(
                    l10n?.refVoucherNumber ?? 'Ref / Voucher',
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _tableHeader(
                    l10n?.amountRupees ?? 'Amount',
                    alignRight: true,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _tableHeader(l10n?.statusFilter ?? 'Status'),
                ),
                Expanded(
                  flex: 2,
                  child: _tableHeader(
                    l10n?.actions ?? 'Actions',
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final exp = items[index];
              final isVoid = !exp.isActive;

              return InkWell(
                onTap: () => _showExpenseDetails(exp),
                hoverColor: const Color(0xFFF8FAFC),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // 1. Date & Time
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _shortDateFormat.format(exp.expenseDate),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isVoid
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF0F172A),
                                decoration: isVoid
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            Text(
                              DateFormat('hh:mm a').format(exp.expenseDate),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. Title & Notes
                      Expanded(
                        flex: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exp.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isVoid
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF0F172A),
                                decoration: isVoid
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (exp.notes != null && exp.notes!.isNotEmpty)
                              Text(
                                exp.notes!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),

                      // 3. Category Badge
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildCategoryBadge(exp.category),
                        ),
                      ),

                      // 4. Payee
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                exp.payeeName ?? '—',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isVoid
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF334155),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 5. Payment Mode Badge
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildPaymentModeBadge(
                            context,
                            exp.paymentMode,
                          ),
                        ),
                      ),

                      // 6. Ref / Voucher #
                      Expanded(
                        flex: 2,
                        child: Text(
                          exp.referenceNumber ??
                              exp.expenseId.substring(
                                0,
                                exp.expenseId.length > 8
                                    ? 8
                                    : exp.expenseId.length,
                              ),
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: isVoid
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF475569),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // 7. Amount
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _currencyFormat.format(exp.amountRupees),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isVoid
                                  ? const Color(0xFF94A3B8)
                                  : Colors.red.shade700,
                              decoration: isVoid
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ),

                      // 8. Status Badge
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isVoid
                                  ? const Color(0xFFF1F5F9)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isVoid
                                  ? (l10n?.statusVoided ?? 'VOIDED')
                                  : (l10n?.statusActive ?? 'ACTIVE'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isVoid
                                    ? const Color(0xFF64748B)
                                    : const Color(0xFF15803D),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 9. Actions
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.info_outline_rounded,
                                size: 18,
                              ),
                              color: const Color(0xFF64748B),
                              tooltip: 'Details',
                              onPressed: () => _showExpenseDetails(exp),
                            ),
                            if (exp.isActive)
                              IconButton(
                                icon: const Icon(Icons.block_rounded, size: 18),
                                color: Colors.red.shade400,
                                tooltip: l10n?.voidExpense ?? 'Void Expense',
                                onPressed: () => _voidExpense(exp),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, {bool alignRight = false}) {
    return Text(
      text,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: Color(0xFF64748B),
        letterSpacing: 0.3,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 6. CARD GRID VIEW (MOBILE / TOUCH)
  // ---------------------------------------------------------------------------
  Widget _buildCardGridView(
    BuildContext context,
    AppLocalizations? l10n,
    List<ExpenseModel> items,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 900
            ? 3
            : w >= 550
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: cols == 1 ? 2.3 : 1.9,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final exp = items[index];
            final isVoid = !exp.isActive;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Category + Amount + Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildCategoryBadge(exp.category),
                      Text(
                        _currencyFormat.format(exp.amountRupees),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isVoid
                              ? const Color(0xFF94A3B8)
                              : Colors.red.shade700,
                          decoration: isVoid
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ],
                  ),

                  // Middle Row: Title & Notes
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exp.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isVoid
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF0F172A),
                          decoration: isVoid
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (exp.notes != null && exp.notes!.isNotEmpty)
                        Text(
                          exp.notes!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),

                  // Payee & Mode Row
                  Row(
                    children: [
                      _buildPaymentModeBadge(context, exp.paymentMode),
                      const SizedBox(width: 8),
                      if (exp.payeeName != null && exp.payeeName!.isNotEmpty)
                        Expanded(
                          child: Text(
                            'To: ${exp.payeeName}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),

                  const Divider(height: 1, color: Color(0xFFF1F5F9)),

                  // Footer: Date + Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _shortDateFormat.format(exp.expenseDate),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => _showExpenseDetails(exp),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'View',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          if (exp.isActive) ...[
                            const SizedBox(width: 4),
                            TextButton(
                              onPressed: () => _voidExpense(exp),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                l10n?.voidExpense ?? 'Void',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 7. EMPTY & ERROR STATES
  // ---------------------------------------------------------------------------
  Widget _buildEmptyState(BuildContext context, AppLocalizations? l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.payments_outlined,
                size: 40,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _hasActiveFilters
                  ? (l10n?.noExpensesMatchingFilters ??
                        'No expense vouchers match your active filters.')
                  : (l10n?.noExpensesFound ?? 'No expense records found'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _hasActiveFilters
                  ? 'Try clearing or relaxing your filters above'
                  : (l10n?.noExpensesSubtitle ??
                        'Record operational overheads, utilities, or petty cash to start tracking'),
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_hasActiveFilters)
              OutlinedButton.icon(
                onPressed: _resetFilters,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(l10n?.clearAllFilters ?? 'Clear Filters'),
              )
            else
              FilledButton.icon(
                onPressed: _openAddExpenseDialog,
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n?.recordExpense ?? 'Record First Expense'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error ?? 'An unexpected error occurred.',
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.red.shade700,
            onPressed: _loadExpenses,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPER BADGES
  // ---------------------------------------------------------------------------
  Widget _buildCategoryBadge(String category) {
    final color = _getCategoryColor(category);
    final icon = _getCategoryIcon(category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentModeBadge(BuildContext context, String mode) {
    Color bg;
    Color fg;
    final label = _getPaymentModeLabel(context, mode);

    switch (mode.toUpperCase()) {
      case 'CASH':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        break;
      case 'UPI':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
        break;
      case 'BANK_TRANSFER':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7E22CE);
        break;
      case 'CHEQUE':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        break;
      case 'CARD':
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0369A1);
        break;
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF475569);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// VOUCHER DETAILS DIALOG
// -----------------------------------------------------------------------------
class _ExpenseDetailsDialog extends StatelessWidget {
  const _ExpenseDetailsDialog({
    required this.expense,
    required this.currencyFormat,
    required this.dateFormat,
    required this.onVoidRequested,
  });

  final ExpenseModel expense;
  final NumberFormat currencyFormat;
  final DateFormat dateFormat;
  final VoidCallback onVoidRequested;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isVoid = !expense.isActive;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.receipt_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n?.expenseDetails ?? 'Expense Voucher Details',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            expense.expenseId,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isVoid
                          ? const Color(0xFFF1F5F9)
                          : const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isVoid
                          ? (l10n?.statusVoided ?? 'VOIDED')
                          : (l10n?.statusActive ?? 'ACTIVE'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isVoid
                            ? const Color(0xFF64748B)
                            : const Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Large Amount Hero Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isVoid
                      ? const Color(0xFFF8FAFC)
                      : Colors.red.shade50.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isVoid
                        ? const Color(0xFFE2E8F0)
                        : Colors.red.shade100,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      currencyFormat.format(expense.amountRupees),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: isVoid
                            ? const Color(0xFF94A3B8)
                            : Colors.red.shade700,
                        decoration: isVoid ? TextDecoration.lineThrough : null,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      expense.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isVoid
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF334155),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Specs Grid
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _detailItem(
                    l10n?.categoryFilter ?? 'Category',
                    expense.category,
                  ),
                  _detailItem(
                    l10n?.paymentModeFilter ?? 'Payment Mode',
                    _getPaymentModeLabel(context, expense.paymentMode),
                  ),
                  _detailItem(
                    l10n?.dateTime ?? 'Date & Time',
                    dateFormat.format(expense.expenseDate),
                  ),
                  _detailItem(l10n?.payee ?? 'Payee', expense.payeeName ?? '—'),
                  _detailItem(
                    l10n?.refVoucherNumber ?? 'Reference #',
                    expense.referenceNumber ?? '—',
                  ),
                  _detailItem(
                    l10n?.createdBy ?? 'Created By',
                    expense.createdBy ?? 'System',
                  ),
                ],
              ),

              if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 12),
                Text(
                  l10n?.remarksOrNotes ?? 'Remarks / Notes',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  expense.notes!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF334155),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (expense.isActive)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: onVoidRequested,
                      icon: const Icon(Icons.block_rounded, size: 16),
                      label: Text(l10n?.voidExpense ?? 'Void Voucher'),
                    )
                  else
                    const SizedBox.shrink(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(l10n?.close ?? 'Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailItem(String label, String value) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// RECORD EXPENSE MODAL
// -----------------------------------------------------------------------------
class _ExpenseFormDialog extends StatefulWidget {
  const _ExpenseFormDialog({required this.controller});
  final AppController controller;

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _titleController = TextEditingController();
  final _payeeController = TextEditingController();
  final _refController = TextEditingController();
  final _notesController = TextEditingController();

  String _category = ExpenseRepository.defaultCategories.first;
  String _paymentMode = 'CASH';
  DateTime _expenseDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    _payeeController.dispose();
    _refController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _expenseDate = picked);
    }
  }

  void _addQuickAmount(int rupees) {
    final current = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final updated = current + rupees;
    _amountController.text = updated.toStringAsFixed(0);
    setState(() {});
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    final amountRupees = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amountRupees <= 0) {
      setState(
        () => _error =
            l10n?.amountRequiredError ??
            'Please enter an amount greater than 0',
      );
      return;
    }

    final amountPaise = (amountRupees * 100).round();
    final appContext = widget.controller.appContext;
    final token = widget.controller.idToken;
    final repo = widget.controller.expenseRepository;

    if (appContext?.businessId == null || token == null || repo == null) {
      setState(
        () => _error = 'Session expired. Please reselect your business.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await repo.createExpense(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        outletId: widget.controller.currentOutlet?.outletId,
        title: _titleController.text.trim(),
        category: _category,
        amountPaise: amountPaise,
        expenseDate: _expenseDate,
        paymentMode: _paymentMode,
        payeeName: _payeeController.text.trim().isEmpty
            ? null
            : _payeeController.text.trim(),
        referenceNumber: _refController.text.trim().isEmpty
            ? null
            : _refController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdBy: widget.controller.user?.name,
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.expenseSavedSuccess ??
                  'Expense voucher recorded successfully.',
            ),
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final amountEntered = double.tryParse(_amountController.text.trim()) ?? 0.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.add_shopping_cart_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n?.newExpenseVoucher ?? 'Record New Expense',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Color(0xFFE2E8F0)),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: Colors.red.shade700,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 1. Amount Field + Quick Add Chips
                  TextFormField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: InputDecoration(
                      labelText: '${l10n?.amountRupees ?? "Amount (₹)"} *',
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      hintText: '0.00',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return l10n?.amountRequiredError ??
                            'Amount is required';
                      }
                      final num = double.tryParse(val.trim());
                      if (num == null || num <= 0) {
                        return l10n?.amountRequiredError ??
                            'Enter a valid amount greater than 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Quick Amount Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [100, 500, 1000, 2000, 5000].map((step) {
                      return ActionChip(
                        label: Text('+₹$step'),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _addQuickAmount(step),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 2. Title Field + Common Suggestions
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText:
                          '${l10n?.titleOrDescription ?? "Title / Description"} *',
                      hintText:
                          'e.g., Shop Electricity, Staff Lunch, Rent, Porter',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return l10n?.descriptionRequiredError ??
                            'Description is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 6),

                  // Quick Title Suggestion Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children:
                        [
                          'Shop Electricity',
                          'Staff Refreshments',
                          'Shop Rent',
                          'Courier / Porter',
                          'Packaging Materials',
                          'Office Supplies',
                        ].map((sug) {
                          return ActionChip(
                            label: Text(sug),
                            labelStyle: const TextStyle(fontSize: 10),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onPressed: () {
                              _titleController.text = sug;
                              setState(() {});
                            },
                          );
                        }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // 3. Category & Payment Mode Row
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _category,
                          decoration: InputDecoration(
                            labelText:
                                '${l10n?.categoryFilter ?? "Category"} *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: ExpenseRepository.defaultCategories.map((c) {
                            return DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _category = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _paymentMode,
                          decoration: InputDecoration(
                            labelText:
                                '${l10n?.paymentModeFilter ?? "Payment Mode"} *',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'CASH',
                              child: Text(
                                l10n?.paymentModeCash ?? 'Cash',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'UPI',
                              child: Text(
                                l10n?.paymentModeUpi ?? 'UPI',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'BANK_TRANSFER',
                              child: Text(
                                l10n?.paymentModeBankTransfer ??
                                    'Bank Transfer',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'CHEQUE',
                              child: Text(
                                l10n?.paymentModeCheque ?? 'Cheque',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'CARD',
                              child: Text(
                                l10n?.paymentModeCard ?? 'Card',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _paymentMode = val);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 4. Date Picker & Payee Row
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: l10n?.expenseDate ?? 'Expense Date',
                              suffixIcon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              DateFormat('dd MMM yyyy').format(_expenseDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _payeeController,
                          decoration: InputDecoration(
                            labelText: l10n?.payee ?? 'Paid To (Payee Name)',
                            hintText: 'e.g., Landlord, Porter, Electrician',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 5. Reference & Notes Fields
                  TextFormField(
                    controller: _refController,
                    decoration: InputDecoration(
                      labelText:
                          l10n?.refVoucherNumber ??
                          'Receipt / Voucher / Ref # (Optional)',
                      hintText: 'e.g. REC-1029, UPI Ref #',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText:
                          l10n?.remarksOrNotes ?? 'Remarks / Notes (Optional)',
                      hintText: 'Additional details or memo...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // Live Voucher Preview Banner
                  if (amountEntered > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            color: Color(0xFF0F172A),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Outflow Preview: ₹${amountEntered.toStringAsFixed(2)} via ${_getPaymentModeLabel(context, _paymentMode)} under $_category',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: Text(l10n?.cancel ?? 'Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: Text(
                          _saving
                              ? 'Saving...'
                              : (l10n?.saveExpense ?? 'Save Expense'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// UTILITY FUNCTIONS & COLOR MAPPINGS
// -----------------------------------------------------------------------------

String _getPaymentModeLabel(BuildContext context, String mode) {
  final l10n = AppLocalizations.of(context);
  switch (mode.toUpperCase()) {
    case 'CASH':
      return l10n?.paymentModeCash ?? 'Cash';
    case 'UPI':
      return l10n?.paymentModeUpi ?? 'UPI';
    case 'BANK_TRANSFER':
      return l10n?.paymentModeBankTransfer ?? 'Bank Transfer';
    case 'CHEQUE':
      return l10n?.paymentModeCheque ?? 'Cheque';
    case 'CARD':
      return l10n?.paymentModeCard ?? 'Card';
    default:
      return mode;
  }
}

Color _getCategoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'rent & lease':
      return const Color(0xFF6366F1); // Indigo
    case 'salaries & wages':
      return const Color(0xFF8B5CF6); // Purple
    case 'electricity & utilities':
      return const Color(0xFFF59E0B); // Amber
    case 'freight & delivery':
      return const Color(0xFF0EA5E9); // Sky
    case 'repairs & maintenance':
      return const Color(0xFFEC4899); // Pink
    case 'tea & refreshments':
      return const Color(0xFF10B981); // Emerald
    case 'packaging & materials':
      return const Color(0xFF14B8A6); // Teal
    case 'office & stationery':
      return const Color(0xFF3B82F6); // Blue
    case 'marketing & ads':
      return const Color(0xFFF97316); // Orange
    case 'taxes & bank fees':
      return const Color(0xFFEF4444); // Red
    default:
      return const Color(0xFF64748B); // Slate
  }
}

IconData _getCategoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'rent & lease':
      return Icons.domain_rounded;
    case 'salaries & wages':
      return Icons.people_alt_outlined;
    case 'electricity & utilities':
      return Icons.bolt_rounded;
    case 'freight & delivery':
      return Icons.local_shipping_outlined;
    case 'repairs & maintenance':
      return Icons.build_outlined;
    case 'tea & refreshments':
      return Icons.coffee_outlined;
    case 'packaging & materials':
      return Icons.inventory_2_outlined;
    case 'office & stationery':
      return Icons.edit_note_rounded;
    case 'marketing & ads':
      return Icons.campaign_outlined;
    case 'taxes & bank fees':
      return Icons.account_balance_outlined;
    default:
      return Icons.receipt_long_outlined;
  }
}

String _formatCompactRupees(double amount) {
  if (amount >= 10000000) {
    return '₹${(amount / 10000000).toStringAsFixed(1)}Cr';
  } else if (amount >= 100000) {
    return '₹${(amount / 100000).toStringAsFixed(1)}L';
  } else if (amount >= 1000) {
    return '₹${(amount / 1000).toStringAsFixed(1)}k';
  }
  return '₹${amount.toStringAsFixed(0)}';
}

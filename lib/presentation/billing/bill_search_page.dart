import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/firebase_constants.dart';
import '../../data/models/business_settings_model.dart';
import '../../data/services/firestore_rest_service.dart';
import '../../data/services/offline_firestore_service.dart';
import '../../data/services/invoice_print_service.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../widgets/custom_date_range_dialog.dart';
import 'edit_bill_dialog.dart';
import 'widgets/print_format_dialog.dart';
import 'widgets/upi_qr_widget.dart';

enum RepaymentUrgency { overdue, dueToday, upcoming, noDate }

class RepaymentInfo {
  final DateTime? dueDate;
  final RepaymentUrgency urgency;
  final int daysDifference;

  const RepaymentInfo({
    required this.dueDate,
    required this.urgency,
    required this.daysDifference,
  });
}

class BillSearchPage extends StatefulWidget {
  const BillSearchPage({
    super.key,
    required this.controller,
    this.onNewBill,
    this.embeddedInHub = false,
  });

  final AppController controller;
  final VoidCallback? onNewBill;
  final bool embeddedInHub;

  @override
  State<BillSearchPage> createState() => _BillSearchPageState();
}

class _BillSearchPageState extends State<BillSearchPage> {
  final _billId = TextEditingController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  String _status = 'ALL';
  String _borrowTimelineFilter = 'ALL';
  BusinessSettingsModel? _businessSettings;

  RepaymentInfo _getRepaymentInfo(Map<String, dynamic> fields) {
    final rawDueDate = fields['dueDate'];
    final dueDate = _parseDate(rawDueDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (dueDate != null) {
      final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
      final diff = dueDay.difference(today).inDays;
      if (diff < 0) {
        return RepaymentInfo(
          dueDate: dueDate,
          urgency: RepaymentUrgency.overdue,
          daysDifference: diff.abs(),
        );
      } else if (diff == 0) {
        return RepaymentInfo(
          dueDate: dueDate,
          urgency: RepaymentUrgency.dueToday,
          daysDifference: 0,
        );
      } else {
        return RepaymentInfo(
          dueDate: dueDate,
          urgency: RepaymentUrgency.upcoming,
          daysDifference: diff,
        );
      }
    }

    final rawBillDate =
        fields['invoiceDate'] ?? fields['createdAt'] ?? fields['entryDate'];
    final billDate = _parseDate(rawBillDate);
    if (billDate != null) {
      final billDay = DateTime(billDate.year, billDate.month, billDate.day);
      final diff = today.difference(billDay).inDays;
      return RepaymentInfo(
        dueDate: null,
        urgency: RepaymentUrgency.noDate,
        daysDifference: diff,
      );
    }

    return const RepaymentInfo(
      dueDate: null,
      urgency: RepaymentUrgency.noDate,
      daysDifference: 0,
    );
  }

  List<Map<String, dynamic>> get _displayRows {
    List<Map<String, dynamic>> result;
    if (_status != 'PENDING') {
      result = _rows;
    } else if (_borrowTimelineFilter == 'ALL') {
      result = List<Map<String, dynamic>>.from(_rows);
    } else {
      result = _rows.where((row) {
        final fields = FirestoreRestService.decodeFields(row['fields']);
        final info = _getRepaymentInfo(fields);
        switch (_borrowTimelineFilter) {
          case 'OVERDUE':
            return info.urgency == RepaymentUrgency.overdue ||
                (info.urgency == RepaymentUrgency.noDate &&
                    info.daysDifference > 0);
          case 'DUE_TODAY':
            return info.urgency == RepaymentUrgency.dueToday ||
                (info.urgency == RepaymentUrgency.noDate &&
                    info.daysDifference == 0);
          case 'UPCOMING':
            return info.urgency == RepaymentUrgency.upcoming;
          default:
            return true;
        }
      }).toList();
    }

    if (_status == 'PENDING') {
      result.sort((a, b) {
        final fa = FirestoreRestService.decodeFields(a['fields']);
        final fb = FirestoreRestService.decodeFields(b['fields']);
        final ia = _getRepaymentInfo(fa);
        final ib = _getRepaymentInfo(fb);

        int rank(RepaymentInfo info) {
          if (info.urgency == RepaymentUrgency.overdue ||
              (info.urgency == RepaymentUrgency.noDate &&
                  info.daysDifference > 0)) {
            return 0;
          }
          if (info.urgency == RepaymentUrgency.dueToday ||
              (info.urgency == RepaymentUrgency.noDate &&
                  info.daysDifference == 0)) {
            return 1;
          }
          if (info.urgency == RepaymentUrgency.upcoming) {
            return 2;
          }
          return 3;
        }

        final ra = rank(ia);
        final rb = rank(ib);
        if (ra != rb) return ra.compareTo(rb);

        if (ra == 0) {
          return ib.daysDifference.compareTo(ia.daysDifference);
        }
        if (ra == 2) {
          return ia.daysDifference.compareTo(ib.daysDifference);
        }
        return 0;
      });
    }

    return result;
  }

  String? _currentOutletId;
  String? _currentBusinessId;

  @override
  void initState() {
    super.initState();
    _currentOutletId = widget.controller.appContext?.outletId;
    _currentBusinessId = widget.controller.appContext?.businessId;
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _search();
      _loadBusinessSettings();
    });
  }

  @override
  void didUpdateWidget(BillSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    _onControllerChanged();
  }

  void _onControllerChanged() {
    final newOutletId = widget.controller.appContext?.outletId;
    final newBusinessId = widget.controller.appContext?.businessId;
    if (newOutletId != _currentOutletId ||
        newBusinessId != _currentBusinessId) {
      _currentOutletId = newOutletId;
      _currentBusinessId = newBusinessId;
      if (mounted) {
        _search();
        _loadBusinessSettings();
      }
    }
  }

  Future<void> _loadBusinessSettings() async {
    try {
      final repo = widget.controller.settingsRepository;
      final appContext = widget.controller.appContext;
      final token = widget.controller.idToken;
      if (repo == null || appContext?.businessId == null || token == null) {
        return;
      }
      final s = await repo.loadSettings(
        businessId: appContext!.businessId!,
        tenantId: appContext.ownerUid,
        token: token,
      );
      if (mounted) setState(() => _businessSettings = s);
    } catch (_) {}
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _billId.dispose();
    _customer.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // Top Header
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.salesHistoryAndSearch ?? 'Sales Invoices & History',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Real-time sales ledgers, status filters, payment settlements & receipts',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ],
            );
            final actions = widget.onNewBill == null
                ? const SizedBox.shrink()
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF132B45),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: widget.onNewBill,
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: Text(l10n?.createInvoice ?? 'New Bill'),
                  );
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      title,
                      if (widget.onNewBill != null) ...[
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: title),
                      if (widget.onNewBill != null) actions,
                    ],
                  );
          },
        ),
        const SizedBox(height: 20),

        // Sales KPI Metrics 4-Card Banner
        _buildKpiMetricsBanner(context, l10n),
        const SizedBox(height: 20),

        // Filter Controls Card
        _buildFilterConsole(context, l10n),
        const SizedBox(height: 20),

        if (_loading) const LinearProgressIndicator(),

        if (!_loading && _rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64748B).withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n?.noBillsFound ?? 'No bills found matching filters.',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_startDate != null) ...[
                    Text(
                      'Try widening the date range (${_formatDate(_startDate)} – ${_formatDate(_endDate)})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Try adjusting or clearing your search filters above.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ],
              ),
            ),
          ),

        if (!_loading && _rows.isNotEmpty && _displayRows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 40,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No borrow bills found in this timeline category.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _borrowTimelineFilter = 'ALL'),
                    icon: const Icon(Icons.all_inbox_rounded, size: 16),
                    label: Text(
                      'Show ${l10n?.allPending ?? "All Pending"} (${_rows.length})',
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (!_loading && _displayRows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(
                  _status == 'PENDING' && _borrowTimelineFilter != 'ALL'
                      ? 'Showing ${_displayRows.length} of ${_rows.length} pending bill(s)'
                      : 'Showing ${_displayRows.length} bill(s)${_startDate != null ? ' from ${_formatDate(_startDate)} to ${_formatDate(_endDate)}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Spacer(),
                Text(
                  _status == 'PENDING'
                      ? 'Timeline: ${_borrowTimelineFilter.replaceAll('_', ' ')}'
                      : 'Status: $_status',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

        for (final row in _displayRows) _resultCard(context, row, l10n),
      ],
    );
  }

  Widget _buildKpiMetricsBanner(BuildContext context, AppLocalizations? l10n) {
    final totalCount = _rows.length;
    int totalBilledPaise = 0;
    int totalPaidPaise = 0;
    int totalDuePaise = 0;

    for (final row in _rows) {
      final fields = FirestoreRestService.decodeFields(row['fields']);
      final status = fields['status'] as String? ?? '';
      if (status != 'CANCELLED') {
        totalBilledPaise += (fields['grandTotalPaise'] as num?)?.toInt() ?? 0;
        totalPaidPaise += (fields['paidPaise'] as num?)?.toInt() ?? 0;
        totalDuePaise += (fields['dueAmount'] as num?)?.toInt() ?? 0;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 740;
        final isMobile = constraints.maxWidth < 460;

        final cards = [
          _kpiCard(
            title: l10n?.totalInvoices ?? 'Total Invoices',
            value: '$totalCount',
            subtitle: 'Orders / Bills',
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF132B45),
          ),
          _kpiCard(
            title: l10n?.totalBilled ?? 'Total Billed',
            value: '₹${_money(totalBilledPaise)}',
            subtitle: 'Gross Sales',
            icon: Icons.account_balance_wallet_rounded,
            color: const Color(0xFFC18B35),
          ),
          _kpiCard(
            title: l10n?.totalCollected ?? 'Total Collected',
            value: '₹${_money(totalPaidPaise)}',
            subtitle: 'Received',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF059669),
          ),
          _kpiCard(
            title: l10n?.outstandingDue ?? 'Outstanding Due',
            value: '₹${_money(totalDuePaise)}',
            subtitle: totalDuePaise > 0 ? (l10n?.due ?? 'Due') : 'All Settled',
            icon: Icons.pending_actions_rounded,
            color: totalDuePaise > 0
                ? const Color(0xFFDC2626)
                : const Color(0xFF10B981),
            highlight: totalDuePaise > 0,
          ),
        ];

        if (isMobile) {
          return Column(
            children: cards
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: c,
                  ),
                )
                .toList(),
          );
        }

        if (isNarrow) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
            const SizedBox(width: 12),
            Expanded(child: cards[2]),
            const SizedBox(width: 12),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? color.withValues(alpha: 0.4)
              : const Color(0xFFE2E8F0),
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: highlight ? color : const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (highlight ? color : const Color(0xFF64748B))
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: highlight ? color : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowTimelineBar(BuildContext context, AppLocalizations? l10n) {
    int pendingCount = 0;
    int pendingDuePaise = 0;
    int overdueCount = 0;
    int overdueDuePaise = 0;
    int dueTodayCount = 0;
    int dueTodayDuePaise = 0;
    int upcomingCount = 0;
    int upcomingDuePaise = 0;

    for (final row in _rows) {
      final fields = FirestoreRestService.decodeFields(row['fields']);
      final due = (fields['dueAmount'] as num?)?.toInt() ?? 0;
      final st = fields['status'] as String? ?? '';
      if (due <= 0 && st != 'PENDING') continue;
      if (st == 'CANCELLED' || st == 'RETURN') continue;

      pendingCount++;
      pendingDuePaise += due;

      final info = _getRepaymentInfo(fields);
      if (info.urgency == RepaymentUrgency.overdue ||
          (info.urgency == RepaymentUrgency.noDate &&
              info.daysDifference > 0)) {
        overdueCount++;
        overdueDuePaise += due;
      } else if (info.urgency == RepaymentUrgency.dueToday ||
          (info.urgency == RepaymentUrgency.noDate &&
              info.daysDifference == 0)) {
        dueTodayCount++;
        dueTodayDuePaise += due;
      } else if (info.urgency == RepaymentUrgency.upcoming) {
        upcomingCount++;
        upcomingDuePaise += due;
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: Color(0xFF475569),
              ),
              const SizedBox(width: 6),
              Text(
                l10n?.repaymentTimeline ?? 'Repayment Timeline',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              Text(
                'Total: ₹${_money(pendingDuePaise)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 640;
              final isMobile = constraints.maxWidth < 420;

              final tabs = [
                _timelineFilterCard(
                  key: 'ALL',
                  title: l10n?.allPending ?? 'All Pending',
                  count: pendingCount,
                  amountPaise: pendingDuePaise,
                  icon: Icons.all_inbox_rounded,
                  color: const Color(0xFF132B45),
                ),
                _timelineFilterCard(
                  key: 'OVERDUE',
                  title: l10n?.overdue ?? 'Overdue',
                  count: overdueCount,
                  amountPaise: overdueDuePaise,
                  icon: Icons.warning_amber_rounded,
                  color: const Color(0xFFDC2626),
                  highlight: overdueCount > 0,
                ),
                _timelineFilterCard(
                  key: 'DUE_TODAY',
                  title: l10n?.dueToday ?? 'Due Today',
                  count: dueTodayCount,
                  amountPaise: dueTodayDuePaise,
                  icon: Icons.alarm_on_rounded,
                  color: const Color(0xFFD97706),
                  highlight: dueTodayCount > 0,
                ),
                _timelineFilterCard(
                  key: 'UPCOMING',
                  title: l10n?.upcomingDue ?? 'Upcoming Due',
                  count: upcomingCount,
                  amountPaise: upcomingDuePaise,
                  icon: Icons.event_available_rounded,
                  color: const Color(0xFF2563EB),
                ),
              ];

              if (isMobile) {
                return Column(
                  children: tabs
                      .map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: t,
                        ),
                      )
                      .toList(),
                );
              }

              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: tabs[0]),
                        const SizedBox(width: 8),
                        Expanded(child: tabs[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: tabs[2]),
                        const SizedBox(width: 8),
                        Expanded(child: tabs[3]),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: tabs[0]),
                  const SizedBox(width: 8),
                  Expanded(child: tabs[1]),
                  const SizedBox(width: 8),
                  Expanded(child: tabs[2]),
                  const SizedBox(width: 8),
                  Expanded(child: tabs[3]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _timelineFilterCard({
    required String key,
    required String title,
    required int count,
    required int amountPaise,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    final isSelected = _borrowTimelineFilter == key;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _borrowTimelineFilter = key);
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? color
                  : (highlight
                        ? color.withValues(alpha: 0.4)
                        : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.8 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: isSelected ? color : const Color(0xFF334155),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count · ₹${_money(amountPaise)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? color
                            : (highlight ? color : const Color(0xFF64748B)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 14, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepaymentBanner(
    BuildContext context,
    Map<String, dynamic> row,
    Map<String, dynamic> fields,
    RepaymentInfo info,
    AppLocalizations? l10n, {
    VoidCallback? onDateChanged,
  }) {
    final Color bgColor;
    final Color borderColor;
    final Color accentColor;
    final IconData iconData;
    final String badgeLabel;

    switch (info.urgency) {
      case RepaymentUrgency.overdue:
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        accentColor = const Color(0xFFDC2626);
        iconData = Icons.warning_amber_rounded;
        badgeLabel =
            '⚠️ ${info.daysDifference} ${l10n?.daysOverdueSuffix ?? "days overdue"}';
        break;
      case RepaymentUrgency.dueToday:
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        accentColor = const Color(0xFFD97706);
        iconData = Icons.alarm_rounded;
        badgeLabel = '⏰ ${l10n?.dueToday ?? "Due Today"}';
        break;
      case RepaymentUrgency.upcoming:
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFFBFDBFE);
        accentColor = const Color(0xFF2563EB);
        iconData = Icons.event_available_rounded;
        badgeLabel =
            '📅 ${info.daysDifference} ${l10n?.daysRemainingSuffix ?? "days left"}';
        break;
      case RepaymentUrgency.noDate:
        if (info.daysDifference > 0) {
          bgColor = const Color(0xFFFEF2F2);
          borderColor = const Color(0xFFFECACA);
          accentColor = const Color(0xFFDC2626);
          iconData = Icons.warning_amber_rounded;
          badgeLabel =
              '⚠️ ${info.daysDifference} ${l10n?.daysOverdueSuffix ?? "days overdue"}';
        } else {
          bgColor = const Color(0xFFFFFBEB);
          borderColor = const Color(0xFFFDE68A);
          accentColor = const Color(0xFFD97706);
          iconData = Icons.alarm_rounded;
          badgeLabel = '⏰ ${l10n?.dueToday ?? "Due Today"}';
        }
        break;
    }

    final dueDateStr = info.dueDate != null
        ? _formatDate(info.dueDate)
        : (l10n?.noRepaymentDate ?? 'No Due Date');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(iconData, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${l10n?.repaymentDate ?? "Repayment Date"}: ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                        Text(
                          dueDateStr,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: info.dueDate != null
                                ? accentColor
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _updateDueDate(
                context,
                row,
                fields,
                l10n,
                onUpdated: onDateChanged,
              ),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      info.dueDate == null
                          ? Icons.add_circle_outline
                          : Icons.edit_calendar_outlined,
                      size: 14,
                      color: accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      info.dueDate == null
                          ? (l10n?.setRepaymentDate ?? 'Set Date')
                          : (l10n?.changeRepaymentDate ?? 'Change'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateDueDate(
    BuildContext context,
    Map<String, dynamic> row,
    Map<String, dynamic> fields,
    AppLocalizations? l10n, {
    VoidCallback? onUpdated,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final current =
        _parseDate(fields['dueDate']) ??
        DateTime.now().add(const Duration(days: 15));
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      helpText: l10n?.setRepaymentDueDate ?? 'Select Repayment Due Date',
    );
    if (picked == null || !mounted) return;

    final token = widget.controller.idToken;
    final service = widget.controller.offline;
    final repo = widget.controller.billingRepository;
    final invoiceName = row['name'] as String?;
    if (token == null || invoiceName == null) return;
    final invoiceId = invoiceName.split('/').last;

    try {
      final dueDateValue = _dateOnly(picked);
      if (repo != null) {
        await repo.updateDueDate(
          invoiceId: invoiceId,
          dueDate: picked,
          token: token,
        );
      } else if (service != null) {
        await service.patchDocument(FirebaseConstants.invoices, invoiceId, {
          'dueDate': dueDateValue,
        }, idToken: token);
      }

      fields['dueDate'] = dueDateValue;
      if (row['fields'] is Map) {
        (row['fields'] as Map<String, dynamic>)['dueDate'] = {
          'stringValue': dueDateValue,
        };
      }
      onUpdated?.call();

      if (mounted) {
        await _search();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${l10n?.repaymentDateUpdated ?? "Repayment date updated successfully"}: ${_formatDate(dueDateValue)}',
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to update due date: $e')),
        );
      }
    }
  }

  Widget _buildFilterConsole(BuildContext context, AppLocalizations? l10n) {
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
        children: [
          // Status Chips Row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: _status == 'ALL',
                label: Text(l10n?.allBills ?? 'All Bills'),
                avatar: const Icon(Icons.receipt_long_outlined, size: 16),
                selectedColor: const Color(0xFF132B45).withValues(alpha: 0.12),
                onSelected: (_) {
                  setState(() => _status = 'ALL');
                  _search();
                },
              ),
              FilterChip(
                selected: _status == 'PAID',
                label: Text(l10n?.paidStatus ?? 'Paid'),
                avatar: const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: Color(0xFF059669),
                ),
                selectedColor: const Color(0xFF059669).withValues(alpha: 0.12),
                onSelected: (_) {
                  setState(() => _status = 'PAID');
                  _search();
                },
              ),
              FilterChip(
                selected: _status == 'PENDING',
                label: Text(l10n?.borrowPending ?? 'Borrow / Pending'),
                avatar: const Icon(
                  Icons.pending_outlined,
                  size: 16,
                  color: Color(0xFFDC2626),
                ),
                selectedColor: const Color(0xFFDC2626).withValues(alpha: 0.12),
                onSelected: (_) {
                  setState(() {
                    _status = 'PENDING';
                    _borrowTimelineFilter = 'ALL';
                  });
                  _search();
                },
              ),
              FilterChip(
                selected: _status == 'RETURN',
                label: Text(l10n?.refundReturn ?? 'Refund / Return'),
                avatar: const Icon(
                  Icons.assignment_return_outlined,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
                selectedColor: const Color(0xFF6B7280).withValues(alpha: 0.12),
                onSelected: (_) {
                  setState(() => _status = 'RETURN');
                  _search();
                },
              ),
            ],
          ),
          if (_status == 'PENDING') ...[
            _buildBorrowTimelineBar(context, l10n),
            const SizedBox(height: 14),
          ] else ...[
            const SizedBox(height: 14),
          ],

          // Inputs & Search Controls
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _field(
                _billId,
                l10n?.billId ?? 'Bill ID',
                icon: Icons.tag_rounded,
              ),
              _field(
                _customer,
                l10n?.customerNamePrefix ?? 'Customer Name',
                icon: Icons.person_outline_rounded,
              ),
              _field(
                _phone,
                l10n?.phone ?? 'Phone',
                icon: Icons.phone_outlined,
              ),

              // Custom Date Range Selector
              if (_startDate != null && _endDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF0D9488)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.date_range_rounded,
                        size: 16,
                        color: Color(0xFF0D9488),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDate(_startDate)} – ${_formatDate(_endDate)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                          });
                          _search();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: Color(0xFF0D9488),
                        ),
                      ),
                    ],
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(l10n?.dateRange ?? 'Date Range'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),

              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF132B45),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(l10n?.search ?? 'Search'),
              ),

              if (_startDate != null ||
                  _customer.text.isNotEmpty ||
                  _phone.text.isNotEmpty ||
                  _billId.text.isNotEmpty ||
                  _status != 'ALL')
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _billId.clear();
                      _customer.clear();
                      _phone.clear();
                      _status = 'ALL';
                      _borrowTimelineFilter = 'ALL';
                      _startDate = null;
                      _endDate = null;
                    });
                    _search();
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: Text(l10n?.clearFilters ?? 'Clear Filters'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    IconData? icon,
  }) => SizedBox(
    width: 220,
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        isDense: true,
      ),
      onSubmitted: (_) => _search(),
    ),
  );

  Widget _resultCard(
    BuildContext context,
    Map<String, dynamic> row,
    AppLocalizations? l10n,
  ) {
    final fields = FirestoreRestService.decodeFields(row['fields']);
    final isStaffKhataInvoice =
        fields['chargeType'] == 'STAFF_KHATA' && fields['employeeId'] is String;
    final due =
        ((isStaffKhataInvoice
                    ? fields['outstandingAmount']
                    : fields['dueAmount'])
                as num?)
            ?.toInt() ??
        0;
    final grandTotal = (fields['grandTotalPaise'] as num?)?.toInt() ?? 0;
    final paid = (fields['paidPaise'] as num?)?.toInt() ?? 0;
    final status = fields['status'] as String? ?? '';
    final canCancel = status != 'CANCELLED' && status != 'RETURN';
    final billDateStr = _formatDate(
      fields['invoiceDate'] ?? fields['createdAt'] ?? fields['entryDate'],
    );
    final invoiceNumber =
        fields['invoiceNumber'] as String? ?? row['name'] as String? ?? '';
    final repaymentInfo = _getRepaymentInfo(fields);

    // Color code accent based on status
    final Color statusColor;
    final String statusLabel;
    if (status == 'CANCELLED') {
      statusColor = const Color(0xFFDC2626);
      statusLabel = 'CANCELLED';
    } else if (status == 'RETURN') {
      statusColor = const Color(0xFF7C3AED);
      statusLabel = l10n?.refundReturn ?? 'RETURN';
    } else if (due > 0) {
      statusColor = const Color(0xFFD97706);
      statusLabel = '${l10n?.due ?? 'DUE'} ₹${_money(due)}';
    } else {
      statusColor = const Color(0xFF059669);
      statusLabel = l10n?.paidStatus ?? 'PAID';
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFE2E8F0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: statusColor, width: 4)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Invoice Number, Date, and Status Badge
              Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: invoiceNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $invoiceNumber to clipboard'),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF132B45).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            invoiceNumber,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF132B45),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: Color(0xFF132B45),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (billDateStr.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            billDateStr,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (due > 0 || status == 'PENDING') ...[
                const SizedBox(height: 10),
                _buildRepaymentBanner(
                  context,
                  row,
                  fields,
                  repaymentInfo,
                  l10n,
                ),
              ],
              const SizedBox(height: 12),

              // Middle Row: Customer Info & Financial Summary
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF132B45)
                        .withValues(alpha: 0.1),
                    foregroundColor: const Color(0xFF132B45),
                    radius: 18,
                    child: const Icon(Icons.person, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fields['customerName'] as String? ??
                              'Walk-in Customer',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ((fields['customerPhone'] as String?)?.isNotEmpty ==
                            true)
                          Text(
                            'Phone: ${fields['customerPhone']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total: ₹${_money(grandTotal)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (due > 0)
                        Text(
                          'Paid ₹${_money(paid)} · Due ₹${_money(due)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDC2626),
                          ),
                        )
                      else
                        Text(
                          'Fully Paid (₹${_money(paid)})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF059669),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Action Buttons Row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _showDetails(context, row, fields, l10n),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(l10n?.viewDetail ?? 'View detail'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: canCancel
                        ? () => _editBill(context, row, fields)
                        : null,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(l10n?.editBill ?? 'Edit bill'),
                  ),
                  if (due > 0 &&
                      (fields['customerId'] is String ||
                          (isStaffKhataInvoice &&
                              widget.controller.canChargeStaffKhata()))) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _settle(context, row, fields, l10n),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: Text(l10n?.paySettle ?? 'Pay / Settle'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFF059669),
                        side: const BorderSide(color: Color(0xFF059669)),
                      ),
                      onPressed: () => _settle(
                        context,
                        row,
                        fields,
                        l10n,
                        initialMode: 'UPI',
                      ),
                      icon: const Icon(Icons.qr_code_2, size: 16),
                      label: Text(l10n?.upiQr ?? 'UPI QR'),
                    ),
                  ],
                  if (due > 0)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                        foregroundColor: const Color(0xFF2563EB),
                      ),
                      onPressed: () =>
                          _updateDueDate(context, row, fields, l10n),
                      icon: const Icon(Icons.edit_calendar_outlined, size: 16),
                      label: Text(
                        repaymentInfo.dueDate == null
                            ? (l10n?.setRepaymentDate ?? 'Set Due Date')
                            : (l10n?.changeRepaymentDate ?? 'Change Date'),
                      ),
                    ),
                  if (canCancel)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _cancel(context, row, fields, l10n),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(l10n?.deleteBill ?? 'Delete bill'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    Map<String, dynamic> row,
    Map<String, dynamic> fields,
    AppLocalizations? l10n,
  ) async {
    final token = widget.controller.idToken;
    final service = widget.controller.offline;
    final invoiceName = row['name'] as String?;
    if (token == null || service == null || invoiceName == null) return;
    final invoiceId = invoiceName.split('/').last;
    try {
      final items = await service.queryDocuments(
        collection: FirebaseConstants.invoiceItems,
        filters: [FirestoreFilter('invoiceId', 'EQUAL', invoiceId)],
        orderBy: 'name',
        idToken: token,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: Color(0xFF132B45),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${fields['invoiceNumber'] ?? invoiceId} · ${l10n?.invoiceSummary ?? 'Details'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customer: ${fields['customerName'] ?? 'Walk-in Customer'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if ((fields['customerPhone'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            Text('Phone: ${fields['customerPhone']}'),
                          if ((fields['customerGstin'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            Text('GSTIN: ${fields['customerGstin']}'),
                          if (((fields['dueAmount'] as num?)?.toInt() ?? 0) >
                              0) ...[
                            const SizedBox(height: 8),
                            _buildRepaymentBanner(
                              context,
                              row,
                              fields,
                              _getRepaymentInfo(fields),
                              l10n,
                              onDateChanged: () => setDialogState(() {}),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No line items found for this bill.'),
                      )
                    else
                      ...items.map((item) {
                        final itemFields = FirestoreRestService.decodeFields(
                          item['fields'],
                        );
                        final quantity =
                            (itemFields['quantity'] as num?)?.toInt() ?? 0;
                        final total =
                            (itemFields['lineTotalPaise'] as num?)?.toInt() ??
                            0;
                        final rate =
                            (itemFields['unitPricePaise'] as num?)?.toInt() ??
                            0;
                        final itemName = _itemName(itemFields);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            itemName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '$quantity × ₹${_money(rate)} · '
                            'GST ${((itemFields['gstRateBps'] as num?)?.toInt() ?? 0) / 100}%',
                          ),
                          trailing: Text(
                            '₹${_money(total)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }),
                    const Divider(height: 24),
                    _amountRow('Subtotal', fields['subtotalPaise']),
                    _amountRow('Discount', fields['discountPaise']),
                    _amountRow('Taxable', fields['taxablePaise']),
                    _amountRow(
                      'GST',
                      ((fields['cgstPaise'] as num?)?.toInt() ?? 0) +
                          ((fields['sgstPaise'] as num?)?.toInt() ?? 0) +
                          ((fields['igstPaise'] as num?)?.toInt() ?? 0),
                    ),
                    _amountRow('Paid', fields['paidPaise']),
                    _amountRow('Due', fields['dueAmount']),
                    const Divider(height: 16),
                    _amountRow(
                      'Grand Total',
                      fields['grandTotalPaise'],
                      strong: true,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF132B45),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final invoiceNumber =
                      fields['invoiceNumber'] as String? ?? invoiceId;
                  final printData = _buildPrintData(
                    invoiceNumber: invoiceNumber,
                    fields: fields,
                    items: items,
                  );
                  PrintFormatDialog.show(
                    context: context,
                    data: printData,
                    defaultFormatString: _businessSettings?.printFormat,
                    defaultCustomWidthMm:
                        _businessSettings?.customPrintWidthMm ?? 80.0,
                    onSaveDefaultFormat: (format, customWidth) async {
                      final repo = widget.controller.settingsRepository;
                      final token = widget.controller.idToken;
                      if (repo != null &&
                          _businessSettings != null &&
                          token != null) {
                        final updated = _businessSettings!.copyWith(
                          printFormat: PrintFormatDialog.formatToString(format),
                          customPrintWidthMm: customWidth,
                        );
                        _businessSettings = updated;
                        await repo.saveSettings(
                          settings: updated,
                          token: token,
                        );
                      }
                    },
                  );
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print Bill'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  final invoiceNumber =
                      fields['invoiceNumber'] as String? ?? invoiceId;
                  final printData = _buildPrintData(
                    invoiceNumber: invoiceNumber,
                    fields: fields,
                    items: items,
                  );
                  PrintFormatDialog.show(
                    context: context,
                    data: printData,
                    defaultFormatString: _businessSettings?.printFormat,
                    defaultCustomWidthMm:
                        _businessSettings?.customPrintWidthMm ?? 80.0,
                  );
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share PDF'),
              ),
              if ((fields['status'] as String? ?? '') != 'CANCELLED' &&
                  (fields['status'] as String? ?? '') != 'RETURN')
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _editBill(context, row, fields);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n?.editBill ?? 'Edit bill'),
                ),
              if (((fields['dueAmount'] as num?)?.toInt() ?? 0) > 0 &&
                  fields['customerId'] is String)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _settle(context, row, fields, l10n, initialMode: 'UPI');
                  },
                  icon: const Icon(Icons.qr_code_2),
                  label: Text('${l10n?.paySettle ?? 'Pay Due'} · UPI QR'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _editBill(
    BuildContext context,
    Map<String, dynamic> row,
    Map<String, dynamic> fields,
  ) async {
    await EditBillDialog.show(
      context: context,
      controller: widget.controller,
      row: row,
      fields: fields,
      onBillUpdated: _search,
    );
  }

  InvoicePrintData _buildPrintData({
    required String invoiceNumber,
    required Map<String, dynamic> fields,
    required List<Map<String, dynamic>> items,
  }) {
    final business = widget.controller.businesses
        .where((b) => b.businessId == widget.controller.appContext?.businessId)
        .firstOrNull;

    final lines = <InvoicePrintLine>[];
    for (final item in items) {
      final itemFields = FirestoreRestService.decodeFields(item['fields']);
      lines.add(
        InvoicePrintLine(
          name: _itemName(itemFields),
          hsn: itemFields['hsn'] as String?,
          quantity: (itemFields['quantity'] as num?)?.toDouble() ?? 1.0,
          unit: itemFields['unit'] as String? ?? 'Pcs',
          unitPricePaise: (itemFields['unitPricePaise'] as num?)?.toInt() ?? 0,
          discountPaise: (itemFields['discountPaise'] as num?)?.toInt() ?? 0,
          taxablePaise: (itemFields['taxablePaise'] as num?)?.toInt() ?? 0,
          gstRateBps: (itemFields['gstRateBps'] as num?)?.toInt() ?? 0,
          cgstPaise: (itemFields['cgstPaise'] as num?)?.toInt() ?? 0,
          sgstPaise: (itemFields['sgstPaise'] as num?)?.toInt() ?? 0,
          igstPaise: (itemFields['igstPaise'] as num?)?.toInt() ?? 0,
          lineTotalPaise: (itemFields['lineTotalPaise'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return InvoicePrintData(
      invoiceNumber: invoiceNumber,
      invoiceDate:
          DateTime.tryParse(fields['createdAt'] as String? ?? '') ??
          DateTime.now(),
      businessName: business?.businessName ?? 'NubiBill',
      businessTradeName: business?.gstTradeName,
      businessAddress: business?.address,
      businessGstin: business?.gstin,
      businessPan: business?.gstin != null && business!.gstin!.length >= 12
          ? business.gstin!.substring(2, 12)
          : null,
      businessPhone: business?.phone,
      businessEmail: business?.email,
      businessState: business?.gstState,
      customerName: fields['customerName'] as String?,
      customerPhone: fields['customerPhone'] as String?,
      customerAddress: fields['customerAddress'] as String?,
      customerGstin: fields['customerGstin'] as String?,
      lines: lines,
      subtotalPaise: (fields['subtotalPaise'] as num?)?.toInt() ?? 0,
      discountPaise: (fields['discountPaise'] as num?)?.toInt() ?? 0,
      taxablePaise: (fields['taxablePaise'] as num?)?.toInt() ?? 0,
      cgstPaise: (fields['cgstPaise'] as num?)?.toInt() ?? 0,
      sgstPaise: (fields['sgstPaise'] as num?)?.toInt() ?? 0,
      igstPaise: (fields['igstPaise'] as num?)?.toInt() ?? 0,
      roundOffPaise: (fields['roundOffPaise'] as num?)?.toInt() ?? 0,
      grandTotalPaise: (fields['grandTotalPaise'] as num?)?.toInt() ?? 0,
      paidPaise: (fields['paidPaise'] as num?)?.toInt() ?? 0,
      duePaise: (fields['dueAmount'] as num?)?.toInt() ?? 0,
      paymentMode: fields['paymentMode'] as String? ?? 'Cash',
      upiId: _businessSettings?.upiId,
      bankName: _businessSettings?.bankName,
      bankAccountNumber: _businessSettings?.bankAccountNumber,
      bankIfsc: _businessSettings?.bankIfsc,
      bankAccountName: _businessSettings?.bankAccountName,
      terms: _businessSettings?.invoiceTerms,
      cashierName: fields['cashierUid'] as String?,
      status: fields['status'] as String?,
    );
  }

  String _itemName(Map<String, dynamic> fields) {
    final storedName = fields['name'] as String?;
    final variantId = fields['variantId'] as String?;
    if (variantId != null) {
      for (final product in widget.controller.products) {
        for (final variant in product.variants) {
          if (variant.variantId == variantId) return variant.displayName;
        }
      }
    }
    return storedName?.trim().isNotEmpty == true ? storedName! : 'Item';
  }

  Widget _amountRow(String label, Object? raw, {bool strong = false}) {
    final amount = raw is num ? raw.toInt() : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
          Text(
            '₹${_money(amount)}',
            style: strong ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ],
      ),
    );
  }

  String _money(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.isUtc ? raw.toLocal() : raw;
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) return null;
      // Keep legacy UTC timestamps aligned with the local calendar date. New
      // repayment dates are stored as YYYY-MM-DD and parse as local dates.
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }
    return null;
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _formatDate(dynamic raw) {
    final dt = _parseDate(raw);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showCustomDateRangePicker(
      context: context,
      initialStart: _startDate ?? DateTime.now(),
      initialEnd: _endDate ?? DateTime.now(),
      title: 'Search Bills by Date',
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
    _search();
  }

  Future<void> _search() async {
    try {
      final appContext = widget.controller.appContext;
      OfflineFirestoreService? service;
      try {
        service = widget.controller.offline;
      } catch (_) {}
      String? token;
      try {
        token = widget.controller.idToken;
      } catch (_) {}
      if (appContext?.businessId == null || service == null || token == null) {
        return;
      }
      final businessId = appContext!.businessId!;
      final outletId = appContext.outletId;
      setState(() => _loading = true);
      final custTerm = _customer.text.trim().toLowerCase();
      final hasDateFilter = _startDate != null || _endDate != null;

      final allRows = await service.queryDocuments(
        collection: FirebaseConstants.invoices,
        filters: [
          FirestoreFilter('businessId', 'EQUAL', businessId),
          if (outletId != null && outletId.isNotEmpty)
            FirestoreFilter('outletId', 'EQUAL', outletId),
          if (_billId.text.trim().isNotEmpty)
            FirestoreFilter('invoiceNumber', 'EQUAL', _billId.text.trim()),
          if (_phone.text.trim().isNotEmpty)
            FirestoreFilter('customerPhone', 'EQUAL', _phone.text.trim()),
          if (_status != 'ALL') FirestoreFilter('status', 'EQUAL', _status),
        ],
        orderBy: 'createdAt',
        descending: true,
        limit: (hasDateFilter || custTerm.isNotEmpty || _status == 'PENDING')
            ? 500
            : 35,
        idToken: token,
      );

      _rows = allRows.where((row) {
        final fields = FirestoreRestService.decodeFields(row['fields']);

        // Outlet filter fallback
        if (outletId != null && outletId.isNotEmpty) {
          final rowOutletId = fields['outletId'] as String?;
          if (rowOutletId != null &&
              rowOutletId.isNotEmpty &&
              rowOutletId != outletId) {
            return false;
          }
        }

        // Status filter check
        if (_status == 'PENDING') {
          final due = (fields['dueAmount'] as num?)?.toInt() ?? 0;
          final st = fields['status'] as String? ?? '';
          if (due <= 0 && st != 'PENDING') return false;
          if (st == 'CANCELLED' || st == 'RETURN') return false;
        }

        // 1. Customer name filter (substring / prefix match)
        if (custTerm.isNotEmpty) {
          final cName = (fields['customerName'] as String? ?? '').toLowerCase();
          final cPhone = (fields['customerPhone'] as String? ?? '')
              .toLowerCase();
          if (!cName.contains(custTerm) && !cPhone.contains(custTerm)) {
            return false;
          }
        }

        // 2. Date range filter
        if (hasDateFilter) {
          final rawDate =
              fields['invoiceDate'] ??
              fields['createdAt'] ??
              fields['entryDate'];
          final dt = _parseDate(rawDate);
          if (dt != null) {
            if (_startDate != null) {
              final s = DateTime(
                _startDate!.year,
                _startDate!.month,
                _startDate!.day,
              );
              if (dt.isBefore(s)) return false;
            }
            if (_endDate != null) {
              final e = DateTime(
                _endDate!.year,
                _endDate!.month,
                _endDate!.day,
                23,
                59,
                59,
                999,
              );
              if (dt.isAfter(e)) return false;
            }
          }
        }

        return true;
      }).toList();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _settle(
    BuildContext context,
    Map<String, dynamic> row,
    Map<String, dynamic> fields,
    AppLocalizations? l10n, {
    String initialMode = 'CASH',
  }) async {
    final isStaffKhataInvoice =
        fields['chargeType'] == 'STAFF_KHATA' && fields['employeeId'] is String;
    final duePaise =
        ((isStaffKhataInvoice
                    ? fields['outstandingAmount']
                    : fields['dueAmount'])
                as num?)
            ?.toInt() ??
        0;
    final initialDueText = (duePaise / 100.0).toStringAsFixed(2);
    final amount = TextEditingController(text: initialDueText);
    final mode = ValueNotifier<String>(initialMode);
    final billNum = fields['invoiceNumber'] as String? ?? '';
    final custName = isStaffKhataInvoice
        ? (fields['employeeName'] as String? ?? 'Employee')
        : (fields['customerName'] as String? ?? 'Customer');
    DateTime? nextDueDate = _parseDate(fields['dueDate']);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          int enteredPaise = 0;
          try {
            enteredPaise = _parseMoney(amount.text);
          } catch (_) {}

          return AlertDialog(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.payments_outlined,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${l10n?.paySettle ?? 'Due Settlement'} · Udhaar',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Bill: $billNum',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${isStaffKhataInvoice ? 'Employee' : 'Customer'}: $custName',
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n?.outstandingDue ?? 'Outstanding Due'}: ₹${_money(duePaise)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Settlement Amount (₹)',
                      prefixText: '₹ ',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: mode.value,
                    decoration: const InputDecoration(
                      labelText: 'Payment Mode',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                      DropdownMenuItem(
                        value: 'UPI',
                        child: Text('UPI (Dynamic QR Code)'),
                      ),
                    ],
                    onChanged: (next) {
                      if (next != null) {
                        mode.value = next;
                        setDialogState(() {});
                      }
                    },
                  ),
                  if (!isStaffKhataInvoice && enteredPaise < duePaise) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_outlined,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n?.nextRepaymentDate ??
                                      'Next Repayment Due Date',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E40AF),
                                  ),
                                ),
                                Text(
                                  nextDueDate != null
                                      ? _formatDate(nextDueDate)
                                      : (l10n?.noRepaymentDate ?? 'Not Set'),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate:
                                    nextDueDate ??
                                    now.add(const Duration(days: 15)),
                                firstDate: now,
                                lastDate: now.add(const Duration(days: 365)),
                              );
                              if (picked != null) {
                                setDialogState(() => nextDueDate = picked);
                              }
                            },
                            child: Text(
                              nextDueDate == null
                                  ? (l10n?.setRepaymentDate ?? 'Set')
                                  : (l10n?.changeRepaymentDate ?? 'Change'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (mode.value == 'UPI') ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1B5E20),
                      ),
                      onPressed: enteredPaise <= 0
                          ? null
                          : () async {
                              final confirmed = await showUpiPaymentDialog(
                                context,
                                amount: enteredPaise / 100.0,
                                billNumber: billNum,
                                customerName: custName,
                                note: 'Settle Bill $billNum',
                              );
                              if (confirmed == true && dialogCtx.mounted) {
                                Navigator.pop(dialogCtx, true);
                              }
                            },
                      icon: const Icon(Icons.qr_code_scanner, size: 20),
                      label: Text(
                        'Show Dynamic UPI QR (₹${(enteredPaise / 100.0).toStringAsFixed(2)})',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: Text(l10n?.cancel ?? 'Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF132B45),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogCtx, true),
                child: const Text('Save Settlement'),
              ),
            ],
          );
        },
      ),
    );
    if (result != true || !mounted) return;
    final token = widget.controller.idToken;
    final invoiceId = (row['name'] as String).split('/').last;
    try {
      if (isStaffKhataInvoice) {
        await widget.controller.recordStaffPurchasePayment(
          invoiceId: invoiceId,
          employeeId: fields['employeeId'] as String,
          amountPaise: _parseMoney(amount.text),
          paymentMode: mode.value,
        );
      } else {
        await widget.controller.billingRepository!.settle(
          invoiceId: invoiceId,
          customerId: fields['customerId'] as String,
          amountPaise: _parseMoney(amount.text),
          mode: mode.value,
          paymentAt: DateTime.now(),
          nextDueDate: nextDueDate,
          token: token!,
        );
      }
      await _search();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  int _parseMoney(String value) {
    final normalized = value.trim().replaceAll(',', '');
    final parts = normalized.split('.');
    if (parts.length > 2 ||
        parts.isEmpty ||
        !RegExp(r'^\d+$').hasMatch(parts.first) ||
        (parts.length == 2 && !RegExp(r'^\d{1,2}$').hasMatch(parts[1]))) {
      throw const FormatException('Enter a valid amount in rupees.');
    }
    final rupees = int.parse(parts.first);
    final paise = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
    return rupees * 100 + paise;
  }

  Future<void> _cancel(
    BuildContext context,
    Map<String, dynamic> row,
    Map<String, dynamic> fields,
    AppLocalizations? l10n,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n?.deleteBill ?? 'Cancel bill?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bill: ${fields['invoiceNumber'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This restores stock and reverses customer due/advance. '
              'Any payment is recorded with an immutable reversal entry.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Cancellation reason',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n?.cancel ?? 'Keep bill'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n?.deleteBill ?? 'Cancel bill'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final appContext = widget.controller.appContext;
    final repository = widget.controller.billingRepository;
    final token = widget.controller.idToken;
    final invoiceName = row['name'] as String?;
    if (appContext == null ||
        repository == null ||
        token == null ||
        invoiceName == null) {
      return;
    }
    try {
      await repository.cancel(
        invoiceId: invoiceName.split('/').last,
        actorUid: appContext.uid,
        reason: reason.text,
        token: token,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Bill cancelled and reversed.')),
      );
      if (mounted) {
        await _search();
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      reason.dispose();
    }
  }
}

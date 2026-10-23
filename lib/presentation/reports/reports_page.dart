import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/repositories/reports_repository.dart';
import '../../data/sync/sync_engine.dart';
import '../../domain/reports/report_models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../widgets/custom_date_range_dialog.dart';
import 'audit_report_dialog.dart';
import 'report_export_service.dart';

enum _ExportAction { print, pdf, csv, excel }

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final ReportsRepository _repository;
  StreamSubscription<void>? _syncSubscription;

  DateRangePreset _selectedPreset = DateRangePreset.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;

  late ReportDateRange _currentDateRange;
  ReportsOverviewData _overview = ReportsOverviewData.empty();
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Repository queries local SQLite via the controller's offline service
    _repository = ReportsRepository(
      widget.controller.offline ??
          widget.controller.dashboardRepository.firestore,
    );
    _currentDateRange = ReportDateRange.fromPreset(_selectedPreset);

    // Initial load from local SQLite
    _loadFromSqlite(syncInBackground: true);

    // Reactive sync wakeup: whenever online DB finishes syncing down to SQLite, reload
    if (widget.controller.sync != null) {
      _syncSubscription = widget.controller.sync!.changes.stream.listen((_) {
        if (mounted) {
          _loadFromSqlite(syncInBackground: false);
        }
      });
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  void _onPresetSelected(DateRangePreset preset) async {
    if (preset == DateRangePreset.custom) {
      final picked = await showCustomDateRangePicker(
        context: context,
        initialStart: _customStart ?? _currentDateRange.start,
        initialEnd: _customEnd ?? _currentDateRange.end,
      );
      if (picked == null) return;
      setState(() {
        _selectedPreset = DateRangePreset.custom;
        _customStart = picked.start;
        _customEnd = picked.end;
        _currentDateRange = ReportDateRange.fromPreset(
          DateRangePreset.custom,
          customStart: picked.start,
          customEnd: picked.end,
        );
      });
    } else {
      setState(() {
        _selectedPreset = preset;
        _currentDateRange = ReportDateRange.fromPreset(preset);
      });
    }
    _loadFromSqlite(syncInBackground: false);
  }

  Future<void> _loadFromSqlite({bool syncInBackground = false}) async {
    final ctx = widget.controller.appContext;
    final token = widget.controller.idToken ?? '';
    final tenantId = ctx?.ownerUid ?? ctx?.uid ?? '';
    final businessId = (ctx?.businessId?.isNotEmpty == true)
        ? ctx!.businessId!
        : (widget.controller.businesses.firstOrNull?.businessId ?? '');
    final outletId = (ctx?.outletId?.isNotEmpty == true)
        ? ctx!.outletId!
        : (widget.controller.currentOutlet?.outletId ??
            widget.controller.outlets.firstOrNull?.outletId ??
            '');

    if (businessId.isEmpty || outletId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Select a business and outlet to view reports.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch data dynamically from local SQLite
      final data = await _repository.loadOverview(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        dateRange: _currentDateRange,
        token: token,
      );

      if (mounted) {
        setState(() {
          _overview = data;
          _isLoading = false;
        });
      }

      // 2. In background, schedule/trigger sync from online DB to SQLite
      if (syncInBackground && widget.controller.sync != null) {
        unawaited(
          widget.controller.sync!.sync().catchError((e) {
            // Background sync errors are handled gracefully without blocking offline view
          }),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Report failed to load: $e';
        });
      }
    }
  }

  void _openDetailReport(ReportTileId tileId) async {
    if (tileId == ReportTileId.completeAuditReport) {
      _openCompleteAuditDialog();
      return;
    }

    final ctx = widget.controller.appContext;
    final token = widget.controller.idToken ?? '';
    final tenantId = ctx?.ownerUid ?? ctx?.uid ?? '';
    final businessId = (ctx?.businessId?.isNotEmpty == true)
        ? ctx!.businessId!
        : (widget.controller.businesses.firstOrNull?.businessId ?? '');
    final outletId = (ctx?.outletId?.isNotEmpty == true)
        ? ctx!.outletId!
        : (widget.controller.currentOutlet?.outletId ??
            widget.controller.outlets.firstOrNull?.outletId ??
            '');
    final businessName =
        widget.controller.businesses
            .where((b) => b.businessId == businessId)
            .firstOrNull
            ?.businessName ??
        widget.controller.businesses.firstOrNull?.businessName ??
        'Business';
    final outletName =
        widget.controller.currentOutlet?.outletName ??
        widget.controller.outlets.firstOrNull?.outletName ??
        'Outlet';

    var loadingDismissed = false;
    void dismissLoading() {
      if (!loadingDismissed && mounted) {
        loadingDismissed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final detail = await _repository.loadDetailReport(
        tileId: tileId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        businessName: businessName,
        outletName: outletName,
        dateRange: _currentDateRange,
        token: token,
        includeSalaryData: widget.controller.canViewStaffSalary(),
      );
      dismissLoading();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: _ReportDetailDialog(report: detail),
        ),
      );
    } catch (e) {
      dismissLoading();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load report detail: $e')),
      );
    }
  }

  Future<AuditScopeSelection?> _chooseAuditScope() async {
    late AuditScopeOptions choices;
    try {
      choices = await _repository.loadAuditScopeOptions(
        tenantId: widget.controller.appContext?.ownerUid ?? '',
        token: widget.controller.idToken ?? '',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Report scope unavailable: $e')));
      }
      return null;
    }
    if (!mounted) return null;
    var mode = AuditScopeMode.selectedOutlet;
    final selectedOutlets = <String>{
      widget.controller.appContext?.outletId ?? '',
    };
    final selectedBusinesses = <String>{
      widget.controller.appContext?.businessId ?? '',
    };
    return showDialog<AuditScopeSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          return AlertDialog(
            title: const Text('Financial report scope'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Period: ${_currentDateRange.formatLabel()} (India calendar dates)',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<AuditScopeMode>(
                      initialValue: mode,
                      isExpanded: true,
                      items: AuditScopeMode.values
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(
                                v.label,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) update(() => mode = v);
                      },
                    ),
                    if (mode == AuditScopeMode.allOutletsInBusiness)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'Includes authorized active and historical outlets. Unavailable data is disclosed in the report.',
                        ),
                      ),
                    if (mode == AuditScopeMode.selectedOutletsInBusiness)
                      for (final outlet in choices.outlets.where(
                        (o) =>
                            o.businessId ==
                            widget.controller.appContext?.businessId,
                      ))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${outlet.name}${outlet.isActive ? '' : ' (historical)'}',
                          ),
                          subtitle: Text(outlet.id),
                          value: selectedOutlets.contains(outlet.id),
                          onChanged: (value) => update(() {
                            value == true
                                ? selectedOutlets.add(outlet.id)
                                : selectedOutlets.remove(outlet.id);
                          }),
                        ),
                    if (mode ==
                        AuditScopeMode.combinedAuthorizedBusinesses) ...[
                      const Text(
                        'Select compatible businesses explicitly. Each selected business includes all authorized outlets; GST schedules remain separate for each business.',
                      ),
                      for (final business in choices.businesses)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${business.name}${business.isActive ? '' : ' (historical)'}',
                          ),
                          subtitle: Text(business.id),
                          value: selectedBusinesses.contains(business.id),
                          onChanged: (value) => update(() {
                            value == true
                                ? selectedBusinesses.add(business.id)
                                : selectedBusinesses.remove(business.id);
                          }),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    (mode == AuditScopeMode.selectedOutletsInBusiness &&
                            selectedOutlets.isEmpty) ||
                        (mode == AuditScopeMode.combinedAuthorizedBusinesses &&
                            selectedBusinesses.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(
                          dialogContext,
                          AuditScopeSelection(
                            mode: mode,
                            outletsByBusiness: {
                              if (mode ==
                                  AuditScopeMode.selectedOutletsInBusiness)
                                (widget.controller.appContext?.businessId ??
                                        widget.controller.businesses.firstOrNull
                                            ?.businessId ??
                                        ''):
                                    selectedOutlets.toList(),
                              if (mode ==
                                  AuditScopeMode.combinedAuthorizedBusinesses)
                                for (final id in selectedBusinesses)
                                  id: <String>[],
                            },
                          ),
                        );
                      },
                child: const Text('Generate report'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openCompleteAuditDialog({
    bool autoPdf = false,
    bool autoExcel = false,
  }) async {
    final ctx = widget.controller.appContext;
    final token = widget.controller.idToken ?? '';
    final tenantId = ctx?.ownerUid ?? ctx?.uid ?? '';
    final businessId = (ctx?.businessId?.isNotEmpty == true)
        ? ctx!.businessId!
        : (widget.controller.businesses.firstOrNull?.businessId ?? '');
    final outletId = (ctx?.outletId?.isNotEmpty == true)
        ? ctx!.outletId!
        : (widget.controller.currentOutlet?.outletId ??
            widget.controller.outlets.firstOrNull?.outletId ??
            '');
    final currentBusiness = widget.controller.businesses
        .where((b) => b.businessId == businessId)
        .firstOrNull;
    final businessName =
        currentBusiness?.businessName ??
        widget.controller.businesses.firstOrNull?.businessName ??
        'Business';
    final outletName =
        widget.controller.currentOutlet?.outletName ??
        widget.controller.outlets.firstOrNull?.outletName ??
        'Outlet';

    final scope = await _chooseAuditScope();
    if (scope == null || !mounted) return;

    var loadingDismissed = false;
    void dismissLoading() {
      if (!loadingDismissed && mounted) {
        loadingDismissed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final compact = MediaQuery.sizeOf(dialogContext).width < 420;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(dialogContext).width - 32,
            ),
            child: Card(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 18 : 24,
                  vertical: 16,
                ),
                child: compact
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5),
                          SizedBox(height: 12),
                          Text(
                            'Compiling financial reconciliation...',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2.5),
                          SizedBox(width: 16),
                          Text('Compiling financial reconciliation...'),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final audit = await _repository.loadCompleteAuditReport(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        businessName: businessName,
        outletName: outletName,
        dateRange: _currentDateRange,
        token: token,
        gstin: currentBusiness?.gstin,
        tradeName: currentBusiness?.gstTradeName,
        legalName: currentBusiness?.gstLegalName,
        address: currentBusiness?.address,
        phone: currentBusiness?.phone,
        email: currentBusiness?.email,
        includeSalaryData: widget.controller.canViewStaffSalary(),
        scope: scope,
      );

      dismissLoading();
      if (!mounted) return;

      if (autoPdf) {
        final path = await ReportExportService.saveAuditPdf(audit);
        if (mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audit PDF saved: $path'),
              backgroundColor: const Color(0xFF0D9488),
            ),
          );
        }
        return;
      }

      if (autoExcel) {
        final path = await ReportExportService.exportAuditExcel(audit);
        if (mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Audit Excel saved: $path'),
              backgroundColor: const Color(0xFF0D9488),
            ),
          );
        }
        return;
      }

      showDialog(
        context: context,
        builder: (_) => AuditReportDialog(audit: audit),
      );
    } catch (e) {
      dismissLoading();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to compile audit report: $e')),
      );
    }
  }

  Future<void> _exportPeriodReport(_ExportAction action) async {
    final ctx = widget.controller.appContext;
    final token = widget.controller.idToken ?? '';
    final tenantId = ctx?.ownerUid ?? ctx?.uid ?? '';
    final businessId = (ctx?.businessId?.isNotEmpty == true)
        ? ctx!.businessId!
        : (widget.controller.businesses.firstOrNull?.businessId ?? '');
    final outletId = (ctx?.outletId?.isNotEmpty == true)
        ? ctx!.outletId!
        : (widget.controller.currentOutlet?.outletId ??
            widget.controller.outlets.firstOrNull?.outletId ??
            '');
    final businessName =
        widget.controller.businesses
            .where((b) => b.businessId == businessId)
            .firstOrNull
            ?.businessName ??
        widget.controller.businesses.firstOrNull?.businessName ??
        'Business';
    final outletName =
        widget.controller.currentOutlet?.outletName ??
        widget.controller.outlets.firstOrNull?.outletName ??
        'Outlet';

    if (businessId.isEmpty || outletId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a business and outlet to export reports.'),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Preparing report export...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final detail = await _repository.loadDetailReport(
        tileId: ReportTileId.salesSummary,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        businessName: businessName,
        outletName: outletName,
        dateRange: _currentDateRange,
        token: token,
      );

      String? result;
      switch (action) {
        case _ExportAction.print:
          await ReportExportService.printReport(detail);
          return;
        case _ExportAction.pdf:
          result = await ReportExportService.savePdf(detail);
          break;
        case _ExportAction.csv:
          result = await ReportExportService.exportCsv(detail);
          break;
        case _ExportAction.excel:
          result = await ReportExportService.exportExcel(detail);
          break;
      }

      if (mounted && result != null && result.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('File saved successfully: $result'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _showLanguageSelectorDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentCode = widget.controller.currentLocale.languageCode;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.language_rounded,
              color: Color(0xFF0D9488),
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(l10n?.selectLanguage ?? 'Select Language'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageOption(
              context: dialogCtx,
              locale: const Locale('en'),
              nativeName: 'English',
              subLabel: 'Default / International',
              isSelected: currentCode == 'en',
            ),
            const Divider(height: 1),
            _buildLanguageOption(
              context: dialogCtx,
              locale: const Locale('hi'),
              nativeName: 'हिंदी',
              subLabel: 'Hindi • भारत की आधिकारिक भाषा',
              isSelected: currentCode == 'hi',
            ),
            const Divider(height: 1),
            _buildLanguageOption(
              context: dialogCtx,
              locale: const Locale('bn'),
              nativeName: 'বাংলা',
              subLabel: 'Bengali • পশ্চিমবঙ্গ ও আঞ্চলিক ভাষা',
              isSelected: currentCode == 'bn',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOption({
    required BuildContext context,
    required Locale locale,
    required String nativeName,
    required String subLabel,
    required bool isSelected,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: isSelected,
      selectedTileColor: const Color(0xFF0D9488).withValues(alpha: 0.08),
      leading: Icon(
        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
        color: isSelected ? const Color(0xFF0D9488) : Colors.black38,
      ),
      title: Text(
        nativeName,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text(subLabel, style: const TextStyle(fontSize: 11)),
      onTap: () {
        widget.controller.setLocale(locale);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentLocale = widget.controller.currentLocale;
    final businessId = widget.controller.appContext?.businessId;
    final businessName =
        widget.controller.businesses
            .where((b) => b.businessId == businessId)
            .firstOrNull
            ?.businessName ??
        '[YOUR BUSINESS]';
    final outletName =
        widget.controller.currentOutlet?.outletName ?? '[OUTLET NAME]';
    final isSyncing = widget.controller.sync?.state == SyncState.syncing;

    final langLabel = currentLocale.languageCode == 'hi'
        ? 'हिंदी (Hindi)'
        : (currentLocale.languageCode == 'bn' ? 'বাংলা (Bengali)' : 'English');
    final contextControls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFE2F3EB),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF0D9488),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                'Local SQLite • Dynamic',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F766E),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: () => _showLanguageSelectorDialog(context),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1)),
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
                const Icon(
                  Icons.language_rounded,
                  size: 14,
                  color: Color(0xFF0D9488),
                ),
                const SizedBox(width: 6),
                Text(
                  langLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: Color(0xFF64748B),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final breadcrumb = Text(
      '${l10n?.business ?? "Business"}: $businessName   ›   ${l10n?.outlet ?? "Outlet"}: $outletName',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 12,
        color: Color(0xFF5A6A7E),
        fontWeight: FontWeight.w500,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F9),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 28,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Breadcrumb, Sync Tag, and Multi-Language Switcher
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 620
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        breadcrumb,
                        const SizedBox(height: 8),
                        contextControls,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: breadcrumb),
                        const SizedBox(width: 12),
                        contextControls,
                      ],
                    ),
            ),
            const SizedBox(height: 14),

            // Header: Title, Freshness, and Top Action Buttons
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 800;
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.reportsNavTitle ?? 'Reports & Analytics',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 3,
                      children: [
                        Text(
                          'Generated ${_formatTimestamp(_overview.generatedAt)} · Data up to now',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        InkWell(
                          onTap: isSyncing
                              ? null
                              : () => _loadFromSqlite(syncInBackground: true),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: isSyncing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.refresh,
                                    size: 16,
                                    color: Color(0xFF0D9488),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _TopActionButton(
                      label: 'Print',
                      onPressed: () =>
                          _exportPeriodReport(_ExportAction.print),
                    ),
                    _TopActionButton(
                      label: 'Save PDF',
                      onPressed: () =>
                          _exportPeriodReport(_ExportAction.pdf),
                    ),
                    _TopActionButton(
                      label: 'Export CSV',
                      onPressed: () =>
                          _exportPeriodReport(_ExportAction.csv),
                    ),
                  ],
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title,
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: title),
                          actions,
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),

            // ⚡ HERO ONE-CLICK FINANCIAL AUDIT BANNER
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E293B),
                    Color(0xFF0F766E),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final icon = Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2DD4BF), Color(0xFF0D9488)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  );
                  final summary = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          Text(
                            l10n?.oneClickAuditHeroTitle ??
                                'Automated Financial Reconciliation',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14B8A6)
                                  .withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF2DD4BF)
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            child: Text(
                              l10n?.statutoryComplianceBadge ??
                                  'Evidence-based review',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5EEAD4),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        l10n?.oneClickAuditHeroSubtitle ?? 'Review persisted financial records with source evidence and disclosed limitations.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFCBD5E1),
                          height: 1.3,
                        ),
                      ),
                    ],
                  );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _openCompleteAuditDialog(),
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: Text(
                          l10n?.launchCompleteAudit ?? 'Launch Complete Audit',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _openCompleteAuditDialog(autoPdf: true),
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                        label: Text(l10n?.downloadAuditPdf ?? 'Audit PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _openCompleteAuditDialog(autoExcel: true),
                        icon: const Icon(
                          Icons.table_chart_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                        label: Text(l10n?.downloadAuditExcel ?? 'Audit Excel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  );

                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: 12),
                            Expanded(child: summary),
                          ],
                        ),
                        const SizedBox(height: 14),
                        actions,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: 18),
                      Expanded(child: summary),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 18),

            // Date Range Presets Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final preset in DateRangePreset.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _DatePresetPill(
                        label: preset.label,
                        isSelected: _selectedPreset == preset,
                        onTap: () => _onPresetSelected(preset),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _loadFromSqlite(syncInBackground: true),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // 4 KPI Cards
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // Executive Stat Cards
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = (constraints.maxWidth / 210).floor().clamp(
                    1,
                    5,
                  );
                  final width = math.max(
                    0.0,
                    (constraints.maxWidth - ((columns - 1) * 16)) / columns,
                  );
                  return Wrap(
                    spacing: 16,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: width,
                        child: _ModernKpiCard(
                          title: 'Total Revenue',
                          value: _formatMoney(_overview.netSalesPaise),
                          subValue: _overview.salesGrowthPercentage != null
                              ? '${_overview.salesGrowthPercentage! >= 0 ? '+' : ''}${_overview.salesGrowthPercentage!.toStringAsFixed(1)}% vs previous'
                              : 'Period: ${_currentDateRange.formatLabel()}',
                          growthPositive:
                              _overview.salesGrowthPercentage != null
                              ? _overview.salesGrowthPercentage! >= 0
                              : null,
                          icon: Icons.account_balance_wallet_rounded,
                          iconBg: const Color(0xFFE6F7F5),
                          iconColor: const Color(0xFF0D9488),
                          onTap: () =>
                              _openDetailReport(ReportTileId.salesSummary),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _ModernKpiCard(
                          title: l10n?.grossProfitLabel ?? 'Gross Profit & Margin',
                          value: _formatMoney(_overview.grossProfitPaise),
                          subValue: _overview.grossProfitMarginPercentage != null
                              ? '${_overview.grossProfitMarginPercentage! >= 0 ? '+' : ''}${_overview.grossProfitMarginPercentage!.toStringAsFixed(1)}% margin'
                              : 'Estimated gross profit',
                          growthPositive: _overview.grossProfitPaise >= 0,
                          icon: Icons.trending_up_rounded,
                          iconBg: const Color(0xFFF0FDF4),
                          iconColor: const Color(0xFF16A34A),
                          onTap: () =>
                              _openDetailReport(ReportTileId.profitEstimate),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _ModernKpiCard(
                          title: 'Purchases & Outflow',
                          value: _formatMoney(_overview.purchasesPaise),
                          subValue: _overview.purchasesToSalesRatio != null
                              ? '${_overview.purchasesToSalesRatio!.toStringAsFixed(0)}% of sales revenue'
                              : 'Period outflow',
                          growthPositive: null,
                          icon: Icons.shopping_bag_outlined,
                          iconBg: const Color(0xFFEEF2FF),
                          iconColor: const Color(0xFF4E45D5),
                          onTap: () =>
                              _openDetailReport(ReportTileId.purchaseSummary),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _ModernKpiCard(
                          title: 'Receivables Due',
                          value: _formatMoney(
                            _overview.receivablesOutstandingPaise,
                          ),
                          subValue:
                              'Collected ${_formatMoney(_overview.collectedPaise)}',
                          growthPositive:
                              _overview.receivablesOutstandingPaise == 0,
                          icon: Icons.pending_actions_rounded,
                          iconBg: const Color(0xFFFEF3C7),
                          iconColor: const Color(0xFFD97706),
                          onTap: () => _openDetailReport(
                            ReportTileId.outstandingReceivables,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: width,
                        child: _ModernKpiCard(
                          title: 'Inventory SKUs',
                          value: _overview.totalSkusCount > 0
                              ? '${_overview.totalSkusCount} SKUs'
                              : '${_overview.lowStockCount} Alerts',
                          subValue: _overview.lowStockCount > 0
                              ? '${_overview.lowStockCount} items need restock'
                              : '${_overview.expiringBatchesCount} batches expire soon',
                          growthPositive: _overview.lowStockCount == 0,
                          icon: Icons.inventory_2_outlined,
                          iconBg: _overview.lowStockCount > 0
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFF1F5F9),
                          iconColor: _overview.lowStockCount > 0
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF475569),
                          onTap: () =>
                              _openDetailReport(ReportTileId.lowStockReorder),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // Hero Revenue vs Expenses Trend Chart
              _ExecutiveRevenueExpenseChart(
                points: _overview.trendPoints,
                onViewSalesSummary: () =>
                    _openDetailReport(ReportTileId.salesSummary),
              ),
              const SizedBox(height: 24),

              // Secondary Visual Analytics Grid (Donut Chart + Horizontal Bar Chart + Inventory Health)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 920;
                  if (isWide) {
                    final colWidth = (constraints.maxWidth - (2 * 18)) / 3;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: colWidth,
                          child: _CollectionDonutChart(
                            collectedPaise: _overview.collectedPaise,
                            outstandingPaise:
                                _overview.receivablesOutstandingPaise,
                            overduePaise: _overview.overdueReceivablesPaise,
                            onViewReceivables: () => _openDetailReport(
                              ReportTileId.outstandingReceivables,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        SizedBox(
                          width: colWidth,
                          child: _CategorySalesBarChart(
                            categories: _overview.topCategories,
                            onViewProductSales: () =>
                                _openDetailReport(ReportTileId.productSales),
                          ),
                        ),
                        const SizedBox(width: 18),
                        SizedBox(
                          width: colWidth,
                          child: _InventoryHealthCard(
                            totalSkus: _overview.totalSkusCount,
                            lowStockCount: _overview.lowStockCount,
                            expiringBatchesCount:
                                _overview.expiringBatchesCount,
                            onRestock: () =>
                                _openDetailReport(ReportTileId.lowStockReorder),
                            onViewExpiry: () =>
                                _openDetailReport(ReportTileId.batchExpiry),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _CollectionDonutChart(
                          collectedPaise: _overview.collectedPaise,
                          outstandingPaise:
                              _overview.receivablesOutstandingPaise,
                          overduePaise: _overview.overdueReceivablesPaise,
                          onViewReceivables: () => _openDetailReport(
                            ReportTileId.outstandingReceivables,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _CategorySalesBarChart(
                          categories: _overview.topCategories,
                          onViewProductSales: () =>
                              _openDetailReport(ReportTileId.productSales),
                        ),
                        const SizedBox(height: 18),
                        _InventoryHealthCard(
                          totalSkus: _overview.totalSkusCount,
                          lowStockCount: _overview.lowStockCount,
                          expiringBatchesCount: _overview.expiringBatchesCount,
                          onRestock: () =>
                              _openDetailReport(ReportTileId.lowStockReorder),
                          onViewExpiry: () =>
                              _openDetailReport(ReportTileId.batchExpiry),
                        ),
                      ],
                    );
                  }
                },
              ),
              const SizedBox(height: 32),

              // Report Tile Groups
              _buildReportSection(
                title:
                    l10n?.auditsAndStatutory ??
                    'Financial review and tax schedules',
                tiles: [
                  ReportTileId.completeAuditReport,
                  ReportTileId.gstSalesSummary,
                  ReportTileId.gstPurchaseSummary,
                  ReportTileId.profitEstimate,
                ],
              ),
              const SizedBox(height: 28),

              _buildReportSection(
                title: l10n?.salesAndCollections ?? 'Sales and collections',
                tiles: [
                  ReportTileId.salesSummary,
                  ReportTileId.salesRegister,
                  ReportTileId.productSales,
                  ReportTileId.salesForecast,
                  ReportTileId.outstandingReceivables,
                ],
              ),
              const SizedBox(height: 28),

              _buildReportSection(
                title: l10n?.purchasesAndInventory ?? 'Purchases and inventory',
                tiles: [
                  ReportTileId.purchaseSummary,
                  ReportTileId.stockMovement,
                  ReportTileId.batchExpiry,
                  ReportTileId.lowStockReorder,
                ],
              ),
              const SizedBox(height: 28),

              _buildReportSection(
                title: l10n?.taxAndProfit ?? 'Tax and profit',
                tiles: [
                  ReportTileId.profitEstimate,
                  ReportTileId.expenseCashFlow,
                ],
              ),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReportSection({
    required String title,
    required List<ReportTileId> tiles,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 240).floor().clamp(1, 4);
            final width = math.max(
              0.0,
              (constraints.maxWidth - ((columns - 1) * 16)) / columns,
            );
            return Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: width,
                    child: _ReportTileCard(
                      id: tile,
                      status:
                          _overview.tileStatuses[tile] ??
                          ReportTileStatus.ready,
                      onTap: () => _openDetailReport(tile),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _formatTimestamp(DateTime dt) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year}, ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  String _formatMoney(int paise) {
    final isNeg = paise < 0;
    final abs = paise.abs();
    final rupees = abs ~/ 100;
    final s = rupees.toString();
    if (s.length <= 3) return '${isNeg ? '-' : ''}₹ $s';
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final buffer = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) buffer.write(',');
      buffer.write(rest[i]);
    }
    return '${isNeg ? '-' : ''}₹ ${buffer.toString()},$last3';
  }
}

// -----------------------------------------------------------------------------
// WIDGETS MATCHING SCREENSHOT PIXEL-ACCURATELY
// -----------------------------------------------------------------------------

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF334155),
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _DatePresetPill extends StatelessWidget {
  const _DatePresetPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1E293B)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

class _ModernKpiCard extends StatelessWidget {
  const _ModernKpiCard({
    required this.title,
    required this.value,
    required this.subValue,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    this.growthPositive,
    this.onTap,
  });

  final String title;
  final String value;
  final String subValue;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final bool? growthPositive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
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
            const SizedBox(height: 8),
            Row(
              children: [
                if (growthPositive != null) ...[
                  Icon(
                    growthPositive! ? Icons.trending_up : Icons.trending_down,
                    size: 15,
                    color: growthPositive!
                        ? const Color(0xFF0D9488)
                        : const Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    subValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: growthPositive == true
                          ? const Color(0xFF0D9488)
                          : growthPositive == false
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// EXECUTIVE REVENUE VS EXPENSES DUAL-SERIES AREA & LINE TREND CHART
// -----------------------------------------------------------------------------

class _ExecutiveRevenueExpenseChart extends StatefulWidget {
  const _ExecutiveRevenueExpenseChart({
    required this.points,
    required this.onViewSalesSummary,
  });

  final List<ReportTrendPoint> points;
  final VoidCallback onViewSalesSummary;

  @override
  State<_ExecutiveRevenueExpenseChart> createState() =>
      _ExecutiveRevenueExpenseChartState();
}

class _ExecutiveRevenueExpenseChartState
    extends State<_ExecutiveRevenueExpenseChart> {
  int? _hoveredIndex;

  String _formatCompactPaise(int paise) {
    final rupees = paise ~/ 100;
    if (rupees >= 10000000) {
      return '₹${(rupees / 10000000).toStringAsFixed(1)}Cr';
    } else if (rupees >= 100000) {
      return '₹${(rupees / 100000).toStringAsFixed(1)}L';
    } else if (rupees >= 1000) {
      return '₹${(rupees / 1000).toStringAsFixed(0)}k';
    }
    return '₹$rupees';
  }

  String _formatCurrency(int paise) {
    final abs = (paise.abs() ~/ 100).toString();
    if (abs.length <= 3) return '₹ $abs';
    final last3 = abs.substring(abs.length - 3);
    final rest = abs.substring(0, abs.length - 3);
    final buf = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
      buf.write(rest[i]);
    }
    return '₹ ${buf.toString()},$last3';
  }

  @override
  Widget build(BuildContext context) {
    // Fallback baseline points if none exist yet
    final displayPoints = widget.points.isNotEmpty
        ? widget.points
        : const [
            ReportTrendPoint(label: 'P1', salesPaise: 0, purchasesPaise: 0),
            ReportTrendPoint(label: 'P2', salesPaise: 0, purchasesPaise: 0),
            ReportTrendPoint(label: 'P3', salesPaise: 0, purchasesPaise: 0),
            ReportTrendPoint(label: 'P4', salesPaise: 0, purchasesPaise: 0),
            ReportTrendPoint(label: 'P5', salesPaise: 0, purchasesPaise: 0),
            ReportTrendPoint(label: 'P6', salesPaise: 0, purchasesPaise: 0),
          ];

    // Find peak interval and totals
    ReportTrendPoint? peakPoint;
    int totalSales = 0;
    int totalPurchases = 0;
    for (final p in displayPoints) {
      totalSales += p.salesPaise;
      totalPurchases += p.purchasesPaise;
      if (peakPoint == null || p.salesPaise > peakPoint.salesPaise) {
        peakPoint = p;
      }
    }
    final overallNetPaise = totalSales - totalPurchases;
    final double overallMarginPct =
        totalSales > 0 ? (overallNetPaise / totalSales) * 100 : 0.0;

    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 14 : 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Keep the title and legend in separate rows so narrow screens never
          // force the chart heading into a tiny width.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Executive Revenue vs Expenses',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Periodic comparison showing net sales revenue against purchase outflow.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Legend Pills
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Revenue (Sales)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4E45D5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Expenses (Purchases)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: overallNetPaise >= 0
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Net Margin: ${overallNetPaise >= 0 ? '+' : ''}${_formatCompactPaise(overallNetPaise)} (${overallMarginPct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: overallNetPaise >= 0
                              ? const Color(0xFF15803D)
                              : const Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Chart Canvas with Tooltip Overlay
          SizedBox(
            height: 250,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                const leftPadding = 56.0;
                const rightPadding = 20.0;
                final chartWidth = width - leftPadding - rightPadding;
                final groupWidth = displayPoints.isNotEmpty
                    ? chartWidth / displayPoints.length
                    : chartWidth;

                return MouseRegion(
                  onHover: (event) {
                    final dx = event.localPosition.dx;
                    if (dx >= leftPadding &&
                        dx <= width - rightPadding &&
                        displayPoints.isNotEmpty) {
                      final index = ((dx - leftPadding) / groupWidth)
                          .floor()
                          .clamp(0, displayPoints.length - 1);
                      if (_hoveredIndex != index) {
                        setState(() => _hoveredIndex = index);
                      }
                    } else if (_hoveredIndex != null) {
                      setState(() => _hoveredIndex = null);
                    }
                  },
                  onExit: (_) => setState(() => _hoveredIndex = null),
                  child: GestureDetector(
                    onTapDown: (details) {
                      final dx = details.localPosition.dx;
                      if (dx >= leftPadding &&
                          dx <= width - rightPadding &&
                          displayPoints.isNotEmpty) {
                        final index = ((dx - leftPadding) / groupWidth)
                            .floor()
                            .clamp(0, displayPoints.length - 1);
                        setState(() => _hoveredIndex = index);
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CustomPaint(
                          size: Size(width, height),
                          painter: _RevenueExpenseBarChartPainter(
                            points: displayPoints,
                            hoveredIndex: _hoveredIndex,
                            formatCompact: _formatCompactPaise,
                          ),
                        ),
                        // Interactive Floating Tooltip
                        if (_hoveredIndex != null &&
                            _hoveredIndex! < displayPoints.length) ...[
                          Builder(
                            builder: (context) {
                              final pt = displayPoints[_hoveredIndex!];
                              final netPaise =
                                  pt.salesPaise - pt.purchasesPaise;
                              final groupCenterX =
                                  leftPadding +
                                  (_hoveredIndex! * groupWidth) +
                                  (groupWidth / 2);
                              const tooltipW = 160.0;
                              final maxLeft = math.max(
                                leftPadding,
                                width - tooltipW - 8.0,
                              );
                              final tooltipLeft =
                                  (groupCenterX - (tooltipW / 2)).clamp(
                                    leftPadding,
                                    maxLeft,
                                  );

                              return Positioned(
                                left: tooltipLeft,
                                top: 8,
                                child: IgnorePointer(
                                  child: Container(
                                    width: tooltipW,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.25,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          pt.label,
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF0D9488,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                const Text(
                                                  'Sales',
                                                  style: TextStyle(
                                                    color: Color(0xFFE2E8F0),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              _formatCurrency(pt.salesPaise),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF818CF8,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          2,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(width: 5),
                                                const Text(
                                                  'Purchases',
                                                  style: TextStyle(
                                                    color: Color(0xFFE2E8F0),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              _formatCurrency(
                                                pt.purchasesPaise,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: 1,
                                          color: const Color(0xFF334155),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Net Margin',
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              '${netPaise >= 0 ? '+' : ''}${_formatCurrency(netPaise)} (${pt.salesPaise > 0 ? ((netPaise / pt.salesPaise) * 100).toStringAsFixed(1) : '0.0'}%)',
                                              style: TextStyle(
                                                color: netPaise >= 0
                                                    ? const Color(0xFF34D399)
                                                    : const Color(0xFFF87171),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Footer Banner: Peak Performance Note & Quick Link
          LayoutBuilder(
            builder: (context, constraints) {
              final note = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.stars_rounded,
                    size: 16,
                    color: Color(0xFF0D9488),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      peakPoint != null && peakPoint.salesPaise > 0
                          ? 'Peak revenue period: ${peakPoint.label} (${_formatCurrency(peakPoint.salesPaise)})'
                          : 'Dynamic real-time trends updated from offline SQLite store',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              );
              final link = InkWell(
                onTap: widget.onViewSalesSummary,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Row(
                    children: const [
                      Text(
                        'View detailed sales ledger',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D9488),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: Color(0xFF0D9488),
                      ),
                    ],
                  ),
                ),
              );

              if (constraints.maxWidth < 700) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [note, const SizedBox(height: 8), link],
                );
              }

              return Row(
                children: [
                  Expanded(child: note),
                  const SizedBox(width: 12),
                  link,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RevenueExpenseBarChartPainter extends CustomPainter {
  _RevenueExpenseBarChartPainter({
    required this.points,
    required this.hoveredIndex,
    required this.formatCompact,
  });

  final List<ReportTrendPoint> points;
  final int? hoveredIndex;
  final String Function(int) formatCompact;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 56.0;
    const rightPad = 20.0;
    const topPad = 16.0;
    const bottomPad = 32.0;

    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    // 1. Calculate a human-friendly scale for Y-axis
    var maxPaise = 0;
    for (final p in points) {
      if (p.salesPaise > maxPaise) maxPaise = p.salesPaise;
      if (p.purchasesPaise > maxPaise) maxPaise = p.purchasesPaise;
    }

    // Minimum baseline ₹10,000 (1,000,000 paise)
    if (maxPaise < 1000000) {
      maxPaise = 1000000;
    } else {
      maxPaise = _calculateNiceCeiling(maxPaise);
    }

    const gridLinesCount = 4;
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final axisLinePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final textStyle = const TextStyle(
      color: Color(0xFF94A3B8),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );

    // 2. Draw horizontal grid lines & Y-axis labels
    for (int i = 0; i <= gridLinesCount; i++) {
      final y = topPad + (chartH * (gridLinesCount - i) / gridLinesCount);
      final value = (maxPaise * i / gridLinesCount).round();

      if (i > 0) {
        _drawDashedLine(
          canvas,
          Offset(leftPad, y),
          Offset(leftPad + chartW, y),
          gridPaint,
        );
      }

      // Y-axis label
      final textSpan = TextSpan(text: formatCompact(value), style: textStyle);
      final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(leftPad - tp.width - 8, y - (tp.height / 2)));
    }

    // Baseline (Y=0 line)
    final baselineY = topPad + chartH;
    canvas.drawLine(
      Offset(leftPad, baselineY),
      Offset(leftPad + chartW, baselineY),
      axisLinePaint,
    );

    if (points.isEmpty) return;

    final count = points.length;
    final groupWidth = chartW / count;
    // Calculate bar width nicely: maximum 24px, with 4px gap between sales & purchase bars
    final totalBarArea = math.min(groupWidth * 0.65, 48.0);
    const barGap = 4.0;
    final singleBarWidth = math.max(4.0, (totalBarArea - barGap) / 2);

    final salesPaint = Paint()..color = const Color(0xFF0D9488);
    final purchasePaint = Paint()..color = const Color(0xFF4E45D5);

    final hoveredSalesPaint = Paint()..color = const Color(0xFF0F766E);
    final hoveredPurchasePaint = Paint()..color = const Color(0xFF4338CA);

    // 3. Clip canvas to prevent any overflow outside the chart area
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        leftPad - 2,
        topPad - 4,
        chartW + 4,
        chartH + bottomPad + 4,
      ),
    );

    for (int i = 0; i < count; i++) {
      final groupX = leftPad + (i * groupWidth);
      final groupCenterX = groupX + (groupWidth / 2);
      final isHovered = hoveredIndex == i;

      // Draw hover column highlight
      if (isHovered) {
        final highlightPaint = Paint()
          ..color = const Color(0xFF0F172A).withValues(alpha: 0.04);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(groupX + 2, topPad, groupWidth - 4, chartH),
            const Radius.circular(8),
          ),
          highlightPaint,
        );
      }

      final p = points[i];

      // Calculate bar heights (clamped so they never overshoot)
      final salesFraction = maxPaise > 0
          ? (p.salesPaise / maxPaise).clamp(0.0, 1.0)
          : 0.0;
      final purchaseFraction = maxPaise > 0
          ? (p.purchasesPaise / maxPaise).clamp(0.0, 1.0)
          : 0.0;

      final salesH = salesFraction * chartH;
      final purchaseH = purchaseFraction * chartH;

      final salesBarX = groupCenterX - singleBarWidth - (barGap / 2);
      final purchaseBarX = groupCenterX + (barGap / 2);

      // --- Draw Sales Bar ---
      if (p.salesPaise > 0) {
        final actualSalesH = math.max(3.0, salesH);
        final salesY = baselineY - actualSalesH;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(salesBarX, salesY, singleBarWidth, actualSalesH),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          isHovered ? hoveredSalesPaint : salesPaint,
        );
      } else {
        // Zero baseline pill
        final zeroPaint = Paint()
          ..color = const Color(0xFF0D9488).withValues(alpha: 0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(salesBarX, baselineY - 2.5, singleBarWidth, 2.5),
            const Radius.circular(1.5),
          ),
          zeroPaint,
        );
      }

      // --- Draw Purchase Bar ---
      if (p.purchasesPaise > 0) {
        final actualPurchaseH = math.max(3.0, purchaseH);
        final purchaseY = baselineY - actualPurchaseH;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(
              purchaseBarX,
              purchaseY,
              singleBarWidth,
              actualPurchaseH,
            ),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          isHovered ? hoveredPurchasePaint : purchasePaint,
        );
      } else {
        // Zero baseline pill
        final zeroPaint = Paint()
          ..color = const Color(0xFF4E45D5).withValues(alpha: 0.35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(purchaseBarX, baselineY - 2.5, singleBarWidth, 2.5),
            const Radius.circular(1.5),
          ),
          zeroPaint,
        );
      }

      // --- Draw X-axis label ---
      final labelStyle = isHovered
          ? const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            )
          : textStyle;
      final labelSpan = TextSpan(text: p.label, style: labelStyle);
      final ltp = TextPainter(text: labelSpan, textDirection: TextDirection.ltr)
        ..layout();
      ltp.paint(canvas, Offset(groupCenterX - (ltp.width / 2), baselineY + 8));
    }

    canvas.restore();
  }

  static int _calculateNiceCeiling(int valuePaise) {
    if (valuePaise <= 0) return 1000000;
    final rupees = valuePaise / 100.0;
    if (rupees <= 0 || !rupees.isFinite || rupees.isNaN) return 1000000;
    final logVal = math.log(rupees) / math.ln10;
    if (!logVal.isFinite || logVal.isNaN) return 1000000;
    final magnitude = math.pow(10, logVal.floor()).toDouble();
    if (!magnitude.isFinite || magnitude <= 0) return 1000000;
    final fraction = rupees / magnitude;

    double niceFraction;
    if (fraction <= 1.0) {
      niceFraction = 1.0;
    } else if (fraction <= 1.25) {
      niceFraction = 1.25;
    } else if (fraction <= 1.5) {
      niceFraction = 1.5;
    } else if (fraction <= 2.0) {
      niceFraction = 2.0;
    } else if (fraction <= 2.5) {
      niceFraction = 2.5;
    } else if (fraction <= 5.0) {
      niceFraction = 5.0;
    } else if (fraction <= 7.5) {
      niceFraction = 7.5;
    } else {
      niceFraction = 10.0;
    }

    final result = (niceFraction * magnitude * 100).round();
    return result > 0 ? result : 1000000;
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0 || !distance.isFinite || distance.isNaN) return;
    final count = (distance / (dashWidth + dashSpace)).floor();
    final unitX = dx / distance;
    final unitY = dy / distance;
    if (!unitX.isFinite || !unitY.isFinite || unitX.isNaN || unitY.isNaN) return;

    for (int i = 0; i < count; i++) {
      final start = Offset(
        p1.dx + (unitX * (dashWidth + dashSpace) * i),
        p1.dy + (unitY * (dashWidth + dashSpace) * i),
      );
      final end = Offset(
        start.dx + (unitX * dashWidth),
        start.dy + (unitY * dashWidth),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueExpenseBarChartPainter oldDelegate) {
    return oldDelegate.hoveredIndex != hoveredIndex ||
        oldDelegate.points != points;
  }
}

// -----------------------------------------------------------------------------
// 3D PIE CHART & COLLECTION / CATEGORY VISUALIZATIONS
// -----------------------------------------------------------------------------

const List<Color> _kExcel3dPalette = [
  Color(0xFF5B84B1), // Slate Blue (slice 1)
  Color(0xFF82B366), // Soft Apple Green (slice 2)
  Color(0xFFFFC000), // Warm Gold / Yellow (slice 3)
  Color(0xFFED7D31), // Amber Orange / Tangerine (slice 4)
  Color(0xFFA05A2C), // Cinnamon / Bronze Brown (slice 5)
  Color(0xFF8FAADC), // Cool Silver Grey / Periwinkle (slice 6)
];

enum _CollectionChartType { pie3d, bar, donut }

enum _CategoryChartType { bar, pie3d }

class _Pie3DSlice {
  const _Pie3DSlice({
    required this.label,
    required this.value,
    required this.percentage,
    required this.color,
    required this.formattedAmount,
  });

  final String label;
  final double value;
  final double percentage; // 0.0 to 1.0
  final Color color;
  final String formattedAmount;
}

class _Pie3DChartPainter extends CustomPainter {
  _Pie3DChartPainter({
    required this.slices,
  });

  final List<_Pie3DSlice> slices;
  static const double depth = 18.0;
  static const double yRatio = 0.52;

  @override
  void paint(Canvas canvas, Size size) {
    if (slices.isEmpty) return;
    if (size.width <= 20 || size.height <= depth + 10) return;

    final cx = size.width / 2;
    final cy = (size.height - depth) / 2;
    final rx = math.max(
      10.0,
      math.min(size.width / 2 - 12, (size.height - depth) / (2 * yRatio) - 4),
    );
    final ry = rx * yRatio;
    if (rx <= 0 || rx.isNaN || !rx.isFinite) return;

    final topRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: rx * 2,
      height: ry * 2,
    );
    final bottomRect = Rect.fromCenter(
      center: Offset(cx, cy + depth),
      width: rx * 2,
      height: ry * 2,
    );

    // 1. Soft blurred drop shadow beneath the 3D pie base
    final shadowPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy + depth + 4),
        width: rx * 1.95,
        height: ry * 1.95,
      ),
      shadowPaint,
    );

    // Filter positive slices and calculate normalized arc angles
    final validSlices = slices.where((s) => s.value > 0).toList();
    if (validSlices.isEmpty) return;

    final totalVal = validSlices.fold<double>(0.0, (acc, s) => acc + s.value);
    if (totalVal <= 0) return;

    // Start angle at -0.70 * pi so primary slices sweep across the front rim
    const startAngle = -math.pi * 0.70;

    final sliceAngles = <Map<String, dynamic>>[];
    var currentAngle = startAngle;
    for (final slice in validSlices) {
      final sweep = (slice.value / totalVal) * (2 * math.pi);
      sliceAngles.add({
        'slice': slice,
        'pct': slice.value / totalVal,
        'a1': currentAngle,
        'a2': currentAngle + sweep,
        'sweep': sweep,
      });
      currentAngle += sweep;
    }

    // 2. Draw front rim extrusion walls
    // Rim is visible in the front half where sin(theta) >= 0 (theta in [0, pi] mod 2*pi)
    for (final item in sliceAngles) {
      final slice = item['slice'] as _Pie3DSlice;
      final a1 = item['a1'] as double;
      final a2 = item['a2'] as double;

      void checkInterval(double fStart, double fEnd) {
        final start = math.max(a1, fStart);
        final end = math.min(a2, fEnd);
        if (start < end) {
          final wallPath = Path();
          wallPath.arcTo(topRect, start, end - start, true);
          wallPath.arcTo(bottomRect, end, -(end - start), false);
          wallPath.close();

          final wallPaint = Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(slice.color, Colors.black, 0.12)!,
                Color.lerp(slice.color, Colors.black, 0.35)!,
              ],
            ).createShader(Rect.fromLTWH(cx - rx, cy, rx * 2, depth))
            ..style = PaintingStyle.fill;

          canvas.drawPath(wallPath, wallPaint);

          final rimBorder = Paint()
            ..color = Colors.white.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8;
          canvas.drawPath(wallPath, rimBorder);
        }
      }

      checkInterval(-2 * math.pi, -math.pi);
      checkInterval(0.0, math.pi);
      checkInterval(2 * math.pi, 3 * math.pi);
      checkInterval(4 * math.pi, 5 * math.pi);
    }

    // 3. Draw top elliptical slices
    for (final item in sliceAngles) {
      final slice = item['slice'] as _Pie3DSlice;
      final a1 = item['a1'] as double;
      final sweep = item['sweep'] as double;

      final slicePath = Path();
      slicePath.moveTo(cx, cy);
      slicePath.arcTo(topRect, a1, sweep, false);
      slicePath.close();

      final topPaint = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.15,
          colors: [
            Color.lerp(slice.color, Colors.white, 0.18)!,
            slice.color,
            Color.lerp(slice.color, Colors.black, 0.08)!,
          ],
        ).createShader(topRect)
        ..style = PaintingStyle.fill;

      canvas.drawPath(slicePath, topPaint);

      // Clean white separator border between slices
      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(slicePath, borderPaint);
    }

    // 4. Draw slice percentage labels printed directly on top of the slices
    for (final item in sliceAngles) {
      final pct = item['pct'] as double;
      if (pct < 0.045) continue; // Skip tiny slivers to prevent crowding

      final a1 = item['a1'] as double;
      final sweep = item['sweep'] as double;
      final midAngle = a1 + sweep / 2;

      final px = cx + rx * 0.62 * math.cos(midAngle);
      final py = cy + ry * 0.62 * math.sin(midAngle);

      final pctStr = '${(pct * 100).round()}%';
      final textSpan = TextSpan(
        text: pctStr,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          shadows: [
            Shadow(
              color: Color(0xCC000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(px - tp.width / 2, py - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _Pie3DChartPainter oldDelegate) {
    if (oldDelegate.slices.length != slices.length) return true;
    for (int i = 0; i < slices.length; i++) {
      if (oldDelegate.slices[i].value != slices[i].value ||
          oldDelegate.slices[i].color != slices[i].color) {
        return true;
      }
    }
    return false;
  }
}

// -----------------------------------------------------------------------------
// COLLECTION STATUS DASHBOARD CARD (3D PIE / BAR / DONUT MULTI-VIEW)
// -----------------------------------------------------------------------------

class _CollectionDonutChart extends StatefulWidget {
  const _CollectionDonutChart({
    required this.collectedPaise,
    required this.outstandingPaise,
    required this.overduePaise,
    required this.onViewReceivables,
  });

  final int collectedPaise;
  final int outstandingPaise;
  final int overduePaise;
  final VoidCallback onViewReceivables;

  @override
  State<_CollectionDonutChart> createState() => _CollectionDonutChartState();
}

class _CollectionDonutChartState extends State<_CollectionDonutChart> {
  _CollectionChartType _selectedChart = _CollectionChartType.pie3d;

  String _formatCurrency(int paise) {
    final abs = (paise.abs() ~/ 100).toString();
    if (abs.length <= 3) return '₹ $abs';
    final last3 = abs.substring(abs.length - 3);
    final rest = abs.substring(0, abs.length - 3);
    final buf = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
      buf.write(rest[i]);
    }
    return '₹ ${buf.toString()},$last3';
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.collectedPaise + widget.outstandingPaise;
    final currentDuePaise = math.max(
      0,
      widget.outstandingPaise - widget.overduePaise,
    );
    final double collectedRatio = total > 0 ? (widget.collectedPaise / total) : 0.0;
    final double outstandingRatio = total > 0 ? (currentDuePaise / total).clamp(0.0, 1.0) : 0.0;
    final double overdueRatio = total > 0 ? (widget.overduePaise / total).clamp(0.0, 1.0) : 0.0;
    final collectedPct = total > 0 ? (collectedRatio * 100).round() : 0;

    // Build slices for 3D pie and horizontal bar
    final slices = <_Pie3DSlice>[];
    if (widget.collectedPaise > 0) {
      slices.add(_Pie3DSlice(
        label: 'Collected',
        value: widget.collectedPaise.toDouble(),
        percentage: total > 0 ? widget.collectedPaise / total : 0.0,
        color: _kExcel3dPalette[0], // Slate Blue
        formattedAmount: _formatCurrency(widget.collectedPaise),
      ));
    }
    if (currentDuePaise > 0) {
      slices.add(_Pie3DSlice(
        label: 'Current Due',
        value: currentDuePaise.toDouble(),
        percentage: total > 0 ? currentDuePaise / total : 0.0,
        color: _kExcel3dPalette[1], // Apple Green
        formattedAmount: _formatCurrency(currentDuePaise),
      ));
    }
    if (widget.overduePaise > 0) {
      slices.add(_Pie3DSlice(
        label: 'Overdue',
        value: widget.overduePaise.toDouble(),
        percentage: total > 0 ? widget.overduePaise / total : 0.0,
        color: _kExcel3dPalette[3], // Tangerine / Amber
        formattedAmount: _formatCurrency(widget.overduePaise),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Mode Switcher
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Collection Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Invoice reconciliation breakdown',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildViewModeToggle(),
            ],
          ),
          const SizedBox(height: 18),

          // Chart Content based on selected mode
          if (_selectedChart == _CollectionChartType.pie3d)
            _buildPie3DView(slices: slices, total: total)
          else if (_selectedChart == _CollectionChartType.bar)
            _buildBarView(slices: slices, total: total)
          else
            _buildDonutView(
              collectedRatio: collectedRatio,
              outstandingRatio: outstandingRatio,
              overdueRatio: overdueRatio,
              collectedPct: collectedPct,
              currentDuePaise: currentDuePaise,
            ),

          const SizedBox(height: 16),

          // Link to report
          InkWell(
            onTap: widget.onViewReceivables,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'View outstanding receivables',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: Color(0xFF0D9488),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleItem(
            type: _CollectionChartType.pie3d,
            label: '3D Pie',
          ),
          _buildToggleItem(
            type: _CollectionChartType.bar,
            label: 'Bar',
          ),
          _buildToggleItem(
            type: _CollectionChartType.donut,
            label: 'Donut',
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required _CollectionChartType type,
    required String label,
  }) {
    final isSelected = _selectedChart == type;
    return InkWell(
      onTap: () {
        if (_selectedChart != type) {
          setState(() {
            _selectedChart = type;
          });
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildPie3DView({
    required List<_Pie3DSlice> slices,
    required int total,
  }) {
    if (slices.isEmpty || total <= 0) {
      return _buildEmptyState();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 320;
        if (isNarrow) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 145,
                child: CustomPaint(
                  painter: _Pie3DChartPainter(slices: slices),
                ),
              ),
              const SizedBox(height: 14),
              _build3DLegend(slices),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 155,
              height: 155,
              child: CustomPaint(
                painter: _Pie3DChartPainter(slices: slices),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _build3DLegend(slices),
            ),
          ],
        );
      },
    );
  }

  Widget _build3DLegend(List<_Pie3DSlice> slices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < slices.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 3D beveled square chiclet matching the reference image
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2.5),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(slices[i].color, Colors.white, 0.35)!,
                      slices[i].color,
                      Color.lerp(slices[i].color, Colors.black, 0.25)!,
                    ],
                  ),
                  border: Border.all(
                    color: Color.lerp(slices[i].color, Colors.black, 0.35)!,
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 1.5,
                      offset: const Offset(0.5, 1.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slices[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                slices[i].formattedAmount,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${(slices[i].percentage * 100).round()}%)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBarView({
    required List<_Pie3DSlice> slices,
    required int total,
  }) {
    if (slices.isEmpty || total <= 0) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < slices.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: slices[i].color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        slices[i].label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        slices[i].formattedAmount,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${(slices[i].percentage * 100).round()}%)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Stack(
                children: [
                  Container(
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4.5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: slices[i].percentage.clamp(0.02, 1.0),
                    child: Container(
                      height: 9,
                      decoration: BoxDecoration(
                        color: slices[i].color,
                        borderRadius: BorderRadius.circular(4.5),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDonutView({
    required double collectedRatio,
    required double outstandingRatio,
    required double overdueRatio,
    required int collectedPct,
    required int currentDuePaise,
  }) {
    return Column(
      children: [
        Center(
          child: SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(140, 140),
                  painter: _DonutChartPainter(
                    collectedRatio: collectedRatio,
                    outstandingRatio: outstandingRatio,
                    overdueRatio: overdueRatio,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$collectedPct%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Text(
                      'Collected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                _buildDonutLegendRow(
                  color: _kExcel3dPalette[0],
                  label: 'Collected',
                  amount: _formatCurrency(widget.collectedPaise),
                  pct: '${(collectedRatio * 100).toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 8),
                _buildDonutLegendRow(
                  color: _kExcel3dPalette[1],
                  label: 'Current Due',
                  amount: _formatCurrency(currentDuePaise),
                  pct: '${(outstandingRatio * 100).toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 8),
                _buildDonutLegendRow(
                  color: _kExcel3dPalette[3],
                  label: 'Overdue Due',
                  amount: _formatCurrency(widget.overduePaise),
                  pct: '${(overdueRatio * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDonutLegendRow({
    required Color color,
    required String label,
    required String amount,
    required String pct,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF334155),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Text(
              amount,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($pct)',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: const [
            Icon(
              Icons.pie_chart_outline_rounded,
              size: 36,
              color: Color(0xFFCBD5E1),
            ),
            SizedBox(height: 8),
            Text(
              'No collection data in period',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Invoices and settlements will populate breakdown',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  _DonutChartPainter({
    required this.collectedRatio,
    required this.outstandingRatio,
    required this.overdueRatio,
  });

  final double collectedRatio;
  final double outstandingRatio;
  final double overdueRatio;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 16.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    if (radius <= 0 || !radius.isFinite || radius.isNaN) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final bgPaint = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final safeCollected = (collectedRatio.isFinite && !collectedRatio.isNaN)
        ? collectedRatio.clamp(0.0, 1.0)
        : 0.0;
    final safeOutstanding =
        (outstandingRatio.isFinite && !outstandingRatio.isNaN)
            ? outstandingRatio.clamp(0.0, 1.0)
            : 0.0;
    final safeOverdue = (overdueRatio.isFinite && !overdueRatio.isNaN)
        ? overdueRatio.clamp(0.0, 1.0)
        : 0.0;

    var startAngle = -math.pi / 2;

    // Draw Collected slice
    if (safeCollected > 0) {
      final sweepAngle = 2 * math.pi * safeCollected;
      final p = Paint()
        ..color = _kExcel3dPalette[0]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = safeCollected >= 0.999
            ? StrokeCap.butt
            : StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweepAngle, false, p);
      startAngle += sweepAngle;
    }

    // Draw Outstanding slice
    if (safeOutstanding > 0) {
      final sweepAngle = 2 * math.pi * safeOutstanding;
      final p = Paint()
        ..color = _kExcel3dPalette[1]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle, false, p);
      startAngle += sweepAngle;
    }

    // Draw Overdue slice
    if (safeOverdue > 0) {
      final sweepAngle = 2 * math.pi * safeOverdue;
      final p = Paint()
        ..color = _kExcel3dPalette[3]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweepAngle, false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.collectedRatio != collectedRatio ||
        oldDelegate.outstandingRatio != outstandingRatio ||
        oldDelegate.overdueRatio != overdueRatio;
  }
}

// -----------------------------------------------------------------------------
// TOP PRODUCT CATEGORIES CHART (HORIZONTAL BARS & 3D PIE MULTI-VIEW)
// -----------------------------------------------------------------------------

class _CategorySalesBarChart extends StatefulWidget {
  const _CategorySalesBarChart({
    required this.categories,
    required this.onViewProductSales,
  });

  final List<ReportCategoryDistribution> categories;
  final VoidCallback onViewProductSales;

  @override
  State<_CategorySalesBarChart> createState() => _CategorySalesBarChartState();
}

class _CategorySalesBarChartState extends State<_CategorySalesBarChart> {
  _CategoryChartType _selectedChart = _CategoryChartType.bar;

  String _formatCurrency(int paise) {
    final abs = (paise.abs() ~/ 100).toString();
    if (abs.length <= 3) return '₹ $abs';
    final last3 = abs.substring(abs.length - 3);
    final rest = abs.substring(0, abs.length - 3);
    final buf = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) buf.write(',');
      buf.write(rest[i]);
    }
    return '₹ ${buf.toString()},$last3';
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;
    final totalCatAmount = categories.fold<int>(
      0,
      (sum, c) => sum + c.amountPaise,
    );

    // Map categories to 3D pie slices
    final slices = <_Pie3DSlice>[];
    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      if (cat.amountPaise <= 0) continue;
      final pct = totalCatAmount > 0 ? (cat.amountPaise / totalCatAmount) : 0.0;
      slices.add(_Pie3DSlice(
        label: cat.name,
        value: cat.amountPaise.toDouble(),
        percentage: pct,
        color: _kExcel3dPalette[i % _kExcel3dPalette.length],
        formattedAmount: _formatCurrency(cat.amountPaise),
      ));
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Mode Switcher
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Top Product Categories',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sales distribution across catalog departments',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (categories.isNotEmpty) _buildViewModeToggle(),
            ],
          ),
          const SizedBox(height: 18),

          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: const [
                    Icon(
                      Icons.bar_chart_rounded,
                      size: 36,
                      color: Color(0xFFCBD5E1),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No category sales in period',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sales invoices will populate distribution',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            )
          else if (_selectedChart == _CategoryChartType.pie3d)
            _buildPie3DView(slices: slices)
          else
            _buildBarView(categories: categories),

          const SizedBox(height: 18),

          // Link to Product Sales
          InkWell(
            onTap: widget.onViewProductSales,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text(
                    'View all product sales rankings',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: Color(0xFF0D9488),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleItem(
            type: _CategoryChartType.bar,
            label: 'Bar',
          ),
          _buildToggleItem(
            type: _CategoryChartType.pie3d,
            label: '3D Pie',
          ),
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required _CategoryChartType type,
    required String label,
  }) {
    final isSelected = _selectedChart == type;
    return InkWell(
      onTap: () {
        if (_selectedChart != type) {
          setState(() {
            _selectedChart = type;
          });
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildPie3DView({required List<_Pie3DSlice> slices}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 320;
        if (isNarrow) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 145,
                child: CustomPaint(
                  painter: _Pie3DChartPainter(slices: slices),
                ),
              ),
              const SizedBox(height: 14),
              _build3DLegend(slices),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 155,
              height: 155,
              child: CustomPaint(
                painter: _Pie3DChartPainter(slices: slices),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _build3DLegend(slices),
            ),
          ],
        );
      },
    );
  }

  Widget _build3DLegend(List<_Pie3DSlice> slices) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < slices.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2.5),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(slices[i].color, Colors.white, 0.35)!,
                      slices[i].color,
                      Color.lerp(slices[i].color, Colors.black, 0.25)!,
                    ],
                  ),
                  border: Border.all(
                    color: Color.lerp(slices[i].color, Colors.black, 0.35)!,
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 1.5,
                      offset: const Offset(0.5, 1.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  slices[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                slices[i].formattedAmount,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${(slices[i].percentage * 100).round()}%)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBarView({required List<ReportCategoryDistribution> categories}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < categories.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      categories[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatCurrency(categories[i].amountPaise),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final pct = categories[i].percentage;
                      final safeWidth = (pct.isFinite && !pct.isNaN)
                          ? (pct / 100).clamp(0.04, 1.0)
                          : 0.04;
                      return FractionallySizedBox(
                        widthFactor: safeWidth,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: _kExcel3dPalette[i % _kExcel3dPalette.length],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// INVENTORY HEALTH & REORDER GAUGES
// -----------------------------------------------------------------------------

class _InventoryHealthCard extends StatelessWidget {
  const _InventoryHealthCard({
    required this.totalSkus,
    required this.lowStockCount,
    required this.expiringBatchesCount,
    required this.onRestock,
    required this.onViewExpiry,
  });

  final int totalSkus;
  final int lowStockCount;
  final int expiringBatchesCount;
  final VoidCallback onRestock;
  final VoidCallback onViewExpiry;

  @override
  Widget build(BuildContext context) {
    final healthySkus = math.max(0, totalSkus - lowStockCount);
    final healthyPct = totalSkus > 0
        ? ((healthySkus / totalSkus) * 100).round()
        : 100;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inventory Health',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Stock status & automated replenishment triggers',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),

          // Optimal Stock Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Optimal Stock SKUs',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF15803D),
                              ),
                            ),
                            Text(
                              '$healthySkus items healthy',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF166534),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$healthyPct%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Low Stock Alert Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Low Stock Alerts',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                            Text(
                              '$lowStockCount SKUs below threshold',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onRestock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text('Restock'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Expiring Batches Tile
          if (expiringBatchesCount > 0)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_top_rounded,
                          size: 16,
                          color: Color(0xFFD97706),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$expiringBatchesCount batches expire in 30d',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onViewExpiry,
                    child: const Text(
                      'Review',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          // Bottom note
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Automated alerts active',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              Text(
                'Dynamic sync',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D9488),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MODERN REPORT TILE CARD WITH ENHANCED VISUAL ICONS
// -----------------------------------------------------------------------------

class _ReportTileCard extends StatelessWidget {
  const _ReportTileCard({
    required this.id,
    required this.status,
    required this.onTap,
  });

  final ReportTileId id;
  final ReportTileStatus status;
  final VoidCallback onTap;

  IconData _getIconForReport(ReportTileId tileId) {
    switch (tileId) {
      case ReportTileId.completeAuditReport:
        return Icons.verified_user_rounded;
      case ReportTileId.salesSummary:
        return Icons.auto_graph_rounded;
      case ReportTileId.salesRegister:
        return Icons.receipt_long_rounded;
      case ReportTileId.productSales:
        return Icons.local_mall_outlined;
      case ReportTileId.salesForecast:
        return Icons.insights_rounded;
      case ReportTileId.outstandingReceivables:
        return Icons.account_balance_wallet_outlined;
      case ReportTileId.purchaseSummary:
        return Icons.shopping_bag_outlined;
      case ReportTileId.stockMovement:
        return Icons.swap_horiz_rounded;
      case ReportTileId.batchExpiry:
        return Icons.hourglass_top_rounded;
      case ReportTileId.lowStockReorder:
        return Icons.notification_important_outlined;
      case ReportTileId.gstSalesSummary:
        return Icons.pie_chart_outline_rounded;
      case ReportTileId.gstPurchaseSummary:
        return Icons.request_quote_outlined;
      case ReportTileId.profitEstimate:
        return Icons.trending_up_rounded;
      case ReportTileId.expenseCashFlow:
        return Icons.payments_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = status == ReportTileStatus.ready;
    final icon = _getIconForReport(id);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: const Color(0xFF0F766E)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isReady
                        ? const Color(0xFFE6F7F5)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isReady
                          ? const Color(0xFF0D9488)
                          : const Color(0xFFD97706),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              id.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Text(
                id.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  height: 1.25,
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Text(
                  'Open report',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0D9488),
                  ),
                ),
                SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: Color(0xFF0D9488),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// DETAIL REPORT DIALOG WITH PAGINATED TABLE AND EXPORTS
// -----------------------------------------------------------------------------

class _ReportDetailDialog extends StatefulWidget {
  const _ReportDetailDialog({required this.report});
  final ReportDetailData report;

  @override
  State<_ReportDetailDialog> createState() => _ReportDetailDialogState();
}

class _ReportDetailDialogState extends State<_ReportDetailDialog> {
  String _filter = '';
  bool _isExporting = false;
  bool _showChartView = true;
  bool _sortByRevenue = true;
  bool _showLeastSelling = false;
  int _chartItemLimit = 10;
  String _forecastFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final isProductReport = report.tileId == ReportTileId.productSales;
    final isForecastReport = report.tileId == ReportTileId.salesForecast;
    final filteredRows = report.rows.where((row) {
      if (_filter.isEmpty) return true;
      return row.any(
        (cell) => cell.toLowerCase().contains(_filter.toLowerCase()),
      );
    }).toList();

    return Container(
      width: 1100,
      height: 720,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Title and Actions
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final isCompact = headerConstraints.maxWidth < 700;
              if (isCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            report.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${report.businessName} › ${report.outletName} • ${report.dateRange.formatLabel()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isExporting
                                ? null
                                : () => _runExport(
                                    () =>
                                        ReportExportService.printReport(report),
                                  ),
                            icon: const Icon(Icons.print_outlined, size: 15),
                            label: const Text('Print'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isExporting
                                ? null
                                : () => _runExport(
                                    () => ReportExportService.savePdf(report),
                                  ),
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 15,
                            ),
                            label: const Text('Save PDF'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: _isExporting
                                ? null
                                : () => _runExport(
                                    () => ReportExportService.exportCsv(report),
                                  ),
                            icon: const Icon(
                              Icons.file_download_outlined,
                              size: 15,
                            ),
                            label: const Text('CSV'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _isExporting
                                ? null
                                : () => _runExport(
                                    () =>
                                        ReportExportService.exportExcel(report),
                                  ),
                            icon: const Icon(
                              Icons.table_view_outlined,
                              size: 15,
                            ),
                            label: const Text('Excel'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                report.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                report.dateRange.formatLabel(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${report.businessName} › ${report.outletName} • ${report.subtitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _runExport(
                                () => ReportExportService.printReport(report),
                              ),
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('Print'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _runExport(
                                () => ReportExportService.savePdf(report),
                              ),
                        icon: const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 16,
                        ),
                        label: const Text('Save PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _runExport(
                                () => ReportExportService.exportCsv(report),
                              ),
                        icon:
                            const Icon(Icons.file_download_outlined, size: 16),
                        label: const Text('CSV'),
                      ),
                      FilledButton.icon(
                        onPressed: _isExporting
                            ? null
                            : () => _runExport(
                                () => ReportExportService.exportExcel(report),
                              ),
                        icon: const Icon(Icons.table_view_outlined, size: 16),
                        label: const Text('Excel (.xlsx)'),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Key metrics cards
          if (report.summaryStats.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in report.summaryStats)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.value,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (s.subValue != null)
                            Text(
                              s.subValue!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF0D9488),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),

          // View Selector Toolbar for Product Sales & Forecast Reports
          if (isProductReport || isForecastReport)
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 650;
                final modeSelector = SegmentedButton<bool>(
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text(
                        isForecastReport
                            ? '🔮 Trends & Forecast'
                            : '📊 Ranking Charts',
                      ),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: const Text('📋 Detail Table'),
                    ),
                  ],
                  selected: {_showChartView},
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (val) {
                    setState(() => _showChartView = val.first);
                  },
                );

                Widget? filterChips;
                if (_showChartView && isProductReport) {
                  filterChips = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChoiceChip(
                          label: const Text('🏆 Top Selling'),
                          selected: !_showLeastSelling,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _showLeastSelling = false);
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('📉 Least Selling'),
                          selected: _showLeastSelling,
                          selectedColor: const Color(0xFFFEF3C7),
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            color: _showLeastSelling
                                ? const Color(0xFF92400E)
                                : null,
                            fontWeight: _showLeastSelling
                                ? FontWeight.w600
                                : null,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _showLeastSelling = true);
                          },
                        ),
                        const SizedBox(width: 12),
                        Container(
                          height: 18,
                          width: 1,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('₹ Revenue'),
                          selected: _sortByRevenue,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _sortByRevenue = true);
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('📦 Quantity'),
                          selected: !_sortByRevenue,
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _sortByRevenue = false);
                          },
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment<int>(value: 5, label: Text('5')),
                            ButtonSegment<int>(value: 10, label: Text('10')),
                            ButtonSegment<int>(value: 20, label: Text('20')),
                            ButtonSegment<int>(value: 0, label: Text('All')),
                          ],
                          selected: {_chartItemLimit},
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onSelectionChanged: (val) {
                            setState(() => _chartItemLimit = val.first);
                          },
                        ),
                      ],
                    ),
                  );
                } else if (_showChartView && isForecastReport) {
                  filterChips = SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChoiceChip(
                          label: const Text('All Products'),
                          selected: _forecastFilter == 'ALL',
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _forecastFilter = 'ALL');
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('🚨 Stockout Alerts (< 10d)'),
                          selected: _forecastFilter == 'CRITICAL',
                          selectedColor: const Color(0xFFFEE2E2),
                          visualDensity: VisualDensity.compact,
                          labelStyle: TextStyle(
                            color: _forecastFilter == 'CRITICAL'
                                ? const Color(0xFF991B1B)
                                : null,
                            fontWeight: _forecastFilter == 'CRITICAL'
                                ? FontWeight.w600
                                : null,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() => _forecastFilter = 'CRITICAL');
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('📈 High Growth'),
                          selected: _forecastFilter == 'GROWTH',
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _forecastFilter = 'GROWTH');
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('💤 Dead Stock (0 Sales)'),
                          selected: _forecastFilter == 'DEAD',
                          visualDensity: VisualDensity.compact,
                          onSelected: (val) {
                            if (val) setState(() => _forecastFilter = 'DEAD');
                          },
                        ),
                      ],
                    ),
                  );
                }

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      modeSelector,
                      if (filterChips != null) ...[
                        const SizedBox(height: 8),
                        filterChips,
                      ],
                      const SizedBox(height: 12),
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      modeSelector,
                      if (filterChips != null)
                        Flexible(child: filterChips),
                    ],
                  ),
                );
              },
            ),

          // Main Body: Charts View or Table View
          Expanded(
            child: (_showChartView && isProductReport)
                ? _buildProductChartsView(filteredRows)
                : ((_showChartView && isForecastReport)
                      ? _buildForecastChartsView(filteredRows)
                      : Column(
                          children: [
                            // Search bar
                            SizedBox(
                              height: 38,
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search within this report...',
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 18,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (val) =>
                                    setState(() => _filter = val),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Data Table
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: filteredRows.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'No matching records found for this period.',
                                          style: TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 13,
                                          ),
                                        ),
                                      )
                                    : Scrollbar(
                                        thumbVisibility: true,
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.vertical,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: DataTable(
                                              headingRowColor:
                                                  WidgetStateProperty.all(
                                                    const Color(0xFFF1F5F9),
                                                  ),
                                              headingTextStyle: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF334155),
                                              ),
                                              dataTextStyle: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF1E293B),
                                              ),
                                              columns: [
                                                for (final col
                                                    in report.columns)
                                                  DataColumn(label: Text(col)),
                                              ],
                                              rows: [
                                                for (final row in filteredRows)
                                                  DataRow(
                                                    cells: List.generate(
                                                      report.columns.length,
                                                      (idx) => DataCell(
                                                        Text(idx < row.length ? row[idx] : '—'),
                                                      ),
                                                    ),
                                                  ),
                                                if (report
                                                    .columnTotals
                                                    .isNotEmpty)
                                                  DataRow(
                                                    color:
                                                        WidgetStateProperty.all(
                                                          const Color(
                                                            0xFFF8FAFC,
                                                          ),
                                                        ),
                                                    cells: [
                                                      for (
                                                        int i = 0;
                                                        i <
                                                            report
                                                                .columns
                                                                .length;
                                                        i++
                                                      )
                                                        DataCell(
                                                          Text(
                                                            report.columnTotals[i] ??
                                                                (i == 0
                                                                    ? 'Total'
                                                                    : ''),
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
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
                            ),
                          ],
                        )),
          ),
          const SizedBox(height: 10),

          // Notes footer
          if (report.notes.isNotEmpty)
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    report.notes.join(' • '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _runExport(Future<dynamic> Function() action) async {
    setState(() => _isExporting = true);
    try {
      final res = await action();
      if (mounted && res is String && res.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved successfully: $res'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Widget _buildProductChartsView(List<List<String>> rows) {
    final items = <_ProductSalesChartItem>[];
    for (final r in rows) {
      if (r.length < 7) continue;
      final name = r[0];
      final sku = r[1];
      final unit = r[2];
      final qty = double.tryParse(r[3].replaceAll(',', '').trim()) ?? 0.0;
      final taxable =
          double.tryParse(
            r[4].replaceAll('₹', '').replaceAll(',', '').trim(),
          ) ??
          0.0;
      final tax =
          double.tryParse(
            r[5].replaceAll('₹', '').replaceAll(',', '').trim(),
          ) ??
          0.0;
      final rev =
          double.tryParse(
            r[6].replaceAll('₹', '').replaceAll(',', '').trim(),
          ) ??
          0.0;
      items.add(
        _ProductSalesChartItem(
          name: name,
          sku: sku,
          unit: unit,
          quantity: qty,
          taxable: taxable,
          tax: tax,
          revenue: rev,
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No product sales recorded for this period.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
      );
    }

    // Sort items
    if (_showLeastSelling) {
      if (_sortByRevenue) {
        items.sort((a, b) => a.revenue.compareTo(b.revenue));
      } else {
        items.sort((a, b) => a.quantity.compareTo(b.quantity));
      }
    } else {
      if (_sortByRevenue) {
        items.sort((a, b) => b.revenue.compareTo(a.revenue));
      } else {
        items.sort((a, b) => b.quantity.compareTo(a.quantity));
      }
    }

    final displayed = _chartItemLimit > 0
        ? items.take(_chartItemLimit).toList()
        : items;

    final double maxVal = displayed.fold<double>(
      0.0,
      (max, p) => math.max(max, _sortByRevenue ? p.revenue : p.quantity),
    );
    final double totalRevenue = items.fold<double>(
      0.0,
      (sum, p) => sum + p.revenue,
    );
    final double totalQuantity = items.fold<double>(
      0.0,
      (sum, p) => sum + p.quantity,
    );

    return Column(
      children: [
        // Summary ribbon
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 650;
            final titleWidget = Text(
              _showLeastSelling
                  ? '⚠️ Least Selling / Dead Stock Warning: ${displayed.length} slow-moving products identified'
                  : '🏆 Showing ${_chartItemLimit > 0 ? 'Top ${displayed.length}' : 'All ${displayed.length}'} Products by ${_sortByRevenue ? 'Revenue (Income)' : 'Quantity Sold'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _showLeastSelling
                    ? const Color(0xFF991B1B)
                    : const Color(0xFF166534),
              ),
            );
            final statsWidget = Text(
              'Total Revenue: ${_formatCurrency(totalRevenue)}  •  Total Units: ${totalQuantity % 1 == 0 ? totalQuantity.toInt() : totalQuantity.toStringAsFixed(1)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _showLeastSelling
                    ? const Color(0xFF991B1B)
                    : const Color(0xFF166534),
              ),
            );

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _showLeastSelling
                    ? const Color(0xFFFEF2F2)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _showLeastSelling
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 6),
                        statsWidget,
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: titleWidget),
                        const SizedBox(width: 8),
                        statsWidget,
                      ],
                    ),
            );
          },
        ),
        const SizedBox(height: 12),
        // Scrollable List of Charts
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: displayed.length,
              itemBuilder: (context, index) {
                final item = displayed[index];
                final rank = index + 1;
                final currentVal = _sortByRevenue
                    ? item.revenue
                    : item.quantity;
                final rawProgress = maxVal > 0 ? (currentVal / maxVal) : 0.02;
                final progress = (rawProgress.isFinite && !rawProgress.isNaN)
                    ? rawProgress.clamp(0.02, 1.0)
                    : 0.02;
                final sharePct = (totalRevenue > 0 && totalRevenue.isFinite && !totalRevenue.isNaN && item.revenue.isFinite && !item.revenue.isNaN)
                    ? ((item.revenue / totalRevenue) * 100).clamp(0.0, 100.0)
                    : 0.0;

                Color rankBg;
                Color rankText;
                if (_showLeastSelling) {
                  rankBg = const Color(0xFFFEE2E2);
                  rankText = const Color(0xFF991B1B);
                } else if (rank == 1) {
                  rankBg = const Color(0xFFFEF3C7);
                  rankText = const Color(0xFFB45309);
                } else if (rank == 2) {
                  rankBg = const Color(0xFFE2E8F0);
                  rankText = const Color(0xFF475569);
                } else if (rank == 3) {
                  rankBg = const Color(0xFFFFEDD5);
                  rankText = const Color(0xFFC2410C);
                } else {
                  rankBg = const Color(0xFFF1F5F9);
                  rankText = const Color(0xFF64748B);
                }

                Color barColor;
                if (_showLeastSelling) {
                  barColor = const Color(0xFFF87171);
                } else if (_sortByRevenue) {
                  barColor = const Color(0xFF0D9488);
                } else {
                  barColor = const Color(0xFF3B82F6);
                }

                final qtyLabel = item.unit.isNotEmpty
                    ? '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} ${item.unit}'
                    : '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)} sold';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: rankBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$rank',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: rankText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    if (item.sku.isNotEmpty &&
                                        item.sku != '—') ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'SKU: ${item.sku}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Taxable: ${_formatCurrency(item.taxable)}  •  Tax: ${_formatCurrency(item.tax)}',
                                  style: const TextStyle(
                                    fontSize: 11,
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
                                _sortByRevenue
                                    ? _formatCurrency(item.revenue)
                                    : qtyLabel,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _showLeastSelling
                                      ? const Color(0xFFB45309)
                                      : (_sortByRevenue
                                            ? const Color(0xFF0F766E)
                                            : const Color(0xFF1D4ED8)),
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    _sortByRevenue
                                        ? qtyLabel
                                        : _formatCurrency(item.revenue),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      '${sharePct.toStringAsFixed(1)}% income share',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Bar meter
                      Stack(
                        children: [
                          Container(
                            height: 7,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              height: 7,
                              decoration: BoxDecoration(
                                color: barColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForecastChartsView(List<List<String>> rows) {
    final items = <_ForecastChartRow>[];
    for (final r in rows) {
      if (r.length < 11) continue;
      items.add(
        _ForecastChartRow(
          name: r[0],
          sku: r[1],
          stockOnHand: double.tryParse(r[2].replaceAll(',', '').trim()) ?? 0,
          m3Qty: double.tryParse(r[3].replaceAll(',', '').trim()) ?? 0,
          m2Qty: double.tryParse(r[4].replaceAll(',', '').trim()) ?? 0,
          m1Qty: double.tryParse(r[5].replaceAll(',', '').trim()) ?? 0,
          growthPct:
              double.tryParse(
                r[6].replaceAll('%', '').replaceAll('+', '').replaceAll(',', '').trim(),
              ) ??
              0,
          forecastQty: double.tryParse(r[7].replaceAll(',', '').trim()) ?? 0,
          forecastIncome: r[8],
          stockDepletion: r[9],
          suggestedReorder: double.tryParse(r[10].replaceAll(',', '').trim()) ?? 0,
        ),
      );
    }

    final filtered = items.where((it) {
      if (_forecastFilter == 'CRITICAL') {
        final days = double.tryParse(
          it.stockDepletion.replaceAll('days', '').trim(),
        );
        return days != null && days < 10 && it.forecastQty > 0;
      }
      if (_forecastFilter == 'GROWTH') {
        return it.growthPct > 0;
      }
      if (_forecastFilter == 'DEAD') {
        return it.m1Qty == 0 && it.m2Qty == 0 && it.m3Qty == 0;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
        child: Text(
          'No items matching the selected forecast filter.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(
            children: [
              Icon(Icons.auto_graph, size: 16, color: Color(0xFF1D4ED8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Predictive Engine: Compares 3-Month sales velocity (Month -2, Month -1, Recent 30d) with current stock on hand to forecast future demand, project revenue, and prevent stockouts.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final maxBar = [
                  item.m3Qty,
                  item.m2Qty,
                  item.m1Qty,
                  item.forecastQty,
                ].fold<double>(1.0, math.max);

                final isCritical =
                    item.stockDepletion.contains('day') &&
                    (double.tryParse(
                              item.stockDepletion.replaceAll('days', '').trim(),
                            ) ??
                            99) <
                        10;
                final isGrowing = item.growthPct > 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isCritical
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
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
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (item.sku.isNotEmpty && item.sku != '—') ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.sku,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  'Current Stock: ${item.stockOnHand % 1 == 0 ? item.stockOnHand.toInt() : item.stockOnHand.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isGrowing
                                      ? const Color(0xFFDCFCE7)
                                      : const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${isGrowing ? '▲ +' : '▼ '}${item.growthPct.toStringAsFixed(1)}% MoM',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isGrowing
                                        ? const Color(0xFF166534)
                                        : const Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _buildTrendBar(
                                  label: 'Month -2',
                                  value: item.m3Qty,
                                  maxVal: maxBar,
                                  color: const Color(0xFF94A3B8),
                                ),
                                _buildTrendBar(
                                  label: 'Month -1',
                                  value: item.m2Qty,
                                  maxVal: maxBar,
                                  color: const Color(0xFF64748B),
                                ),
                                _buildTrendBar(
                                  label: 'Recent 30d',
                                  value: item.m1Qty,
                                  maxVal: maxBar,
                                  color: const Color(0xFF0284C7),
                                ),
                                _buildTrendBar(
                                  label: '🔮 Next 30d',
                                  value: item.forecastQty,
                                  maxVal: maxBar,
                                  color: const Color(0xFF10B981),
                                  isForecast: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isCritical
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isCritical
                                      ? const Color(0xFFFECACA)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Projected Revenue:',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      Text(
                                        item.forecastIncome,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F766E),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Stock Depletion:',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      Text(
                                        item.stockDepletion,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isCritical
                                              ? const Color(0xFFDC2626)
                                              : const Color(0xFF334155),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.suggestedReorder > 0) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCritical
                                            ? const Color(0xFFDC2626)
                                            : const Color(0xFF0D9488),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.shopping_cart_checkout,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Reorder +${item.suggestedReorder.toStringAsFixed(0)} units',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendBar({
    required String label,
    required double value,
    required double maxVal,
    required Color color,
    bool isForecast = false,
  }) {
    final safeValue = (value.isFinite && !value.isNaN) ? math.max(0.0, value) : 0.0;
    final safeMax = (maxVal.isFinite && !maxVal.isNaN && maxVal > 0) ? maxVal : 1.0;
    final rawRatio = safeValue / safeMax;
    final heightRatio = (rawRatio.isFinite && !rawRatio.isNaN)
        ? rawRatio.clamp(0.08, 1.0)
        : 0.08;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          safeValue % 1 == 0 ? safeValue.toInt().toString() : safeValue.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isForecast
                ? const Color(0xFF0F766E)
                : const Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 32,
          height: 60 * heightRatio,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            border: isForecast
                ? Border.all(color: const Color(0xFF047857), width: 1.5)
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: isForecast ? FontWeight.w700 : FontWeight.w500,
            color: isForecast
                ? const Color(0xFF0F766E)
                : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double amt) {
    final s = amt.toStringAsFixed(amt % 1 == 0 ? 0 : 2);
    return '₹ $s';
  }
}

class _ForecastChartRow {
  _ForecastChartRow({
    required this.name,
    required this.sku,
    required this.stockOnHand,
    required this.m3Qty,
    required this.m2Qty,
    required this.m1Qty,
    required this.growthPct,
    required this.forecastQty,
    required this.forecastIncome,
    required this.stockDepletion,
    required this.suggestedReorder,
  });

  final String name;
  final String sku;
  final double stockOnHand;
  final double m3Qty;
  final double m2Qty;
  final double m1Qty;
  final double growthPct;
  final double forecastQty;
  final String forecastIncome;
  final String stockDepletion;
  final double suggestedReorder;
}

class _ProductSalesChartItem {
  _ProductSalesChartItem({
    required this.name,
    required this.sku,
    required this.unit,
    required this.quantity,
    required this.taxable,
    required this.tax,
    required this.revenue,
  });

  final String name;
  final String sku;
  final String unit;
  final double quantity;
  final double taxable;
  final double tax;
  final double revenue;
}

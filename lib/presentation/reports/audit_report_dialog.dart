import 'package:flutter/material.dart';

import '../../domain/reports/report_models.dart';
import 'report_export_service.dart';

class AuditReportDialog extends StatefulWidget {
  const AuditReportDialog({super.key, required this.audit});
  final FinancialAuditReportData audit;

  @override
  State<AuditReportDialog> createState() => _AuditReportDialogState();
}

class _AuditReportDialogState extends State<AuditReportDialog> {
  int _section = 0;
  bool _exporting = false;

  Future<void> _export(Future<Object?> Function() action) async {
    setState(() => _exporting = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final audit = widget.audit;
    final review = audit.reconciliation;
    if (review == null) {
      return AlertDialog(
        title: const Text('INSUFFICIENT DATA'),
        content: const Text(
          'Regenerate this report with the financial reconciliation engine. Legacy estimates cannot be certified or exported.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    }
    final schedule = review.schedules[_section];
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 650;
          return SizedBox(
            width: 1240,
            height: MediaQuery.sizeOf(context).height * .92,
            child: Padding(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          FinancialReconciliation.title,
                          style: isCompact
                              ? Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  )
                              : Theme.of(context).textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    '${audit.businessName} | ${audit.dateRange.formatLabel()} | ${review.scopeLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCompact ? 11 : 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${review.status} | Automated data quality: ${review.score}/100',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isCompact ? 11 : 12,
                      color: review.status == 'RECONCILED'
                          ? Colors.green.shade800
                          : Colors.orange.shade900,
                    ),
                  ),
                  Text(
                    'Internal automated review. Not a statutory audit, CA certification or filing approval.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isCompact ? 10 : 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _exporting
                              ? null
                              : () => _export(
                                  () => ReportExportService.printAuditReport(audit),
                                ),
                          icon: const Icon(Icons.print, size: 16),
                          label: const Text('Print'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _exporting
                              ? null
                              : () => _export(
                                  () => ReportExportService.saveAuditPdf(audit),
                                ),
                          icon: const Icon(Icons.picture_as_pdf, size: 16),
                          label: const Text('Save PDF'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _exporting
                              ? null
                              : () => _export(
                                  () => ReportExportService.exportAuditExcel(audit),
                                ),
                          icon: const Icon(Icons.table_view, size: 16),
                          label: const Text('Export Excel'),
                        ),
                      ],
                    ),
                  ),
                  if (_exporting) const LinearProgressIndicator(),
                  SizedBox(height: isCompact ? 8 : 12),
                  DropdownButtonFormField<int>(
                    initialValue: _section,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Report section',
                      border: const OutlineInputBorder(),
                      isDense: isCompact,
                      contentPadding: isCompact
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                          : null,
                    ),
                    items: [
                      for (var i = 0; i < review.schedules.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            review.schedules[i].title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _section = value);
                    },
                  ),
                  SizedBox(height: isCompact ? 8 : 12),
              if (schedule.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(schedule.note),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Builder(
                      builder: (context) {
                        final cols = schedule.columns.isEmpty
                            ? const ['Details']
                            : schedule.columns;
                        return DataTable(
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 180,
                          columns: cols
                              .map(
                                (v) => DataColumn(
                                  label: Text(
                                    v,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          rows: schedule.rows.isEmpty
                              ? [
                                  DataRow(
                                    cells: List.generate(
                                      cols.length,
                                      (i) => DataCell(
                                        Text(
                                          i == 0
                                              ? 'No observed records. See source coverage.'
                                              : '',
                                        ),
                                      ),
                                    ),
                                  ),
                                ]
                              : schedule.rows
                                    .map(
                                      (row) => DataRow(
                                        cells: List.generate(
                                          cols.length,
                                          (i) => DataCell(
                                            SizedBox(
                                              width: cols.length > 3
                                                  ? 170
                                                  : 360,
                                              child: SelectableText(
                                                i < row.length ? row[i] : '—',
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  ),
);
  }
}

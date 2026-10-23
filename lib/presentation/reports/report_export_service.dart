import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../domain/reports/report_models.dart';

class ReportExportService {
  ReportExportService._();

  // ---------------------------------------------------------------------------
  // PDF GENERATION
  // ---------------------------------------------------------------------------

  static Future<Uint8List> generatePdf(ReportDetailData report) async {
    pw.Font font;
    pw.Font? bengali;
    pw.Font? hindi;
    try {
      font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
      );
      bengali = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'),
      );
      hindi = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
      );
    } catch (_) {
      font = pw.Font.helvetica();
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        fontFallback: [
          ?bengali,
          ?hindi,
        ],
      ),
    );

    String clean(String s) => s
        .replaceAll('₹', 'Rs. ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '*');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      clean(report.businessName),
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Outlet: ${clean(report.outletName)}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      clean(report.title.toUpperCase()),
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.Text(
                      'Period: ${clean(report.dateRange.formatLabel())}',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(thickness: 0.5, color: PdfColors.grey300),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated on ${report.generatedAt.toLocal().toString().split('.').first} | Confidential',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          if (report.summaryStats.isNotEmpty) ...[
            pw.Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final s in report.summaryStats)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColors.grey100,
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          clean(s.label),
                          style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.Text(
                          clean(s.value),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            pw.SizedBox(height: 12),
          ],
          if (report.rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(32),
              child: pw.Center(
                child: pw.Text(
                  'No records found for this period.',
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: report.columns.map(clean).toList(),
              data: [
                for (final row in report.rows) row.map(clean).toList(),
                if (report.columnTotals.isNotEmpty)
                  [
                    for (int i = 0; i < report.columns.length; i++)
                      clean(report.columnTotals[i] ?? (i == 0 ? 'Total' : '')),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              rowDecoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
                ),
              ),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
            ),
          if (report.notes.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            for (final note in report.notes)
              pw.Text(
                '* ${clean(note)}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printReport(ReportDetailData report) async {
    final bytes = await generatePdf(report);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${report.tileId.name}_${report.dateRange.preset.name}',
      dynamicLayout: false,
    );
  }

  static Future<String?> savePdf(ReportDetailData report) async {
    final bytes = await generatePdf(report);
    final safeName = report.title.toLowerCase().replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    Uri? output;
    try {
      output = await FilePicker.saveFile(
        dialogTitle: 'Save PDF Report',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        mimeType: 'application/pdf',
      );
    } catch (_) {
      final shared = await Printing.sharePdf(bytes: bytes, filename: fileName);
      return shared ? 'Exported via System Print/Share' : null;
    }
    if (output == null) return null;
    final filePath = output.hasScheme && output.scheme == 'file'
        ? output.toFilePath()
        : (output.path.isNotEmpty ? output.path : output.toString());
    try {
      final file = File(filePath);
      if (!await file.exists() || (await file.length()) == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
    return filePath;
  }

  // ---------------------------------------------------------------------------
  // CSV EXPORT
  // ---------------------------------------------------------------------------

  static Future<String?> exportCsv(ReportDetailData report) async {
    final csvRows = <List<dynamic>>[];

    // Report Header Information
    csvRows.add([report.businessName, 'Outlet: ${report.outletName}']);
    csvRows.add([
      'Report: ${report.title}',
      'Period: ${report.dateRange.formatLabel()}',
    ]);
    csvRows.add([
      'Generated on:',
      report.generatedAt.toLocal().toString().split('.').first,
    ]);
    csvRows.add([]);

    // Summary Stats
    if (report.summaryStats.isNotEmpty) {
      csvRows.add(['Summary Totals']);
      for (final s in report.summaryStats) {
        csvRows.add([s.label, s.value]);
      }
      csvRows.add([]);
    }

    // Detail Columns & Rows
    csvRows.add(report.columns);
    for (final row in report.rows) {
      csvRows.add(row);
    }

    // Column Totals
    if (report.columnTotals.isNotEmpty) {
      final totalRow = <String>[];
      for (int i = 0; i < report.columns.length; i++) {
        totalRow.add(report.columnTotals[i] ?? (i == 0 ? 'Total' : ''));
      }
      csvRows.add(totalRow);
    }

    final csvString = csv.encode(csvRows);
    final bytes = Uint8List.fromList(utf8.encode(csvString));
    final safeName = report.title.toLowerCase().replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final fileName = '${safeName}_${DateTime.now().millisecondsSinceEpoch}.csv';

    try {
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export CSV',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        mimeType: 'text/csv',
      );
      if (output == null) return null;
      final filePath = output.hasScheme && output.scheme == 'file'
          ? output.toFilePath()
          : (output.path.isNotEmpty ? output.path : output.toString());
      try {
        final file = File(filePath);
        if (!await file.exists() || (await file.length()) == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {}
      return filePath;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // EXCEL (.xlsx) EXPORT
  // ---------------------------------------------------------------------------

  static Future<String?> exportExcel(ReportDetailData report) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final safeTitle = (report.title.length > 30
            ? report.title.substring(0, 30)
            : report.title)
        .replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ');
    excel.rename(defaultSheet, safeTitle);
    final sheet = excel[safeTitle];

    // Meta Header
    sheet.appendRow([
      TextCellValue(report.businessName),
      TextCellValue('Outlet: ${report.outletName}'),
    ]);
    sheet.appendRow([
      TextCellValue('Report: ${report.title}'),
      TextCellValue('Period: ${report.dateRange.formatLabel()}'),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Generated: ${report.generatedAt.toLocal().toString().split('.').first}',
      ),
    ]);
    sheet.appendRow([TextCellValue('')]);

    // Summary
    if (report.summaryStats.isNotEmpty) {
      sheet.appendRow([TextCellValue('Key Metrics')]);
      for (final s in report.summaryStats) {
        sheet.appendRow([TextCellValue(s.label), TextCellValue(s.value)]);
      }
      sheet.appendRow([TextCellValue('')]);
    }

    // Columns
    sheet.appendRow([for (final c in report.columns) TextCellValue(c)]);

    // Rows
    for (final row in report.rows) {
      sheet.appendRow([for (final cell in row) TextCellValue(cell)]);
    }

    // Totals
    if (report.columnTotals.isNotEmpty) {
      final totalRow = <CellValue>[];
      for (int i = 0; i < report.columns.length; i++) {
        totalRow.add(
          TextCellValue(report.columnTotals[i] ?? (i == 0 ? 'Total' : '')),
        );
      }
      sheet.appendRow(totalRow);
    }

    final fileBytes = excel.save();
    if (fileBytes == null) return null;
    final bytes = Uint8List.fromList(fileBytes);
    final safeName = report.title.toLowerCase().replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final fileName =
        '${safeName}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

    try {
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export Excel Workbook',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (output == null) return null;
      final filePath = output.hasScheme && output.scheme == 'file'
          ? output.toFilePath()
          : (output.path.isNotEmpty ? output.path : output.toString());
      try {
        final file = File(filePath);
        if (!await file.exists() || (await file.length()) == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {}
      return filePath;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // COMPLETE FINANCIAL & TAX AUDIT EXPORT (PDF, PRINT, EXCEL)
  // ---------------------------------------------------------------------------

  static String _cleanText(String s) => s
      .replaceAll('₹', 'Rs. ')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('•', '*');

  static Future<Uint8List> generateAuditPdf(
    FinancialAuditReportData audit,
  ) async {
    final review = audit.reconciliation;
    if (review == null) {
      throw StateError(
        'Regenerate the legacy report; reconciliation evidence is required.',
      );
    }
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bengali = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'),
    );
    final hindi = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
    );
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        fontFallback: [bengali, hindi],
      ),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 1000,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              FinancialReconciliation.title,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _cleanText(
                '${audit.businessName} | ${audit.dateRange.formatLabel()}',
              ),
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Report Scope: ${review.scopeLabel}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              _cleanText(
                'Business IDs: ${audit.businessId} | Included outlets: see inclusion schedule',
              ),
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Divider(),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(),
            pw.Text(
              _cleanText(
                'Internal automated review - not certified | Generated by ${review.generatedBy} | ${audit.generatedAt.toIso8601String()}',
              ),
              style: const pw.TextStyle(fontSize: 6.5),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount} | ${review.scopeLabel}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
        build: (context) => [
          pw.Text(
            _cleanText(
              '${review.status} | Automated data quality ${review.score}/100',
            ),
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'This report is not a statutory audit, CA certification, tax advice or filing approval. Missing values are shown as INSUFFICIENT DATA.',
            style: const pw.TextStyle(fontSize: 9),
          ),
          for (final schedule in review.schedules) ...[
            pw.NewPage(freeSpace: 100),
            pw.SizedBox(height: 14),
            pw.Text(
              _cleanText(schedule.title),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            if (schedule.note.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                child: pw.Text(
                  _cleanText(schedule.note),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            pw.TableHelper.fromTextArray(
              headers: schedule.columns.map(_cleanText).toList(),
              columnWidths: _auditColumnWidths(schedule),
              data: schedule.rows.isEmpty
                  ? [
                      List.generate(
                        schedule.columns.length,
                        (i) => i == 0
                            ? 'No observed records; see source coverage.'
                            : '',
                      ),
                    ]
                  : schedule.rows
                        .map((r) => r.map(_cleanText).toList())
                        .toList(),
              headerStyle: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blueGrey800,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellPadding: const pw.EdgeInsets.all(4),
              oddRowDecoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
              ),
              border: pw.TableBorder.all(color: PdfColors.grey400, width: .3),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Map<int, pw.TableColumnWidth> _auditColumnWidths(
    AuditSchedule schedule,
  ) {
    final weights = switch (schedule.title) {
      'Business and outlet inclusion' => [1.2, 1.8, 1.2, 3.4, 1.8, 1.8],
      'Automated validation and scoring' => [2.4, 1.8, 1.3, 5.5],
      'Statutory validation checklist' => [2.4, 1.8, 5.8],
      'Source evidence index' => [1.1, 2.6, 4.0, 1.8, 3.0, 1.7],

      'Data completeness and sync checkpoints' => [3.8, 1.0, 2.4, 2.8, 2.0],
      'GST rate and classification reconciliation' => [
        3.4,
        2.0,
        1.8,
        1.5,
        1.5,
        1.5,
        1.5,
      ],
      'HSN / SAC reconciliation' => [3.4, 3.1, 1.8, 1.5, 1.5, 1.5, 1.5],
      'Item and outlet inventory audit' => [3.1, 1.2, 1.2, 1.2, 1.2, 2.4, 2.8],
      _ =>
        schedule.columns.length == 2
            ? [3.8, 2.2]
            : schedule.columns.length == 3
            ? [2.0, 6.0, 2.0]
            : <double>[],
    };
    return {
      for (var i = 0; i < weights.length; i++)
        i: pw.FlexColumnWidth(weights[i].toDouble()),
    };
  }

  static Future<void> printAuditReport(FinancialAuditReportData audit) async {
    final bytes = await generateAuditPdf(audit);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name:
          'Audit_Report_${audit.businessName.replaceAll(RegExp(r'\s+'), '_')}',
      dynamicLayout: false,
    );
  }

  static Future<String?> saveAuditPdf(FinancialAuditReportData audit) async {
    final bytes = await generateAuditPdf(audit);
    final safeName = audit.businessName.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final fileName =
        'Financial_Reconciliation_${safeName.length > 80 ? safeName.substring(0, 80) : safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    Uri? output;
    try {
      output = await FilePicker.saveFile(
        dialogTitle: 'Save financial reconciliation report (PDF)',
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        mimeType: 'application/pdf',
      );
    } catch (_) {
      final shared = await Printing.sharePdf(bytes: bytes, filename: fileName);
      return shared ? 'Exported via System Print/Share' : null;
    }
    if (output == null) return null;
    final filePath = output.hasScheme && output.scheme == 'file'
        ? output.toFilePath()
        : (output.path.isNotEmpty ? output.path : output.toString());
    try {
      final file = File(filePath);
      if (!await file.exists() || (await file.length()) == 0) {
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
    return filePath;
  }

  static Uint8List generateAuditWorkbook(FinancialAuditReportData audit) {
    final review = audit.reconciliation;
    if (review == null) {
      throw StateError('Reconciliation evidence is required.');
    }
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Report scope');
    final summary = excel['Report scope'];
    for (final row in [
      [FinancialReconciliation.title],
      [audit.businessName, audit.businessId],
      [review.scopeLabel, audit.outletId],
      [audit.dateRange.formatLabel()],
      [review.status, 'Internal data quality ${review.score}/100'],
      ['Generated by', review.generatedBy, audit.generatedAt.toIso8601String()],
      ...review.limitations.map((s) => [s]),
    ]) {
      summary.appendRow(row.map((v) => TextCellValue(v)).toList());
    }
    var index = 0;
    for (final schedule in review.schedules) {
      index++;
      final name = '$index ${schedule.title}'.replaceAll(
        RegExp(r'[:\\/?*\[\]]'),
        ' ',
      );
      final sheet = excel[name.length > 31 ? name.substring(0, 31) : name];
      sheet.appendRow([TextCellValue(schedule.title)]);
      sheet.appendRow([TextCellValue(review.scopeLabel)]);
      if (schedule.note.isNotEmpty) {
        sheet.appendRow([TextCellValue(schedule.note)]);
      }
      sheet.appendRow(schedule.columns.map((v) => TextCellValue(v)).toList());
      for (final row in schedule.rows) {
        sheet.appendRow(row.map((v) => TextCellValue(v)).toList());
      }
    }
    return Uint8List.fromList(excel.save()!);
  }

  static Future<String?> exportAuditExcel(
    FinancialAuditReportData audit,
  ) async {
    final bytes = generateAuditWorkbook(audit);
    final filename =
        'Financial_Reconciliation_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    try {
      final output = await FilePicker.saveFile(
        dialogTitle: 'Export financial reconciliation',
        fileName: filename,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (output == null) return null;
      final filePath = output.hasScheme && output.scheme == 'file'
          ? output.toFilePath()
          : (output.path.isNotEmpty ? output.path : output.toString());
      try {
        final file = File(filePath);
        if (!await file.exists() || (await file.length()) == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      } catch (_) {}
      return filePath;
    } catch (_) {
      return null;
    }
  }
}

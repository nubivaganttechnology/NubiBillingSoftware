import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../presentation/procurement/widgets/supplier_ledger_localizations.dart';
import '../models/supplier_ledger_entry_model.dart';
import '../models/supplier_model.dart';

class SupplierStatementExportService {
  SupplierStatementExportService._();

  static Future<Uint8List> generatePdf({
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    required SupplierModel supplier,
    required List<SupplierLedgerEntryModel> entries,
    required DateTime fromDate,
    required DateTime toDate,
    required int openingBalancePaise,
    required int totalPurchasesPaise,
    required int totalPaymentsPaise,
    required int closingBalancePaise,
    SupplierLedgerStrings? strings,
  }) async {
    final s = strings ?? const SupplierLedgerStrings('en');
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

    final toLabel = s.isBn ? 'থেকে' : s.isHi ? 'से' : 'to';
    final dateRangeStr =
        '${_formatDate(fromDate)} $toLabel ${_formatDate(toDate)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildHeader(
          businessName: businessName,
          businessAddress: businessAddress,
          businessPhone: businessPhone,
          businessGstin: businessGstin,
          supplier: supplier,
          dateRange: dateRangeStr,
          pageNum: context.pageNumber,
          totalPages: context.pagesCount,
          s: s,
        ),
        footer: (context) => _buildFooter(context, s),
        build: (context) => [
          pw.SizedBox(height: 10),
          _buildSummaryCards(
            openingBalance: openingBalancePaise,
            totalPurchases: totalPurchasesPaise,
            totalPayments: totalPaymentsPaise,
            closingBalance: closingBalancePaise,
            s: s,
          ),
          pw.SizedBox(height: 14),
          _buildTable(entries, s),
          pw.SizedBox(height: 14),
          _buildClosingSummary(
            closingBalance: closingBalancePaise,
            s: s,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printStatement({
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    required SupplierModel supplier,
    required List<SupplierLedgerEntryModel> entries,
    required DateTime fromDate,
    required DateTime toDate,
    required int openingBalancePaise,
    required int totalPurchasesPaise,
    required int totalPaymentsPaise,
    required int closingBalancePaise,
    SupplierLedgerStrings? strings,
  }) async {
    final bytes = await generatePdf(
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessGstin: businessGstin,
      supplier: supplier,
      entries: entries,
      fromDate: fromDate,
      toDate: toDate,
      openingBalancePaise: openingBalancePaise,
      totalPurchasesPaise: totalPurchasesPaise,
      totalPaymentsPaise: totalPaymentsPaise,
      closingBalancePaise: closingBalancePaise,
      strings: strings,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Statement_${supplier.name.replaceAll(' ', '_')}.pdf',
    );
  }

  static Future<void> sharePdf({
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    required SupplierModel supplier,
    required List<SupplierLedgerEntryModel> entries,
    required DateTime fromDate,
    required DateTime toDate,
    required int openingBalancePaise,
    required int totalPurchasesPaise,
    required int totalPaymentsPaise,
    required int closingBalancePaise,
    SupplierLedgerStrings? strings,
  }) async {
    final bytes = await generatePdf(
      businessName: businessName,
      businessAddress: businessAddress,
      businessPhone: businessPhone,
      businessGstin: businessGstin,
      supplier: supplier,
      entries: entries,
      fromDate: fromDate,
      toDate: toDate,
      openingBalancePaise: openingBalancePaise,
      totalPurchasesPaise: totalPurchasesPaise,
      totalPaymentsPaise: totalPaymentsPaise,
      closingBalancePaise: closingBalancePaise,
      strings: strings,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Statement_${supplier.name.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _buildHeader({
    required String businessName,
    String? businessAddress,
    String? businessPhone,
    String? businessGstin,
    required SupplierModel supplier,
    required String dateRange,
    required int pageNum,
    required int totalPages,
    required SupplierLedgerStrings s,
  }) {
    final titleText = s.isBn
        ? 'খতিয়ান ও হিসাব বিবরণী'
        : s.isHi
            ? 'खाता और हिसाब विवरण'
            : 'LEDGER ACCOUNT';

    final periodLabel = s.isBn ? 'সময়কাল' : s.isHi ? 'अवधि' : 'Period';
    final pageLabel = s.isBn
        ? 'পৃষ্ঠা $pageNum / $totalPages'
        : s.isHi
            ? 'पृष्ठ $pageNum / $totalPages'
            : 'Page $pageNum of $totalPages';

    final addressLabel = s.isBn ? 'ঠিকানা' : s.isHi ? 'पता' : 'Address';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    businessName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900,
                    ),
                  ),
                  if (businessAddress != null && businessAddress.isNotEmpty)
                    pw.Text(
                      businessAddress,
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  if (businessPhone != null && businessPhone.isNotEmpty)
                    pw.Text(
                      '${s.phone}: $businessPhone',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  if (businessGstin != null && businessGstin.isNotEmpty)
                    pw.Text(
                      '${s.gstin}: $businessGstin',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  titleText,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
                pw.Text(
                  '$periodLabel: $dateRange',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                pw.Text(
                  pageLabel,
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(4),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${s.supplier}: ${supplier.name}',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  if (supplier.contactPerson != null && supplier.contactPerson!.isNotEmpty)
                    pw.Text('${s.contactPerson}: ${supplier.contactPerson}', style: const pw.TextStyle(fontSize: 9)),
                  if (supplier.address != null && supplier.address!.isNotEmpty)
                    pw.Text('$addressLabel: ${supplier.address}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (supplier.mobile != null && supplier.mobile!.isNotEmpty)
                    pw.Text('${s.phone}: ${supplier.mobile}', style: const pw.TextStyle(fontSize: 9)),
                  if (supplier.gstin != null && supplier.gstin!.isNotEmpty)
                    pw.Text('${s.gstin}: ${supplier.gstin}', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
      ],
    );
  }

  static pw.Widget _buildSummaryCards({
    required int openingBalance,
    required int totalPurchases,
    required int totalPayments,
    required int closingBalance,
    required SupplierLedgerStrings s,
  }) {
    final purchasesCardTitle = '${s.totalPurchases} (${s.crLabel})';
    final paymentsCardTitle = '${s.totalPayments} (${s.drLabel})';

    return pw.Row(
      children: [
        _summaryCard(s.openingBalance, openingBalance, PdfColors.blueGrey800),
        pw.SizedBox(width: 8),
        _summaryCard(purchasesCardTitle, totalPurchases, PdfColors.indigo800),
        pw.SizedBox(width: 8),
        _summaryCard(paymentsCardTitle, totalPayments, PdfColors.green800),
        pw.SizedBox(width: 8),
        _summaryCard(
          s.currentBalance,
          closingBalance.abs(),
          closingBalance > 0 ? PdfColors.red800 : PdfColors.green800,
          suffix: closingBalance > 0 ? ' ${s.payableSuffix}' : (closingBalance < 0 ? ' ${s.advanceSuffix}' : ''),
        ),
      ],
    );
  }

  static pw.Widget _summaryCard(String title, int paise, PdfColor color, {String suffix = ''}) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          borderRadius: pw.BorderRadius.circular(4),
          color: PdfColors.grey50,
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(
              'Rs ${_money(paise)}$suffix',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildTable(List<SupplierLedgerEntryModel> entries, SupplierLedgerStrings s) {
    final paidColHeader = '${s.paidLabel} (${s.drLabel})';
    final billedColHeader = '${s.isBn ? 'ক্রয়' : s.isHi ? 'खरीद' : 'Billed'} (${s.crLabel})';

    final headers = [
      s.dateCol,
      s.particularsCol,
      s.vchTypeCol,
      s.vchNoCol,
      paidColHeader,
      billedColHeader,
      s.runningBalCol,
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: entries.map((e) {
        String vchNo;
        final vch = e.voucherNumber?.trim() ?? '';
        final ref = e.referenceNo?.trim() ?? '';
        final refId = e.referenceId?.trim() ?? '';
        if (vch.isNotEmpty && ref.isNotEmpty && vch != ref) {
          vchNo = '$vch / $ref';
        } else if (vch.isNotEmpty) {
          vchNo = vch;
        } else if (ref.isNotEmpty) {
          vchNo = ref;
        } else if (refId.isNotEmpty) {
          vchNo = refId;
        } else {
          vchNo = '-';
        }

        String particularsText;
        if (e.particulars != null && e.particulars!.trim().isNotEmpty) {
          particularsText = e.particulars!.trim();
        } else if (e.itemsSummary != null && e.itemsSummary!.trim().isNotEmpty) {
          particularsText = e.itemsSummary!.trim();
        } else if (e.isPurchase) {
          particularsText = vch.isNotEmpty
              ? '${s.localizedEntryType(e.entryType)} #$vch'
              : s.localizedEntryType(e.entryType);
        } else if (e.isPayment) {
          final mode = e.paymentMode != null ? s.localizedPaymentMode(e.paymentMode!) : '';
          if (mode.isNotEmpty && ref.isNotEmpty) {
            particularsText = '${s.localizedEntryType(e.entryType)} ($mode) Ref: $ref';
          } else if (mode.isNotEmpty) {
            particularsText = '${s.localizedEntryType(e.entryType)} ($mode)';
          } else {
            particularsText = s.localizedEntryType(e.entryType);
          }
        } else {
          particularsText = s.localizedEntryType(e.entryType);
        }

        final debitStr = e.debitPaise > 0 ? _money(e.debitPaise) : '';
        final creditStr = e.creditPaise > 0 ? _money(e.creditPaise) : '';
        final balanceStr = '${_money(e.runningBalancePaise.abs())} ${e.runningBalancePaise >= 0 ? s.crLabel : s.drLabel}';

        return [
          _formatDate(e.transactionDate),
          particularsText,
          s.localizedEntryType(e.entryType),
          vchNo,
          debitStr,
          creditStr,
          balanceStr,
        ];
      }).toList(),
      headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellHeight: 22,
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerLeft,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(60),
        1: const pw.FlexColumnWidth(3.0),
        2: const pw.FixedColumnWidth(65),
        3: const pw.FixedColumnWidth(80),
        4: const pw.FixedColumnWidth(60),
        5: const pw.FixedColumnWidth(60),
        6: const pw.FixedColumnWidth(70),
      },
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
    );
  }

  static pw.Widget _buildClosingSummary({
    required int closingBalance,
    required SupplierLedgerStrings s,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            s.netClosingBalance,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Rs ${_money(closingBalance.abs())} ${closingBalance >= 0 ? s.payableSuffix : s.advanceSuffix}',
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: closingBalance > 0 ? PdfColors.red800 : PdfColors.green800,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter(pw.Context context, SupplierLedgerStrings s) {
    final note = s.isBn
        ? 'সফটওয়্যার দ্বারা প্রস্তুতকৃত স্টেটমেন্ট - কোনো স্বাক্ষরের প্রয়োজন নেই'
        : s.isHi
            ? 'कंप्यूटर जनरेटेड स्टेटमेंट - हस्ताक्षर की आवश्यकता नहीं'
            : 'Computer Generated Statement - No Signature Required';

    return pw.Column(
      children: [
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated via NubiBilling Software',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
            pw.Text(
              note,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year.toString().substring(2)}';
  }

  static String _money(int paise) {
    final rs = paise / 100.0;
    return rs.toStringAsFixed(2);
  }
}

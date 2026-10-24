import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/supplier_payment_receipt_model.dart';
import 'supplier_ledger_localizations.dart';

/// Modal dialog displaying a supplier payment voucher with summary metrics,
/// bill settlement breakdown, WhatsApp sharing, and thermal/A4 slip printing.
class SupplierPaymentVoucherDialog extends StatelessWidget {
  final SupplierPaymentReceiptModel receipt;

  const SupplierPaymentVoucherDialog({
    super.key,
    required this.receipt,
  });

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $hr:$min';
  }

  Future<void> _shareOnWhatsApp(BuildContext context) async {
    final langCode = Localizations.localeOf(context).languageCode;
    final message = receipt.generateWhatsAppMessage(languageCode: langCode);
    final rawPhone = receipt.supplierPhone?.replaceAll(RegExp(r'\D'), '') ?? '';
    final phone = rawPhone.length == 10 ? '91$rawPhone' : rawPhone;

    if (phone.isNotEmpty) {
      final url = 'https://wa.me/$phone?text=${Uri.encodeComponent(message)}';
      final uri = Uri.parse(url);
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) return;
      } catch (_) {}
    }

    // Fallback: system share sheet
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Payment Voucher - ${receipt.voucherNumber ?? receipt.paymentId}',
        ),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: message));
      if (context.mounted) {
        final s = SupplierLedgerStrings.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.copiedToast),
          ),
        );
      }
    }
  }

  Future<void> _copyMessage(BuildContext context) async {
    final langCode = Localizations.localeOf(context).languageCode;
    final message = receipt.generateWhatsAppMessage(languageCode: langCode);
    final s = SupplierLedgerStrings.of(context);
    await Clipboard.setData(ClipboardData(text: message));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.copiedToast),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<Uint8List> _generatePdfSlip(PdfPageFormat format, [SupplierLedgerStrings? strings]) async {
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

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        fontFallback: [
          ?bengali,
          ?hindi,
        ],
      ),
    );

    final titleText = s.isBn
        ? 'পেমেন্ট রসিদ'
        : s.isHi
            ? 'भुगतान वाउचर'
            : 'PAYMENT VOUCHER';

    final thankYouText = s.isBn
        ? 'লেনদেনের জন্য ধন্যবাদ!'
        : s.isHi
            ? 'व्यापार के लिए धन्यवाद!'
            : 'Thank you for your business!';

    final branchLabel = s.isBn ? 'শাখা' : s.isHi ? 'शाखा' : 'Branch';
    final billNoLabel = s.isBn ? 'বিল নং' : s.isHi ? 'बिल नं' : 'Bill No';
    final statusLabel = s.isBn ? 'অবস্থা' : s.isHi ? 'स्थिति' : 'Status';
    final authSignLabel = s.isBn ? 'অনুমোদিত স্বাক্ষর' : s.isHi ? 'अधिकृत हस्ताक्षर' : 'Authorized Signature';
    final recSignLabel = s.isBn ? 'গ্রহীতার স্বাক্ষর' : s.isHi ? 'प्राप्तकर्ता के हस्ताक्षर' : 'Receiver Signature';

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Center(
                child: pw.Text(
                  receipt.businessName.isNotEmpty
                      ? receipt.businessName.toUpperCase()
                      : titleText,
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
              ),
              if (receipt.outletName != null && receipt.outletName!.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    '$branchLabel: ${receipt.outletName}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey700),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    titleText,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.8),

              // Voucher & Supplier Info
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${s.voucherNo}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(receipt.voucherNumber ?? receipt.paymentId,
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${s.dateTime}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(_formatDate(receipt.paymentDate),
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${s.supplier}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(receipt.supplierName,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              if (receipt.supplierPhone != null && receipt.supplierPhone!.isNotEmpty)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${s.phone}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(receipt.supplierPhone!,
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('${s.paymentMode}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(s.localizedPaymentMode(receipt.paymentMode),
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
              if (receipt.referenceNo != null && receipt.referenceNo!.isNotEmpty)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${s.refUtr}:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text(receipt.referenceNo!,
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.8),

              // Financial Summary Box
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${s.previousDue}:',
                            style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Rs. ${receipt.previousDueRs.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${s.amountPaid}:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.green800)),
                        pw.Text('Rs. ${receipt.amountPaidRs.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green800)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Divider(thickness: 0.5),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${s.remainingDue}:',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('Rs. ${receipt.remainingDueRs.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                    if (receipt.unallocatedAdvancePaise > 0) ...[
                      pw.SizedBox(height: 2),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('${s.advanceBalance}:',
                              style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800)),
                          pw.Text('Rs. ${receipt.unallocatedAdvanceRs.toStringAsFixed(2)}',
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.blue800)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Settled Bills Breakdown
              if (receipt.settledBills.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('${s.billSettlementBreakdown}:',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(billNoLabel, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(s.paidLabel,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(s.remainingLabel,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(statusLabel,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                        ),
                      ],
                    ),
                    for (final bill in receipt.settledBills)
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(3),
                            child: pw.Text('#${bill.invoiceNumber}',
                                style: const pw.TextStyle(fontSize: 8)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(3),
                            child: pw.Text(bill.allocatedRs.toStringAsFixed(2),
                                textAlign: pw.TextAlign.right,
                                style: const pw.TextStyle(fontSize: 8)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(3),
                            child: pw.Text(bill.remainingDueRs.toStringAsFixed(2),
                                textAlign: pw.TextAlign.right,
                                style: const pw.TextStyle(fontSize: 8)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(3),
                            child: pw.Text(
                              bill.isFullyPaid
                                  ? (s.isBn ? 'পরিশোধিত' : s.isHi ? 'चुकाया गया' : 'PAID')
                                  : (s.isBn ? 'আংশিক' : s.isHi ? 'आंशिक' : 'PARTIAL'),
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 8,
                                  color: bill.isFullyPaid
                                      ? PdfColors.green800
                                      : PdfColors.orange800),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],

              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(height: 14),
                      pw.Text(authSignLabel,
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.SizedBox(height: 14),
                      pw.Text(recSignLabel,
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(thankYouText,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _printSlip(BuildContext context) async {
    final s = SupplierLedgerStrings.of(context);
    try {
      await Printing.layoutPdf(
        onLayout: (format) => _generatePdfSlip(format, s),
        name: 'Voucher_${receipt.voucherNumber ?? receipt.paymentId}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SupplierLedgerStrings.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Green Check Icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Colors.green.shade700,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.paymentVoucherTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          s.paymentVoucherSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: s.close,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Supplier & Meta Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _infoRow(s.supplier, receipt.supplierName, bold: true),
                    if (receipt.supplierPhone != null && receipt.supplierPhone!.isNotEmpty)
                      _infoRow(s.phone, receipt.supplierPhone!),
                    _infoRow(s.voucherNo, receipt.voucherNumber ?? receipt.paymentId),
                    _infoRow(s.dateTime, _formatDate(receipt.paymentDate)),
                    _infoRow(s.paymentMode, s.localizedPaymentMode(receipt.paymentMode)),
                    if (receipt.referenceNo != null && receipt.referenceNo!.isNotEmpty)
                      _infoRow(s.refUtr, receipt.referenceNo!),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Financial Highlight Box (The core feature requested by user)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  children: [
                    _kpiRow(
                      label: '${s.previousDue}:',
                      amountStr: '₹${receipt.previousDueRs.toStringAsFixed(2)}',
                      color: Colors.grey.shade800,
                      isBold: false,
                    ),
                    const Divider(height: 16, thickness: 1),
                    _kpiRow(
                      label: '${s.amountPaid}:',
                      amountStr: '₹${receipt.amountPaidRs.toStringAsFixed(2)}',
                      color: Colors.green.shade800,
                      isBold: true,
                      fontSize: 16,
                    ),
                    const Divider(height: 16, thickness: 1),
                    _kpiRow(
                      label: '${s.remainingDue}:',
                      amountStr: '₹${receipt.remainingDueRs.toStringAsFixed(2)}',
                      color: receipt.remainingDuePaise > 0
                          ? Colors.red.shade700
                          : Colors.teal.shade700,
                      isBold: true,
                      fontSize: 17,
                    ),
                    if (receipt.unallocatedAdvancePaise > 0) ...[
                      const SizedBox(height: 6),
                      _kpiRow(
                        label: '${s.advanceCredit}:',
                        amountStr: '₹${receipt.unallocatedAdvanceRs.toStringAsFixed(2)}',
                        color: Colors.indigo.shade700,
                        isBold: true,
                      ),
                    ],
                  ],
                ),
              ),

              // Settled Bills Section
              if (receipt.settledBills.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.receipt_rounded, size: 16, color: Colors.blueGrey.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${s.billSettlementBreakdown}:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: receipt.settledBills.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, idx) {
                      final b = receipt.settledBills[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '#${b.invoiceNumber}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                  Text(
                                    '${s.billedCrCol}: ₹${b.billTotalRs.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${s.paidLabel}: ₹${b.allocatedRs.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${s.remainingLabel}: ₹${b.remainingDueRs.toStringAsFixed(2)}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: b.isFullyPaid ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: b.isFullyPaid ? Colors.green.shade300 : Colors.orange.shade300,
                                ),
                              ),
                              child: Text(
                                b.isFullyPaid
                                    ? (s.isBn ? 'পরিশোধিত' : s.isHi ? 'चुकाया गया' : 'PAID')
                                    : (s.isBn ? 'আংশিক' : s.isHi ? 'आंशिक' : 'PARTIAL'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: b.isFullyPaid ? Colors.green.shade800 : Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Action Buttons: WhatsApp Share & Print Slip
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _shareOnWhatsApp(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        s.shareWhatsApp,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _printSlip(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: Text(
                        s.printSlip,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _copyMessage(context),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: Text(s.copyReceiptText),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiRow({
    required String label,
    required String amountStr,
    required Color color,
    required bool isBold,
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize - 2,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          amountStr,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

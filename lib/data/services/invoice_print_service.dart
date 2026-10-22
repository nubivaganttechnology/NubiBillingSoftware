import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum InvoicePrintFormat {
  a4Standard,
  a5Compact,
  thermal80mm,
  thermal58mm,
  custom,
}

class InvoicePrintLine {
  const InvoicePrintLine({
    required this.name,
    this.hsn,
    required this.quantity,
    this.unit = 'Pcs',
    required this.unitPricePaise,
    this.discountPaise = 0,
    required this.taxablePaise,
    this.gstRateBps = 0,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    required this.lineTotalPaise,
  });

  final String name;
  final String? hsn;
  final double quantity;
  final String unit;
  final int unitPricePaise;
  final int discountPaise;
  final int taxablePaise;
  final int gstRateBps;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int lineTotalPaise;
}

class InvoicePrintData {
  const InvoicePrintData({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.businessName,
    this.businessTradeName,
    this.businessAddress,
    this.businessGstin,
    this.businessPan,
    this.businessPhone,
    this.businessEmail,
    this.businessState,
    this.businessStateCode,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.customerGstin,
    this.customerState,
    this.customerStateCode,
    required this.lines,
    required this.subtotalPaise,
    this.discountPaise = 0,
    required this.taxablePaise,
    this.cgstPaise = 0,
    this.sgstPaise = 0,
    this.igstPaise = 0,
    this.roundOffPaise = 0,
    required this.grandTotalPaise,
    this.paidPaise = 0,
    this.duePaise = 0,
    this.dueDate,
    this.paymentMode = 'Cash',
    this.upiId,
    this.bankName,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankAccountName,
    this.terms,
    this.cashierName,
    this.status,
  });

  final String invoiceNumber;
  final DateTime invoiceDate;
  final String businessName;
  final String? businessTradeName;
  final String? businessAddress;
  final String? businessGstin;
  final String? businessPan;
  final String? businessPhone;
  final String? businessEmail;
  final String? businessState;
  final String? businessStateCode;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String? customerGstin;
  final String? customerState;
  final String? customerStateCode;
  final List<InvoicePrintLine> lines;
  final int subtotalPaise;
  final int discountPaise;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int roundOffPaise;
  final int grandTotalPaise;
  final int paidPaise;
  final int duePaise;
  final DateTime? dueDate;
  final String paymentMode;
  final String? upiId;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? bankAccountName;
  final String? terms;
  final String? cashierName;
  final String? status;
}

class InvoicePrintService {
  static const PdfColor primaryColor = PdfColor.fromInt(0xFF0F1A2E);
  static const PdfColor secondaryColor = PdfColor.fromInt(0xFF1E3A8A);
  static const PdfColor lightHeaderBg = PdfColor.fromInt(0xFFF1F5F9);
  static const PdfColor borderColor = PdfColor.fromInt(0xFFCBD5E1);
  static const PdfColor subtleBorder = PdfColor.fromInt(0xFFE2E8F0);
  static const PdfColor textMuted = PdfColor.fromInt(0xFF64748B);

  static Future<Uint8List> buildPdf({
    required InvoicePrintData data,
    InvoicePrintFormat format = InvoicePrintFormat.a4Standard,
    double customWidthMm = 80.0,
    bool showUpiQr = true,
    bool showBankDetails = true,
    bool showHsnSummary = true,
  }) async {
    final doc = pw.Document();

    switch (format) {
      case InvoicePrintFormat.a4Standard:
        doc.addPage(_buildA4Page(data, showUpiQr, showBankDetails, showHsnSummary));
        break;
      case InvoicePrintFormat.a5Compact:
        doc.addPage(_buildA5Page(data, showUpiQr, showBankDetails, showHsnSummary));
        break;
      case InvoicePrintFormat.thermal80mm:
        doc.addPage(_buildThermalPage(data, 80.0, showUpiQr));
        break;
      case InvoicePrintFormat.thermal58mm:
        doc.addPage(_buildThermalPage(data, 58.0, showUpiQr));
        break;
      case InvoicePrintFormat.custom:
        doc.addPage(_buildThermalPage(data, customWidthMm.clamp(40.0, 150.0), showUpiQr));
        break;
    }

    return doc.save();
  }

  // A4 GST TAX INVOICE
  static pw.Page _buildA4Page(
    InvoicePrintData data,
    bool showUpiQr,
    bool showBankDetails,
    bool showHsnSummary,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header Bar
            _buildA4Header(data),
            pw.SizedBox(height: 10),

            // Seller & Buyer Details Block
            _buildA4PartyDetails(data),
            pw.SizedBox(height: 10),

            // Itemized Table
            _buildA4ItemTable(data),
            pw.SizedBox(height: 6),

            // HSN Summary & Calculation Totals
            _buildA4SummaryAndHsn(data, showHsnSummary),
            pw.SizedBox(height: 6),

            // Amount in words
            _buildAmountInWords(data.grandTotalPaise),
            pw.SizedBox(height: 8),

            // Footer Section: Bank Details, UPI QR, Terms, Authorized Signatory
            _buildA4Footer(data, showUpiQr, showBankDetails),
          ],
        );
      },
    );
  }

  // A5 COMPACT HALF-PAGE
  static pw.Page _buildA5Page(
    InvoicePrintData data,
    bool showUpiQr,
    bool showBankDetails,
    bool showHsnSummary,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildA4Header(data, compact: true),
            pw.SizedBox(height: 6),
            _buildA4PartyDetails(data, compact: true),
            pw.SizedBox(height: 6),
            _buildA4ItemTable(data, compact: true),
            pw.SizedBox(height: 4),
            _buildA4SummaryAndHsn(data, false, compact: true),
            pw.SizedBox(height: 4),
            _buildAmountInWords(data.grandTotalPaise, compact: true),
            pw.SizedBox(height: 6),
            _buildA4Footer(data, showUpiQr, showBankDetails, compact: true),
          ],
        );
      },
    );
  }

  // A4/A5 Header
  static pw.Widget _buildA4Header(InvoicePrintData data, {bool compact = false}) {
    return pw.Container(
      padding: pw.EdgeInsets.all(compact ? 8 : 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: primaryColor, width: 1.2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.businessName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: compact ? 13 : 16,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                if (data.businessTradeName != null &&
                    data.businessTradeName!.isNotEmpty &&
                    data.businessTradeName != data.businessName)
                  pw.Text(
                    '(${data.businessTradeName})',
                    style: pw.TextStyle(
                      fontSize: compact ? 8 : 9,
                      color: textMuted,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                if (data.businessAddress != null && data.businessAddress!.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    data.businessAddress!,
                    style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5, color: textMuted),
                  ),
                ],
                pw.SizedBox(height: 2),
                pw.Row(
                  children: [
                    if (data.businessGstin != null && data.businessGstin!.isNotEmpty)
                      pw.Text(
                        'GSTIN: ${data.businessGstin!}   ',
                        style: pw.TextStyle(
                          fontSize: compact ? 8 : 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    if (data.businessPhone != null && data.businessPhone!.isNotEmpty)
                      pw.Text(
                        'Phone: ${data.businessPhone!}   ',
                        style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
                      ),
                    if (data.businessState != null)
                      pw.Text(
                        'State: ${data.businessState}${data.businessStateCode != null ? ' (${data.businessStateCode})' : ''}',
                        style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  'TAX INVOICE',
                  style: pw.TextStyle(
                    fontSize: compact ? 9 : 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'ORIGINAL FOR RECIPIENT',
                style: pw.TextStyle(
                  fontSize: compact ? 6.5 : 7.5,
                  color: textMuted,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Invoice No: ${data.invoiceNumber}',
                style: pw.TextStyle(
                  fontSize: compact ? 8.5 : 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Date: ${_formatDate(data.invoiceDate)}',
                style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
              ),
              if (data.status != null && data.status!.isNotEmpty)
                pw.Text(
                  'Status: ${data.status!}',
                  style: pw.TextStyle(
                    fontSize: compact ? 7 : 8,
                    fontWeight: pw.FontWeight.bold,
                    color: data.status == 'PAID' ? PdfColors.green800 : PdfColors.blueGrey800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // Seller / Buyer party details card
  static pw.Widget _buildA4PartyDetails(InvoicePrintData data, {bool compact = false}) {
    return pw.Container(
      padding: pw.EdgeInsets.all(compact ? 6 : 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: borderColor, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Billed To
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BILLED TO / CUSTOMER DETAILS:',
                  style: pw.TextStyle(
                    fontSize: compact ? 7 : 8,
                    fontWeight: pw.FontWeight.bold,
                    color: textMuted,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  data.customerName?.isNotEmpty == true ? data.customerName! : 'Walk-in Customer',
                  style: pw.TextStyle(
                    fontSize: compact ? 8.5 : 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (data.customerPhone != null && data.customerPhone!.isNotEmpty)
                  pw.Text(
                    'Phone: ${data.customerPhone}',
                    style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
                  ),
                if (data.customerAddress != null && data.customerAddress!.isNotEmpty)
                  pw.Text(
                    'Address: ${data.customerAddress}',
                    style: pw.TextStyle(fontSize: compact ? 7 : 8, color: textMuted),
                  ),
                if (data.customerGstin != null && data.customerGstin!.isNotEmpty)
                  pw.Text(
                    'GSTIN: ${data.customerGstin}',
                    style: pw.TextStyle(
                      fontSize: compact ? 7.5 : 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          pw.Container(width: 1, height: compact ? 40 : 50, color: subtleBorder),
          pw.SizedBox(width: 12),
          // Invoice & Payment Details
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'PAYMENT & DISPATCH DETAILS:',
                  style: pw.TextStyle(
                    fontSize: compact ? 7 : 8,
                    fontWeight: pw.FontWeight.bold,
                    color: textMuted,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment Mode:', style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5)),
                    pw.Text(
                      data.paymentMode,
                      style: pw.TextStyle(
                        fontSize: compact ? 7.5 : 8.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (data.dueDate != null)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Due Date:', style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5)),
                      pw.Text(
                        _formatDate(data.dueDate!),
                        style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
                      ),
                    ],
                  ),
                if (data.cashierName != null && data.cashierName!.isNotEmpty)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Cashier / Staff:', style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5)),
                      pw.Text(
                        data.cashierName!,
                        style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
                      ),
                    ],
                  ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Place of Supply:', style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5)),
                    pw.Text(
                      data.businessState ?? 'State (Inter/Intra)',
                      style: pw.TextStyle(fontSize: compact ? 7.5 : 8.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Itemized Table
  static pw.Widget _buildA4ItemTable(InvoicePrintData data, {bool compact = false}) {
    final headers = [
      '#',
      'Item Description',
      'HSN',
      'Qty',
      'Rate',
      'Disc',
      'Taxable',
      'GST',
      'Total',
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: borderColor, width: 0.6),
      columnWidths: {
        0: const pw.FixedColumnWidth(20),
        1: const pw.FlexColumnWidth(3.2),
        2: const pw.FixedColumnWidth(42),
        3: const pw.FixedColumnWidth(38),
        4: const pw.FixedColumnWidth(48),
        5: const pw.FixedColumnWidth(36),
        6: const pw.FixedColumnWidth(50),
        7: const pw.FixedColumnWidth(38),
        8: const pw.FixedColumnWidth(56),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: lightHeaderBg),
          children: [
            for (final h in headers)
              pw.Padding(
                padding: pw.EdgeInsets.symmetric(horizontal: 3, vertical: compact ? 3 : 5),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(
                    fontSize: compact ? 7 : 8,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryColor,
                  ),
                  textAlign: (h == 'Item Description' || h == '#')
                      ? pw.TextAlign.left
                      : pw.TextAlign.right,
                ),
              ),
          ],
        ),
        // Item Rows
        for (var i = 0; i < data.lines.length; i++)
          () {
            final line = data.lines[i];
            return pw.TableRow(
              decoration: i.isEven
                  ? null
                  : const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAFAFC)),
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    '${i + 1}',
                    style: pw.TextStyle(fontSize: compact ? 7 : 8),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    line.name,
                    style: pw.TextStyle(
                      fontSize: compact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    line.hsn?.isNotEmpty == true ? line.hsn! : '-',
                    style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5, color: textMuted),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    '${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity} ${line.unit}',
                    style: pw.TextStyle(fontSize: compact ? 7 : 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    _rupees(line.unitPricePaise),
                    style: pw.TextStyle(fontSize: compact ? 7 : 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    line.discountPaise > 0 ? _rupees(line.discountPaise) : '-',
                    style: pw.TextStyle(fontSize: compact ? 7 : 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    _rupees(line.taxablePaise),
                    style: pw.TextStyle(fontSize: compact ? 7 : 8),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    '${(line.gstRateBps / 100).toStringAsFixed(0)}%',
                    style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(
                    _rupees(line.lineTotalPaise),
                    style: pw.TextStyle(
                      fontSize: compact ? 7 : 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            );
          }(),
      ],
    );
  }

  // Summary and HSN Tax Table
  static pw.Widget _buildA4SummaryAndHsn(
    InvoicePrintData data,
    bool showHsnSummary, {
    bool compact = false,
  }) {
    // Group items by HSN for GST compliance summary
    final hsnMap = <String, _HsnGroup>{};
    for (final line in data.lines) {
      final code = line.hsn?.isNotEmpty == true ? line.hsn! : 'N/A';
      final current = hsnMap.putIfAbsent(
        code,
        () => _HsnGroup(
          hsn: code,
          rateBps: line.gstRateBps,
          taxablePaise: 0,
          cgstPaise: 0,
          sgstPaise: 0,
        ),
      );
      current.taxablePaise += line.taxablePaise;
      current.cgstPaise += line.cgstPaise;
      current.sgstPaise += line.sgstPaise;
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Left side: HSN Summary table
        if (showHsnSummary && !compact) ...[
          pw.Expanded(
            flex: 3,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderColor, width: 0.6),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    color: lightHeaderBg,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'HSN/SAC TAX SUMMARY',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.Text(
                          'CGST + SGST (INR)',
                          style: pw.TextStyle(fontSize: 6.5, color: textMuted),
                        ),
                      ],
                    ),
                  ),
                  pw.Table(
                    border: pw.TableBorder.symmetric(
                      inside: pw.BorderSide(color: subtleBorder, width: 0.5),
                    ),
                    children: [
                      pw.TableRow(
                        children: [
                          _hsnCell('HSN', isHeader: true),
                          _hsnCell('Taxable', isHeader: true, alignRight: true),
                          _hsnCell('CGST', isHeader: true, alignRight: true),
                          _hsnCell('SGST', isHeader: true, alignRight: true),
                          _hsnCell('Total Tax', isHeader: true, alignRight: true),
                        ],
                      ),
                      for (final h in hsnMap.values)
                        pw.TableRow(
                          children: [
                            _hsnCell(h.hsn),
                            _hsnCell(_rupees(h.taxablePaise), alignRight: true),
                            _hsnCell(_rupees(h.cgstPaise), alignRight: true),
                            _hsnCell(_rupees(h.sgstPaise), alignRight: true),
                            _hsnCell(_rupees(h.cgstPaise + h.sgstPaise), alignRight: true),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pw.SizedBox(width: 12),
        ] else
          pw.Spacer(),

        // Right side: Totals card
        pw.Expanded(
          flex: compact ? 5 : 2,
          child: pw.Container(
            padding: pw.EdgeInsets.all(compact ? 5 : 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: primaryColor, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                _summaryRow('Subtotal:', _rupees(data.subtotalPaise), compact: compact),
                if (data.discountPaise > 0)
                  _summaryRow(
                    'Discount:',
                    '-${_rupees(data.discountPaise)}',
                    color: PdfColors.red800,
                    compact: compact,
                  ),
                _summaryRow('Taxable Value:', _rupees(data.taxablePaise), compact: compact),
                if (data.cgstPaise > 0)
                  _summaryRow('CGST:', _rupees(data.cgstPaise), compact: compact),
                if (data.sgstPaise > 0)
                  _summaryRow('SGST:', _rupees(data.sgstPaise), compact: compact),
                if (data.igstPaise > 0)
                  _summaryRow('IGST:', _rupees(data.igstPaise), compact: compact),
                if (data.roundOffPaise != 0)
                  _summaryRow(
                    'Round Off:',
                    _rupees(data.roundOffPaise),
                    compact: compact,
                  ),
                pw.Divider(color: primaryColor, thickness: 1),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  color: lightHeaderBg,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'GRAND TOTAL:',
                        style: pw.TextStyle(
                          fontSize: compact ? 8 : 10,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.Text(
                        _rupees(data.grandTotalPaise),
                        style: pw.TextStyle(
                          fontSize: compact ? 9 : 11,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (data.paidPaise > 0) ...[
                  pw.SizedBox(height: 2),
                  _summaryRow('Paid Amount:', _rupees(data.paidPaise), compact: compact),
                ],
                if (data.duePaise > 0)
                  _summaryRow(
                    'Balance Due:',
                    _rupees(data.duePaise),
                    color: PdfColors.red800,
                    isBold: true,
                    compact: compact,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Amount in Words
  static pw.Widget _buildAmountInWords(int grandTotalPaise, {bool compact = false}) {
    final words = convertPaiseToIndianWords(grandTotalPaise);
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 2 : 4),
      decoration: pw.BoxDecoration(
        color: lightHeaderBg,
        border: pw.Border.all(color: borderColor, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Amount in Words: ',
            style: pw.TextStyle(
              fontSize: compact ? 7 : 8,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              words,
              style: pw.TextStyle(
                fontSize: compact ? 7 : 8,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Footer: Bank Details, UPI QR, Terms, Signatory
  static pw.Widget _buildA4Footer(
    InvoicePrintData data,
    bool showUpiQr,
    bool showBankDetails, {
    bool compact = false,
  }) {
    final upiUri = _buildUpiUri(data);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        // Bank details & UPI QR
        pw.Expanded(
          flex: 4,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (showUpiQr && upiUri != null) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: borderColor, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: upiUri,
                        width: compact ? 42 : 54,
                        height: compact ? 42 : 54,
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Scan & Pay (UPI)',
                        style: pw.TextStyle(
                          fontSize: compact ? 5.5 : 6.5,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 8),
              ],
              if (showBankDetails && data.bankAccountNumber?.isNotEmpty == true)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'BANK TRANSFER DETAILS:',
                        style: pw.TextStyle(
                          fontSize: compact ? 6.5 : 7.5,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      if (data.bankName != null)
                        pw.Text('Bank: ${data.bankName}', style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5)),
                      pw.Text('A/C No: ${data.bankAccountNumber}', style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5, fontWeight: pw.FontWeight.bold)),
                      if (data.bankIfsc != null)
                        pw.Text('IFSC: ${data.bankIfsc}', style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5)),
                      if (data.upiId != null)
                        pw.Text('UPI ID: ${data.upiId}', style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        // Terms & Conditions
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'TERMS & CONDITIONS:',
                style: pw.TextStyle(
                  fontSize: compact ? 6.5 : 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryColor,
                ),
              ),
              pw.SizedBox(height: 1),
              pw.Text(
                data.terms?.isNotEmpty == true
                    ? data.terms!
                    : '1. Goods once sold will not be taken back without bill.\n2. Warranty as per manufacturer terms.',
                style: pw.TextStyle(fontSize: compact ? 5.5 : 6.5, color: textMuted),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        // Authorized Signatory
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'For ${data.businessName}',
                style: pw.TextStyle(
                  fontSize: compact ? 7 : 8,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: compact ? 18 : 28),
              pw.Container(width: 100, height: 0.8, color: primaryColor),
              pw.SizedBox(height: 2),
              pw.Text(
                'Authorized Signatory',
                style: pw.TextStyle(fontSize: compact ? 6.5 : 7.5, color: textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ================= THERMAL POS RECEIPT LAYOUT (80mm, 58mm, or Custom Width) =================
  static pw.Page _buildThermalPage(
    InvoicePrintData data,
    double widthMm,
    bool showUpiQr,
  ) {
    final isMini58 = widthMm <= 62;
    final upiUri = _buildUpiUri(data);

    return pw.Page(
      pageFormat: PdfPageFormat(
        widthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: 2.5 * PdfPageFormat.mm,
      ),
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Store Name
            pw.Text(
              data.businessName.toUpperCase(),
              style: pw.TextStyle(
                fontSize: isMini58 ? 10 : 12,
                fontWeight: pw.FontWeight.bold,
              ),
              textAlign: pw.TextAlign.center,
            ),
            if (data.businessAddress != null && data.businessAddress!.isNotEmpty) ...[
              pw.SizedBox(height: 1),
              pw.Text(
                data.businessAddress!,
                style: pw.TextStyle(fontSize: isMini58 ? 7 : 8),
                textAlign: pw.TextAlign.center,
              ),
            ],
            pw.SizedBox(height: 1),
            if (data.businessPhone != null)
              pw.Text(
                'Phone: ${data.businessPhone}',
                style: pw.TextStyle(fontSize: isMini58 ? 7 : 8),
                textAlign: pw.TextAlign.center,
              ),
            if (data.businessGstin != null && data.businessGstin!.isNotEmpty)
              pw.Text(
                'GSTIN: ${data.businessGstin}',
                style: pw.TextStyle(
                  fontSize: isMini58 ? 7.5 : 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
            _thermalDashedDivider(),

            // Receipt Title & Meta
            pw.Text(
              'TAX INVOICE / RETAIL RECEIPT',
              style: pw.TextStyle(
                fontSize: isMini58 ? 7.5 : 8.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 2),
            _thermalMetaRow('Bill No:', data.invoiceNumber, isMini58),
            _thermalMetaRow('Date:', _formatDateTime(data.invoiceDate), isMini58),
            if (data.cashierName != null)
              _thermalMetaRow('Cashier:', data.cashierName!, isMini58),
            if (data.customerName?.isNotEmpty == true &&
                data.customerName != 'Walk-in Customer')
              _thermalMetaRow('Customer:', data.customerName!, isMini58),
            if (data.customerPhone?.isNotEmpty == true)
              _thermalMetaRow('Mobile:', data.customerPhone!, isMini58),
            if (data.customerGstin != null &&
                data.customerGstin!.trim().isNotEmpty)
              _thermalMetaRow('GSTIN:', data.customerGstin!.trim(), isMini58),

            _thermalDashedDivider(),

            // Item Headers
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    'Item',
                    style: pw.TextStyle(fontSize: isMini58 ? 7 : 8, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Expanded(
                  flex: 2,
                  child: pw.Text(
                    'Qty',
                    style: pw.TextStyle(fontSize: isMini58 ? 7 : 8, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'Total',
                    style: pw.TextStyle(fontSize: isMini58 ? 7 : 8, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.right,
                  ),
                ),
              ],
            ),
            pw.Divider(thickness: 0.5, color: PdfColors.black),

            // Item List
            for (final line in data.lines) ...[
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  line.name,
                  style: pw.TextStyle(fontSize: isMini58 ? 7.5 : 8.5, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '  ${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity} ${line.unit} x ${_rupees(line.unitPricePaise)}',
                    style: pw.TextStyle(fontSize: isMini58 ? 6.5 : 7.5),
                  ),
                  pw.Text(
                    _rupees(line.lineTotalPaise),
                    style: pw.TextStyle(fontSize: isMini58 ? 7 : 8),
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
            ],

            _thermalDashedDivider(),

            // Financial Summary
            _thermalSummaryRow('Subtotal:', _rupees(data.subtotalPaise), isMini58),
            if (data.discountPaise > 0)
              _thermalSummaryRow('Discount:', '-${_rupees(data.discountPaise)}', isMini58),
            _thermalSummaryRow('Taxable Value:', _rupees(data.taxablePaise), isMini58),
            if (data.cgstPaise > 0)
              _thermalSummaryRow('CGST:', _rupees(data.cgstPaise), isMini58),
            if (data.sgstPaise > 0)
              _thermalSummaryRow('SGST:', _rupees(data.sgstPaise), isMini58),
            if (data.roundOffPaise != 0)
              _thermalSummaryRow('Round Off:', _rupees(data.roundOffPaise), isMini58),

            pw.Divider(thickness: 1, color: PdfColors.black),

            // Grand Total (Big Bold)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'GRAND TOTAL:',
                  style: pw.TextStyle(
                    fontSize: isMini58 ? 9 : 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  _rupees(data.grandTotalPaise),
                  style: pw.TextStyle(
                    fontSize: isMini58 ? 10 : 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.black),

            // Payment Breakup
            _thermalSummaryRow('Payment Mode:', data.paymentMode, isMini58),
            if (data.paidPaise > 0)
              _thermalSummaryRow('Paid Amount:', _rupees(data.paidPaise), isMini58),
            if (data.duePaise > 0)
              _thermalSummaryRow('Balance Due:', _rupees(data.duePaise), isMini58, isBold: true),

            // UPI QR Code on thermal receipt
            if (showUpiQr && upiUri != null) ...[
              pw.SizedBox(height: 6),
              pw.Text(
                'Scan & Pay via UPI',
                style: pw.TextStyle(fontSize: isMini58 ? 7 : 8, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 2),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: upiUri,
                width: isMini58 ? 60 : 75,
                height: isMini58 ? 60 : 75,
              ),
            ],

            pw.SizedBox(height: 6),
            // Barcode for receipt tracking
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: data.invoiceNumber,
              width: isMini58 ? 110 : 140,
              height: 22,
              drawText: false,
            ),
            pw.Text(
              data.invoiceNumber,
              style: pw.TextStyle(fontSize: 6.5),
            ),

            pw.SizedBox(height: 6),
            pw.Text(
              'Thank You! Visit Again.',
              style: pw.TextStyle(fontSize: isMini58 ? 7.5 : 8.5, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            pw.Text(
              'Goods once sold will not be returned without bill.',
              style: pw.TextStyle(fontSize: isMini58 ? 5.5 : 6.5, color: PdfColors.grey700),
              textAlign: pw.TextAlign.center,
            ),
          ],
        );
      },
    );
  }

  // Helpers
  static pw.Widget _thermalDashedDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Text(
        '------------------------------------------------',
        maxLines: 1,
        style: const pw.TextStyle(fontSize: 8),
      ),
    );
  }

  static pw.Widget _thermalMetaRow(String label, String value, bool isMini58) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: isMini58 ? 6.5 : 7.5)),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: isMini58 ? 6.5 : 7.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _thermalSummaryRow(
    String label,
    String value,
    bool isMini58, {
    bool isBold = false,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: isMini58 ? 7 : 8)),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: isMini58 ? 7 : 8,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  static pw.Widget _summaryRow(
    String label,
    String value, {
    PdfColor? color,
    bool isBold = false,
    bool compact = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: compact ? 7 : 8,
              color: color ?? textMuted,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: compact ? 7 : 8,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _hsnCell(String text, {bool isHeader = false, bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 6.5,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      ),
    );
  }

  static String _rupees(int paise) {
    final rs = (paise / 100).toStringAsFixed(2);
    return 'Rs. $rs';
  }

  static String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static String _formatDateTime(DateTime d) {
    final date = _formatDate(d);
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  static String? _buildUpiUri(InvoicePrintData data) {
    final upi = data.upiId?.trim();
    if (upi == null || upi.isEmpty) return null;
    final amountRs = (data.grandTotalPaise / 100).toStringAsFixed(2);
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upi,
        'pn': data.businessName,
        'am': amountRs,
        'cu': 'INR',
        'tn': 'Bill ${data.invoiceNumber}',
      },
    ).toString();
  }

  /// Converts paise into Indian Numbering Currency Words:
  /// e.g. 4582000 paise (Rs 45,820) -> "Rupees Forty-Five Thousand Eight Hundred Twenty Only"
  static String convertPaiseToIndianWords(int paise) {
    if (paise <= 0) return 'Rupees Zero Only';

    final rupees = paise ~/ 100;
    final remainingPaise = paise % 100;

    String words = 'Rupees ${_convertToIndianWords(rupees)}';
    if (remainingPaise > 0) {
      words += ' and ${_convertToIndianWords(remainingPaise)} Paise';
    }
    return '$words Only';
  }

  static String _convertToIndianWords(int n) {
    if (n == 0) return 'Zero';

    const units = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];

    const tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];

    String formatTwoDigits(int val) {
      if (val < 20) return units[val];
      final ten = tens[val ~/ 10];
      final unit = units[val % 10];
      return unit.isEmpty ? ten : '$ten $unit';
    }

    String formatThreeDigits(int val) {
      final hundred = val ~/ 100;
      final rest = val % 100;
      if (hundred > 0 && rest > 0) {
        return '${units[hundred]} Hundred and ${formatTwoDigits(rest)}';
      } else if (hundred > 0) {
        return '${units[hundred]} Hundred';
      }
      return formatTwoDigits(rest);
    }

    final crore = n ~/ 10000000;
    final lakh = (n % 10000000) ~/ 100000;
    final thousand = (n % 100000) ~/ 1000;
    final remainder = n % 1000;

    final parts = <String>[];

    if (crore > 0) {
      parts.add('${formatThreeDigits(crore)} Crore');
    }
    if (lakh > 0) {
      parts.add('${formatTwoDigits(lakh)} Lakh');
    }
    if (thousand > 0) {
      parts.add('${formatTwoDigits(thousand)} Thousand');
    }
    if (remainder > 0) {
      parts.add(formatThreeDigits(remainder));
    }

    return parts.join(' ').trim();
  }
}

class _HsnGroup {
  _HsnGroup({
    required this.hsn,
    required this.rateBps,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
  });

  final String hsn;
  final int rateBps;
  int taxablePaise;
  int cgstPaise;
  int sgstPaise;
}

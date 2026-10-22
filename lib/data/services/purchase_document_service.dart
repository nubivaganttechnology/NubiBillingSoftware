import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/purchase_bill_model.dart';

class PurchaseDocumentService {
  const PurchaseDocumentService();

  Future<Uint8List> buildPdf(PurchaseBillModel bill) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Text(
            'PURCHASE ${bill.status}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '${bill.purchaseNumber ?? bill.purchaseBillId} · Supplier: ${bill.supplierName ?? bill.supplierId}',
          ),
          pw.Text('Supplier invoice: ${bill.supplierInvoiceNumber}'),
          pw.Text(
            'Invoice date: ${_date(bill.invoiceDate)} · Purchase date: ${_date(bill.purchaseDate ?? bill.invoiceDate)}',
          ),
          pw.Text(
            'Payment: ${bill.paymentStatus} · Paid ₹${_money(bill.paidAmount)} · Due ₹${_money(bill.outstandingAmount)}',
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: const [
              '#',
              'Product / Variant',
              'Qty',
              'Rate',
              'GST',
              'Taxable',
              'MRP',
              'Sell',
              'Total',
            ],
            data: [
              for (var i = 0; i < bill.items.length; i++)
                [
                  '${i + 1}',
                  '${bill.items[i].productName}\n${bill.items[i].variantName ?? bill.items[i].variantId}',
                  _qty(bill.items[i].quantity),
                  _money(bill.items[i].rate),
                  '${bill.items[i].gstRateBps / 100}%',
                  _money(bill.items[i].taxableAmount),
                  _money(bill.items[i].mrp ?? 0),
                  _money(bill.items[i].sellingPrice ?? 0),
                  _money(bill.items[i].taxableAmount + bill.items[i].taxAmount),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellPadding: const pw.EdgeInsets.all(5),
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.5),
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Subtotal ₹${_money(bill.subtotal)}'),
                pw.Text('Discount ₹${_money(bill.discountAmount)}'),
                pw.Text('Taxable ₹${_money(bill.taxableAmount)}'),
                pw.Text(
                  'CGST ₹${_money(bill.cgstAmount)} · SGST ₹${_money(bill.sgstAmount)} · IGST ₹${_money(bill.igstAmount)}',
                ),
                pw.Text(
                  'Charges ₹${_money(bill.chargesAmount)} · Round off ₹${_money(bill.roundOff)}',
                ),
                pw.Text(
                  'Grand Total ₹${_money(bill.grandTotal)}',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          for (final item in bill.items)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Text(
                '${item.productName} · ${item.variantName ?? item.variantId} · Barcode ${item.barcodeSnapshot ?? '—'} · Batch ${item.internalBatchNo ?? '—'} · Supplier lot ${item.supplierLotNo ?? '—'} · Expiry ${item.expiryDate == null ? '—' : _date(item.expiryDate!)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
        ],
      ),
    );
    return document.save();
  }

  Future<void> print(PurchaseBillModel bill) async {
    final bytes = await buildPdf(bill);
    await Printing.layoutPdf(
      name: 'Purchase-${bill.purchaseNumber ?? bill.purchaseBillId}',
      onLayout: (_) async => bytes,
      dynamicLayout: false,
    );
  }

  static String _money(int paise) => (paise / 100).toStringAsFixed(2);
  static String _qty(int milli) =>
      (milli / 1000).toStringAsFixed(milli % 1000 == 0 ? 0 : 3);
  static String _date(DateTime value) {
    final date = value.toLocal();
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

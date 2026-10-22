import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/invoice_print_service.dart';

void main() {
  test('InvoicePrintService.buildPdf handles unicode Hindi / Bengali names gracefully', () async {
    final data = InvoicePrintData(
      invoiceNumber: 'INV-2026-0001',
      invoiceDate: DateTime(2026, 10, 20),
      businessName: 'কলকাতা হার্ডওয়্যার (Kolkata Hardware)',
      businessAddress: '123 MG Road, Kolkata',
      businessGstin: '19ABCDE1234F1Z5',
      customerName: 'अमित कुमार (Amit Kumar)',
      customerPhone: '9876543210',
      lines: const [
        InvoicePrintLine(
          name: 'Apex Ultima 20L লাল',
          quantity: 2,
          unitPricePaise: 450000,
          taxablePaise: 762712,
          gstRateBps: 1800,
          cgstPaise: 68644,
          sgstPaise: 68644,
          lineTotalPaise: 900000,
        ),
      ],
      subtotalPaise: 900000,
      taxablePaise: 762712,
      cgstPaise: 68644,
      sgstPaise: 68644,
      grandTotalPaise: 900000,
      paidPaise: 500000,
      duePaise: 400000,
      dueDate: DateTime(2026, 11, 5),
    );

    final a4Bytes = await InvoicePrintService.buildPdf(
      data: data,
      format: InvoicePrintFormat.a4Standard,
    );
    expect(a4Bytes.isNotEmpty, isTrue);
  });
}

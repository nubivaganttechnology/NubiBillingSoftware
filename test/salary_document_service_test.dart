import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/salary_document_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'offline salary statements embed English, Bengali and Hindi fonts',
    () async {
      final period = <String, dynamic>{
        'periodId': 'SALPER-EMP-20261001-20261031',
        'periodStart': '2026-10-01T00:00:00.000Z',
        'periodEnd': '2026-10-31T00:00:00.000Z',
        'grossEarningsPaise': 3200000,
        'approvedDeductionsPaise': 20000,
        'netEarnedPaise': 3180000,
        'advanceAdjustedPaise': 250000,
        'paidAmountPaise': 1500000,
      };
      final transactions = <Map<String, dynamic>>[
        {
          'recordId': 'SKH-ADV-001',
          'transactionDate': '2026-10-05T10:30:00.000Z',
          'transactionType': 'BANK_ADVANCE',
          'paymentMode': 'BANK_TRANSFER',
          'referenceNo': 'UTR-00490012001',
          'amountPaise': 250000,
        },
      ];
      for (final language in SalaryDocumentLanguage.values) {
        final bytes = await SalaryDocumentService.buildStatement(
          business: {'name': 'Kolkata Hardware'},
          employee: {'name': 'রাহুল দাস / राहुल दास', 'employeeId': 'EMP-1'},
          period: period,
          language: language,
          transactions: transactions,
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        expect(bytes.length, greaterThan(5000));
        final file = File(
          '${Directory.systemTemp.path}/salary-${language.name}.pdf',
        );
        await file.writeAsBytes(bytes, flush: true);
        addTearDown(() async {
          if (await file.exists()) await file.delete();
        });
        final slip = await SalaryDocumentService.buildStatement(
          business: {'name': 'Kolkata Hardware'},
          employee: {'name': 'Daily worker', 'employeeId': 'EMP-2'},
          period: period,
          language: language,
          type: SalaryDocumentType.payslip,
        );
        expect(String.fromCharCodes(slip.take(5)), '%PDF-');
      }
    },
  );
}

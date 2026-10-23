import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum SalaryDocumentLanguage { english, bengali, hindi }

enum SalaryDocumentType { payslip, statement }

/// Offline PDF generation and platform share-sheet handoff for payroll docs.
/// All monetary values are accepted and displayed as integer paise.
class SalaryDocumentService {
  static Future<Uint8List> buildStatement({
    required Map<String, dynamic> business,
    required Map<String, dynamic> employee,
    required Map<String, dynamic> period,
    required SalaryDocumentLanguage language,
    SalaryDocumentType type = SalaryDocumentType.statement,
    List<Map<String, dynamic>> transactions = const [],
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bengali = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'),
    );
    final devanagari = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'),
    );
    final font = switch (language) {
      SalaryDocumentLanguage.english => regular,
      SalaryDocumentLanguage.bengali => bengali,
      SalaryDocumentLanguage.hindi => devanagari,
    };
    final labels = switch (language) {
      SalaryDocumentLanguage.english => (
        type == SalaryDocumentType.payslip ? 'Salary slip' : 'Salary statement',
        'Employee',
        'Period',
        'Gross earnings',
        'Deductions',
        'Net earned',
        'Advance adjusted',
        'Paid',
        'Balance payable',
        'Acknowledgment',
        'Transactions',
        'Date',
        'Type',
        'Reference',
        'Amount',
        'Payment method',
      ),
      SalaryDocumentLanguage.bengali => (
        type == SalaryDocumentType.payslip ? 'বেতন স্লিপ' : 'বেতনের বিবরণী',
        'কর্মচারী',
        'সময়কাল',
        'মোট উপার্জন',
        'কর্তন',
        'নিট উপার্জন',
        'অগ্রিম সমন্বয়',
        'পরিশোধিত',
        'বকেয়া বেতন',
        'স্বীকৃতি',
        'লেনদেন',
        'তারিখ',
        'ধরন',
        'রেফারেন্স',
        'পরিমাণ',
        'পরিশোধের পদ্ধতি',
      ),
      SalaryDocumentLanguage.hindi => (
        type == SalaryDocumentType.payslip ? 'वेतन पर्ची' : 'वेतन विवरण',
        'कर्मचारी',
        'अवधि',
        'कुल कमाई',
        'कटौती',
        'शुद्ध कमाई',
        'अग्रिम समायोजन',
        'भुगतान',
        'शेष देय',
        'स्वीकृति',
        'लेन-देन',
        'तारीख',
        'प्रकार',
        'संदर्भ',
        'राशि',
        'भुगतान का तरीका',
      ),
    };
    final employeeIdLabel = switch (language) {
      SalaryDocumentLanguage.english => 'Employee ID',
      SalaryDocumentLanguage.bengali => 'কর্মচারী আইডি',
      SalaryDocumentLanguage.hindi => 'कर्मचारी आईडी',
    };
    final mobileLabel = switch (language) {
      SalaryDocumentLanguage.english => 'Mobile',
      SalaryDocumentLanguage.bengali => 'মোবাইল',
      SalaryDocumentLanguage.hindi => 'मोबाइल',
    };
    final codeLabel = switch (language) {
      SalaryDocumentLanguage.english => 'Staff code',
      SalaryDocumentLanguage.bengali => 'কর্মী কোড',
      SalaryDocumentLanguage.hindi => 'कर्मचारी कोड',
    };
    final contactLabel = switch (language) {
      SalaryDocumentLanguage.english => 'Phone',
      SalaryDocumentLanguage.bengali => 'ফোন',
      SalaryDocumentLanguage.hindi => 'फोन',
    };
    final storeOffsetLabel = switch (language) {
      SalaryDocumentLanguage.english => 'Store credit offset',
      SalaryDocumentLanguage.bengali => 'দোকান ক্রেডিট সমন্বয়',
      SalaryDocumentLanguage.hindi => 'दुकान क्रेडिट समायोजन',
    };
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        fontFallback: [regular, bengali, devanagari],
      ),
    );
    final start = (period['periodStart'] ?? '').toString().split('T').first;
    final end = (period['periodEnd'] ?? '').toString().split('T').first;
    String money(Object? amount) =>
        '₹${(((amount as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)}';
    final net = (period['netEarnedPaise'] as num?)?.toInt() ?? 0;
    final paid = (period['paidAmountPaise'] as num?)?.toInt() ?? 0;
    final adjusted = (period['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
    final storeOffset =
        (period['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
    final balance = (net - paid - adjusted - storeOffset).clamp(0, 1 << 30);
    String transactionLabel(Object? value) {
      final key = value?.toString() ?? '';
      const english = {
        'CASH_ADVANCE': 'Cash advance',
        'UPI_ADVANCE': 'UPI advance',
        'BANK_ADVANCE': 'Bank advance',
        'STORE_PURCHASE': 'Store purchase',
        'BONUS': 'Bonus',
        'OVERTIME': 'Overtime',
        'INCENTIVE': 'Incentive',
        'APPROVED_DEDUCTION': 'Approved deduction',
        'ADVANCE_ADJUSTMENT': 'Advance adjustment',
        'STORE_CREDIT_ADJUSTMENT': 'Store credit adjustment',
        'SALARY_PAYMENT': 'Salary payment',
        'REVERSAL': 'Reversal',
      };
      const bengaliLabels = {
        'CASH_ADVANCE': 'নগদ অগ্রিম',
        'UPI_ADVANCE': 'ইউপিআই অগ্রিম',
        'BANK_ADVANCE': 'ব্যাংক অগ্রিম',
        'STORE_PURCHASE': 'দোকানের কেনাকাটা',
        'BONUS': 'বোনাস',
        'OVERTIME': 'অতিরিক্ত কাজ',
        'INCENTIVE': 'প্রণোদনা',
        'APPROVED_DEDUCTION': 'অনুমোদিত কর্তন',
        'ADVANCE_ADJUSTMENT': 'অগ্রিম সমন্বয়',
        'STORE_CREDIT_ADJUSTMENT': 'দোকান ক্রেডিট সমন্বয়',
        'SALARY_PAYMENT': 'বেতন পরিশোধ',
        'REVERSAL': 'বাতিল সংশোধন',
      };
      const hindiLabels = {
        'CASH_ADVANCE': 'नकद अग्रिम',
        'UPI_ADVANCE': 'यूपीआई अग्रिम',
        'BANK_ADVANCE': 'बैंक अग्रिम',
        'STORE_PURCHASE': 'दुकान खरीद',
        'BONUS': 'बोनस',
        'OVERTIME': 'अतिरिक्त समय',
        'INCENTIVE': 'प्रोत्साहन',
        'APPROVED_DEDUCTION': 'स्वीकृत कटौती',
        'ADVANCE_ADJUSTMENT': 'अग्रिम समायोजन',
        'STORE_CREDIT_ADJUSTMENT': 'दुकान क्रेडिट समायोजन',
        'SALARY_PAYMENT': 'वेतन भुगतान',
        'REVERSAL': 'वापसी प्रविष्टि',
      };
      return switch (language) {
        SalaryDocumentLanguage.english => english[key] ?? key,
        SalaryDocumentLanguage.bengali => bengaliLabels[key] ?? key,
        SalaryDocumentLanguage.hindi => hindiLabels[key] ?? key,
      };
    }

    String paymentLabel(Object? value) {
      final key = value?.toString() ?? '';
      const labels = {
        'CASH': ('Cash', 'নগদ', 'नकद'),
        'UPI': ('UPI', 'ইউপিআই', 'यूपीआई'),
        'BANK_TRANSFER': (
          'Bank transfer',
          'ব্যাংক ট্রান্সফার',
          'बैंक हस्तांतरण',
        ),
        'CHEQUE': ('Cheque', 'চেক', 'चेक'),
        'CARD': ('Card', 'কার্ড', 'कार्ड'),
        'NON_CASH': ('Non-cash', 'নগদ নয়', 'गैर-नकद'),
      };
      final translation = labels[key];
      if (translation == null) return key;
      return switch (language) {
        SalaryDocumentLanguage.english => translation.$1,
        SalaryDocumentLanguage.bengali => translation.$2,
        SalaryDocumentLanguage.hindi => translation.$3,
      };
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Text(
            business['name']?.toString() ?? '',
            style: pw.TextStyle(
              font: font,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if ((business['address']?.toString() ?? '').isNotEmpty)
            pw.Text(
              business['address'].toString(),
              style: pw.TextStyle(font: font),
            ),
          if ((business['phone']?.toString() ?? '').isNotEmpty)
            pw.Text(
              '$contactLabel: ${business['phone']}',
              style: pw.TextStyle(font: regular),
            ),
          if ((business['gstin']?.toString() ?? '').isNotEmpty)
            pw.Text(
              'GSTIN: ${business['gstin']}',
              style: pw.TextStyle(font: regular),
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            labels.$1,
            style: pw.TextStyle(
              font: font,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '${labels.$2}: ${employee['name'] ?? ''}',
            style: pw.TextStyle(font: font, fontSize: 12),
          ),
          pw.Text(
            '$employeeIdLabel: ${employee['employeeId'] ?? ''}',
            style: pw.TextStyle(font: regular, fontSize: 10),
          ),
          if ((employee['mobile']?.toString() ?? '').isNotEmpty)
            pw.Text(
              '$mobileLabel: ${employee['mobile']}',
              style: pw.TextStyle(font: regular, fontSize: 10),
            ),
          if ((employee['employeeCode']?.toString() ?? '').isNotEmpty)
            pw.Text(
              '$codeLabel: ${employee['employeeCode']}',
              style: pw.TextStyle(font: regular, fontSize: 10),
            ),
          pw.Text(
            '${labels.$3}: $start — $end',
            style: pw.TextStyle(font: font, fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: [
              for (final row in <(String, String)>[
                (labels.$4, money(period['grossEarningsPaise'])),
                (labels.$5, money(period['approvedDeductionsPaise'])),
                (labels.$6, money(period['netEarnedPaise'])),
                if (adjusted > 0) (labels.$7, money(adjusted)),
                if (storeOffset > 0) (storeOffsetLabel, money(storeOffset)),
                (labels.$8, money(period['paidAmountPaise'])),
                (labels.$9, money(balance)),
              ])
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(row.$1, style: pw.TextStyle(font: font)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        row.$2,
                        style: pw.TextStyle(font: regular),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (type == SalaryDocumentType.statement &&
              transactions.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text(
              labels.$11,
              style: pw.TextStyle(
                font: font,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                pw.TableRow(
                  children: [
                    for (final label in [
                      labels.$12,
                      labels.$13,
                      labels.$16,
                      labels.$14,
                      labels.$15,
                    ])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          label,
                          style: pw.TextStyle(font: font, fontSize: 8),
                        ),
                      ),
                  ],
                ),
                for (final entry in transactions)
                  pw.TableRow(
                    children:
                        [
                              (entry['transactionDate'] ?? '')
                                  .toString()
                                  .split('T')
                                  .first,
                              transactionLabel(entry['transactionType']),
                              paymentLabel(entry['paymentMode']),
                              (entry['referenceNo'] ?? entry['recordId'] ?? '')
                                  .toString(),
                              money(entry['amountPaise']),
                            ]
                            .map(
                              (value) => pw.Padding(
                                padding: const pw.EdgeInsets.all(5),
                                child: pw.Text(
                                  value,
                                  style: pw.TextStyle(
                                    font: regular,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
              ],
            ),
          ],
          pw.SizedBox(height: 24),
          pw.Text(
            '${labels.$10}: ${period['employeeAcknowledgmentName'] ?? '________________'}',
            style: pw.TextStyle(font: font),
          ),
          if (period['employeeAcknowledgedAt'] != null)
            pw.Text(
              'Acknowledged ${period['employeeAcknowledgedAt']}',
              style: pw.TextStyle(font: regular, fontSize: 9),
            ),
        ],
      ),
    );
    return doc.save();
  }
}

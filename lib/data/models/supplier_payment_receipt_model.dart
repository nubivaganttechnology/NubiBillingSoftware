import 'package:flutter/foundation.dart';

/// Information about a specific purchase bill settled during a supplier payment.
@immutable
class SupplierSettledBillInfo {
  final String billId;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final int billTotalPaise;
  final int paidBeforePaise;
  final int allocatedPaise;
  final int remainingDuePaise;
  final bool isFullyPaid;

  const SupplierSettledBillInfo({
    required this.billId,
    required this.invoiceNumber,
    this.invoiceDate,
    required this.billTotalPaise,
    required this.paidBeforePaise,
    required this.allocatedPaise,
    required this.remainingDuePaise,
    required this.isFullyPaid,
  });

  double get billTotalRs => billTotalPaise / 100.0;
  double get paidBeforeRs => paidBeforePaise / 100.0;
  double get allocatedRs => allocatedPaise / 100.0;
  double get remainingDueRs => remainingDuePaise / 100.0;

  Map<String, dynamic> toMap() => {
        'billId': billId,
        'invoiceNumber': invoiceNumber,
        'invoiceDate': invoiceDate?.toIso8601String(),
        'billTotalPaise': billTotalPaise,
        'paidBeforePaise': paidBeforePaise,
        'allocatedPaise': allocatedPaise,
        'remainingDuePaise': remainingDuePaise,
        'isFullyPaid': isFullyPaid,
      };

  factory SupplierSettledBillInfo.fromMap(Map<String, dynamic> map) =>
      SupplierSettledBillInfo(
        billId: map['billId'] as String? ?? '',
        invoiceNumber: map['invoiceNumber'] as String? ?? '',
        invoiceDate: map['invoiceDate'] != null
            ? DateTime.tryParse(map['invoiceDate'].toString())
            : null,
        billTotalPaise: (map['billTotalPaise'] as num?)?.toInt() ?? 0,
        paidBeforePaise: (map['paidBeforePaise'] as num?)?.toInt() ?? 0,
        allocatedPaise: (map['allocatedPaise'] as num?)?.toInt() ?? 0,
        remainingDuePaise: (map['remainingDuePaise'] as num?)?.toInt() ?? 0,
        isFullyPaid: map['isFullyPaid'] as bool? ?? false,
      );
}

/// Complete receipt model for supplier payments with previous due, amount paid,
/// remaining balance, and settled bills details.
@immutable
class SupplierPaymentReceiptModel {
  final String paymentId;
  final String? voucherNumber;
  final DateTime paymentDate;
  final String supplierId;
  final String supplierName;
  final String? supplierPhone;
  final String businessName;
  final String? outletName;
  final String paymentMode;
  final String? referenceNo;
  final int previousDuePaise;
  final int amountPaidPaise;
  final int remainingDuePaise;
  final int unallocatedAdvancePaise;
  final List<SupplierSettledBillInfo> settledBills;
  final String? notes;

  const SupplierPaymentReceiptModel({
    required this.paymentId,
    this.voucherNumber,
    required this.paymentDate,
    required this.supplierId,
    required this.supplierName,
    this.supplierPhone,
    required this.businessName,
    this.outletName,
    required this.paymentMode,
    this.referenceNo,
    required this.previousDuePaise,
    required this.amountPaidPaise,
    required this.remainingDuePaise,
    this.unallocatedAdvancePaise = 0,
    this.settledBills = const [],
    this.notes,
  });

  double get previousDueRs => previousDuePaise / 100.0;
  double get amountPaidRs => amountPaidPaise / 100.0;
  double get remainingDueRs => remainingDuePaise / 100.0;
  double get unallocatedAdvanceRs => unallocatedAdvancePaise / 100.0;

  /// Generates a neatly formatted receipt text suitable for WhatsApp in English, Bengali, or Hindi.
  String generateWhatsAppMessage({String languageCode = 'en'}) {
    final isBn = languageCode == 'bn';
    final isHi = languageCode == 'hi';

    final buffer = StringBuffer();
    if (isBn) {
      buffer.writeln('🧾 *পেমেন্ট রসিদ*');
    } else if (isHi) {
      buffer.writeln('🧾 *भुगतान रसीद*');
    } else {
      buffer.writeln('🧾 *PAYMENT VOUCHER*');
    }

    if (businessName.trim().isNotEmpty) {
      buffer.writeln('🏪 *$businessName*');
    }
    if (outletName != null && outletName!.trim().isNotEmpty) {
      final outletLabel = isBn ? 'শাখা' : isHi ? 'शाखा' : 'Outlet';
      buffer.writeln('📍 $outletLabel: ${outletName!.trim()}');
    }
    buffer.writeln('--------------------------------');

    final supplierLabel = isBn ? 'সাপ্লায়ার' : isHi ? 'आपूर्तिकर्ता' : 'Supplier';
    buffer.writeln('👤 $supplierLabel: *$supplierName*');

    final voucherLabel = isBn ? 'ভাউচার নং' : isHi ? 'वाउचर नं' : 'Voucher No';
    buffer.writeln('🔢 $voucherLabel: ${voucherNumber ?? paymentId}');

    final day = paymentDate.day.toString().padLeft(2, '0');
    final month = paymentDate.month.toString().padLeft(2, '0');
    final year = paymentDate.year.toString();
    final hour = paymentDate.hour.toString().padLeft(2, '0');
    final minute = paymentDate.minute.toString().padLeft(2, '0');
    final dateLabel = isBn ? 'তারিখ ও সময়' : isHi ? 'दिनांक और समय' : 'Date & Time';
    buffer.writeln('📅 $dateLabel: $day/$month/$year $hour:$minute');

    final modeLabel = isBn ? 'পেমেন্ট মাধ্যম' : isHi ? 'भुगतान माध्यम' : 'Payment Mode';
    final localizedMode = isBn
        ? (switch (paymentMode.toUpperCase()) {
            'CASH' => 'নগদ',
            'UPI' => 'ইউপিআই',
            'BANK_TRANSFER' => 'ব্যাংক ট্রান্সফার',
            'CHEQUE' => 'চেক',
            'CARD' => 'কার্ড',
            _ => paymentMode,
          })
        : isHi
            ? (switch (paymentMode.toUpperCase()) {
                'CASH' => 'नकद',
                'UPI' => 'यूपीआई',
                'BANK_TRANSFER' => 'बैंक ट्रांसफर',
                'CHEQUE' => 'चेक',
                'CARD' => 'कार्ड',
                _ => paymentMode,
              })
            : paymentMode.replaceAll('_', ' ');
    buffer.writeln('💳 $modeLabel: $localizedMode');

    if (referenceNo != null && referenceNo!.trim().isNotEmpty) {
      final refLabel = isBn ? 'রেফারেন্স/UTR' : isHi ? 'रेफरेंस/UTR' : 'Ref/UTR';
      buffer.writeln('🔖 $refLabel: ${referenceNo!.trim()}');
    }
    buffer.writeln('--------------------------------');

    final prevDueLabel = isBn ? 'আগের মোট বাকি' : isHi ? 'पिछला कुल बकाया' : 'Previous Due';
    buffer.writeln('💰 *$prevDueLabel:* ₹${previousDueRs.toStringAsFixed(2)}');

    final paidLabel = isBn ? 'জমা দেওয়া হলো' : isHi ? 'जमा की गई राशि' : 'Amount Paid';
    buffer.writeln('✅ *$paidLabel:* ₹${amountPaidRs.toStringAsFixed(2)}');

    final remDueLabel = isBn ? 'বর্তমান নিট বাকি' : isHi ? 'वर्तमान शेष बकाया' : 'Remaining Due';
    buffer.writeln('📌 *$remDueLabel:* ₹${remainingDueRs.toStringAsFixed(2)}');

    if (unallocatedAdvancePaise > 0) {
      final advLabel = isBn ? 'অগ্রিম জমা' : isHi ? 'अग्रिम जमा' : 'Advance Credit';
      buffer.writeln('🎁 *$advLabel:* ₹${unallocatedAdvanceRs.toStringAsFixed(2)}');
    }

    if (settledBills.isNotEmpty) {
      buffer.writeln('--------------------------------');
      final billsLabel = isBn ? 'বিলের সমন্বয় বিবরণী' : isHi ? 'বিল समायोजन विवरण' : 'Bill Settlement Breakdown';
      buffer.writeln('📋 *$billsLabel:*');
      for (final bill in settledBills) {
        final status = bill.isFullyPaid
            ? (isBn ? 'পরিশোধিত' : isHi ? 'पूर्ण भुगतान' : 'PAID')
            : (isBn ? 'আংশিক' : isHi ? 'आंशिक' : 'PARTIAL');
        final bPaid = isBn ? 'জমা' : isHi ? 'जमा' : 'Paid';
        final bDue = isBn ? 'বাকি' : isHi ? 'बकाया' : 'Due';
        buffer.writeln(
          ' • #${bill.invoiceNumber}: $bPaid ₹${bill.allocatedRs.toStringAsFixed(2)} ($bDue: ₹${bill.remainingDueRs.toStringAsFixed(2)}) [$status]',
        );
      }
    }
    buffer.writeln('--------------------------------');
    final thankYou = isBn
        ? 'লেনদেনের জন্য ধন্যবাদ!'
        : isHi
            ? 'लेनदेन के लिए धन्यवाद!'
            : 'Thank you for your business!';
    buffer.writeln(thankYou);
    return buffer.toString();
  }
}

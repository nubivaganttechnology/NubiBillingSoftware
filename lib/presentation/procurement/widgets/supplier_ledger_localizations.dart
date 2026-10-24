import 'package:flutter/material.dart';

import '../../app_controller.dart';

/// Multilingual dictionary supporting English ('en'), Bengali ('bn'), and Hindi ('hi')
/// for the Supplier Ledger, FIFO Due Settlement, and Payment Voucher features.
/// Ensures pure localized text without mixed-language strings.
class SupplierLedgerStrings {
  final String languageCode;

  const SupplierLedgerStrings(this.languageCode);

  factory SupplierLedgerStrings.of(BuildContext context, [AppController? controller]) {
    String? code;
    try {
      code = controller?.currentLocale.languageCode;
    } catch (_) {}
    code ??= Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return SupplierLedgerStrings(code);
  }

  bool get isBn => languageCode == 'bn';
  bool get isHi => languageCode == 'hi';

  // --- Supplier Due Payment Dialog ---
  String get paySupplierDueTitle =>
      isBn ? 'বকেয়া পরিশোধ' : isHi ? 'बकाया भुगतान' : 'Pay Supplier Due';
  String get totalPayable =>
      isBn ? 'বর্তমান মোট বাকি' : isHi ? 'कुल बकाया' : 'Total Payable';
  String get paymentAmount =>
      isBn ? 'জমা দেওয়ার পরিমাণ (₹)' : isHi ? 'भुगतान राशि (₹)' : 'Payment Amount (₹)';
  String get paymentMode =>
      isBn ? 'পেমেন্ট মাধ্যম' : isHi ? 'भुगतान माध्यम' : 'Payment Mode';
  String get date =>
      isBn ? 'তারিখ' : isHi ? 'दिनांक' : 'Date';
  String get referenceOptional =>
      isBn ? 'রেফারেন্স / ইউটিআর / চেক নং (ঐচ্ছিক)' : isHi ? 'रेफरेंस / यूटीआर / चेक नं (वैकल्पिक)' : 'Reference / UTR / Cheque # (Optional)';
  String get fifoPreviewTitle =>
      isBn ? 'বিলের স্বয়ংক্রিয় সমন্বয় পূর্বরূপ' : isHi ? 'বিল समायोजन पूर्वावलोकन' : 'FIFO Bill Settlement Preview';
  String get remainingDueAfterPayment =>
      isBn ? 'পেমেন্টের পর দেনা থাকবে:' : isHi ? 'भुगतान के बाद शेष बकाया:' : 'Remaining Due After Payment:';
  String get advanceCredit =>
      isBn ? 'অগ্রিম জমা:' : isHi ? 'अग्रिम जमा:' : 'Advance Credit:';
  String get confirmPayment =>
      isBn ? 'পেমেন্ট নিশ্চিত করুন' : isHi ? 'भुगतान की पुष्टि करें' : 'Confirm Payment';
  String get cancel =>
      isBn ? 'বাতিল' : isHi ? 'रद्द करें' : 'Cancel';
  String get enterValidAmount =>
      isBn ? 'সঠিক পেমেন্ট পরিমাণ লিখুন।' : isHi ? 'कृपया सही राशि दर्ज करें।' : 'Please enter a valid amount.';
  String get saving =>
      isBn ? 'সংরক্ষণ হচ্ছে...' : isHi ? 'सहेज रहा है...' : 'Saving...';
  String get noOutstandingBills =>
      isBn ? 'কোনো অনিষ্পন্ন বিল নেই।' : isHi ? 'कोई बकाया बिल नहीं मिला।' : 'No outstanding bills found.';
  String get unchanged =>
      isBn ? 'অপরিবর্তিত' : isHi ? 'अपरिवर्तित' : 'Unchanged';
  String get paidLabel =>
      isBn ? 'জমা' : isHi ? 'जमा' : 'Paid';
  String get remainingLabel =>
      isBn ? 'বাকি' : isHi ? 'बकाया' : 'Due';

  // --- Payment Voucher Dialog ---
  String get paymentVoucherTitle =>
      isBn ? 'পেমেন্ট রসিদ' : isHi ? 'भुगतान रसीद' : 'Payment Voucher';
  String get paymentVoucherSubtitle =>
      isBn ? 'সাপ্লায়ার পেমেন্ট সফলভাবে সংরক্ষিত হয়েছে' : isHi ? 'आपूर्तिकर्ता भुगतान सफलतापूर्वक दर्ज किया गया' : 'Supplier payment recorded successfully';
  String get supplier =>
      isBn ? 'সাপ্লায়ার' : isHi ? 'आपूर्तिकर्ता' : 'Supplier';
  String get phone =>
      isBn ? 'মোবাইল নং' : isHi ? 'मोबाइल नं' : 'Phone';
  String get voucherNo =>
      isBn ? 'ভাউচার নং' : isHi ? 'वाउचर नं' : 'Voucher No';
  String get dateTime =>
      isBn ? 'তারিখ ও সময়' : isHi ? 'दिनांक और समय' : 'Date & Time';
  String get refUtr =>
      isBn ? 'রেফারেন্স / ইউটিআর' : isHi ? 'रेफरेंस / यूटीआर' : 'Ref / UTR';
  String get previousDue =>
      isBn ? 'আগের মোট বাকি' : isHi ? 'पिछला कुल बकाया' : 'Previous Due';
  String get amountPaid =>
      isBn ? 'জমা দেওয়া হলো' : isHi ? 'जमा की गई राशि' : 'Amount Paid';
  String get remainingDue =>
      isBn ? 'বর্তমান নিট বাকি' : isHi ? 'वर्तमान शेष बकाया' : 'Remaining Due';
  String get billSettlementBreakdown =>
      isBn ? 'বিলের সমন্বয় বিবরণী' : isHi ? 'বিল समायोजन विवरण' : 'Bill Settlement Breakdown';
  String get shareWhatsApp =>
      isBn ? 'হোয়াটসঅ্যাপে পাঠান' : isHi ? 'व्हाट्सएप पर भेजें' : 'Share on WhatsApp';
  String get printSlip =>
      isBn ? 'রসিদ প্রিন্ট' : isHi ? 'रसीद प्रिंट' : 'Print Slip';
  String get copyReceiptText =>
      isBn ? 'মেসেজ কপি করুন' : isHi ? 'संदेश कॉपी करें' : 'Copy Text';
  String get close =>
      isBn ? 'বন্ধ করুন' : isHi ? 'बंद करें' : 'Close';
  String get copiedToast =>
      isBn ? 'রসিদের বিবরণ কপি করা হয়েছে!' : isHi ? 'रसीद का विवरण कॉपी किया गया!' : 'Receipt details copied!';

  // --- Supplier Ledger Dashboard ---
  String get ledgerTitle =>
      isBn ? 'সাপ্লায়ার লেজার ও খতিয়ান' : isHi ? 'आपूर्तिकर्ता खाता और विवरण' : 'Supplier Ledger & Statement';
  String get ledgerSubtitle =>
      isBn ? 'মহাজনের ক্রয়, পরিশোধ ও রানিং ব্যালেন্স খতিয়ান' : isHi ? 'खरीद, भुगतान और चालू शेष खाता' : 'Track supplier purchases, payments, and running balance ledger';
  String get openingBalance =>
      isBn ? 'প্রারম্ভিক জের' : isHi ? 'प्रारंभिक शेष' : 'Opening Balance';
  String get broughtForward =>
      isBn ? 'পূর্বের জের' : isHi ? 'पूर्व शेष' : 'Brought Forward';
  String get totalPurchases =>
      isBn ? 'মোট ক্রয়' : isHi ? 'कुल खरीद' : 'Total Purchases';
  String get totalPayments =>
      isBn ? 'মোট পরিশোধ' : isHi ? 'कुल भुगतान' : 'Total Payments';
  String get currentBalance =>
      isBn ? 'বর্তমান দেনা' : isHi ? 'वर्तमान बकाया' : 'Current Balance';
  String get netPayable =>
      isBn ? 'দেনা' : isHi ? 'देय' : 'Net Payable';
  String get advanceBalance =>
      isBn ? 'অগ্রিম জমা' : isHi ? 'अग्रिम शेष' : 'Advance Balance';
  String get payDue =>
      isBn ? 'বকেয়া পরিশোধ' : isHi ? 'बकाया भुगतान' : 'Pay Due';
  String get exportPdf =>
      isBn ? 'পিডিএফ ডাউনলোড' : isHi ? 'पीडीएफ डाउनलोड' : 'Export PDF';
  String get print =>
      isBn ? 'প্রিন্ট' : isHi ? 'प्रिंट' : 'Print';
  String get refresh =>
      isBn ? 'রিফ্রেশ' : isHi ? 'रिफ्रेश' : 'Refresh';
  String get searchPlaceholder =>
      isBn ? 'ভাউচার নং বা বিবরণ দিয়ে খুঁজুন...' : isHi ? 'वाउचर या विवरण से खोजें...' : 'Search by voucher, particulars...';
  String get all =>
      isBn ? 'সমস্ত' : isHi ? 'सभी' : 'All';
  String get purchasesCr =>
      isBn ? 'ক্রয় (ক্রেডিট)' : isHi ? 'खरीद (क्रेडिट)' : 'Purchases (Cr)';
  String get paymentsDr =>
      isBn ? 'পরিশোধ (ডেবিট)' : isHi ? 'भुगतान (डेबिट)' : 'Payments (Dr)';
  String get allTime =>
      isBn ? 'সব সময়' : isHi ? 'सभी समय' : 'All Time';
  String get thisMonth =>
      isBn ? 'চলতি মাস' : isHi ? 'इस महीने' : 'This Month';
  String get last30Days =>
      isBn ? 'গত ৩০ দিন' : isHi ? 'पिछले 30 दिन' : 'Last 30 Days';
  String get last90Days =>
      isBn ? 'গত ৯০ দিন' : isHi ? 'पिछले 90 दिन' : 'Last 90 Days';
  String get customRange =>
      isBn ? 'নির্দিষ্ট সময়সীমা' : isHi ? 'कस्टम अवधि' : 'Custom Range';
  String get viewVoucher =>
      isBn ? 'রশিদ' : isHi ? 'रसीद' : 'Voucher / Slip';
  String get dateCol =>
      isBn ? 'তারিখ' : isHi ? 'दिनांक' : 'Date';
  String get particularsCol =>
      isBn ? 'বিবরণ' : isHi ? 'विवरण' : 'Particulars / Items';
  String get vchTypeCol =>
      isBn ? 'টাইপ' : isHi ? 'प्रकार' : 'Vch Type';
  String get vchNoCol =>
      isBn ? 'ভাউচার নং' : isHi ? 'वाउचर नं' : 'Vch / Ref No.';
  String get paidDrCol =>
      isBn ? 'পরিশোধ / ডেবিট (Dr)' : isHi ? 'भुगतान / डेबिट (Dr)' : 'Paid / Debit (Dr)';
  String get billedCrCol =>
      isBn ? 'ক্রয় / ক্রেডিট (Cr)' : isHi ? 'खरीद / क्रेडिट (Cr)' : 'Billed / Credit (Cr)';
  String get runningBalCol =>
      isBn ? 'ব্যালেন্স' : isHi ? 'चालू शेष' : 'Running Balance';
  String get noRecordsFound =>
      isBn ? 'এই সময়ের জন্য কোনো লেনদেন পাওয়া যায়নি।' : isHi ? 'इस अवधि के लिए कोई रिकॉर्ड नहीं मिला।' : 'No ledger records found for this period.';
  String get paymentSettledByMode =>
      isBn ? 'পেমেন্ট মাধ্যম অনুযায়ী মোট:' : isHi ? 'माध्यम अनुसार कुल भुगतान:' : 'Payment Settled by Mode:';
  String get lastPaymentBanner =>
      isBn ? 'সর্বশেষ পেমেন্ট ভাউচার' : isHi ? 'अंतिम भुगतान वाउचर' : 'Latest Payment Voucher';
  String get selectSupplier =>
      isBn ? 'সাপ্লায়ার নির্বাচন' : isHi ? 'आपूर्तिकर्ता चुनें' : 'Select Supplier';
  String get totalRecords =>
      isBn ? 'মোট রেকর্ড:' : isHi ? 'कुल रिकॉर्ड:' : 'Total Records:';
  String get netClosingBalance =>
      isBn ? 'সমাপ্তি জের:' : isHi ? 'अंतिम शेष:' : 'Net Closing Balance:';
  String get payableSuffix =>
      isBn ? '(দেনা)' : isHi ? '(देय)' : '(Payable)';
  String get advanceSuffix =>
      isBn ? '(অগ্রিম)' : isHi ? '(अग्रिम)' : '(Advance)';
  String get viewSlip =>
      isBn ? 'রশিদ দেখুন' : isHi ? 'रसीद देखें' : 'View Slip';
  String get dismiss =>
      isBn ? 'বন্ধ করুন' : isHi ? 'हटाएं' : 'Dismiss';
  String get unregistered =>
      isBn ? 'অনিবন্ধিত' : isHi ? 'अपंजीकृत' : 'Unregistered';
  String get contactPerson =>
      isBn ? 'যোগাযোগ ব্যক্তি' : isHi ? 'संपर्क व्यक्ति' : 'Contact Person';
  String get gstin =>
      isBn ? 'GSTIN' : isHi ? 'GSTIN' : 'GSTIN';

  String billsCount(int count) =>
      isBn ? '$countটি বিল' : isHi ? '$count বিল' : '$count bills';

  String paymentsCount(int count) =>
      isBn ? '$countটি পেমেন্ট' : isHi ? '$count भुगतान' : '$count payments';

  String get crLabel => isBn ? 'পাওনা' : isHi ? 'जमा' : 'Cr';
  String get drLabel => isBn ? 'দেনা' : isHi ? 'বकाया' : 'Dr';

  String localizedPaymentMode(String mode) {
    final clean = mode.toUpperCase().trim();
    if (isBn) {
      return switch (clean) {
        'CASH' => 'নগদ',
        'UPI' => 'ইউপিআই',
        'BANK_TRANSFER' => 'ব্যাংক ট্রান্সফার',
        'CHEQUE' => 'চেক',
        'CARD' => 'কার্ড',
        'OTHER' => 'অন্যান্য',
        _ => clean,
      };
    } else if (isHi) {
      return switch (clean) {
        'CASH' => 'नकद',
        'UPI' => 'यूपीआई',
        'BANK_TRANSFER' => 'बैंक ट्रांसफर',
        'CHEQUE' => 'चेक',
        'CARD' => 'कार्ड',
        'OTHER' => 'अन्य',
        _ => clean,
      };
    }
    return clean.replaceAll('_', ' ');
  }

  String localizedEntryType(String entryType) {
    if (isBn) {
      return switch (entryType) {
        'PURCHASE_BILL' => 'ক্রয় বিল',
        'SUPPLIER_PAYMENT' => 'পরিশোধ',
        'OPENING_BALANCE' => 'প্রারম্ভিক জের',
        'PURCHASE_CORRECTION' => 'বিল সংশোধন',
        'SUPPLIER_REFUND' => 'ফেরত সমন্বয়',
        _ => entryType.replaceAll('_', ' '),
      };
    } else if (isHi) {
      return switch (entryType) {
        'PURCHASE_BILL' => 'खरीद बिल',
        'SUPPLIER_PAYMENT' => 'भुगतान',
        'OPENING_BALANCE' => 'प्रारंभिक शेष',
        'PURCHASE_CORRECTION' => 'বিল सुधार',
        'SUPPLIER_REFUND' => 'रिफंड',
        _ => entryType.replaceAll('_', ' '),
      };
    }
    return switch (entryType) {
      'PURCHASE_BILL' => 'Purchase Bill',
      'SUPPLIER_PAYMENT' => 'Payment',
      'OPENING_BALANCE' => 'Opening Balance',
      'PURCHASE_CORRECTION' => 'Purchase Correction',
      'SUPPLIER_REFUND' => 'Supplier Refund',
      _ => entryType.replaceAll('_', ' '),
    };
  }
}

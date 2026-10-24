class SupplierLedgerEntryModel {
  const SupplierLedgerEntryModel({
    required this.ledgerEntryId,
    required this.tenantId,
    required this.businessId,
    this.outletId,
    required this.supplierId,
    this.supplierBusinessId,
    required this.entryType,
    this.referenceType,
    this.referenceId,
    required this.debitPaise,
    required this.creditPaise,
    required this.transactionDate,
    required this.createdAt,
    this.createdBy,
    this.notes,
    this.paymentMode,
    this.referenceNo,
    this.voucherNumber,
    this.particulars,
    this.runningBalancePaise = 0,
    this.itemsSummary,
  });

  static const String typePurchaseBill = 'PURCHASE_BILL';
  static const String typeSupplierPayment = 'SUPPLIER_PAYMENT';
  static const String typeOpeningBalance = 'OPENING_BALANCE';
  static const String typePurchaseCorrection = 'PURCHASE_CORRECTION';
  static const String typeSupplierRefund = 'SUPPLIER_REFUND';
  static const String typeAdjustment = 'ADJUSTMENT';

  final String ledgerEntryId;
  final String tenantId;
  final String businessId;
  final String? outletId;
  final String supplierId;
  final String? supplierBusinessId;
  final String entryType;
  final String? referenceType;
  final String? referenceId;
  final int debitPaise; // Payments made to supplier / reduction in liability
  final int creditPaise; // Purchases / Opening balance / increase in liability
  final DateTime transactionDate;
  final DateTime createdAt;
  final String? createdBy;
  final String? notes;
  final String? paymentMode; // CASH, BANK_TRANSFER, UPI, CHEQUE, CARD
  final String? referenceNo; // e.g. Cheque No, UTR, Txn Ref
  final String? voucherNumber; // Bill No or Payment Voucher No
  final String? particulars; // Description
  final int runningBalancePaise; // Running balance after this transaction
  final String? itemsSummary; // Product items summary if purchase

  bool get isOpening => entryType == typeOpeningBalance;
  bool get isRefund => entryType == typeSupplierRefund;
  bool get isCorrection => entryType == typePurchaseCorrection;
  bool get isPayment =>
      entryType == typeSupplierPayment ||
      (debitPaise > 0 && creditPaise == 0 && !isRefund);
  bool get isPurchase =>
      entryType == typePurchaseBill ||
      (creditPaise > 0 && debitPaise == 0 && !isOpening && !isCorrection);

  String get displayType {
    switch (entryType) {
      case typePurchaseBill:
        return 'Purchase Bill';
      case typeSupplierPayment:
        return 'Payment';
      case typeOpeningBalance:
        return 'Opening Balance';
      case typePurchaseCorrection:
        return 'Purchase Correction';
      case typeSupplierRefund:
        return 'Supplier Refund';
      default:
        return entryType.replaceAll('_', ' ');
    }
  }

  factory SupplierLedgerEntryModel.fromData(
    String id,
    Map<String, dynamic> data, {
    String? fallbackParticulars,
    String? fallbackVoucherNumber,
    String? fallbackPaymentMode,
    String? fallbackReferenceNo,
    String? fallbackItemsSummary,
    int runningBalance = 0,
  }) {
    final rawDate = data['transactionDate'] ?? data['date'];
    final transactionDate = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(rawDate?.toString() ?? '') ??
            _date(data['createdAt']) ??
            DateTime.now();

    final createdAt = _date(data['createdAt']) ?? transactionDate;

    final debit = (data['debit'] as num?)?.toInt() ??
        (data['debitPaise'] as num?)?.toInt() ??
        0;
    final credit = (data['credit'] as num?)?.toInt() ??
        (data['creditPaise'] as num?)?.toInt() ??
        0;

    return SupplierLedgerEntryModel(
      ledgerEntryId: data['ledgerEntryId'] as String? ?? id,
      tenantId:
          data['tenantId'] as String? ?? data['ownerUid'] as String? ?? '',
      businessId: data['businessId'] as String? ?? '',
      outletId: data['outletId'] as String?,
      supplierId: data['supplierId'] as String? ?? '',
      supplierBusinessId: data['supplierBusinessId'] as String?,
      entryType: data['entryType'] as String? ?? 'PURCHASE_BILL',
      referenceType: data['referenceType'] as String?,
      referenceId: data['referenceId'] as String?,
      debitPaise: debit,
      creditPaise: credit,
      transactionDate: transactionDate,
      createdAt: createdAt,
      createdBy: data['createdBy'] as String?,
      notes: data['notes'] as String? ?? data['reason'] as String?,
      paymentMode:
          data['paymentMode'] as String? ?? fallbackPaymentMode,
      referenceNo: data['transactionReference'] as String? ??
          data['referenceNo'] as String? ??
          fallbackReferenceNo,
      voucherNumber: data['voucherNumber'] as String? ??
          data['invoiceNumber'] as String? ??
          fallbackVoucherNumber ??
          (data['referenceId'] as String?),
      particulars:
          data['particulars'] as String? ?? fallbackParticulars,
      runningBalancePaise: runningBalance,
      itemsSummary:
          data['itemsSummary'] as String? ?? fallbackItemsSummary,
    );
  }

  SupplierLedgerEntryModel copyWith({
    int? runningBalancePaise,
    String? particulars,
    String? voucherNumber,
    String? paymentMode,
    String? referenceNo,
    String? itemsSummary,
  }) {
    return SupplierLedgerEntryModel(
      ledgerEntryId: ledgerEntryId,
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      supplierId: supplierId,
      supplierBusinessId: supplierBusinessId,
      entryType: entryType,
      referenceType: referenceType,
      referenceId: referenceId,
      debitPaise: debitPaise,
      creditPaise: creditPaise,
      transactionDate: transactionDate,
      createdAt: createdAt,
      createdBy: createdBy,
      notes: notes,
      paymentMode: paymentMode ?? this.paymentMode,
      referenceNo: referenceNo ?? this.referenceNo,
      voucherNumber: voucherNumber ?? this.voucherNumber,
      particulars: particulars ?? this.particulars,
      runningBalancePaise: runningBalancePaise ?? this.runningBalancePaise,
      itemsSummary: itemsSummary ?? this.itemsSummary,
    );
  }

  static DateTime? _date(dynamic val) {
    if (val == null) return null;
    if (val is DateTime) return val;
    return DateTime.tryParse(val.toString());
  }
}

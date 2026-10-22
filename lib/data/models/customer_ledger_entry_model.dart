class CustomerLedgerEntryModel {
  const CustomerLedgerEntryModel({
    required this.transactionId,
    required this.businessId,
    required this.tenantId,
    required this.customerId,
    required this.outletId,
    this.invoiceId,
    required this.transactionType,
    required this.amountPaise,
    this.debitPaise = 0,
    this.creditPaise = 0,
    this.advanceCreditPaise = 0,
    required this.createdAt,
    required this.createdBy,
    this.status = 'POSTED',
    this.notes,
    this.paymentId,
    this.entryType,
    this.immutable = true,
  });

  static const String typeCreditSale = 'CREDIT_SALE';
  static const String typePayment = 'PAYMENT';
  static const String typeCreditNote = 'CREDIT_NOTE';
  static const String typeRefund = 'REFUND';
  static const String typeAdjustment = 'ADJUSTMENT';
  static const String typeOpeningBalance = 'OPENING_BALANCE';

  static const List<String> allowedTransactionTypes = [
    typeCreditSale,
    typePayment,
    typeCreditNote,
    typeRefund,
    typeAdjustment,
    typeOpeningBalance,
  ];

  final String transactionId;
  final String businessId;
  final String tenantId;
  final String customerId;
  final String outletId;
  final String? invoiceId;
  final String transactionType;
  final int amountPaise;
  final int debitPaise;
  final int creditPaise;
  final int advanceCreditPaise;
  final DateTime createdAt;
  final String createdBy;
  final String status;
  final String? notes;
  final String? paymentId;
  final String? entryType;
  final bool immutable;

  factory CustomerLedgerEntryModel.fromData(String id, Map<String, dynamic> data) {
    final rawDate = data['createdAt'];
    final createdAt = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

    final rawType = data['transactionType'] as String?;
    final legacyEntryType = data['entryType'] as String?;
    final resolvedType = rawType != null && allowedTransactionTypes.contains(rawType)
        ? rawType
        : _inferTransactionType(legacyEntryType, data);

    final amount = (data['amountPaise'] as num?)?.toInt() ??
        (data['amount'] as num?)?.toInt() ??
        ((data['debitPaise'] as num?)?.toInt() ?? 0) +
            ((data['creditPaise'] as num?)?.toInt() ?? 0);

    return CustomerLedgerEntryModel(
      transactionId: data['transactionId'] as String? ?? id,
      businessId: data['businessId'] as String? ?? '',
      tenantId: data['tenantId'] as String? ?? '',
      customerId: data['customerId'] as String? ?? '',
      outletId: data['outletId'] as String? ?? '',
      invoiceId: data['invoiceId'] as String?,
      transactionType: resolvedType,
      amountPaise: amount,
      debitPaise: (data['debitPaise'] as num?)?.toInt() ?? 0,
      creditPaise: (data['creditPaise'] as num?)?.toInt() ?? 0,
      advanceCreditPaise: (data['advanceCreditPaise'] as num?)?.toInt() ?? 0,
      createdAt: createdAt,
      createdBy: data['createdBy'] as String? ?? data['createdByUid'] as String? ?? 'SYSTEM',
      status: data['status'] as String? ?? 'POSTED',
      notes: data['notes'] as String? ?? data['reason'] as String?,
      paymentId: data['paymentId'] as String?,
      entryType: legacyEntryType,
      immutable: data['immutable'] as bool? ?? true,
    );
  }

  static String _inferTransactionType(String? legacyType, Map<String, dynamic> data) {
    if (legacyType == 'CANCELLATION_REVERSAL' ||
        legacyType == 'INVOICE_EDIT_ADJUSTMENT') {
      return typeAdjustment;
    }
    if (legacyType == 'OVERPAYMENT_ADVANCE') {
      return typePayment;
    }
    final debit = (data['debitPaise'] as num?)?.toInt() ?? 0;
    final credit = (data['creditPaise'] as num?)?.toInt() ?? 0;
    if (credit > 0 && debit == 0) return typePayment;
    if (debit > 0 && credit == 0) return typeCreditSale;
    return typeAdjustment;
  }

  Map<String, dynamic> toData() => {
    'transactionId': transactionId,
    'businessId': businessId,
    'tenantId': tenantId,
    'customerId': customerId,
    'outletId': outletId,
    if (invoiceId != null) 'invoiceId': invoiceId,
    'transactionType': transactionType,
    'amountPaise': amountPaise,
    'debitPaise': debitPaise,
    'creditPaise': creditPaise,
    'advanceCreditPaise': advanceCreditPaise,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'createdBy': createdBy,
    'status': status,
    if (notes != null) 'notes': notes,
    if (paymentId != null) 'paymentId': paymentId,
    if (entryType != null) 'entryType': entryType,
    'immutable': immutable,
  };
}

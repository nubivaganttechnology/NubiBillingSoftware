class SupplierRefundModel {
  const SupplierRefundModel({
    required this.refundId,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.supplierBusinessId,
    required this.amount,
    required this.refundDate,
    required this.paymentMode,
    required this.reason,
    required this.status,
    required this.financialTransactionId,
    required this.createdByUid,
    required this.createdAt,
    this.referenceNo,
    this.notes,
    this.requestId,
  });

  final String refundId;
  final String tenantId;
  final String businessId;
  final String outletId;
  final String supplierBusinessId;
  final int amount;
  final DateTime refundDate;
  final String paymentMode;
  final String reason;
  final String status;
  final String financialTransactionId;
  final String createdByUid;
  final DateTime createdAt;
  final String? referenceNo;
  final String? notes;
  final String? requestId;

  Map<String, dynamic> toData() => {
    'refundId': refundId,
    'tenantId': tenantId,
    'businessId': businessId,
    'outletId': outletId,
    'supplierBusinessId': supplierBusinessId,
    'amount': amount,
    'refundDate': refundDate.toUtc(),
    'paymentMode': paymentMode,
    'referenceNo': referenceNo,
    'reason': reason,
    'notes': notes,
    'status': status,
    'financialTransactionId': financialTransactionId,
    'createdByUid': createdByUid,
    'createdAt': createdAt.toUtc(),
    'updatedAt': createdAt.toUtc(),
    'requestId': requestId,
  };

  factory SupplierRefundModel.fromData(String id, Map<String, dynamic> data) =>
      SupplierRefundModel(
        refundId: data['refundId'] as String? ?? id,
        tenantId: data['tenantId'] as String? ?? '',
        businessId: data['businessId'] as String? ?? '',
        outletId: data['outletId'] as String? ?? '',
        supplierBusinessId: data['supplierBusinessId'] as String? ?? '',
        amount: (data['amount'] as num?)?.toInt() ?? 0,
        refundDate: _date(data['refundDate']),
        paymentMode: data['paymentMode'] as String? ?? '',
        referenceNo: data['referenceNo'] as String?,
        reason: data['reason'] as String? ?? '',
        notes: data['notes'] as String?,
        status: data['status'] as String? ?? '',
        financialTransactionId: data['financialTransactionId'] as String? ?? '',
        createdByUid: data['createdByUid'] as String? ?? '',
        createdAt: _date(data['createdAt']),
        requestId: data['requestId'] as String?,
      );
}

DateTime _date(dynamic value) => value is DateTime
    ? value
    : DateTime.tryParse(value?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

class FinancialTransactionModel {
  const FinancialTransactionModel({
    required this.transactionId,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.direction,
    required this.transactionType,
    required this.partyType,
    required this.partyId,
    required this.amount,
    required this.paymentMode,
    required this.referenceType,
    required this.referenceId,
    required this.transactionDate,
    required this.createdByUid,
    required this.createdAt,
    required this.status,
    this.referenceNo,
    this.notes,
  });

  final String transactionId;
  final String tenantId;
  final String businessId;
  final String outletId;
  final String direction;
  final String transactionType;
  final String partyType;
  final String partyId;
  final int amount;
  final String paymentMode;
  final String referenceType;
  final String referenceId;
  final DateTime transactionDate;
  final String createdByUid;
  final DateTime createdAt;
  final String status;
  final String? referenceNo;
  final String? notes;

  Map<String, dynamic> toData() => {
    'transactionId': transactionId,
    'tenantId': tenantId,
    'businessId': businessId,
    'outletId': outletId,
    'direction': direction,
    'transactionType': transactionType,
    'partyType': partyType,
    'partyId': partyId,
    'amount': amount,
    'paymentMode': paymentMode,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'transactionDate': transactionDate.toUtc(),
    'referenceNo': referenceNo,
    'notes': notes,
    'createdByUid': createdByUid,
    'createdAt': createdAt.toUtc(),
    'updatedAt': createdAt.toUtc(),
    'status': status,
  };
}

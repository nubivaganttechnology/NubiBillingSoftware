class CustomerPaymentAllocation {
  const CustomerPaymentAllocation({
    required this.allocationId,
    required this.paymentId,
    required this.invoiceId,
    required this.originalOutletId,
    required this.allocatedPaise,
    this.status = 'POSTED',
    required this.createdAt,
  });

  final String allocationId;
  final String paymentId;
  final String invoiceId;
  final String originalOutletId;
  final int allocatedPaise;
  final String status;
  final DateTime createdAt;

  factory CustomerPaymentAllocation.fromData(Map<String, dynamic> data) {
    final rawDate = data['createdAt'];
    final createdAt = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

    return CustomerPaymentAllocation(
      allocationId: data['allocationId'] as String? ?? '',
      paymentId: data['paymentId'] as String? ?? '',
      invoiceId: data['invoiceId'] as String? ?? '',
      originalOutletId: data['originalOutletId'] as String? ?? '',
      allocatedPaise: (data['allocatedPaise'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? 'POSTED',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toData() => {
    'allocationId': allocationId,
    'paymentId': paymentId,
    'invoiceId': invoiceId,
    'originalOutletId': originalOutletId,
    'allocatedPaise': allocatedPaise,
    'status': status,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class CustomerPaymentRecord {
  const CustomerPaymentRecord({
    required this.paymentId,
    required this.businessId,
    required this.tenantId,
    required this.customerId,
    required this.collectedAtOutletId,
    required this.amountPaise,
    required this.paymentMethod,
    required this.receivedBy,
    this.status = 'POSTED',
    this.allocations = const [],
    this.excessAdvancePaise = 0,
    this.notes,
    this.idempotencyKey,
    required this.createdAt,
    this.immutable = true,
  });

  final String paymentId;
  final String businessId;
  final String tenantId;
  final String customerId;
  final String collectedAtOutletId;
  final int amountPaise;
  final String paymentMethod;
  final String receivedBy;
  final String status;
  final List<CustomerPaymentAllocation> allocations;
  final int excessAdvancePaise;
  final String? notes;
  final String? idempotencyKey;
  final DateTime createdAt;
  final bool immutable;

  int get totalAllocatedPaise =>
      allocations.fold<int>(0, (sum, a) => sum + a.allocatedPaise);

  factory CustomerPaymentRecord.fromData(String id, Map<String, dynamic> data) {
    final rawDate = data['createdAt'];
    final createdAt = rawDate is DateTime
        ? rawDate
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

    final rawAllocations = data['allocations'];
    final allocations = <CustomerPaymentAllocation>[];
    if (rawAllocations is List) {
      for (final item in rawAllocations) {
        if (item is Map<String, dynamic>) {
          allocations.add(CustomerPaymentAllocation.fromData(item));
        } else if (item is Map) {
          allocations.add(
            CustomerPaymentAllocation.fromData(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return CustomerPaymentRecord(
      paymentId: data['paymentId'] as String? ?? id,
      businessId: data['businessId'] as String? ?? '',
      tenantId: data['tenantId'] as String? ?? '',
      customerId: data['customerId'] as String? ?? '',
      collectedAtOutletId:
          data['collectedAtOutletId'] as String? ?? data['outletId'] as String? ?? '',
      amountPaise: (data['amountPaise'] as num?)?.toInt() ??
          (data['amount'] as num?)?.toInt() ??
          0,
      paymentMethod: data['paymentMethod'] as String? ??
          data['mode'] as String? ??
          'CASH',
      receivedBy: data['receivedBy'] as String? ??
          data['createdBy'] as String? ??
          data['cashierUid'] as String? ??
          'SYSTEM',
      status: data['status'] as String? ?? 'POSTED',
      allocations: allocations,
      excessAdvancePaise:
          (data['excessAdvancePaise'] as num?)?.toInt() ??
          (data['advancePaise'] as num?)?.toInt() ??
          0,
      notes: data['notes'] as String? ?? data['reason'] as String?,
      idempotencyKey: data['idempotencyKey'] as String?,
      createdAt: createdAt,
      immutable: data['immutable'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toData() => {
    'paymentId': paymentId,
    'businessId': businessId,
    'tenantId': tenantId,
    'customerId': customerId,
    'collectedAtOutletId': collectedAtOutletId,
    'outletId': collectedAtOutletId,
    'amountPaise': amountPaise,
    'paymentMethod': paymentMethod,
    'mode': paymentMethod,
    'receivedBy': receivedBy,
    'status': status,
    'allocations': allocations.map((a) => a.toData()).toList(),
    'excessAdvancePaise': excessAdvancePaise,
    if (notes != null) 'notes': notes,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'immutable': immutable,
    if (allocations.isNotEmpty) 'invoiceId': allocations.first.invoiceId,
    if (allocations.isNotEmpty)
      'appliedPaise': totalAllocatedPaise,
  };
}

class PaymentAllocationRequest {
  const PaymentAllocationRequest({
    required this.invoiceId,
    required this.originalOutletId,
    required this.allocatedPaise,
  });

  final String invoiceId;
  final String originalOutletId;
  final int allocatedPaise;
}

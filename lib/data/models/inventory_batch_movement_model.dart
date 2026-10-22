import '../../core/errors/app_exception.dart';

class InventoryBatchMovementModel {
  const InventoryBatchMovementModel({
    required this.movementId,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.batchId,
    required this.variantId,
    required this.movementType,
    required this.quantity,
    required this.direction,
    required this.referenceType,
    required this.referenceId,
    required this.occurredAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.productId,
    this.referenceLineId,
    this.reason,
    this.createdByUid,
    this.isDeleted = false,
  });

  static const movementDirections = <String, String>{
    'PURCHASE_RECEIPT': 'IN',
    'SALE': 'OUT',
    'SALE_RETURN': 'IN',
    'PURCHASE_RETURN': 'OUT',
    'TRANSFER_IN': 'IN',
    'TRANSFER_OUT': 'OUT',
    'ADJUSTMENT_IN': 'IN',
    'ADJUSTMENT_OUT': 'OUT',
    'PURCHASE_CORRECTION_IN': 'IN',
    'PURCHASE_CORRECTION_OUT': 'OUT',
    'PURCHASE_CANCEL_REVERSAL': 'OUT',
  };

  final String movementId, tenantId, businessId, outletId, batchId, variantId;
  final String movementType, direction, referenceType, referenceId, status;
  final String? productId, referenceLineId, reason, createdByUid;
  final int quantity;
  final DateTime occurredAt, createdAt, updatedAt;
  final bool isDeleted;

  void validate() {
    if (movementId.trim().isEmpty ||
        tenantId.trim().isEmpty ||
        businessId.trim().isEmpty ||
        outletId.trim().isEmpty ||
        batchId.trim().isEmpty ||
        variantId.trim().isEmpty) {
      throw const AppException(
        'Batch movement scope and identity are required.',
      );
    }
    if (quantity <= 0) {
      throw const AppException(
        'Batch movement quantity must be greater than zero.',
      );
    }
    final expectedDirection = movementDirections[movementType];
    if (expectedDirection == null || direction != expectedDirection) {
      throw const AppException(
        'Batch movement type and direction are invalid.',
      );
    }
    if (referenceType.trim().isEmpty || referenceId.trim().isEmpty) {
      throw const AppException('Batch movement reference is required.');
    }
    if (status != 'POSTED') {
      throw const AppException('Only posted batch movements can be recorded.');
    }
  }

  factory InventoryBatchMovementModel.fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime parse(dynamic value) => value is DateTime
        ? value.toUtc()
        : DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return InventoryBatchMovementModel(
      movementId: data['movementId'] as String? ?? id,
      tenantId: data['tenantId'] as String? ?? '',
      businessId: data['businessId'] as String? ?? '',
      outletId: data['outletId'] as String? ?? '',
      batchId: data['batchId'] as String? ?? '',
      productId: data['productId'] as String?,
      variantId: data['variantId'] as String? ?? '',
      movementType: data['movementType'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      direction: data['direction'] as String? ?? '',
      referenceType: data['referenceType'] as String? ?? '',
      referenceId: data['referenceId'] as String? ?? '',
      referenceLineId: data['referenceLineId'] as String?,
      reason: data['reason'] as String?,
      createdByUid: data['createdByUid'] as String?,
      occurredAt: parse(data['occurredAt']),
      status: data['status'] as String? ?? '',
      isDeleted: data['isDeleted'] == true,
      createdAt: parse(data['createdAt']),
      updatedAt: parse(data['updatedAt']),
    );
  }

  Map<String, dynamic> toData() => {
    'movementId': movementId,
    'tenantId': tenantId,
    'businessId': businessId,
    'outletId': outletId,
    'batchId': batchId,
    if (productId != null) 'productId': productId,
    'variantId': variantId,
    'movementType': movementType,
    'quantity': quantity,
    'direction': direction,
    'referenceType': referenceType,
    'referenceId': referenceId,
    if (referenceLineId != null) 'referenceLineId': referenceLineId,
    if (reason != null) 'reason': reason,
    if (createdByUid != null) 'createdByUid': createdByUid,
    'occurredAt': occurredAt.toUtc(),
    'status': status,
    'isDeleted': isDeleted,
    'createdAt': createdAt.toUtc(),
    'updatedAt': updatedAt.toUtc(),
  };
}

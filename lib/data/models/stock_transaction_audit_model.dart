import '../../core/errors/app_exception.dart';

/// Represents an immutable audit trail record for any inventory movement or adjustment.
///
/// Complies with enterprise inventory audit standards, tracking complete provenance,
/// previous/changed/new quantities, user authorization, approval lifecycle, and offline sync.
class StockTransactionAuditModel {
  const StockTransactionAuditModel({
    required this.transactionId,
    required this.businessId,
    required this.outletId,
    required this.productId,
    required this.variantId,
    required this.transactionType,
    required this.sourceDocumentId,
    required this.previousQuantity,
    required this.changedQuantity,
    required this.newQuantity,
    required this.unit,
    required this.reason,
    required this.performedBy,
    required this.approvedBy,
    required this.approvalStatus,
    required this.createdAt,
    required this.syncStatus,
    this.tenantId,
    this.unitCostPaise,
    this.batchId,
    this.rejectionReason,
  });

  final String transactionId;
  final String businessId;
  final String outletId;
  final String productId;
  final String variantId;
  final String transactionType;
  final String? sourceDocumentId;
  final int previousQuantity;
  final int changedQuantity;
  final int newQuantity;
  final String unit;
  final String reason;
  final String performedBy;
  final String? approvedBy;
  final String approvalStatus;
  final DateTime createdAt;
  final String syncStatus;
  final String? tenantId;
  final int? unitCostPaise;
  final String? batchId;
  final String? rejectionReason;

  // Approval Statuses
  static const statusPosted = 'POSTED';
  static const statusPendingApproval = 'PENDING_APPROVAL';
  static const statusRejected = 'REJECTED';
  static const statusPendingSync = 'PENDING_SYNC';
  static const statusConflict = 'CONFLICT';

  // Sync Statuses
  static const syncStatusSynced = 'SYNCED';
  static const syncStatusPending = 'PENDING_SYNC';
  static const syncStatusConflict = 'CONFLICT';
  static const syncStatusPosted = 'POSTED';

  static const typeOpeningStock = 'OPENING_STOCK';
  static const typeAdjustmentIn = 'ADJUSTMENT_IN';
  static const typeAdjustmentOut = 'ADJUSTMENT_OUT';
  static const typePurchaseReceipt = 'PURCHASE_RECEIPT';
  static const typeSale = 'SALE';
  static const typeCustomerReturn = 'CUSTOMER_RETURN';
  static const typeSupplierReturn = 'SUPPLIER_RETURN';
  static const typeTransferIn = 'TRANSFER_IN';
  static const typeTransferOut = 'TRANSFER_OUT';
  static const typeDamageLoss = 'DAMAGE_LOSS';
  static const typeCountCorrection = 'COUNT_CORRECTION';

  bool get isApproved => approvalStatus == statusPosted;
  bool get isPendingApproval => approvalStatus == statusPendingApproval;
  bool get isRejected => approvalStatus == statusRejected;

  void validate() {
    if (transactionId.trim().isEmpty) {
      throw const AppException('Stock transaction ID is required.');
    }
    if (businessId.trim().isEmpty || outletId.trim().isEmpty) {
      throw const AppException('Business and outlet scope are required.');
    }
    if (productId.trim().isEmpty || variantId.trim().isEmpty) {
      throw const AppException('Product and variant IDs are required.');
    }
    if (reason.trim().isEmpty) {
      throw const AppException('A reason is required for every stock movement.');
    }
    if (changedQuantity <= 0) {
      throw const AppException('Changed quantity must be greater than zero.');
    }
    if (newQuantity < 0) {
      throw const AppException('Stock cannot become negative.');
    }
  }

  Map<String, dynamic> toData() {
    return {
      'transactionId': transactionId,
      'movementId': transactionId, // Compatibility with legacy stock_movements
      'businessId': businessId,
      'outletId': outletId,
      'productId': productId,
      'variantId': variantId,
      'transactionType': transactionType,
      'type': transactionType, // Compatibility with legacy stock_movements
      'sourceDocumentId': sourceDocumentId,
      'referenceId': sourceDocumentId, // Compatibility
      'previousQuantity': previousQuantity,
      'changedQuantity': changedQuantity,
      'qtyBase': changedQuantity, // Compatibility
      'newQuantity': newQuantity,
      'balanceAfter': newQuantity, // Compatibility
      'unit': unit,
      'reason': reason,
      'performedBy': performedBy,
      'userId': performedBy, // Compatibility
      'approvedBy': approvedBy,
      'approvalStatus': approvalStatus,
      'status': approvalStatus, // Compatibility
      'createdAt': createdAt.toUtc().toIso8601String(),
      'syncStatus': syncStatus,
      if (tenantId != null) 'tenantId': tenantId,
      if (unitCostPaise != null) 'unitCostPaise': unitCostPaise,
      if (batchId != null) 'batchId': batchId,
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      'immutable': approvalStatus == statusPosted,
    };
  }

  factory StockTransactionAuditModel.fromData(
    String id,
    Map<String, dynamic> data,
  ) {
    DateTime parseDate(dynamic value) {
      if (value is DateTime) return value.toUtc();
      if (value is String) {
        return DateTime.tryParse(value)?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final prev = (data['previousQuantity'] as num?)?.toInt() ?? 0;
    final chg = (data['changedQuantity'] as num?)?.toInt() ??
        (data['qtyBase'] as num?)?.toInt() ??
        0;
    final nxt = (data['newQuantity'] as num?)?.toInt() ??
        (data['balanceAfter'] as num?)?.toInt() ??
        0;

    return StockTransactionAuditModel(
      transactionId: data['transactionId'] as String? ??
          data['movementId'] as String? ??
          id,
      businessId: data['businessId'] as String? ?? '',
      outletId: data['outletId'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      variantId: data['variantId'] as String? ?? '',
      transactionType: data['transactionType'] as String? ??
          data['type'] as String? ??
          'ADJUSTMENT',
      sourceDocumentId: data['sourceDocumentId'] as String? ??
          data['referenceId'] as String?,
      previousQuantity: prev,
      changedQuantity: chg,
      newQuantity: nxt,
      unit: data['unit'] as String? ?? 'pcs',
      reason: data['reason'] as String? ?? '',
      performedBy: data['performedBy'] as String? ??
          data['userId'] as String? ??
          '',
      approvedBy: data['approvedBy'] as String?,
      approvalStatus: data['approvalStatus'] as String? ??
          data['status'] as String? ??
          statusPosted,
      createdAt: parseDate(data['createdAt']),
      syncStatus: data['syncStatus'] as String? ?? 'SYNCED',
      tenantId: data['tenantId'] as String?,
      unitCostPaise: (data['unitCostPaise'] as num?)?.toInt(),
      batchId: data['batchId'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}

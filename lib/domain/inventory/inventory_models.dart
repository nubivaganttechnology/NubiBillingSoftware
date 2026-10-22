enum StockMovementType {
  receive,
  adjustIn,
  adjustOut,
  damageLoss,
  countCorrection,
  sale,
  returnStock,
}

extension StockMovementTypeValue on StockMovementType {
  String get value => switch (this) {
    StockMovementType.receive => 'RECEIVE',
    StockMovementType.adjustIn => 'ADJUST_IN',
    StockMovementType.adjustOut => 'ADJUST_OUT',
    StockMovementType.damageLoss => 'DAMAGE_LOSS',
    StockMovementType.countCorrection => 'COUNT_CORRECTION',
    StockMovementType.sale => 'SALE',
    StockMovementType.returnStock => 'RETURN',
  };
}

class StockMovementRequest {
  const StockMovementRequest({
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.productId,
    required this.qtyBase,
    required this.type,
    required this.reason,
    required this.userId,
    required this.token,
    this.unitCostPaise,
    this.referenceId,
    this.stockBalanceId,
  });

  final String tenantId;
  final String businessId;
  final String outletId;
  final String productId;
  final int qtyBase;
  final StockMovementType type;
  final String reason;
  final String userId;
  final String token;
  final int? unitCostPaise;
  final String? referenceId;
  final String? stockBalanceId;
}

class StockMovementResult {
  const StockMovementResult({
    required this.movementId,
    required this.balanceAfter,
  });

  final String movementId;
  final int balanceAfter;
}

class InventoryProductStatus {
  const InventoryProductStatus._(this.value);

  static const out = InventoryProductStatus._('OUT');
  static const low = InventoryProductStatus._('LOW');
  static const inStock = InventoryProductStatus._('IN_STOCK');

  final String value;
}

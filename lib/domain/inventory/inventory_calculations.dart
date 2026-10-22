import 'inventory_models.dart';

int weightedAverageCost({
  required int currentQuantity,
  required int currentAverageCostPaise,
  required int receivedQuantity,
  required int receivedUnitCostPaise,
}) {
  if (currentQuantity < 0 ||
      receivedQuantity <= 0 ||
      currentAverageCostPaise < 0 ||
      receivedUnitCostPaise < 0) {
    throw ArgumentError('Inventory quantities and costs must be non-negative.');
  }
  if (currentQuantity == 0) return receivedUnitCostPaise;
  return ((currentQuantity * currentAverageCostPaise) +
          (receivedQuantity * receivedUnitCostPaise)) ~/
      (currentQuantity + receivedQuantity);
}

int applyStockMovement({
  required int currentQuantity,
  required StockMovementType type,
  required int qtyBase,
}) {
  if (currentQuantity < 0 || qtyBase <= 0) {
    throw ArgumentError('Inventory quantities must be positive.');
  }
  final increases = switch (type) {
    StockMovementType.receive ||
    StockMovementType.adjustIn ||
    StockMovementType.returnStock => true,
    StockMovementType.adjustOut ||
    StockMovementType.damageLoss ||
    StockMovementType.countCorrection ||
    StockMovementType.sale => false,
  };
  final next = increases ? currentQuantity + qtyBase : currentQuantity - qtyBase;
  if (next < 0) {
    throw StateError('Stock cannot become negative.');
  }
  return next;
}

InventoryProductStatus stockStatus({
  required int quantityOnHand,
  required int reorderLevel,
}) {
  if (quantityOnHand <= 0) return InventoryProductStatus.out;
  if (quantityOnHand <= reorderLevel) return InventoryProductStatus.low;
  return InventoryProductStatus.inStock;
}

int sellingQuantityToBase({
  required int quantity,
  required int conversionFactor,
}) {
  if (quantity <= 0 || conversionFactor <= 0) {
    throw ArgumentError('Quantity and conversion factor must be positive.');
  }
  return quantity * conversionFactor;
}

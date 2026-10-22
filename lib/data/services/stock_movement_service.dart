import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/inventory/inventory_calculations.dart';
import '../../domain/inventory/inventory_models.dart';
import 'firestore_transaction_service.dart';

class StockMovementService {
  StockMovementService(this.transactions);

  final FirestoreTransactionService transactions;

  Future<StockMovementResult> apply(StockMovementRequest request) {
    final reason = request.reason.trim();
    if (reason.isEmpty) {
      throw const AppException('A reason is required for every stock movement.');
    }
    if (request.qtyBase <= 0) {
      throw const AppException('Stock quantity must be greater than zero.');
    }
    if (request.type == StockMovementType.receive &&
        (request.unitCostPaise == null || request.unitCostPaise! < 0)) {
      throw const AppException('Enter a valid purchase cost for received stock.');
    }

    final balanceId =
        request.stockBalanceId ??
        '${request.tenantId}_${request.businessId}_OUTLET_'
        '${request.outletId}_DIRECT_${request.productId}';
    return transactions.runAtomicOperation((tx) async {
      final balance = await tx.get(FirebaseConstants.stockBalances, balanceId);
      final currentQuantity =
          (balance.fields['quantityOnHand'] as num?)?.toInt() ?? 0;
      final balanceAfter = applyStockMovement(
        currentQuantity: currentQuantity,
        type: request.type,
        qtyBase: request.qtyBase,
      );

      final movementId = IdGenerator.create('STM');
      tx.create(FirebaseConstants.stockMovements, movementId, {
        'tenantId': request.tenantId,
        'businessId': request.businessId,
        'outletId': request.outletId,
        'productId': request.productId,
        'variantId': request.productId,
        'type': request.type.value,
        'qtyBase': request.qtyBase,
        'unitCostPaise': request.unitCostPaise,
        'reason': reason,
        'referenceId': request.referenceId,
        'userId': request.userId,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'balanceAfter': balanceAfter,
        'immutable': true,
      });

      final balanceFields = <String, dynamic>{
        'tenantId': request.tenantId,
        'businessId': request.businessId,
        'outletId': request.outletId,
        'productId': request.productId,
        'variantId': request.productId,
        'quantityOnHand': balanceAfter,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      if (request.type == StockMovementType.receive) {
        final currentAverage =
            (balance.fields['avgCostPaise'] as num?)?.toInt() ?? 0;
        final average = weightedAverageCost(
          currentQuantity: currentQuantity,
          currentAverageCostPaise: currentAverage,
          receivedQuantity: request.qtyBase,
          receivedUnitCostPaise: request.unitCostPaise!,
        );
        balanceFields['avgCostPaise'] = average;
        balanceFields['lastPurchasePricePaise'] = request.unitCostPaise;
        final cost = await tx.get(FirebaseConstants.productCosts, request.productId);
        final costFields = {
          'productId': request.productId,
          'businessId': request.businessId,
          'purchasePricePaise': request.unitCostPaise,
          'avgCostPaise': average,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'updatedBy': request.userId,
        };
        if (cost.exists) {
          tx.update(
            FirebaseConstants.productCosts,
            request.productId,
            costFields,
            updateTime: cost.updateTime,
          );
        } else {
          tx.create(FirebaseConstants.productCosts, request.productId, costFields);
        }
      }
      if (balance.exists) {
        tx.update(
          FirebaseConstants.stockBalances,
          balanceId,
          balanceFields,
          updateTime: balance.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.stockBalances, balanceId, balanceFields);
      }
      return StockMovementResult(
        movementId: movementId,
        balanceAfter: balanceAfter,
      );
    }, idToken: request.token);
  }
}

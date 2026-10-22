import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../models/inventory_batch_movement_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

class InventoryBatchMovementRepository {
  InventoryBatchMovementRepository(this.firestore);

  final FirestoreDataService firestore;

  Future<void> record(
    FirestoreTransactionContext transaction,
    InventoryBatchMovementModel movement, {
    required String token,
  }) async {
    movement.validate();
    final batch = await transaction.get(
      FirebaseConstants.inventoryBatches,
      movement.batchId,
    );
    if (!batch.exists ||
        batch.fields['tenantId'] != movement.tenantId ||
        batch.fields['businessId'] != movement.businessId ||
        batch.fields['outletId'] != movement.outletId ||
        batch.fields['variantId'] != movement.variantId ||
        (movement.productId != null &&
            batch.fields['productId'] != movement.productId)) {
      throw const AppException(
        'Batch movement does not match an existing scoped inventory batch.',
      );
    }
    if (movement.direction == 'OUT') {
      await validateOutboundQuantity(
        tenantId: movement.tenantId,
        businessId: movement.businessId,
        outletId: movement.outletId,
        batchId: movement.batchId,
        quantity: movement.quantity,
        token: token,
      );
    }
    transaction.create(
      FirebaseConstants.inventoryBatchMovements,
      movement.movementId,
      movement.toData(),
    );
  }

  Future<List<InventoryBatchMovementModel>> listByBatch({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String batchId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.inventoryBatchMovements,
      filters: _scope(tenantId, businessId, outletId)
        ..add(FirestoreFilter('batchId', 'EQUAL', batchId)),
      orderBy: 'occurredAt',
      idToken: token,
    );
    return _models(docs);
  }

  Future<List<InventoryBatchMovementModel>> listByVariantAndOutlet({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String variantId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.inventoryBatchMovements,
      filters: _scope(tenantId, businessId, outletId)
        ..add(FirestoreFilter('variantId', 'EQUAL', variantId)),
      orderBy: 'occurredAt',
      idToken: token,
    );
    return _models(docs);
  }

  Future<List<InventoryBatchMovementModel>> listByReference({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String referenceType,
    required String referenceId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.inventoryBatchMovements,
      filters: _scope(tenantId, businessId, outletId)
        ..addAll([
          FirestoreFilter('referenceType', 'EQUAL', referenceType),
          FirestoreFilter('referenceId', 'EQUAL', referenceId),
        ]),
      orderBy: 'occurredAt',
      idToken: token,
    );
    return _models(docs);
  }

  Future<int> totalInForBatch({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String batchId,
    required String token,
  }) async => _totalForDirection(
    tenantId: tenantId,
    businessId: businessId,
    outletId: outletId,
    batchId: batchId,
    direction: 'IN',
    token: token,
  );

  Future<int> totalOutForBatch({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String batchId,
    required String token,
  }) async => _totalForDirection(
    tenantId: tenantId,
    businessId: businessId,
    outletId: outletId,
    batchId: batchId,
    direction: 'OUT',
    token: token,
  );

  Future<int> derivedAvailableForBatch({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String batchId,
    required String token,
  }) async {
    final incoming = await totalInForBatch(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      batchId: batchId,
      token: token,
    );
    final outgoing = await totalOutForBatch(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      batchId: batchId,
      token: token,
    );
    return incoming - outgoing;
  }

  Future<void> validateOutboundQuantity({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String batchId,
    required int quantity,
    required String token,
  }) async {
    if (quantity <= 0) {
      throw const AppException(
        'Batch movement quantity must be greater than zero.',
      );
    }
    final available = await derivedAvailableForBatch(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      batchId: batchId,
      token: token,
    );
    if (quantity > available) {
      throw const AppException(
        'Outbound quantity exceeds the derived available quantity for this batch.',
      );
    }
  }

  Future<int> _totalForDirection({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String batchId,
    required String direction,
    required String token,
  }) async {
    final movements = await listByBatch(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      batchId: batchId,
      token: token,
    );
    return movements
        .where(
          (movement) =>
              movement.direction == direction &&
              movement.status == 'POSTED' &&
              !movement.isDeleted,
        )
        .fold<int>(0, (total, movement) => total + movement.quantity);
  }

  List<FirestoreFilter> _scope(
    String tenantId,
    String businessId,
    String outletId,
  ) => [
    FirestoreFilter('tenantId', 'EQUAL', tenantId),
    FirestoreFilter('businessId', 'EQUAL', businessId),
    FirestoreFilter('outletId', 'EQUAL', outletId),
  ];

  List<InventoryBatchMovementModel> _models(List<Map<String, dynamic>> docs) =>
      [
        for (final doc in docs)
          InventoryBatchMovementModel.fromData(
            (doc['name'] as String).split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
      ];
}

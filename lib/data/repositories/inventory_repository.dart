import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_catalog.dart';
import '../../core/utils/id_generator.dart';
import '../models/inventory_batch_movement_model.dart';
import '../models/stock_transaction_audit_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';
import 'inventory_batch_movement_repository.dart';

class InventoryRepository {
  InventoryRepository({
    required this.firestore,
    required this.transactions,
  }) : batchMovements = InventoryBatchMovementRepository(firestore);

  final FirestoreDataService firestore;
  final FirestoreTransactionService transactions;
  final InventoryBatchMovementRepository batchMovements;

  static String stockBalanceId(String tenantId, String outletId, String variantId) =>
      '${tenantId}_${outletId}_$variantId';

  /// Returns current stock balance for a given variant at a specific outlet.
  Future<int> getAvailableStock({
    required String tenantId,
    required String outletId,
    required String variantId,
    required String token,
  }) async {
    final balanceId = stockBalanceId(tenantId, outletId, variantId);
    try {
      final doc = await firestore.getDocument(
        FirebaseConstants.stockBalances,
        balanceId,
        idToken: token,
      );
      if (!doc.containsKey('fields')) return 0;
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      if (fields['tenantId'] != tenantId || fields['outletId'] != outletId) return 0;
      return (fields['quantityOnHand'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // Document does not exist yet -> stock is 0
      return 0;
    }
  }

  /// Checks whether opening stock has already been registered or verified for this variant at this outlet.
  Future<bool> hasOpeningStockBeenInitialized({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String variantId,
    required String token,
  }) async {
    final movements = await firestore.queryDocuments(
      collection: FirebaseConstants.stockMovements,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        FirestoreFilter('variantId', 'EQUAL', variantId),
      ],
      idToken: token,
    );

    for (final doc in movements) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final type = fields['transactionType'] as String? ?? fields['type'] as String?;
      final status = fields['approvalStatus'] as String? ?? fields['status'] as String?;
      if ((type == StockTransactionAuditModel.typeOpeningStock ||
              type == StockTransactionAuditModel.typePurchaseReceipt) &&
          status == StockTransactionAuditModel.statusPosted) {
        return true;
      }
    }

    final batches = await firestore.queryDocuments(
      collection: FirebaseConstants.inventoryBatches,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        FirestoreFilter('variantId', 'EQUAL', variantId),
      ],
      idToken: token,
    );
    for (final doc in batches) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final batchId = fields['batchId'] as String? ?? '';
      final receivedQty = (fields['receivedQty'] as num?)?.toInt() ?? 0;
      if (batchId.contains('BATCH_OP_') && receivedQty > 0) {
        return true;
      }
    }

    return false;
  }

  /// Registers physical inventory opening stock during initial setup.
  Future<StockTransactionAuditModel> addOpeningStock({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String productId,
    required String variantId,
    required int quantity,
    required String reason,
    required String userId,
    required String token,
    required List<String> permissions,
    required bool isOwner,
    int? unitCostPaise,
    String? unit,
    String? transactionId,
  }) async {
    final authorized = isOwner ||
        PermissionCatalog.allows('inventory.opening_stock', permissions);
    if (!authorized) {
      throw const AppException(
        'You do not have permission to enter opening stock.',
        code: 'permission-denied',
      );
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AppException('A reason is required for opening stock.');
    }
    if (quantity <= 0) {
      throw const AppException('Stock quantity must be greater than zero.');
    }

    final alreadyInitialized = await hasOpeningStockBeenInitialized(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      variantId: variantId,
      token: token,
    );
    if (alreadyInitialized) {
      throw const AppException(
        'Opening stock has already been initialized for this product at this outlet.',
      );
    }

    final currentBalance = await getAvailableStock(
      tenantId: tenantId,
      outletId: outletId,
      variantId: variantId,
      token: token,
    );
    if (currentBalance > 0) {
      throw const AppException(
        'Opening stock has already been initialized for this product at this outlet.',
      );
    }

    final balanceId = stockBalanceId(tenantId, outletId, variantId);
    final txId = transactionId ?? IdGenerator.create('TX_OP');
    final now = DateTime.now().toUtc();
    final cost = unitCostPaise ?? 0;
    final totalVal = (cost * quantity) ~/ 1000;

    return transactions.runAtomicOperation((tx) async {
      // Idempotency: prevent duplicate execution
      final existingMovement =
          await tx.get(FirebaseConstants.stockMovements, txId);
      if (existingMovement.exists) {
        return StockTransactionAuditModel.fromData(
          txId,
          existingMovement.fields,
        );
      }

      final balanceDoc =
          await tx.get(FirebaseConstants.stockBalances, balanceId);
      final prevQty =
          (balanceDoc.fields['quantityOnHand'] as num?)?.toInt() ?? 0;
      if (prevQty > 0) {
        throw const AppException(
          'Opening stock has already been initialized for this product at this outlet.',
        );
      }

      final batchId =
          'BATCH_OP_${outletId}_${variantId}_${now.millisecondsSinceEpoch}';
      tx.create(FirebaseConstants.inventoryBatches, batchId, {
        'batchId': batchId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'productId': productId,
        'variantId': variantId,
        'internalBatchNo': 'BAT-OP-${IdGenerator.create('B')}',
        'receivedQty': quantity,
        'availableQty': quantity,
        'receivedDate': now,
        'status': 'AVAILABLE',
        'isDeleted': false,
        'createdAt': now,
        'updatedAt': now,
      });

      final batchMovementId =
          'BM_OP_${now.millisecondsSinceEpoch}_${IdGenerator.create('M')}';
      final batchMovement = InventoryBatchMovementModel(
        movementId: batchMovementId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        batchId: batchId,
        productId: productId,
        variantId: variantId,
        movementType: 'OPENING_STOCK',
        quantity: quantity,
        direction: 'IN',
        referenceType: 'OPENING_STOCK',
        referenceId: txId,
        reason: trimmedReason,
        createdByUid: userId,
        occurredAt: now,
        status: 'POSTED',
        createdAt: now,
        updatedAt: now,
      );
      tx.create(
        FirebaseConstants.inventoryBatchMovements,
        batchMovement.movementId,
        batchMovement.toData(),
      );

      tx.create(FirebaseConstants.inventoryTransactions, txId, {
        'inventoryTransactionId': txId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'locationType': 'OUTLET',
        'locationId': outletId,
        'productId': productId,
        'variantId': variantId,
        'transactionType': 'OPENING_STOCK',
        'sourceType': 'OPENING_STOCK',
        'sourceId': txId,
        'direction': 'IN',
        'quantity': quantity,
        'baseQuantity': quantity,
        'unitCost': cost,
        'totalCost': totalVal,
        'reason': trimmedReason,
        'createdBy': userId,
        'createdAt': now,
      });

      final nextQty = prevQty + quantity;
      final balanceFields = {
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'locationType': 'OUTLET',
        'locationId': outletId,
        'rackId': null,
        'productId': productId,
        'variantId': variantId,
        'quantityOnHand': nextQty,
        'averageCost': cost,
        'totalValue': totalVal,
        'lastInventoryTransactionId': txId,
        'updatedAt': now,
      };

      if (balanceDoc.exists) {
        tx.update(
          FirebaseConstants.stockBalances,
          balanceId,
          balanceFields,
          updateTime: balanceDoc.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.stockBalances, balanceId, balanceFields);
      }

      final audit = StockTransactionAuditModel(
        transactionId: txId,
        businessId: businessId,
        outletId: outletId,
        productId: productId,
        variantId: variantId,
        transactionType: StockTransactionAuditModel.typeOpeningStock,
        sourceDocumentId: txId,
        previousQuantity: prevQty,
        changedQuantity: quantity,
        newQuantity: nextQty,
        unit: unit ?? 'pcs',
        reason: trimmedReason,
        performedBy: userId,
        approvedBy: userId,
        approvalStatus: StockTransactionAuditModel.statusPosted,
        createdAt: now,
        syncStatus: StockTransactionAuditModel.statusPendingSync,
        tenantId: tenantId,
        unitCostPaise: cost,
        batchId: batchId,
      );

      tx.create(FirebaseConstants.stockMovements, txId, audit.toData());
      return audit;
    }, idToken: token);
  }

  /// Submits a stock adjustment.
  ///
  /// If the user possesses [inventory.approve_adjustment] or is an owner, the adjustment
  /// is posted immediately and stock balances/batches are updated atomically.
  /// If the user does not possess approval rights, the adjustment is recorded as
  /// [PENDING_APPROVAL], leaving available stock strictly unchanged until approved.
  Future<StockTransactionAuditModel> requestOrApplyAdjustment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String productId,
    required String variantId,
    required int quantity,
    required bool isIncrease,
    required String transactionType,
    required String reason,
    required String userId,
    required String token,
    required List<String> permissions,
    required bool isOwner,
    String? unit,
    int? unitCostPaise,
    String? transactionId,
    String? sourceDocumentId,
  }) async {
    final canAdjust =
        isOwner || PermissionCatalog.allows('inventory.adjust', permissions);
    if (!canAdjust) {
      throw const AppException(
        'You do not have permission to adjust stock.',
        code: 'permission-denied',
      );
    }

    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AppException('A reason is required for every stock movement.');
    }
    if (quantity <= 0) {
      throw const AppException('Stock quantity must be greater than zero.');
    }

    // Direct quantity increase without authorized method safeguard
    if (isIncrease &&
        transactionType != StockTransactionAuditModel.typeAdjustmentIn &&
        transactionType != StockTransactionAuditModel.typeCountCorrection &&
        transactionType != StockTransactionAuditModel.typeOpeningStock &&
        transactionType != StockTransactionAuditModel.typePurchaseReceipt &&
        transactionType != StockTransactionAuditModel.typeCustomerReturn &&
        transactionType != StockTransactionAuditModel.typeTransferIn) {
      throw const AppException(
        'This product has no recorded stock. Please enter a purchase receipt, authorized opening stock, or stock adjustment.',
      );
    }

    final currentAvailable = await getAvailableStock(
      tenantId: tenantId,
      outletId: outletId,
      variantId: variantId,
      token: token,
    );

    if (!isIncrease) {
      if (currentAvailable <= 0) {
        throw const AppException(
          'Stock cannot be reduced because the available quantity is 0.',
        );
      }
      if (quantity > currentAvailable) {
        throw const AppException(
          'Insufficient available stock. Please check the quantity.',
        );
      }
    }

    final canApprove = isOwner ||
        PermissionCatalog.allows(
          'inventory.approve_adjustment',
          permissions,
        );

    final txId = transactionId ?? IdGenerator.create('TX_ADJ');
    final now = DateTime.now().toUtc();
    final effectiveType = isIncrease
        ? (transactionType.isNotEmpty
            ? transactionType
            : StockTransactionAuditModel.typeAdjustmentIn)
        : (transactionType.isNotEmpty
            ? transactionType
            : StockTransactionAuditModel.typeAdjustmentOut);

    if (!canApprove) {
      // Unapproved adjustment: Stock remains unchanged!
      final audit = StockTransactionAuditModel(
        transactionId: txId,
        businessId: businessId,
        outletId: outletId,
        productId: productId,
        variantId: variantId,
        transactionType: effectiveType,
        sourceDocumentId: sourceDocumentId ?? txId,
        previousQuantity: currentAvailable,
        changedQuantity: quantity,
        newQuantity: currentAvailable,
        unit: unit ?? 'pcs',
        reason: trimmedReason,
        performedBy: userId,
        approvedBy: null,
        approvalStatus: StockTransactionAuditModel.statusPendingApproval,
        createdAt: now,
        syncStatus: StockTransactionAuditModel.statusPendingSync,
        tenantId: tenantId,
        unitCostPaise: unitCostPaise,
      );

      await firestore.createDocument(
        FirebaseConstants.stockMovements,
        txId,
        audit.toData(),
        idToken: token,
      );
      return audit;
    }

    // Approved: atomic balance, batch, and transaction update
    final balanceId = stockBalanceId(tenantId, outletId, variantId);
    return transactions.runAtomicOperation((tx) async {
      final existingMovement =
          await tx.get(FirebaseConstants.stockMovements, txId);
      if (existingMovement.exists &&
          existingMovement.fields['approvalStatus'] ==
              StockTransactionAuditModel.statusPosted) {
        return StockTransactionAuditModel.fromData(
          txId,
          existingMovement.fields,
        );
      }

      final balanceDoc =
          await tx.get(FirebaseConstants.stockBalances, balanceId);
      final currentQty =
          (balanceDoc.fields['quantityOnHand'] as num?)?.toInt() ?? 0;

      if (!isIncrease) {
        if (currentQty <= 0) {
          throw const AppException(
            'Stock cannot be reduced because the available quantity is 0.',
          );
        }
        if (quantity > currentQty) {
          throw const AppException(
            'Insufficient available stock. Please check the quantity.',
          );
        }
      }

      final int nextQty;
      String? assignedBatchId;

      if (isIncrease) {
        nextQty = currentQty + quantity;
        assignedBatchId =
            'BATCH_ADJ_${outletId}_${variantId}_${now.millisecondsSinceEpoch}';
        tx.create(FirebaseConstants.inventoryBatches, assignedBatchId, {
          'batchId': assignedBatchId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'productId': productId,
          'variantId': variantId,
          'internalBatchNo': 'BAT-ADJ-${IdGenerator.create('B')}',
          'receivedQty': quantity,
          'availableQty': quantity,
          'receivedDate': now,
          'status': 'AVAILABLE',
          'isDeleted': false,
          'createdAt': now,
          'updatedAt': now,
        });

        final mvId =
            'BM_ADJ_${now.millisecondsSinceEpoch}_${IdGenerator.create('M')}';
        final batchMovement = InventoryBatchMovementModel(
          movementId: mvId,
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          batchId: assignedBatchId,
          productId: productId,
          variantId: variantId,
          movementType: 'ADJUSTMENT_IN',
          quantity: quantity,
          direction: 'IN',
          referenceType: 'STOCK_ADJUSTMENT',
          referenceId: txId,
          reason: trimmedReason,
          createdByUid: userId,
          occurredAt: now,
          status: 'POSTED',
          createdAt: now,
          updatedAt: now,
        );
        tx.create(
          FirebaseConstants.inventoryBatchMovements,
          batchMovement.movementId,
          batchMovement.toData(),
        );
      } else {
        nextQty = currentQty - quantity;
        if (nextQty < 0) {
          throw const AppException('Stock cannot become negative.');
        }

        // Allocate from available batches (FIFO)
        final batchDocs = await tx.query(
          FirebaseConstants.inventoryBatches,
          [
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
            FirestoreFilter('outletId', 'EQUAL', outletId),
            FirestoreFilter('variantId', 'EQUAL', variantId),
          ],
        );

        var remainingToDeduct = quantity;
        for (final bDoc in batchDocs) {
          if (remainingToDeduct <= 0) break;
          final bData = bDoc.fields;
          if (bData['isDeleted'] == true) continue;
          final bAvail = (bData['availableQty'] as num?)?.toInt() ?? 0;
          if (bAvail <= 0) continue;

          final deduct = remainingToDeduct < bAvail ? remainingToDeduct : bAvail;
          final nextAvail = bAvail - deduct;
          remainingToDeduct -= deduct;
          final bId = bData['batchId'] as String;
          assignedBatchId ??= bId;

          tx.update(
            FirebaseConstants.inventoryBatches,
            bId,
            {
              'availableQty': nextAvail,
              'status': nextAvail == 0 ? 'DEPLETED' : 'AVAILABLE',
              'updatedAt': now,
            },
            updateTime: bDoc.updateTime,
          );

          final mvId =
              'BM_ADJ_${now.millisecondsSinceEpoch}_${IdGenerator.create('M')}';
          final batchMovement = InventoryBatchMovementModel(
            movementId: mvId,
            tenantId: tenantId,
            businessId: businessId,
            outletId: outletId,
            batchId: bId,
            productId: productId,
            variantId: variantId,
            movementType: 'ADJUSTMENT_OUT',
            quantity: deduct,
            direction: 'OUT',
            referenceType: 'STOCK_ADJUSTMENT',
            referenceId: txId,
            reason: trimmedReason,
            createdByUid: userId,
            occurredAt: now,
            status: 'POSTED',
            createdAt: now,
            updatedAt: now,
          );
          tx.create(
            FirebaseConstants.inventoryBatchMovements,
            batchMovement.movementId,
            batchMovement.toData(),
          );
        }
      }

      tx.create(FirebaseConstants.inventoryTransactions, txId, {
        'inventoryTransactionId': txId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'locationType': 'OUTLET',
        'locationId': outletId,
        'productId': productId,
        'variantId': variantId,
        'transactionType': effectiveType,
        'sourceType': 'STOCK_ADJUSTMENT',
        'sourceId': txId,
        'direction': isIncrease ? 'IN' : 'OUT',
        'quantity': quantity,
        'baseQuantity': quantity,
        'unitCost': unitCostPaise ?? 0,
        'reason': trimmedReason,
        'createdBy': userId,
        'createdAt': now,
      });

      final balanceFields = {
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'locationType': 'OUTLET',
        'locationId': outletId,
        'rackId': null,
        'productId': productId,
        'variantId': variantId,
        'quantityOnHand': nextQty,
        'lastInventoryTransactionId': txId,
        'updatedAt': now,
      };

      if (balanceDoc.exists) {
        tx.update(
          FirebaseConstants.stockBalances,
          balanceId,
          balanceFields,
          updateTime: balanceDoc.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.stockBalances, balanceId, balanceFields);
      }

      final audit = StockTransactionAuditModel(
        transactionId: txId,
        businessId: businessId,
        outletId: outletId,
        productId: productId,
        variantId: variantId,
        transactionType: effectiveType,
        sourceDocumentId: sourceDocumentId ?? txId,
        previousQuantity: currentQty,
        changedQuantity: quantity,
        newQuantity: nextQty,
        unit: unit ?? 'pcs',
        reason: trimmedReason,
        performedBy: userId,
        approvedBy: userId,
        approvalStatus: StockTransactionAuditModel.statusPosted,
        createdAt: now,
        syncStatus: StockTransactionAuditModel.statusPendingSync,
        tenantId: tenantId,
        unitCostPaise: unitCostPaise,
        batchId: assignedBatchId,
      );

      if (existingMovement.exists) {
        tx.update(
          FirebaseConstants.stockMovements,
          txId,
          audit.toData(),
          updateTime: existingMovement.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.stockMovements, txId, audit.toData());
      }

      return audit;
    }, idToken: token);
  }

  /// Approves a pending stock adjustment.
  Future<StockTransactionAuditModel> approveAdjustment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String transactionId,
    required String userId,
    required String token,
    required List<String> permissions,
    required bool isOwner,
  }) async {
    final canApprove = isOwner ||
        PermissionCatalog.allows(
          'inventory.approve_adjustment',
          permissions,
        );
    if (!canApprove) {
      throw const AppException(
        'You do not have permission to approve stock adjustments.',
        code: 'permission-denied',
      );
    }

    return transactions.runAtomicOperation((tx) async {
      final doc = await tx.get(FirebaseConstants.stockMovements, transactionId);
      if (!doc.exists) {
        throw const AppException('Stock adjustment was not found.');
      }
      final pending = StockTransactionAuditModel.fromData(transactionId, doc.fields);
      if (pending.approvalStatus != StockTransactionAuditModel.statusPendingApproval) {
        throw const AppException('This stock adjustment is not pending approval.');
      }

      final isIncrease = pending.transactionType == StockTransactionAuditModel.typeAdjustmentIn ||
          pending.transactionType == StockTransactionAuditModel.typeCountCorrection ||
          pending.transactionType == StockTransactionAuditModel.typeOpeningStock;

      final variantBalanceId = stockBalanceId(tenantId, outletId, pending.variantId);
      final balanceDoc = await tx.get(FirebaseConstants.stockBalances, variantBalanceId);
      final currentQty = (balanceDoc.fields['quantityOnHand'] as num?)?.toInt() ?? 0;

      if (!isIncrease) {
        if (currentQty <= 0) {
          throw const AppException(
            'Stock cannot be reduced because the available quantity is 0.',
          );
        }
        if (pending.changedQuantity > currentQty) {
          throw const AppException(
            'Insufficient available stock. Please check the quantity.',
          );
        }
      }

      final nextQty = isIncrease
          ? currentQty + pending.changedQuantity
          : currentQty - pending.changedQuantity;

      if (nextQty < 0) {
        throw const AppException('Stock cannot become negative.');
      }

      final now = DateTime.now().toUtc();
      String? assignedBatchId = pending.batchId;

      if (isIncrease) {
        assignedBatchId ??=
            'BATCH_ADJ_${outletId}_${pending.variantId}_${now.millisecondsSinceEpoch}';
        tx.create(FirebaseConstants.inventoryBatches, assignedBatchId, {
          'batchId': assignedBatchId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'productId': pending.productId,
          'variantId': pending.variantId,
          'internalBatchNo': 'BAT-ADJ-${IdGenerator.create('B')}',
          'receivedQty': pending.changedQuantity,
          'availableQty': pending.changedQuantity,
          'receivedDate': now,
          'status': 'AVAILABLE',
          'isDeleted': false,
          'createdAt': now,
          'updatedAt': now,
        });

        final mvId =
            'BM_ADJ_${now.millisecondsSinceEpoch}_${IdGenerator.create('M')}';
        final batchMovement = InventoryBatchMovementModel(
          movementId: mvId,
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          batchId: assignedBatchId,
          productId: pending.productId,
          variantId: pending.variantId,
          movementType: 'ADJUSTMENT_IN',
          quantity: pending.changedQuantity,
          direction: 'IN',
          referenceType: 'STOCK_ADJUSTMENT',
          referenceId: transactionId,
          reason: pending.reason,
          createdByUid: userId,
          occurredAt: now,
          status: 'POSTED',
          createdAt: now,
          updatedAt: now,
        );
        tx.create(
          FirebaseConstants.inventoryBatchMovements,
          batchMovement.movementId,
          batchMovement.toData(),
        );
      } else {
        // Allocate batches
        final batchDocs = await tx.query(
          FirebaseConstants.inventoryBatches,
          [
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
            FirestoreFilter('outletId', 'EQUAL', outletId),
            FirestoreFilter('variantId', 'EQUAL', pending.variantId),
          ],
        );

        var remaining = pending.changedQuantity;
        for (final bDoc in batchDocs) {
          if (remaining <= 0) break;
          final bData = bDoc.fields;
          if (bData['isDeleted'] == true) continue;
          final bAvail = (bData['availableQty'] as num?)?.toInt() ?? 0;
          if (bAvail <= 0) continue;

          final deduct = remaining < bAvail ? remaining : bAvail;
          final nextAvail = bAvail - deduct;
          remaining -= deduct;
          final bId = bData['batchId'] as String;
          assignedBatchId ??= bId;

          tx.update(
            FirebaseConstants.inventoryBatches,
            bId,
            {
              'availableQty': nextAvail,
              'status': nextAvail == 0 ? 'DEPLETED' : 'AVAILABLE',
              'updatedAt': now,
            },
            updateTime: bDoc.updateTime,
          );

          final mvId =
              'BM_ADJ_${now.millisecondsSinceEpoch}_${IdGenerator.create('M')}';
          final batchMovement = InventoryBatchMovementModel(
            movementId: mvId,
            tenantId: tenantId,
            businessId: businessId,
            outletId: outletId,
            batchId: bId,
            productId: pending.productId,
            variantId: pending.variantId,
            movementType: 'ADJUSTMENT_OUT',
            quantity: deduct,
            direction: 'OUT',
            referenceType: 'STOCK_ADJUSTMENT',
            referenceId: transactionId,
            reason: pending.reason,
            createdByUid: userId,
            occurredAt: now,
            status: 'POSTED',
            createdAt: now,
            updatedAt: now,
          );
          tx.create(
            FirebaseConstants.inventoryBatchMovements,
            batchMovement.movementId,
            batchMovement.toData(),
          );
        }
      }

      final balanceFields = {
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'locationType': 'OUTLET',
        'locationId': outletId,
        'rackId': null,
        'productId': pending.productId,
        'variantId': pending.variantId,
        'quantityOnHand': nextQty,
        'lastInventoryTransactionId': transactionId,
        'updatedAt': now,
      };

      if (balanceDoc.exists) {
        tx.update(
          FirebaseConstants.stockBalances,
          variantBalanceId,
          balanceFields,
          updateTime: balanceDoc.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.stockBalances, variantBalanceId, balanceFields);
      }

      final approvedAudit = StockTransactionAuditModel(
        transactionId: pending.transactionId,
        businessId: pending.businessId,
        outletId: pending.outletId,
        productId: pending.productId,
        variantId: pending.variantId,
        transactionType: pending.transactionType,
        sourceDocumentId: pending.sourceDocumentId,
        previousQuantity: currentQty,
        changedQuantity: pending.changedQuantity,
        newQuantity: nextQty,
        unit: pending.unit,
        reason: pending.reason,
        performedBy: pending.performedBy,
        approvedBy: userId,
        approvalStatus: StockTransactionAuditModel.statusPosted,
        createdAt: pending.createdAt,
        syncStatus: StockTransactionAuditModel.statusPendingSync,
        tenantId: tenantId,
        unitCostPaise: pending.unitCostPaise,
        batchId: assignedBatchId,
      );

      tx.update(
        FirebaseConstants.stockMovements,
        transactionId,
        approvedAudit.toData(),
        updateTime: doc.updateTime,
      );

      return approvedAudit;
    }, idToken: token);
  }

  /// Rejects a pending stock adjustment without modifying stock balances.
  Future<StockTransactionAuditModel> rejectAdjustment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String transactionId,
    required String userId,
    required String token,
    required List<String> permissions,
    required bool isOwner,
    String? rejectionReason,
  }) async {
    final canApprove = isOwner ||
        PermissionCatalog.allows(
          'inventory.approve_adjustment',
          permissions,
        );
    if (!canApprove) {
      throw const AppException(
        'You do not have permission to reject stock adjustments.',
        code: 'permission-denied',
      );
    }

    return transactions.runAtomicOperation((tx) async {
      final doc = await tx.get(FirebaseConstants.stockMovements, transactionId);
      if (!doc.exists) {
        throw const AppException('Stock adjustment was not found.');
      }
      final pending = StockTransactionAuditModel.fromData(transactionId, doc.fields);
      if (pending.approvalStatus != StockTransactionAuditModel.statusPendingApproval) {
        throw const AppException('This stock adjustment is not pending approval.');
      }

      final rejectedAudit = StockTransactionAuditModel(
        transactionId: pending.transactionId,
        businessId: pending.businessId,
        outletId: pending.outletId,
        productId: pending.productId,
        variantId: pending.variantId,
        transactionType: pending.transactionType,
        sourceDocumentId: pending.sourceDocumentId,
        previousQuantity: pending.previousQuantity,
        changedQuantity: pending.changedQuantity,
        newQuantity: pending.previousQuantity, // Stock untouched
        unit: pending.unit,
        reason: pending.reason,
        performedBy: pending.performedBy,
        approvedBy: userId,
        approvalStatus: StockTransactionAuditModel.statusRejected,
        createdAt: pending.createdAt,
        syncStatus: StockTransactionAuditModel.statusPendingSync,
        tenantId: tenantId,
        unitCostPaise: pending.unitCostPaise,
        batchId: pending.batchId,
        rejectionReason: rejectionReason ?? 'Rejected by manager.',
      );

      tx.update(
        FirebaseConstants.stockMovements,
        transactionId,
        rejectedAudit.toData(),
        updateTime: doc.updateTime,
      );

      return rejectedAudit;
    }, idToken: token);
  }

  /// Returns audit history of stock movements for a specific variant or outlet.
  Future<List<StockTransactionAuditModel>> getStockHistory({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
    String? variantId,
    List<String> permissions = const ['*'],
    bool isOwner = true,
  }) async {
    final canView = isOwner ||
        PermissionCatalog.allows('inventory.view', permissions) ||
        PermissionCatalog.allows('inventory', permissions);
    if (!canView) {
      throw const AppException(
        'You do not have permission to view inventory history.',
        code: 'permission-denied',
      );
    }

    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.stockMovements,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        if (variantId != null && variantId.isNotEmpty)
          FirestoreFilter('variantId', 'EQUAL', variantId),
      ],
      orderBy: 'createdAt',
      idToken: token,
    );

    final list = docs.map((doc) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final id = (doc['name'] as String? ?? '').split('/').last;
      return StockTransactionAuditModel.fromData(id, fields);
    }).toList();

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Returns adjustments that are awaiting approval.
  Future<List<StockTransactionAuditModel>> getPendingAdjustments({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
    List<String> permissions = const ['*'],
    bool isOwner = true,
  }) async {
    final canApprove = isOwner ||
        PermissionCatalog.allows(
          'inventory.approve_adjustment',
          permissions,
        );
    if (!canApprove) {
      throw const AppException(
        'You do not have permission to view pending adjustments.',
        code: 'permission-denied',
      );
    }

    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.stockMovements,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        FirestoreFilter('approvalStatus', 'EQUAL', StockTransactionAuditModel.statusPendingApproval),
      ],
      idToken: token,
    );

    final list = docs.map((doc) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final id = (doc['name'] as String? ?? '').split('/').last;
      return StockTransactionAuditModel.fromData(id, fields);
    }).toList();

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/stock_transaction_audit_model.dart';
import 'package:testflutter/data/repositories/inventory_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

class _OfflineConnectivity extends ConnectivityService {
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

String _token({String uid = 'test-owner'}) {
  final claims = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'sub': uid,
        'aud': EnvironmentConfig.projectId,
        'exp':
            DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }),
    ),
  );
  return 'header.$claims.signature';
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalDatabase database;
  late OfflineFirestoreService offline;
  late SyncEngine sync;
  late LocalDataSource local;
  late InventoryRepository inventoryRepository;

  const tenantId = 'TENANT-001';
  const businessId = 'BIZ-001';
  const outlet1 = 'OUTLET-A';
  const outlet2 = 'OUTLET-B';
  const productId = 'PROD-100';
  const variantId = 'VAR-100';

  final ownerToken = _token(uid: 'OWNER-1');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inventory-test-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    final remote = FirestoreRestService(ApiClient());
    sync = SyncEngine(
      remote,
      _OfflineConnectivity(),
      sessionProvider: () async => null,
    );
    offline = OfflineFirestoreService(database, remote, sync);
    await offline.activate('OWNER-1');
    local = await offline.localDataSourceForToken(ownerToken);
    inventoryRepository = InventoryRepository(
      firestore: offline,
      transactions: offline,
    );

    // Seed master business, outlet, and catalog product
    await local.upsertRemote('businesses', [
      {
        'name': 'businesses/$businessId',
        'fields': FirestoreRestService.encodeFields({
          'businessId': businessId,
          'ownerUid': 'OWNER-1',
          'tenantId': tenantId,
          'status': 'ACTIVE',
          'isActive': true,
        }),
      },
    ]);

    await local.upsertRemote('outlets', [
      {
        'name': 'outlets/$outlet1',
        'fields': FirestoreRestService.encodeFields({
          'outletId': outlet1,
          'tenantId': tenantId,
          'businessId': businessId,
          'status': 'ACTIVE',
          'isActive': true,
        }),
      },
      {
        'name': 'outlets/$outlet2',
        'fields': FirestoreRestService.encodeFields({
          'outletId': outlet2,
          'tenantId': tenantId,
          'businessId': businessId,
          'status': 'ACTIVE',
          'isActive': true,
        }),
      },
    ]);

    await local.upsertRemote('products', [
      {
        'name': 'products/$productId',
        'fields': FirestoreRestService.encodeFields({
          'productId': productId,
          'tenantId': tenantId,
          'businessId': businessId,
          'name': 'Premium Arabica Coffee Beans',
          'status': 'ACTIVE',
          'isActive': true,
        }),
      },
    ]);

    await local.upsertRemote('product_variants', [
      {
        'name': 'product_variants/$variantId',
        'fields': FirestoreRestService.encodeFields({
          'variantId': variantId,
          'productId': productId,
          'tenantId': tenantId,
          'businessId': businessId,
          'name': '1kg Whole Bean',
          'sellingPrice': 120000,
          'purchaseRate': 85000,
          'reorderLevel': 5,
          'status': 'ACTIVE',
        }),
      },
    ]);
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  group('Secure Product Stock Quantity Management Specification Tests', () {
    test('Scenario 1: New product without purchase exists with stock 0 and OUT status', () async {
      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );

      expect(stock, 0);

      // Verify no purchase record exists
      final purchases = await offline.queryDocuments(
        collection: FirebaseConstants.purchaseBills,
        filters: [],
        idToken: ownerToken,
      );
      expect(purchases, isEmpty);
    });

    test('Scenario 2: Increase stock directly is blocked without authorized transaction', () async {
      // Attempting to bypass workflows by directly requesting an adjustment without permissions
      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 10,
          isIncrease: true,
          transactionType: StockTransactionAuditModel.typeAdjustmentIn,
          reason: 'Direct injection attempt',
          userId: 'EMP-UNAUTHORIZED',
          token: ownerToken,
          permissions: [], // No permissions
          isOwner: false,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('permission'),
          ),
        ),
      );

      // Stock remains 0
      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 0);
    });

    test('Scenario 3: Decrease stock from 0 is strictly blocked', () async {
      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 5,
          isIncrease: false,
          transactionType: StockTransactionAuditModel.typeAdjustmentOut,
          reason: 'Reducing uninitialized stock',
          userId: 'OWNER-1',
          token: ownerToken,
          permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
          isOwner: true,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Stock cannot be reduced because the available quantity is 0.',
          ),
        ),
      );
    });

    test('Scenario 4: Opening stock of 10 units sets stock to 10 and prevents duplicates', () async {
      final audit = await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 10,
        reason: 'Initial physical count verification',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 85000,
        unit: 'KG',
      );

      expect(audit.newQuantity, 10);
      expect(audit.changedQuantity, 10);
      expect(audit.approvalStatus, StockTransactionAuditModel.statusPosted);

      // Balance now reflects 10
      final stockAfter = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stockAfter, 10);

      // Verify batch created
      final batches = await offline.queryDocuments(
        collection: FirebaseConstants.inventoryBatches,
        filters: [],
        idToken: ownerToken,
      );
      expect(batches.length, 1);
      final batchData = FirestoreRestService.decodeFields(batches.first['fields']);
      expect(batchData['availableQty'], 10);
      expect(batchData['batchId'], startsWith('BATCH_OP_'));

      // Attempt duplicate opening stock -> blocked
      expect(
        () => inventoryRepository.addOpeningStock(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 15,
          reason: 'Duplicate setup try',
          userId: 'OWNER-1',
          token: ownerToken,
          permissions: ['inventory.opening_stock'],
          isOwner: true,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Opening stock has already been initialized for this product at this outlet.',
          ),
        ),
      );
    });

    test('Scenario 5: Purchase draft of 20 units does not alter stock balance', () async {
      // Simulate creating a purchase draft bill
      await local.upsertRemote(FirebaseConstants.purchaseBills, [
        {
          'name': '${FirebaseConstants.purchaseBills}/BILL-DRAFT-01',
          'fields': FirestoreRestService.encodeFields({
            'billId': 'BILL-DRAFT-01',
            'tenantId': tenantId,
            'businessId': businessId,
            'outletId': outlet1,
            'purchaseType': 'DIRECT',
            'status': 'DRAFT',
            'items': [
              {
                'productId': productId,
                'variantId': variantId,
                'quantity': 20,
                'unitCost': 85000,
              }
            ],
          }),
        },
      ]);

      // Stock balance remains 0
      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 0);
    });

    test('Scenario 6: Receive purchase of 20 units increases stock by 20 exactly once', () async {
      // Post purchase receiving via inventory transaction
      final result = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 20,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typePurchaseReceipt,
        reason: 'Goods Receipt GRN-9988',
        sourceDocumentId: 'BILL-POSTED-01',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
        unitCostPaise: 85000,
      );

      expect(result.newQuantity, 20);
      expect(result.approvalStatus, StockTransactionAuditModel.statusPosted);

      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 20);
    });

    test('Scenario 7: Sell 5 units when available stock is 10 reduces balance to 5', () async {
      // Setup 10 units via opening stock
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 10,
        reason: 'Initial stock for sales test',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
      );

      // Post sale deduction of 5 units
      final saleResult = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 5,
        isIncrease: false,
        transactionType: StockTransactionAuditModel.typeSale,
        sourceDocumentId: 'INV-2026-001',
        reason: 'Retail POS Sale',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      expect(saleResult.newQuantity, 5);
      expect(saleResult.previousQuantity, 10);

      final remainingStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(remainingStock, 5);
    });

    test('Scenario 8: Decrease 15 units when available stock is 10 is blocked', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 10,
        reason: 'Initial 10 units',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
      );

      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 15,
          isIncrease: false,
          transactionType: StockTransactionAuditModel.typeAdjustmentOut,
          reason: 'Excessive adjustment',
          userId: 'OWNER-1',
          token: ownerToken,
          permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
          isOwner: true,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Insufficient available stock. Please check the quantity.',
          ),
        ),
      );

      // Stock remains intact at 10
      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 10);
    });

    test('Scenario 9: Unapproved adjustment leaves available stock unchanged until approved', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 10,
        reason: 'Initial baseline stock',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
      );

      // Employee with 'inventory.adjust' but WITHOUT 'inventory.approve_adjustment'
      final unapprovedTx = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 4,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Found surplus box in backroom',
        userId: 'EMP-1',
        token: ownerToken,
        permissions: ['inventory.adjust'], // lacking inventory.approve_adjustment
        isOwner: false,
      );

      expect(unapprovedTx.approvalStatus, StockTransactionAuditModel.statusPendingApproval);
      expect(unapprovedTx.isPendingApproval, isTrue);

      // Available stock balance must REMAIN 10 (unaltered while pending)
      final stockDuringPending = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stockDuringPending, 10);

      // Manager approves the adjustment
      final approvedTx = await inventoryRepository.approveAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        transactionId: unapprovedTx.transactionId,
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.approve_adjustment'],
        isOwner: true,
      );

      expect(approvedTx.approvalStatus, StockTransactionAuditModel.statusPosted);
      expect(approvedTx.isApproved, isTrue);

      // Now available stock balance reflects the addition: 10 + 4 = 14
      final stockAfterApproval = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stockAfterApproval, 14);
    });

    test('Scenario 10: Unauthorized employee adjustment is blocked by backend', () async {
      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 2,
          isIncrease: true,
          transactionType: StockTransactionAuditModel.typeAdjustmentIn,
          reason: 'Unauthorized stock change attempt',
          userId: 'EMP-2',
          token: ownerToken,
          permissions: ['inventory.view'], // missing inventory.adjust
          isOwner: false,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('permission'),
          ),
        ),
      );
    });

    test('Scenario 11: Duplicate offline sync posts transaction only once', () async {
      const fixedTxId = 'TX_OFFLINE_IDEMPOTENT_001';

      // Product must be initialized first (opening stock or purchase receipt)
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 10,
        reason: 'Initial physical count baseline',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 50000,
      );

      // First sync posting
      final firstResult = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 8,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Offline verified physical receipt',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
        transactionId: fixedTxId,
      );

      expect(firstResult.newQuantity, 18);

      final stock1 = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock1, 18);

      // Replay identical transaction (duplicate offline sync attempt)
      final duplicateResult = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 8,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Offline verified physical receipt',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
        transactionId: fixedTxId,
      );

      // Should return already-posted transaction without double-incrementing stock
      expect(duplicateResult.transactionId, fixedTxId);

      final stock2 = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock2, 18, reason: 'Duplicate sync must not increment balance a second time');
    });

    test('Scenario 12: Same product in different outlets maintains completely independent stock', () async {
      // Add opening stock of 10 to Outlet 1
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 10,
        reason: 'Outlet 1 inventory',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
      );

      // Check Outlet 2 stock before any action
      final outlet2StockInitial = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet2,
        variantId: variantId,
        token: ownerToken,
      );
      expect(outlet2StockInitial, 0, reason: 'Outlet 2 must start with 0 stock');

      // Add opening stock of 25 to Outlet 2
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet2,
        productId: productId,
        variantId: variantId,
        quantity: 25,
        reason: 'Outlet 2 inventory',
        userId: 'OWNER-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
      );

      // Verify complete independence
      final outlet1Final = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      final outlet2Final = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet2,
        variantId: variantId,
        token: ownerToken,
      );

      expect(outlet1Final, 10);
      expect(outlet2Final, 25);
    });

    test('Audit history tracks complete 17 fields accurately', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 12,
        reason: 'Audit verification test',
        userId: 'AUDITOR-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unit: 'KG',
        unitCostPaise: 75000,
      );

      final history = await inventoryRepository.getStockHistory(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );

      expect(history, isNotEmpty);
      final entry = history.first;
      expect(entry.tenantId, tenantId);
      expect(entry.businessId, businessId);
      expect(entry.outletId, outlet1);
      expect(entry.productId, productId);
      expect(entry.variantId, variantId);
      expect(entry.transactionType, StockTransactionAuditModel.typeOpeningStock);
      expect(entry.previousQuantity, 0);
      expect(entry.changedQuantity, 12);
      expect(entry.newQuantity, 12);
      expect(entry.unit, 'KG');
      expect(entry.reason, 'Audit verification test');
      expect(entry.performedBy, 'AUDITOR-1');
      expect(entry.approvalStatus, StockTransactionAuditModel.statusPosted);
      expect(entry.syncStatus, StockTransactionAuditModel.statusPendingSync);
    });
  });
}

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

  const tenantId = 'TENANT-PF-001';
  const businessId = 'BIZ-PF-001';
  const outlet1 = 'OUTLET-PF-A';
  const outlet2 = 'OUTLET-PF-B';
  const productId = 'PROD-PAINT-10L';
  const variantId = 'VAR-PAINT-10L-WHITE';

  final ownerToken = _token(uid: 'OWNER-PF-1');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('purchase-first-test-');
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
    await offline.activate('OWNER-PF-1');
    local = await offline.localDataSourceForToken(ownerToken);
    inventoryRepository = InventoryRepository(
      firestore: offline,
      transactions: offline,
    );

    // Seed master business, outlets, and catalog product
    await local.upsertRemote('businesses', [
      {
        'name': 'businesses/$businessId',
        'fields': FirestoreRestService.encodeFields({
          'businessId': businessId,
          'ownerUid': 'OWNER-PF-1',
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
          'name': 'Berger Paint WeatherCoat 10L',
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
          'name': '10L Brilliant White',
          'sellingPrice': 450000,
          'purchaseRate': 320000,
          'mrp': 480000,
          'reorderLevel': 10,
        }),
      },
    ]);
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  group('Purchase-First Inventory Rules Specification Tests', () {
    test('Scenario 1: Create new product exists with initial stock 0', () async {
      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 0);

      final isInitialized = await inventoryRepository.hasOpeningStockBeenInitialized(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(isInitialized, isFalse);
    });

    test('Scenario 2: New product manual adjustment +2 is strictly BLOCKED before valid stock initialization', () async {
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
          reason: 'Manual stock increase attempt without purchase or opening stock',
          userId: 'OWNER-PF-1',
          token: ownerToken,
          permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
          isOwner: true,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'This product has no received purchase or opening stock. Please receive a purchase or register existing inventory through Opening Stock.',
          ),
        ),
      );

      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 0);
    });

    test('Scenario 3: New product manual adjustment -2 is strictly BLOCKED', () async {
      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 2,
          isIncrease: false,
          transactionType: StockTransactionAuditModel.typeAdjustmentOut,
          reason: 'Manual stock decrease attempt on 0 stock',
          userId: 'OWNER-PF-1',
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

    test('Scenario 4: Existing shop inventory opening stock +500 initializes stock to 500 and creates batch & audit transaction', () async {
      final audit = await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 500,
        reason: 'Physical inventory baseline setup for Berger Paint 10L',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
        unit: 'Bucket',
      );

      expect(audit.newQuantity, 500);
      expect(audit.changedQuantity, 500);
      expect(audit.previousQuantity, 0);
      expect(audit.transactionType, StockTransactionAuditModel.typeOpeningStock);
      expect(audit.approvalStatus, StockTransactionAuditModel.statusPosted);

      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 500);

      // Verify FIFO batch creation
      final batches = await offline.queryDocuments(
        collection: FirebaseConstants.inventoryBatches,
        filters: [],
        idToken: ownerToken,
      );
      expect(batches, isNotEmpty);
      final batchData = FirestoreRestService.decodeFields(batches.first['fields']);
      expect(batchData['receivedQty'], 500);
      expect(batchData['availableQty'], 500);
      expect(batchData['unitCost'], 320000);
    });

    test('Scenario 5: Repeat opening stock +500 is BLOCKED (duplicate initialization prohibited)', () async {
      // First initialization
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 500,
        reason: 'Physical inventory baseline setup',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      // Duplicate attempt
      expect(
        () => inventoryRepository.addOpeningStock(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 500,
          reason: 'Duplicate physical inventory entry attempt',
          userId: 'OWNER-PF-1',
          token: ownerToken,
          permissions: ['inventory.opening_stock'],
          isOwner: true,
          unitCostPaise: 320000,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'Opening stock has already been initialized for this product at this outlet.',
          ),
        ),
      );

      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 500);
    });

    test('Scenario 6: Purchase draft of 100 units does NOT alter stock balance', () async {
      // Initialize opening stock 500
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 500,
        reason: 'Setup 500 units',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      // Save a purchase bill in DRAFT state
      await local.upsertRemote(FirebaseConstants.purchaseBills, [
        {
          'name': '${FirebaseConstants.purchaseBills}/BILL-DRAFT-100',
          'fields': FirestoreRestService.encodeFields({
            'billId': 'BILL-DRAFT-100',
            'tenantId': tenantId,
            'businessId': businessId,
            'outletId': outlet1,
            'status': 'DRAFT',
            'items': [
              {
                'productId': productId,
                'variantId': variantId,
                'quantity': 100,
              }
            ],
          }),
        },
      ]);

      // Verify stock balance remains exactly 500
      final stock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(stock, 500);
    });

    test('Scenario 7: Receive purchase of 100 units after opening stock 500 increases stock to 600', () async {
      // 1. Initial 500
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 500,
        reason: 'Setup 500 units',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      // 2. Confirmed goods receipt of 100 units
      final purchaseReceipt = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 100,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typePurchaseReceipt,
        sourceDocumentId: 'BILL-RCV-001',
        reason: 'Received vendor order 100 units',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
        unitCostPaise: 310000,
      );

      expect(purchaseReceipt.previousQuantity, 500);
      expect(purchaseReceipt.newQuantity, 600);

      final currentStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(currentStock, 600);
    });

    test('Scenario 8: Sell 50 units after stock 600 reduces balance to 550', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 500,
        reason: 'Opening 500',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 100,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typePurchaseReceipt,
        sourceDocumentId: 'BILL-RCV-001',
        reason: 'Received 100 units',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      // Retail POS Sale of 50 units
      final sale = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 50,
        isIncrease: false,
        transactionType: StockTransactionAuditModel.typeSale,
        sourceDocumentId: 'INV-2026-99',
        reason: 'Customer purchase',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      expect(sale.previousQuantity, 600);
      expect(sale.newQuantity, 550);

      final currentStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(currentStock, 550);
    });

    test('Scenario 9: Authorized adjustment +2 after initialization updates stock to 552', () async {
      // Starting from 550
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 550,
        reason: 'Baseline 550',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      // Authorized physical adjustment +2
      final adjustment = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 2,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Physical count found 2 unrecorded buckets in warehouse',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      expect(adjustment.previousQuantity, 550);
      expect(adjustment.newQuantity, 552);

      final currentStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(currentStock, 552);
    });

    test('Scenario 10: Reduce quantity beyond available stock is BLOCKED', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 552,
        reason: 'Baseline 552',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      // Attempt reducing 600 when available is 552
      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 600,
          isIncrease: false,
          transactionType: StockTransactionAuditModel.typeAdjustmentOut,
          reason: 'Excessive stock write-off',
          userId: 'OWNER-PF-1',
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
    });

    test('Scenario 11: Previously purchased product currently at zero remains initialized and allows authorized positive adjustment', () async {
      // 1. Initialized via purchase receipt of 20
      await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 20,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typePurchaseReceipt,
        reason: 'Initial purchase batch',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      // 2. All 20 units sold out
      await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 20,
        isIncrease: false,
        transactionType: StockTransactionAuditModel.typeSale,
        reason: 'Sold all inventory',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      final zeroStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(zeroStock, 0);

      // 3. Confirm product status remains INITIALIZED
      final isInit = await inventoryRepository.hasOpeningStockBeenInitialized(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(isInit, isTrue);

      // 4. Positive manual adjustment +2 on this zero-balance initialized product is ALLOWED
      final adj = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 2,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Found 2 unopened units in back storage',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      expect(adj.previousQuantity, 0);
      expect(adj.newQuantity, 2);

      final finalStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(finalStock, 2);
    });

    test('Scenario 12: Employee without inventory adjustment permission is BLOCKED', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 50,
        reason: 'Initial 50',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      expect(
        () => inventoryRepository.requestOrApplyAdjustment(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 5,
          isIncrease: true,
          transactionType: StockTransactionAuditModel.typeAdjustmentIn,
          reason: 'Unauthorized stock shift',
          userId: 'EMP-READ-ONLY',
          token: ownerToken,
          permissions: ['inventory.view'], // Lacks inventory.adjust
          isOwner: false,
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            'You do not have permission to adjust stock.',
          ),
        ),
      );
    });

    test('Scenario 13: Duplicate offline synchronization posts transaction only once (idempotent)', () async {
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 100,
        reason: 'Initial 100',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      const fixedTxId = 'TX_OFFLINE_IDEMPOTENT_99';

      // First sync
      final firstSync = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 15,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Offline verified adjustment',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
        transactionId: fixedTxId,
      );

      expect(firstSync.newQuantity, 115);

      // Repeated sync with identical transactionId
      final secondSync = await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 15,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Duplicate sync retry',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
        transactionId: fixedTxId,
      );

      // Transaction is idempotent and returns identical recorded audit without mutating balance
      expect(secondSync.transactionId, fixedTxId);
      final finalStock = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      expect(finalStock, 115);
    });

    test('Scenario 14: Same product in different outlets maintains independent stock balances', () async {
      // Initialize Outlet A with 500
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 500,
        reason: 'Outlet A baseline',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      // Initialize Outlet B with 200
      await inventoryRepository.addOpeningStock(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet2,
        productId: productId,
        variantId: variantId,
        quantity: 200,
        reason: 'Outlet B baseline',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.opening_stock'],
        isOwner: true,
        unitCostPaise: 320000,
      );

      final stockA = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet1,
        variantId: variantId,
        token: ownerToken,
      );
      final stockB = await inventoryRepository.getAvailableStock(
        tenantId: tenantId,
        outletId: outlet2,
        variantId: variantId,
        token: ownerToken,
      );

      expect(stockA, 500);
      expect(stockB, 200);

      // Adjust Outlet A only
      await inventoryRepository.requestOrApplyAdjustment(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outlet1,
        productId: productId,
        variantId: variantId,
        quantity: 50,
        isIncrease: true,
        transactionType: StockTransactionAuditModel.typeAdjustmentIn,
        reason: 'Outlet A replenishment',
        userId: 'OWNER-PF-1',
        token: ownerToken,
        permissions: ['inventory.adjust', 'inventory.approve_adjustment'],
        isOwner: true,
      );

      expect(
        await inventoryRepository.getAvailableStock(
          tenantId: tenantId,
          outletId: outlet1,
          variantId: variantId,
          token: ownerToken,
        ),
        550,
      );
      expect(
        await inventoryRepository.getAvailableStock(
          tenantId: tenantId,
          outletId: outlet2,
          variantId: variantId,
          token: ownerToken,
        ),
        200,
      );
    });

    test('Scenario 15: Unit Purchase Cost is strictly enforced on Opening Stock', () async {
      expect(
        () => inventoryRepository.addOpeningStock(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outlet1,
          productId: productId,
          variantId: variantId,
          quantity: 10,
          reason: 'Missing cost test',
          userId: 'OWNER-PF-1',
          token: ownerToken,
          permissions: ['inventory.opening_stock'],
          isOwner: true,
          unitCostPaise: -50,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}

import 'support/synthetic_face_verification.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/sales_invoice_model.dart';
import 'package:testflutter/data/repositories/sales_repository.dart';
import 'package:testflutter/data/repositories/staff_attendance_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

class _OfflineConnectivity extends ConnectivityService {
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

String _token() {
  final claims = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'sub': 'sales-posting-test',
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
  late SalesRepository repository;
  late Future<void> Function() seedBase;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sales-posting-');
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
    await offline.activate('sales-posting-test');
    local = await offline.localDataSourceForToken(_token());
    repository = SalesRepository(offline);
    await seedBase();
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> put(
    String collection,
    String id,
    Map<String, dynamic> fields,
  ) async {
    await local.upsertRemote(collection, [
      {
        'name': '$collection/$id',
        'fields': FirestoreRestService.encodeFields(fields),
      },
    ]);
  }

  seedBase = () async {
    await put('businesses', 'BUS-1', {
      'businessId': 'BUS-1',
      'ownerUid': 'TEN-1',
      'tenantId': 'TEN-1',
      'status': 'ACTIVE',
      'isActive': true,
    });
    await put('outlets', 'OUT-1', {
      'outletId': 'OUT-1',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'status': 'ACTIVE',
      'isActive': true,
      'gstState': '27',
    });
    await put('employees', 'EMP-1', {
      'employeeId': 'EMP-1',
      'ownerUid': 'TEN-1',
      'tenantId': 'TEN-1',
      'businessIds': ['BUS-1'],
      'outletIds': ['OUT-1'],
      'status': 'ACTIVE',
    });
    await put('products', 'PROD-1', {
      'productId': 'PROD-1',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'status': 'ACTIVE',
    });
    await put('product_variants', 'VAR-1', {
      'variantId': 'VAR-1',
      'productId': 'PROD-1',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'status': 'ACTIVE',
      'defaultGstRateBps': 0,
      'baseQuantityPerCommercialUnit': 10,
      'baseUnitId': 'BASE-UNIT',
      'commercialUnitId': 'BUCKET',
    });
    await put('outlet_products', 'PLACEMENT-1', {
      'placementId': 'PLACEMENT-1',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'outletId': 'OUT-1',
      'productId': 'PROD-1',
      'variantIds': ['VAR-1'],
      'status': 'ACTIVE',
      'isActive': true,
    });
    await put('stock_balances', 'TEN-1_OUT-1_VAR-1', {
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'outletId': 'OUT-1',
      'variantId': 'VAR-1',
      'quantityOnHand': 10,
      'totalValue': 1000,
      'averageCost': 100000,
    });
    for (final (id, quantity) in [('BATCH-A', 6), ('BATCH-B', 4)]) {
      await put('inventory_batches', id, {
        'batchId': id,
        'tenantId': 'TEN-1',
        'businessId': 'BUS-1',
        'outletId': 'OUT-1',
        'productId': 'PROD-1',
        'variantId': 'VAR-1',
        'receivedQty': quantity,
        'availableQty': quantity,
        'internalBatchNo': 'BAT-$id',
        'status': 'AVAILABLE',
        'storageType': 'OUTLET',
        'storageLocationId': 'OUT-1',
      });
      await put('inventory_batch_movements', 'RECEIPT-$id', {
        'movementId': 'RECEIPT-$id',
        'tenantId': 'TEN-1',
        'businessId': 'BUS-1',
        'outletId': 'OUT-1',
        'batchId': id,
        'productId': 'PROD-1',
        'variantId': 'VAR-1',
        'movementType': 'PURCHASE_RECEIPT',
        'quantity': quantity,
        'direction': 'IN',
        'referenceType': 'GOODS_RECEIPT',
        'referenceId': 'GRN-1',
        'status': 'POSTED',
        'isDeleted': false,
      });
    }
  };

  SalesInvoiceLine makeLine(List<SalesBatchAllocation> allocations) =>
      SalesInvoiceLine(
        invoiceLineId: 'LINE-1',
        productId: 'PROD-1',
        variantId: 'VAR-1',
        productName: 'Paint',
        variantName: '10 Litre',
        quantity: 1,
        baseUnitId: 'BASE-UNIT',
        commercialUnitId: 'BUCKET',
        conversionFactor: 10000,
        baseQuantity: 10,
        unitPrice: 5000,
        mrp: 6000,
        gstPercent: 0,
        taxableAmount: 5000,
        lineTotal: 5000,
        batchAllocations: allocations,
      );

  Future<String> post(
    String invoiceId,
    List<SalesBatchAllocation> allocations, {
    String? employeeId,
  }) => repository.postInvoice(
    invoiceId: invoiceId,
    tenantId: 'TEN-1',
    businessId: 'BUS-1',
    outletId: 'OUT-1',
    actorUid: 'USER-1',
    invoiceDate: DateTime.utc(2026, 10, 14),
    customerId: null,
    customerName: null,
    chargeToEmployeeId: employeeId,
    lines: [makeLine(allocations)],
    token: _token(),
  );

  test('staff khata invoice links employee and posts one receivable without bypassing stock', () async {
    await post('INV-STAFF-1', [
      const SalesBatchAllocation(batchId: 'BATCH-A', baseQuantity: 6),
      const SalesBatchAllocation(batchId: 'BATCH-B', baseQuantity: 4),
    ], employeeId: 'EMP-1');
    final invoice = FirestoreRestService.decodeFields(
      jsonDecode(
        (await local.row('invoices', 'INV-STAFF-1'))!['payloadJson'] as String,
      ),
    );
    expect(invoice['employeeId'], 'EMP-1');
    expect(invoice['chargeType'], 'STAFF_KHATA');
    expect(invoice['paymentStatus'], 'UNPAID');
    final event = await local.row(
      'staff_khata_transactions',
      'SKH-POS-INV-STAFF-1',
    );
    expect(event, isNotNull);
    expect(
      FirestoreRestService.decodeFields(
        jsonDecode(event!['payloadJson'] as String),
      )['amountPaise'],
      5000,
    );
    expect(
      await local.db.query(
        'sync_outbox',
        where: "entityType='staff_khata_transactions'",
      ),
      hasLength(1),
    );
    await post('INV-STAFF-1', [
      const SalesBatchAllocation(batchId: 'BATCH-A', baseQuantity: 6),
      const SalesBatchAllocation(batchId: 'BATCH-B', baseQuantity: 4),
    ], employeeId: 'EMP-1');
    expect(
      await local.db.query(
        'sync_outbox',
        where: "entityType='staff_khata_transactions'",
      ),
      hasLength(1),
    );
  });

  test('face kiosk attendance events persist in SQLite with outbox records offline', () async {
    await put('employees', 'EMP-ATT', {
      'employeeId': 'EMP-ATT',
      'ownerUid': 'TEN-1',
      'businessIds': ['BUS-1'],
      'outletIds': ['OUT-1'],
      'status': 'ACTIVE',
    });
    var eventClock = DateTime.utc(2026, 10, 15, 9);
    final attendance = StaffAttendanceRepository(
      offline,
      offline,
      clock: () => eventClock,
    );
    final workDate = DateTime.utc(2026, 10, 15);
    final id = await attendance.recordFaceCheckIn(
      verification: await syntheticFaceVerification(
        at: DateTime.utc(2026, 10, 15, 9),
        tenantId: 'TEN-1',
        businessId: 'BUS-1',
        outletId: 'OUT-1',
        employeeId: 'EMP-ATT',
        deviceId: 'KIOSK-OFFLINE-1',
        modelVersion: 'EMULATOR-FIXTURE',
        livenessVersion: 'EMULATOR-FIXTURE',
      ),
      tenantId: 'TEN-1',
      businessId: 'BUS-1',
      outletId: 'OUT-1',
      employeeId: 'EMP-ATT',
      workDate: workDate,
      occurredAt: DateTime.utc(2026, 10, 15, 9),
      timeZoneId: 'Asia/Kolkata',
      kioskDeviceId: 'KIOSK-OFFLINE-1',
      modelVersion: 'EMULATOR-FIXTURE',
      livenessVersion: 'EMULATOR-FIXTURE',
      recordedBy: 'OWNER',
      token: _token(),
    );
    eventClock = DateTime.utc(2026, 10, 15, 17);
    await attendance.recordFaceCheckOut(
      verification: await syntheticFaceVerification(
        at: DateTime.utc(2026, 10, 15, 17),
        tenantId: 'TEN-1',
        businessId: 'BUS-1',
        outletId: 'OUT-1',
        employeeId: 'EMP-ATT',
        deviceId: 'KIOSK-OFFLINE-1',
        modelVersion: 'EMULATOR-FIXTURE',
        livenessVersion: 'EMULATOR-FIXTURE',
      ),
      tenantId: 'TEN-1',
      businessId: 'BUS-1',
      outletId: 'OUT-1',
      employeeId: 'EMP-ATT',
      workDate: workDate,
      occurredAt: DateTime.utc(2026, 10, 15, 17),
      timeZoneId: 'Asia/Kolkata',
      kioskDeviceId: 'KIOSK-OFFLINE-1',
      modelVersion: 'EMULATOR-FIXTURE',
      livenessVersion: 'EMULATOR-FIXTURE',
      recordedBy: 'OWNER',
      token: _token(),
    );
    final row = await local.row('staff_attendance', id);
    expect(row, isNotNull);
    expect(row!['syncStatus'], 'PENDING_CREATE');
    final daily = FirestoreRestService.decodeFields(
      jsonDecode(row['payloadJson'] as String),
    );
    expect(daily['workedMinutes'], 480);
    expect(daily['approvalStatus'], 'PENDING');
    final events = await local.query('staff_attendance_events', const []);
    expect(events, hasLength(2));
    for (final event in events) {
      final fields = FirestoreRestService.decodeFields(event['fields']);
      expect(fields['immutable'], isTrue);
      expect(
        fields.keys.any(
          (key) => RegExp(
            'embedding|template|image|photo|similarity|consent',
            caseSensitive: false,
          ).hasMatch(key),
        ),
        isFalse,
      );
    }
    expect(
      events.map((doc) => doc['localSyncStatus']),
      everyElement('PENDING_CREATE'),
    );
    expect(
      await local.db.query(
        'sync_outbox',
        where: 'entityType=?',
        whereArgs: ['staff_attendance_events'],
      ),
      hasLength(2),
    );
  });

  test(
    'manual allocation posts invoice, SALE movements and stock atomically',
    () async {
      expect(
        await post('INV-RETRY-1', [
          const SalesBatchAllocation(batchId: 'BATCH-A', baseQuantity: 6),
          const SalesBatchAllocation(batchId: 'BATCH-B', baseQuantity: 4),
        ]),
        'INV-RETRY-1',
      );

      final invoice = await local.row('invoices', 'INV-RETRY-1');
      final invoiceFields = FirestoreRestService.decodeFields(
        jsonDecode(invoice!['payloadJson'] as String),
      );
      final items = invoiceFields['items'] as List;
      expect((items.single as Map)['batchAllocations'], [
        {'batchId': 'BATCH-A', 'baseQuantity': 6},
        {'batchId': 'BATCH-B', 'baseQuantity': 4},
      ]);
      final movements = await local.query(
        'inventory_batch_movements',
        const [],
      );
      final sales = movements
          .map((doc) => FirestoreRestService.decodeFields(doc['fields']))
          .where((fields) => fields['movementType'] == 'SALE')
          .toList();
      expect(sales, hasLength(2));
      expect(
        sales.fold<int>(
          0,
          (sum, row) => sum + (row['quantity'] as num).toInt(),
        ),
        10,
      );
      final stock = await local.row('stock_balances', 'TEN-1_OUT-1_VAR-1');
      expect(
        FirestoreRestService.decodeFields(
          jsonDecode(stock!['payloadJson'] as String),
        )['quantityOnHand'],
        0,
      );
      final outbox = await local.db.query(
        'sync_outbox',
        where: 'documentId=? OR entityType=?',
        whereArgs: ['INV-RETRY-1', 'inventory_batch_movements'],
      );
      expect(outbox, isNotEmpty);
      expect(outbox.map((row) => row['batchId']).toSet(), hasLength(1));

      await post('INV-RETRY-1', [
        const SalesBatchAllocation(batchId: 'BATCH-A', baseQuantity: 6),
        const SalesBatchAllocation(batchId: 'BATCH-B', baseQuantity: 4),
      ]);
      final afterRetry = await local.row('stock_balances', 'TEN-1_OUT-1_VAR-1');
      expect(
        FirestoreRestService.decodeFields(
          jsonDecode(afterRetry!['payloadJson'] as String),
        )['quantityOnHand'],
        0,
      );
      expect(
        (await local.query('inventory_batch_movements', const [])).where((doc) {
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          return fields['movementType'] == 'SALE';
        }),
        hasLength(2),
      );
    },
  );

  test(
    'under-allocation and legacy batches are rejected without writes',
    () async {
      await expectLater(
        post('INV-UNDER', [
          const SalesBatchAllocation(batchId: 'BATCH-A', baseQuantity: 9),
        ]),
        throwsA(isA<Exception>()),
      );
      await put('inventory_batches', 'LEGACY', {
        'batchId': 'LEGACY',
        'tenantId': 'TEN-1',
        'businessId': 'BUS-1',
        'outletId': 'OUT-1',
        'productId': 'PROD-1',
        'variantId': 'VAR-1',
        'receivedQty': 10,
        'availableQty': 10,
        'status': 'AVAILABLE',
      });
      await expectLater(
        post('INV-LEGACY', [
          const SalesBatchAllocation(batchId: 'LEGACY', baseQuantity: 10),
        ]),
        throwsA(isA<Exception>()),
      );
      expect(await local.row('invoices', 'INV-UNDER'), isNull);
      expect(await local.row('invoices', 'INV-LEGACY'), isNull);
      expect(await local.db.query('sync_outbox'), isEmpty);
    },
  );

  test('ledger availability and exact batch scope are enforced', () async {
    await put('inventory_batch_movements', 'PRIOR-OUT-B', {
      'movementId': 'PRIOR-OUT-B',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'outletId': 'OUT-1',
      'batchId': 'BATCH-B',
      'productId': 'PROD-1',
      'variantId': 'VAR-1',
      'movementType': 'SALE',
      'quantity': 3,
      'direction': 'OUT',
      'referenceType': 'INVOICE',
      'referenceId': 'OLD-INVOICE',
      'status': 'POSTED',
      'isDeleted': false,
    });
    await put('inventory_batches', 'BATCH-B', {
      'batchId': 'BATCH-B',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'outletId': 'OUT-1',
      'productId': 'PROD-1',
      'variantId': 'VAR-1',
      'receivedQty': 4,
      'availableQty': 1,
      'internalBatchNo': 'BAT-BATCH-B',
      'status': 'AVAILABLE',
    });
    await expectLater(
      post('INV-INSUFFICIENT-BATCH', [
        const SalesBatchAllocation(batchId: 'BATCH-A', baseQuantity: 6),
        const SalesBatchAllocation(batchId: 'BATCH-B', baseQuantity: 4),
      ]),
      throwsA(isA<Exception>()),
    );

    await put('inventory_batches', 'WRONG-OUTLET', {
      'batchId': 'WRONG-OUTLET',
      'tenantId': 'TEN-1',
      'businessId': 'BUS-1',
      'outletId': 'OUT-2',
      'productId': 'PROD-1',
      'variantId': 'VAR-1',
      'receivedQty': 10,
      'availableQty': 10,
      'internalBatchNo': 'BAT-OTHER',
      'status': 'AVAILABLE',
    });
    await expectLater(
      post('INV-WRONG-OUTLET', [
        const SalesBatchAllocation(batchId: 'WRONG-OUTLET', baseQuantity: 10),
      ]),
      throwsA(isA<Exception>()),
    );
    expect(await local.row('invoices', 'INV-INSUFFICIENT-BATCH'), isNull);
    expect(await local.row('invoices', 'INV-WRONG-OUTLET'), isNull);
  });
}

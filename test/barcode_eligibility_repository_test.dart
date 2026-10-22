import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/auth_session_model.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

class _OfflineConnectivity extends ConnectivityService {
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

String _token() {
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode({
        'sub': 'barcode-test-user',
        'aud': EnvironmentConfig.projectId,
        'exp':
            DateTime.now()
                .add(const Duration(days: 1))
                .millisecondsSinceEpoch ~/
            1000,
      }),
    ),
  );
  return 'header.$payload.signature';
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late LocalDatabase database;
  late OfflineFirestoreService offline;
  late SyncEngine sync;
  late ProductRepository repository;
  late LocalDataSource local;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('barcode-eligibility-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    final remote = FirestoreRestService(ApiClient());
    sync = SyncEngine(
      remote,
      _OfflineConnectivity(),
      sessionProvider: () async => AuthSession(
        idToken: _token(),
        refreshToken: '',
        uid: 'barcode-test-user',
        email: 'test@example.com',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      ),
    );
    offline = OfflineFirestoreService(database, remote, sync);
    await offline.activate('barcode-test-user');
    local = await offline.localDataSourceForToken(_token());
    repository = ProductRepository(offline, offline);
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> addBatch({
    required String id,
    required String variantId,
    required int receivedQty,
    required String status,
    String outletId = 'OUT-1',
  }) async {
    await local.upsertRemote('inventory_batches', [
      {
        'name': 'inventory_batches/$id',
        'fields': FirestoreRestService.encodeFields({
          'tenantId': 'TEN-1',
          'businessId': 'BUS-1',
          'outletId': outletId,
          'variantId': variantId,
          'receivedQty': receivedQty,
          'availableQty': 0,
          'status': status,
          'isDeleted': false,
        }),
      },
    ]);
  }

  Future<bool> eligible(String variantId, {String outletId = 'OUT-1'}) =>
      repository.variantHasReceivedInventory(
        token: _token(),
        tenantId: 'TEN-1',
        businessId: 'BUS-1',
        outletId: outletId,
        variantId: variantId,
      );

  test(
    'receipt evidence is exact variant/scope and independent of stock',
    () async {
      await addBatch(
        id: 'batch-a',
        variantId: 'VAR-RECEIVED',
        receivedQty: 8,
        status: 'AVAILABLE',
      );
      expect(await eligible('VAR-RECEIVED'), isTrue);
      expect(await eligible('VAR-OTHER'), isFalse);
      expect(await eligible('VAR-RECEIVED', outletId: 'OUT-OTHER'), isFalse);
    },
  );

  test('draft and zero-quantity batches do not prove receipt', () async {
    await addBatch(
      id: 'draft',
      variantId: 'VAR-DRAFT',
      receivedQty: 0,
      status: 'PENDING_RECEIPT',
    );
    expect(await eligible('VAR-DRAFT'), isFalse);
  });
}

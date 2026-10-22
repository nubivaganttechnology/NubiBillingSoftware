import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/data/sync/sync_outbox_repository.dart';

import 'offline_sync_test.dart'
    show FakeRemote, TestConnectivity, session, token;

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalDatabase database;
  late FakeRemote remote;
  late ConnectivityService connectivity;
  late SyncEngine sync;
  late OfflineFirestoreService service;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nubibill-phase10k-sync-');
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    remote = FakeRemote();
    connectivity = TestConnectivity();
    sync = SyncEngine(
      remote,
      connectivity,
      sessionProvider: () async => session('U'),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    await service.setScope(tenant: 'T', business: 'B');
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<LocalDataSource> local() async =>
      LocalDataSource(await database.open('', 'U'));

  Future<void> seedLocal(
    String collection,
    String id,
    Map<String, dynamic> fields,
  ) async {
    remote.seed(collection, id, fields);
    await (await local()).upsertRemote(collection, [
      remote.docs['$collection/$id']!,
    ]);
  }

  test('historical inactive query errors do not show Sync error', () async {
    final src = await local();

    // Insert an inactive query with a historical 429 quota error
    await src.db.insert('sync_queries', {
      'queryKey': 'QRY-INACTIVE-429',
      'collectionName': 'products',
      'queryJson': '{"filters":[]}',
      'lastSyncedAt': '2026-10-02T00:00:00Z',
      'active': 0, // Inactive query!
      'lastAttemptAt': '2026-10-02T00:00:00Z',
      'lastError': 'RESOURCE_EXHAUSTED: Quota exceeded (HTTP 429)',
    });

    connectivity.available = true;
    await sync.sync();

    // Verify sync state is synced, error is null
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);
  });

  test('successful outbox drain returns header state to Synced', () async {
    final src = await local();
    connectivity.available = false;

    // Enqueue document offline
    await service.createDocument('products', 'PROD-DRAIN', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Test Drain',
    }, idToken: token('U'));

    expect(await SyncOutboxRepository(src).pendingCount(), 1);
    expect(sync.state, SyncState.offline);

    // Reconnect and sync
    connectivity.available = true;
    await sync.sync();

    expect(await SyncOutboxRepository(src).pendingCount(), 0);
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);
  });

  test('stale failed mutation already satisfied remotely can be safely cleared', () async {
    final src = await local();

    // 1. Seed product locally and remotely as active
    await seedLocal('products', 'PROD-ALREADY-ACTIVE', {
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
      'isDeleted': false,
      'name': 'Already Active Product',
      'updatedBy': 'remote-user',
    });

    // 2. Perform a local update offline
    connectivity.available = false;
    await service.updateDocument('products', 'PROD-ALREADY-ACTIVE', {
      'status': 'ACTIVE',
      'isDeleted': false,
    }, idToken: token('U'));

    // 3. Mark the outbox row as FAILED (simulating a previous conflict error)
    await src.db.update('sync_outbox', {
      'status': 'FAILED',
      'attemptCount': 5,
      'lastError': 'Remote version changed. Local data retained.',
    }, where: "documentId = 'PROD-ALREADY-ACTIVE'");

    // 4. Remote is already active with newer remote updateTime
    remote.seed('products', 'PROD-ALREADY-ACTIVE', {
      'tenantId': 'T',
      'businessId': 'B',
      'status': 'ACTIVE',
      'isDeleted': false,
      'name': 'Already Active Product',
      'updatedBy': 'remote-user',
    });

    connectivity.available = true;
    await sync.sync();

    // Outbox item should be cleared as satisfied
    expect(await SyncOutboxRepository(src).pendingCount(), 0);
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);

    // Remote document should NOT have been overwritten with stale data
    final remoteDoc = remote.docs['products/PROD-ALREADY-ACTIVE']!;
    final fields = FirestoreRestService.decodeFields(remoteDoc['fields']);
    expect(fields['status'], 'ACTIVE');
    expect(fields['isDeleted'], isFalse);
    expect(fields['updatedBy'], 'remote-user');
  });

  test('rebased restore preserves unrelated remote fields', () async {
    // 1. Seed initial active document locally and remotely
    await seedLocal('products', 'PROD-RESTORE-ME', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Silk Breathe Easy',
      'description': 'Keep this description intact',
      'category': 'Paints',
      'status': 'ACTIVE',
      'isDeleted': false,
      'updatedBy': 'creator',
    });

    // 2. Remotely soft-delete the document
    remote.seed('products', 'PROD-RESTORE-ME', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Silk Breathe Easy',
      'description': 'Keep this description intact',
      'category': 'Paints',
      'status': 'DELETED',
      'isDeleted': true,
      'updatedBy': 'deleter',
    });

    // 3. Offline restore locally
    connectivity.available = false;
    await service.updateDocument('products', 'PROD-RESTORE-ME', {
      'status': 'ACTIVE',
      'isDeleted': false,
      'updatedBy': 'restorer',
    }, idToken: token('U'));

    // 4. Reconnect and sync
    connectivity.available = true;
    await sync.sync();

    final src = await local();
    expect(await SyncOutboxRepository(src).pendingCount(), 0);
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);

    // Remote document should now be ACTIVE and preserve unrelated fields
    final remoteDoc = remote.docs['products/PROD-RESTORE-ME']!;
    final fields = FirestoreRestService.decodeFields(remoteDoc['fields']);
    expect(fields['status'], 'ACTIVE');
    expect(fields['isDeleted'], isFalse);
    expect(fields['description'], 'Keep this description intact');
    expect(fields['category'], 'Paints');
    expect(fields['updatedBy'], 'restorer');
  });

  test('outlet_products conflict resolution never mutates products', () async {
    // 1. Seed product master
    await seedLocal('products', 'PROD-MASTER-1', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Master Product 1',
      'status': 'ACTIVE',
      'isDeleted': false,
    });
    final productInitialVersion = remote.docs['products/PROD-MASTER-1']!['updateTime'];

    // 2. Seed placement
    await seedLocal('outlet_products', 'OP-DEACTIVATE', {
      'tenantId': 'T',
      'businessId': 'B',
      'outletId': 'OUT-001',
      'productId': 'PROD-MASTER-1',
      'status': 'ACTIVE',
      'isActive': true,
    });

    // 3. Offline deactivate placement
    connectivity.available = false;
    await service.updateDocument('outlet_products', 'OP-DEACTIVATE', {
      'status': 'INACTIVE',
      'isActive': false,
      'updatedBy': 'tester',
    }, idToken: token('U'));

    connectivity.available = true;
    await sync.sync();

    final src = await local();
    expect(await SyncOutboxRepository(src).pendingCount(), 0);
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);

    // Outlet product was deactivated
    final opFields = FirestoreRestService.decodeFields(
      remote.docs['outlet_products/OP-DEACTIVATE']!['fields'],
    );
    expect(opFields['status'], 'INACTIVE');
    expect(opFields['isActive'], isFalse);

    // Master product was completely untouched!
    expect(remote.docs['products/PROD-MASTER-1']!['updateTime'], productInitialVersion);
    final prodFields = FirestoreRestService.decodeFields(
      remote.docs['products/PROD-MASTER-1']!['fields'],
    );
    expect(prodFields['status'], 'ACTIVE');
    expect(prodFields['isDeleted'], isFalse);
    expect(prodFields['name'], 'Master Product 1');
  });
}

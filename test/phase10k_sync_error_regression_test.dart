import 'dart:convert';
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

    expect((await src.db.query('sync_outbox')).length, 1);
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

  test('stale failed attendance approval already approved remotely is resolved idempotently', () async {
    final src = await local();

    // 1. Seed attendance locally with morning check-in
    await seedLocal('staff_attendance', 'ATT-IDEMPOTENT-1', {
      'tenantId': 'T',
      'businessId': 'B',
      'outletId': 'O',
      'employeeId': 'EMP-1',
      'attendanceStatus': 'PRESENT',
      'approvalStatus': 'PENDING',
      'checkInAt': '2026-10-21T06:49:07.581022Z',
      'workedMinutes': 0,
      'approvedOvertimeMinutes': 0,
    });

    // 2. Remotely, the employee checked out and the record was approved
    remote.seed('staff_attendance', 'ATT-IDEMPOTENT-1', {
      'tenantId': 'T',
      'businessId': 'B',
      'outletId': 'O',
      'employeeId': 'EMP-1',
      'attendanceStatus': 'PRESENT',
      'approvalStatus': 'APPROVED',
      'approvedBy': 'manager-uid',
      'approvedAt': '2026-10-21T14:55:59.833891Z',
      'checkInAt': '2026-10-21T06:49:07.581022Z',
      'checkOutAt': '2026-10-21T14:55:39.328262Z',
      'workedMinutes': 486,
      'approvedOvertimeMinutes': 6,
    });

    // 3. Local offline mutation tries to approve
    connectivity.available = false;
    await service.updateDocument('staff_attendance', 'ATT-IDEMPOTENT-1', {
      'approvalStatus': 'APPROVED',
      'approvedBy': 'manager-uid',
      'approvedAt': '2026-10-22T05:03:40.447284Z',
      'approvedOvertimeMinutes': 0,
      'workedMinutes': 0,
    }, idToken: token('U'));

    // 4. Mark outbox row as FAILED with remote version changed
    await src.db.update('sync_outbox', {
      'status': 'FAILED',
      'attemptCount': 5,
      'lastError': 'Remote version changed for staff_attendance/ATT-IDEMPOTENT-1. Local data retained.',
    }, where: "documentId = 'ATT-IDEMPOTENT-1'");

    // 5. Reconnect and sync
    connectivity.available = true;
    await sync.sync();

    // Outbox should be cleanly resolved as already satisfied
    expect(await SyncOutboxRepository(src).pendingCount(), 0);
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);

    // Local SQLite database should be updated to match remote approved document
    final localRow = await src.row('staff_attendance', 'ATT-IDEMPOTENT-1');
    expect(localRow, isNotNull);
    expect(localRow!['syncStatus'], 'SYNCED');
    expect(localRow['syncError'], isNull);
    final localFields = FirestoreRestService.decodeFields(
      jsonDecode(localRow['payloadJson'] as String) as Map<String, dynamic>,
    );
    expect(localFields['approvalStatus'], 'APPROVED');
    expect(localFields['workedMinutes'], 486);
    expect(localFields['approvedOvertimeMinutes'], 6);
  });

  test('resolveConflictedOutbox discards failed conflict and reconciles to remote document', () async {
    final src = await local();

    // 1. Seed document locally and remotely
    await seedLocal('customers', 'CUST-CONFLICT-1', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Original Name',
      'phone': '1234567890',
    });

    // 2. Remotely update the document
    remote.seed('customers', 'CUST-CONFLICT-1', {
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Remote Updated Name',
      'phone': '1234567890',
    });

    // 3. Offline local update
    connectivity.available = false;
    await service.updateDocument('customers', 'CUST-CONFLICT-1', {
      'name': 'Local Conflicted Name',
    }, idToken: token('U'));

    // 4. Mark as FAILED conflict
    await src.db.update('sync_outbox', {
      'status': 'FAILED',
      'attemptCount': 5,
      'lastError': 'Remote version changed for customers/CUST-CONFLICT-1. Local data retained.',
    }, where: "documentId = 'CUST-CONFLICT-1'");

    expect((await src.db.query('sync_outbox')).length, 1);

    // 5. User accepts remote data to resolve conflict
    connectivity.available = true;
    await sync.resolveConflictedOutbox();

    expect(await SyncOutboxRepository(src).pendingCount(), 0);
    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);

    final localRow = await src.row('customers', 'CUST-CONFLICT-1');
    expect(localRow, isNotNull);
    expect(localRow!['syncStatus'], 'SYNCED');
    final localFields = FirestoreRestService.decodeFields(
      jsonDecode(localRow['payloadJson'] as String) as Map<String, dynamic>,
    );
    expect(localFields['name'], 'Remote Updated Name');
  });
}


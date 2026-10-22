import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/constants/firebase_constants.dart';
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
    dir = await Directory.systemTemp.createTemp('nubibill-multibatch-');
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
    await service.setScope(tenant: 'T', business: 'BUS-001');
  });

  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });

  Future<LocalDataSource> local() async =>
      LocalDataSource(await database.open('', 'U'));

  test('multiple offline batches rebase successively past remote sequence', () async {
    // 1. Seed sequence in remote Firestore: sequence is 3 (invoices 1, 2, 3 already exist remotely)
    remote.seed(FirebaseConstants.documentSequences, 'BUS-001_26_SALES_INVOICE', {
      'businessId': 'BUS-001',
      'financialYear': '26',
      'sequenceType': 'SALES_INVOICE',
      'sequence': 3,
    });

    // 2. Go offline
    connectivity.available = false;

    // 3. Batch 1: create invoice SUMANE-26-00001 offline
    await service.runAtomicOperation((tx) async {
      tx.create(FirebaseConstants.invoices, 'REQ_1', {
        'invoiceNumber': 'SUMANE-26-00001',
        'tenantId': 'T',
        'businessId': 'BUS-001',
      });
      tx.create(FirebaseConstants.documentSequences, 'BUS-001_26_SALES_INVOICE', {
        'businessId': 'BUS-001',
        'financialYear': '26',
        'sequenceType': 'SALES_INVOICE',
        'sequence': 1,
      });
    }, idToken: token('U'));

    // 4. Batch 2: create invoice SUMANE-26-00002 offline (pending read on sequence)
    await service.runAtomicOperation((tx) async {
      final seq = await tx.get(FirebaseConstants.documentSequences, 'BUS-001_26_SALES_INVOICE');
      expect(seq.exists, isTrue);

      tx.create(FirebaseConstants.invoices, 'REQ_2', {
        'invoiceNumber': 'SUMANE-26-00002',
        'tenantId': 'T',
        'businessId': 'BUS-001',
      });
      tx.update(FirebaseConstants.documentSequences, 'BUS-001_26_SALES_INVOICE', {
        'businessId': 'BUS-001',
        'financialYear': '26',
        'sequenceType': 'SALES_INVOICE',
        'sequence': 2,
      }, updateTime: seq.updateTime);
    }, idToken: token('U'));

    final src = await local();
    expect(await SyncOutboxRepository(src).pendingCount(), 4);

    // 5. Go online and sync
    connectivity.available = true;
    await sync.sync();

    expect(sync.error, isNull);
    expect(sync.state, SyncState.synced);
    expect(await SyncOutboxRepository(src).pendingCount(), 0);

    // Check remote invoices
    final inv1 = FirestoreRestService.decodeFields(remote.docs['invoices/REQ_1']!['fields']);
    final inv2 = FirestoreRestService.decodeFields(remote.docs['invoices/REQ_2']!['fields']);
    final seqFinal = FirestoreRestService.decodeFields(
      remote.docs['document_sequences/BUS-001_26_SALES_INVOICE']!['fields'],
    );

    print('inv1 invoiceNumber: ${inv1['invoiceNumber']}');
    print('inv2 invoiceNumber: ${inv2['invoiceNumber']}');
    print('seqFinal sequence: ${seqFinal['sequence']}');

    expect(inv1['invoiceNumber'], 'SUMANE-26-00004');
    expect(inv2['invoiceNumber'], 'SUMANE-26-00005');
    expect(seqFinal['sequence'], 5);
  });
}

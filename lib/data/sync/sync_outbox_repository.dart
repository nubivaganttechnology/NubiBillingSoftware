import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../local/local_data_source.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

/// One outbox row per document, one batch per original repository transaction.
class SyncOutboxRepository {
  SyncOutboxRepository(this.local);
  final LocalDataSource local;

  /// Authoritative financial collections that must never be created or modified
  /// via offline synchronization queues.
  static const financialCollections = {
    'payments',
    'payment_allocations',
    'customer_ledger_entries',
    'financial_transactions',
    'supplier_payments',
    'supplier_credits',
    'supplier_ledger_entries',
    'supplier_refunds',
  };

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(
        await local.db.rawQuery("SELECT COUNT(*) FROM sync_outbox WHERE status='PENDING'"),
      ) ??
      0;
  Future<void> enqueue(
    DatabaseExecutor tx,
    String batch,
    Map<String, dynamic> write,
    Map<String, dynamic> readSet,
  ) async {
    final collection = write['collection'] as String,
        id = write['id'] as String;
    final operation = write['operation'] as String;

    // Hard boundary: Prohibit offline financial balance changes
    if (financialCollections.contains(collection)) {
      throw const AppException(
        'Offline financial operations are prohibited. Financial transactions must be confirmed directly by the server.',
        code: 'offline-financial-prohibited',
      );
    }
    if ({
          'purchase_corrections',
          'inventory_batch_movements',
          'supplier_refunds',
          'financial_transactions',
          'staff_khata_transactions',
          'staff_attendance_events',
        }.contains(collection) &&
        operation != 'CREATE') {
      throw const AppException('This audit/financial event is immutable.');
    }
    final existing = await local.row(collection, id, executor: tx);
    if (operation == 'CREATE' &&
        existing != null &&
        existing['isDeleted'] == 0) {
      throw const AppException(
        'This record already exists.',
        code: 'already-exists',
      );
    }
    if (operation != 'CREATE' &&
        (existing == null || existing['isDeleted'] == 1)) {
      throw const AppException(
        'Record is unavailable locally. Sync and retry.',
        code: 'not-found',
      );
    }
    final previous = existing == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(
            jsonDecode(existing['payloadJson'] as String) as Map,
          );
    final encoded = <String, dynamic>{
      ...previous,
      ...?write['fields'] as Map<String, dynamic>?,
    };
    final fields = FirestoreRestService.decodeFields(encoded);
    if (fields['scopeType'] == 'SYSTEM') {
      throw const AppException('System records are read-only.');
    }

    // Authoritative balance modifications require online server confirmation
    if (collection == 'customers' || collection == 'customer_balances') {
      final prevFields = existing == null
          ? <String, dynamic>{}
          : FirestoreRestService.decodeFields(
              jsonDecode(existing['payloadJson'] as String) as Map<String, dynamic>,
            );
      final newDue = (fields['duePaise'] as num?)?.toInt() ?? 0;
      final oldDue = (prevFields['duePaise'] as num?)?.toInt() ?? 0;
      final newAdv = (fields['advancePaise'] as num?)?.toInt() ?? 0;
      final oldAdv = (prevFields['advancePaise'] as num?)?.toInt() ?? 0;
      if (newDue != oldDue || newAdv != oldAdv) {
        throw const AppException(
          'Authoritative customer financial balances cannot be modified offline. Server confirmation is required.',
          code: 'offline-balance-prohibited',
        );
      }
    }

    if (collection == 'invoices') {
      final prevFields = existing == null
          ? <String, dynamic>{}
          : FirestoreRestService.decodeFields(
              jsonDecode(existing['payloadJson'] as String) as Map<String, dynamic>,
            );
      final newDue = (fields['dueAmount'] as num?)?.toInt() ?? 0;
      final oldDue = (prevFields['dueAmount'] as num?)?.toInt() ?? 0;
      final newPaid = (fields['paidPaise'] as num?)?.toInt() ?? 0;
      final oldPaid = (prevFields['paidPaise'] as num?)?.toInt() ?? 0;
      final newStatus = fields['status']?.toString() ?? '';
      final oldStatus = prevFields['status']?.toString() ?? '';
      if (newDue != oldDue || newPaid != oldPaid || (newStatus == 'PAID' && oldStatus != 'PAID')) {
        throw const AppException(
          'Authoritative invoice settlements cannot be performed offline. Server confirmation is required.',
          code: 'offline-settlement-prohibited',
        );
      }
    }

    final revision = ((existing?['localRevision'] as int?) ?? 0) + 1;
    final status = operation == 'DELETE'
        ? 'PENDING_DELETE'
        : existing?['syncStatus'] == 'PENDING_CREATE' || operation == 'CREATE'
        ? 'PENDING_CREATE'
        : 'PENDING_UPDATE';
    await LocalDataSource.put(tx, collection, {
      'remoteId': id,
      'payloadJson': jsonEncode(encoded),
      ...LocalDataSource.scopeColumns(fields),
      'syncStatus': status,
      'localUpdatedAt': LocalDataSource.now(),
      'localRevision': revision,
      'isDeleted':
          operation == 'DELETE' ||
              fields['isDeleted'] == true ||
              fields['status'] == 'DELETED'
          ? 1
          : 0,
      'syncError': null,
    });
    await tx.insert('sync_outbox', {
      'batchId': batch,
      'entityType': collection,
      'documentId': id,
      'operation': operation,
      'tenantId': fields['tenantId'] ?? fields['ownerUid'],
      'businessId': fields['businessId'],
      'outletId': fields['outletId'],
      'payloadJson': jsonEncode(write),
      'readSetJson': jsonEncode(readSet),
      'localRevision': revision,
      'createdAt': LocalDataSource.now(),
    });
  }

  Future<bool> acquire(String owner) => local.db.transaction((tx) async {
    final lease = (await tx.query('sync_lease')).single;
    final expiry = lease['expiresAt'] as String?;
    if (lease['owner'] != null &&
        lease['owner'] != owner &&
        expiry != null &&
        DateTime.parse(expiry).isAfter(DateTime.now().toUtc())) {
      return false;
    }
    await tx.update('sync_lease', {
      'owner': owner,
      'expiresAt': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
    }, where: 'id=1');
    // A previous owner died; the persistent batch is retryable, never discarded.
    await tx.update('sync_outbox', {
      'status': 'PENDING',
    }, where: "status='PROCESSING'");
    return true;
  });
  Future<void> release(String owner) => local.db.update(
    'sync_lease',
    {'owner': null, 'expiresAt': null},
    where: 'id=1 AND owner=?',
    whereArgs: [owner],
  );
  Future<List<Map<String, Object?>>> nextBatch() async {
    final candidates = await local.db.rawQuery(
      "SELECT batchId, MIN(id) AS firstId FROM sync_outbox WHERE status='PENDING' GROUP BY batchId ORDER BY firstId",
    );
    for (final candidate in candidates) {
      final rows = await local.db.query(
        'sync_outbox',
        where: 'batchId=?',
        whereArgs: [candidate['batchId']],
        orderBy: 'id',
      );

      // Quarantine legacy batches containing financial collections
      final hasFinancialRow = rows.any(
        (r) => financialCollections.contains(r['entityType'] as String?),
      );
      if (hasFinancialRow) {
        await local.db.update(
          'sync_outbox',
          {
            'status': 'FAILED',
            'lastError':
                'RECONCILIATION_REQUIRED: Legacy financial operation quarantined. Online reconciliation required.',
          },
          where: 'batchId=?',
          whereArgs: [candidate['batchId']],
        );
        continue;
      }

      bool blocked = false;
      for (final row in rows) {
        final preceding = await local.db.query(
          'sync_outbox',
          where: 'id<? AND batchId!=? AND entityType=? AND documentId=?',
          whereArgs: [
            row['id'],
            row['batchId'],
            row['entityType'],
            row['documentId'],
          ],
          limit: 1,
        );
        if (preceding.isNotEmpty) {
          blocked = true;
          break;
        }
      }
      final reads = jsonDecode(rows.first['readSetJson'] as String) as Map;
      for (final raw in reads.values) {
        final read = raw as Map;
        if (read['pending'] != true) continue;
        final record = await local.row(
          read['collection'] as String,
          read['id'] as String,
        );
        if (record == null ||
            (record['acknowledgedRevision'] as int) <
                (read['revision'] as int)) {
          blocked = true;
          break;
        }
      }
      if (!blocked) return rows;
    }
    return [];
  }

  /// Identifies legacy or unconfirmed financial sync entries in the outbox
  /// for administrative audit and reconciliation.
  Future<List<Map<String, dynamic>>> getPendingFinancialEntries() async {
    return local.db.query(
      'sync_outbox',
      where:
          "lastError LIKE 'RECONCILIATION_REQUIRED%' OR entityType IN ('payments', 'payment_allocations', 'customer_ledger_entries', 'financial_transactions')",
      orderBy: 'id ASC',
    );
  }

  /// Resolves a quarantined legacy financial batch safely without losing audit trail.
  Future<void> reconcileLegacyFinancialBatch(
    String batchId, {
    required String resolution,
  }) async {
    await local.db.update(
      'sync_outbox',
      {
        'status': 'FAILED',
        'lastError': 'RECONCILED: $resolution',
      },
      where: 'batchId=?',
      whereArgs: [batchId],
    );
  }

  Future<void> retry() => local.db.update('sync_outbox', {
    'status': 'PENDING',
    'lastError': null,
  }, where: "status='FAILED' AND lastError NOT LIKE 'RECONCILIATION_REQUIRED%' AND lastError NOT LIKE 'RECONCILED%'");
}

class LocalTransactionContext implements FirestoreTransactionContext {
  LocalTransactionContext(this.local, this.tx);
  final LocalDataSource local;
  final DatabaseExecutor tx;
  final Map<String, Map<String, dynamic>> writes = {};
  final Map<String, dynamic> reads = {};
  String get batchId => _batchId;
  final String _batchId = IdGenerator.create('SYNC');
  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) async {
    final key = '$collection/$id';
    final row = await local.row(collection, id, executor: tx);
    reads[key] = {
      'collection': collection,
      'id': id,
      'exists': row != null && row['isDeleted'] == 0,
      'updateTime': row?['remoteUpdateTime'],
      'revision': row?['localRevision'] ?? 0,
      'pending': row != null && row['syncStatus'] != 'SYNCED',
    };
    final write = writes[key];
    if (write != null) {
      final base = row == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(
              jsonDecode(row['payloadJson'] as String) as Map,
            );
      final fields = FirestoreRestService.decodeFields({
        ...base,
        ...?write['fields'] as Map<String, dynamic>?,
      });
      fields.putIfAbsent('id', () => id);
      if (collection == FirebaseConstants.invoices) {
        fields.putIfAbsent('invoiceId', () => id);
      }
      return FirestoreTransactionDocument(
        id: id,
        exists: write['operation'] != 'DELETE',
        fields: fields,
        updateTime: row?['remoteUpdateTime'] as String?,
      );
    }
    final fields = row == null
        ? <String, dynamic>{}
        : FirestoreRestService.decodeFields(
            jsonDecode(row['payloadJson'] as String),
          );
    if (row != null) {
      fields.putIfAbsent('id', () => id);
      if (collection == FirebaseConstants.invoices) {
        fields.putIfAbsent('invoiceId', () => id);
      }
    }
    return FirestoreTransactionDocument(
      id: id,
      exists: row != null && row['isDeleted'] == 0,
      fields: fields,
      updateTime: row?['remoteUpdateTime'] as String?,
    );
  }

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) async {
    final documents = await local.query(collection, filters, executor: tx);
    return documents
        .map(
          (document) {
            final docName = document['name'] as String? ?? '';
            final docId = docName.split('/').last;
            final fields = FirestoreRestService.decodeFields(document['fields']);
            if (docId.isNotEmpty) {
              fields.putIfAbsent('id', () => docId);
              if (collection == FirebaseConstants.invoices) {
                fields.putIfAbsent('invoiceId', () => docId);
              }
            }
            return FirestoreTransactionDocument(
              id: docId,
              exists: true,
              fields: fields,
            );
          },
        )
        .toList();
  }

  void add(
    String collection,
    String id,
    String operation,
    Map<String, dynamic>? fields,
  ) {
    final key = '$collection/$id';
    final previous = writes[key];
    if (previous != null) {
      if ((previous['operation'] == 'CREATE' ||
              previous['operation'] == 'UPDATE') &&
          operation == 'UPDATE') {
        previous['fields'] = {
          ...previous['fields'] as Map<String, dynamic>,
          ...FirestoreRestService.encodeFields(fields!),
        };
        return;
      }
      if (previous['operation'] == 'CREATE' && operation == 'DELETE') {
        writes.remove(key);
        return;
      }
      throw const AppException(
        'A document can only be written once per operation.',
      );
    }
    writes[key] = {
      'collection': collection,
      'id': id,
      'operation': operation,
      if (fields != null) 'fields': FirestoreRestService.encodeFields(fields),
    };
  }

  @override
  void create(String collection, String id, Map<String, dynamic> fields) =>
      add(collection, id, 'CREATE', fields);
  @override
  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  }) => add(collection, id, 'UPDATE', fields);
  @override
  void delete(String collection, String id, {required String? updateTime}) =>
      add(collection, id, 'DELETE', null);
}

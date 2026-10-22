import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/errors/app_exception.dart';
import '../catalogue/central_product_master_contract.dart';
import '../models/central_product_master.dart';
import '../models/product_model.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_value_codec.dart';
import 'local_database_tables.dart';

class LocalDataSource {
  LocalDataSource(this.db);
  final Database db;
  static String table(String collection) =>
      LocalDatabaseTables.tables[collection] ??
      (throw AppException(
        'No local schema for $collection.',
        code: 'local-schema',
      ));
  static String now() => DateTime.now().toUtc().toIso8601String();
  static Map<String, dynamic> document(
    Map<String, Object?> row,
    String collection,
  ) => {
    'name': '$collection/${row['remoteId']}',
    'fields': jsonDecode(row['payloadJson'] as String),
    'localSyncStatus': row['syncStatus'],
    if (row['remoteUpdateTime'] != null) 'updateTime': row['remoteUpdateTime'],
  };
  Future<Map<String, Object?>?> row(
    String collection,
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final rows = await (executor ?? db).query(
      table(collection),
      where: 'remoteId=?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.single;
  }

  static Map<String, Object?> scopeColumns(Map<String, dynamic> fields) => {
    for (final key in [
      'scopeType',
      'status',
      'catalogueId',
      'businessTypeId',
      'businessSubTypeId',
      'tenantId',
      'businessId',
      'outletId',
      'categoryId',
      'subcategoryId',
      'attributeId',
    ])
      key: fields[key]?.toString(),
  };
  Future<void> upsertRemote(
    String collection,
    List<Map<String, dynamic>> docs, {
    List<FirestoreFilter>? completeQuery,
    DatabaseExecutor? executor,
  }) async {
    Future<void> apply(DatabaseExecutor tx) async {
      if (completeQuery != null && collection != 'inventory_batch_movements') {
        final ids = docs
            .map((d) => (d['name'] as String).split('/').last)
            .toSet();
        final rows = await tx.query(
          table(collection),
          where: "syncStatus='SYNCED' AND isDeleted=0",
        );
        for (final row in rows) {
          final fields = FirestoreValueCodec.decodeFields(
            jsonDecode(row['payloadJson'] as String),
          );
          if (!ids.contains(row['remoteId']) &&
              completeQuery.every((f) => matches(fields[f.field], f))) {
            await tx.update(
              table(collection),
              {
                if (fields['scopeType'] == 'SYSTEM' &&
                    fields['catalogueId'] != null) ...{
                  'status': 'INACTIVE',
                  'payloadJson': jsonEncode(
                    FirestoreValueCodec.encodeFields({
                      ...fields,
                      'status': 'INACTIVE',
                    }),
                  ),
                } else
                  'isDeleted': 1,
                'lastSyncedAt': now(),
              },
              where: 'remoteId=?',
              whereArgs: [row['remoteId']],
            );
          }
        }
      }
      for (final doc in docs) {
        final id = (doc['name'] as String).split('/').last;
        final existing = await row(collection, id, executor: tx);
        if ({
              'purchase_corrections',
              'inventory_batch_movements',
              'supplier_refunds',
              'financial_transactions',
              'staff_khata_transactions',
              'staff_attendance_events',
            }.contains(collection) &&
            existing != null) {
          final prior = FirestoreValueCodec.decodeFields(
            jsonDecode(existing['payloadJson'] as String),
          );
          final incoming = FirestoreValueCodec.decodeFields(
            doc['fields'] as Map<String, dynamic>? ?? const {},
          );
          if (jsonEncode(FirestoreValueCodec.encodeFields(prior)) !=
              jsonEncode(FirestoreValueCodec.encodeFields(incoming))) {
            final conflicts = await tx.query(
              'sync_conflicts',
              where: 'entityType=? AND documentId=? AND resolved=0',
              whereArgs: [collection, id],
            );
            if (conflicts.isEmpty) {
              await tx.insert('sync_conflicts', {
                'entityType': collection,
                'documentId': id,
                'localJson': existing['payloadJson'],
                'remoteJson': jsonEncode(doc),
                'reason': collection == 'purchase_corrections'
                    ? 'Immutable purchase correction audit changed remotely.'
                    : collection == 'inventory_batch_movements'
                    ? 'Immutable inventory batch movement changed remotely.'
                    : 'Immutable financial event changed remotely.',
                'createdAt': now(),
              });
            }
            continue;
          }
        }
        if (existing != null && existing['syncStatus'] != 'SYNCED') {
          final base = existing['remoteUpdateTime'];
          if (base != null && base != doc['updateTime']) {
            final duplicate = await tx.query(
              'sync_conflicts',
              where: 'entityType=? AND documentId=? AND remoteJson=? AND resolved=0',
              whereArgs: [collection, id, jsonEncode(doc)],
            );
            if (duplicate.isEmpty) {
              await tx.insert('sync_conflicts', {
                'entityType': collection,
                'documentId': id,
                'localJson': existing['payloadJson'],
                'remoteJson': jsonEncode(doc),
                'reason': 'Remote changed while local changes are pending.',
                'createdAt': now(),
              });
            }
          }
          continue;
        }
        final fields = FirestoreValueCodec.decodeFields(doc['fields']);
        var rawFields = doc['fields'] as Map<String, dynamic>? ?? {};
        if (collection == 'products') {
          final remoteImg = ProductModel.parseProductImage(fields);
          if (remoteImg != null && remoteImg.isNotEmpty) {
            rawFields = Map<String, dynamic>.from(rawFields);
            rawFields['productImage'] = {'stringValue': remoteImg};
            rawFields['imageUrl'] = {'stringValue': remoteImg};
            fields['productImage'] = remoteImg;
            fields['imageUrl'] = remoteImg;
          } else if (existing != null &&
              (fields['productImage'] == null && fields['imageUrl'] == null)) {
            try {
              final existingFields = FirestoreValueCodec.decodeFields(
                jsonDecode(existing['payloadJson'] as String),
              );
              final existingImg = ProductModel.parseProductImage(
                existingFields,
              );
              if (existingImg != null && existingImg.isNotEmpty) {
                rawFields = Map<String, dynamic>.from(rawFields);
                rawFields['productImage'] = {'stringValue': existingImg};
                rawFields['imageUrl'] = {'stringValue': existingImg};
                fields['productImage'] = existingImg;
                fields['imageUrl'] = existingImg;
              }
            } catch (_) {}
          }
        }
        final data = <String, Object?>{
          'remoteId': id,
          'payloadJson': jsonEncode(rawFields),
          ...scopeColumns(fields),
          'syncStatus': 'SYNCED',
          'isDeleted':
              fields['isDeleted'] == true || fields['status'] == 'DELETED'
              ? 1
              : 0,
          'localUpdatedAt': existing?['localUpdatedAt'] ?? now(),
          'remoteUpdatedAt': fields['updatedAt']?.toString(),
          'remoteUpdateTime': doc['updateTime'],
          'lastSyncedAt': now(),
          'syncError': null,
        };
        await put(tx, collection, data);
      }
    }

    if (executor != null) {
      await apply(executor);
    } else {
      await db.transaction(apply);
    }
  }

  Future<void> upsertCentralProductMasters(
    List<Map<String, dynamic>> documents, {
    DatabaseExecutor? executor,
  }) async {
    Future<void> apply(DatabaseExecutor tx) async {
      for (final document in documents) {
        final documentName = document['name'] as String;
        final documentId = documentName.split('/').last;
        final fields = FirestoreRestService.decodeFields(
          document['fields'] as Map<String, dynamic>? ?? const {},
        );
        final product = CentralProductMaster.fromData(documentId, fields);
        if (documentName.split('/').length < 2 ||
            documentName.split('/')[documentName.split('/').length - 2] !=
                CentralProductMasterContract.collection) {
          throw const AppException(
            'Central product sync returned a document from an unexpected collection.',
            code: 'central-product-source',
          );
        }
        CentralProductMasterContract.validateProduct(product);
        final updatedAt = fields['updatedAt'];
        final remoteUpdatedAt = updatedAt is DateTime
            ? updatedAt.toUtc().toIso8601String()
            : updatedAt?.toString() ?? document['updateTime'] as String?;
        final values = <String, Object?>{
          'master_product_id': product.masterProductId,
          'source_collection': CentralProductMasterContract.collection,
          'product_name': product.productName,
          'normalized_product_name': product.normalizedProductName,
          'business_type_id': product.businessTypeId,
          'business_sub_type_id': product.businessSubTypeId,
          'brand_id': product.brandId,
          'brand_name': product.brandName,
          'range_name': product.rangeName,
          'category_id': product.categoryId,
          'category_name': product.categoryName,
          'subcategory_id': product.subcategoryId,
          'subcategory_name': product.subcategoryName,
          'scope_type': product.scopeType,
          'status': product.status,
          'is_active': product.isActive ? 1 : 0,
          'image_url': product.imageUrl,
          'description': product.description,
          'pack_sizes': product.packSizes == null
              ? null
              : jsonEncode(product.packSizes),
          'finish': product.finish,
          'colour': product.colour,
          'remote_updated_at': remoteUpdatedAt,
          'synced_at': now(),
          'payload_json': jsonEncode(FirestoreRestService.encodeFields(fields)),
        };
        final columns = values.keys.toList();
        await tx.rawInsert(
          'INSERT INTO local_central_product_master (${columns.join(',')}) '
          'VALUES (${List.filled(columns.length, '?').join(',')}) '
          'ON CONFLICT(master_product_id) DO UPDATE SET '
          '${columns.where((column) => column != 'master_product_id').map((column) => '$column=excluded.$column').join(',')}',
          values.values.toList(),
        );
      }
    }

    if (executor == null) {
      await db.transaction(apply);
    } else {
      await apply(executor);
    }
  }

  Future<void> replaceCentralProductMasters(
    List<Map<String, dynamic>> documents, {
    required DatabaseExecutor executor,
  }) async {
    CentralProductMasterContract.validateSnapshot(documents);
    await executor.delete('local_central_product_master');
    await upsertCentralProductMasters(documents, executor: executor);
  }

  Future<void> markRemoteMissing(String collection, String id) async {
    await db.update(
      table(collection),
      {'isDeleted': 1, 'lastSyncedAt': now()},
      where: "remoteId=? AND syncStatus='SYNCED'",
      whereArgs: [id],
    );
  }

  static Future<void> put(
    DatabaseExecutor tx,
    String collection,
    Map<String, Object?> data,
  ) async {
    if (collection == 'inventory_batches' && data['payloadJson'] is String) {
      final fields = FirestoreValueCodec.decodeFields(
        jsonDecode(data['payloadJson'] as String),
      );
      for (final key in [
        'variantId',
        'internalBatchNo',
        'supplierLotNo',
        'expiryDate',
        'purchaseId',
      ]) {
        final value = fields[key];
        data[key] = value is DateTime
            ? value.toUtc().toIso8601String()
            : value?.toString();
      }
    }
    // UPSERT preserves metadata and relationships; never delete/reinsert records.
    final columns = data.keys.toList();
    await tx.rawInsert(
      'INSERT INTO ${table(collection)} (${columns.join(',')}) '
      'VALUES (${List.filled(columns.length, '?').join(',')}) '
      'ON CONFLICT(remoteId) DO UPDATE SET ${columns.where((c) => c != 'remoteId').map((c) => '$c=excluded.$c').join(',')}',
      data.values.toList(),
    );
  }

  Future<List<Map<String, dynamic>>> query(
    String collection,
    List<FirestoreFilter> filters, {
    String? orderBy,
    int? limit,
    bool descending = false,
    DatabaseExecutor? executor,
  }) async {
    // Push indexed scope predicates into SQLite; apply remaining Firestore
    // operators to decoded documents without changing repository contracts.
    final indexed = filters
        .where(
          (f) =>
              f.operation == 'EQUAL' &&
              [
                'tenantId',
                'businessId',
                'outletId',
                'scopeType',
                'categoryId',
                'subcategoryId',
                'attributeId',
                'status',
              ].contains(f.field),
        )
        .toList();
    final rows = await (executor ?? db).query(
      table(collection),
      where: [
        'isDeleted=0',
        ...indexed.map((f) => '${f.field}=?'),
      ].join(' AND '),
      whereArgs: indexed.map((f) => f.value).toList(),
    );
    final docs = rows.map((r) => document(r, collection)).where((d) {
      final fields = FirestoreValueCodec.decodeFields(d['fields']);
      return filters.every((f) => matches(fields[f.field], f));
    }).toList();
    if (orderBy != null) {
      docs.removeWhere(
        (d) =>
            !FirestoreValueCodec.decodeFields(d['fields']).containsKey(orderBy),
      );
      docs.sort((a, b) {
        final comparison = compare(
          FirestoreValueCodec.decodeFields(a['fields'])[orderBy],
          FirestoreValueCodec.decodeFields(b['fields'])[orderBy],
        );
        return descending ? -comparison : comparison;
      });
    }
    return limit == null ? docs : docs.take(limit).toList();
  }

  static int compare(dynamic a, dynamic b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime) a = a.toUtc().toIso8601String();
    if (b is DateTime) b = b.toUtc().toIso8601String();
    return '$a'.compareTo('$b');
  }

  static bool matches(dynamic value, FirestoreFilter filter) {
    final other = filter.value;
    switch (filter.operation) {
      case 'EQUAL':
        return jsonEncode(_json(value)) == jsonEncode(_json(other));
      case 'NOT_EQUAL':
        return value != null &&
            !matches(value, FirestoreFilter(filter.field, 'EQUAL', other));
      case 'ARRAY_CONTAINS':
        return value is List && value.contains(other);
      case 'IN':
        return other is List && other.contains(value);
      case 'NOT_IN':
        return value != null && other is List && !other.contains(value);
      case 'ARRAY_CONTAINS_ANY':
        return value is List && other is List && value.any(other.contains);
      case 'GREATER_THAN':
        return value != null && compare(value, other) > 0;
      case 'GREATER_THAN_OR_EQUAL':
        return value != null && compare(value, other) >= 0;
      case 'LESS_THAN':
        return value != null && compare(value, other) < 0;
      case 'LESS_THAN_OR_EQUAL':
        return value != null && compare(value, other) <= 0;
      default:
        throw AppException('Unsupported local filter ${filter.operation}.');
    }
  }

  static dynamic _json(dynamic value) =>
      value is DateTime ? value.toUtc().toIso8601String() : value;
}

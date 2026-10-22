import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/errors/app_exception.dart';
import '../catalogue/catalogue_fingerprint.dart';
import '../services/firestore_value_codec.dart';
import 'local_data_source.dart';

class CatalogueArchiveStore {
  static const table = 'local_catalogue_archive';
  static const collections = <String>{
    'product_categories',
    'product_subcategories',
    'product_attributes',
    'product_attribute_options',
    'units',
    'subcategory_attribute_templates',
    'product_catalogue_releases',
  };
  static const idFields = <String, String>{
    'product_categories': 'categoryId',
    'product_subcategories': 'subcategoryId',
    'product_attributes': 'attributeId',
    'product_attribute_options': 'optionId',
    'units': 'unitId',
    'subcategory_attribute_templates': 'templateId',
    'product_catalogue_releases': 'releaseId',
  };

  static Future<void> createSchema(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS $table (
      catalogueFingerprint TEXT NOT NULL,
      collection TEXT NOT NULL,
      documentId TEXT NOT NULL,
      payloadId TEXT,
      payloadJson TEXT NOT NULL,
      canonicalContent TEXT NOT NULL,
      archivedAt TEXT NOT NULL,
      PRIMARY KEY (catalogueFingerprint, collection, documentId)
    )
  ''');

  /// Archives only exact SYSTEM source rows, using their stored REST payloads
  /// verbatim. Caller must invoke inside the snapshot-install transaction.
  Future<int> archiveCurrentSnapshot(
    DatabaseExecutor tx, {
    required String fingerprint,
    Future<void> Function(int insertedRows, DatabaseExecutor tx)? failureProbe,
  }) async {
    if (!CatalogueFingerprint.isValid(fingerprint)) {
      throw const AppException(
        'Cannot archive catalogue metadata without an exact fingerprint.',
        code: 'catalogue-provenance-missing',
      );
    }
    await createSchema(tx);
    var count = 0;
    for (final collection in collections) {
      final rows = await tx.query(
        LocalDataSource.table(collection),
        where: "scopeType='SYSTEM' AND isDeleted=0",
        orderBy: 'remoteId',
      );
      for (final row in rows) {
        final documentId = row['remoteId'] as String;
        final payloadJson = row['payloadJson'] as String;
        final decoded = FirestoreValueCodec.decodeFields(jsonDecode(payloadJson));
        final payloadId = decoded[idFields[collection]]?.toString();
        final inserted = await archiveDocument(
          tx,
          fingerprint: fingerprint,
          collection: collection,
          documentId: documentId,
          payloadId: payloadId,
          payloadJson: payloadJson,
        );
        if (inserted) {
          count++;
          if (failureProbe != null) await failureProbe(count, tx);
        }
      }
    }
    return count;
  }

  /// Insert immutable exact source payload. Identical key/content is idempotent;
  /// differing content at an existing key is a hard failure.
  Future<bool> archiveDocument(
    DatabaseExecutor db, {
    required String fingerprint,
    required String collection,
    required String documentId,
    required String? payloadId,
    required String payloadJson,
  }) async {
    if (!CatalogueFingerprint.isValid(fingerprint) ||
        !collections.contains(collection) ||
        documentId.isEmpty) {
      throw const AppException('Invalid catalogue archive identity.');
    }
    final canonicalContent = _canonicalJson({
      'payloadId': payloadId,
      'payload': jsonDecode(payloadJson),
    });
    final old = await db.query(
      table,
      where: 'catalogueFingerprint=? AND collection=? AND documentId=?',
      whereArgs: [fingerprint, collection, documentId],
      limit: 1,
    );
    if (old.isNotEmpty) {
      if (old.single['canonicalContent'] == canonicalContent) return false;
      throw AppException(
        'Catalogue archive key collision for $collection/$documentId.',
        code: 'catalogue-archive-collision',
      );
    }
    await db.insert(table, {
      'catalogueFingerprint': fingerprint,
      'collection': collection,
      'documentId': documentId,
      'payloadId': payloadId,
      'payloadJson': payloadJson,
      'canonicalContent': canonicalContent,
      'archivedAt': LocalDataSource.now(),
    });
    return true;
  }

  Future<Map<String, dynamic>?> getDocument(
    DatabaseExecutor db, {
    required String fingerprint,
    required String collection,
    required String documentId,
  }) async {
    if (!CatalogueFingerprint.isValid(fingerprint)) return null;
    final rows = await db.query(
      table,
      columns: ['documentId', 'payloadId', 'payloadJson'],
      where: 'catalogueFingerprint=? AND collection=? AND documentId=?',
      whereArgs: [fingerprint, collection, documentId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return {
      'documentId': rows.single['documentId'],
      'payloadId': rows.single['payloadId'],
      'fields': FirestoreValueCodec.decodeFields(
        jsonDecode(rows.single['payloadJson'] as String),
      ),
      'payloadJson': rows.single['payloadJson'],
    };
  }

  Future<List<Map<String, dynamic>>> getCollection(
    DatabaseExecutor db, {
    required String fingerprint,
    required String collection,
  }) async {
    if (!CatalogueFingerprint.isValid(fingerprint) ||
        !collections.contains(collection)) {
      return const [];
    }
    final rows = await db.query(
      table,
      where: 'catalogueFingerprint=? AND collection=?',
      whereArgs: [fingerprint, collection],
      orderBy: 'documentId',
    );
    return [
      for (final row in rows)
        {
          'documentId': row['documentId'],
          'payloadId': row['payloadId'],
          'fields': FirestoreValueCodec.decodeFields(
            jsonDecode(row['payloadJson'] as String),
          ),
          'payloadJson': row['payloadJson'],
        },
    ];
  }

  static String _canonicalJson(Object? value) => jsonEncode(_canonical(value));
  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.whereType<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList(growable: false);
    return value;
  }
}

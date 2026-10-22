import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

const _localOnlyKeys = {
  '_syncMutationId',
  'syncStatus',
  'syncError',
  'localUpdatedAt',
  'remoteUpdatedAt',
  'remoteUpdateTime',
  'lastSyncedAt',
  'localRevision',
  'acknowledgedRevision',
};

String canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.whereType<String>().toList()..sort();
    return <String, Object?>{
      for (final key in keys)
        if (key != 'catalogueFingerprint' && !_localOnlyKeys.contains(key))
          key: _canonicalValue(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalValue).toList(growable: false);
  return value;
}

/// Test-only, deterministic fingerprint for the Phase 10H snapshot contract.
String catalogueSnapshotFingerprint(
  Map<String, List<Map<String, dynamic>>> collections,
) {
  final collectionNames = collections.keys.toList()..sort();
  final snapshot = <Map<String, Object?>>[];
  for (final collection in collectionNames) {
    final documents = [...collections[collection]!]
      ..sort(
        (left, right) =>
            (left['documentId'] as String).compareTo(
              right['documentId'] as String,
            ),
      );
    for (final document in documents) {
      final documentId = document['documentId'] as String;
      final fields = Map<String, dynamic>.from(
        document['fields'] as Map? ?? const {},
      );
      snapshot.add({
        'collection': collection,
        'documentId': documentId,
        'fields': fields,
      });
    }
  }
  final digest = sha256.convert(utf8.encode(canonicalJson(snapshot)));
  return 'sha256:$digest';
}

bool isCatalogueFingerprint(Object? value) =>
    value is String && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);

Future<void> createDisposableArchiveSchema(DatabaseExecutor db) => db.execute('''
CREATE TABLE IF NOT EXISTS phase10hb_catalogue_archive (
  catalogueFingerprint TEXT NOT NULL,
  collection TEXT NOT NULL,
  documentId TEXT NOT NULL,
  payloadId TEXT,
  payloadJson TEXT NOT NULL,
  canonicalContent TEXT NOT NULL,
  PRIMARY KEY (catalogueFingerprint, collection, documentId)
)
''');

/// Returns true when inserted and false for an identical idempotent repeat.
Future<bool> archiveSnapshotDocument(
  DatabaseExecutor db, {
  required String fingerprint,
  required String collection,
  required String documentId,
  required String? payloadId,
  required Map<String, dynamic> payload,
}) async {
  if (!isCatalogueFingerprint(fingerprint)) {
    throw ArgumentError.value(fingerprint, 'fingerprint');
  }
  final existing = await db.query(
    'phase10hb_catalogue_archive',
    where: 'catalogueFingerprint=? AND collection=? AND documentId=?',
    whereArgs: [fingerprint, collection, documentId],
    limit: 1,
  );
  final canonicalContent = canonicalJson({
    'payloadId': payloadId,
    'payload': payload,
  });
  if (existing.isNotEmpty) {
    if (existing.single['canonicalContent'] == canonicalContent) return false;
    throw StateError(
      'Archive key collision for $fingerprint/$collection/$documentId',
    );
  }
  await db.insert('phase10hb_catalogue_archive', {
    'catalogueFingerprint': fingerprint,
    'collection': collection,
    'documentId': documentId,
    'payloadId': payloadId,
    // Preserve the source map's own JSON representation independently of ID.
    'payloadJson': jsonEncode(payload),
    'canonicalContent': canonicalContent,
  });
  return true;
}

class ArchiveResolution {
  const ArchiveResolution(this.status, {this.payload, this.payloadId});
  final String status;
  final Map<String, dynamic>? payload;
  final String? payloadId;
}

Future<ArchiveResolution> resolveArchivedDocument(
  DatabaseExecutor db, {
  required String? fingerprint,
  required String collection,
  required String documentId,
}) async {
  if (!isCatalogueFingerprint(fingerprint)) {
    return const ArchiveResolution('PROVENANCE_MISSING');
  }
  final rows = await db.query(
    'phase10hb_catalogue_archive',
    where: 'catalogueFingerprint=? AND collection=? AND documentId=?',
    whereArgs: [fingerprint, collection, documentId],
    limit: 1,
  );
  if (rows.isEmpty) return const ArchiveResolution('ARCHIVE_ENTRY_MISSING');
  return ArchiveResolution(
    'EXACT',
    payload: Map<String, dynamic>.from(
      jsonDecode(rows.single['payloadJson'] as String) as Map,
    ),
    payloadId: rows.single['payloadId'] as String?,
  );
}

ArchiveResolution resolveVariantParent(
  Map<String, dynamic> variant,
  Map<String, Map<String, dynamic>> productsById,
) {
  final productId = variant['productId'];
  if (productId is! String || productId.isEmpty) {
    return const ArchiveResolution('PROVENANCE_MISSING');
  }
  final product = productsById[productId];
  if (product == null || !isCatalogueFingerprint(product['catalogueFingerprint'])) {
    return const ArchiveResolution('PROVENANCE_MISSING');
  }
  return ArchiveResolution(
    'EXACT',
    payload: product,
    payloadId: product['catalogueFingerprint'] as String,
  );
}

ArchiveResolution resolveProductProvenance(Map<String, dynamic> product) =>
    isCatalogueFingerprint(product['catalogueFingerprint'])
    ? ArchiveResolution(
        'EXACT',
        payload: product,
        payloadId: product['catalogueFingerprint'] as String,
      )
    : const ArchiveResolution('PROVENANCE_MISSING');

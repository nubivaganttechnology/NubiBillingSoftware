import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../services/firestore_value_codec.dart';

/// Exact identity of a canonical installed SYSTEM metadata snapshot.
/// This is a content identity, not an authentication/signature mechanism.
class CatalogueFingerprint {
  static final _valid = RegExp(r'^sha256:[0-9a-f]{64}$');
  static const _excludedFields = {
    'catalogueFingerprint',
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

  static bool isValid(Object? value) => value is String && _valid.hasMatch(value);

  static String calculate(Map<String, List<Map<String, dynamic>>> documents) {
    final collections = documents.keys.toList()..sort();
    final canonical = <Map<String, Object?>>[];
    for (final collection in collections) {
      final ordered = [...documents[collection]!]
        ..sort((a, b) => _documentId(a).compareTo(_documentId(b)));
      for (final document in ordered) {
        canonical.add({
          'collection': collection,
          'documentId': _documentId(document),
          'fields': _orderedValue(_decodedFields(document)),
        });
      }
    }
    final bytes = utf8.encode(jsonEncode(canonical));
    return 'sha256:${sha256.convert(bytes)}';
  }

  static String _documentId(Map<String, dynamic> document) {
    final name = document['name'];
    if (name is String && name.isNotEmpty) return name.split('/').last;
    final id = document['documentId'];
    if (id is String && id.isNotEmpty) return id;
    throw const FormatException('Catalogue document has no stable document ID.');
  }

  static Map<String, dynamic> _decodedFields(Map<String, dynamic> document) {
    final fields = document['fields'] ?? document['payload'];
    if (fields is! Map) {
      throw const FormatException('Catalogue document has no metadata fields.');
    }
    // Accept decoded fixture/source maps and Firestore REST typed field maps.
    if (fields.values.any((value) => value is Map && value.keys.any(
          (key) => const {
            'stringValue', 'integerValue', 'doubleValue', 'booleanValue',
            'timestampValue', 'arrayValue', 'mapValue', 'nullValue',
          }.contains(key),
        ))) {
      return FirestoreValueCodec.decodeFields(fields);
    }
    return Map<String, dynamic>.from(fields);
  }

  static Object? _orderedValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.whereType<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys)
          if (!_excludedFields.contains(key)) key: _orderedValue(value[key]),
      };
    }
    if (value is List) return value.map(_orderedValue).toList(growable: false);
    if (value is DateTime) return value.toUtc().toIso8601String();
    return value;
  }
}

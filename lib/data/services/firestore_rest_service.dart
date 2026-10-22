import 'dart:async';
import 'dart:convert';

import '../../core/config/environment_config.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import 'firestore_data_service.dart';
import 'firestore_transaction_service.dart';
import 'firestore_value_codec.dart';

export 'firestore_data_service.dart' show FirestoreFilter;

class FirestoreRestService
    implements FirestoreDataService, FirestoreTransactionService {
  FirestoreRestService(this.api);
  final ApiClient api;
  String get _documents =>
      '${FirebaseConstants.firestore}/${EnvironmentConfig.projectId}/databases/(default)/documents';
  Uri _uri(String c, String id) =>
      Uri.parse('$_documents/$c/${Uri.encodeComponent(id)}');

  /// Checks whether the remote Firestore server is actively reachable.
  /// Does not accept device Wi-Fi presence alone; verifies with a real authenticated ping.
  Future<bool> checkServerAvailability({String? idToken}) async {
    try {
      await api.get(
        Uri.parse('$_documents/${FirebaseConstants.appConfig}/global'),
        token: idToken,
      );
      return true;
    } on AppException catch (e) {
      if (e.code == 'not-found' ||
          e.code == '404' ||
          e.code == '403' ||
          e.code == 'permission-denied' ||
          e.code == '401' ||
          e.code == 'unauthenticated') {
        // The server answered the HTTP request, meaning server is reachable.
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> getDocument(
    String c,
    String id, {
    String? idToken,
  }) async {
    try {
      return await api.get(_uri(c, id), token: idToken);
    } on AppException catch (x) {
      if (x.code == '404') {
        throw const AppException('Document not found.', code: 'not-found');
      }
      if (x.code == '403') {
        throw AppException(x.message, code: 'permission-denied');
      }
      if (x.code == '401') {
        throw AppException(
          'Your session has expired. Please sign in again.',
          code: 'unauthenticated',
        );
      }
      if (x.code != null) {
        throw AppException('${x.message} (HTTP ${x.code})', code: x.code);
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> queryEqual(
    String collection,
    String field,
    Object value, {
    String? idToken,
  }) async {
    final uri = Uri.parse('$_documents${FirebaseConstants.runQuery}');
    try {
      final response = await api.postList(
        uri,
        body: jsonEncode({
          'structuredQuery': {
            'from': [
              {'collectionId': collection},
            ],
            'where': {
              'fieldFilter': {
                'field': {'fieldPath': field},
                'op': 'EQUAL',
                'value': encodeValue(value),
              },
            },
          },
        }),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
      );
      return response
          .where((entry) => entry['document'] is Map<String, dynamic>)
          .map((entry) => entry['document'] as Map<String, dynamic>)
          .toList(growable: false);
    } on AppException catch (error) {
      throw _friendlyError(error);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    final uri = Uri.parse('$_documents${FirebaseConstants.runQuery}');
    try {
      final results = await api.postList(
        uri,
        body: jsonEncode({
          'structuredQuery': _structuredQuery(
            collection,
            filters,
            orderBy: orderBy,
            limit: limit,
            descending: descending,
          ),
        }),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
      );
      return results
          .where((entry) => entry['document'] is Map<String, dynamic>)
          .map((entry) => entry['document'] as Map<String, dynamic>)
          .toList(growable: false);
    } on AppException catch (error) {
      throw _friendlyError(error);
    }
  }

  /// A snapshot-pinned, bounded sync page. Initial name ordering includes legacy
  /// documents that have no updatedAt. Incremental pages use timestamp + name.
  Future<FirestoreSyncPage> readSyncPage({
    required String collection,
    required List<FirestoreFilter> filters,
    required String queryId,
    required String reason,
    String? cursor,
    String? readTime,
    Map<String, dynamic>? after,
    int pageSize = 200,
    String? idToken,
  }) async {
    try {
      final effective = [
        ...filters,
        if (cursor != null)
          FirestoreFilter(
            'updatedAt',
            'GREATER_THAN_OR_EQUAL',
            DateTime.parse(cursor).subtract(const Duration(seconds: 2)),
          ),
      ];
      final query = _structuredQuery(collection, effective, limit: pageSize);
      query['orderBy'] = [
        if (cursor != null)
          {
            'field': {'fieldPath': 'updatedAt'},
            'direction': 'ASCENDING',
          },
        {
          'field': {'fieldPath': '__name__'},
          'direction': 'ASCENDING',
        },
      ];
      if (after != null) {
        query['startAt'] = {
          'before': false,
          'values': [
            if (cursor != null) (after['fields'] as Map)['updatedAt'],
            {'referenceValue': after['name']},
          ],
        };
      }
      final results = await runZoned(
        () => api.postList(
          Uri.parse('$_documents${FirebaseConstants.runQuery}'),
          body: jsonEncode({'structuredQuery': query, 'readTime': ?readTime}),
          headers: {
            'Content-Type': 'application/json',
            if (idToken != null) 'Authorization': 'Bearer $idToken',
          },
        ),
        zoneValues: {
          #firestoreReadContext: '$reason query=$queryId cursor=$cursor',
        },
      );
      final docs = results
          .where((r) => r['document'] is Map)
          .map((r) => Map<String, dynamic>.from(r['document'] as Map))
          .toList();
      final time =
          readTime ??
          results
              .where((r) => r['readTime'] != null)
              .map((r) => r['readTime'] as String)
              .lastOrNull;
      if (time == null) {
        throw const AppException(
          'Missing server readTime; cursor was not advanced.',
          code: 'missing-read-time',
        );
      }
      return FirestoreSyncPage(
        docs,
        DateTime.parse(time).toUtc().toIso8601String(),
      );
    } on AppException catch (e) {
      throw _friendlyError(e);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> runQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) => queryDocuments(
    collection: collection,
    filters: filters,
    orderBy: orderBy,
    limit: limit,
    descending: descending,
    idToken: idToken,
  );

  @override
  Future<List<Map<String, dynamic>>> listDocuments(
    String collection, {
    String? idToken,
  }) => queryDocuments(
    collection: collection,
    filters: const [],
    idToken: idToken,
  );

  @override
  Future<Map<String, dynamic>> aggregateDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) async {
    final uri = Uri.parse(
      '$_documents${FirebaseConstants.runAggregationQuery}',
    );
    final aggregations = <Map<String, dynamic>>[
      {'alias': 'count', 'count': <String, dynamic>{}},
      if (sumField != null)
        {
          'alias': 'total',
          'sum': {
            'field': {'fieldPath': sumField},
          },
        },
    ];
    try {
      final results = await api.postList(
        uri,
        body: jsonEncode({
          'structuredAggregationQuery': {
            'structuredQuery': _structuredQuery(collection, filters),
            'aggregations': aggregations,
          },
        }),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
      );
      if (results.isEmpty || results.first['result'] is! Map) return const {};
      final result = results.first['result'] as Map;
      return decodeFields(result['aggregateFields']);
    } on AppException catch (error) {
      throw _friendlyError(error);
    }
  }

  @override
  Future<Map<String, dynamic>> runAggregationQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  }) => aggregateDocuments(
    collection: collection,
    filters: filters,
    sumField: sumField,
    idToken: idToken,
  );

  Map<String, dynamic> _structuredQuery(
    String collection,
    List<FirestoreFilter> filters, {
    String? orderBy,
    int? limit,
    bool descending = false,
  }) {
    final query = <String, dynamic>{
      'from': [
        {'collectionId': collection},
      ],
      if (filters.isNotEmpty)
        'where': filters.length == 1
            ? _fieldFilter(filters.single)
            : {
                'compositeFilter': {
                  'op': 'AND',
                  'filters': filters.map(_fieldFilter).toList(),
                },
              },
      if (orderBy != null)
        'orderBy': [
          {
            'field': {'fieldPath': orderBy},
            'direction': descending ? 'DESCENDING' : 'ASCENDING',
          },
        ],
      'limit': ?limit,
    };
    return query;
  }

  Map<String, dynamic> _fieldFilter(FirestoreFilter filter) => {
    'fieldFilter': {
      'field': {'fieldPath': filter.field},
      'op': filter.operation,
      'value': encodeValue(filter.value),
    },
  };

  AppException _friendlyError(AppException error) {
    switch (error.code) {
      case 'network':
        return error;
      case '401':
        return AppException(
          'Your session has expired. Please sign in again.',
          code: 'unauthenticated',
        );
      case '403':
        return AppException(error.message, code: 'permission-denied');
      case '404':
        return AppException(
          'The requested workspace data could not be found.',
          code: 'not-found',
        );
      default:
        if (error.code != null) {
          return AppException(
            '${error.message} (HTTP ${error.code})',
            code: error.code,
          );
        }
        return error;
    }
  }

  @override
  Future<void> createDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    final uri = Uri.parse(
      '$_documents/$collection?documentId=${Uri.encodeQueryComponent(id)}',
    );
    try {
      await api.post(
        uri,
        body: jsonEncode({'fields': encodeFields(fields)}),
        headers: {
          'Content-Type': 'application/json',
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
      );
    } on AppException catch (error) {
      throw _friendlyError(error);
    }
  }

  @override
  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {
    final updateMask = fields.keys
        .map(
          (field) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(field)}',
        )
        .join('&');
    final uri = Uri.parse('${_uri(collection, id)}?$updateMask');
    try {
      await api.patch(
        uri,
        body: jsonEncode({'fields': encodeFields(fields)}),
        token: idToken,
        headers: {'Content-Type': 'application/json'},
      );
    } on AppException catch (error) {
      throw _friendlyError(error);
    }
  }

  @override
  Future<void> patchDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) => updateDocument(collection, id, fields, idToken: idToken);

  @override
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext transaction) action, {
    required String idToken,
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final transaction = _RestFirestoreTransaction(this, idToken);
      final result = await action(transaction);
      try {
        await commitAtomicWrites(
          transaction._writes.values.toList(growable: false),
          idToken: idToken,
        );
        return result;
      } on AppException catch (error) {
        final retryable = const {
          'ABORTED',
          '409',
          'FAILED_PRECONDITION',
          '412',
        }.contains(error.code?.toUpperCase());
        final preconditionFailure =
            error.code == '400' &&
            (error.message.toLowerCase().contains('precondition') ||
                error.message.toLowerCase().contains('update time'));
        if ((!retryable && !preconditionFailure) || attempt == maxAttempts) {
          rethrow;
        }
      }
    }
    throw const AppException(
      'The operation changed concurrently. Reload and retry.',
    );
  }

  Future<void> commitAtomicWrites(
    List<FirestoreWrite> writes, {
    String? idToken,
  }) => commitWrites(writes, idToken: idToken);

  Future<void> commitWrites(
    List<FirestoreWrite> writes, {
    String? idToken,
  }) async {
    if (writes.isEmpty) return;
    if (writes.length > 500) {
      throw const AppException(
        'This atomic operation exceeds Firestore’s 500-write limit.',
        code: 'write-limit-exceeded',
      );
    }
    await api.post(
      Uri.parse('$_documents:commit'),
      body: jsonEncode({
        'writes': writes.map(_encodeWrite).toList(growable: false),
      }),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
    );
  }

  Future<void> updateWithPrecondition(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String updateTime,
    String? idToken,
  }) => commitWrites([
    FirestoreWrite.update(collection, id, fields, updateTime: updateTime),
  ], idToken: idToken);

  Future<void> deleteWithPrecondition(
    String collection,
    String id, {
    required String updateTime,
    String? idToken,
  }) => commitWrites([
    FirestoreWrite.delete(collection, id, updateTime: updateTime),
  ], idToken: idToken);

  Map<String, dynamic> _encodeWrite(FirestoreWrite write) {
    final fields = {...?write.fields}..remove('updatedAt');
    final transforms = [
      {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
    ];
    final name =
        'projects/${EnvironmentConfig.projectId}/databases/(default)/documents/${write.collection}/${Uri.encodeComponent(write.id)}';
    switch (write.kind) {
      case FirestoreWriteKind.create:
        return {
          'update': {'name': name, 'fields': encodeFields(fields)},
          'updateMask': {'fieldPaths': fields.keys.toList()},
          'currentDocument': {'exists': false},
          'updateTransforms': transforms,
        };
      case FirestoreWriteKind.update:
        return {
          'update': {'name': name, 'fields': encodeFields(fields)},
          'updateMask': {'fieldPaths': fields.keys.toList()},
          'currentDocument': {'updateTime': write.updateTime},
          'updateTransforms': transforms,
        };
      case FirestoreWriteKind.delete:
        return {
          'delete': name,
          'currentDocument': {'updateTime': write.updateTime},
        };
    }
  }

  @override
  Future<void> deleteDocument(
    String collection,
    String id, {
    String? idToken,
  }) async {
    try {
      await api.delete(_uri(collection, id), token: idToken);
    } on AppException catch (error) {
      throw _friendlyError(error);
    }
  }

  static Map<String, dynamic> decodeFields(Object? raw) {
    return FirestoreValueCodec.decodeFields(raw);
  }

  static dynamic decodeValue(dynamic value) =>
      FirestoreValueCodec.decodeValue(value);

  static Map<String, dynamic> encodeFields(Map<String, dynamic> fields) =>
      FirestoreValueCodec.encodeFields(fields);

  static Map<String, dynamic> encodeValue(dynamic value) =>
      FirestoreValueCodec.encodeValue(value);
}

enum FirestoreWriteKind { create, update, delete }

class FirestoreWrite {
  FirestoreWrite._(
    this.kind,
    this.collection,
    this.id, {
    this.fields,
    this.updateTime,
  });

  factory FirestoreWrite.create(
    String collection,
    String id,
    Map<String, dynamic> fields,
  ) => FirestoreWrite._(
    FirestoreWriteKind.create,
    collection,
    id,
    fields: Map.of(fields),
  );

  factory FirestoreWrite.update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String updateTime,
  }) => FirestoreWrite._(
    FirestoreWriteKind.update,
    collection,
    id,
    fields: Map.of(fields),
    updateTime: updateTime,
  );

  factory FirestoreWrite.delete(
    String collection,
    String id, {
    required String updateTime,
  }) => FirestoreWrite._(
    FirestoreWriteKind.delete,
    collection,
    id,
    updateTime: updateTime,
  );

  final FirestoreWriteKind kind;
  final String collection;
  final String id;
  final Map<String, dynamic>? fields;
  final String? updateTime;
}

class _RestFirestoreTransaction implements FirestoreTransactionContext {
  _RestFirestoreTransaction(this._firestore, this._idToken);

  final FirestoreRestService _firestore;
  final String _idToken;
  final Map<String, FirestoreWrite> _writes = {};
  final Map<String, String?> _readUpdateTimes = {};

  String _key(String collection, String id) => '$collection/$id';

  @override
  Future<FirestoreTransactionDocument> get(String collection, String id) async {
    final key = _key(collection, id);
    final pending = _writes[key];
    if (pending?.kind == FirestoreWriteKind.create) {
      return FirestoreTransactionDocument(
        exists: true,
        fields: Map.of(pending!.fields!),
      );
    }
    try {
      final document = await _firestore.getDocument(
        collection,
        id,
        idToken: _idToken,
      );
      final updateTime = document['updateTime'] as String?;
      if (updateTime == null || updateTime.isEmpty) {
        throw const AppException(
          'Firestore did not return an update time for a read document.',
          code: 'missing-update-time',
        );
      }
      _readUpdateTimes[key] = updateTime;
      return FirestoreTransactionDocument(
        exists: true,
        fields: FirestoreRestService.decodeFields(document['fields']),
        updateTime: updateTime,
      );
    } on AppException catch (error) {
      if (error.code == 'not-found') {
        _readUpdateTimes[key] = null;
        return const FirestoreTransactionDocument(exists: false, fields: {});
      }
      rethrow;
    }
  }

  @override
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  ) async {
    final docs = await _firestore.queryDocuments(
      collection: collection,
      filters: filters,
      idToken: _idToken,
    );
    return docs.map((doc) {
      final name = doc['name'] as String? ?? '';
      final docId = name.split('/').last;
      final updateTime = doc['updateTime'] as String?;
      final key = _key(collection, docId);
      if (updateTime != null) {
        _readUpdateTimes[key] = updateTime;
      }
      return FirestoreTransactionDocument(
        exists: true,
        fields: FirestoreRestService.decodeFields(doc['fields']),
        updateTime: updateTime,
      );
    }).toList();
  }

  @override
  void create(String collection, String id, Map<String, dynamic> fields) {
    final key = _key(collection, id);
    if (_writes.containsKey(key)) {
      throw const AppException(
        'A document can only be written once per operation.',
      );
    }
    _writes[key] = FirestoreWrite.create(collection, id, fields);
  }

  @override
  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  }) {
    final key = _key(collection, id);
    final pending = _writes[key];
    if (pending?.kind == FirestoreWriteKind.create) {
      pending!.fields!.addAll(fields);
      return;
    }
    final version = updateTime ?? _readUpdateTimes[key];
    if (version == null) {
      throw const AppException(
        'Read the document before updating it so concurrent changes are protected.',
        code: 'precondition-required',
      );
    }
    if (pending?.kind == FirestoreWriteKind.update) {
      pending!.fields!.addAll(fields);
      return;
    }
    _writes[key] = FirestoreWrite.update(
      collection,
      id,
      fields,
      updateTime: version,
    );
  }

  @override
  void delete(String collection, String id, {required String? updateTime}) {
    final key = _key(collection, id);
    final pending = _writes[key];
    if (pending?.kind == FirestoreWriteKind.create) {
      _writes.remove(key);
      return;
    }
    final version = updateTime ?? _readUpdateTimes[key];
    if (version == null) {
      throw const AppException(
        'Read the document before deleting it so concurrent changes are protected.',
        code: 'precondition-required',
      );
    }
    _writes[key] = FirestoreWrite.delete(collection, id, updateTime: version);
  }
}

class FirestoreSyncPage {
  const FirestoreSyncPage(this.documents, this.readTime);
  final List<Map<String, dynamic>> documents;
  final String readTime;
}

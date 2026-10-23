import 'firestore_data_service.dart';

/// Provider-neutral contract for REST-backed atomic write operations.
abstract interface class FirestoreTransactionService {
  Future<T> runAtomicOperation<T>(
    Future<T> Function(FirestoreTransactionContext transaction) action, {
    required String idToken,
    int maxAttempts = 3,
  });
}

abstract interface class FirestoreTransactionContext {
  Future<FirestoreTransactionDocument> get(String collection, String id);

  /// Reads the transaction's local snapshot when backed by SQLite. This is
  /// used for operational guards that must not depend on a network query.
  Future<List<FirestoreTransactionDocument>> query(
    String collection,
    List<FirestoreFilter> filters,
  );

  void create(String collection, String id, Map<String, dynamic> fields);

  void update(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String? updateTime,
  });

  void delete(String collection, String id, {required String? updateTime});
}

class FirestoreTransactionDocument {
  const FirestoreTransactionDocument({
    this.id,
    required this.exists,
    required this.fields,
    this.updateTime,
  });

  final String? id;
  final bool exists;
  final Map<String, dynamic> fields;

  /// Firestore REST updateTime captured when this document was read.
  final String? updateTime;
}

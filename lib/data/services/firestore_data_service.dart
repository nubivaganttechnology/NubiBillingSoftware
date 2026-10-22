abstract interface class FirestoreDataService {
  Future<Map<String, dynamic>> getDocument(
    String collection,
    String id, {
    String? idToken,
  });

  Future<List<Map<String, dynamic>>> queryEqual(
    String collection,
    String field,
    Object value, {
    String? idToken,
  });

  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  });

  Future<List<Map<String, dynamic>>> runQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  });

  Future<List<Map<String, dynamic>>> listDocuments(
    String collection, {
    String? idToken,
  });

  Future<Map<String, dynamic>> aggregateDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  });

  Future<Map<String, dynamic>> runAggregationQuery({
    required String collection,
    required List<FirestoreFilter> filters,
    String? sumField,
    String? idToken,
  });

  Future<void> createDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  });

  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  });

  Future<void> patchDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  });

  Future<void> deleteDocument(String collection, String id, {String? idToken});
}

class FirestoreFilter {
  const FirestoreFilter(this.field, this.operation, this.value);

  final String field;
  final String operation;
  final Object value;
}

class ReportReadQuery {
  const ReportReadQuery(this.key, this.collection, this.filters);
  final String key, collection;
  final List<FirestoreFilter> filters;
}

class ReportReadSnapshot {
  const ReportReadSnapshot(this.documents, this.coverage);
  final Map<String, List<Map<String, dynamic>>> documents;
  // Query key -> sync timestamp, status, pending count, conflict count.
  final Map<String, Map<String, Object?>> coverage;
}

/// Read-only reporting access. It must not register sync queries or write cursors.
abstract interface class FinancialReportSnapshotReader {
  Future<ReportReadSnapshot> readReportSnapshot(
    List<ReportReadQuery> queries, {
    required String token,
  });
}

/// Implemented by local sources to distinguish an empty, synchronized business
/// from an incomplete first download before reserving offline product codes.
abstract interface class OfflineWritePrerequisites {
  Future<void> ensureProductScopeReady(String tenantId, String businessId);
}

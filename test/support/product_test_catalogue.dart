import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

import 'phase10e_release.dart' show release4Documents;

typedef ProductTestRemoteSeed = void Function(
  String collection,
  String id,
  Map<String, dynamic> fields,
);

/// Installs the complete isolated v4 compiler fixture into a fresh/test SQLite
/// source and mirrors the exact installed SYSTEM snapshot to a fake remote.
/// The fixture's approval flags remain false; only test callers may opt into
/// the test-only approval policy, while production readiness checks stay on.
Future<void> installProductTestCatalogue({
  required LocalDataSource source,
  required ProductTestRemoteSeed seedRemote,
}) async {
  final documents = release4Documents();
  await SystemCatalogueSnapshot.import(
    source: source,
    documents: documents,
    readTimes: const {},
    allowUnapprovedIsolatedForTests: true,
  );
  for (final collection in documents.keys) {
    final rows = await source.query(collection, const [
      FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
    ]);
    for (final document in rows) {
      final id = (document['name'] as String).split('/').last;
      seedRemote(
        collection,
        id,
        FirestoreValueCodec.decodeFields(document['fields']),
      );
    }
  }
}

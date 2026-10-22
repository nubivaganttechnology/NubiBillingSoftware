import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';
import 'package:testflutter/data/services/product_validator.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';
import 'package:testflutter/data/sync/sync_query_registry.dart';

import 'decoded_catalogue_audit.dart' show ReadOnlyCatalogueService;
import 'phase10c_model.dart';

final phase10eReview = jsonDecode(
  File('docs/catalogue-release-v4-review.json').readAsStringSync(),
) as Map<String, dynamic>;
final phase10eCandidates = (phase10eReview['canonicalCandidates'] as List)
    .cast<Map<String, dynamic>>();
const liquidBasement = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID';
const cementitiousBasement =
    'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS';

Map<String, List<Map<String, dynamic>>> release4Rows() => {
  for (final e in (jsonDecode(
    File('test/fixtures/system_catalogue_v4.json').readAsStringSync(),
  ) as Map).entries)
    e.key as String: (e.value as List).cast<Map<String, dynamic>>(),
};

Map<String, List<Map<String, dynamic>>> release4Documents() =>
    CatalogueContract.encode(release4Rows());

/// Test-only synthetic approval for repository tests that require a published
/// release. Production readiness never treats the review fixture as approved.
Map<String, List<Map<String, dynamic>>> approvedRelease4DocumentsForTest() {
  final documents = release4Documents();
  final marker = documents['product_catalogue_releases']!.single;
  final fields = FirestoreValueCodec.decodeFields(marker['fields']);
  fields
    ..['isolatedOnly'] = false
    ..['approvedForLiveExecution'] = true
    ..['productionMigrationApproved'] = true
    ..['firestorePublicationApproved'] = true
    ..remove('contentFingerprint');
  marker['fields'] = FirestoreValueCodec.encodeFields(fields);
  return documents;
}

/// All mutation is inside a new temporary directory. Actual snapshot importer;
/// reads use LocalDataSource and a query-only adapter with no remote client.
class Phase10EFixture extends Phase10CFixture {
  @override
  Future<void> open({bool importRelease = true}) async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('nubibill-phase10e-');
    database = LocalDatabase(
      factory: databaseFactoryFfi,
      directory: directory.path,
    );
    local = LocalDataSource(await database.open('phase10e', 'isolated'));
    final reader = ReadOnlyCatalogueService(local);
    resolver = ProductTemplateResolver(reader);
    validator = ProductValidator(reader);
    for (final collection in ['units', 'product_subcategories']) {
      await SyncQueryRegistry.upsert(local.db, collection, {
        'filters': [
          {
            'field': 'scopeType',
            'operation': 'EQUAL',
            'value': {'stringValue': 'SYSTEM'},
          },
        ],
      });
    }
    if (importRelease) {
      await SystemCatalogueSnapshot.import(
        source: local,
        documents: release4Documents(),
        readTimes: const {
          'units': 'ISOLATED_RELEASE_4_UNITS_CURSOR',
          'product_subcategories': 'ISOLATED_RELEASE_4_SUBS_CURSOR',
        },
        allowUnapprovedIsolatedForTests: true,
      );
    }
  }

  static String unitId(String name) => CatalogueContract.unitIds[name]!;

  @override
  Map<String, dynamic> state(
    ResolvedProductTemplate template, {
    ResolvedTemplateAttribute? selected,
    String? option,
    bool converting = false,
    bool omitColourMode = false,
  }) {
    final result = super.state(
      template,
      selected: selected,
      option: option,
      converting: converting,
      omitColourMode: omitColourMode,
    );
    // Reuse the form-state builder, translating its synthetic unit IDs to the
    // immutable canonical master identities that the actual release imported.
    final variant = (result['variants'] as List).single as Map;
    for (final field in ['packUnitId', 'commercialUnitId', 'baseUnitId']) {
      variant[field] = unitId(
        (variant[field] as String).substring('UNIT_'.length),
      );
    }
    return result;
  }
}

/// Complete logical state, including query cursors/outbox/all business tables.
/// Exact SQL values (including timestamps) must match on no-op/rollback.
Future<String> completeState(DatabaseExecutor db) async {
  final names = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
  );
  final result = <String, dynamic>{};
  for (final entry in names) {
    final name = entry['name'] as String;
    final quoted = name.replaceAll('"', '""');
    final records = await db.rawQuery('SELECT * FROM "$quoted"');
    final encoded =
        records.map((r) => jsonEncode(SyncQueryRegistry.canonical(r))).toList()
          ..sort();
    result[name] = encoded;
  }
  return jsonEncode(result);
}

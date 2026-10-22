import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/product_template_resolver.dart';

class _LocalCatalogueReader implements FirestoreDataService {
  _LocalCatalogueReader(this.local);
  final LocalDataSource local;

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) => local.query(
    collection,
    filters,
    orderBy: orderBy,
    limit: limit,
    descending: descending,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Phase 8 only permits local catalogue queries.');
}

void main() {
  // Register each direct Python/SQLite proof in the normal workspace suite.
  // Python's unittest loader is the single source of test names.
  final discovered = Process.runSync('python3', [
    '-B',
    '-c',
    'import json,unittest; from tool.tests.test_catalogue_phase8 import '
        'CatalogueMigrationProof; print(json.dumps(unittest.TestLoader()'
        '.getTestCaseNames(CatalogueMigrationProof)))',
  ]);
  if (discovered.exitCode != 0) {
    throw StateError(
      'Cannot discover Phase 8 SQLite tests: ${discovered.stderr}',
    );
  }
  final names = (jsonDecode(discovered.stdout as String) as List)
      .cast<String>();
  group('Phase 8 isolated SQLite migration', () {
    for (final name in names) {
      test(name.replaceFirst('test_', '').replaceAll('_', ' '), () async {
        final result = await Process.run('python3', [
          '-B',
          '-m',
          'unittest',
          'tool.tests.test_catalogue_phase8.CatalogueMigrationProof.$name',
          '-v',
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      });
    }
  });

  test(
    'Phase 8 representative canonical target resolves READY in real resolver',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'nubibill-phase8-resolver-',
      );
      final database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: directory.path,
      );
      try {
        final fixture = jsonDecode(
          await File('test/fixtures/phase8_representative_legacy.json')
              .readAsString(),
        ) as Map<String, dynamic>;
        final local = LocalDataSource(
          await database.open('phase8-proof', 'isolated'),
        );
        final rows = fixture['rows'] as Map<String, dynamic>;
        await local.db.transaction((tx) async {
          for (final entry in rows.entries.where(
            (e) => e.key.startsWith('local_'),
          )) {
            for (final raw in entry.value as List) {
              await tx.insert(entry.key, Map<String, Object?>.from(raw as Map));
            }
          }
        });
        final resolved =
            await ProductTemplateResolver(_LocalCatalogueReader(local))
                .resolveTemplate(
                  tenantId: 'isolated',
                  businessId: 'isolated',
                  subcategoryId: fixture['canonicalSubcategoryId'] as String,
                  categoryId: fixture['canonicalCategoryId'] as String,
                  token: 'no-network',
                );
        expect(resolved.readiness, TemplateReadinessState.ready);
        expect(resolved.categoryId, fixture['canonicalCategoryId']);
        expect(resolved.subcategoryId, fixture['canonicalSubcategoryId']);
        expect(resolved.allAttributes, isNotEmpty);
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

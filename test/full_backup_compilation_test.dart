// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

void main() {
  sqfliteFfiInit();

  test('Comprehensive Full Backup Acceptance Gate', () async {
    final winPath = r'C:\Users\SKSUM\Downloads\FirestoreBackup\firestore_complete_merged.json';
    const macPath = '/Users/sksuman/Desktop/Firebase Billing/Firestore Data Fetch/firestore_full_backup/firestore_complete_merged.json';
    final backupFile = File(Platform.environment['FIRESTORE_BACKUP_PATH'] ?? (File(winPath).existsSync() ? winPath : macPath));
    expect(backupFile.existsSync(), isTrue);

    // 1. Verify byte size and SHA-256
    final bytes = backupFile.readAsBytesSync();
    expect(bytes.length, 8019500);
    final sha256Hex = sha256.convert(bytes).toString();
    expect(
      sha256Hex,
      'ae7b20ca2a158ac451328a77bafb3c33eeeb0b97084de6f34eb182dd3b7dc583',
    );

    final jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final collections = jsonMap['collections'] as Map<String, dynamic>;

    // Verify 4,011 total documents across all 54 collections
    int totalDocCount = 0;
    for (final col in collections.values) {
      totalDocCount += (col as Map).length;
    }
    expect(totalDocCount, 4011);
    expect(collections.length, 54);

    // 2. Prepare required SYSTEM collections
    final inputDocs = <String, List<Map<String, dynamic>>>{};
    for (final colName in CatalogueContract.requiredCollections) {
      final colData = collections[colName] as Map<String, dynamic>? ?? {};
      final list = <Map<String, dynamic>>[];
      for (final entry in colData.entries) {
        final doc = entry.value as Map<String, dynamic>;
        final fields = FirestoreValueCodec.decodeFields(doc['fields']);
        if (fields['scopeType'] == 'SYSTEM') {
          if (colName == 'product_attribute_options' &&
              SystemCatalogueMetadata.redundantOptionIds.contains(entry.key)) {
            continue;
          }
          list.add({
            'name': '$colName/${entry.key}',
            'fields': FirestoreValueCodec.encodeFields(fields),
          });
        }
      }
      inputDocs[colName] = list;
    }

    // Verify active SYSTEM subcategories in raw backup
    final rawSubcategories =
        collections['product_subcategories'] as Map<String, dynamic>;
    final activeSystemSubcats = rawSubcategories.entries.where((e) {
      final f = FirestoreValueCodec.decodeFields((e.value as Map)['fields']);
      return f['scopeType'] == 'SYSTEM' && f['status'] == 'ACTIVE';
    }).toList();
    expect(activeSystemSubcats.length, 117);

    // Verify raw authored templates for the 21 explicit subcategories in backup
    final rawTemplates =
        collections['subcategory_attribute_templates'] as Map<String, dynamic>;
    final explicitTemplatesRaw = rawTemplates.entries.where((e) {
      final f = FirestoreValueCodec.decodeFields((e.value as Map)['fields']);
      return SystemCatalogueMetadata.legacyExplicitSubcategories.contains(
        f['subcategoryId'],
      );
    }).toList();
    expect(explicitTemplatesRaw.length, 268);

    // Verify Central Product Masters count in backup
    final cpms =
        collections['central_product_master_verified'] as Map<String, dynamic>;
    expect(cpms.length, 1305);

    // 3. Compile catalogue in memory
    final compiled = SystemCatalogueMetadata.compile(inputDocs);
    final decodedCompiled = CatalogueContract.decode(compiled);

    // Total subcategories and templates in compiled output
    final compiledSubcats = decodedCompiled['product_subcategories']!;
    final compiledTemplates =
        decodedCompiled['subcategory_attribute_templates']!;
    expect(compiledSubcats.length, 190);
    expect(compiledTemplates.length, 2837);

    // Active vs Inactive subcategories
    final activeCompiledSubs =
        compiledSubcats.where(CatalogueContract.active).toList();
    final inactiveCompiledSubs =
        compiledSubcats.where((s) => !CatalogueContract.active(s)).toList();
    expect(activeCompiledSubs.length, 141);
    expect(inactiveCompiledSubs.length, 49);
    expect(activeCompiledSubs.length + inactiveCompiledSubs.length, 190);

    // Verify all 117 original active SYSTEM subcategories are still present and active
    for (final rawSub in activeSystemSubcats) {
      final subId = rawSub.key;
      final match = compiledSubcats.firstWhere(
        (s) => s['id'] == subId || s['subcategoryId'] == subId,
        orElse: () => throw StateError('Missing active subcategory $subId'),
      );
      expect(
        CatalogueContract.active(match),
        isTrue,
        reason: 'Subcategory $subId should remain active',
      );
    }

    // Verify all 268 authored templates across 21 explicit subcategories are preserved
    final compiledExplicitTemplates = compiledTemplates
        .where(
          (t) => SystemCatalogueMetadata.legacyExplicitSubcategories.contains(
            t['subcategoryId'],
          ),
        )
        .toList();
    expect(compiledExplicitTemplates.length, 268);
    for (final t in compiledExplicitTemplates) {
      expect(t['status'], 'ACTIVE');
      expect(t['subcategoryId'], isNotNull);
      expect(t['attributeId'], isNotNull);
    }

    // Verify all 1,305 Central Product Masters reference valid subcategories
    final compiledSubcatIdSet = {
      for (final s in compiledSubcats) s['id'] as String,
    };
    for (final entry in cpms.entries) {
      final f = FirestoreValueCodec.decodeFields((entry.value as Map)['fields']);
      final subId = f['subcategoryId'] as String?;
      expect(subId, isNotNull, reason: 'CPM ${entry.key} missing subcategoryId');
      final exists = compiledSubcatIdSet.contains(subId);
      expect(
        exists,
        isTrue,
        reason:
            'CPM ${entry.key} references non-existent subcategory $subId in compiled catalogue',
      );
    }

    // 4. Validate catalogue readiness
    final readiness = CatalogueReadiness.validate(inputDocs);
    expect(readiness.isReady, isTrue);
    expect(readiness.errors, isEmpty);

    // 5. Import into disposable SQLite database
    final tempDir = await Directory.systemTemp.createTemp(
      'full-backup-sqlite-gate-',
    );
    try {
      final localDb = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: tempDir.path,
      );
      final db = await localDb.open('', 'acceptance-user');
      final source = LocalDataSource(db);

      await SystemCatalogueSnapshot.import(
        source: source,
        documents: inputDocs,
        readTimes: {},
      );

      // Verify row counts in SQLite tables
      final catRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM local_product_categories',
      );
      final subRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM local_product_subcategories',
      );
      final activeSubRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM local_product_subcategories WHERE status = 'ACTIVE'",
      );
      final inactiveSubRows = await db.rawQuery(
        "SELECT COUNT(*) as c FROM local_product_subcategories WHERE status != 'ACTIVE'",
      );
      final tplRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM local_subcategory_attribute_templates',
      );
      final optRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM local_product_attribute_options',
      );
      final attrRows = await db.rawQuery(
        'SELECT COUNT(*) as c FROM local_product_attributes',
      );

      print('SQLite Table Row Counts:');
      print('  local_product_categories: ${catRows.first['c']}');
      print('  local_product_subcategories total: ${subRows.first['c']}');
      print('  local_product_subcategories active: ${activeSubRows.first['c']}');
      print('  local_product_subcategories inactive: ${inactiveSubRows.first['c']}');
      print('  local_subcategory_attribute_templates: ${tplRows.first['c']}');
      print('  local_product_attribute_options: ${optRows.first['c']}');
      print('  local_product_attributes: ${attrRows.first['c']}');

      expect(subRows.first['c'], 190);
      expect(activeSubRows.first['c'], 141);
      expect(inactiveSubRows.first['c'], 49);
      expect(tplRows.first['c'], 2837);

      await localDb.close();
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}

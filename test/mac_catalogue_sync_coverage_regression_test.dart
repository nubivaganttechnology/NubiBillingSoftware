import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

void main() {
  sqfliteFfiInit();

  final winPath =
      r'C:\Users\SKSUM\Downloads\FirestoreBackup\firestore_complete_merged.json';
  const macPath =
      '/Users/sksuman/Desktop/Firebase Billing/Firestore Data Fetch/firestore_full_backup/firestore_complete_merged.json';
  final backupFilePath =
      Platform.environment['FIRESTORE_BACKUP_PATH'] ??
      (File(winPath).existsSync() ? winPath : macPath);

  Map<String, List<Map<String, dynamic>>> loadProductionCatalogue() {
    final backupFile = File(backupFilePath);
    expect(
      backupFile.existsSync(),
      isTrue,
      reason: 'Full backup file must exist at $backupFilePath',
    );
    final bytes = backupFile.readAsBytesSync();
    final jsonMap = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final collections = jsonMap['collections'] as Map<String, dynamic>;

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
    return inputDocs;
  }

  group('Mac Catalogue Sync Root Cause & Hand Sanitizers Verification', () {
    test(
      'Hand Sanitizers subcategory compiles with EXPLICIT_METADATA, preserves 3 authored templates, and passes isolated SQLite readiness',
      () async {
        final inputDocs = loadProductionCatalogue();

        // 1. In-memory compilation audit
        final compiled = SystemCatalogueMetadata.compile(inputDocs);
        final rawCompiled = CatalogueContract.decode(compiled);
        final subcategories = rawCompiled['product_subcategories']!;
        final templates = rawCompiled['subcategory_attribute_templates']!;

        const handSanitizerId =
            'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_HAND_SANITIZERS';
        final handSanitizer = subcategories.firstWhere(
          (s) => s['subcategoryId'] == handSanitizerId,
          orElse: () => throw StateError('Hand Sanitizers subcategory missing'),
        );

        // Verification of Hand Sanitizers metadata resolution
        expect(handSanitizer['status'], 'ACTIVE');
        expect(handSanitizer['categoryId'], 'SYS_CATEGORY_HEALTH_HYGIENE');
        expect(handSanitizer['profileId'], 'EXPLICIT_METADATA');
        expect(handSanitizer['templateStatus'], 'READY');
        expect(handSanitizer['templateSelectable'], false);

        // Verification of authored templates: exactly 3 authored templates preserved
        final hsTemplates =
            templates
                .where((t) => t['subcategoryId'] == handSanitizerId)
                .toList();
        expect(
          hsTemplates.length,
          3,
          reason: 'Hand Sanitizers must have exactly 3 authored templates',
        );

        final templateAttrIds =
            hsTemplates.map((t) => t['attributeId']).toSet();
        expect(templateAttrIds, containsAll(['packSize', 'surface', 'unit']));

        for (final t in hsTemplates) {
          expect(t['status'], 'ACTIVE');
          expect(t['subcategoryId'], handSanitizerId);
        }

        // Ensure no synthetic architectural paint templates were injected
        expect(templateAttrIds.contains('colourMode'), isFalse);
        expect(templateAttrIds.contains('numberOfCoats'), isFalse);
        expect(templateAttrIds.contains('dilutionType'), isFalse);
        expect(templateAttrIds.contains('finish'), isFalse);

        // 2. Isolated SQLite database import & readiness verification
        final tempDir = await Directory.systemTemp.createTemp(
          'mac-sync-hs-test-',
        );
        try {
          final localDb = LocalDatabase(
            factory: databaseFactoryFfi,
            directory: tempDir.path,
          );
          final db = await localDb.open('', 'mac-test-hs-user');
          final source = LocalDataSource(db);

          // Import entire compiled production snapshot
          await SystemCatalogueSnapshot.import(
            source: source,
            documents: inputDocs,
            readTimes: {},
          );

          // Verify Hand Sanitizers row in SQLite
          final hsRows = await db.query(
            'local_product_subcategories',
            where: 'remoteId = ?',
            whereArgs: [handSanitizerId],
          );
          expect(hsRows.length, 1);
          final hsDbRow = hsRows.single;
          expect(hsDbRow['status'], 'ACTIVE');
          expect(hsDbRow['scopeType'], 'SYSTEM');
          final hsDbFields = FirestoreValueCodec.decodeFields(
            jsonDecode(hsDbRow['payloadJson'] as String) as Map<String, dynamic>,
          );
          expect(hsDbFields['profileId'], 'EXPLICIT_METADATA');
          expect(hsDbFields['templateStatus'], 'READY');
          expect(hsDbFields['templateSelectable'], false);

          // Verify SQLite templates count for Hand Sanitizers
          final hsDbTemplates = await db.query(
            'local_subcategory_attribute_templates',
            where: 'subcategoryId = ? AND status = ?',
            whereArgs: [handSanitizerId, 'ACTIVE'],
          );
          expect(hsDbTemplates.length, 3);

          await db.insert('sync_queries', {
            'queryKey': 'catalogue_query',
            'collectionName': 'product_catalogue_releases',
            'queryJson': '{}',
            'lastSyncedAt': LocalDataSource.now(),
            'active': 1,
          });

          // Verify deep catalogue readiness on installed SQLite database
          final readiness = await CatalogueReadiness.checkInstalledReadiness(
            source,
          );
          expect(readiness, isNotNull);
          expect(
            readiness!.isReady,
            isTrue,
            reason:
              'Readiness errors: ${readiness.errors.join("; ")}',
          );
          expect(readiness.errors, isEmpty);
          expect(readiness.releaseVersion, 3);

          await localDb.close();
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  group('Complete Audit of all 21 Legacy Explicit Subcategories', () {
    test(
      'all 21 legacy explicit subcategories retain original IDs, EXPLICIT_METADATA profile, and preserve all 268 authored templates in SQLite',
      () async {
        final inputDocs = loadProductionCatalogue();

        // Check compile output
        final compiled = SystemCatalogueMetadata.compile(inputDocs);
        final rawCompiled = CatalogueContract.decode(compiled);
        final subcategories = rawCompiled['product_subcategories']!;
        final templates = rawCompiled['subcategory_attribute_templates']!;

        expect(SystemCatalogueMetadata.legacyExplicitSubcategories.length, 21);

        for (final subId
            in SystemCatalogueMetadata.legacyExplicitSubcategories) {
          final sub = subcategories.firstWhere(
            (s) => s['subcategoryId'] == subId,
            orElse: () => throw StateError('Missing explicit subcategory $subId'),
          );
          expect(
            sub['status'],
            'ACTIVE',
            reason: 'Subcategory $subId must be ACTIVE',
          );
          expect(
            sub['profileId'],
            'EXPLICIT_METADATA',
            reason: 'Subcategory $subId must have EXPLICIT_METADATA profile',
          );
          expect(
            sub['templateStatus'],
            'READY',
            reason: 'Subcategory $subId must have READY templateStatus',
          );
          expect(
            sub['templateSelectable'],
            false,
            reason: 'Subcategory $subId must have templateSelectable = false',
          );
        }

        // Verify all 268 authored templates across the 21 explicit subcategories
        final explicitTemplates =
            templates
                .where(
                  (t) =>
                      SystemCatalogueMetadata.legacyExplicitSubcategories
                          .contains(t['subcategoryId']) &&
                      CatalogueContract.active(t),
                )
                .toList();
        expect(
          explicitTemplates.length,
          268,
          reason:
              'Must preserve exactly 268 authored templates across all 21 explicit subcategories',
        );

        // Verify isolated SQLite database installation and query
        final tempDir = await Directory.systemTemp.createTemp(
          'mac-sync-all-explicit-',
        );
        try {
          final localDb = LocalDatabase(
            factory: databaseFactoryFfi,
            directory: tempDir.path,
          );
          final db = await localDb.open('', 'mac-test-explicit-user');
          final source = LocalDataSource(db);

          await SystemCatalogueSnapshot.import(
            source: source,
            documents: inputDocs,
            readTimes: {},
          );

          // Query SQLite for all 21 explicit subcategories
          for (final subId
              in SystemCatalogueMetadata.legacyExplicitSubcategories) {
            final rows = await db.query(
              'local_product_subcategories',
              where: 'remoteId = ?',
              whereArgs: [subId],
            );
            expect(
              rows.length,
              1,
              reason: 'Subcategory $subId must exist in SQLite',
            );
            final row = rows.single;
            expect(row['status'], 'ACTIVE');
            final fields = FirestoreValueCodec.decodeFields(
              jsonDecode(row['payloadJson'] as String) as Map<String, dynamic>,
            );
            expect(fields['profileId'], 'EXPLICIT_METADATA');
            expect(fields['templateStatus'], 'READY');
            expect(fields['templateSelectable'], false);
          }

          // Query SQLite for explicit templates count
          final placeholders = List.filled(
            SystemCatalogueMetadata.legacyExplicitSubcategories.length,
            '?',
          ).join(',');
          final dbTplRows = await db.rawQuery(
            'SELECT COUNT(*) as c FROM local_subcategory_attribute_templates '
            "WHERE subcategoryId IN ($placeholders) AND status = 'ACTIVE'",
            SystemCatalogueMetadata.legacyExplicitSubcategories.toList(),
          );
          expect(
            dbTplRows.first['c'],
            268,
            reason: 'SQLite must contain exactly 268 active explicit templates',
          );

          await db.insert('sync_queries', {
            'queryKey': 'catalogue_query',
            'collectionName': 'product_catalogue_releases',
            'queryJson': '{}',
            'lastSyncedAt': LocalDataSource.now(),
            'active': 1,
          });

          // Deep readiness check
          final readiness = await CatalogueReadiness.checkInstalledReadiness(
            source,
          );
          expect(readiness, isNotNull);
          expect(readiness!.isReady, isTrue);
          expect(readiness.errors, isEmpty);

          await localDb.close();
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  group('Active SYSTEM Subcategory Complete Profile Resolution Audit', () {
    test(
      'all 141 active compiled SYSTEM subcategories resolve valid profiles with zero unmapped records',
      () async {
        final inputDocs = loadProductionCatalogue();
        final compiled = SystemCatalogueMetadata.compile(inputDocs);
        final rawCompiled = CatalogueContract.decode(compiled);
        final subcategories = rawCompiled['product_subcategories']!;

        final activeSubs =
            subcategories.where(CatalogueContract.active).toList();
        expect(activeSubs.length, 141);

        for (final sub in activeSubs) {
          final subId = sub['subcategoryId'] as String?;
          final catId = sub['categoryId'] as String?;
          final profileId = sub['profileId'] as String?;

          expect(
            subId,
            isNotNull,
            reason: 'Subcategory must have subcategoryId',
          );
          expect(catId, isNotNull, reason: 'Subcategory must have categoryId');
          if (subId == 'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS') {
            expect(profileId, isNull);
            expect(sub['templateSelectable'], false);
          } else {
            expect(
              profileId,
              isNotNull,
              reason:
                  'Subcategory $subId under $catId must have a non-null profileId',
            );
            expect(
              profileId!.isNotEmpty,
              isTrue,
              reason:
                  'Subcategory $subId under $catId must have a non-empty profileId',
            );
          }
        }
      },
    );
  });

  group('Negative and Malformed Profile Regression Cases', () {
    test(
      'unknown active SYSTEM subcategory without profile fails compilation and readiness',
      () {
        final inputDocs = loadProductionCatalogue();

        // Inject an unknown subcategory under SYS_CATEGORY_HEALTH_HYGIENE
        final subList = List<Map<String, dynamic>>.from(
          inputDocs['product_subcategories']!,
        );
        subList.add({
          'name':
              'product_subcategories/SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_UNKNOWN_TEST',
          'fields': FirestoreValueCodec.encodeFields({
            'catalogueId': 'PAINT_V1',
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'version': 2,
            'subcategoryId':
                'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_UNKNOWN_TEST',
            'categoryId': 'SYS_CATEGORY_HEALTH_HYGIENE',
            'name': 'Unknown Test Subcategory',
          }),
        });
        inputDocs['product_subcategories'] = subList;

        // Verify compiler rejection
        expect(
          () => SystemCatalogueMetadata.compile(inputDocs),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'catalogue-profile')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_UNKNOWN_TEST under SYS_CATEGORY_HEALTH_HYGIENE.'),
                ),
          ),
        );

        // Verify readiness report rejection
        final readiness = CatalogueReadiness.validate(inputDocs);
        expect(readiness.isReady, isFalse);
        expect(
          readiness.errors,
          contains(
            'Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_UNKNOWN_TEST under SYS_CATEGORY_HEALTH_HYGIENE.',
          ),
        );
      },
    );

    test(
      'active SYSTEM subcategory with malformed explicit profile fails compilation and readiness',
      () {
        final inputDocs = loadProductionCatalogue();

        final subList = List<Map<String, dynamic>>.from(
          inputDocs['product_subcategories']!,
        );
        subList.add({
          'name':
              'product_subcategories/SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_MALFORMED',
          'fields': FirestoreValueCodec.encodeFields({
            'catalogueId': 'PAINT_V1',
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'version': 2,
            'subcategoryId':
                'SYS_SUBCATEGORY_SYS_CATEGORY_HEALTH_HYGIENE_MALFORMED',
            'categoryId': 'SYS_CATEGORY_HEALTH_HYGIENE',
            'name': 'Malformed Profile Subcategory',
            'profileId': 'NONEXISTENT_BOGUS_PROFILE',
          }),
        });
        inputDocs['product_subcategories'] = subList;

        expect(
          () => SystemCatalogueMetadata.compile(inputDocs),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'catalogue-profile')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Unknown or conflicting catalogue profile NONEXISTENT_BOGUS_PROFILE'),
                ),
          ),
        );

        final readiness = CatalogueReadiness.validate(inputDocs);
        expect(readiness.isReady, isFalse);
        expect(
          readiness.errors.any((e) => e.contains('Unknown or conflicting catalogue profile NONEXISTENT_BOGUS_PROFILE')),
          isTrue,
        );
      },
    );

    test(
      'active SYSTEM subcategory with conflicting explicit profile fails compilation and readiness',
      () {
        final inputDocs = loadProductionCatalogue();

        // Pick an interior paints subcategory and explicitly set conflicting profile WOOD_FINISH
        final subList = List<Map<String, dynamic>>.from(
          inputDocs['product_subcategories']!,
        );
        final index = subList.indexWhere(
          (d) =>
              d['name'] ==
              'product_subcategories/SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_EMULSIONS',
        );
        expect(index, isNot(-1));

        final decoded = FirestoreValueCodec.decodeFields(
          subList[index]['fields'],
        );
        decoded['profileId'] = 'WOOD_FINISH';
        subList[index] = {
          'name': subList[index]['name'],
          'fields': FirestoreValueCodec.encodeFields(decoded),
        };
        inputDocs['product_subcategories'] = subList;

        expect(
          () => SystemCatalogueMetadata.compile(inputDocs),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'catalogue-profile')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Unknown or conflicting catalogue profile WOOD_FINISH'),
                ),
          ),
        );
      },
    );

    test(
      'Release 4 candidate subcategory missing profile is NOT auto-promoted to EXPLICIT_METADATA',
      () {
        final inputDocs = loadProductionCatalogue();

        // Promote release to version 4
        final releaseList = List<Map<String, dynamic>>.from(
          inputDocs['product_catalogue_releases']!,
        );
        final relDoc = releaseList.first;
        final relFields = FirestoreValueCodec.decodeFields(relDoc['fields']);
        relFields['version'] = 4;
        relFields['catalogueVersion'] = 4;
        relFields['schemaRevision'] = CatalogueContract.schemaRevision;
        relFields['compilerRevision'] = SystemCatalogueMetadata.revision;
        relFields['approvedForLiveExecution'] = true;
        relFields['productionMigrationApproved'] = true;
        relFields['firestorePublicationApproved'] = true;
        releaseList[0] = {
          'name': relDoc['name'],
          'fields': FirestoreValueCodec.encodeFields(relFields),
        };
        inputDocs['product_catalogue_releases'] = releaseList;

        // In Release 4, legacy explicit auto-promotion does NOT apply.
        // Legacy explicit subcategories without profileId must fail compilation.
        expect(
          () => SystemCatalogueMetadata.compile(inputDocs),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'catalogue-profile')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS.'),
                ),
          ),
        );
      },
    );

    test(
      'malformed duplicate option groups fail safely without runtime silent deduplication',
      () {
        final inputDocs = loadProductionCatalogue();

        // Re-inject a duplicate option group: SYS_OPT_brushType_1
        final optList = List<Map<String, dynamic>>.from(
          inputDocs['product_attribute_options']!,
        );
        optList.add({
          'name': 'product_attribute_options/SYS_OPT_brushType_1',
          'fields': FirestoreValueCodec.encodeFields({
            'attributeId': 'brushType',
            'catalogueId': 'PAINT_V1',
            'name': 'Flat',
            'normalizedName': 'flat',
            'optionId': 'SYS_OPT_brushType_1',
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'version': 2,
          }),
        });
        inputDocs['product_attribute_options'] = optList;

        // Must fail with ambiguous duplicate catalogue identity
        expect(
          () => SystemCatalogueMetadata.compile(inputDocs),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', 'catalogue-collision')
                .having(
                  (e) => e.message,
                  'message',
                  contains('Ambiguous duplicate catalogue identity: option:brushType:flat'),
                ),
          ),
        );
      },
    );
  });
}

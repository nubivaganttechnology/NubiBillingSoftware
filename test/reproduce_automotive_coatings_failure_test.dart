import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

void main() {
  test('reproduce Legacy Release 3 AUTOMOTIVE_COATINGS compile failure', () {
    final rows = jsonDecode(
      File('test/fixtures/system_catalogue_v4.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final fixture = {
      for (final entry in rows.entries)
        entry.key: [
          for (final raw in (entry.value as List).cast<Map>())
            {
              'name': '${entry.key}/${raw['id']}',
              'fields': FirestoreValueCodec.encodeFields(
                Map<String, dynamic>.from(raw)..remove('id'),
              ),
            },
        ],
    };

    // Transform fixture into Legacy Release 3:
    // 1. Release version 3, compilerRevision 0
    final release = fixture['product_catalogue_releases']!.single;
    final releaseFields = FirestoreValueCodec.decodeFields(release['fields']);
    releaseFields['catalogueVersion'] = 3;
    releaseFields['version'] = 3;
    releaseFields['compilerRevision'] = 0;
    releaseFields['sourceCompilerRevision'] = 0;
    releaseFields['isolatedOnly'] = false;
    releaseFields['approvedForLiveExecution'] = true;
    releaseFields['productionMigrationApproved'] = true;
    releaseFields['firestorePublicationApproved'] = true;
    release['fields'] = FirestoreValueCodec.encodeFields(releaseFields);

    // 1. Verify profileFor throws the exact observed error when profileId is missing:
    expect(
      () => SystemCatalogueMetadata.profileFor(
        'SYS_CATEGORY_AUTOMOTIVE_COATINGS',
        'SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS',
      ),
      throwsA(
        isA<AppException>()
            .having((e) => e.code, 'code', 'catalogue-profile')
            .having(
              (e) => e.message,
              'message',
              contains(
                'Explicit profile required for SYS_SUBCATEGORY_SYS_CATEGORY_AUTOMOTIVE_COATINGS_AUTOMOTIVE_COATINGS under SYS_CATEGORY_AUTOMOTIVE_COATINGS',
              ),
            ),
      ),
    );
  });
}

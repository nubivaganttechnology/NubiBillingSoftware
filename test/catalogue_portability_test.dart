import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/catalogue/catalogue_readiness.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/services/firestore_value_codec.dart';

void main() {
  late Map<String, List<Map<String, dynamic>>> fixture;

  setUpAll(() {
    final rows = jsonDecode(
      File('test/fixtures/system_catalogue_v4.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    fixture = {
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
    // The checked-in v4 content is a review candidate, not a live publication.
    // Tests exercise structure only, so mark this in-memory copy publishable.
    final release = fixture['product_catalogue_releases']!.single;
    final fields = FirestoreValueCodec.decodeFields(release['fields']);
    fields
      ..['isolatedOnly'] = false
      ..['approvedForLiveExecution'] = true
      ..['productionMigrationApproved'] = true
      ..['firestorePublicationApproved'] = true;
    release['fields'] = FirestoreValueCodec.encodeFields(fields);
  });

  test('compiler preserves an explicit DIY_KITS profile from the snapshot', () {
    final compiled = SystemCatalogueMetadata.compile(fixture);
    final diy = FirestoreValueCodec.decodeFields(
      compiled['product_subcategories']!
          .singleWhere(
            (doc) => doc['name'].toString().endsWith(
              'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS',
            ),
          )['fields'],
    );
    expect(diy['profileId'], 'EXPLICIT_METADATA');
  });

  test('compiler does not guess a missing DIY_KITS profile', () {
    expect(
      () => SystemCatalogueMetadata.profileFor(
        'SYS_CATEGORY_DIY_AEROSOLS',
        'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS',
      ),
      throwsA(
        isA<AppException>().having(
          (error) => error.code,
          'code',
          'catalogue-profile',
        ),
      ),
    );
  });

  test('validates a complete fresh-install catalogue snapshot', () {
    final report = CatalogueReadiness.validate(fixture);

    expect(report.state, CatalogueReadinessState.ready, reason: '${report.errors}');
    expect(report.releaseVersion, 4);
    expect(report.errors, isEmpty);
  });

  test('rejects a DIY_KITS row with missing profile metadata', () {
    final invalid = _clone(fixture);
    final doc = invalid['product_subcategories']!.singleWhere(
      (doc) => doc['name'].toString().endsWith('_DIY_KITS'),
    );
    final fields = FirestoreValueCodec.decodeFields(doc['fields']);
    fields.remove('profileId');
    doc['fields'] = FirestoreValueCodec.encodeFields(fields);

    final report = CatalogueReadiness.validate(invalid);

    expect(report.state, CatalogueReadinessState.failed);
    expect(report.errors.join(' '), contains('Explicit profile required'));
  });

  test('rejects unsupported DIY_KITS profile metadata', () {
    final invalid = _clone(fixture);
    final doc = invalid['product_subcategories']!.singleWhere(
      (row) => row['name'].toString().endsWith('_DIY_KITS'),
    );
    final fields = FirestoreValueCodec.decodeFields(doc['fields']);
    fields['profileId'] = 'OTHER_DOMAIN_REVIEW';
    doc['fields'] = FirestoreValueCodec.encodeFields(fields);

    final report = CatalogueReadiness.validate(invalid);

    expect(report.state, CatalogueReadinessState.failed);
    expect(report.errors.join(' '), contains('Unknown or conflicting catalogue profile'));
  });

  test('diagnostics expose configuration presence, never secret values', () {
    final diagnostics = EnvironmentConfig.diagnostics();

    expect(diagnostics['requiredDefines'], contains('FIREBASE_PROJECT_ID'));
    expect(diagnostics, containsPair('firebaseProjectId', '(unset)'));
    expect(diagnostics.keys, isNot(contains('apiKey')));
    expect(diagnostics.keys, isNot(contains('FIREBASE_API_KEY')));
  });
}

Map<String, List<Map<String, dynamic>>> _clone(
  Map<String, List<Map<String, dynamic>>> value,
) => {
  for (final entry in value.entries)
    entry.key: [
      for (final doc in entry.value)
        {
          'name': doc['name'],
          'fields': FirestoreValueCodec.encodeFields(
            FirestoreValueCodec.decodeFields(doc['fields']),
          ),
        },
    ],
};

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/catalogue/catalogue_contract.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';

import 'support/phase10e_release.dart';

void main() {
  final fixture = Phase10EFixture();
  setUpAll(fixture.open);
  tearDownAll(fixture.close);

  for (final entry in {
    liquidBasement: ['Litre', 'Millilitre'],
    cementitiousBasement: ['Kilogram', 'Gram'],
  }.entries) {
    test('Basement ${entry.key} has one dimension and no selling default', () async {
      final candidate = phase10eCandidates.singleWhere(
        (c) => c['canonicalId'] == entry.key,
      );
      final template = await fixture.resolve(candidate);
      final rules = template.unitRules;
      expect(rules.allowedPackUnits, entry.value);
      expect(rules.allowedBaseUnits, entry.value);
      expect(rules.allowedSellingUnits, entry.value);
      expect(rules.defaultPackUnit, entry.value.first);
      expect(rules.defaultBaseUnit, entry.value.first);
      expect(rules.defaultSellingUnit, isNull);
      expect(rules.conversionAllowed, false);
      expect(
        rules.allowedBaseUnits.map(rules.dimensionOf).toSet(),
        hasLength(1),
      );
      final other = entry.key == liquidBasement ? 'Kilogram' : 'Litre';
      expect(
        rules.allows(Phase10EFixture.unitId(other), rules.allowedBaseUnits),
        false,
      );
      for (final field in ['packUnitId', 'commercialUnitId', 'baseUnitId']) {
        final state = fixture.state(template);
        final variant = (state['variants'] as List).single as Map;
        variant[field] = Phase10EFixture.unitId(other);
        if (field == 'baseUnitId') variant['_packaging'] = true;
        final result = await fixture.validate(state);
        expect(result.isValid, false);
        expect(
          result.errors.any(
            (e) => e.code == 'UNIT_NOT_ALLOWED' && e.field == field,
          ),
          true,
          reason:
              '$field must reject the other Basement dimension: ${result.errors}',
        );
      }
      final converted = fixture.state(template, converting: true);
      final rejected = await fixture.validate(converted);
      expect(
        rejected.errors.any((e) => e.code == 'CONVERSION_NOT_ALLOWED'),
        true,
      );
    });
  }

  test(
    'actual imported rows match release and have zero active orphans',
    () async {
      for (final entry in release4Rows().entries) {
        final documents = await fixture.local.query(entry.key, []);
        expect(documents.length, entry.value.length);
        expect(
          documents.map((d) => (d['name'] as String).split('/').last).toSet(),
          entry.value.map((r) => r['id']).toSet(),
        );
        for (final doc in documents) {
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          expect(
            fields[CatalogueContract.idFields[entry.key]],
            (doc['name'] as String).split('/').last,
          );
        }
      }
      expect(
        await fixture.local.db.rawQuery(r'''
      SELECT t.remoteId FROM local_subcategory_attribute_templates t
      LEFT JOIN local_product_subcategories s ON t.subcategoryId=s.remoteId AND s.status='ACTIVE' AND s.isDeleted=0
      LEFT JOIN local_product_attributes a ON t.attributeId=a.remoteId AND a.status='ACTIVE' AND a.isDeleted=0
      WHERE t.status='ACTIVE' AND t.isDeleted=0 AND (s.remoteId IS NULL OR a.remoteId IS NULL)
    '''),
        isEmpty,
      );
      expect(
        await fixture.local.db.rawQuery(r'''
      SELECT categoryId,lower(trim(json_extract(payloadJson,'$.name.stringValue'))) FROM local_product_subcategories
      WHERE status='ACTIVE' AND isDeleted=0 GROUP BY categoryId,lower(trim(json_extract(payloadJson,'$.name.stringValue'))) HAVING COUNT(*)>1
    '''),
        isEmpty,
      );
    },
  );

  test('captured installed SYSTEM preimage confirms actual snapshot retirement interlock only in isolated SQLite', () async {
    final diff = jsonDecode(
      File('docs/phase10e-installed-v3-v4-diff.json').readAsStringSync(),
    ) as Map;
    expect(diff['productionInstallationAllowed'], false);
    final entries = (diff['entries'] as List).cast<Map<String, dynamic>>();
    final replay = Phase10EFixture();
    await replay.open(importRelease: false);
    addTearDown(replay.close);
    // Repository-generated read-only evidence, never a production connection.
    for (final collection in release4Rows().keys) {
      await replay.local.upsertRemote(collection, [
        for (final e in entries.where(
          (e) => e['collection'] == collection && e['beforeFields'] != null,
        ))
          {
            'name': '$collection/${e['documentId']}',
            'fields': FirestoreRestService.encodeFields(
              e['beforeFields'] as Map<String, dynamic>,
            ),
          },
      ]);
    }
    await SystemCatalogueSnapshot.import(
      source: replay.local,
      documents: release4Documents(),
      readTimes: const {},
      allowUnapprovedIsolatedForTests: true,
    );
    var inactive = 0;
    for (final e in entries) {
      final row = await replay.local.row(
        e['collection'] as String,
        e['documentId'] as String,
      );
      expect(row, isNotNull);
      final fields = FirestoreRestService.decodeFields(
        jsonDecode(row!['payloadJson'] as String),
      );
      if (e['action'] == 'DEACTIVATE') {
        expect(fields['status'], 'INACTIVE', reason: '${e['documentId']}');
        expect(row['isDeleted'], 0);
        inactive++;
      } else if (e['action'] == 'INSERT' || e['action'] == 'REPLACE') {
        expect(fields['status'], 'ACTIVE');
      } else {
        fail(
          'Captured preimage changed; re-review interlock action ${e['action']}',
        );
      }
      expect(e['approved'], false);
      expect(e['migrationApproved'], false);
      expect(e['retirementApproved'], false);
    }
    expect(inactive, (diff['counts'] as Map)['actions']['DEACTIVATE']);
    expect(await replay.local.db.query('local_products'), isEmpty);
    expect(await replay.local.db.query('local_product_variants'), isEmpty);
    expect(await replay.local.db.query('sync_outbox'), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

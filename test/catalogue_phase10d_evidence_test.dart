import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/sync/sync_query_registry.dart';

import 'support/phase10c_model.dart';

void main() {
  final evidence = jsonDecode(
    File('docs/phase10d-basement-evidence.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final canonicalId = evidence['candidateId'] as String;
  final legacyId = evidence['historicalPayloadId'] as String;
  final candidate = phase10cCandidates.singleWhere(
    (d) => d['canonicalId'] == canonicalId,
  );
  final fixture = Phase10CFixture();
  setUpAll(fixture.open);
  tearDownAll(fixture.close);

  Set<String> dimensions(List<dynamic> units) => {
    for (final unit in units)
      if (unit == 'Litre' || unit == 'Millilitre')
        'VOLUME'
      else if (unit == 'Kilogram' || unit == 'Gram')
        'MASS',
  };

  test('Basement mixed evidence cannot establish one material or distinct products', () {
    final profile =
        (evidence['currentSubcategory']['fields']['templateProfile'] as Map);
    expect(dimensions(profile['allowedUnits'] as List), {'MASS', 'VOLUME'});
    expect(profile['defaults']['unit'], 'Litre');
    for (final field in [
      'materialForm',
      'physicalForm',
      'materialDimension',
      'measurementDimension',
    ]) {
      expect(profile.containsKey(field), false);
    }
    for (final id in [canonicalId, legacyId]) {
      expect(evidence['referencesById'][id]['productReferences'], 0);
      final group = evidence['templateGroups'][id] as List;
      final unit = group.singleWhere(
        (r) => r['fields']['attributeId'] == 'unit',
      );
      expect(dimensions(unit['fields']['options'] as List), {'MASS', 'VOLUME'});
    }
    expect(evidence['classification'], 'INSUFFICIENT_EVIDENCE');
    expect((evidence['rejectedConclusions'] as Map).keys.toSet(), {
      'VOLUME',
      'MASS',
      'DISTINCT_PRODUCTS_REQUIRED',
    });
  });

  test('Basement still fails actual resolver readiness and release gate stays closed', () async {
    final resolved = await fixture.resolve(candidate);
    expect(resolved.readiness, TemplateReadinessState.invalid);
    expect(resolved.unitRules.allowedPackUnits, isEmpty);
    expect(resolved.unitRules.allowedBaseUnits, isEmpty);
    expect(resolved.unitRules.conversionAllowed, false);
    expect(
      resolved.diagnostics.any(
        (d) => d.code == 'DOMAIN_REVIEW_REQUIRED' && d.severity == 'ERROR',
      ),
      true,
    );
    expect(candidate['intendedSelectability'], 'DOMAIN_REVIEW_REQUIRED');
    expect(evidence['basementReady'], false);
    expect(evidence['release4Generated'], false);
    expect(evidence['approvedForLiveExecution'], false);
    expect(evidence['migrationApproved'], false);
    expect(
      await fixture.local.db.query('local_product_catalogue_releases'),
      isEmpty,
    );
  });

  test('Basement document and historical groups are separate, with independent options', () {
    final groups = evidence['templateGroups'] as Map;
    for (final id in [canonicalId, legacyId]) {
      final rows = groups[id] as List;
      expect(rows, hasLength(14));
      expect(rows.every((r) => r['fields']['subcategoryId'] == id), true);
      expect(rows.every((r) => r['active'] == true), true);
    }
    List<dynamic> optionsFor(String id) =>
        (groups[id] as List).singleWhere(
              (r) => r['fields']['attributeId'] == 'unit',
            )['fields']['options']
            as List;
    expect(optionsFor(canonicalId), contains('Gram'));
    expect(optionsFor(legacyId), isNot(contains('Gram')));
    expect(
      candidate['sourceEvidence']['templateGroupSource'],
      'CURRENT_DOCUMENT_TEMPLATE_GROUP',
    );
    expect(candidate['sourceEvidence']['installedPayloadId'], legacyId);
    expect(
      (candidate['attributes'] as List).any(
        (a) => a['attributeId'] == 'dilutionType',
      ),
      false,
    );
  });

  test('committed content evidence is preserved and archived fixture has no Basement source', () {
    final paths = [
      'docs/phase10a-catalogue-audit.json',
      'docs/phase10b-intended-catalogue.json',
      'docs/phase10c-canonical-content.json',
      'test/fixtures/system_catalogue_v3.json',
    ];
    final hashes = Process.runSync('python3', [
      '-B',
      '-c',
      'import hashlib,json,sys; from pathlib import Path; print(json.dumps({p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in sys.argv[1:]}))',
      ...paths,
    ]);
    expect(hashes.exitCode, 0, reason: '${hashes.stderr}');
    final actualHashes = jsonDecode(hashes.stdout as String) as Map;
    for (final path in paths) {
      final source = (evidence['inspectedSourceFiles'] as List).singleWhere(
        (r) => r['path'] == path,
      );
      expect(actualHashes[path], source['sha256']);
    }
    expect(
      evidence['canonicalContentFingerprint'],
      phase10cModel['fingerprint'],
    );
    final archive = jsonDecode(
      File('test/fixtures/system_catalogue_v3.json').readAsStringSync(),
    ) as Map;
    for (final records in archive.values) {
      expect(
        (records as List).any(
          (r) =>
              jsonEncode(r).contains(canonicalId) ||
              jsonEncode(r).contains(legacyId),
        ),
        false,
      );
    }
    expect(
      evidence['compilerEvidence']['basementSpecificMaterialDeclaration'],
      false,
    );
    expect(evidence['archivedFixture']['basementRecords'], 0);
  });

  test('protected historical query blocks registration without alias rewrite in temporary SQLite', () async {
    final spec = <String, dynamic>{'subcategoryId': legacyId};
    await fixture.local.db.insert('sync_queries', {
      'queryKey': 'phase10d-historical-probe',
      'collectionName': 'subcategory_attribute_templates',
      'queryJson': jsonEncode(spec),
      'active': 1,
    });
    final before = await fixture.local.db.query('sync_queries');
    final audit = await SyncQueryRegistry.auditLegacy(fixture.local.db);
    expect(audit.single['legacyIds'], [legacyId]);
    expect(audit.single['disposition'], startsWith('BLOCK_MIGRATION'));
    await expectLater(
      SyncQueryRegistry.upsert(
        fixture.local.db,
        'subcategory_attribute_templates',
        spec,
      ),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          'legacy-query-reference',
        ),
      ),
    );
    expect(await fixture.local.db.query('sync_queries'), before);
    expect(await fixture.local.db.query('sync_outbox'), isEmpty);
    expect(
      (evidence['duplicateMigrationInterlock'] as List).every(
        (d) => d['approved'] == false && d['migrationApproved'] == false,
      ),
      true,
    );
  });
}

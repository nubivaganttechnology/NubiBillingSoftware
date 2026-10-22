import 'dart:convert';
import 'dart:io';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// These assertions cover the preserved Phase 10A historical audit export.
/// They intentionally do not inspect a developer's local account database or
/// claim that this unapproved snapshot is the currently published catalogue.
void main() {
  late Map<String, dynamic> audit;

  setUpAll(() {
    audit = jsonDecode(
      File('test/fixtures/phase10a_catalogue_audit_summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('preserves the historical 149-row classification evidence', () {
    expect(audit['source'], 'docs/phase10a-catalogue-audit.json');
    expect(audit['sourceCommit'], '5ef897f');
    expect(audit['approvedForLiveExecution'], false);
    expect(audit['activeRows'], 149);
    expect(audit['classificationCounts'], {
      'MISSING_TEMPLATE': 1,
      'SELECTABLE_READY': 37,
      'DUPLICATE_REVIEW': 20,
      'OTHER_DOMAIN_REVIEW': 87,
      'UNAVAILABLE': 1,
      'BUSINESS_SCOPE_EXCLUDED': 1,
      'IDENTITY_MISMATCH_REVIEW': 2,
    });
    final counts = (audit['classificationCounts'] as Map).values.cast<int>();
    expect(counts.reduce((a, b) => a + b), audit['activeRows']);
  });

  test('preserves disabled, mismatched and duplicate historical evidence', () {
    expect(audit['disabledFlags'], 88);
    expect(audit['duplicateGroupCount'], 10);
    expect(audit['duplicateReviewRows'], 20);
    expect(audit['duplicateGroups'], hasLength(10));
    expect(
      audit['duplicateGroups'],
      contains(equals([
        'SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES',
        'SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES',
      ])),
    );
    expect(audit['disabledDispositionCounts'], {
      'PROBABLY_SHOULD_BE_SELECTABLE': 87,
      'DOMAIN_REVIEW_REQUIRED': 1,
    });
    expect(audit['identityMismatches'], {
      'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS':
          'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS',
      'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING':
          'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT',
    });
  });

  test('historical audit export remains present and provenance checked', () {
    final source = File('docs/phase10a-catalogue-audit.json').readAsBytesSync();
    expect(audit['sourceSha256'], '2b5c73714b4038d82d5938d8790e57c503036c61d50decb4d47fdf191690bba7');
    // Changing the export requires an explicit audit review and regenerated
    // summary. Its full digest is recorded above for external verification.
    expect(source, isNotEmpty);
    expect(sha256.convert(source).toString(), audit['sourceSha256']);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Phase 10A closure audit is historical evidence, not a live catalogue
/// validation. Its original account database is not a portable test input.
void main() {
  test('historical full-catalogue audit retains its recorded closure totals', () {
    final summary = jsonDecode(
      File('test/fixtures/phase10a_catalogue_audit_summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(summary['source'], 'docs/phase10a-catalogue-audit.json');
    expect(summary['sourceCommit'], '5ef897f');
    expect(summary['sourceSha256'], '2b5c73714b4038d82d5938d8790e57c503036c61d50decb4d47fdf191690bba7');
    expect(summary['approvedForLiveExecution'], isFalse);
    expect(summary['activeRows'], 149);
    expect(summary['eligibleRecords'], 59);
    expect(summary['selectableEntries'], 49);
    expect(summary['eligibleCategories'], 15);

    final classifications = (summary['classificationCounts'] as Map).values
        .cast<int>();
    expect(classifications.reduce((a, b) => a + b), summary['activeRows']);
  });
}

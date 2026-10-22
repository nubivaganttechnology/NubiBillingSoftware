import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final discovered = Process.runSync('python3', [
    '-B',
    '-c',
    'import json,unittest; from tool.tests.test_catalogue_phase10a import '
        'CatalogueIntentProof; print(json.dumps(unittest.TestLoader()'
        '.getTestCaseNames(CatalogueIntentProof)))',
  ]);
  if (discovered.exitCode != 0) {
    throw StateError('Cannot discover Phase 10A proofs: ${discovered.stderr}');
  }
  final names = (jsonDecode(discovered.stdout as String) as List)
      .cast<String>();
  group('Phase 10A catalogue intent evidence', () {
    for (final name in names) {
      test(name.replaceFirst('test_', '').replaceAll('_', ' '), () async {
        final result = await Process.run('python3', [
          '-B',
          '-m',
          'unittest',
          'tool.tests.test_catalogue_phase10a.CatalogueIntentProof.$name',
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
}

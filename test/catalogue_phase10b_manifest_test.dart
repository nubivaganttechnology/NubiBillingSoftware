import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final discovered = Process.runSync('python3', [
    '-B',
    '-c',
    'import json,unittest; from tool.tests.test_catalogue_phase10b import '
        'CatalogueIntentNormalizationProof; print(json.dumps(unittest.TestLoader()'
        '.getTestCaseNames(CatalogueIntentNormalizationProof)))',
  ]);
  if (discovered.exitCode != 0) throw StateError('${discovered.stderr}');
  for (final name
      in (jsonDecode(discovered.stdout as String) as List).cast<String>()) {
    test('Phase 10B ${name.replaceAll('_', ' ')}', () async {
      final result = await Process.run('python3', [
        '-B',
        '-m',
        'unittest',
        'tool.tests.test_catalogue_phase10b.CatalogueIntentNormalizationProof.$name',
        '-v',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}

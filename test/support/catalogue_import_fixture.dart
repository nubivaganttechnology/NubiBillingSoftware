import 'dart:convert';
import 'dart:io';

/// A reviewed *test-only* successor manifest. The archived v3 fixture retains
/// its malformed duplicate option records and is separately tested as rejected.
/// These explicit exclusions do not approve or execute any live ID migration.
Map<String, dynamic> catalogueImportFixture({bool archived = false}) {
  final raw = Map<String, dynamic>.from(
    jsonDecode(
      File('test/fixtures/system_catalogue_v3.json').readAsStringSync(),
    ) as Map,
  );
  if (!archived) {
    const redundantOptionIds = {
      'SYS_OPT_brushType_1',
      'SYS_OPT_brushType_2',
      'SYS_OPT_brushType_3',
      'SYS_OPT_brushType_4',
      'SYS_OPT_brushType_5',
      'SYS_OPT_brushType_6',
      'SYS_OPT_bristleMaterial_1',
      'SYS_OPT_bristleMaterial_2',
      'SYS_OPT_bristleMaterial_3',
      'SYS_OPT_bristleMaterial_4',
      'SYS_OPT_bristleMaterial_5',
    };
    (raw['product_attribute_options'] as List).removeWhere(
      (r) => redundantOptionIds.contains(r['id']),
    );
  }
  return raw;
}

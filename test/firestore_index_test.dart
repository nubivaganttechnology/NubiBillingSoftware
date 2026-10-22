import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outlet_products pull query (tenant+business+updatedAt) has an index', () {
    final json = jsonDecode(File('firestore.indexes.json').readAsStringSync())
        as Map<String, dynamic>;
    final found = (json['indexes'] as List).any((i) {
      final fields = [for (final f in i['fields'] as List) f['fieldPath']];
      return i['collectionGroup'] == 'outlet_products' &&
          fields.toSet().containsAll(['tenantId', 'businessId']) &&
          fields.last == 'updatedAt';
    });
    expect(found, isTrue);
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:testflutter/core/network/api_client.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';

void main() {
  test('initial and incremental REST pages use bounds, server snapshot and tie-safe ordering', () async {
    final bodies = <Map<String, dynamic>>[];
    final remote = FirestoreRestService(
      ApiClient(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode([
              {'readTime': '2026-10-02T10:00:00.123456Z'},
            ]),
            200,
          );
        }),
      ),
    );
    final filters = [
      const FirestoreFilter('tenantId', 'EQUAL', 'T'),
      const FirestoreFilter('businessId', 'EQUAL', 'B'),
    ];
    final initial = await remote.readSyncPage(
      collection: 'products',
      filters: filters,
      queryId: 'Q',
      reason: 'INITIAL_PULL',
      idToken: 'SECRET',
    );
    expect(initial.readTime, '2026-10-02T10:00:00.123456Z');
    final query = bodies.first['structuredQuery'] as Map;
    expect(query['limit'], 200);
    expect((query['orderBy'] as List).length, 1);
    expect((query['orderBy'] as List).first['field']['fieldPath'], '__name__');
    final name = 'projects/test/databases/(default)/documents/products/P';
    await remote.readSyncPage(
      collection: 'products',
      filters: filters,
      queryId: 'Q',
      reason: 'INCREMENTAL_PULL',
      cursor: initial.readTime,
      readTime: initial.readTime,
      after: {
        'name': name,
        'fields': {
          'updatedAt': {'timestampValue': initial.readTime},
        },
      },
    );
    final delta = bodies.last['structuredQuery'] as Map;
    expect(bodies.last['readTime'], initial.readTime);
    expect((delta['orderBy'] as List).map((o) => o['field']['fieldPath']), [
      'updatedAt',
      '__name__',
    ]);
    expect(delta['startAt']['before'], false);
    expect(delta['startAt']['values'][1], {'referenceValue': name});
    final clauses = delta['where']['compositeFilter']['filters'] as List;
    expect(clauses.last['fieldFilter']['op'], 'GREATER_THAN_OR_EQUAL');
    expect(clauses.last['fieldFilter']['value'], {
      'timestampValue': '2026-10-02T09:59:58.123456Z',
    });
  });

  test('commit assigns updatedAt on the server and retains mutation identity and version preconditions', () async {
    late Map<String, dynamic> body;
    final remote = FirestoreRestService(
      ApiClient(
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        }),
      ),
    );
    await remote.commitWrites([
      FirestoreWrite.create('products', 'P', {
        'name': 'New',
        'updatedAt': DateTime.utc(2020),
        '_syncMutationId': 'BATCH',
      }),
      FirestoreWrite.update('products', 'Q', {
        'isDeleted': true,
        'updatedAt': DateTime.utc(2020),
      }, updateTime: '2026-10-02T10:00:00Z'),
    ]);
    final writes = body['writes'] as List;
    for (final write in writes) {
      expect(write['update']['fields'].containsKey('updatedAt'), false);
      expect(write['updateMask']['fieldPaths'], isNot(contains('updatedAt')));
      expect(write['updateTransforms'], [
        {'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'},
      ]);
    }
    expect(writes.first['currentDocument'], {'exists': false});
    expect(writes.last['currentDocument'], {
      'updateTime': '2026-10-02T10:00:00Z',
    });
    expect(writes.first['update']['fields']['_syncMutationId'], {
      'stringValue': 'BATCH',
    });
  });
}

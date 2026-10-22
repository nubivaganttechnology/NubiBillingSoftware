import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/presentation/products/product_thumbnail.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? url) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ProductThumbnail(url: url, name: 'dia'),
        ),
      ),
    ),
  );

  for (final bad in [
    null,
    '',
    '   ',
    'not a url',
    'http://',
    'ftp://x/y.png',
  ]) {
    testWidgets('invalid image "$bad" renders the placeholder', (tester) async {
      await pump(tester, bad);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('product-image-placeholder')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('product-image-box'))),
        const Size(52, 52),
      );
    });
  }

  testWidgets(
    'unreadable local file and unreachable URL fall back to the placeholder',
    (tester) async {
      for (final url in [
        '/definitely/missing.png',
        'https://127.0.0.1:9/x.png',
      ]) {
        await pump(tester, url);
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const ValueKey('product-image-box'))),
          const Size(52, 52),
        );
      }
    },
  );

  testWidgets('valid local image stays inside the bounded box', (tester) async {
    final file = File('${Directory.systemTemp.path}/thumb_test.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
        ),
      );
    addTearDown(file.deleteSync);
    await pump(tester, file.path);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('product-image-box'))),
      const Size(52, 52),
    );
  });
}

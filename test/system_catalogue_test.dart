import 'dart:convert';
import 'dart:io';

import 'support/catalogue_import_fixture.dart';
import 'support/phase10e_release.dart' show approvedRelease4DocumentsForTest;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:testflutter/core/errors/app_exception.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/system_catalogue_metadata.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/product_attribute.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

import 'product_entry_form_test.dart' show EntryController, field;

import 'offline_sync_test.dart'
    show FakeRemote, TestConnectivity, token, session;

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalDatabase database;
  late LocalDataSource source;
  late FakeRemote remote;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  late ProductRepository repository;
  late Map<String, List<Map<String, dynamic>>> snapshot;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalogue-v3-');
    database = LocalDatabase(factory: databaseFactoryFfi, directory: dir.path);
    remote = FakeRemote();
    sync = SyncEngine(
      remote,
      TestConnectivity()..available = false,
      sessionProvider: () async => session('U'),
    );
    service = OfflineFirestoreService(database, remote, sync);
    await service.activate('U');
    await service.setScope(tenant: 'T', business: 'B');
    source = LocalDataSource(await database.open('', 'U'));
    repository = ProductRepository(service, service);
    final decoded = catalogueImportFixture();
    snapshot = {
      for (final entry in decoded.entries)
        entry.key: [
          for (final data in entry.value as List)
            {
              'name': '${entry.key}/${data['id']}',
              'fields': FirestoreRestService.encodeFields(
                Map<String, dynamic>.from(data)..remove('id'),
              ),
            },
        ],
    };
  });
  tearDown(() async {
    sync.dispose();
    await database.close();
    await dir.delete(recursive: true);
  });
  Future<void> import() => SystemCatalogueSnapshot.import(
    source: source,
    documents: snapshot,
    readTimes: {},
  );
  Future<List<ProductAttribute>> template(String name) async {
    final sub =
        (await source.query('product_subcategories', [
          FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
          FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
        ])).firstWhere(
          (d) => FirestoreRestService.decodeFields(d['fields'])['name'] == name,
        );
    return repository.loadTemplate(
      tenantId: 'T',
      businessId: 'B',
      subcategoryId: (sub['name'] as String).split('/').last,
      token: token('U'),
    );
  }

  test('v3 retires v1, deduplicates canonical choices and preserves pending BUSINESS data', () async {
    await source.upsertRemote('product_categories', [
      {
        'name': 'product_categories/OLD',
        'fields': FirestoreRestService.encodeFields({
          'scopeType': 'SYSTEM',
          'catalogueId': 'PAINT_V1',
          'name': 'Paint',
          'status': 'ACTIVE',
        }),
      },
    ]);
    await service.createDocument('product_categories', 'CUSTOM', {
      'scopeType': 'BUSINESS',
      'tenantId': 'T',
      'businessId': 'B',
      'name': 'Interior Wall Coatings',
      'categoryId': 'CUSTOM',
      'status': 'ACTIVE',
    }, idToken: token('U'));
    final before = await source.row('product_categories', 'CUSTOM');
    await import();
    expect(
      (await source.row('product_categories', 'OLD'))!['status'],
      'INACTIVE',
    );
    expect(await source.row('product_categories', 'CUSTOM'), before);
    final categories = await repository.getMasterValues(
      tenantId: 'T',
      businessId: 'B',
      masterType: 'CATEGORY',
      token: token('U'),
    );
    expect(
      categories
          .where((c) => c.name == 'Interior Wall Coatings')
          .single
          .scopeType,
      'SYSTEM',
    );
    expect(categories.map((c) => c.name), isNot(contains('Paint')));
    for (final old in [
      'Metal Paints',
      'Accessories',
      'Floor Coatings',
      'Interior Wall Paints',
    ]) {
      expect(categories.map((c) => c.name), isNot(contains(old)));
    }
    final release = await source.query('product_catalogue_releases', []);
    expect(
      FirestoreRestService.decodeFields(
        release.single['fields'],
      )['catalogueVersion'],
      3,
    );
    expect(await source.db.query('sync_outbox'), hasLength(1));
  });
  test('paint metadata controls fields, colour validation, defaults and technical sections offline', () async {
    await import();
    remote.offline = true;
    final before = remote.queries + remote.reads;
    final attrs = await template('Premium Interior Emulsions');
    ProductAttribute attr(String id) => attrs.singleWhere((a) => a.id == id);
    expect(attr('usage').defaultValue, 'Interior');
    expect(attr('surface').defaultValue, ['Wall']);
    expect(attr('surface').dataType, 'MULTI_SELECT');
    for (final id in [
      'finish',
      'numberOfCoats',
      'dilutionType',
      'colourType',
    ]) {
      expect(attr(id).dataType, 'SELECT');
      expect(attr(id).options, isNotEmpty);
    }
    expect(attr('numberOfCoats').section, 'ESSENTIAL');
    expect(attr('coverage').section, 'TECHNICAL');
    expect(attr('unit').options, contains('Litre'));
    expect(attr('unit').semanticRole, 'PACK_UNIT');
    expect(attr('packSize').minimumExclusive, 0);
    final values = {'colourType': 'Ready Colour'};
    expect(attr('shade').isRequired(values), isTrue);
    expect(attr('colourFamily').isRequired(values), isTrue);
    expect(attr('baseType').isVisible(values), isFalse);
    values['colourType'] = 'Tintable Base';
    expect(attr('baseType').isRequired(values), isTrue);
    expect(attr('shade').isRequired(values), isFalse);
    expect(attr('baseType').hintText, contains('manufacturer'));
    for (final type in ['Clear / Transparent', 'Not Applicable']) {
      values['colourType'] = type;
      for (final id in [
        'shade',
        'shadeCode',
        'colourFamily',
        'baseType',
        'baseCode',
      ]) {
        expect(attr(id).isVisible(values), isFalse);
        expect(attr(id).isRequired(values), isFalse);
      }
    }
    expect(remote.queries + remote.reads, before);
  });
  test(
    'tools, putty, wallpaper and sealant use distinct unit metadata',
    () async {
      await import();
      for (final entry in {
        'Brush': 'Piece',
        'Roller': 'Piece',
        'Wall Putty': 'Kilogram',
        'Wallpapers': 'Roll',
        'Silicone Sealants': 'Cartridge',
        'Masking Tape': 'Roll',
        'Sandpaper & Abrasives': 'Sheet',
      }.entries) {
        final attrs = await template(entry.key);
        expect(
          attrs.singleWhere((a) => a.id == 'unit').defaultValue,
          entry.value,
        );
        if (entry.key == 'Brush') {
          for (final id in ['brushType', 'bristleMaterial', 'handleMaterial']) {
            final a = attrs.singleWhere((a) => a.id == id);
            expect(a.dataType, 'SELECT');
            expect(a.options, isNotEmpty);
          }
          expect(attrs.map((a) => a.id), isNot(contains('finish')));
          final size = attrs.singleWhere((a) => a.id == 'brushSize');
          expect(size.dataType, 'NUMBER');
          expect(size.measurementUnitAttributeId, 'sizeUnit');
          expect(attrs.singleWhere((a) => a.id == 'sizeUnit').options, [
            'inch',
            'mm',
            'cm',
          ]);
        }
        if (entry.key == 'Silicone Sealants') {
          expect(
            attrs.singleWhere((a) => a.id == 'unit').options,
            containsAll(['Cartridge', 'Tube', 'Pouch']),
          );
        }
      }
      final units = await repository.getMasterValues(
        tenantId: 'T',
        businessId: 'B',
        masterType: 'UNIT',
        token: token('U'),
      );
      expect(
        units.map((u) => u.name),
        containsAll([
          'Cartridge',
          'Tube',
          'Pouch',
          'Bottle',
          'Jar',
          'Drum',
          'Bag',
        ]),
      );
    },
  );
  test('BUSINESS custom options survive restricted template merges and repeat imports', () async {
    await import();
    final newOption = await repository.createAttributeOption(
      tenantId: 'T',
      businessId: 'B',
      attributeId: 'colourFamily',
      name: 'Ocean Tones',
      actorUid: 'U',
      token: token('U'),
    );
    expect(newOption, 'Ocean Tones');
    final outbox = await source.db.query('sync_outbox');
    expect(outbox, hasLength(1));
    await import();
    final attrs = await template('Premium Interior Emulsions');
    expect(
      attrs.singleWhere((a) => a.id == 'colourFamily').options,
      contains('Ocean Tones'),
    );
    expect(
      attrs.singleWhere((a) => a.id == 'colourType').options,
      SystemCatalogueMetadata.colourTypes,
    );
    expect(await source.db.query('sync_outbox'), outbox);
  });
  test('failed SYSTEM page leaves catalogue release and previous categories unchanged', () async {
    await source.upsertRemote('product_catalogue_releases', [
      {
        'name': 'product_catalogue_releases/R',
        'fields': FirestoreRestService.encodeFields({
          'scopeType': 'SYSTEM',
          'catalogueVersion': 1,
          'status': 'ACTIVE',
        }),
      },
    ]);
    remote.seed('product_catalogue_releases', 'R', {
      'scopeType': 'SYSTEM',
      'catalogueVersion': 3,
      'status': 'ACTIVE',
    });
    for (var i = 0; i < 201; i++) {
      remote.seed('subcategory_attribute_templates', 'T$i', {
        'scopeType': 'SYSTEM',
      });
    }
    remote.failAfter = 'subcategory_attribute_templates';
    await sync.sync();
    final release = await source.row('product_catalogue_releases', 'R');
    expect(
      FirestoreRestService.decodeFields(
        jsonDecode(release!['payloadJson'] as String),
      )['catalogueVersion'],
      1,
    );
    expect(await source.query('subcategory_attribute_templates', []), isEmpty);
    final releaseQuery = await source.db.query(
      'sync_queries',
      where: "collectionName='product_catalogue_releases'",
    );
    expect(releaseQuery.every((q) => q['cursor'] == null), isTrue);
  });
  testWidgets(
    'v3 form applies colour validation and removes paint fields when switching to Brush',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController();
      controller.productMasterValues.remove('SUBCATEGORY:CA');
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await import();
        for (final type in ['CATEGORY', 'UNIT']) {
          controller.productMasterValues[type] = await repository
              .getMasterValues(
                tenantId: 'T',
                businessId: 'B',
                masterType: type,
                token: token('U'),
              );
        }
        for (final category in controller.productMasterValues['CATEGORY']!) {
          controller.productMasterValues['SUBCATEGORY:${category.id}'] =
              await repository.getMasterValues(
                tenantId: 'T',
                businessId: 'B',
                masterType: 'SUBCATEGORY',
                categoryId: category.id,
                token: token('U'),
              );
        }
        for (final name in ['Premium Interior Emulsions', 'Brush']) {
          final sub = controller.productMasterValues.values
              .expand((v) => v)
              .firstWhere((v) => v.name == name);
          controller.templates[sub.id] = await template(name);
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      Future<void> pick(String label, String name) async {
        await tester.ensureVisible(field(label));
        await tester.enterText(field(label), name);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      Finder menu(String label) => find.byWidgetPredicate(
        (w) =>
            w is DropdownMenu<String> &&
            w.label is Text &&
            (w.label as Text).data == label,
      );
      Future<void> select(String label, String name) async {
        final input = find.descendant(
          of: menu(label),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(input);
        await tester.tap(input);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await tester.enterText(field('Product Name *'), 'Catalogue form test');
      await pick('Brand / Company', 'Berger');
      await pick('Category', 'Interior Wall Coatings');
      await pick('Subcategory', 'Premium Interior Emulsions');
      expect(menu('Finish / Sheen'), findsOneWidget);
      expect(menu('Recommended Coats'), findsOneWidget);
      expect(menu('Dilution / Thinner Type'), findsOneWidget);
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Pack Unit *'))
            .initialSelection,
        'Litre',
      );
      await tester.enterText(field('Pack Size *'), '10');
      await select('Colour Type *', 'Ready Colour');
      expect(field('Shade / Colour *'), findsOneWidget);
      expect(menu('Colour Family *'), findsOneWidget);
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      expect(controller.savedVariants, isNull);
      expect(find.text('Enter shade / colour'), findsOneWidget);
      await tester.enterText(field('Shade / Colour *'), 'Snow White');
      await select('Colour Family *', 'White');
      await select('Colour Type *', 'Tintable Base');
      expect(field('Shade / Colour *'), findsNothing);
      expect(menu('Colour Family *'), findsNothing);
      expect(menu('Base Type *'), findsOneWidget);
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      expect(controller.savedVariants, isNull);
      await select('Base Type *', 'White Base');
      await select('Colour Type *', 'Clear / Transparent');
      expect(menu('Base Type *'), findsNothing);
      await tester.tap(find.text('Technical Details'));
      await tester.pumpAndSettle();
      expect(field('Coverage'), findsOneWidget);
      await pick('Category', 'Painting Tools & Accessories');
      await pick('Subcategory', 'Brush');
      expect(menu('Brush Type'), findsOneWidget);
      expect(menu('Bristle Material'), findsOneWidget);
      expect(menu('Finish / Sheen'), findsNothing);
      expect(menu('Colour Type *'), findsNothing);
      expect(menu('Recommended Coats'), findsNothing);
      expect(menu('Dilution / Thinner Type'), findsNothing);
      expect(
        tester.widget<DropdownMenu<String>>(menu('Sold As *')).initialSelection,
        'Piece',
      );
      expect(field('Variant GST (%)'), findsNothing);
      expect(find.text('Selling Mode'), findsNothing);
      await tester.enterText(field('Brush Size *'), '2');
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      final variant = controller.savedVariants!.single;
      expect(variant['commercialUnitId'], 'SYS_UNIT_PIECE');
      expect((variant['attributeValues'] as Map)['sizeUnit'], 'inch');
      for (final key in ['shade', 'baseType', 'colourType', 'finish']) {
        expect((variant['attributeValues'] as Map).containsKey(key), isFalse);
      }
      for (final key in ['sellingPrice', 'purchaseRate', 'mrp']) {
        expect(variant.containsKey(key), isFalse);
      }
      expect(tester.takeException(), isNull);
    },
  );
  test('repository reserves unique SKUs and rejects duplicate barcodes on Release 4', () async {
    await import();
    await SystemCatalogueSnapshot.import(
      source: source,
      documents: approvedRelease4DocumentsForTest(),
      readTimes: const {},
    );
    await service.createDocument('businesses', 'B', {
      'tenantId': 'T',
      'businessId': 'B',
    }, idToken: token('U'));
    await source.upsertRemote('brands', [
      {
        'name': 'brands/BR',
        'fields': FirestoreRestService.encodeFields({
          'brandId': 'BR',
          'scopeType': 'SYSTEM',
          'status': 'ACTIVE',
          'name': 'Manufacturer',
        }),
      },
    ]);
    final sub = snapshot['product_subcategories']!
        .map((d) => FirestoreRestService.decodeFields(d['fields']))
        .singleWhere((s) => s['name'] == 'Premium Interior Emulsions');
    final fields = {
      'brandId': 'BR',
      'categoryId': sub['categoryId'],
      'subcategoryId': sub['subcategoryId'],
      'defaultGstRateBps': 1800,
      'attributeValues': {
        'usage': 'Interior',
        'surface': ['Wall'],
      },
    };
    Map<String, dynamic> variant(
      Map<String, dynamic> values, {
      String? barcode,
    }) => {
      'attributeValues': {'unit': 'Litre', 'packSize': 10, ...values},
      'baseUnitId': 'SYS_UNIT_LITRE',
      'commercialUnitId': 'SYS_UNIT_LITRE',
      'baseQuantityPerCommercialUnit': 1,
      'barcode': barcode,
    };
    Future<void> save(String name, Map<String, dynamic> v) =>
        repository.createStructuredProduct(
          tenantId: 'T',
          businessId: 'B',
          productName: name,
          actorUid: 'U',
          token: token('U'),
          productFields: fields,
          variants: [v],
        );
    Matcher required(String label) => throwsA(
      isA<AppException>().having((e) => e.message, 'message', contains(label)),
    );
    await save(
      'Tint',
      variant({
        'colourType': 'Tintable Base',
        'baseType': 'White Base',
      }, barcode: 'BC-1'),
    );
    await expectLater(
      save(
        'Duplicate barcode',
        variant({'colourType': 'Not Applicable'}, barcode: 'BC-1'),
      ),
      required('barcode'),
    );
    await save('Clear', variant({'colourType': 'Clear / Transparent'}));
    final products = await repository.getProducts(
      tenantId: 'T',
      businessId: 'B',
      token: token('U'),
    );
    expect(products, hasLength(2));
    expect(
      products.expand((p) => p.variants).map((v) => v.sku).toSet(),
      hasLength(2),
    );
    final tint = products.singleWhere((p) => p.name == 'Tint').variants.single;
    expect(tint.attributeValues.containsKey('shade'), isFalse);
    expect(tint.attributeValues.containsKey('colourFamily'), isFalse);
    expect(tint.gstOverride, isFalse);
    expect(tint.defaultGstRateBps, 1800);
    expect(remote.queries + remote.reads, 0);
  });
}

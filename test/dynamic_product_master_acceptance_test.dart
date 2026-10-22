import 'dart:io';

import 'support/catalogue_import_fixture.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/product_attribute.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

import 'offline_sync_test.dart'
    show FakeRemote, TestConnectivity, token, session;
import 'product_entry_form_test.dart' show EntryController, field;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late LocalDatabase database;
  late FakeRemote remote;
  late LocalDataSource source;
  late SyncEngine sync;
  late OfflineFirestoreService service;
  late ProductRepository repository;
  late Map<String, List<Map<String, dynamic>>> snapshot;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalogue-acceptance-');
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

  testWidgets(
    'dynamic Product Master subcategory switching acceptance test',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = EntryController();
      controller.productMasterValues.clear();
      addTearDown(controller.dispose);

      await tester.runAsync(() async {
        await import();
        for (final type in ['BRAND', 'CATEGORY', 'UNIT']) {
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
        for (final name in [
          'Wall Putty',
          'Interior Wall Primers',
          'Metal Primers',
          'Brush',
        ]) {
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
            ((w.label as Text).data == label ||
                (w.label as Text).data == '$label *' ||
                (w.label as Text).data == label.replaceAll(' *', '')),
      );

      Finder anyField(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            (widget.decoration?.labelText == label ||
                widget.decoration?.labelText == '$label *' ||
                widget.decoration?.labelText == label.replaceAll(' *', '')),
      );

      // Step 1: Select Putty & Surface Preparation -> Wall Putty.
      await tester.enterText(field('Product Name *'), 'Test Product Master');
      await pick('Brand / Company', 'Berger');
      await pick('Category', 'Putty & Surface Preparation');
      await pick('Subcategory', 'Wall Putty');

      // Step 2 & 3: Verify Pack Unit defaults to Kilogram, Sold As defaults to Bag.
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Pack Unit *'))
            .initialSelection,
        'Kilogram',
      );
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Sold As *'))
            .initialSelection,
        'Bag',
      );

      // Step 4: Verify conversion is OFF.
      final allowConversionCheckbox = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Allow loose / converted sale'),
      );
      expect(allowConversionCheckbox.value, isFalse);
      expect(field('Contains *'), findsNothing);
      expect(find.text('Base Unit *'), findsNothing);

      // Step 5: Switch immediately to Primers & Undercoats -> Interior Wall Primers.
      await pick('Category', 'Primers & Undercoats');
      await pick('Subcategory', 'Interior Wall Primers');

      // Step 6: Verify Kilogram and Bag do not remain.
      // Step 7: Verify Pack Unit becomes Litre.
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Pack Unit *'))
            .initialSelection,
        'Litre',
      );
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Sold As *'))
            .initialSelection,
        isNot('Bag'),
      );

      // Step 8: Verify Usage = Interior.
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Usage'))
            .initialSelection,
        'Interior',
      );

      // Step 9: Verify Surface = Wall.
      expect(find.widgetWithText(FilterChip, 'Wall'), findsOneWidget);

      // Step 10: Verify Colour Availability appears.
      expect(menu('Colour Availability'), findsOneWidget);
      expect(
        tester
            .widget<DropdownMenu<String>>(menu('Colour Availability'))
            .initialSelection,
        'Fixed Colour',
      );

      // Step 11: Verify Fixed Colour can display White.
      expect(anyField('Product Colour'), findsOneWidget);
      expect(find.text('White'), findsWidgets);

      // Step 12 & 13: Verify Recommended Coats and Dilution / Thinner Type are dropdowns.
      expect(menu('Recommended Coats'), findsOneWidget);
      expect(menu('Dilution / Thinner Type'), findsOneWidget);

      // Step 14: Verify price fields do not exist.
      expect(field('Purchase Rate'), findsNothing);
      expect(field('Selling Price'), findsNothing);
      expect(field('MRP'), findsNothing);

      // Step 15 & 16: Switch to Metal Primer. Verify surface becomes Metal and colour is available.
      await pick('Subcategory', 'Metal Primers');
      expect(find.widgetWithText(FilterChip, 'Metal'), findsOneWidget);
      expect(menu('Colour Availability'), findsOneWidget);

      // Step 17: Switch to Brush.
      await pick('Category', 'Painting Tools & Accessories');
      await pick('Subcategory', 'Brush');

      // Step 18: Verify all primer/paint colour and dilution fields disappear.
      expect(menu('Colour Availability'), findsNothing);
      expect(field('Product Colour'), findsNothing);
      expect(menu('Dilution / Thinner Type'), findsNothing);
      expect(menu('Recommended Coats'), findsNothing);

      // Step 19: Verify Brush Type and Bristle Material are dropdowns.
      expect(menu('Brush Type'), findsOneWidget);
      expect(menu('Bristle Material'), findsOneWidget);
    },
  );
}

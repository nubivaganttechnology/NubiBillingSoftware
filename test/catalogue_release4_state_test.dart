import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

import 'product_entry_form_test.dart' show EntryController, field;
import 'support/phase10e_release.dart';

class _CanonicalController extends EntryController {
  _CanonicalController(this.fixture);
  final Phase10EFixture fixture;
  @override
  Future<ResolvedProductTemplate> resolveProductTemplate(
    String subcategoryId,
  ) => fixture.resolve(
    phase10eCandidates.singleWhere((d) => d['canonicalId'] == subcategoryId),
  );
}

void main() {
  final fixture = Phase10EFixture();
  setUpAll(() async {
    await fixture.open();
    for (final d in phase10eCandidates) {
      await fixture.resolve(d);
    }
  });
  tearDownAll(fixture.close);
  final cases = {
    'Wall Putty -> Interior Wall Primer': [
      'SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WALL_PUTTY',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS',
    ],
    'Interior Paint -> Brush': [
      'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_BRUSH',
    ],
    'Litre coating -> Sandpaper': [
      'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_ECONOMY_INTERIOR_PAINTS',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PAINTING_TOOLS_ACCESSORIES_SANDPAPER_ABRASIVES',
    ],
    'Sealant cartridge -> liquid primer': [
      'SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_SILICONE_SEALANTS',
      'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_UNDERCOATS_INTERIOR_WALL_PRIMERS',
    ],
    'Powder coating -> aerosol product': [
      'SYS_SUBCATEGORY_SYS_CATEGORY_POWDER_COATINGS_POWDER_COATINGS',
      'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_SPRAY_PAINTS',
    ],
    'Basement Liquid -> Basement Cementitious': [
      liquidBasement,
      cementitiousBasement,
    ],
    'Basement Cementitious -> Basement Liquid': [
      cementitiousBasement,
      liquidBasement,
    ],
  };
  for (final entry in cases.entries) {
    testWidgets('canonical Create state transition ${entry.key}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final before = phase10eCandidates.singleWhere(
        (d) => d['canonicalId'] == entry.value[0],
      );
      final after = phase10eCandidates.singleWhere(
        (d) => d['canonicalId'] == entry.value[1],
      );
      final beforeTemplate = await fixture.resolve(before);
      final afterTemplate = await fixture.resolve(after);
      final controller = _CanonicalController(fixture);
      addTearDown(controller.dispose);
      controller.productMasterValues['CATEGORY'] = [
        ProductMasterValue(
          id: before['categoryId'] as String,
          name: 'Before Family',
          status: 'ACTIVE',
        ),
        if (after['categoryId'] != before['categoryId'])
          ProductMasterValue(
            id: after['categoryId'] as String,
            name: 'After Family',
            status: 'ACTIVE',
          ),
      ];
      for (final d in [before, after]) {
        controller.productMasterValues
            .putIfAbsent('SUBCATEGORY:${d['categoryId']}', () => [])
            .addAll([
              ProductMasterValue(
                id: d['canonicalId'] as String,
                name: d['name'] as String,
                categoryId: d['categoryId'] as String,
                status: 'ACTIVE',
              ),
            ]);
      }
      final names = <String>{'inch', 'mm', 'cm', 'Metre'};
      for (final d in phase10eCandidates) {
        for (final key in [
          'allowedPackUnits',
          'allowedBaseUnits',
          'allowedSellingUnits',
        ]) {
          names.addAll((d['unitRules'][key] as List).cast<String>());
        }
      }
      controller.productMasterValues['UNIT'] = [
        for (final name in names)
          ProductMasterValue(
            id: Phase10EFixture.unitId(name),
            name: name,
            status: 'ACTIVE',
            measurementDimension: {'inch', 'mm', 'cm', 'Metre'}.contains(name)
                ? 'LENGTH'
                : null,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      Finder inputFor(String label) {
        var input = field(label);
        if (input.evaluate().isEmpty) {
          final menu = find.byWidgetPredicate(
            (w) =>
                w is DropdownMenu<String> &&
                w.label is Text &&
                (w.label as Text).data == label,
          );
          expect(
            menu,
            findsOneWidget,
            reason: 'Expected selectable field $label',
          );
          input = find
              .descendant(of: menu, matching: find.byType(TextField))
              .first;
        }
        return input;
      }

      Future<void> pick(String label, String value) async {
        final input = inputFor(label);
        await tester.ensureVisible(input);
        if (tester.widget<TextField>(input).controller?.text == value) {
          return;
        }
        await tester.enterText(input, value);
        await tester.pumpAndSettle();
        await tester.tap(find.text(value).hitTestable().last);
        await tester.pumpAndSettle();
      }

      await tester.enterText(field('Product Name *'), 'Representative switch');
      await pick('Brand / Company', 'Berger');
      await pick('Category', 'Before Family');
      await pick('Subcategory', before['name'] as String);
      final mode = beforeTemplate.productAttributes
          .where((a) => a.attributeId == 'colourType')
          .firstOrNull;
      if (mode != null && mode.optionNames.contains('Tintable')) {
        await pick('Colour Availability', 'Tintable');
        await pick('Base Type *', 'Deep Base');
      } else if (mode != null &&
          mode.optionNames.contains('Multiple Ready Colours')) {
        await pick('Colour Availability', 'Multiple Ready Colours');
        await tester.enterText(field('Shade / Colour *'), 'OLD SHADE');
      }
      final checkbox = find.byWidgetPredicate(
        (w) =>
            w is CheckboxListTile &&
            w.title is Text &&
            (w.title as Text).data == 'Allow loose / converted sale',
      );
      if (beforeTemplate.unitRules.conversionAllowed) {
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tester.enterText(field('Contains *'), '11');
      }
      if (entry.value.contains(liquidBasement) ||
          entry.value.contains(cementitiousBasement)) {
        // Deliberately populate the other measurement unit before switching;
        // the target must reset it and must not guess a selling default.
        await pick(
          'Pack Unit *',
          beforeTemplate.unitRules.allowedPackUnits.last,
        );
        await pick(
          'Sold As *',
          beforeTemplate.unitRules.allowedSellingUnits.last,
        );
      }
      if (after['categoryId'] != before['categoryId']) {
        await pick('Category', 'After Family');
      }
      await pick('Subcategory', after['name'] as String);
      expect(tester.widget<CheckboxListTile>(checkbox).value, false);
      expect(find.text('Contains *'), findsNothing);
      final afterMode = afterTemplate.productAttributes
          .where((a) => a.attributeId == 'colourType')
          .firstOrNull;
      if (afterMode != null) {
        await pick('Colour Availability', 'Not Applicable');
      }
      final values = <String, dynamic>{'colourType': 'Not Applicable'};
      for (final a in afterTemplate.allAttributes) {
        final legacy = a.toProductAttribute();
        if (!legacy.isRequired(
          a.level == AttributeLevel.product ? values : <String, dynamic>{},
          a.level == AttributeLevel.variant ? values : null,
        )) {
          continue;
        }
        if (a.defaultValue != null ||
            {'unit', 'soldAs'}.contains(a.attributeId)) {
          continue;
        }
        final label = '${a.displayName} *';
        if (a.dataType == 'NUMBER') {
          await tester.ensureVisible(field(label));
          await tester.enterText(field(label), '4');
        } else if (a.dataType == 'SELECT') {
          await pick(label, a.optionNames.first);
        }
      }
      if (afterTemplate.unitRules.defaultSellingUnit == null) {
        expect(
          tester.widget<TextField>(inputFor('Sold As *')).controller?.text,
          isEmpty,
        );
        await pick(
          'Sold As *',
          afterTemplate.unitRules.allowedSellingUnits.first,
        );
      }
      await tester.ensureVisible(find.text('Save Product'));
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      expect(controller.savedFields, isNotNull);
      expect(controller.savedVariants, isNotNull);
      final saved = controller.savedVariants!.single;
      expect(
        saved['packUnitId'],
        Phase10EFixture.unitId(afterTemplate.unitRules.defaultPackUnit!),
      );
      expect(
        saved['commercialUnitId'],
        Phase10EFixture.unitId(
          afterTemplate.unitRules.defaultSellingUnit ??
              afterTemplate.unitRules.allowedSellingUnits.first,
        ),
      );
      expect(saved['baseUnitId'], saved['commercialUnitId']);
      expect(saved['baseQuantityPerCommercialUnit'], 1);
      final attrs = saved['attributeValues'] as Map;
      expect(
        attrs.keys.toSet().difference(
          afterTemplate.variantAttributes.map((a) => a.attributeId).toSet(),
        ),
        isEmpty,
      );
      expect(
        attrs.keys.toSet().intersection({
          'shade',
          'shadeCode',
          'baseType',
          'baseCode',
          'colourFamily',
        }),
        isEmpty,
      );
      final p = controller.savedFields!['attributeValues'] as Map;
      expect(
        p.keys.toSet().difference({
          ...afterTemplate.productAttributes.map((a) => a.attributeId),
          'colourMode',
        }),
        isEmpty,
      );
      final surface = afterTemplate.productAttributes
          .where((a) => a.attributeId == 'surface')
          .firstOrNull;
      if (surface != null) {
        expect(p['surface'], surface.defaultValue);
      }
      final validation = await tester.runAsync(
        () => fixture.validate({
          'productFields': controller.savedFields!,
          'variants': controller.savedVariants!,
        }),
      );
      expect(validation!.isValid, true, reason: '${validation.errors}');
      expect(tester.takeException(), isNull);
    });
  }
}

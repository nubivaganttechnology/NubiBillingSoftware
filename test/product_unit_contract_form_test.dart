import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/product_attribute.dart';
import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

import 'product_entry_form_test.dart' show EntryController, field;

void main() {
  final aliases = {
    for (final name in [
      'Litre',
      'Millilitre',
      'Kilogram',
      'Gram',
      'Piece',
      'Sheet',
      'Roll',
      'Cartridge',
      'Can',
    ])
      'master_$name'.toLowerCase(): name,
  };
  ResolvedUnitRule rules(
    String unit, {
    String? dimension,
    bool conversion = false,
    String? selling,
  }) => ResolvedUnitRule(
    allowedPackUnits: [unit],
    defaultPackUnit: unit,
    allowedSellingUnits: [selling ?? unit],
    defaultSellingUnit: selling ?? unit,
    allowedBaseUnits: dimension == null ? [] : [unit],
    defaultBaseUnit: dimension == null ? null : unit,
    conversionAllowed: conversion,
    conversionDimension: dimension,
    unitAliases: aliases,
    explicitContract: true,
  );
  final cases = <String, List<ResolvedUnitRule>>{
    'Wall Putty -> Interior Wall Primer': [
      rules('Kilogram', dimension: 'MASS', conversion: true),
      rules('Litre', dimension: 'VOLUME', conversion: true),
    ],
    'Interior Paint -> Brush': [
      rules('Litre', dimension: 'VOLUME', conversion: true),
      rules('Piece'),
    ],
    'Litre coating -> Sandpaper': [
      rules('Litre', dimension: 'VOLUME', conversion: true),
      rules('Sheet'),
    ],
    'Sealant cartridge -> liquid primer': [
      rules('Cartridge'),
      rules('Litre', dimension: 'VOLUME', conversion: true),
    ],
    'Powder coating -> aerosol product': [
      rules('Kilogram', dimension: 'MASS', conversion: true),
      rules('Millilitre', selling: 'Can'),
    ],
  };
  for (final entry in cases.entries) {
    testWidgets('unit contract widget transition ${entry.key}', (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController();
      addTearDown(controller.dispose);
      controller.productMasterValues['UNIT'] = [
        for (final name in [
          'Litre',
          'Millilitre',
          'Kilogram',
          'Gram',
          'Piece',
          'Sheet',
          'Roll',
          'Cartridge',
          'Can',
        ])
          ProductMasterValue(id: 'master_$name', name: name, status: 'ACTIVE'),
      ];
      controller.productMasterValues['SUBCATEGORY:CA'] = [
        const ProductMasterValue(
          id: 'BEFORE',
          name: 'Before',
          categoryId: 'CA',
          status: 'ACTIVE',
        ),
        const ProductMasterValue(
          id: 'AFTER',
          name: 'After',
          categoryId: 'CA',
          status: 'ACTIVE',
        ),
      ];
      for (final index in [0, 1]) {
        final id = index == 0 ? 'BEFORE' : 'AFTER';
        final rule = entry.value[index];
        controller.unitContracts[id] = rule;
        controller.templates[id] = [
          const ProductAttribute(
            id: 'packSize',
            name: 'Pack Size',
            dataType: 'NUMBER',
            level: 'VARIANT',
            required: true,
          ),
          ProductAttribute(
            id: 'unit',
            name: 'Pack Unit',
            dataType: 'SELECT',
            level: 'VARIANT',
            required: true,
            options: rule.allowedPackUnits,
            defaultValue: rule.defaultPackUnit,
          ),
          ProductAttribute(
            id: 'soldAs',
            name: 'Sold As',
            dataType: 'SELECT',
            level: 'VARIANT',
            required: true,
            options: rule.allowedSellingUnits,
            defaultValue: rule.defaultSellingUnit,
          ),
        ];
      }
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

      await tester.enterText(field('Product Name *'), 'Unit transition');
      await pick('Brand / Company', 'Berger');
      await pick('Category', 'Accessories');
      await pick('Subcategory', 'Before');
      final checkbox = find.byWidgetPredicate(
        (w) =>
            w is CheckboxListTile &&
            w.title is Text &&
            (w.title as Text).data == 'Allow loose / converted sale',
      );
      expect(tester.widget<CheckboxListTile>(checkbox).value, false);
      if (entry.value[0].conversionAllowed) {
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        await tester.enterText(field('Contains *'), '20');
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(checkbox).value, true);
      } else {
        expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);
      }
      await pick('Subcategory', 'After');
      expect(tester.widget<CheckboxListTile>(checkbox).value, false);
      expect(find.text('Contains *'), findsNothing);
      if (!entry.value[1].conversionAllowed) {
        expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);
      }
      final packMenu = find.byWidgetPredicate(
        (w) =>
            w is DropdownMenu<String> &&
            w.label is Text &&
            (w.label as Text).data == 'Pack Unit *',
      );
      expect(
        tester
            .widget<DropdownMenu<String>>(packMenu)
            .dropdownMenuEntries
            .map((e) => e.value),
        entry.value[1].allowedPackUnits,
      );
      await tester.ensureVisible(field('Pack Size *'));
      await tester.enterText(field('Pack Size *'), '4');
      await tester.ensureVisible(find.text('Save Product'));
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      expect(controller.savedVariants, isNotNull);
      final saved = controller.savedVariants!.single;
      expect(saved['packUnitId'], 'master_${entry.value[1].defaultPackUnit}');
      expect(
        saved['commercialUnitId'],
        'master_${entry.value[1].defaultSellingUnit}',
      );
      expect(saved['baseUnitId'], saved['commercialUnitId']);
      expect(saved['baseQuantityPerCommercialUnit'], 1);
      expect(
        (saved['attributeValues'] as Map)['unit'],
        entry.value[1].defaultPackUnit,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

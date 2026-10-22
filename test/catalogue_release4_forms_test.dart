import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';

import 'support/decoded_catalogue_audit.dart' show ReadOnlyCatalogueService;
import 'support/phase10e_release.dart';

void main() {
  final fixture = Phase10EFixture();
  var simulations = 0;
  var selectCases = 0;
  var conversionCases = 0;
  var invalidConversionCases = 0;
  var colourCases = 0;
  setUpAll(fixture.open);
  tearDownAll(() async {
    // ignore: avoid_print
    print(
      'PHASE10E_SIMULATION: ${jsonEncode({'candidates': phase10eCandidates.length, 'minimallyConstructible': simulations, 'selectCases': selectCases, 'conversionCases': conversionCases, 'invalidConversionCases': invalidConversionCases, 'colourCases': colourCases})}',
    );
    await fixture.close();
  });

  test(
    'all 137 candidates reconcile to selector and remain temporary review data',
    () async {
      final selector = CatalogueSelectionResolver(
        ReadOnlyCatalogueService(fixture.local),
      );
      final actual = <String>{};
      for (final category
          in phase10eCandidates.map((d) => d['categoryId'] as String).toSet()) {
        actual.addAll(
          (await selector.getEligibleSubcategories(
            tenantId: 'T',
            businessId: 'B',
            categoryId: category,
            token: 'ISOLATED',
          )).map((r) => r.id),
        );
      }
      final expected = phase10eCandidates
          .where((d) => d['intendedSelectability'] == 'SELECTABLE_READY')
          .map((d) => d['canonicalId'])
          .toSet();
      expect(actual, expected);
      expect(phase10eCandidates.length, 137);
      expect(expected, hasLength(phase10eCandidates.length));
      expect(
        await fixture.local.db.query('local_product_catalogue_releases'),
        hasLength(1),
      );
      expect(await fixture.local.db.query('local_products'), isEmpty);
      expect(await fixture.local.db.query('local_product_variants'), isEmpty);
      expect(await fixture.local.db.query('sync_outbox'), isEmpty);
      expect(phase10eReview['importable'], true);
      expect(phase10eReview['approvedForLiveExecution'], false);
      expect(
        fixture.directory.path,
        isNot(startsWith('/Users/sksuman/Documents')),
      );
    },
  );

  for (final candidate in phase10eCandidates) {
    test('content and full form simulation ${candidate['canonicalId']}', () async {
      final template = await fixture.resolve(candidate);
      final productIds = template.productAttributes
          .map((a) => a.attributeId)
          .toSet();
      final variantIds = template.variantAttributes
          .map((a) => a.attributeId)
          .toSet();
      expect(productIds.intersection(variantIds), isEmpty);
      final authored = {
        for (final a in candidate['attributes'] as List)
          a['attributeId'] as String: a as Map,
      };
      expect(
        template.allAttributes.map((a) => a.attributeId).toSet(),
        authored.keys.toSet(),
      );
      for (final a in template.allAttributes) {
        expect(
          a.defaultValue,
          authored[a.attributeId]!['defaultValue'],
          reason: 'Resolver must not discard an invalid authored default',
        );
        expect(a.level.name, authored[a.attributeId]!['level']);
        expect(a.required, authored[a.attributeId]!['required']);
        // SELECT/MULTI_SELECT options constrain values. TEXT fields remain
        // free text; the runtime may attach master suggestions to them.
        if (a.dataType == 'SELECT' || a.dataType == 'MULTI_SELECT') {
          expect(a.optionNames, [
            for (final o in authored[a.attributeId]!['options'] as List)
              o['name'],
          ]);
        }
        if (a.dataType == 'SELECT' && a.defaultValue != null) {
          expect(a.optionNames, contains(a.defaultValue));
        }
        if (a.dataType == 'MULTI_SELECT' && a.defaultValue != null) {
          expect((a.defaultValue as List).every(a.optionNames.contains), true);
        }
        for (final c in a.conditions) {
          expect(authored, contains(c.targetAttributeId));
          expect(ConditionScope.values, contains(c.scope));
        }
      }
      final structuralDiagnostics = template.diagnostics
          .where(
            (d) => {
              'INVALID_DEFAULT',
              'INVALID_CONDITION_SCOPE',
              'MISSING_CONDITION_ATTRIBUTE',
              'DOMAIN_REVIEW_REQUIRED',
            }.contains(d.code),
          )
          .toList();
      expect(template.readiness, TemplateReadinessState.ready);
      expect(
        template.diagnostics.where(
          (d) => d.severity == 'ERROR' || d.severity == 'WARNING',
        ),
        isEmpty,
        reason: 'No unexplained structural/content findings',
      );
      expect(structuralDiagnostics, isEmpty, reason: '$structuralDiagnostics');
      final rules = template.unitRules;
      final unitIntent = candidate['unitRules'] as Map;
      expect(rules.allowedPackUnits, unitIntent['allowedPackUnits']);
      expect(rules.allowedBaseUnits, unitIntent['allowedBaseUnits']);
      expect(rules.allowedSellingUnits, unitIntent['allowedSellingUnits']);
      expect(rules.defaultPackUnit, unitIntent['defaultPackUnit']);
      expect(rules.defaultBaseUnit, unitIntent['defaultBaseUnit']);
      expect(rules.defaultSellingUnit, unitIntent['defaultSellingUnit']);
      expect(rules.allowedBaseUnits.length, lessThanOrEqualTo(2));
      expect(
        rules.conversionAllowed,
        (candidate['unitRules'] as Map)['conversionAllowed'],
      );
      if (rules.conversionAllowed) {
        expect(
          rules.allowedBaseUnits.every(
            (u) =>
                rules.isMeasurement(u) &&
                rules.dimensionOf(u) == rules.conversionDimension,
          ),
          true,
        );
      }
      final initial = fixture.state(template);
      final valid = await fixture.validate(initial);
      expect(
        valid.isValid,
        true,
        reason: '${candidate['name']}: ${valid.errors}',
      );
      simulations++;
      final withoutMode = fixture.state(template, omitColourMode: true);
      final noModeValidation = await fixture.validate(withoutMode);
      expect(
        noModeValidation.isValid,
        true,
        reason:
            'Colour mode must not be globally required: ${noModeValidation.errors}',
      );

      for (final attribute in template.allAttributes.where(
        (a) => a.dataType == 'SELECT',
      )) {
        expect(attribute.optionNames, isNotEmpty);
        for (final option in attribute.optionNames) {
          final state = fixture.state(
            template,
            selected: attribute,
            option: option,
          );
          final product =
              (state['productFields'] as Map)['attributeValues']
                  as Map<String, dynamic>;
          final variant =
              (state['variants'] as List).single['attributeValues']
                  as Map<String, dynamic>;
          for (final dependent in template.allAttributes) {
            final values = dependent.level == AttributeLevel.product
                ? product
                : variant;
            if (!dependent.isVisible(product, variant, [variant])) {
              expect(values.containsKey(dependent.attributeId), false);
              expect(
                dependent.toProductAttribute().isRequired(
                  values,
                  dependent.level == AttributeLevel.variant ? product : null,
                  [variant],
                ),
                false,
                reason: 'Hidden identity field cannot be required',
              );
            }
          }
          final validation = await fixture.validate(state);
          expect(
            validation.isValid,
            true,
            reason:
                '${candidate['name']} ${attribute.attributeId}=$option: ${validation.errors}',
          );
          selectCases++;
          if (attribute.attributeId == 'colourType') {
            colourCases++;
            final forbidden = switch (option) {
              'Fixed Colour' => {
                'shade',
                'shadeCode',
                'colourFamily',
                'baseType',
                'baseCode',
              },
              'Multiple Ready Colours' => {
                'productColour',
                'baseType',
                'baseCode',
              },
              'Tintable' => {
                'productColour',
                'shade',
                'shadeCode',
                'colourFamily',
              },
              _ => {
                'productColour',
                'shade',
                'shadeCode',
                'colourFamily',
                'baseType',
                'baseCode',
              },
            };
            expect(
              forbidden.intersection({...product.keys, ...variant.keys}),
              isEmpty,
            );
            final needed = switch (option) {
              'Fixed Colour' => 'productColour',
              'Multiple Ready Colours' => 'shade',
              'Tintable' => 'baseType',
              _ => null,
            };
            if (needed != null) {
              (needed == 'productColour' ? product : variant).remove(needed);
              final missing = await fixture.validate(state);
              expect(
                missing.errors.any(
                  (e) =>
                      e.code == 'MISSING_REQUIRED_ATTRIBUTE' &&
                      e.attributeId == needed,
                ),
                true,
                reason: 'Active colour identity must be enforced',
              );
            }
          }
        }
      }
      if (rules.conversionAllowed) {
        for (final base in rules.allowedBaseUnits) {
          final converted = fixture.state(template, converting: true);
          ((converted['variants'] as List).single as Map)['baseUnitId'] =
              Phase10EFixture.unitId(base);
          final result = await fixture.validate(converted);
          expect(
            result.isValid,
            true,
            reason: '${candidate['name']} base $base: ${result.errors}',
          );
          conversionCases++;
        }
        for (final invalidBase in [
          rules.conversionDimension == 'MASS' ? 'Litre' : 'Kilogram',
          'Bucket',
        ]) {
          final invalid = fixture.state(template, converting: true);
          ((invalid['variants'] as List).single as Map)['baseUnitId'] =
              Phase10EFixture.unitId(invalidBase);
          final rejected = await fixture.validate(invalid);
          expect(
            rejected.errors.any((e) => e.code == 'UNIT_NOT_ALLOWED'),
            true,
          );
          expect(
            rejected.errors.any((e) => e.code == 'INCOMPATIBLE_UNIT_DIMENSION'),
            true,
          );
          invalidConversionCases++;
        }
        final invalidFactor = fixture.state(template, converting: true);
        ((invalidFactor['variants'] as List).single
                as Map)['baseQuantityPerCommercialUnit'] =
            0;
        final rejectedFactor = await fixture.validate(invalidFactor);
        expect(
          rejectedFactor.errors.any(
            (e) => e.code == 'INVALID_CONVERSION_FACTOR',
          ),
          true,
        );
        invalidConversionCases++;
      } else {
        final attempted = fixture.state(template);
        ((attempted['variants'] as List).single as Map)['_packaging'] = true;
        final result = await fixture.validate(attempted);
        expect(
          result.errors.any((e) => e.code == 'CONVERSION_NOT_ALLOWED'),
          true,
        );
        conversionCases++;
        invalidConversionCases++;
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  String findPython() {
    final candidates = [
      if (Platform.isWindows) 'python',
      'python3',
      'python',
      'py',
    ];
    for (final cmd in candidates) {
      try {
        final res = Process.runSync(cmd, ['--version']);
        if (res.exitCode == 0) return cmd;
      } catch (_) {}
    }
    return Platform.isWindows ? 'python' : 'python3';
  }

  final pyCmd = findPython();
  final discovered = Process.runSync(pyCmd, [
    '-B',
    '-c',
    'import json,unittest; from tool.tests.test_catalogue_phase10e import Release4Proof; print(json.dumps(unittest.TestLoader().getTestCaseNames(Release4Proof)))',
  ]);
  if (discovered.exitCode != 0) {
    throw StateError('${discovered.stderr}');
  }
  for (final name
      in (jsonDecode(discovered.stdout as String) as List).cast<String>()) {
    test('Phase 10E ${name.replaceAll('_', ' ')}', () async {
      final result = await Process.run(pyCmd, [
        '-B',
        '-m',
        'unittest',
        'tool.tests.test_catalogue_phase10e.Release4Proof.$name',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}

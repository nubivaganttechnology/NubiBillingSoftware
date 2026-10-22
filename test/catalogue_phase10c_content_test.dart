import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/services/catalogue_selection_resolver.dart';

import 'support/decoded_catalogue_audit.dart' show ReadOnlyCatalogueService;
import 'support/phase10c_model.dart';

void main() {
  final fixture = Phase10CFixture();
  var simulations = 0;
  var selectCases = 0;
  var conversionCases = 0;
  setUpAll(fixture.open);
  tearDownAll(() async {
    // ignore: avoid_print
    print(
      'PHASE10C_SIMULATION: ${jsonEncode({'candidates': phase10cCandidates.length, 'minimallyConstructible': simulations, 'selectCases': selectCases, 'conversionCases': conversionCases})}',
    );
    await fixture.close();
  });

  test(
    'all 136 candidates reconcile to selector and remain temporary review data',
    () async {
      final selector = CatalogueSelectionResolver(
        ReadOnlyCatalogueService(fixture.local),
      );
      final actual = <String>{};
      for (final category
          in phase10cCandidates.map((d) => d['categoryId'] as String).toSet()) {
        actual.addAll(
          (await selector.getEligibleSubcategories(
            tenantId: 'T',
            businessId: 'B',
            categoryId: category,
            token: 'ISOLATED',
          )).map((r) => r.id),
        );
      }
      final expected = phase10cCandidates
          .where((d) => d['intendedSelectability'] == 'SELECTABLE_READY')
          .map((d) => d['canonicalId'])
          .toSet();
      expect(actual, expected);
      expect(phase10cCandidates.length, 136);
      expect(
        await fixture.local.db.query('local_product_catalogue_releases'),
        isEmpty,
      );
      expect(await fixture.local.db.query('local_products'), isEmpty);
      expect(await fixture.local.db.query('local_product_variants'), isEmpty);
      expect(await fixture.local.db.query('sync_outbox'), isEmpty);
      expect(phase10cModel['importable'], false);
      expect(phase10cModel['approvedForLiveExecution'], false);
      expect(
        fixture.directory.path,
        isNot(startsWith('/Users/sksuman/Documents')),
      );
    },
  );

  for (final candidate in phase10cCandidates) {
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
        expect(a.optionNames, [
          for (final o in authored[a.attributeId]!['options'] as List)
            o['name'],
        ]);
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
      if (candidate['intendedSelectability'] == 'DOMAIN_REVIEW_REQUIRED') {
        expect(template.readiness, TemplateReadinessState.invalid);
        expect(
          structuralDiagnostics.any(
            (d) =>
                d.severity == 'ERROR' &&
                d.message.contains('Pack and selling unit sets'),
          ),
          true,
        );
        expect(
          (candidate['remainingDomainReviews'] as List).any(
            (r) => r['blocking'] == true,
          ),
          true,
        );
        expect(template.unitRules.conversionAllowed, false);
        return;
      }
      expect(template.readiness, TemplateReadinessState.ready);
      expect(structuralDiagnostics, isEmpty, reason: '$structuralDiagnostics');
      final rules = template.unitRules;
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
              Phase10CFixture.unitId(base);
          final result = await fixture.validate(converted);
          expect(
            result.isValid,
            true,
            reason: '${candidate['name']} base $base: ${result.errors}',
          );
          conversionCases++;
        }
      } else {
        final attempted = fixture.state(template);
        ((attempted['variants'] as List).single as Map)['_packaging'] = true;
        final result = await fixture.validate(attempted);
        expect(
          result.errors.any((e) => e.code == 'CONVERSION_NOT_ALLOWED'),
          true,
        );
        conversionCases++;
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  final discovered = Process.runSync('python3', [
    '-B',
    '-c',
    'import json,unittest; from tool.tests.test_catalogue_phase10c import CanonicalContentProof; print(json.dumps(unittest.TestLoader().getTestCaseNames(CanonicalContentProof)))',
  ]);
  if (discovered.exitCode != 0) {
    throw StateError('${discovered.stderr}');
  }
  for (final name
      in (jsonDecode(discovered.stdout as String) as List).cast<String>()) {
    test('Phase 10C ${name.replaceAll('_', ' ')}', () async {
      final result = await Process.run('python3', [
        '-B',
        '-m',
        'unittest',
        'tool.tests.test_catalogue_phase10c.CanonicalContentProof.$name',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}

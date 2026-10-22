"""Release 4 proofs using committed evidence and generated artifacts; no network/DB."""
import copy
import json
from collections import Counter
from pathlib import Path
import unittest

from tool.catalogue_phase10e import (
    build, canonical, digest, logical, runtime_fingerprint, ID_FIELDS,
    OLD_BASEMENT, OLD_PAYLOAD, LIQUID, CEMENTITIOUS,
)


class Release4Proof(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content = json.loads(Path('docs/phase10c-canonical-content.json').read_text())
        cls.audit = json.loads(Path('docs/phase10a-catalogue-audit.json').read_text())
        cls.review = json.loads(Path('docs/catalogue-release-v4-review.json').read_text())
        cls.rows = json.loads(Path('test/fixtures/system_catalogue_v4.json').read_text())
        cls.diff = json.loads(Path('docs/phase10e-installed-v3-v4-diff.json').read_text())

    def test_deterministic_generated_artifacts_match(self):
        review, rows = build(self.content, self.audit)
        self.assertEqual(review, self.review)
        self.assertEqual(rows, self.rows)
        self.assertEqual(runtime_fingerprint(rows), review['contentFingerprint'])
        self.assertEqual(digest(logical(rows)), review['semanticFingerprintSha256'])
        self.assertEqual(build(self.content, self.audit), (review, rows))

    def test_input_record_order_does_not_change_release(self):
        reordered = copy.deepcopy(self.content)
        reordered['candidates'].reverse()
        reordered['attributeDefinitions'].reverse()
        for candidate in reordered['candidates']:
            candidate['attributes'].reverse()
            for attribute in candidate['attributes']:
                attribute['options'].reverse()
        audit = copy.deepcopy(self.audit)
        audit['records'].reverse()
        review, rows = build(reordered, audit)
        self.assertEqual(rows, self.rows)
        self.assertEqual(review['contentFingerprint'], self.review['contentFingerprint'])
        self.assertEqual(review['semanticFingerprintSha256'], self.review['semanticFingerprintSha256'])

    def test_137_accounting_preserves_all_other_135_contracts(self):
        previous = {c['canonicalId']: c for c in self.content['candidates']}
        current = {c['canonicalId']: c for c in self.review['canonicalCandidates']}
        self.assertEqual(len(previous), 136)
        self.assertEqual(len(current), 137)
        self.assertEqual(set(current), (set(previous) - {OLD_BASEMENT}) | {LIQUID, CEMENTITIOUS})
        for id_, candidate in previous.items():
            if id_ != OLD_BASEMENT:
                self.assertEqual(current[id_], candidate)
        self.assertTrue(all(c['intendedSelectability'] == 'SELECTABLE_READY' for c in current.values()))
        self.assertFalse(any(r['blocking'] for c in current.values() for r in c['remainingDomainReviews']))

    def test_split_units_and_identities_are_distinct_without_presentation_defaults(self):
        candidates = {c['canonicalId']: c for c in self.review['canonicalCandidates']}
        for id_, names, dimension in [(LIQUID, ['Litre', 'Millilitre'], 'VOLUME'),
                                      (CEMENTITIOUS, ['Kilogram', 'Gram'], 'MASS')]:
            c = candidates[id_]
            rules = c['unitRules']
            for key in ['allowedPackUnits', 'allowedBaseUnits', 'allowedSellingUnits']:
                self.assertEqual(rules[key], names)
            self.assertEqual(rules['defaultPackUnit'], names[0])
            self.assertEqual(rules['defaultBaseUnit'], names[0])
            self.assertIsNone(rules['defaultSellingUnit'])
            self.assertFalse(rules['conversionAllowed'])
            self.assertEqual(rules['conversionDimension'], dimension)
            attrs = {a['attributeId']: a for a in c['attributes']}
            self.assertEqual(attrs['usage']['defaultValue'], 'Interior & Exterior')
            self.assertEqual(attrs['surface']['defaultValue'], ['Concrete', 'Wall', 'Floor'])
            self.assertIsNone(attrs['soldAs']['defaultValue'])
            self.assertNotIn('finish', attrs)
            self.assertNotIn('colourType', attrs)
        self.assertTrue(set(candidates[LIQUID]['unitRules']['allowedBaseUnits']).isdisjoint(
            candidates[CEMENTITIOUS]['unitRules']['allowedBaseUnits']))
        self.assertTrue(all(d['id'] not in candidates for d in self.review['oldBasementDisposition']))

    def test_identity_and_references_and_orphans_and_duplicates_zero(self):
        ids = {}
        for collection, rows in self.rows.items():
            ids[collection] = {r['id'] for r in rows}
            self.assertEqual(len(ids[collection]), len(rows))
            self.assertTrue(all(r['id'] == r[ID_FIELDS[collection]] for r in rows))
        names = Counter((r['categoryId'], ' '.join(r['name'].casefold().split()))
                        for r in self.rows['product_subcategories'])
        self.assertTrue(all(n == 1 for n in names.values()))
        self.assertTrue(all(r['categoryId'] in ids['product_categories'] for r in self.rows['product_subcategories']))
        pairs = Counter((r['subcategoryId'], r['attributeId']) for r in self.rows['subcategory_attribute_templates'])
        self.assertTrue(all(n == 1 for n in pairs.values()))
        options = Counter((r['attributeId'], r['name']) for r in self.rows['product_attribute_options'])
        self.assertTrue(all(n == 1 for n in options.values()))
        for row in self.rows['subcategory_attribute_templates']:
            self.assertIn(row['subcategoryId'], ids['product_subcategories'])
            self.assertIn(row['attributeId'], ids['product_attributes'])
            self.assertTrue(all((row['attributeId'], o) in options for o in row['options']))
            self.assertEqual(len(row['options']), len(set(row['options'])))
        self.assertTrue(all(r['attributeId'] in ids['product_attributes'] for r in self.rows['product_attribute_options']))

    def test_defaults_levels_and_condition_scopes_zero_defects(self):
        for candidate in self.review['canonicalCandidates']:
            attributes = {a['attributeId']: a for a in candidate['attributes']}
            self.assertEqual(len(attributes), len(candidate['attributes']))
            for a in attributes.values():
                self.assertIn(a['level'], ['product', 'variant'])
                options = [o['name'] for o in a['options']]
                if a['dataType'] == 'SELECT':
                    self.assertTrue(options)
                    if a['defaultValue'] is not None:
                        self.assertIn(a['defaultValue'], options)
                if a['dataType'] == 'MULTI_SELECT' and a['defaultValue'] is not None:
                    self.assertTrue(set(a['defaultValue']) <= set(options))
                for condition in a['conditions']:
                    self.assertIn(condition['targetAttributeId'], attributes)
                    self.assertIn(condition['scope'], ['product', 'variant', 'any_variant'])
            rules = candidate['unitRules']
            for allowed, default in [('allowedPackUnits', 'defaultPackUnit'), ('allowedBaseUnits', 'defaultBaseUnit'),
                                     ('allowedSellingUnits', 'defaultSellingUnit')]:
                if allowed != 'allowedBaseUnits' or rules['conversionAllowed']:
                    self.assertTrue(rules[allowed])
                if rules[default] is not None:
                    self.assertIn(rules[default], rules[allowed])

    def test_labels_do_not_generate_parallel_ids(self):
        changed = copy.deepcopy(self.content)
        for candidate in changed['candidates']:
            candidate['name'] += ' Display formatting'
        _, rows = build(changed, self.audit)
        for collection in self.rows:
            self.assertEqual([r['id'] for r in rows[collection]], [r['id'] for r in self.rows[collection]])
        self.assertNotEqual(runtime_fingerprint(rows), self.review['contentFingerprint'])

    def test_semantic_default_option_unit_changes_change_fingerprints(self):
        for field in ['default', 'option', 'units', 'placement', 'requiredness']:
            rows = copy.deepcopy(self.rows)
            if field == 'units':
                rows['product_subcategories'][0]['unitRules']['conversionAllowed'] ^= True
            else:
                row = next(r for r in rows['subcategory_attribute_templates'] if r['dataType'] == 'SELECT')
                if field == 'default': row['defaultValue'] = 'SEMANTIC-CHANGE'
                if field == 'option': row['options'].append('SEMANTIC-CHANGE')
                if field == 'placement': row['attributeLevel'] = 'VARIANT' if row['attributeLevel'] == 'PRODUCT' else 'PRODUCT'
                if field == 'requiredness': row['required'] ^= True
            self.assertNotEqual(runtime_fingerprint(rows), self.review['contentFingerprint'])
            self.assertNotEqual(digest(logical(rows)), self.review['semanticFingerprintSha256'])
        rows = copy.deepcopy(self.rows)
        for collection in rows.values():
            for row in collection: row['updatedAt'] = 'IGNORED-NONSEMANTIC-TIMESTAMP'
        self.assertEqual(runtime_fingerprint(rows), self.review['contentFingerprint'])

    def test_migration_interlock_accounts_for_every_row_and_never_approves(self):
        entries = self.diff['entries']
        self.assertEqual(len(entries), len({(e['collection'], e['documentId']) for e in entries}))
        self.assertEqual(self.diff['counts']['rows'], len(entries))
        self.assertEqual(self.diff['counts']['actions'], dict(Counter(e['action'] for e in entries)))
        self.assertEqual(self.diff['counts']['classifications'], dict(Counter(e['classification'] for e in entries)))
        for collection, rows in self.rows.items():
            covered = {e['documentId'] for e in entries if e['collection'] == collection and e['action'] in ['INSERT', 'REPLACE']}
            self.assertEqual(covered, {r['id'] for r in rows})
        classifications = {'CANONICAL_KEEP', 'NEW_CANONICAL', 'LEGACY_RETAIN_REQUIRED', 'MIGRATION_REQUIRED',
                           'REVIEW_REQUIRED', 'SAFE_UNREFERENCED_RETIREMENT_CANDIDATE'}
        for e in entries:
            self.assertIn(e['classification'], classifications)
            self.assertEqual(e['referenceCount'], len(e['referenceRecords']))
            self.assertEqual(e['referencesByTable'], dict(Counter(r['table'] for r in e['referenceRecords'])))
            for key in ['approved', 'migrationApproved', 'retirementApproved']: self.assertFalse(e[key])
            if e['referenceCount'] and e['action'] in ['DEACTIVATE', 'TOMBSTONE']:
                self.assertIn(e['classification'], ['LEGACY_RETAIN_REQUIRED', 'MIGRATION_REQUIRED'])
        self.assertGreater(self.diff['counts']['activeOmissions'], 0)
        self.assertEqual(self.diff['productionBefore'], self.diff['productionAfter'])
        self.assertFalse(self.diff['productionInstallationAllowed'])
        self.assertTrue(all(q['disposition'] == 'BLOCK_MIGRATION_NO_REWRITE' for q in self.diff['protectedLegacyQueries']))
        self.assertEqual(self.diff['counts']['protectedLegacyQueries'], len(self.diff['protectedLegacyQueries']))

    def test_duplicate_legacy_and_live_approvals_remain_false(self):
        self.assertEqual(len(self.review['duplicateDecisions']), 10)
        ready = {c['canonicalId'] for c in self.review['canonicalCandidates']}
        for d in self.review['duplicateDecisions']:
            self.assertIn(d['canonicalId'], ready)
            self.assertNotIn(d['legacyId'], ready)
            self.assertFalse(d['approved'])
            self.assertFalse(d['migrationApproved'])
        for d in self.review['oldBasementDisposition']:
            self.assertFalse(d['migrationApproved'])
            self.assertFalse(d['retirementApproved'])
            self.assertFalse(d['automaticReferenceMappingAllowed'])
        for key in ['approvedForLiveExecution', 'productionMigrationApproved', 'firestorePublicationApproved']:
            self.assertFalse(self.review[key])
            self.assertFalse(self.rows['product_catalogue_releases'][0][key])
        self.assertTrue(self.review['isolatedOnly'])
        self.assertTrue(all(c['name'] not in ['Miscellaneous', 'Hand Sanitizers', 'Interior Wall Paint'] for c in self.review['canonicalCandidates']))


if __name__ == '__main__':
    unittest.main()

"""Audited snapshot proofs plus independent semantic and read-only guard checks."""
import copy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from tool import catalogue_phase10a as audit
from tool import catalogue_phase8 as storage

ARTIFACT = Path('docs/phase10a-catalogue-audit.json')

class CatalogueIntentProof(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads(ARTIFACT.read_text())

    def test_all_disabled_flags_have_evidence_backed_disposition(self):
        records = {r['documentId']: r for r in self.evidence['records']}
        disabled = self.evidence['disabledDispositions']
        self.assertEqual(len(disabled), 88)
        self.assertEqual({d['documentId'] for d in disabled},
                         {id_ for id_, r in records.items() if r['templateSelectable'] is False})
        for d in disabled:
            self.assertEqual(d['disposition'], audit.disabled_disposition(records[d['documentId']])[0])
            self.assertFalse(d['approved'])

    def test_requiredness_default_option_placement_and_order_are_semantic(self):
        baseline = {'attributeId': 'finish', 'required': False, 'defaultValue': 'Satin',
                    'options': ['Satin', 'Gloss'], 'level': 'PRODUCT', 'sortOrder': 1}
        for key, value in {'required': True, 'defaultValue': 'Gloss', 'options': ['Satin'],
                           'level': 'VARIANT', 'sortOrder': 2}.items():
            with self.subTest(key=key):
                changed = {**baseline, key: value}
                self.assertEqual(audit.semantic_classification(baseline, changed), 'SEMANTIC_CONFLICT')
        self.assertEqual(audit.semantic_fields({**baseline, 'updatedAt': 'old'}),
                         audit.semantic_fields({**baseline, 'updatedAt': 'new'}))

    def test_reference_counts_include_config_keys_history_and_pending_queries(self):
        tables = {'local_product_subcategories': [{'remoteId': 'old', 'subcategoryId': 'old',
                    'payloadJson': json.dumps(storage.encode({'subcategoryId': 'old'}))}],
                  'local_products': [{'remoteId': 'P', 'subcategoryId': 'old',
                    'payloadJson': json.dumps(storage.encode({'subcategoryId': 'old'}))}],
                  'history': [{'id': 'H', 'body': '{"subcategoryId":"old"}'}],
                  'sync_queries': [{'queryId': 'Q', 'spec': '{"where":["old"]}'}],
                  'config': [{'id': 'C', 'body': '{"old":{"enabled":true}}'}]}
        result = audit.reference_inventory({'isolated': tables}, {'old'})['old']
        self.assertEqual(result['referencingRecords'], 4)
        self.assertEqual(result['productReferences'], 1)
        self.assertEqual(result['syncQueryReferences'], 1)
        self.assertEqual(result['referenceOccurrences'], 4)

    def test_read_only_connection_rejects_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'proof.db'
            db = sqlite3.connect(path)
            db.execute('CREATE TABLE proof(id TEXT)'); db.commit(); db.close()
            before = path.read_bytes()
            with storage.read_only(path) as ro:
                self.assertEqual(ro.execute('PRAGMA query_only').fetchone()[0], 1)
                with self.assertRaises(sqlite3.OperationalError):
                    ro.execute("INSERT INTO proof VALUES ('forbidden')")
            self.assertEqual(before, path.read_bytes())
            self.assertFalse(any(Path(str(path)+suffix).exists() for suffix in ['-wal','-shm','-journal']))

    def test_identity_mismatch_is_not_an_approved_alias(self):
        for record in self.evidence['identityMismatchReview']:
            self.assertNotEqual(record['documentId'], record['payloadId'])
            self.assertEqual(record['recommendedCanonicalCandidate'], record['activeDefinitionDocument'])
            self.assertTrue(record['templateDifferences'])
            self.assertFalse(record['approved'])
            self.assertEqual(record['recommendedApproval'], 'NEEDS_DOMAIN_CONFIRMATION')


def pair_test(name):
    def run(self):
        pair = next(p for p in self.evidence['duplicateComparisons'] if p['name'] == name)
        left, right = pair['contracts']
        self.assertEqual(left['parentId'], right['parentId'])
        self.assertEqual(left['scope'], right['scope'])
        self.assertEqual(pair['semanticClassification'], audit.semantic_classification(left, right))
        self.assertEqual(pair['differences'], audit.differences(left, right))
        self.assertTrue(pair['differences'], 'Different contracts cannot be silently equated')
        self.assertFalse(pair['approved'])
        self.assertEqual(pair['recommendedApproval'], 'NEEDS_DOMAIN_CONFIRMATION')
        for id_, references in pair['references'].items():
            self.assertEqual(references['referencingRecords'], len(references['records']))
            self.assertEqual(references['referenceOccurrences'], sum(len(r['locations']) for r in references['records']))
            self.assertEqual(references['templateReferences'], sum(r['table'] == storage.TEMPLATE for r in references['records']))
        # Equal resolved forms do not erase differences in source contracts.
        rewritten = copy.deepcopy(left)
        rewritten['resolvedAttributes'] = copy.deepcopy(right['resolvedAttributes'])
        self.assertNotEqual(audit.semantic_classification(rewritten, right), 'EXACT_EQUIVALENT')
    return run

for name in ['Tile Adhesives','Thinners','Epoxy Flooring','Acrylic Putty','Waterproof Wall Putty',
             'Acrylic Sealants','Bathroom & Kitchen Waterproofing','Exterior Wall Waterproofing',
             'Interior Dampness Treatment','Roof & Terrace Waterproofing']:
    setattr(CatalogueIntentProof, 'test_duplicate_' + name.lower().replace(' & ', '_').replace(' ', '_'), pair_test(name))

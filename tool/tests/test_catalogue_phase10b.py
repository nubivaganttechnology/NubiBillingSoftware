import copy
import json
from pathlib import Path
import unittest
from tool import catalogue_phase10b as builder

class CatalogueIntentNormalizationProof(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.audit=json.loads(Path('docs/phase10a-catalogue-audit.json').read_text())
        cls.saved=json.loads(Path('docs/phase10b-intended-catalogue.json').read_text())

    def test_deterministic_non_importable_model_matches_evidence(self):
        before=Path('docs/phase10a-catalogue-audit.json').read_bytes()
        self.assertEqual(self.saved,builder.build(self.audit))
        changed=copy.deepcopy(self.audit);changed['records'].reverse();changed['duplicateComparisons'].reverse()
        # Input ordering cannot change semantic candidate/record output. Source
        # evidence fingerprint intentionally records exact input evidence ordering.
        reordered=builder.build(changed)
        self.assertEqual(reordered['intentFingerprint'],self.saved['intentFingerprint'])
        self.assertEqual(reordered['duplicateReviewManifest'],self.saved['duplicateReviewManifest'])
        self.assertEqual(reordered['records'],self.saved['records'])
        self.assertEqual(reordered['canonicalContentCandidates'],self.saved['canonicalContentCandidates'])
        self.assertFalse(self.saved['importable']);self.assertFalse(self.saved['approvedForLiveExecution'])
        self.assertNotIn('product_catalogue_releases',self.saved)
        self.assertEqual(before,Path('docs/phase10a-catalogue-audit.json').read_bytes())

    def test_all_87_schema_residue_records_are_pending_without_installed_flag_changes(self):
        expected={d['documentId'] for d in self.audit['disabledDispositions'] if d['disposition']=='PROBABLY_SHOULD_BE_SELECTABLE'}
        actual=[r for r in self.saved['records'] if r['schemaResidue']]
        self.assertEqual(len(actual),87);self.assertEqual({r['documentId'] for r in actual},expected)
        for r in actual:
            self.assertEqual(r['intendedSelectability'],'SELECTABLE_PENDING_CONTENT_VALIDATION')
            self.assertIs(r['installedTemplateSelectable'],False);self.assertFalse(r['approved'])

    def test_miscellaneous_hand_sanitizers_and_legacy_paint_remain_excluded(self):
        for r in self.saved['records']:
            if r['name']=='Miscellaneous':self.assertEqual(r['intendedSelectability'],'DISABLED_DOMAIN_REVIEW')
            if r['name'] in {'Hand Sanitizers','Interior Wall Paint'}:self.assertEqual(r['intendedSelectability'],'EXCLUDED')
        excluded={r['documentId'] for r in self.saved['records'] if r['intendedSelectability'] in {'EXCLUDED','DISABLED_DOMAIN_REVIEW'}}
        self.assertEqual(len(excluded),3)
        self.assertFalse(excluded & {d['canonicalCandidateId'] for d in self.saved['canonicalContentCandidates']})

    def test_duplicate_manifest_never_approves_or_includes_both_candidates(self):
        pairs=self.saved['duplicateReviewManifest'];self.assertEqual(len(pairs),10)
        definitions={d['canonicalCandidateId'] for d in self.saved['canonicalContentCandidates']}
        preferred={p['preferredCanonicalCandidate'] for p in self.audit['duplicateComparisons']}
        self.assertEqual({p['canonicalCandidateId'] for p in pairs},preferred)
        for p in pairs:
            self.assertIn(p['canonicalCandidateId'],definitions);self.assertNotIn(p['legacyCandidateId'],definitions)
            self.assertFalse(p['approved']);self.assertFalse(p['migrationApproved'])
            self.assertTrue(p['semanticConflictSummary']);self.assertTrue(p['remainingDomainQuestion'])

    def test_ceiling_basement_prospective_ids_preserve_original_payload_evidence(self):
        expected={'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS':'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS',
                  'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING':'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT'}
        self.assertEqual({r['prospectiveCanonicalId']:r['installedPayloadId'] for r in self.saved['identityMismatchReview']},expected)
        for r in self.saved['identityMismatchReview']:
            self.assertFalse(r['approved']);self.assertFalse(r['migrationApproved'])
            self.assertEqual(r['prospectiveContract']['canonicalCandidateId'],r['prospectiveCanonicalId'])
            self.assertEqual(r['prospectiveContract']['templateSemanticsSource'],'CURRENT_DOCUMENT_TEMPLATE_GROUP')
            source=next(m for m in self.audit['identityMismatchReview'] if m['documentId']==r['prospectiveCanonicalId'])
            self.assertEqual(r['prospectiveContract']['authoredTemplateContract'],source['documentTemplates'])
            self.assertEqual(set(r['prospectiveContract']['allowedAttributes']),{a['attributeId'] for a in source['documentTemplates']})

    def test_floor_usage_is_localized_to_epoxy_candidate(self):
        original={r['documentId']:r for r in self.audit['records']}
        for d in self.saved['canonicalContentCandidates']:
            usage=next((a for a in d['attributes'] if a['attributeId']=='usage'),None)
            old=next((a for a in original[d['canonicalCandidateId']]['productAttributes'] if a['attributeId']=='usage'),None)
            if d['canonicalCandidateId']=='SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING':
                self.assertEqual(usage['defaultValue'],'Floor');self.assertIn('Floor',[o['name'] for o in usage['options']])
            elif d.get('templateSemanticsSource')=='CURRENT_DOCUMENT_TEMPLATE_GROUP':
                authored=next((a for a in d['authoredTemplateContract'] if a['attributeId']=='usage'),None)
                self.assertIsNotNone(authored)
                self.assertEqual(usage['defaultValue'],authored.get('defaultValue'))
                if 'options' in authored:
                    self.assertEqual([o['name'] for o in usage['options']],authored['options'])
            elif usage and old:
                self.assertEqual(usage['options'],old['options']);self.assertEqual(usage['defaultValue'],old['defaultValue'])

    def test_family_units_never_create_global_base_fallback(self):
        for d in self.saved['canonicalContentCandidates']:
            rule=d['unitRules'];self.assertLessEqual(len(rule['allowedBaseUnits']),2)
            if rule['conversionAllowed']:
                self.assertIn(rule['conversionDimension'],{'MASS','VOLUME'})
                self.assertTrue(rule['conversionRequiresExplicitFactor'])
                self.assertTrue(all(builder.MEASUREMENTS.get(u)==rule['conversionDimension'] for u in rule['allowedBaseUnits']))
            if d['family'] in {'SEALANT','SPRAY_AEROSOL','DIY_PRESENTATION'}:
                self.assertFalse(rule['conversionAllowed']);self.assertEqual(rule['allowedBaseUnits'],[])
        self.assertFalse(self.saved['conversionDefaultsEnabled'])

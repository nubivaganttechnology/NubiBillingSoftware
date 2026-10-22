"""Independent structural and evidence checks of the Phase 10C content review."""
import copy
import json
from pathlib import Path
import unittest
from tool import catalogue_phase10c as compiler

class CanonicalContentProof(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.b=json.loads(Path('docs/phase10b-intended-catalogue.json').read_text())
        cls.a=json.loads(Path('docs/phase10a-catalogue-audit.json').read_text())
        cls.c=json.loads(Path('docs/phase10c-canonical-content.json').read_text())
        cls.records=cls.c['candidates']

    def test_all_136_exact_identity_accounting_and_no_live_approval(self):
        expected={d['canonicalCandidateId'] for d in self.b['canonicalContentCandidates']}
        self.assertEqual(len(self.records),136)
        self.assertEqual({d['canonicalId'] for d in self.records},expected)
        self.assertEqual(len(expected),len(self.records))
        self.assertFalse(self.c['importable']);self.assertFalse(self.c['approvedForLiveExecution'])
        self.assertNotIn('releaseVersion',self.c)
        for d in self.records:
            self.assertFalse(d['migrationApproved']);self.assertFalse(d['approvedForLiveExecution'])
            self.assertEqual(d['sourceEvidence']['phase10bCandidateId'],d['canonicalId'])

    def test_artifact_determinism_and_order_independence(self):
        self.assertEqual(self.c,compiler.build(self.b,self.a))
        b=copy.deepcopy(self.b);a=copy.deepcopy(self.a)
        b['canonicalContentCandidates'].reverse();b['duplicateReviewManifest'].reverse();a['records'].reverse()
        for d in b['canonicalContentCandidates']:d['attributes'].reverse()
        # Raw source-contract digests intentionally retain exact authoring evidence.
        rebuilt=compiler.build(b,a)
        for original,other in zip(self.records,rebuilt['candidates']):
            self.assertEqual(original['attributes'],other['attributes'])
            self.assertEqual(original['unitRules'],other['unitRules'])
        # Rebuilding unchanged evidence must match the published complete fingerprint.
        self.assertEqual(rebuilt['fingerprint'],self.c['fingerprint'])
        self.assertEqual(self.c['fingerprint'],compiler.logical_fingerprint(self.c))

    def test_87_residue_promoted_only_in_review_and_exclusions_retained(self):
        residue={r['documentId'] for r in self.b['records'] if r['schemaResidue']}
        self.assertEqual(len(residue),87)
        by_id={r['canonicalId']:r for r in self.records}
        for id_ in residue:self.assertEqual(by_id[id_]['intendedSelectability'],'SELECTABLE_READY')
        old=[r for r in self.c['noncanonicalRecords'] if r['name'] in {'Miscellaneous','Hand Sanitizers','Interior Wall Paint'}]
        self.assertEqual(len(old),3)
        self.assertTrue(all(r['documentId'] not in by_id for r in old))
        for r in self.b['records']:
            if r['schemaResidue']:self.assertIs(r['installedTemplateSelectable'],False)

    def test_zero_invalid_defaults_duplicate_options_and_forbidden_pricing_hsn(self):
        forbidden={'purchaseRate','sellingPrice','mrp','hsnCode','hsnSac'}
        for d in self.records:
            ids=[a['attributeId'] for a in d['attributes']]
            self.assertEqual(len(ids),len(set(ids)));self.assertFalse(forbidden & set(ids))
            for a in d['attributes']:
                names=[o['name'] for o in a['options']]
                self.assertEqual(len(names),len({v.casefold() for v in names}))
                value=a['defaultValue']
                if value is None:continue
                if a['dataType']=='SELECT':self.assertIn(value,names,(d['canonicalId'],a['attributeId']))
                if a['dataType']=='MULTI_SELECT':
                    self.assertIsInstance(value,list);self.assertTrue(set(value)<=set(names))
                if a['dataType']=='NUMBER':self.assertIsInstance(value,(int,float))

    def test_supported_conditions_and_single_product_colour_mode(self):
        for d in self.records:
            attrs={a['attributeId']:a for a in d['attributes']}
            for a in attrs.values():
                for field in ['visibleWhen','requiredWhen']:
                    cond=a[field]
                    if cond:
                        self.assertIn(cond['attributeId'],attrs)
                        self.assertIn(cond['scope'],['PRODUCT','VARIANT','ANY_VARIANT','ALL_VARIANTS'])
                        self.assertTrue(cond['in'])
                if a['attributeId'] in {'colourType','finish','productColour'}:self.assertEqual(a['level'],'product')
                if a['attributeId'] in {'shade','shadeCode','baseType','baseCode','brushSize','rollerWidth','grit'}:self.assertEqual(a['level'],'variant')
            if 'colourType' in attrs:
                self.assertFalse(attrs['colourType']['required'])
                modes=[o['name'] for o in attrs['colourType']['options']]
                if 'Multiple Ready Colours' in modes:self.assertTrue({'shade','shadeCode'}<=set(attrs))
                if 'Tintable' in modes:self.assertTrue({'baseType','baseCode'}<=set(attrs))
                for key in ['productColour','shade','shadeCode','colourFamily','baseType','baseCode']:
                    if key in attrs:
                        self.assertNotIn('Not Applicable',attrs[key]['visibleWhen']['in'])
                        self.assertNotIn('Clear/Transparent',attrs[key]['visibleWhen']['in'])

    def test_family_inappropriate_chemistry_removed_and_sku_dimensions_placed(self):
        no_chem={'ADHESIVE','SEALANT','ADMIXTURE','TOOLS','MASKING_TAPE','SANDPAPER','WALL_COVERING','DIY_PRESENTATION','ALLIED','WOOD_TREATMENT'}
        forbidden={'finish','numberOfCoats','dilutionType','dilutionRatio','colourType','shade','baseType'}
        for d in self.records:
            ids={a['attributeId'] for a in d['attributes']}
            if d['family'] in no_chem:self.assertFalse(ids & forbidden,(d['canonicalId'],ids&forbidden))
            self.assertTrue({'packSize','unit','soldAs'}<=ids)
            if d['family']=='PRIMER':self.assertNotIn('finish',ids)

    def test_exact_application_profiles_and_no_wood_enamel_defaults(self):
        for d in self.records:
            if d['family']=='INTERIOR_COATING':self.assertEqual(d['defaults']['usage'],'Interior');self.assertEqual(d['defaults']['surface'],['Wall'])
            if d['family']=='EXTERIOR_COATING':self.assertEqual(d['defaults']['usage'],'Exterior')
            if d['family']=='INTERIOR_EXTERIOR_COATING':self.assertEqual(d['defaults']['usage'],'Interior & Exterior')
            if d['family']=='FLOOR_COATING':self.assertEqual(d['defaults']['usage'],'Floor')
            if d['family']=='ENAMEL':
                self.assertNotEqual(d['defaults'].get('colourType'),'Clear/Transparent')
                self.assertNotEqual(d['defaults'].get('dilutionType'),'PU Thinner')
            if d['canonicalId']=='SYS_SUBCATEGORY_SYS_CATEGORY_METAL_WOOD_ENAMELS_SATIN_ENAMELS':self.assertEqual(d['defaults']['finish'],'Satin')
            if d['family']=='CEILING_PAINT':self.assertEqual(d['defaults']['surface'],['Ceiling']);self.assertEqual(d['defaults']['usage'],'Interior')
            if d['canonicalId']=='SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE':self.assertEqual(d['defaults']['usage'],'Roof');self.assertEqual(d['defaults']['surface'],['Roof'])
            if d['canonicalId']=='SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL':self.assertEqual(d['defaults']['surface'],['Wall','Concrete'])

    def test_unit_rules_preserved_restricted_and_domain_block_is_explicit(self):
        old={d['canonicalCandidateId']:d for d in self.b['canonicalContentCandidates']}
        blocked=[]
        for d in self.records:
            expected=copy.deepcopy(old[d['canonicalId']]['unitRules'])
            if expected['defaultSellingUnit'] is None and len(expected['allowedSellingUnits'])==1:
                expected['defaultSellingUnit']=expected['allowedSellingUnits'][0]
            self.assertEqual(d['unitRules'],expected)
            self.assertFalse(d['conversionDefault']);self.assertLessEqual(len(d['unitRules']['allowedBaseUnits']),2)
            if d['intendedSelectability']=='DOMAIN_REVIEW_REQUIRED':
                blocked.append(d['canonicalId']);self.assertTrue(any(r['blocking'] for r in d['remainingDomainReviews']))
            else:
                self.assertTrue(d['unitRules']['allowedPackUnits']);self.assertTrue(d['unitRules']['allowedSellingUnits'])
            for a in d['attributes']:
                if a['dataType']=='SELECT' and not a['options']:
                    self.assertEqual(d['intendedSelectability'],'DOMAIN_REVIEW_REQUIRED')
                    self.assertTrue(any(r['blocking'] and r['field']==a['attributeId'] for r in d['remainingDomainReviews']))
        self.assertEqual(blocked,['SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING'])

    def test_duplicate_decisions_and_document_identity_do_not_approve_migration(self):
        by_id={d['canonicalId']:d for d in self.records}
        self.assertEqual(len(self.c['duplicateDecisions']),10)
        for pair in self.c['duplicateDecisions']:
            self.assertIn(pair['canonicalId'],by_id);self.assertNotIn(pair['legacyId'],by_id)
            self.assertTrue(pair['semanticDecisions']);self.assertTrue(pair['sourceSemanticConflicts'])
            self.assertEqual({v['path'] for v in pair['semanticDecisions']},set(pair['sourceSemanticConflicts']))
            self.assertTrue(all(v['migrationApproved'] is False for v in pair['semanticDecisions']))
            self.assertFalse(pair['approved']);self.assertFalse(pair['migrationApproved'])
        self.assertEqual(len(self.c['identityMismatchReview']),2)
        for mismatch in self.c['identityMismatchReview']:
            d=by_id[mismatch['prospectiveCanonicalId']]
            self.assertEqual(d['sourceEvidence']['installedPayloadId'],mismatch['installedPayloadId'])
            self.assertEqual(d['sourceEvidence']['templateGroupSource'],'CURRENT_DOCUMENT_TEMPLATE_GROUP')
            self.assertFalse(mismatch['approved']);self.assertFalse(mismatch['migrationApproved'])

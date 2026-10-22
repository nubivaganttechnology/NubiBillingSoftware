"""Direct SQLite migration proofs. No test opens a production database."""
from dataclasses import replace
import json
from pathlib import Path
import sqlite3
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from catalogue_phase8 import (CatalogueCanonicalMapping as Mapping, SandboxCatalogueMigration,
    TABLES, TEMPLATE, decode, encode, inventory, load_rows, read_only, references, load_canonical_mappings)

FIXTURE = Path(__file__).resolve().parents[2] / 'test/fixtures/phase8_representative_legacy.json'
STAMP = '2026-10-04T00:00:00Z'


def row(id_, fields):
    fields = {'status': 'ACTIVE', 'scopeType': 'SYSTEM', 'catalogueId': 'TEST',
              'createdAt': 'original-created', 'updatedAt': 'original-updated', **fields}
    return {'remoteId': id_, 'payloadJson': json.dumps({k: encode(v) for k,v in fields.items()}),
            'status': fields['status'], 'isDeleted': 0, 'categoryId': fields.get('categoryId'),
            'subcategoryId': fields.get('subcategoryId'), 'syncStatus': 'SYNCED',
            'localRevision': 4, 'remoteUpdateTime': 'original-remote-version'}


def data():
    return {TABLES['category']: [row('C_OLD', {'categoryId': 'C_OLD', 'name': 'Walls'}),
                               row('C', {'categoryId': 'C', 'name': 'Walls', 'aliases':['Walls']})],
            TABLES['subcategory']: [row('S_OLD', {'subcategoryId':'S_OLD','categoryId':'C_OLD','name':'Emulsion','templateStatus':'READY'}),
                                    row('S', {'subcategoryId':'S','categoryId':'C','name':'Emulsion','templateStatus':'READY'})],
            TABLES['unit']: [row('L', {'unitId':'L','name':'L','measurementDimension':'VOLUME','unitKind':'MEASUREMENT','scaleToBase':1,'meaning':'litre'}),
                             row('LITRE', {'unitId':'LITRE','name':'Litre','measurementDimension':'VOLUME','unitKind':'MEASUREMENT','scaleToBase':1,'meaning':'litre'})],
            TABLES['product']: [row('P', {'productId':'P','categoryId':'C_OLD','subcategoryId':'S_OLD','name':'Original','sku':'LEGACY-P','barcode':'P-BC','attributeValues':{'usage':'Interior'}})],
            TABLES['variant']: [row('V', {'variantId':'V','productId':'P','sku':'KEEP-SKU','barcode':'KEEP-BC','unitId':'L','baseUnitId':'L','commercialUnitId':'L','packUnitId':'L','unitName':'L','quantity':20})],
            TEMPLATE: [row('T_OLD',{'templateId':'T_OLD','subcategoryId':'S_OLD','attributeId':'usage','attributeLevel':'PRODUCT','required':True}),
                       row('T',{'templateId':'T','subcategoryId':'S','attributeId':'usage','attributeLevel':'PRODUCT','required':True})],
            'local_product_attributes': [row('usage',{'attributeId':'usage','name':'Usage','dataType':'TEXT'})],
            'local_inventory_transactions': [row('H',{'productId':'P','variantId':'V','quantity':20,'unitName':'L'})],
            'local_purchase_bills': [row('B',{'lines':[{'productId':'P','variantId':'V','sku':'KEEP-SKU','barcode':'KEEP-BC'}]})],
            'local_roles': [], 'local_app_config': [], 'sync_outbox': []}


def plan():
    return [Mapping(t, a, b, 'Test-only reviewed mapping', approved=True,
                    semanticEvidence='Explicit fixture IDs/parents and reviewed semantic contract')
            for t,a,b in [('category','C_OLD','C'),('subcategory','S_OLD','S'),('unit','L','LITRE')]]


class CatalogueMigrationProof(unittest.TestCase):
    def setUp(self): self.sandbox = SandboxCatalogueMigration(data())
    def tearDown(self): self.sandbox.close()
    def fields(self,table,id_):
        r=self.sandbox.db.execute(f'SELECT payloadJson FROM {table} WHERE remoteId=?',(id_,)).fetchone()
        return decode(json.loads(r[0]))
    def migrate(self, mappings=None, failure=None):
        return self.sandbox.apply(mappings or plan(),'TEST-8',STAMP, failure)
    def assert_rejected(self,mappings,match):
        before=self.sandbox.snapshot()
        with self.assertRaisesRegex(ValueError,match): self.migrate(mappings)
        self.assertEqual(self.sandbox.snapshot(),before)
    def change(self,table,id_,**fields):
        current=self.fields(table,id_);current.update(fields)
        self.sandbox.db.execute(f'UPDATE {table} SET payloadJson=? WHERE remoteId=?',
                               (json.dumps({k:encode(v)for k,v in current.items()}),id_));self.sandbox.db.commit()

    def test_retired_category_preserves_product_id(self):
        self.change(TABLES['category'],'C_OLD',status='INACTIVE')
        self.migrate()
        p=self.fields(TABLES['product'],'P');self.assertEqual(p['categoryId'],'C');self.assertEqual(p['productId'],'P')

    def test_retired_subcategory_preserves_variant_identity(self):
        self.change(TABLES['subcategory'],'S_OLD',status='INACTIVE')
        before=self.fields(TABLES['variant'],'V');self.migrate()
        after=self.fields(TABLES['variant'],'V')
        for k in ['variantId','productId','sku','barcode']:self.assertEqual(after[k],before[k])
        self.assertEqual(self.fields(TABLES['product'],'P')['subcategoryId'],'S')

    def test_duplicate_is_kept_until_all_references_move(self):
        seen=[]
        def observe(stage,db):
            if stage in ['products','variants','dependencies','before_retirement']:
                self.assertEqual(self.fields(TABLES['category'],'C_OLD')['status'],'ACTIVE')
                self.assertEqual(self.fields(TABLES['subcategory'],'S_OLD')['status'],'ACTIVE')
                seen.append(stage)
            if stage=='before_retirement':
                self.assertFalse([r for r in references(load_rows(db)) if r['legacyId'] in {'C_OLD','S_OLD','L'}])
        self.migrate(failure=observe)
        self.assertEqual(len(seen),4)
        self.assertEqual(self.fields(TABLES['category'],'C_OLD')['status'],'INACTIVE')
        self.assertEqual(self.sandbox.db.execute(f'SELECT COUNT(*) FROM {TABLES["category"]}').fetchone()[0],2)
        self.assertEqual(self.sandbox.db.execute(f'SELECT COUNT(*) FROM {TEMPLATE}').fetchone()[0],2)

    def test_same_name_under_different_parents_never_auto_merges(self):
        inv=inventory(data())
        self.assertEqual(len(inv['sameNameDifferentValidParents']),1)
        self.assertFalse([m for m in inv['canonicalMappings'] if m['recordType']=='subcategory' and m['canonicalId']])
        self.assert_rejected([replace(plan()[1],canonicalId='S')],'Cross-parent')

    def test_business_category_not_merged_by_name(self):
        rows=data();f=decode(json.loads(rows[TABLES['category']][0]['payloadJson']));f.update(scopeType='BUSINESS',tenantId='T',businessId='B')
        rows[TABLES['category']][0]=row('C_OLD',f)
        m=next(m for m in inventory(rows)['canonicalMappings'] if m['legacyId']=='C_OLD')
        self.assertIsNone(m['canonicalId'])

    def test_l_alias_requires_exact_semantics(self):
        self.migrate();v=self.fields(TABLES['variant'],'V')
        for k in ['unitId','baseUnitId','commercialUnitId','packUnitId']:self.assertEqual(v[k],'LITRE')
        self.assertEqual(v['unitName'],'L')
        self.assertEqual(self.fields('local_inventory_transactions','H')['unitName'],'L')

    def test_unit_missing_dimension_is_domain_review_required(self):
        self.change(TABLES['unit'],'L',measurementDimension=None)
        self.assert_rejected(plan(),'Unit semantics')
        m=next(m for m in inventory(load_rows(self.sandbox.db))['canonicalMappings'] if m['legacyId']=='L')
        self.assertIsNone(m['canonicalId']);self.assertTrue(m['warnings'])

    def test_unit_scale_mismatch_rejected(self):
        self.change(TABLES['unit'],'L',scaleToBase=1000)
        self.assert_rejected(plan(),'Unit semantics')

    def test_packaging_never_merged_into_measurement(self):
        self.change(TABLES['unit'],'L',name='Can',unitKind='PACKAGING')
        self.assert_rejected(plan(),'Unit semantics')

    def test_orphan_template_group_detected(self):
        rows=data();rows[TEMPLATE].append(row('ORPHAN',{'subcategoryId':'ABSENT','attributeId':'usage','attributeLevel':'PRODUCT','required':True}))
        inv=inventory(rows);group=next(g for g in inv['orphanTemplateGroups'] if g['subcategoryId']=='ABSENT')
        self.assertFalse(group['subcategoryExists']);self.assertIn('ORPHAN_TEMPLATE_GROUP',group['classifications'])

    def test_ambiguous_orphan_requires_review_and_is_retained(self):
        rows=data();rows[TEMPLATE].append(row('ORPHAN',{'subcategoryId':'ABSENT','attributeId':'other','attributeLevel':'VARIANT'}))
        box=SandboxCatalogueMigration(rows)
        try:
            before=box.snapshot();g=next(g for g in inventory(rows)['orphanTemplateGroups']if g['subcategoryId']=='ABSENT')
            self.assertIn('DOMAIN_REVIEW_REQUIRED',g['classifications'])
            with self.assertRaisesRegex(ValueError,'semantics'):
                box.apply([Mapping('templateGroup','ABSENT','S','test',approved=True,semanticEvidence='test')],'X',STAMP)
            self.assertEqual(box.snapshot(),before)
        finally:box.close()

    def test_exact_approved_orphan_remap_retains_row_identity(self):
        rows=data();rows[TEMPLATE].append(row('ORPHAN',{'subcategoryId':'ABSENT','attributeId':'usage','attributeLevel':'PRODUCT','required':True}))
        box=SandboxCatalogueMigration(rows)
        try:
            box.apply([Mapping('templateGroup','ABSENT','S','Reviewed parent context',approved=True,semanticEvidence='Explicit test parent approval')],'X',STAMP)
            r=box.db.execute(f'SELECT payloadJson FROM {TEMPLATE} WHERE remoteId="ORPHAN"').fetchone()
            self.assertEqual(decode(json.loads(r[0]))['subcategoryId'],'S')
            self.assertEqual(decode(json.loads(r[0]))['status'],'INACTIVE')
        finally:box.close()

    def test_broken_variant_parent_detected_not_auto_repaired(self):
        self.change(TABLES['variant'],'V',productId='ABSENT_PRODUCT')
        before=self.fields(TABLES['variant'],'V')['productId']
        inv=inventory(load_rows(self.sandbox.db));self.assertEqual(len(inv['brokenReferences']),1)
        self.assertIn('BROKEN_REFERENCE',inv['brokenReferences'][0]['classifications'])
        self.migrate();self.assertEqual(self.fields(TABLES['variant'],'V')['productId'],before)

    def test_cycle_rejected(self):
        self.assert_rejected([plan()[0],Mapping('category','C','C_OLD','cycle',approved=True,semanticEvidence='test')],'cycle')

    def test_missing_target_rejected(self):
        self.assert_rejected([replace(plan()[0],canonicalId='MISSING')],'canonical target')

    def test_unapproved_or_ambiguous_mapping_rejected(self):
        self.assert_rejected([replace(plan()[0],approved=False)],'approval')
        self.assert_rejected([replace(plan()[0],canonicalId=None)],'approval')

    def test_product_or_variant_identity_mapping_rejected(self):
        self.assert_rejected([Mapping('product','P','OTHER','forbidden',approved=True,semanticEvidence='test')],'Identity/history')
        self.assert_rejected([Mapping('variant','V','OTHER','forbidden',approved=True,semanticEvidence='test')],'Identity/history')

    def test_non_ready_target_rejected(self):
        self.change(TABLES['subcategory'],'S',templateStatus='UNAVAILABLE')
        self.assert_rejected(plan(),'not READY')

    def test_forced_failure_rolls_back_every_stage(self):
        for target in ['products','variants','dependencies','before_retirement','audit']:
            before=self.sandbox.snapshot()
            def fail(stage,db):
                if stage==target:
                    if stage=='products':self.assertEqual(self.fields(TABLES['product'],'P')['categoryId'],'C')
                    if stage=='variants':self.assertEqual(self.fields(TABLES['variant'],'V')['unitId'],'LITRE')
                    if stage=='audit':self.assertEqual(db.execute('SELECT COUNT(*) FROM migration_audit').fetchone()[0],3)
                    raise RuntimeError('forced '+stage)
            with self.assertRaisesRegex(RuntimeError,'forced'):self.migrate(failure=fail)
            self.assertEqual(self.sandbox.snapshot(),before)
            self.assertEqual(self.fields(TABLES['category'],'C_OLD')['status'],'ACTIVE')

    def test_success_clears_all_migrated_reference_ids(self):
        audit=self.migrate();refs=references(load_rows(self.sandbox.db))
        self.assertFalse([r for r in refs if r['legacyId'] in {'C_OLD','S_OLD','L'}])
        self.assertEqual(len(audit),3)
        self.assertTrue(all(a['referenceCountAfter']==0 and a['status']=='SIMULATED' for a in audit))
        self.assertEqual([a['legacyId']for a in audit],['C_OLD','S_OLD','L'])
        self.assertTrue(all(a['timestamp']==STAMP for a in audit))

    def test_identity_timestamps_history_and_sync_metadata_unchanged(self):
        before=self.sandbox.snapshot();self.migrate();after=self.sandbox.snapshot()
        for t in ['local_inventory_transactions','local_purchase_bills','sync_outbox']:self.assertEqual(after[t],before[t])
        for table,id_ in [(TABLES['product'],'P'),(TABLES['variant'],'V')]:
            original=next(d for d in data()[table] if d['remoteId']==id_)
            current=dict(self.sandbox.db.execute(f'SELECT * FROM {table} WHERE remoteId=?',(id_,)).fetchone())
            for key in ['remoteId','localRevision','syncStatus','remoteUpdateTime']:self.assertEqual(current[key],original[key])
            old=decode(json.loads(original['payloadJson']));new=decode(json.loads(current['payloadJson']))
            for key in ['productId','variantId','sku','barcode','createdAt','updatedAt','attributeValues']:
                self.assertEqual(new.get(key),old.get(key))

    def test_historical_reference_blocks_whole_migration(self):
        self.change('local_inventory_transactions','H',categoryId='C_OLD')
        self.assert_rejected(plan(),'Protected historical/config/sync')

    def test_role_config_nested_reference_blocks_retirement(self):
        rows=data();rows['local_app_config']=[row('CONFIG',{'allowedCategories':['C_OLD']})]
        box=SandboxCatalogueMigration(rows)
        try:
            before=box.snapshot()
            with self.assertRaisesRegex(ValueError,'Protected historical/config/sync'):box.apply(plan(),'X',STAMP)
            self.assertEqual(box.snapshot(),before)
        finally:box.close()

    def test_read_only_connection_cannot_mutate(self):
        with read_only(self.sandbox.path) as db:
            with self.assertRaises(sqlite3.OperationalError):db.execute(f'DELETE FROM {TABLES["product"]}')
        self.assertEqual(self.fields(TABLES['product'],'P')['productId'],'P')

    def test_unresolved_domain_review_cannot_be_marked_approved(self):
        self.assert_rejected([replace(plan()[0],warnings=('DOMAIN_REVIEW_REQUIRED',))],'domain review')

    def test_mapping_json_load_preserves_approval_and_audit_fields(self):
        from dataclasses import asdict
        path=self.sandbox.path.parent/'reviewed-test-plan.json'
        path.write_text(json.dumps({'canonicalMappings':[asdict(m)for m in plan()]}))
        loaded=load_canonical_mappings(path)
        self.assertEqual(loaded,plan());self.migrate(loaded)

    def test_executor_refuses_a_connection_it_does_not_own(self):
        other=SandboxCatalogueMigration(data());original=self.sandbox.db
        try:
            before=other.snapshot();self.sandbox.db=other.db
            with self.assertRaisesRegex(ValueError,'owned temporary'):self.migrate()
            self.assertEqual(other.snapshot(),before)
        finally:
            self.sandbox.db=original;other.close()

    def test_config_map_key_reference_blocks_retirement(self):
        rows=data();rows['local_app_config']=[row('CONFIG',{'categorySettings':{'C_OLD':{'enabled':True}}})]
        box=SandboxCatalogueMigration(rows)
        try:
            before=box.snapshot()
            with self.assertRaisesRegex(ValueError,'Protected historical/config/sync'):box.apply(plan(),'X',STAMP)
            self.assertEqual(box.snapshot(),before)
        finally:box.close()

    def test_pending_outbox_reference_blocks_migration(self):
        rows=data();rows['sync_outbox']=[{'id':1,'payloadJson':json.dumps({'fields':{'categoryId':encode('C_OLD')}})}]
        box=SandboxCatalogueMigration(rows)
        try:
            before=box.snapshot()
            with self.assertRaisesRegex(ValueError,'Protected historical/config/sync'):box.apply(plan(),'X',STAMP)
            self.assertEqual(box.snapshot(),before)
        finally:box.close()

    def test_migration_audit_failure_rolls_back_and_does_not_replay(self):
        self.migrate();before=self.sandbox.snapshot()
        with self.assertRaises(sqlite3.IntegrityError):self.migrate()
        self.assertEqual(self.sandbox.snapshot(),before)

    def test_real_representative_copy_preserves_identity_and_history_fields(self):
        fixture=json.loads(FIXTURE.read_text());box=SandboxCatalogueMigration(fixture['rows'])
        try:
            before=box.snapshot()
            mappings=[Mapping(typ,fixture[a],fixture[b],'Isolated hypothetical approved mapping',
                approved=True,semanticEvidence='Test-only semantic approval; not a live-data approval')
                for typ,a,b in [('category','legacyCategoryId','canonicalCategoryId'),('subcategory','legacySubcategoryId','canonicalSubcategoryId')]]
            box.apply(mappings,'REPRESENTATIVE-8',STAMP)
            refs=references(load_rows(box.db))
            self.assertFalse([r for r in refs if r['legacyId'] in {fixture['legacyCategoryId'],fixture['legacySubcategoryId']}])
            self.assertEqual(box.snapshot()[TABLES['variant']],before[TABLES['variant']])
            prod=decode(json.loads(box.db.execute(f'SELECT payloadJson FROM {TABLES["product"]}').fetchone()[0]))
            old=decode(json.loads(fixture['rows'][TABLES['product']][0]['payloadJson']))
            self.assertEqual(prod['productId'],old['productId'])
            for k in old:
                if k not in {'categoryId','subcategoryId'}:self.assertEqual(prod[k],old[k])
        finally:box.close()


if __name__=='__main__':unittest.main()

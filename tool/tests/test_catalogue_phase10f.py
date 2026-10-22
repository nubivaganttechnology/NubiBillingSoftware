"""Phase 10F plan proofs. Reads committed evidence only; never opens production DB."""
import json
import hashlib
from collections import Counter
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DIFF_PATH = ROOT / 'docs/phase10e-installed-v3-v4-diff.json'
REVIEW_PATH = ROOT / 'docs/catalogue-release-v4-review.json'
MANIFEST_PATH = ROOT / 'docs/phase10f-migration-approval-manifest.json'
RETENTION_POLICY_PATH = ROOT / 'docs/phase10l-legacy-retention-policy.json'
SYNC_PRESERVATION_PATH = ROOT / 'docs/phase10k-sync-query-preservation.json'
PLAN_PATH = ROOT / 'phase10f.md'


class Phase10FPlanProof(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.diff = json.loads(DIFF_PATH.read_text())
        cls.review = json.loads(REVIEW_PATH.read_text())
        cls.manifest = json.loads(MANIFEST_PATH.read_text())
        cls.retention_policy = json.loads(RETENTION_POLICY_PATH.read_text())
        cls.sync_preservation = json.loads(SYNC_PRESERVATION_PATH.read_text())
        cls.plan = PLAN_PATH.read_text()
        cls.inventory = json.loads((ROOT / 'docs/phase8-catalogue-inventory.json').read_text())
        cls.phase8_mappings = json.loads((ROOT / 'docs/phase8-canonical-mappings.json').read_text())
        cls.fixture = json.loads((ROOT / 'test/fixtures/system_catalogue_v4.json').read_text())
        cls.phase10a = (ROOT / 'docs/phase10a-catalogue-audit.json').read_text()

    def test_complete_disposition_accounting(self):
        entries = self.diff['entries']
        self.assertEqual(len(entries), 4958)
        self.assertEqual(len({(e['collection'], e['documentId']) for e in entries}), 4958)
        counts = Counter(e['classification'] for e in entries)
        self.assertEqual(dict(counts), self.diff['counts']['classifications'])
        self.assertEqual(sum(counts.values()), 4958)

    def test_dependency_inventory_and_reference_only_identities_are_accounted(self):
        referenced = [e for e in self.diff['entries'] if e['referenceCount']]
        self.assertEqual(len(referenced), 483)
        for entry in referenced:
            self.assertEqual(entry['referenceCount'], len(entry['referenceRecords']))
            for owner in entry['referenceRecords']:
                self.assertTrue(owner['source'])
                self.assertTrue(owner['table'])
                self.assertTrue(owner['ownerId'])
                self.assertIn('active', owner)
                self.assertTrue(owner['locations'])
                self.assertTrue(all(loc['path'] and loc['role'] for loc in owner['locations']))
        self.assertEqual(len(self.diff['referenceOnlyIdentities']), 2)
        self.assertTrue(all(i['referenceCount'] == len(i['referenceRecords'])
                            for i in self.diff['referenceOnlyIdentities']))

    def test_product_variant_reference_protection(self):
        owners = {(r['table'], r['ownerId'])
                  for e in self.diff['entries'] for r in e['referenceRecords']
                  if r['table'] in {'local_products', 'local_product_variants'}}
        self.assertEqual(len(owners), 11)
        self.assertEqual(sum(t == 'local_products' for t, _ in owners), 4)
        self.assertEqual(sum(t == 'local_product_variants' for t, _ in owners), 7)
        for token in ('REMAP_REQUIRED', 'RETAIN_LEGACY_METADATA',
                      'RECOVER_BROKEN_REFERENCE', 'NO_ACTION', 'productId',
                      'variantId', 'SKU', 'barcode'):
            self.assertIn(token, self.plan)

    def test_historical_template_retention_gate(self):
        templates = [e for e in self.diff['entries']
                     if e['collection'] == 'subcategory_attribute_templates'
                     and e['action'] == 'DEACTIVATE']
        self.assertEqual(len(templates), 2267)
        self.assertTrue(all(e['classification'] == 'REVIEW_REQUIRED' for e in templates))
        self.assertIn('make them selectable for new Product creation', self.plan)

    def test_attribute_option_unit_compatibility_gate(self):
        deactivated = [e for e in self.diff['entries'] if e['action'] == 'DEACTIVATE']
        attrs = [e for e in deactivated if e['collection'] == 'product_attributes']
        options = [e for e in deactivated if e['collection'] == 'product_attribute_options']
        units = [e for e in deactivated if e['collection'] == 'units']
        self.assertEqual(len(attrs), 6)
        self.assertEqual(len(options), 184)
        self.assertEqual(sum(bool(e['referenceCount']) for e in options), 163)
        self.assertEqual(len(units), 5)
        self.assertEqual(sum(bool(e['referenceCount']) for e in units), 1)
        self.assertIn('SYS_UNIT_PACK', self.plan)
        self.assertIn('not coerced into a new canonical option set', self.plan)

    def test_protected_query_interlock(self):
        queries = self.diff['protectedLegacyQueries']
        self.assertEqual(len(queries), 10)
        self.assertTrue(all(q['disposition'] == 'BLOCK_MIGRATION_NO_REWRITE' for q in queries))
        self.assertTrue(all(q['active'] == 0 for q in queries))
        self.assertTrue(all('cursor' in q and 'lastSyncedAt' in q for q in queries))
        self.assertTrue(all(q['cursor'] is None for q in queries))
        self.assertEqual(len({q['queryKey'] for q in queries}), 10)
        protected_ids = {legacy_id for q in queries for legacy_id in q['legacyIds']}
        self.assertEqual(protected_ids, {
            'SYS_CATEGORY_ACCESSORIES', 'SYS_CATEGORY_EXTERIOR_WALL_PAINTS',
            'PM_SUBCATEGORY_ce0bf39843417fca',
            'SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH',
            'SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS',
        })
        self.assertEqual(sorted(q['lastSyncedAt'] or '' for q in queries), sorted([
            '', '', '', '', '', '',
            '2026-10-02T13:27:30.683249Z', '2026-10-02T13:27:31.066930Z',
            '2026-10-02T13:27:31.956359Z', '2026-10-02T13:27:37.720967Z',
        ]))
        self.assertEqual(len(self.diff['syncQueriesDigest']), 64)

    def test_approval_manifest_defaults_false(self):
        defaults = self.manifest['approvalDefaults']
        self.assertEqual(defaults, {
            'approved': False,
            'migrationApproved': False,
            'retirementApproved': False,
            'automaticReferenceMappingAllowed': False,
        })
        self.assertEqual(self.manifest['preapprovedMappings'], [])
        self.assertEqual(self.diff['counts']['rows'], self.manifest['sourceInventory']['rowCount'])
        projection = self.manifest['actionProjection']
        self.assertEqual(projection['mode'], 'DETERMINISTIC_PER_SOURCE_ROW')
        self.assertIn('actionId', projection)
        self.assertIn('source entry referenceCount', projection['referenceCount'])
        self.assertIn('source entry referenceRecords', projection['affectedOwners'])
        self.assertEqual(len(self.diff['entries']), self.manifest['sourceInventory']['rowCount'])
        self.assertFalse(self.diff['approvedForLiveExecution'])
        self.assertFalse(self.diff['migrationApproved'])
        self.assertFalse(self.diff['retirementApproved'])
        self.assertTrue(all(not e['approved'] and not e['migrationApproved']
                            and not e['retirementApproved'] for e in self.diff['entries']))

    def test_migration_order_dependency_graph_is_acyclic(self):
        graph = self.manifest['migrationOrder']
        nodes = graph['nodes']
        adjacency = {node: [] for node in nodes}
        indegree = {node: 0 for node in nodes}
        for source, target in graph['edges']:
            self.assertIn(source, adjacency)
            self.assertIn(target, adjacency)
            adjacency[source].append(target)
            indegree[target] += 1
        ready = [node for node in nodes if indegree[node] == 0]
        visited = 0
        while ready:
            node = ready.pop()
            visited += 1
            for target in adjacency[node]:
                indegree[target] -= 1
                if indegree[target] == 0:
                    ready.append(target)
        self.assertEqual(visited, len(nodes))
        self.assertIn('One SQLite transaction', graph['consistencyBarrier'])

    def test_rollback_plan_completeness(self):
        rollback = self.manifest['rollbackPlanCompleteness']
        self.assertTrue(all(rollback[k] for k in (
            'backupRequirements', 'rollbackTriggers',
            'restoreAccountAndPublicConfigAsOneConsistentSet',
            'associatedMetadataAndReleaseMarkerRestore',
            'productVariantSkuBarcodeQueryIdentityProof')))
        self.assertFalse(rollback['executionAuthorized'])
        for term in ('Rollback triggers', 'Restore:', 'Identity proof:', 'backup'):
            self.assertIn(term, self.plan)

    def test_production_read_only_safety_and_no_install(self):
        self.assertEqual(self.diff['productionBefore'], self.diff['productionAfter'])
        self.assertFalse(self.diff['productionInstallationAllowed'])
        self.assertTrue(self.diff['productionBefore'])
        self.assertTrue(self.manifest['decision'].startswith('PLANNING_ONLY'))
        self.assertIn('No Firestore read or write', self.plan)
        self.assertIn('No migration', self.plan)
        self.assertTrue(self.review['isolatedOnly'])
        self.assertFalse(self.review['approvedForLiveExecution'])
        self.assertFalse(self.review['productionMigrationApproved'])

    def test_ceiling_payload_identity_is_real_and_exact(self):
        document_id = 'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS'
        payload_id = 'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS'
        entry = next(e for e in self.diff['entries']
                     if e['collection'] == 'product_subcategories' and e['documentId'] == document_id)
        reference_only = next(i for i in self.diff['referenceOnlyIdentities'] if i['id'] == payload_id)
        self.assertEqual(entry['beforePayloadId'], payload_id)
        self.assertEqual(entry['beforeFields']['categoryId'], 'SYS_CATEGORY_INTERIOR_WALL_COATINGS')
        self.assertEqual((entry['referenceCount'], reference_only['referenceCount']), (22, 21))
        self.assertEqual(entry['referencesByTable'], {'local_subcategory_attribute_templates': 22})
        self.assertTrue(all(r['table'] == 'local_subcategory_attribute_templates'
                            for r in reference_only['referenceRecords']))
        for identity, refs in ((document_id, entry['referenceRecords']),
                       (payload_id, reference_only['referenceRecords'])):
            template_ids = {r['ownerId'] for r in refs}
            template_rows = {e['documentId']: e for e in self.diff['entries']
                     if e['collection'] == 'subcategory_attribute_templates'}
            self.assertTrue(all(template_rows[template_id]['beforeFields']['subcategoryId'] == identity
                    for template_id in template_ids))
        canonical = next(r for r in self.fixture['product_subcategories'] if r['id'] == document_id)
        self.assertEqual(canonical['subcategoryId'], document_id)
        self.assertEqual(canonical['categoryId'], 'SYS_CATEGORY_INTERIOR_WALL_COATINGS')
        payload_sources = (
            json.dumps(self.inventory),
            self.phase10a,
            json.dumps(self.diff),
            json.dumps(self.review),
            json.dumps(self.manifest),
            self.plan,
        )
        self.assertTrue(all(payload_id in text for text in payload_sources))
        self.assertTrue(all(document_id in text for text in payload_sources))
        self.assertNotIn('SYS_SUBCATEGORY_INTERIOR_WALL_CEILING_PAINTS', self.plan)

    def test_basement_document_and_payload_remain_distinct(self):
        document_id = 'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING'
        payload_id = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT'
        entry = next(e for e in self.diff['entries']
                     if e['collection'] == 'product_subcategories' and e['documentId'] == document_id)
        reference_only = next(i for i in self.diff['referenceOnlyIdentities'] if i['id'] == payload_id)
        self.assertEqual(entry['beforePayloadId'], payload_id)
        self.assertEqual((entry['referenceCount'], reference_only['referenceCount']), (14, 14))
        self.assertEqual(entry['referencesByTable'], {'local_subcategory_attribute_templates': 14})
        template_rows = {e['documentId']: e for e in self.diff['entries']
                         if e['collection'] == 'subcategory_attribute_templates'}
        for identity, refs in ((document_id, entry['referenceRecords']),
                               (payload_id, reference_only['referenceRecords'])):
            self.assertTrue(all(template_rows[r['ownerId']]['beforeFields']['subcategoryId'] == identity
                                for r in refs))
        basement_targets = {
            'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID',
            'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS',
        }
        candidates = [r for r in self.review['canonicalCandidates']
                      if r['canonicalId'] in basement_targets]
        self.assertEqual({r['canonicalId'] for r in candidates}, basement_targets)
        self.assertTrue(all(not r['migrationApproved'] for r in candidates))
        release_basement = [r for r in self.fixture['product_subcategories']
                    if r['id'] in basement_targets]
        self.assertEqual({r['categoryId'] for r in release_basement}, {'SYS_CATEGORY_WATERPROOFING'})

    def test_all_ten_duplicate_pairs_match_parent_counts_and_approvals(self):
        expected = {
            ('SYS_SUBCATEGORY_SYS_CATEGORY_ADHESIVES_TILING_TILE_ADHESIVES', 'SYS_SUBCATEGORY_ADHESIVES_TILING_TILE_ADHESIVES', 'SYS_CATEGORY_ADHESIVES_TILING', 12),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_ALLIED_PRODUCTS_THINNERS', 'SYS_SUBCATEGORY_ALLIED_PRODUCTS_THINNERS', 'SYS_CATEGORY_ALLIED_PRODUCTS', 6),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING', 'SYS_SUBCATEGORY_FLOOR_TILE_COATINGS_EPOXY_FLOORING', 'SYS_CATEGORY_FLOOR_TILE_COATINGS', 21),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY', 'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_ACRYLIC_PUTTY', 'SYS_CATEGORY_PUTTY_SURFACE_PREPARATION', 19),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY', 'SYS_SUBCATEGORY_PUTTY_SURFACE_PREPARATION_WATERPROOF_WALL_PUTTY', 'SYS_CATEGORY_PUTTY_SURFACE_PREPARATION', 19),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS', 'SYS_SUBCATEGORY_SEALANTS_REPAIR_ACRYLIC_SEALANTS', 'SYS_CATEGORY_SEALANTS_REPAIR', 14),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_KITCHEN_WATERPROOFING', 'SYS_SUBCATEGORY_WATERPROOFING_BATHROOM_KITCHEN', 'SYS_CATEGORY_WATERPROOFING', 14),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_EXTERIOR_WALL_WATERPROOFING', 'SYS_SUBCATEGORY_WATERPROOFING_EXTERIOR_WALL', 'SYS_CATEGORY_WATERPROOFING', 14),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT', 'SYS_SUBCATEGORY_WATERPROOFING_INTERIOR_DAMPNESS', 'SYS_CATEGORY_WATERPROOFING', 14),
            ('SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_ROOF_TERRACE_WATERPROOFING', 'SYS_SUBCATEGORY_WATERPROOFING_ROOF_TERRACE', 'SYS_CATEGORY_WATERPROOFING', 14),
        }
        duplicate_rows = self.inventory['duplicateSameParentSubcategories']
        actual = {(next(i for i in row['ids'] if i.startswith('SYS_SUBCATEGORY_SYS_CATEGORY_')),
                   next(i for i in row['ids'] if not i.startswith('SYS_SUBCATEGORY_SYS_CATEGORY_')),
                   row['parentId']) for row in duplicate_rows}
        self.assertEqual(len(duplicate_rows), 10)
        self.assertEqual(actual, {(legacy, canonical, parent) for legacy, canonical, parent, _ in expected})
        release_rows = {r['id']: r for r in self.fixture['product_subcategories']}
        for legacy, canonical, parent, refs in expected:
            entry = next(e for e in self.diff['entries']
                         if e['collection'] == 'product_subcategories' and e['documentId'] == legacy)
            mapping = next(m for m in self.phase8_mappings['canonicalMappings'] if m['legacyId'] == legacy)
            review_candidate = next(c for c in self.review['canonicalCandidates']
                                    if c['canonicalId'] == canonical)
            self.assertEqual(entry['beforeFields']['categoryId'], parent)
            self.assertEqual(entry['referenceCount'], refs)
            self.assertEqual(entry['referencesByTable'], {'local_subcategory_attribute_templates': refs})
            self.assertTrue(all(r['table'] == 'local_subcategory_attribute_templates'
                                for r in entry['referenceRecords']))
            self.assertEqual(release_rows[canonical]['categoryId'], parent)
            self.assertFalse(mapping['approved'])
            self.assertFalse(review_candidate['migrationApproved'])
            self.assertFalse(entry['approved'])
            self.assertFalse(entry['migrationApproved'])
            self.assertFalse(entry['retirementApproved'])

    def test_identity_review_manifest_sources_targets_and_false_approvals(self):
        actions = self.manifest['identityReviewActions']
        self.assertEqual(len(actions), 14)
        self.assertEqual(len({a['actionId'] for a in actions}), len(actions))
        entry_ids = {(e['collection'], e['documentId']) for e in self.diff['entries']}
        reference_only_ids = {i['id'] for i in self.diff['referenceOnlyIdentities']}
        release_ids = {row['id'] for rows in self.fixture.values() for row in rows}
        for action in actions:
            self.assertFalse(action['approved'])
            self.assertFalse(action['migrationApproved'])
            self.assertFalse(action['retirementApproved'])
            if action['sourceKind'] == 'ledgerEntry':
                self.assertIn((action['sourceCollection'], action['sourceId']), entry_ids)
            else:
                self.assertEqual(action['sourceKind'], 'referenceOnlyIdentity')
                self.assertIn(action['sourceId'], reference_only_ids)
            self.assertTrue(action['targetId'] is None or action['targetId'] in release_ids)
            self.assertTrue(set(action['prospectiveTargetIds']) <= release_ids)
        self.assertEqual(self.manifest['sourceInventory']['syncQueryCount'], 195)
        self.assertEqual(self.manifest['sourceInventory']['protectedSyncQueryCount'], 10)
        self.assertEqual(self.manifest['sourceInventory']['syncQueriesDigest'], self.diff['syncQueriesDigest'])

    def test_live_product_variant_owner_states_and_proposed_actions(self):
        expected_states = {
            'PROD-515E99F5F2C24423B75AEBFE81CB075A': 'ACTIVE',
            'PROD-6198168F50EA48BB9209914A7A2003D2': 'ACTIVE',
            'PROD-78125CD6E1864CA1AF4E3E71C915D025': 'DELETED',
            'PROD-C446FD4E4DD349DAB46DDFEDA251915D': 'DELETED',
            'VAR-089A2A0AA0A14E45AEC89328F3A193E6': 'INACTIVE',
            'VAR-233931D4CB8A432E8F2DC88912B59C48': 'ACTIVE',
            'VAR-3F8DCEC102144603B4BFF7DF558ECFDF': 'INACTIVE',
            'VAR-42F8F567B7F54AC9A653C5826B53344B': 'ACTIVE',
            'VAR-808222B8F37A40138FE9416965A61F49': 'ACTIVE',
            'VAR-CF94091746164266B8DA7863706991A0': 'ACTIVE',
            'VAR-FE7BA134B0B94E058B21689F4DBB757B': 'ACTIVE',
        }
        for table, count in (('local_products', 4), ('local_product_variants', 7)):
            owners = {r['ownerId'] for e in self.diff['entries'] for r in e['referenceRecords']
                      if r['table'] == table}
            self.assertEqual(sum(owner in expected_states for owner in owners), count)
        for owner, state in expected_states.items():
            self.assertIn(owner, self.plan)
            self.assertIn(state, self.plan)
            lines = [line for line in self.plan.splitlines() if owner in line]
            self.assertTrue(any('RETAIN_LEGACY_METADATA' in line for line in lines))
        self.assertIn('`isDeleted=0`', self.plan)

    def test_phase10l_retention_policy_covers_each_target_row_once(self):
        policy = self.retention_policy
        overlay = self.manifest['phase10lRetentionPolicyApproval']
        expected = {
            'LEGACY_RETAIN_REQUIRED': 242,
            'REVIEW_REQUIRED': 2506,
            'MIGRATION_REQUIRED': 2,
            'SAFE_UNREFERENCED_RETIREMENT_CANDIDATE': 25,
        }
        coverage = policy['coveredDispositionRows']
        selections = coverage['classifications']
        self.assertEqual({row['classification']: row['expectedRows'] for row in selections}, expected)
        self.assertEqual(len(selections), len(expected))
        self.assertEqual(sum(expected.values()), 2775)
        self.assertEqual(coverage['expectedTotalRows'], 2775)

        selected = [entry for entry in self.diff['entries']
                    if entry['classification'] in expected]
        selected_keys = [(entry['collection'], entry['documentId']) for entry in selected]
        self.assertEqual(len(selected), 2775)
        self.assertEqual(len(set(selected_keys)), 2775)
        self.assertEqual(dict(Counter(entry['classification'] for entry in selected)), expected)
        self.assertEqual(len(self.diff['entries']), 4958)
        self.assertEqual(sum(self.diff['counts']['classifications'].values()), 4958)

        source_hash = hashlib.sha256(DIFF_PATH.read_bytes()).hexdigest()
        self.assertEqual(source_hash, policy['sourceInventory']['sha256'])
        self.assertEqual(source_hash, overlay['sourceInventorySha256'])
        self.assertEqual(overlay['coveredSourceClassifications'], expected)
        self.assertEqual(overlay['coveredDispositionRowCount'], 2775)
        self.assertTrue(overlay['retentionPolicyApproved'])
        self.assertFalse(overlay['migrationApproved'])
        self.assertFalse(overlay['retirementApproved'])
        self.assertFalse(overlay['executionAuthorized'])
        self.assertFalse(overlay['historicalLedgerAndEvidenceRewritten'])
        self.assertTrue(policy['retentionPolicyApproved'])
        self.assertFalse(policy['migrationApproved'])
        self.assertFalse(policy['retirementApproved'])
        self.assertFalse(policy['executionAuthorized'])
        self.assertFalse(policy['productionInstallationApproved'])

        actions = self.manifest['identityReviewActions']
        self.assertEqual(len(actions), 14)
        self.assertTrue(all(action['targetId'] is None for action in actions))
        self.assertEqual(self.manifest['preapprovedMappings'], [])
        self.assertTrue(all(not action['migrationApproved'] and not action['retirementApproved']
                            for action in actions))
        self.assertTrue(all(not entry['migrationApproved'] and not entry['retirementApproved']
                            for entry in self.diff['entries']))
        self.assertEqual(coverage['additionalReferenceOnlyIdentityCount'], 2)
        self.assertEqual(len(self.diff['referenceOnlyIdentities']), 2)

    def test_phase10l_product_variant_and_sync_preservation_only(self):
        policy = self.retention_policy
        product_variant = policy['productVariantPolicy']
        self.assertEqual(product_variant['existingProductCount'], 4)
        self.assertEqual(product_variant['existingVariantCount'], 7)
        self.assertFalse(product_variant['mutationsProposed'])
        self.assertTrue(product_variant['existingNullCatalogueFingerprintsRemainNull'])
        self.assertFalse(product_variant['historicalRelease4ProvenanceAssigned'])
        self.assertFalse(product_variant['skuOrBarcodeChangesProposed'])

        sync_policy = policy['syncPolicy']
        self.assertEqual(sync_policy['totalQueryCount'], 195)
        self.assertEqual(sync_policy['protectedQueryCount'], 10)
        self.assertTrue(sync_policy['allQueriesRemainUnchanged'])
        self.assertFalse(sync_policy['queryDeletion'])
        self.assertFalse(sync_policy['queryReactivation'])
        self.assertFalse(sync_policy['migrationTimeCursorOrTrackingMutation'])
        self.assertEqual(len(self.diff['protectedLegacyQueries']), 10)
        self.assertTrue(all(query['disposition'] == 'BLOCK_MIGRATION_NO_REWRITE'
                            for query in self.diff['protectedLegacyQueries']))
        metrics = self.sync_preservation['acceptanceMetrics']
        self.assertEqual(metrics['expectedTotalQueries'], 195)
        self.assertEqual(metrics['actualTotalQueries'], 195)
        self.assertEqual(metrics['protectedLegacyQueries'], 10)
        self.assertEqual(metrics['actualProtectedLegacyQueries'], 10)
        self.assertTrue(metrics['queryDigestMatch'])
        self.assertFalse(self.sync_preservation['productionSafety']['productionDatabasesTouched'])
        self.assertEqual(self.sync_preservation['productionSafety']['firestoreCalls'], 0)

        safety = policy['productionSafety']
        self.assertTrue(all(value is False for value in safety.values()))
        self.assertEqual(policy['policyVersion'], '1.0.0')
        self.assertEqual(policy['policyName'], 'RETAIN_LEGACY_NO_AUTOMATIC_MIGRATION_NO_RETIREMENT')


if __name__ == '__main__':
    unittest.main()

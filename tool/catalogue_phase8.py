"""Read-only catalogue inventory and deliberately sandbox-only migration proof.

CLI: python3 tool/catalogue_phase8.py --database PATH --output PATH
The CLI has no migration, seed, deactivation, HTTP, or Firestore operation.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import tempfile
import unicodedata
from urllib.parse import quote

TABLES = {'category': 'local_product_categories', 'subcategory': 'local_product_subcategories',
          'unit': 'local_units', 'product': 'local_products', 'variant': 'local_product_variants'}
IDENTITIES = {'category': 'categoryId', 'subcategory': 'subcategoryId', 'unit': 'unitId',
              'product': 'productId', 'variant': 'variantId'}
REF_KEYS = {'categoryId': 'category', 'subcategoryId': 'subcategory', 'productId': 'product',
            'variantId': 'variant', 'unitId': 'unit', 'baseUnitId': 'unit',
            'commercialUnitId': 'unit', 'packUnitId': 'unit', 'measurementUnitId': 'unit'}
TEMPLATE = 'local_subcategory_attribute_templates'
PACKAGING = {'pack', 'can', 'bucket', 'box', 'bag', 'bottle', 'jar', 'drum', 'tube',
             'pouch', 'cartridge', 'roll', 'sheet', 'set', 'piece'}
DISPLAY_KEYS = {'name', 'unitName', 'commercialUnitName', 'categoryName', 'subcategory',
                'subcategoryName', 'productName', 'variantName', 'displayName', 'aliases'}
METADATA = {'createdAt', 'updatedAt', 'createdBy', 'updatedBy', 'version', 'status', 'isDeleted',
            'retiredByCatalogueId', 'retiredByCatalogueVersion', '_syncMutationId',
            'templateId', 'subcategoryId', 'catalogueId', 'scopeType', 'localMetadataRevision'}


def normalize(value):
    return re.sub(r'\s+', ' ', unicodedata.normalize('NFKC', str(value or '')).strip()).casefold()


def decode(value):
    if isinstance(value, dict):
        if 'mapValue' in value:
            return {k: decode(v) for k, v in value['mapValue'].get('fields', {}).items()}
        if 'arrayValue' in value:
            return [decode(v) for v in value['arrayValue'].get('values', [])]
        for key in ['stringValue', 'booleanValue', 'timestampValue', 'doubleValue', 'nullValue']:
            if key in value:
                return value[key]
        if 'integerValue' in value:
            return int(value['integerValue'])
        return {k: decode(v) for k, v in value.items()}
    if isinstance(value, list):
        return [decode(v) for v in value]
    return value


def encode(value):
    if value is None: return {'nullValue': None}
    if isinstance(value, bool): return {'booleanValue': value}
    if isinstance(value, int): return {'integerValue': str(value)}
    if isinstance(value, float): return {'doubleValue': value}
    if isinstance(value, str): return {'stringValue': value}
    if isinstance(value, list): return {'arrayValue': {'values': [encode(v) for v in value]}}
    return {'mapValue': {'fields': {k: encode(v) for k, v in value.items()}}}


@contextmanager
def read_only(path):
    db = sqlite3.connect('file:' + quote(str(Path(path).resolve())) + '?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA query_only=ON')
    try:
        yield db
    finally:
        db.close()


def load_rows(db):
    rows = {}
    for row in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
        table = row[0]
        if not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', table):
            raise ValueError('Unexpected table identifier')
        if table.startswith('local_') or table in {'sync_outbox', 'sync_queries', 'sync_conflicts'}:
            rows[table] = [dict(r) for r in db.execute(f'SELECT * FROM "{table}" ORDER BY 1')]
    return rows


def documents(rows):
    return [{'table': table, 'id': r['remoteId'], 'fields': decode(json.loads(r['payloadJson'])),
             'row': r} for table, records in sorted(rows.items()) for r in records
            if table.startswith('local_') and 'payloadJson' in r]


def active(doc):
    return (doc['fields'].get('status', doc['row'].get('status')) == 'ACTIVE'
            and not doc['row'].get('isDeleted') and not doc['fields'].get('isDeleted'))


def scope(doc):
    f = doc['fields']
    return (f.get('scopeType') or ('BUSINESS' if f.get('businessId') else 'UNKNOWN'),
            f.get('tenantId'), f.get('businessId'), f.get('catalogueId'),
            f.get('businessTypeId'), f.get('businessSubTypeId'))


def leaves(value, path=()):
    if isinstance(value, dict):
        for k, v in sorted(value.items()):
            yield from leaves(v, path + (k,))
    elif isinstance(value, list):
        for i, v in enumerate(value):
            yield from leaves(v, path + (i,))
    else:
        yield path, value


def references(rows):
    docs = documents(rows)
    known = {typ: {d['id'] for d in docs if d['table'] == table} for typ, table in TABLES.items()}
    lookup = {id_: typ for typ, ids in known.items() for id_ in ids}
    result = []
    for doc in docs:
        own_type = next((t for t, table in TABLES.items() if table == doc['table']), None)
        for path, value in leaves(doc['fields']):
            if not isinstance(value, str) or not value: continue
            if any(key in DISPLAY_KEYS for key in path): continue
            if own_type and path == (IDENTITIES[own_type],) and value == doc['id']: continue
            typ = REF_KEYS.get(path[-1]) or lookup.get(value)
            if typ:
                result.append({'recordType': typ, 'legacyId': value, 'table': doc['table'],
                               'documentId': doc['id'], 'path': list(path),
                               'activeOwner': active(doc), 'exists': value in known[typ]})
        # IDs used as config/map keys are references too; never rewrite them implicitly.
        keys_seen = set()
        for path, _ in leaves(doc['fields']):
            for i, key in enumerate(path):
                if key in lookup and path[:i + 1] not in keys_seen:
                    keys_seen.add(path[:i + 1])
                    result.append({'recordType': lookup[key], 'legacyId': key, 'table': doc['table'],
                                   'documentId': doc['id'], 'path': ['<map-key>', *path[:i + 1]],
                                   'activeOwner': active(doc), 'exists': True})
    # Conservatively include exact identifiers anywhere in pending sync/config JSON.
    for table in ['sync_outbox', 'sync_queries', 'sync_conflicts']:
        for row in rows.get(table, []):
            for column, raw in row.items():
                try: value = json.loads(raw) if isinstance(raw, str) else raw
                except (ValueError, TypeError): value = raw
                for path, scalar in leaves(value):
                    if isinstance(scalar, str) and scalar in lookup:
                        result.append({'recordType': lookup[scalar], 'legacyId': scalar,
                                       'table': table, 'documentId': str(next(iter(row.values()))),
                                       'path': [column, *path],
                                       'activeOwner': bool(row.get('active', 1)), 'exists': True})
    return sorted(result, key=lambda r: (r['recordType'], r['legacyId'], r['table'],
                                         r['documentId'], json.dumps(r['path'])))


def template_signature(group):
    """Conservative equality; include every semantic field, ignore metadata only."""
    return sorted(json.dumps({k: v for k, v in d['fields'].items() if k not in METADATA},
                             sort_keys=True) for d in group)


@dataclass(frozen=True)
class CatalogueCanonicalMapping:
    recordType: str
    legacyId: str
    canonicalId: str | None
    reason: str
    referenceCount: int = 0
    safeToDeactivate: bool = False
    requiresDataMigration: bool = False
    warnings: tuple[str, ...] = ()
    approved: bool = False
    semanticEvidence: str = ''


def load_canonical_mappings(path):
    data = json.loads(Path(path).read_text())
    records = data['canonicalMappings'] if isinstance(data, dict) else data
    return [CatalogueCanonicalMapping(**{**r, 'warnings': tuple(r.get('warnings', ()))})
            for r in records]


def inventory(rows):
    docs = documents(rows)
    indexed = {typ: {d['id']: d for d in docs if d['table'] == table} for typ, table in TABLES.items()}
    refs = references(rows)
    by_id = {(typ, id_): [r for r in refs if r['recordType'] == typ and r['legacyId'] == id_]
             for typ, ds in indexed.items() for id_ in ds}
    groups = {}
    for d in docs:
        if d['table'] == TEMPLATE:
            groups.setdefault(d['fields'].get('subcategoryId', '<missing>'), []).append(d)
    def ready(d):
        return active(d) and d['fields'].get('templateStatus') == 'READY' and any(active(t) for t in groups.get(d['id'], []))
    duplicates = {'category': [], 'subcategory': []}
    duplicate_ids = set()
    for typ in duplicates:
        buckets = {}
        for d in indexed[typ].values():
            parent = d['fields'].get('categoryId') if typ == 'subcategory' else '<root>'
            buckets.setdefault((parent, normalize(d['fields'].get('name'))), []).append(d['id'])
        for (parent, name), ids in sorted(buckets.items(), key=lambda x: str(x[0])):
            if len(ids) > 1:
                duplicates[typ].append({'parentId': parent, 'normalizedName': name, 'ids': sorted(ids),
                    'scopes': [list(scope(indexed[typ][id_])) for id_ in sorted(ids)]})
                duplicate_ids.update((typ, id_) for id_ in ids)
    cross_parent = []
    buckets = {}
    for d in indexed['subcategory'].values():
        parent = indexed['category'].get(d['fields'].get('categoryId'))
        if parent and active(parent):
            buckets.setdefault(normalize(d['fields'].get('name')), []).append(d)
    for name, ds in sorted(buckets.items()):
        if len({d['fields'].get('categoryId') for d in ds}) > 1:
            cross_parent.append({'normalizedName': name, 'classifications': ['DOMAIN_REVIEW_REQUIRED'],
                'reason': 'Keep distinct valid parents; display name is not semantic equivalence.', 'records': [
                {'id': d['id'], 'parentId': d['fields'].get('categoryId')} for d in ds]})
    cross_parent_ids = {r['id'] for group in cross_parent for r in group['records']}
    mappings = []
    classification = []
    category_targets = {}
    # Only declared SYSTEM aliases in the same business/catalogue scope are safe proposals.
    for typ in ['category', 'subcategory', 'unit']:
        for id_, d in sorted(indexed[typ].items()):
            f = d['fields']; own_refs = by_id[(typ, id_)]; labels = []
            if active(d) and (typ != 'subcategory' or ready(d)): labels.append('CANONICAL_ACTIVE')
            if not active(d): labels.append('RETIRED_BUT_REFERENCED' if own_refs else 'UNREFERENCED_LEGACY')
            if own_refs and (not active(d) or scope(d)[0] != 'SYSTEM'): labels.append('LEGACY_REFERENCED')
            if (typ, id_) in duplicate_ids:
                labels.append('DUPLICATE_REFERENCED' if own_refs else 'DUPLICATE_SHADOW')
            candidates = []; target = None; evidence = ''; warnings = []
            if typ == 'category' and not active(d) and scope(d)[0] == 'SYSTEM':
                candidates = [t for t in indexed[typ].values() if active(t) and scope(t) == scope(d)
                              and normalize(f.get('name')) in {normalize(a) for a in t['fields'].get('aliases', [])}]
                if len(candidates) == 1:
                    target = candidates[0]['id']; category_targets[id_] = target
                    evidence = 'Explicit current SYSTEM category alias; same catalogue/business scope.'
            elif typ == 'subcategory' and (not active(d) or (typ, id_) in duplicate_ids):
                parent = category_targets.get(f.get('categoryId'), f.get('categoryId'))
                candidates = [t for t in indexed[typ].values() if t['id'] != id_ and ready(t)
                              and scope(t) == scope(d) and t['fields'].get('categoryId') == parent
                              and (normalize(t['fields'].get('name')) == normalize(f.get('name'))
                                   or normalize(f.get('name')) in {normalize(a) for a in t['fields'].get('aliases', [])})]
                if len(candidates) == 1 and groups.get(id_) and template_signature(groups[id_]) == template_signature([t for t in groups.get(candidates[0]['id'], []) if active(t)]):
                    target = candidates[0]['id']; evidence = 'Explicit parent context and identical full template semantics in same scope.'
                elif candidates:
                    warnings.append('Name/parent candidate is insufficient: template semantics differ or candidates conflict.')
            elif typ == 'unit' and normalize(f.get('name')) in {'l', 'ltr', 'lt', 'kg', 'g', 'ml', 'm'}:
                labels.append('UNIT_ALIAS')
                names = {'l': 'litre', 'ltr': 'litre', 'lt': 'litre', 'kg': 'kilogram', 'g': 'gram', 'ml': 'millilitre', 'm': 'metre'}
                candidates = [t for t in indexed[typ].values() if active(t) and normalize(t['fields'].get('name')) == names[normalize(f.get('name'))]]
                if len(candidates) == 1 and unit_equivalent(f, candidates[0]['fields']):
                    target = candidates[0]['id']; evidence = 'Explicit unit dimension, kind, scale and meaning match.'
                else: warnings.append('Exact dimension/kind/scale/meaning metadata is missing or incompatible; retain display alias.')
            needs_review = ((typ, id_) in duplicate_ids or not active(d) or f.get('scopeReviewRequired')
                            or (typ == 'subcategory' and id_ in cross_parent_ids)
                            or (typ == 'subcategory' and not ready(d)) or 'UNIT_ALIAS' in labels
                            or (typ == 'category' and scope(d)[0] != 'SYSTEM'))
            if needs_review and target is None:
                labels.append('DOMAIN_REVIEW_REQUIRED')
                warnings.append('No unambiguous ID/parent/semantic mapping established; keep record.')
            classification.append({'recordType': typ, 'id': id_, 'name': f.get('name'),
                'parentId': f.get('categoryId') if typ == 'subcategory' else None,
                'aliases': f.get('aliases', []), 'templateStatus': f.get('templateStatus'),
                'scopeReviewRequired': f.get('scopeReviewRequired', False),
                'unitSemantics': {k: f.get(k) for k in ('measurementDimension', 'unitKind', 'scaleToBase', 'meaning')} if typ == 'unit' else None,
                'scope': list(scope(d)), 'status': f.get('status'), 'isDeleted': d['row'].get('isDeleted'),
                'classifications': sorted(set(labels)), 'referenceCount': len(own_refs),
                'activeReferenceCount': sum(r['activeOwner'] for r in own_refs),
                'productReferenceCount': sum(r['table'] == TABLES['product'] for r in own_refs),
                'templateReferenceCount': sum(r['table'] == TEMPLATE for r in own_refs),
                'references': own_refs, 'candidateCanonicalIds': sorted(t['id'] for t in candidates)})
            if needs_review:
                mappings.append(asdict(CatalogueCanonicalMapping(typ, id_, target,
                    evidence or 'DOMAIN_REVIEW_REQUIRED: no verified semantic equivalence.', len(own_refs),
                    bool(target and not own_refs), bool(own_refs), tuple(warnings), semanticEvidence=evidence)))
    orphan_groups = []
    for id_, group in sorted(groups.items()):
        target = indexed['subcategory'].get(id_)
        if not target or not ready(target):
            candidates = [d['id'] for d in indexed['subcategory'].values() if ready(d)
                          and template_signature(group) == template_signature([t for t in groups.get(d['id'], []) if active(t)])]
            orphan_groups.append({'subcategoryId': id_, 'subcategoryExists': bool(target),
                'subcategoryStatus': target['fields'].get('status') if target else None,
                'rowCount': len(group), 'activeRowCount': sum(active(d) for d in group),
                'rowIds': [d['id'] for d in group], 'candidateCanonicalIds': candidates,
                'classifications': ['ORPHAN_TEMPLATE_GROUP', 'DOMAIN_REVIEW_REQUIRED'],
                'reason': 'No approved ID/parent mapping for template group; semantic comparison alone cannot attach it.'})
            if not target:
                mappings.append(asdict(CatalogueCanonicalMapping('templateGroup', id_, None,
                    'Missing subcategory definition; no verified parent context.',
                    sum(r['recordType'] == 'subcategory' and r['legacyId'] == id_ for r in refs),
                    requiresDataMigration=True, warnings=('DOMAIN_REVIEW_REQUIRED',))))
    broken = [r for r in refs if not r['exists'] and r['table'] in {TABLES['product'], TABLES['variant']}]
    for d in indexed['variant'].values():
        if active(d) and not d['fields'].get('productId'):
            broken.append({'recordType': 'product', 'legacyId': None, 'table': d['table'],
                           'documentId': d['id'], 'path': ['productId'], 'activeOwner': True, 'exists': False})
    for r in broken:
        r['classifications'] = ['BROKEN_REFERENCE', 'DOMAIN_REVIEW_REQUIRED']
        r['recommendation'] = 'Recover original referenced record from authorized backup/server evidence; never auto-attach or regenerate identity.'
    retired = [c for c in classification if 'RETIRED_BUT_REFERENCED' in c['classifications']]
    legacy_cats = [c for c in classification if c['recordType'] == 'category' and c['productReferenceCount'] and 'LEGACY_REFERENCED' in c['classifications']]
    legacy_subs = [c for c in classification if c['recordType'] == 'subcategory' and c['productReferenceCount'] and ('LEGACY_REFERENCED' in c['classifications'] or 'DUPLICATE_REFERENCED' in c['classifications'])]
    aliases = [c for c in classification if 'UNIT_ALIAS' in c['classifications']]
    return {'tableCounts': {k: len(v) for k, v in sorted(rows.items())},
        'counts': {'duplicateCategoryGroups': len(duplicates['category']),
            'duplicateSubcategoryGroups': len(duplicates['subcategory']), 'differentParentNameGroups': len(cross_parent),
            'legacyReferencedCategories': len(legacy_cats), 'legacyReferencedSubcategories': len(legacy_subs),
            'orphanTemplateGroups': len(orphan_groups), 'missingSubcategoryTemplateGroups': sum(not g['subcategoryExists'] for g in orphan_groups),
            'unitAliases': len(aliases), 'brokenReferences': len(broken),
            'safeCanonicalMappings': sum(bool(m['canonicalId']) for m in mappings),
            'unsafeAmbiguousMappings': sum(not m['canonicalId'] for m in mappings)},
        'catalogueRecords': classification, 'canonicalMappings': mappings,
        'duplicateCategories': duplicates['category'], 'duplicateSameParentSubcategories': duplicates['subcategory'],
        'sameNameDifferentValidParents': cross_parent, 'legacyReferencedCategories': legacy_cats,
        'legacyReferencedSubcategories': legacy_subs, 'retiredButReferenced': retired,
        'unitAliases': aliases, 'brokenReferences': broken, 'orphanTemplateGroups': orphan_groups,
        'templateGroups': [{'subcategoryId': id_, 'rowCount': len(ds), 'activeRowCount': sum(active(d) for d in ds),
                            'referenceCount': sum(r['recordType'] == 'subcategory' and r['legacyId'] == id_ for r in refs),
                            'semanticFingerprint': hashlib.sha256(json.dumps(template_signature(ds)).encode()).hexdigest(),
                            'classifications': ['ORPHAN_TEMPLATE_GROUP', 'DOMAIN_REVIEW_REQUIRED'] if any(g['subcategoryId'] == id_ for g in orphan_groups) else ['CANONICAL_ACTIVE'],
                            'rowIds': [d['id'] for d in ds]} for id_, ds in sorted(groups.items())],
        'productReferences': [r for r in refs if r['table'] == TABLES['product']],
        'variantReferences': [r for r in refs if r['table'] == TABLES['variant']],
        'allReferences': refs,
        'domainReviewRequired': [c for c in classification if 'DOMAIN_REVIEW_REQUIRED' in c['classifications']] + orphan_groups + broken}


def unit_equivalent(a, b):
    # No missing==missing inference, and never packaging -> measurement.
    keys = ('measurementDimension', 'unitKind', 'scaleToBase', 'meaning')
    return (normalize(a.get('name')) not in PACKAGING and normalize(b.get('name')) not in PACKAGING
            and a.get('unitKind') == b.get('unitKind') == 'MEASUREMENT'
            and all(a.get(k) is not None and a.get(k) == b.get(k) for k in keys))


class SandboxCatalogueMigration:
    """Only owns a new TemporaryDirectory DB. No API accepts a writable live DB."""
    def __init__(self, rows):
        self._directory = tempfile.TemporaryDirectory(prefix='nubibill-phase8-')
        self.path = Path(self._directory.name) / 'sandbox.db'
        self.db = sqlite3.connect(self.path)
        self.db.row_factory = sqlite3.Row
        # Preserve complete original columns; synthetic fixtures use this same document schema.
        for table, records in rows.items():
            if not table.startswith('local_') and table not in {'sync_outbox', 'sync_queries', 'sync_conflicts'}: continue
            if not re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', table): raise ValueError('Invalid table')
            columns = list(records[0]) if records else ['remoteId', 'payloadJson', 'status', 'isDeleted', 'categoryId', 'subcategoryId']
            if records:
                for column in columns:
                    if not re.fullmatch('[A-Za-z_][A-Za-z_0-9]*', column): raise ValueError('Invalid column')
            definition = ','.join(f'"{k}"' + (' PRIMARY KEY' if k == 'remoteId' else '') for k in columns)
            self.db.execute(f'CREATE TABLE "{table}" ({definition})')
            for row in records:
                self.db.execute(f'INSERT INTO "{table}" VALUES ({",".join("?" for _ in columns)})', list(row.values()))
        self.db.execute('''CREATE TABLE migration_audit (
            migrationId TEXT, recordType TEXT, legacyId TEXT, canonicalId TEXT,
            referenceCountBefore INTEGER, referenceCountAfter INTEGER, timestamp TEXT,
            status TEXT, notes TEXT, PRIMARY KEY(migrationId,recordType,legacyId))''')
        self.db.commit()

    def close(self):
        self.db.close(); self._directory.cleanup()

    def snapshot(self):
        return {r[0]: [tuple(v) for v in self.db.execute(f'SELECT * FROM "{r[0]}" ORDER BY 1')]
                for r in self.db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")}

    def apply(self, mappings, migration_id, timestamp, fail_at=None):
        """Explicit approved mappings only. All mutations and audit share one transaction.

        fail_at is a sandbox-only test callback, after actual SQL writes.
        Historical/config/sync references are blockers, never rewritten.
        """
        if not self.path.resolve().is_relative_to(Path(self._directory.name).resolve()):
            raise ValueError('Sandbox path escaped')
        connections = list(self.db.execute('PRAGMA database_list'))
        if len(connections) != 1 or Path(connections[0]['file']).resolve() != self.path.resolve():
            raise ValueError('Only the owned temporary SQLite connection is permitted')
        if not mappings or not migration_id or not timestamp: raise ValueError('Nonempty plan/audit identity required')
        rows = load_rows(self.db); docs = documents(rows)
        indexed = {t: {d['id']: d for d in docs if d['table'] == table} for t, table in TABLES.items()}
        lookup = {}; groups = {}
        for d in docs:
            if d['table'] == TEMPLATE: groups.setdefault(d['fields'].get('subcategoryId'), []).append(d)
        for m in mappings:
            if m.recordType not in {'category', 'subcategory', 'unit', 'templateGroup'}:
                raise ValueError('Identity/history mappings forbidden')
            if not m.approved or not m.semanticEvidence or not m.canonicalId:
                raise ValueError('Explicit semantic approval required')
            if any('DOMAIN_REVIEW_REQUIRED' in warning for warning in m.warnings):
                raise ValueError('Unresolved domain review prevents migration')
            key = (m.recordType, m.legacyId)
            if key in lookup: raise ValueError('Duplicate source mapping')
            lookup[key] = m.canonicalId
        for (typ, id_), target in lookup.items():
            seen = {id_}; cursor = target
            while (typ, cursor) in lookup:
                if cursor in seen: raise ValueError('Mapping cycle')
                seen.add(cursor); cursor = lookup[(typ, cursor)]
            if cursor in seen: raise ValueError('Mapping cycle')
            if cursor != target: raise ValueError('Mapping chains must be flattened explicitly')
            target_type = 'subcategory' if typ == 'templateGroup' else typ
            if target not in indexed[target_type] or not active(indexed[target_type][target]):
                raise ValueError('Missing/inactive canonical target')
            if typ != 'templateGroup' and id_ not in indexed[typ]: raise ValueError('Missing legacy source')
            if typ == 'templateGroup' and id_ not in groups: raise ValueError('Missing orphan group')
            if typ in {'subcategory', 'templateGroup'}:
                t = indexed['subcategory'][target]
                if t['fields'].get('templateStatus') != 'READY' or not any(active(d) for d in groups.get(target, [])):
                    raise ValueError('Target template is not READY')
                if typ == 'subcategory':
                    source_parent = indexed[typ][id_]['fields'].get('categoryId')
                    if lookup.get(('category', source_parent), source_parent) != t['fields'].get('categoryId'):
                        raise ValueError('Cross-parent subcategory mapping')
                if typ == 'templateGroup' and template_signature(groups[id_]) != template_signature([d for d in groups[target] if active(d)]):
                    raise ValueError('Orphan template semantics differ')
            if typ == 'unit' and not unit_equivalent(indexed[typ][id_]['fields'], indexed[typ][target]['fields']):
                raise ValueError('Unit semantics do not exactly match')
        # All post-migration active Product pairs must resolve to READY. No partial parent move.
        for p in indexed['product'].values():
            f = p['fields']; old_c = f.get('categoryId'); old_s = f.get('subcategoryId')
            if not active(p) or (('category', old_c) not in lookup and ('subcategory', old_s) not in lookup): continue
            cat = lookup.get(('category', old_c), old_c); sub = lookup.get(('subcategory', old_s), old_s)
            target = indexed['subcategory'].get(sub)
            parent = target['fields'].get('categoryId') if target else None
            parent = lookup.get(('category', parent), parent)
            if (cat not in indexed['category'] or not active(indexed['category'][cat]) or not target or not active(target)
                    or parent != cat or target['fields'].get('templateStatus') != 'READY'
                    or not any(active(d) for d in groups.get(sub, []))):
                raise ValueError('Product target pair not READY/coherent')
        before = references(rows)
        allowed = {('local_products', 'categoryId'), ('local_products', 'subcategoryId'),
                   (TABLES['subcategory'], 'categoryId'), (TEMPLATE, 'subcategoryId'),
                   *{(TABLES['variant'], k) for k, typ in REF_KEYS.items() if typ == 'unit'}}
        counts = {}
        for m in mappings:
            typ = 'subcategory' if m.recordType == 'templateGroup' else m.recordType
            relevant = [r for r in before if r['recordType'] == typ and r['legacyId'] == m.legacyId]
            counts[(m.recordType, m.legacyId)] = len(relevant)
            for r in relevant:
                if len(r['path']) != 1 or (r['table'], r['path'][0]) not in allowed:
                    raise ValueError('Protected historical/config/sync or unknown reference blocks migration')
                # Never overlay a semantically different orphan/legacy template group.
                if r['table'] == TEMPLATE and template_signature(groups.get(m.legacyId, [])) != template_signature([d for d in groups.get(m.canonicalId, []) if active(d)]):
                    raise ValueError('Template semantics require domain review')
        def inject(stage):
            if fail_at: fail_at(stage, self.db)
        def patch(d, fields):
            current = self.db.execute(f'SELECT payloadJson FROM "{d["table"]}" WHERE remoteId=?', (d['id'],)).fetchone()
            payload = json.loads(current['payloadJson'])
            for key, value in fields.items(): payload[key] = encode(value)
            columns = {r[1] for r in self.db.execute(f'PRAGMA table_info("{d["table"]}")')}
            updates = {'payloadJson': json.dumps(payload, separators=(',', ':'))}
            updates.update({k: v for k, v in fields.items() if k in {'categoryId','subcategoryId','status','isDeleted'} and k in columns})
            self.db.execute(f'UPDATE "{d["table"]}" SET {",".join(k+"=?" for k in updates)} WHERE remoteId=?', [*updates.values(), d['id']])
        self.db.execute('BEGIN IMMEDIATE')
        try:
            # Revalidate on the locked snapshot; this sandbox has no concurrent writer.
            if load_rows(self.db) != rows: raise ValueError('Stale plan snapshot')
            for stage, table in [('products', TABLES['product']), ('variants', TABLES['variant']),
                                 ('dependencies', None)]:
                for d in docs:
                    if (table and d['table'] != table) or (table is None and d['table'] not in {TABLES['subcategory'], TEMPLATE}): continue
                    changes = {}
                    for key, old in d['fields'].items():
                        if not isinstance(old, str) or (d['table'], key) not in allowed: continue
                        typ = REF_KEYS[key]
                        new = lookup.get((typ, old), lookup.get(('templateGroup', old)) if typ == 'subcategory' else None)
                        if new: changes[key] = new
                    if changes: patch(d, changes)
                inject(stage)
            after = references(load_rows(self.db))
            for m in mappings:
                typ = 'subcategory' if m.recordType == 'templateGroup' else m.recordType
                if any(r['recordType'] == typ and r['legacyId'] == m.legacyId for r in after):
                    raise ValueError('References remain; retirement forbidden')
            inject('before_retirement')
            for m in mappings:
                if m.recordType != 'templateGroup':
                    patch(indexed[m.recordType][m.legacyId], {'status': 'INACTIVE'})
                # Keep template row identities, moved references, and payload semantics.
                if m.recordType in {'subcategory', 'templateGroup'}:
                    for d in groups.get(m.legacyId, []): patch(d, {'subcategoryId': m.canonicalId, 'status': 'INACTIVE'})
                self.db.execute('INSERT INTO migration_audit VALUES (?,?,?,?,?,?,?,?,?)',
                    (migration_id, m.recordType, m.legacyId, m.canonicalId, counts[(m.recordType,m.legacyId)],
                     0, timestamp, 'SIMULATED', m.reason + ' | approval: ' + m.semanticEvidence))
            inject('audit')
            self.db.commit()
        except BaseException:
            self.db.rollback(); raise
        return [dict(r) for r in self.db.execute('SELECT * FROM migration_audit WHERE migrationId=? ORDER BY recordType,legacyId', (migration_id,))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    source = Path(args.database).resolve(); dest = Path(args.output).resolve()
    if source == dest or dest.suffix != '.json': raise ValueError('Output must be a distinct JSON artifact')
    with read_only(source) as db: result = inventory(load_rows(db))
    result['source'] = {'path': str(source), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'mode': 'read-only'}
    dest.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result['counts'], sort_keys=True))


if __name__ == '__main__': main()

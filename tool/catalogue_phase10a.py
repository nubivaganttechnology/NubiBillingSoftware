"""Decision evidence only: read-only SQLite, no import/migration/network operations."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalogue_phase8 as legacy

NONSEMANTIC = {'createdAt', 'updatedAt', 'createdBy', 'updatedBy', 'version',
               'localMetadataRevision', 'retiredByCatalogueId', 'retiredByCatalogueVersion'}
# Row identity is compared separately. Ordering/sections/options/conditions remain semantic.
IDENTITY = {'templateId', 'subcategoryId', 'profileId', 'name'}


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(',', ':'))


def semantic_fields(fields):
    return {k: v for k, v in fields.items() if k not in NONSEMANTIC | IDENTITY}


def differences(left, right, path=''):
    result = []
    if isinstance(left, dict) and isinstance(right, dict):
        for key in sorted(left.keys() | right.keys()):
            where = f'{path}.{key}' if path else key
            if key not in left or key not in right:
                result.append({'path': where, 'left': left.get(key), 'right': right.get(key),
                               'leftPresent': key in left, 'rightPresent': key in right})
            else:
                result.extend(differences(left[key], right[key], where))
    elif left != right:
        result.append({'path': path, 'left': left, 'right': right})
    return result


def semantic_classification(left, right):
    if left == right:
        return 'EXACT_EQUIVALENT'
    # Only explicitly listed timestamp/identity metadata is removed upstream.
    # A requiredness/default/option/order/placement difference blocks equivalence.
    return 'SEMANTIC_CONFLICT'


def all_rows(db):
    out = {}
    for (name,) in db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"):
        if not re.fullmatch(r'[A-Za-z_][A-Za-z_0-9]*', name):
            raise ValueError('Unsupported table identifier')
        out[name] = [dict(r) for r in db.execute(f'SELECT * FROM "{name}"')]
    return out


def reference_inventory(sources, ids):
    """Count logical locations once; indexed SQL mirrors are recorded separately.

    Search every table, JSON value and map key, including public config/history.
    Own identity fields are not dependencies, including document/payload mismatch.
    Embedded protected IDs are conservatively counted and never rewritten.
    """
    result = {id_: [] for id_ in ids}
    identifiers = re.compile(r"(?<![A-Za-z0-9_])(" + "|".join(re.escape(v) for v in sorted(ids, key=len, reverse=True)) + r")(?![A-Za-z0-9_])")
    for source, tables in sources.items():
        for table, rows in tables.items():
            for number, row in enumerate(rows):
                owner = str(row.get('remoteId', row.get('queryKey', row.get('queryId', row.get('id', number)))))
                found = {}
                for column, raw in row.items():
                    if column in {'remoteId', 'id', 'queryId'}: continue
                    try:
                        value = legacy.decode(json.loads(raw)) if isinstance(raw, str) else raw
                    except (ValueError, TypeError): value = raw
                    for path, scalar in legacy.leaves(value):
                        if table == 'local_product_subcategories' and column == 'payloadJson' and path == ('subcategoryId',):
                            continue
                        matches = ({scalar} if scalar in ids else set(identifiers.findall(scalar))) if isinstance(scalar, str) else set()
                        for id_ in matches:
                            location = [column, *path]
                            found.setdefault(id_, []).append(location)
                        for i, key in enumerate(path):
                            if key in ids:
                                location = [column, '<map-key>', *path[:i+1]]
                                if location not in found.setdefault(key, []): found[key].append(location)
                for id_, locations in found.items():
                    payload_locations = [p for p in locations if p[0] == 'payloadJson']
                    mirrors = [p for p in locations if len(p) == 1 and p[0] in {'subcategoryId', 'categoryId'}]
                    if table == 'local_product_subcategories': mirrors = [] # own indexed identity
                    logical = [p for p in locations if p not in mirrors] if payload_locations else locations
                    if table == 'local_product_subcategories':
                        logical = [p for p in logical if p != ['subcategoryId']]
                    if not logical: continue
                    result[id_].append({'source': source, 'table': table, 'ownerId': owner,
                        'active': row.get('status') == 'ACTIVE' or row.get('active') == 1,
                        'locations': logical, 'indexedMirrors': mirrors})
    for id_, refs in result.items():
        counts = Counter(r['table'] for r in refs)
        result[id_] = {'referencingRecords': len(refs),
            'referenceOccurrences': sum(len(r['locations']) for r in refs),
            'activeReferencingRecords': sum(r['active'] for r in refs),
            'byTable': dict(sorted(counts.items())),
            'productReferences': counts['local_products'],
            'templateReferences': counts['local_subcategory_attribute_templates'],
            'syncQueryReferences': counts['sync_queries'], 'records': refs}
    return result


def disabled_disposition(record):
    if record['duplicateGroup']:
        return 'BLOCKED_BY_DUPLICATE_DECISION', 'Resolve duplicate semantics before changing eligibility.'
    profile = record['profile'] or {}
    issues = record['templateIssues'] or []
    if (profile.get('status') == 'ACTIVE' and record['templateStatus'] == 'READY'
        and profile.get('allowedSoldAs') and profile.get('optionsOverrides')
        and any('allowedSellingUnits' in s for s in issues)
        and any('allowedOptions' in s for s in issues)):
        return 'PROBABLY_SHOULD_BE_SELECTABLE', 'Inference: active revision-5 profile uses allowedSoldAs/optionsOverrides; disabling diagnostics demand different schema keys. Confirm successor compiler/content contract before enabling.'
    return 'DOMAIN_REVIEW_REQUIRED', 'No sufficient intentional-disable or valid active-profile evidence; retain flag pending explicit domain contract.'


def build(runtime, sources):
    compiler_source = Path('lib/data/catalogue/system_catalogue_metadata.dart').read_text()
    docs = legacy.documents(sources['account'])
    records = runtime['records']
    ids = {r['documentId'] for r in records} | {r['payloadSubcategoryId'] for r in records}
    refs = reference_inventory(sources, ids)
    for record in records:
        record['references'] = refs[record['documentId']]
    disabled = []
    for r in records:
        if r['templateSelectable'] is False or r['templateSelectable'] == 'false':
            disposition, reason = disabled_disposition(r)
            sibling = [s['documentId'] for s in records if s['documentId'] != r['documentId']
                       and s['categoryId'] == r['categoryId']
                       and legacy.normalize(s['subcategoryName']) == legacy.normalize(r['subcategoryName'])]
            retired = [d['id'] for d in docs if d['table'] == 'local_product_categories'
                       and d['id'] == r['categoryId'] and not legacy.active(d)]
            disabled.append({'documentId': r['documentId'], 'name': r['subcategoryName'],
                'categoryId': r['categoryId'], 'categoryName': r['categoryName'],
                'profile': r['profile'], 'templateStatus': r['templateStatus'],
                'readiness': r['resolvedReadiness'], 'templateRowCount': r['templateRowCount'],
                'activeTemplateRowCount': r['activeTemplateRowCount'],
                'templateIssues': r['templateIssues'], 'sameParentSiblings': sibling,
                'newerCanonicalSibling': None, 'retiredParentIds': retired,
                'retiredLegacyFamilyEvidence': 'No inactive parent found; this is not proof of intentional retirement.' if not retired else 'Parent is inactive; retain for explicit domain review.',
                'explicitDomainDisableReason': None,
                'productReferences': refs[r['documentId']]['productReferences'],
                'disposition': disposition, 'reason': reason, 'approved': False})
    pairs = []
    for group in runtime['duplicateGroups']:
        members = [next(r for r in records if r['documentId'] == id_) for id_ in group['documentIds']]
        contracts = []
        for r in members:
            templates = [semantic_fields(d['fields']) for d in docs
                         if d['table'] == legacy.TEMPLATE and legacy.active(d)
                         and d['fields'].get('subcategoryId') == r['payloadSubcategoryId']]
            # Set of template rows ignores physical insertion order, but sortOrder stays.
            templates.sort(key=canonical)
            contracts.append({'parentId': r['categoryId'], 'scope': r['scope'],
                'catalogueId': r['rawFields'].get('catalogueId'),
                'status': r['rawFields'].get('status'),
                'templateSelectable': r['templateSelectable'], 'templateStatus': r['templateStatus'],
                'authoredProfile': semantic_fields(r['profile'] or {}),
                'activeTemplateRows': templates,
                'resolvedAttributes': sorted(r['productAttributes'] + r['variantAttributes'], key=lambda a: a['attributeId']),
                'unitRules': r['resolvedUnitRules']})
        diff = differences(*contracts)
        effective_diff = differences(*[{a['attributeId']: a for a in c['resolvedAttributes']} for c in contracts])
        declared = [r['documentId'] for r in members if "'id': '" + r['documentId'] + "'" in compiler_source]
        preferred = declared[0] if len(declared) == 1 else None
        pairs.append({'name': members[0]['subcategoryName'], 'parentId': members[0]['categoryId'],
            'parentName': members[0]['categoryName'], 'ids': group['documentIds'],
            'semanticClassification': semantic_classification(*contracts),
            'contracts': contracts, 'differences': diff, 'effectiveAttributeDifferences': effective_diff,
            'references': {r['documentId']: refs[r['documentId']] for r in members},
            'preferredCanonicalCandidate': preferred,
            'legacyCandidate': next((r['documentId'] for r in members if r['documentId'] != preferred), None) if preferred else None,
            'canonicalCandidateEvidence': 'Unique explicit ID in current compiler canonicalCategories declaration; identity preference only, no proof of intended template equivalence.' if preferred else 'No unique explicit canonical declaration.',
            'reason': 'No identity is selected by name, prefix or query order. Authored and/or effective contracts differ; a reviewed intended contract and reference migration plan are required.',
            'recommendedApproval': 'NEEDS_DOMAIN_CONFIRMATION' if diff else 'SAFE_TO_APPROVE',
            'approved': False, 'requiresDomainConfirmation': bool(diff)})
    mismatches = []
    for r in records:
        if r['documentId'] != r['payloadSubcategoryId']:
            doc_group = [semantic_fields(d['fields']) for d in docs if d['table'] == legacy.TEMPLATE and legacy.active(d) and d['fields'].get('subcategoryId') == r['documentId']]
            payload_group = [semantic_fields(d['fields']) for d in docs if d['table'] == legacy.TEMPLATE and legacy.active(d) and d['fields'].get('subcategoryId') == r['payloadSubcategoryId']]
            doc_group.sort(key=canonical); payload_group.sort(key=canonical)
            mismatches.append({'name': r['subcategoryName'], 'documentId': r['documentId'],
                'payloadId': r['payloadSubcategoryId'], 'activeDefinitionDocument': r['documentId'],
                'runtimeDefinitionIdentity': r['payloadSubcategoryId'],
                'recommendedCanonicalCandidate': r['documentId'],
                'recommendationReason': 'Current active definition document and explicit Phase 9 compiler regression input agree on this ID. Compiler preserves supplied canonical IDs and rejects document/payload disagreement; it cannot automatically resolve installed aliases.',
                'currentCompilerProfile': 'INTERIOR_COATING' if 'CEILING' in r['documentId'] else 'WATERPROOFING',
                'documentTemplates': doc_group, 'payloadTemplates': payload_group,
                'templateDifferences': differences(doc_group, payload_group),
                'references': {id_: refs[id_] for id_ in [r['documentId'], r['payloadSubcategoryId']]},
                'approved': False, 'recommendedApproval': 'NEEDS_DOMAIN_CONFIRMATION'})
    return {**runtime, 'disabledDispositions': disabled, 'duplicateComparisons': pairs,
            'identityMismatchReview': mismatches, 'allReferenceCounts': refs,
            'disabledDispositionCounts': dict(Counter(d['disposition'] for d in disabled)),
            'approvedForLiveExecution': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-audit', required=True)
    parser.add_argument('--account', required=True)
    parser.add_argument('--public-config', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    protected = [Path(args.account).resolve(), Path(args.public_config).resolve()]
    output = Path(args.output).resolve()
    if output in protected or output.suffix != '.json': raise ValueError('Output must be a separate JSON artifact')
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    sources = {}
    for name, path in zip(['account', 'public-config'], protected):
        with legacy.read_only(path) as db:
            if db.execute('PRAGMA query_only').fetchone()[0] != 1: raise ValueError('Read-only guard missing')
            sources[name] = all_rows(db)
    report = build(json.loads(Path(args.runtime_audit).read_text()), sources)
    after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in protected}
    if before != after: raise RuntimeError('Production changed during read-only evidence capture; stop')
    report['readOnlyCaptureChecksums'] = {'before': before, 'after': after}
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ['activeRows','eligibleRecords','selectableEntryCount','classificationCounts','disabledDispositionCounts']}))

if __name__ == '__main__': main()

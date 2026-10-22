"""Deterministic Release 4 builder. Writes test/review artifacts only, no network.

--audit-installed opens account/public-config SQLite read-only; it never imports.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re

OLD_BASEMENT = 'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BASEMENT_WATERPROOFING'
OLD_PAYLOAD = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT'
LIQUID = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_LIQUID'
CEMENTITIOUS = 'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT_CEMENTITIOUS'
REVIEW = Path('docs/catalogue-release-v4-review.json')
FIXTURE = Path('test/fixtures/system_catalogue_v4.json')
DIFF = Path('docs/phase10e-installed-v3-v4-diff.json')
ID_FIELDS = {
    'product_categories': 'categoryId', 'product_subcategories': 'subcategoryId',
    'product_attributes': 'attributeId', 'product_attribute_options': 'optionId',
    'subcategory_attribute_templates': 'templateId', 'units': 'unitId',
    'product_catalogue_releases': 'releaseId',
}
IGNORE = {'createdAt', 'updatedAt', 'publishedAt', 'createdBy', 'updatedBy',
          '_remoteUpdateTime', 'localMetadataRevision', 'contentFingerprint', 'installed'}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def registries():
    """Read the explicit Phase 9 identity/profile registries, without running Dart."""
    source = Path('lib/data/catalogue/catalogue_contract.dart').read_text()
    def literal(text, marker):
        value = text.split(marker, 1)[1].split('};', 1)[0].strip() + '}'
        # Profile registries may include explanatory Dart line comments. Strip
        # those before decoding the intentionally JSON-shaped map literal.
        value = re.sub(r'(?m)^\s*//[^\n]*$', '', value)
        return json.loads(re.sub(r',\s*([}\]])', r'\1', value.replace("'", '"')))
    units = literal(source, 'static const unitIds = ')
    options = literal(source, 'static const optionIds = ')
    profile = Path('lib/data/catalogue/system_catalogue_metadata.dart').read_text().split('static String profileFor(', 1)[1]
    families = literal(profile, 'const families = ')
    specific = literal(profile, 'const specific = ')
    return units, options, families, specific


def option_id(attribute, semantic_id, registry):
    known = registry.get(attribute, {}).get(semantic_id)
    return known or 'SYS_OPTION_' + attribute + '_' + digest([attribute, semantic_id])[:24]


def template_id(subcategory, attribute):
    # Immutable tuple keys, independent of release number, labels and order.
    return f'SYS_TEMPLATE_{subcategory}_{attribute.upper()}'


def logical(rows):
    return {collection: [{k: v for k, v in row.items() if k not in IGNORE}
                         for row in sorted(records, key=lambda r: r['id'])]
            for collection, records in sorted(rows.items())}


def runtime_fingerprint(rows):
    # Same ordered-field FNV-1a contract as CatalogueContract; Dart tests compare.
    value = 0xcbf29ce484222325
    for byte in canonical(logical(rows)).encode():
        value = ((value ^ byte) * 0x100000001b3) & ((1 << 64) - 1)
    return f'{value:016x}'


def build(content, audit):
    units, option_registry, profile_families, profile_specific = registries()
    old = next(d for d in content['candidates'] if d['canonicalId'] == OLD_BASEMENT)
    candidates = [copy.deepcopy(d) for d in content['candidates'] if d['canonicalId'] != OLD_BASEMENT]
    for id_, name, family, dimension, names in [
        (LIQUID, 'Basement Waterproofing - Liquid', 'WATERPROOFING_LIQUID', 'VOLUME', ['Litre', 'Millilitre']),
        (CEMENTITIOUS, 'Basement Waterproofing - Cementitious/Powder', 'WATERPROOFING_CEMENTITIOUS', 'MASS', ['Kilogram', 'Gram']),
    ]:
        d = copy.deepcopy(old)
        d.update(canonicalId=id_, name=name, family=family, intendedSelectability='SELECTABLE_READY',
                 remainingDomainReviews=[], changes=[], domainDecisionApproved=True,
                 sourceEvidence={**old['sourceEvidence'], 'domainAuthority': 'PHASE_10E_USER_APPROVED_DISTINCT_PRODUCTS_REQUIRED',
                                 'replacesProspectiveCandidateOnly': OLD_BASEMENT})
        d['unitRules'] = {'allowedPackUnits': names, 'defaultPackUnit': names[0],
            'allowedBaseUnits': names, 'defaultBaseUnit': names[0],
            'allowedSellingUnits': names, 'defaultSellingUnit': None,
            'conversionAllowed': False, 'conversionDimension': dimension,
            'conversionRequiresExplicitFactor': True}
        for a in d['attributes']:
            if a['attributeId'] in {'unit', 'soldAs'}:
                a['options'] = [{'id': u, 'name': u, 'scopeType': 'SYSTEM', 'sortOrder': i} for i, u in enumerate(names)]
                a['defaultValue'] = names[0] if a['attributeId'] == 'unit' else None
        d['defaults'] = {a['attributeId']: a['defaultValue'] for a in d['attributes'] if a['defaultValue'] is not None}
        d['options'] = {a['attributeId']: [o['name'] for o in a['options']] for a in d['attributes'] if a['options']}
        candidates.append(d)
    candidates.sort(key=lambda d: d['canonicalId'])
    if len(candidates) != 137 or any(d['intendedSelectability'] != 'SELECTABLE_READY' for d in candidates):
        raise ValueError('Release gate: exactly 137 valid intended candidates required')
    categories = {r['categoryId']: r['categoryName'] for r in audit['records']}
    common = {'catalogueId': 'PAINT_V1', 'scopeType': 'SYSTEM', 'status': 'ACTIVE',
              'businessTypeId': 'HARDWARE', 'businessSubTypeId': 'PAINTS', 'version': 4}
    rows = {k: [] for k in ID_FIELDS}
    def add(collection, id_, fields):
        rows[collection].append({'id': id_, ID_FIELDS[collection]: id_, **common, **fields})
    for id_ in sorted({d['categoryId'] for d in candidates}):
        add('product_categories', id_, {'name': categories[id_], 'categoryName': categories[id_]})
    for definition in sorted(content['attributeDefinitions'], key=lambda d: d['attributeId']):
        add('product_attributes', definition['attributeId'], copy.deepcopy(definition))
    used_units = set()
    option_rows = {}
    for d in candidates:
        id_ = d['canonicalId']
        add('product_subcategories', id_, {'categoryId': d['categoryId'], 'name': d['name'],
            'subcategoryName': d['name'], 'family': d['family'],
            # Revision-6 explicit rows are preserved; this key selects no defaults.
            'profileId': profile_specific.get(id_, profile_families.get(d['categoryId'], 'EXPLICIT_METADATA')),
            'templateSelectable': True, 'templateStatus': 'READY', 'unitRules': copy.deepcopy(d['unitRules']),
            'conversionDefault': False})
        for key in ['allowedPackUnits', 'allowedBaseUnits', 'allowedSellingUnits']:
            used_units.update(d['unitRules'][key])
        for a in sorted(d['attributes'], key=lambda a: a['attributeId']):
            ordered_options = sorted(a['options'], key=lambda o: (o['sortOrder'], o['id']))
            for option in ordered_options:
                code = option['id'] # immutable semantic code, not display formatting
                oid = option_id(a['attributeId'], code, option_registry)
                candidate = {'attributeId': a['attributeId'], 'name': option['name'], 'semanticCode': code}
                if oid in option_rows and option_rows[oid] != candidate:
                    raise ValueError(f'Conflicting semantic option identity {oid}')
                option_rows[oid] = candidate
            if a['attributeId'] in {'sizeUnit', 'widthUnit', 'lengthUnit', 'dimensionUnit'}:
                used_units.update(o['name'] for o in ordered_options)
            add('subcategory_attribute_templates', template_id(id_, a['attributeId']), {
                **copy.deepcopy(a), 'subcategoryId': id_, 'attributeLevel': a['level'].upper(),
                'options': [o['name'] for o in ordered_options]})
    for id_, option in sorted(option_rows.items()):
        add('product_attribute_options', id_, option)
    for name in sorted(used_units):
        if name not in units:
            raise ValueError(f'No explicit canonical unit identity for {name}')
        dimension = ('VOLUME' if name in {'Litre', 'Millilitre'} else
                     'MASS' if name in {'Kilogram', 'Gram'} else
                     'LENGTH' if name in {'inch', 'mm', 'cm', 'Metre'} else None)
        add('units', units[name], {'name': name, 'unitName': name,
                                  'measurementDimension': dimension})
    add('product_catalogue_releases', 'PAINT_V1', {
        'catalogueVersion': 4, 'schemaRevision': 1, 'compilerRevision': 6,
        'collectionRevisions': {k: 4 for k in sorted(ID_FIELDS)},
        'published': True, 'isolatedOnly': True, 'approvedForLiveExecution': False,
        'productionMigrationApproved': False, 'firestorePublicationApproved': False})
    rows = {k: sorted(v, key=lambda r: r['id']) for k, v in sorted(rows.items())}
    fingerprint = runtime_fingerprint(rows)
    semantic_sha = digest(logical(rows))
    rows['product_catalogue_releases'][0]['contentFingerprint'] = fingerprint
    review = {'phase': 'PHASE_10E_BASEMENT_SPLIT_AND_RELEASE_4_BUILD',
        'catalogueId': 'PAINT_V1', 'dataVersion': 4, 'schemaRevision': 1, 'compilerRevision': 6,
        'importable': True, 'isolatedOnly': True, 'approvedForLiveExecution': False,
        'productionMigrationApproved': False, 'firestorePublicationApproved': False,
        'domainDecision': {'classification': 'DISTINCT_PRODUCTS_REQUIRED', 'approvedByUser': True},
        'sourceContentFingerprint': content['fingerprint'],
        'contentFingerprint': fingerprint, 'semanticFingerprintSha256': semantic_sha,
        'canonicalCandidates': candidates, 'counts': {'canonicalCandidates': len(candidates),
            'selectableReady': len(candidates), 'blockedRequiredContracts': 0,
            'collections': {k: len(v) for k, v in rows.items()}},
        'duplicateDecisions': copy.deepcopy(content['duplicateDecisions']),
        'noncanonicalRecords': copy.deepcopy(content['noncanonicalRecords']),
        'oldBasementDisposition': [{'id': id_, 'disposition': 'LEGACY_UNRESOLVED_RETAIN_PENDING_REVIEW',
            'migrationApproved': False, 'retirementApproved': False,
            'prospectiveTargets': [LIQUID, CEMENTITIOUS], 'automaticReferenceMappingAllowed': False}
            for id_ in [OLD_BASEMENT, OLD_PAYLOAD]],
        'migrationInterlock': {'required': True, 'approved': False,
            'productionInstallationAllowed': False, 'diffArtifact': DIFF.as_posix()}}
    return review, rows


def write_artifact(path, data):
    if path not in {REVIEW, FIXTURE, DIFF}:
        raise ValueError('Only dedicated Phase 10E test/review artifacts can be written')
    if path == DIFF:
        # Complete row/reference evidence is retained. One deterministic row per
        # line avoids millions of indentation bytes in the machine inventory.
        parts = []
        for key, value in data.items():
            encoded = ('[\n' + ',\n'.join('    ' + canonical(row) for row in value) + '\n  ]'
                       if key == 'entries' else json.dumps(value, indent=2, ensure_ascii=False))
            parts.append('  ' + json.dumps(key) + ': ' + encoded)
        path.write_text('{\n' + ',\n'.join(parts) + '\n}\n')
    else:
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit-installed', action='store_true')
    args = parser.parse_args()
    if args.audit_installed:
        from catalogue_phase10e_interlock import capture
        write_artifact(DIFF, capture(json.loads(FIXTURE.read_text())))
    else:
        review, rows = build(json.loads(Path('docs/phase10c-canonical-content.json').read_text()),
                             json.loads(Path('docs/phase10a-catalogue-audit.json').read_text()))
        write_artifact(FIXTURE, rows)
        write_artifact(REVIEW, review)
        print(json.dumps(review['counts'], sort_keys=True))

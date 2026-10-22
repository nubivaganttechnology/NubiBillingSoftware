"""Read-only installed SYSTEM versus Release 4 diff; no migration/import API."""
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

from catalogue_phase8 import decode, read_only
from catalogue_phase10a import all_rows
from catalogue_phase10e import ID_FIELDS, IGNORE, OLD_BASEMENT, OLD_PAYLOAD, digest, canonical

ACCOUNT = Path('/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db')
PUBLIC = Path('/Users/sksuman/Documents/nubibill-test1-bcebe-public-config.db')
BACKUP = Path(str(ACCOUNT) + '.bak')


def metadata(path):
    stat = path.stat()
    return {'path': str(path), 'size': stat.st_size, 'mtimeNs': stat.st_mtime_ns,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'sidecars': [s for s in ['-wal', '-shm', '-journal'] if Path(str(path) + s).exists()]}


def dependencies(sources, ids):
    """Exact IDs, map keys and embedded protected IDs, across every table.

    Option names used with an explicit attribute context are also dependencies;
    ambiguous same-name option identities all remain protected, never auto-merged.
    """
    embedded = re.compile(r'(?<![A-Za-z0-9_])(' + '|'.join(re.escape(i) for i in sorted(ids, key=len, reverse=True)) + r')(?![A-Za-z0-9_])')
    display = {'name', 'displayName', 'normalizedName', 'unitName', 'subcategoryName', 'categoryName', 'productName', 'label'}
    option_names = defaultdict(set)
    for rows in sources.values():
        for row in rows.get('local_product_attribute_options', []):
            f = decode(json.loads(row['payloadJson']))
            if f.get('attributeId') and f.get('name'):
                option_names[(f['attributeId'], f['name'])].add(row['remoteId'])
    attribute_contexts = {a for a, _ in option_names}
    result = defaultdict(list)
    for source, tables in sorted(sources.items()):
        for table, rows in sorted(tables.items()):
            collection = table.removeprefix('local_')
            own_field = ID_FIELDS.get(collection)
            for ordinal, row in enumerate(rows):
                owner = str(row.get('remoteId', row.get('queryKey', row.get('id', ordinal))))
                found = defaultdict(set)
                payload = decode(json.loads(row['payloadJson'])) if row.get('payloadJson') else {}
                def add(id_, path, role='EXACT_ID'):
                    found[id_].add((canonical(path), role))
                def visit(value, path, context=None):
                    if isinstance(value, dict):
                        ctx = value.get('attributeId', context)
                        for key, child in value.items():
                            if len(path) == 1 and path[0] == 'payloadJson' and key in {own_field, 'id'}:
                                continue
                            if key in ids:
                                add(key, path + ['<map-key>', key], 'ATTRIBUTE_KEY_OR_ID_KEY')
                            visit(child, path + [key], key if key in attribute_contexts else ctx)
                    elif isinstance(value, list):
                        for i, child in enumerate(value):
                            visit(child, path + [i], context)
                    elif isinstance(value, str):
                        if path[-1] in display:
                            return
                        for id_ in ({value} if value in ids else set(embedded.findall(value))):
                            add(id_, path)
                        option_context = ('options' in path or 'defaultValue' in path or
                                          'defaults' in path or 'allowedOptions' in path or
                                          'optionsOverrides' in path or 'attributeValues' in path)
                        if context and option_context:
                            for id_ in option_names.get((context, value), []):
                                add(id_, path, 'OPTION_NAME_IN_ATTRIBUTE_CONTEXT')
                for column, value in row.items():
                    if column in {'remoteId', 'id', 'queryKey', 'queryId', own_field}:
                        continue
                    if column in payload: # indexed mirror, not a second dependency
                        continue
                    if column == 'payloadJson':
                        value = payload
                    elif isinstance(value, str):
                        try:
                            value = decode(json.loads(value))
                        except (ValueError, TypeError):
                            pass
                    visit(value, [column])
                for id_, locations in found.items():
                    result[id_].append({'source': source, 'table': table, 'ownerId': owner,
                        'active': row.get('status') == 'ACTIVE' or row.get('active') == 1,
                        'locations': [{'path': json.loads(path), 'role': role} for path, role in sorted(locations)]})
    return result


def capture(release):
    before = [metadata(p) for p in [ACCOUNT, BACKUP, PUBLIC]]
    sources = {}
    for name, path in [('account', ACCOUNT), ('publicConfig', PUBLIC)]:
        with read_only(path) as db:
            assert db.execute('PRAGMA query_only').fetchone()[0] == 1
            sources[name] = all_rows(db)
    installed = {}
    all_ids = {r['id'] for rows in release.values() for r in rows}
    for collection in release:
        records = {}
        for row in sources['account'].get('local_' + collection, []):
            fields = decode(json.loads(row['payloadJson']))
            records[row['remoteId']] = (row, fields)
            all_ids.add(row['remoteId'])
            payload_id = fields.get(ID_FIELDS[collection])
            if isinstance(payload_id, str):
                all_ids.add(payload_id)
        installed[collection] = records
    registry = Path('lib/data/sync/sync_query_registry.dart').read_text().split('protectedLegacyIds = <String>{', 1)[1].split('};', 1)[0]
    protected = set(re.findall(r"'([^']+)'", registry))
    all_ids.update(protected | {OLD_BASEMENT, OLD_PAYLOAD})
    refs = dependencies(sources, all_ids)
    entries = []
    for collection, incoming in sorted(release.items()):
        incoming = {r['id']: r for r in incoming}
        for id_ in sorted(set(installed[collection]) | set(incoming)):
            prior = installed[collection].get(id_)
            target = incoming.get(id_)
            if prior:
                row, fields = prior
                if fields.get('scopeType') != 'SYSTEM' and target is None:
                    continue # actual SYSTEM snapshot does not touch this record
            else:
                row, fields = {}, {}
            target_fields = {k: v for k, v in (target or {}).items() if k != 'id'}
            if target and collection == 'product_catalogue_releases':
                target_fields['installed'] = True  # actual final snapshot marker write
            reference_records = refs.get(id_, [])
            by_table = Counter(r['table'] for r in reference_records)
            changes = [{'field': key, 'beforePresent': key in fields, 'afterPresent': key in target_fields,
                        'before': fields.get(key), 'after': target_fields.get(key)}
                       for key in sorted(fields.keys() | target_fields.keys())
                       if fields.get(key) != target_fields.get(key) or (key in fields) != (key in target_fields)] if target else []
            semantic_changes = [v for v in changes if v['field'] not in IGNORE | {'version'}]
            reason = ''
            if prior is None:
                action, classification = 'INSERT', 'NEW_CANONICAL'
            elif target:
                action = 'REPLACE'
                if row.get('scopeType') != 'SYSTEM' or row.get('syncStatus') != 'SYNCED':
                    action, classification = 'PROTECTED_ID_COLLISION', 'REVIEW_REQUIRED'
                    reason = 'Actual snapshot rejects BUSINESS/pending indexed identity collision.'
                elif fields.get(ID_FIELDS[collection]) != id_:
                    classification = 'MIGRATION_REQUIRED'
                    reason = 'Document/payload correction requires approved identity-reference disposition.'
                elif semantic_changes and reference_records:
                    classification = 'REVIEW_REQUIRED'
                    reason = 'Referenced metadata changes; inspect saved values/template/query/history dependencies before live replacement.'
                else:
                    classification = 'CANONICAL_KEEP'
            elif row.get('syncStatus') != 'SYNCED' or row.get('isDeleted'):
                action = 'NO_CHANGE_PROTECTED_OR_TOMBSTONED'
                classification = 'LEGACY_RETAIN_REQUIRED' if reference_records else 'REVIEW_REQUIRED'
                reason = 'Actual complete-query reconciliation skips this pending/tombstoned row.'
            else:
                action = 'DEACTIVATE' if fields.get('catalogueId') is not None else 'TOMBSTONE'
                if id_ in {OLD_BASEMENT, OLD_PAYLOAD}:
                    classification = 'MIGRATION_REQUIRED'
                    reason = 'Ambiguous Basement identity has two prospective targets; no automatic migration/retirement approval.'
                elif reference_records:
                    classification = 'LEGACY_RETAIN_REQUIRED'
                    reason = 'Current references remain, including contextual option-value dependencies.'
                elif collection == 'subcategory_attribute_templates':
                    classification = 'REVIEW_REQUIRED'
                    reason = 'Unapproved legacy/orphan template group content must not be discarded merely because row IDs differ.'
                else:
                    classification = 'SAFE_UNREFERENCED_RETIREMENT_CANDIDATE'
                    reason = 'No cached ID/contextual references found; candidate only, retirement remains unapproved.'
            if action == 'DEACTIVATE':
                target_fields = {**fields, 'status': 'INACTIVE'}
                changes = [{'field': 'status', 'beforePresent': 'status' in fields, 'afterPresent': True,
                            'before': fields.get('status'), 'after': 'INACTIVE'}] if fields.get('status') != 'INACTIVE' else []
                semantic_changes = changes
            entries.append({'collection': collection, 'documentId': id_, 'action': action,
                'classification': classification, 'reason': reason,
                'statusBefore': fields.get('status'), 'wasActive': fields.get('status') == 'ACTIVE' and not row.get('isDeleted'),
                'beforePayloadId': fields.get(ID_FIELDS[collection]),
                'beforeFields': fields if prior else None,
                'indexedStateBefore': {k: row.get(k) for k in ['scopeType', 'syncStatus', 'isDeleted']} if prior else None,
                'beforeDigest': digest(fields) if prior else None,
                'afterDigest': digest(target_fields) if target or action == 'DEACTIVATE' else None,
                'localWriteEffects': ['lastSyncedAt=transaction-time'] if action in {'INSERT', 'REPLACE', 'DEACTIVATE', 'TOMBSTONE'} else [],
                'fieldChanges': changes, 'semanticChangedFields': [v['field'] for v in semantic_changes],
                'referenceCount': len(reference_records), 'referencesByTable': dict(sorted(by_table.items())),
                'referenceRecords': reference_records, 'approved': False,
                'migrationApproved': False, 'retirementApproved': False})
    legacy_queries = []
    for row in sources['account'].get('sync_queries', []):
        matches = protected & set(embedded_ids(json.loads(row['queryJson'])))
        if matches:
            legacy_queries.append({'queryKey': row['queryKey'], 'active': row['active'],
                'legacyIds': sorted(matches), 'queryJson': row['queryJson'], 'cursor': row.get('cursor'),
                'lastSyncedAt': row.get('lastSyncedAt'), 'disposition': 'BLOCK_MIGRATION_NO_REWRITE'})
    after = [metadata(p) for p in [ACCOUNT, BACKUP, PUBLIC]]
    if before != after:
        raise RuntimeError('Production files changed during read-only inventory; no release installation permitted')
    return {'phase': 'PHASE_10E_READ_ONLY_MIGRATION_INTERLOCK',
        'releaseFingerprint': release['product_catalogue_releases'][0]['contentFingerprint'],
        'approvedForLiveExecution': False, 'migrationApproved': False, 'retirementApproved': False,
        'productionInstallationAllowed': False, 'entries': entries,
        'counts': {'rows': len(entries), 'actions': dict(sorted(Counter(e['action'] for e in entries).items())),
                   'classifications': dict(sorted(Counter(e['classification'] for e in entries).items())),
                   'referencedRows': sum(bool(e['referenceCount']) for e in entries),
                   'activeOmissions': sum(e['wasActive'] and e['action'] in {'DEACTIVATE', 'TOMBSTONE'} for e in entries),
                   'protectedLegacyQueries': len(legacy_queries)},
        'protectedLegacyQueries': sorted(legacy_queries, key=lambda q: q['queryKey']),
        'referenceOnlyIdentities': [{'id': id_, 'classification': 'MIGRATION_REQUIRED',
            'reason': 'Historical payload/protected identity without an installed catalogue document; do not drop template/query references.',
            'referenceCount': len(refs.get(id_, [])), 'referenceRecords': refs.get(id_, []),
            'approved': False, 'migrationApproved': False, 'retirementApproved': False}
            for id_ in sorted(all_ids - {id_ for records in installed.values() for id_ in records}
                             - {r['id'] for rows in release.values() for r in rows}) if refs.get(id_)],
        'oldBasementReferences': [{'id': id_, 'referenceCount': len(refs.get(id_, [])),
            'referencesByTable': dict(sorted(Counter(r['table'] for r in refs.get(id_, [])).items())),
            'referenceRecords': refs.get(id_, []), 'migrationApproved': False, 'retirementApproved': False}
            for id_ in [OLD_BASEMENT, OLD_PAYLOAD]],
        'syncQueriesDigest': digest(sources['account'].get('sync_queries', [])),
        'productionBefore': before, 'productionAfter': after,
        'requiredOrdering': 'Reviewed reference/retention disposition and protected-query resolution before complete snapshot; coordinated process, no live authorization.',
        'referencePolicy': 'Exact IDs plus attribute-scoped option names across all account/public-config tables. Ambiguous option-name references protect every matching existing option identity. No backup SQL inspection.'}


def embedded_ids(value):
    if isinstance(value, dict):
        for key, child in value.items():
            yield key
            yield from embedded_ids(child)
    elif isinstance(value, list):
        for child in value:
            yield from embedded_ids(child)
    elif isinstance(value, str):
        yield value

"""Read-only historical Brush repair planner; never runs inside Flutter.

Usage: python3 tool/repair_brush_catalogue.py --database /path/to/nubibill.db
The legacy unversioned --apply writer is disabled. This plan is review evidence;
future publication must use the validated schema/compiler/release contract and
must not mutate legacy classifications without Phase 8 approval.
"""
import argparse
import json
import sqlite3
from pathlib import Path


def plan(database, project):
    manifest = json.loads(Path(__file__).with_name('brush_catalogue_seed_manifest.json').read_text())['records']
    db = sqlite3.connect(f'file:{database}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    root = f'projects/{project}/databases/(default)/documents'
    writes = []
    for attribute in ('brushType', 'bristleMaterial'):
        rows = db.execute("SELECT * FROM local_product_attributes WHERE attributeId=? AND scopeType='SYSTEM' AND isDeleted=0", (attribute,)).fetchall()
        if len(rows) != 1 or rows[0]['syncStatus'] != 'SYNCED' or not rows[0]['remoteUpdateTime']:
            raise ValueError(f'{attribute}: requires one synchronized SYSTEM definition with remote update time')
        definition = next(r['fields'] for r in manifest['product_attributes'] if r['fields']['attributeId'] == attribute)
        fields = {'dataType': {'stringValue': 'SELECT'}, 'allowAddNewOption': {'booleanValue': True},
                  'allowMultiple': {'booleanValue': False}, 'hintText': {'stringValue': definition['hintText']}}
        writes.append({'update': {'name': f"{root}/product_attributes/{rows[0]['remoteId']}", 'fields': fields},
                       'updateMask': {'fieldPaths': list(fields)},
                       'updateTransforms': [{'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'}],
                       'currentDocument': {'updateTime': rows[0]['remoteUpdateTime']}})
        # Existing templates can contain overrides; repair only select-control metadata.
        for row in db.execute("SELECT * FROM local_subcategory_attribute_templates WHERE attributeId=? AND scopeType='SYSTEM' AND isDeleted=0", (attribute,)):
            raw = json.loads(row['payloadJson'])
            if raw.get('subcategoryId', {}).get('stringValue') != 'SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH':
                continue
            overrides = {k: v for k, v in fields.items() if k in raw}
            if overrides:
                writes.append({'update': {'name': f"{root}/subcategory_attribute_templates/{row['remoteId']}", 'fields': overrides},
                               'updateMask': {'fieldPaths': list(overrides)},
                               'currentDocument': {'updateTime': row['remoteUpdateTime']}})
        existing = {}
        for row in db.execute("SELECT payloadJson FROM local_product_attribute_options WHERE attributeId=? AND scopeType='SYSTEM' AND isDeleted=0", (attribute,)):
            raw = json.loads(row['payloadJson'])
            existing[' '.join(raw['name']['stringValue'].split()).casefold()] = raw
        for record in manifest['product_attribute_options']:
            data = record['fields']
            if data['attributeId'] != attribute or data['name'].casefold() in existing:
                continue
            encoded = {k: {'stringValue': v} for k, v in data.items() if isinstance(v, str)}
            encoded['normalizedName'] = {'stringValue': data['name'].casefold()}
            writes.append({'update': {'name': f"{root}/product_attribute_options/{record['documentId']}", 'fields': encoded},
                           'currentDocument': {'exists': False}})
    db.close()
    return {'writes': writes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--project', default='test1-bcebe')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.apply:
        parser.error('Legacy unversioned --apply is disabled; publish only a validated catalogue release after review.')
    commit = plan(args.database, args.project)
    print(json.dumps({'reviewOnly': True, 'requiresVersionedCatalogueRelease': True, **commit}, indent=2))


if __name__ == '__main__':
    main()

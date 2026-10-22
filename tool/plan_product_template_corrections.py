"""Build a SYSTEM-only, update-time guarded Firestore REST commit from SQLite.

Usage: python3 tool/plan_product_template_corrections.py --database /path/to/db
The printed plan is review-only. Publication requires a new validated catalogue
release; this tool neither publishes a release nor approves legacy mappings.
No writes to SQLite or Firestore are performed by this tool.
"""
import argparse
import json
import sqlite3
from pathlib import Path


def encode(value):
    if isinstance(value, bool):
        return {'booleanValue': value}
    if isinstance(value, str):
        return {'stringValue': value}
    if isinstance(value, list):
        return {'arrayValue': {'values': [encode(v) for v in value]}}
    raise ValueError('Unsupported correction value')


def plan(database, project):
    records = json.loads(Path(__file__).with_name('product_template_corrections.json').read_text())['records']
    with sqlite3.connect(f'file:{Path(database).resolve()}?mode=ro', uri=True) as db:
        db.row_factory = sqlite3.Row
        writes = []
        for record in records:
            if record['collection'] != 'subcategory_attribute_templates':
                raise ValueError('Only template corrections are supported')
            row = db.execute(
                'SELECT * FROM local_subcategory_attribute_templates WHERE remoteId=? AND isDeleted=0',
                (record['documentId'],),
            ).fetchone()
            if row is None or row['scopeType'] != 'SYSTEM' or row['syncStatus'] != 'SYNCED' or not row['remoteUpdateTime']:
                raise ValueError(f"{record['documentId']}: needs synchronized SYSTEM record")
            fields = {k: encode(v) for k, v in record['fields'].items()}
            current = json.loads(row['payloadJson'])
            if all(current.get(k) == v for k, v in fields.items()):
                continue
            writes.append({
                'update': {'name': f"projects/{project}/databases/(default)/documents/{record['collection']}/{record['documentId']}", 'fields': fields},
                'updateMask': {'fieldPaths': list(fields)},
                'updateTransforms': [{'fieldPath': 'updatedAt', 'setToServerValue': 'REQUEST_TIME'}],
                'currentDocument': {'updateTime': row['remoteUpdateTime']},
            })
    return {'reviewOnly': True, 'requiresVersionedCatalogueRelease': True, 'writes': writes}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--project', default='test1-bcebe')
    args = parser.parse_args()
    print(json.dumps(plan(args.database, args.project), indent=2))

# Product KPI correction — 2026-10-02

Selected tenant: `C6btLkx5SyZvUQOzOeUUd7XxsFh2`.
Selected business: `BUS-6CB1F7443C2142159B8EBE3F9303839B`.
Source: read-only inspection of the active account SQLite database. Every cached product and variant was inspected; all currently cached records have this same tenant/business. No live records were edited or deleted.

## Products inspected

| productId | productCode | productName | status | syncStatus | SQLite isDeleted | Payload isDeleted |
|---|---|---|---|---|---|---|
| PROD-78125CD6E1864CA1AF4E3E71C915D025 | PRD-0001 | Royale Glitz Luxury Emulsion | DELETED | PENDING_UPDATE | 0 | true |
| PROD-6198168F50EA48BB9209914A7A2003D2 | PRD-0003 | Sharlimar_paint_001 | ACTIVE | SYNCED | 0 | absent |
| PROD-515E99F5F2C24423B75AEBFE81CB075A | PRD-0004 | Professional Paint Brush | ACTIVE | PENDING_CREATE | 0 | absent |

## Variants inspected

| variantId | productId | SKU | status | syncStatus | SQLite isDeleted | Payload isDeleted |
|---|---|---|---|---|---|---|
| VAR-233931D4CB8A432E8F2DC88912B59C48 | PROD-4B68A3FB3C10447F8A5696B17739C81F (missing parent) | SKU-0002 | ACTIVE | SYNCED | 0 | absent |
| VAR-3F8DCEC102144603B4BFF7DF558ECFDF | PROD-78125CD6E1864CA1AF4E3E71C915D025 (deleted parent) | SKU-0001 | INACTIVE | PENDING_UPDATE | 0 | absent |
| VAR-808222B8F37A40138FE9416965A61F49 | PROD-6198168F50EA48BB9209914A7A2003D2 | SKU-0003 | ACTIVE | SYNCED | 0 | absent |
| VAR-42F8F567B7F54AC9A653C5826B53344B | PROD-515E99F5F2C24423B75AEBFE81CB075A | SKU-0004 | ACTIVE | PENDING_CREATE | 0 | absent |
| VAR-CF94091746164266B8DA7863706991A0 | PROD-515E99F5F2C24423B75AEBFE81CB075A | SKU-0005 | ACTIVE | PENDING_CREATE | 0 | absent |
| VAR-FE7BA134B0B94E058B21689F4DBB757B | PROD-515E99F5F2C24423B75AEBFE81CB075A | SKU-0006 | ACTIVE | PENDING_CREATE | 0 | absent |

## Exact cause

The extra product was Royale Glitz Luxury Emulsion (PRD-0001). Its deletion was an ordinary queued UPDATE: the payload had `status=DELETED` and `isDeleted=true`, but the SQLite tombstone column remained 0. The local query therefore returned it, and the Product repository did not check payload deletion before creating a product family.

The extra counted variant was SKU-0001, VAR-3F8DCEC102144603B4BFF7DF558ECFDF, attached to that deleted family. The table excluded DELETED products but the KPI calculations used the entire returned dataset. This produced 3 products and 5 attached variants, while the table showed 2 products and 4 variants. Active already showed 2 because the deleted product was not ACTIVE.

SKU-0002 is a separate orphan. It did not contribute to the old fifth-variant total: no product family was returned for its missing parent. The corrected repository explicitly rejects this parent relationship.

## Old calculation

```dart
// Repository: tenant/business SQLite queries, with no payload deletion check.
// Table alone excluded p.status == 'DELETED'.
productsKpi = c.products.length;
variantsKpi = c.products.fold<int>(0, (sum, p) => sum + p.variants.length);
activeKpi = c.products.where((p) => p.isActive).length;
```

## Corrected calculation

The repository now constructs one valid dataset from the existing SQLite-backed queries:

- Both tenantId and businessId must match.
- Local tombstones are excluded by LocalDataSource.query (`isDeleted=0`).
- Payload `status=DELETED` (case-insensitive) and payload `isDeleted=true/1` are excluded.
- Products must have a nonempty name.
- Variants must themselves satisfy scope/deletion rules and reference a valid product in this dataset. Duplicate logical variant IDs are not added twice.
- Modern masters without valid stored variants do not gain an invented Default variant. The compatibility fallback is limited to legacy sellable records with selling-unit metadata.
- Sync state is never a membership predicate: SYNCED, PENDING_CREATE and PENDING_UPDATE are treated equally when the record itself is valid.

```dart
final businessProducts = c.products; // Valid repository-loaded SQLite dataset.
productsKpi = businessProducts.length;
variantsKpi = businessProducts.fold<int>(0, (sum, p) => sum + p.variants.length);
activeKpi = businessProducts.where((p) => p.isActive).length;
final tableProducts = businessProducts.where(matchesTableFilters).toList();
```

Search, Brand, Category and Status filters apply to the table only. Inactive products and nondeleted variant records remain part of normal totals; Active separately counts active products.

Read-only SQLite validation using the same scope/deletion predicates and a parent join returned **Products=2, Variants=4, Active=2**. Professional Paint Brush remains PENDING_CREATE and contributes one product plus three variants.

## Validation

37 Product repository, offline SQLite/sync and form tests passed. New tests cover pending records, deleted status/payload/tombstones, deleted and missing parents, cross-tenant/business links, modern masters without variants, legacy compatibility, and business-wide totals with search/status filters.

`flutter analyze --no-pub`: zero errors; 5 existing warnings and 39 informational findings outside the changed Product code (44 findings, nonzero exit). No sync architecture changes were made.

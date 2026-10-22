# Business-level Godown migration

## Active schema

- Godowns are stored in `godowns` with `godownId`, `godownCode`, `tenantId`, and `businessId`. `godownScope` is `CENTRAL` or `OUTLET`; Central documents store `outletId: null`, while Outlet-scoped documents reference one active Outlet in the same tenant and Business.
- Racks are stored in `racks` with `rackId`, `tenantId`, `businessId`, and parent `godownId`.
- Shelves are stored in `shelves` with `shelfId`, `tenantId`, `businessId`, `godownId`, and parent `rackId`.
- Godown codes use a tenant and Business scoped atomic counter in `document_sequences`; `godown_code_reservations` remains as a permanent code reservation ledger so deactivated codes are not reused.
- Address, contact, and capacity settings are stored as nested maps. Legacy address strings continue to display. Legacy Godowns without a scope display `Needs review`; the application does not guess whether they are Central or Outlet-scoped. Capacity tracking defaults to disabled for legacy records.
- New records do not use the legacy `storage_locations` collection. Existing documents in that collection are left untouched; no automatic migration or deletion runs.

## Migration before production rollout

The workspace has no live Firestore inspection capability and no Firestore rules file, so production records and access rules were not inspected. Export legacy `storage_locations`, group records by tenant, business, and outlet, validate each Godown → Rack → Shelf chain, then migrate verified documents while keeping their original IDs where historical records reference them. Preserve existing valid Godown codes and initialize the Business sequence above the highest valid `GD-XXXX` code. Resolve legacy ownership/scope with the business owner before assigning `CENTRAL` or `OUTLET`. Report duplicate codes for review before creating code reservations. Verify references and permissions before retiring the legacy collection. Do not delete or modify Business, Outlet, Product, Supplier, Purchase, Sales, Employee, or Membership data.

## Scope boundary

Inventory balances, stock transfers, purchase receiving into a Godown, and stock-aware Godown deactivation are separate work. Until verified inventory data is location-based, capacity Used/Available/Utilization displays `Not Available`. Existing purchase posting remains Outlet-based. Firestore rules must be added and deployed before this schema can be considered tenant-secure in production.

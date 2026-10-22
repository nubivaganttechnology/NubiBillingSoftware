# Firestore REST synchronization redesign — 2026-10-02

The implementation removes the unconditional 45-second remote synchronization timer. SQLite remains the runtime source for repository reads and local transactions; the outbox remains the only runtime write-upload path. The live account database was inspected read-only and was not reset, edited, or cleared.

## Audit recorded before implementation

The exact 98 pre-change registrations, including filters and last errors, are in [sync-query-inventory-before.json](sync-query-inventory-before.json). There were **zero exact semantic duplicates**, but many overlapping broad/narrow queries and historical date queries. Seven invoice queries contained historical dashboard dates. Twenty attribute-option queries, eight template queries and six subcategory queries overlapped broad SYSTEM/business downloads. Every registry row was eligible for the old timer after successful outbox processing.

The pre-change REST call sites are saved in [firestore-read-call-sites.txt](firestore-read-call-sites.txt). The exhaustive remote read entry points and their runtime callers were:

| Entry point | REST operation | Runtime callers |
|---|---|---|
| `FirestoreRestService.getDocument` | document GET | SyncEngine registered point pulls; outbox idempotency, read-set verification and post-commit acknowledgement; first-time bootstrap cache misses; REST transaction context if explicitly used |
| `queryEqual` | `:runQuery` | REST service compatibility API; runtime repositories use its SQLite implementation |
| `queryDocuments` | `:runQuery` | Old SyncEngine registered collection pulls; first-time bootstrap collection misses |
| `runQuery`, `listDocuments` | delegate to `queryDocuments` | Compatibility aliases, not additional requests |
| `aggregateDocuments` | `:runAggregationQuery` | REST compatibility API; runtime dashboard aggregates use SQLite |
| `runAggregationQuery` | delegates to `aggregateDocuments` | Compatibility alias |

`main.dart` constructs one REST backend and injects OfflineFirestoreService into application repositories. Searching/rebuilding/expanding normal module UI was not itself a direct REST loop. The existing bounded REST transaction retry is separate from runtime SQLite transactions. Maintenance scripts under `tool/` are explicitly invoked administrator operations, not app background loops.

A healthy old cycle made **95 structured queries + 3 GETs = 98 pull requests**, before counting outbox prerequisite and acknowledgement reads. If each cycle finished within 45 seconds, this was approximately **7,840 pull requests/hour**. A read-only estimate against cached SYNCED, nondeleted SQLite records gives **749 matching documents per old cycle**; [sync-read-estimate-before.json](sync-read-estimate-before.json) contains the per-query calculation. This is a cache-based estimate, not a measured remote result or billed read count. Remote data and billing can differ.

The cache contained 511 SYSTEM template documents, 21 attributes, 17 options, 8 brands, 12 categories, 50 subcategories and 6 units. Those catalogue collections, plus every registered business/outlet collection in the inventory, were eligible for repeated full downloads. The currently failing oldest outbox batch prevents reaching the pull phase; therefore 98 requests per cycle describes the healthy old flow, not the current quota-failing flow. The original audit recorded 91 query quota errors and an oldest batch attemptCount of 277.

## Flow and triggers

Old: `45s timer / registration / resume / local write -> push queue -> pull every historical query in full -> SQLite -> broad refresh`.

New: `UI -> SQLite transaction + sync_outbox -> debounced upload request -> bounded REST commits -> acknowledged SQLite records`.

Separately: `login / relevant scope change / reconnect / manual sync / stale resume -> pending uploads first -> active scoped initial or incremental pulls -> atomic SQLite document + cursor commit`.

There is no idle remote timer. The retained 400ms timer coalesces explicit events, and one-shot retry timers exist only after actual failures with pending uploads. The 30-second lease heartbeat changes SQLite only. Repeated connectivity signals with unchanged availability do not create new reconnect events. Missing-plugin and stream errors do not pretend that the network reconnected; an initially unknown signal is reported only once. Resume requests a pull only after 15 minutes since a successful remote pull; this is an event freshness gate, not polling. Switching back to a scope successfully pulled within 15 minutes reuses local data. Repeating an identical scope configuration is a no-op.

Each upload pass processes at most ten atomic operation batches, preserving the existing 500-write atomic limit. Remaining work schedules an upload-only continuation. Local writes, failed upload retries and queue continuations do not request collection pulls. Manual sync retains the existing control and runs uploads before the relevant pull. The secondary synchronization menu explicitly refreshes the SYSTEM catalogue when requested. Local pages stay available while synchronization runs.

## Cursor and catalogue strategy

Schema version 3 stores `cursor`, `active` and `catalogueVersion` in `sync_queries`; `sync_control` stores last successful pull time and durable retry/cooldown metadata. There is one deterministic key per collection + normalized filter set (including operations and typed values). Filters are sorted before serialization. Migration normalizes legacy keys and merges completed-query metadata when duplicate identities collapse. Only registry rows are deduplicated; entity records and outbox operations are preserved.

Initial downloads order by document name, which includes legacy documents lacking `updatedAt`. Incremental downloads filter `updatedAt >= previous server cursor minus two seconds`, then order by `updatedAt, __name__`. The small overlap protects equal timestamps and timestamp precision boundaries. Pages contain at most 200 documents. A name/timestamp start-after cursor handles ties. The first page's server `readTime` pins subsequent pages to the same snapshot. A strict 500-page cap prevents unbounded downloads.

All pages for one query must succeed before its fetched documents and new server cursor commit together in a SQLite transaction. A failed page changes neither documents nor cursor for that query. A scope/account generation change prevents obsolete pulls from being applied. Existing pending-change and version-conflict protection remains in the upsert path. Other collections already committed successfully retain their own valid cursors if a later collection fails.

Legacy successful registrations have no reliable server watermark. They retain completion metadata for offline product-creation prerequisites but require **one initial snapshot to establish a server cursor** after this migration. Subsequent visits use persisted cursors rather than full downloads.

Runtime REST commits assign `updatedAt` using `REQUEST_TIME`, including logical deletions. `_syncMutationId` identifies acknowledged/lost-ack batches independently of server timestamp changes. DELETE outbox operations now publish version-protected `isDeleted=true/status=DELETED` tombstones, allowing other devices to discover deletions incrementally. Local tombstones remain hidden; acknowledgement still requires remote success. Recreation of an observed tombstone uses its version precondition and clears the deleted state. External writers must also maintain server `updatedAt` and publish deletions as tombstones: a physical deletion cannot be discovered by an updatedAt query. Catalogue release/forced refresh remains a full reconciliation path for SYSTEM catalogue records.

SYSTEM catalogue collection queries are separate from BUSINESS values. On an explicit remote pull event, the small SYSTEM `product_catalogue_releases` collection is read in bounded pages to compare active release identities/versions; this check does not require legacy release records to have updatedAt. Matching versions skip initialized SYSTEM catalogue downloads. A changed release refreshes the cached SYSTEM catalogue set; an explicit SYSTEM catalogue refresh also reconciles removals. Business types/subtypes are global, as their existing schema does not require scopeType. BUSINESS custom brands, units, attributes, options and templates remain independently incremental. No release check runs while idle.

## Scope registry and local reads

Scope selection deactivates historical business/outlet/temporary registrations and reactivates canonical queries for the selected workspace and permitted modules. Global account authorization queries remain distinct. Inactive scope rows retain durable cursors for switching back; they are not executed. Normal product/customer/supplier/dashboard query filters no longer register sync queries. SQLite bootstrap queries can reuse an initialized broader query, so local searches and negative results do not create narrower remote pulls. First-time authorization/bootstrap downloads are coalesced, paginated, snapshot-pinned and persisted before the shared request completes; concurrent callers do not issue duplicate reads.

The controlled migration of the audited registry, with all modules enabled and the audited outlet selected, reuses **44** old canonical queries and deactivates **54** old registrations. Six required canonical registrations are added, giving **50 active queries / 104 registry rows**. This is a migrated test copy of the inventory, not a mutation of the running user's database. Permissions can reduce the active set.

SQLite indexes added are justified by existing SQL: active registry selection; outbox status/batch lookup and same-record dependency checks; and `(syncStatus,isDeleted)` reconciliation scans. Existing tenant/business/outlet indexes remain. A local Godown reservation table was missing from the existing offline transaction schema; it is now added and synchronized in the storage scope. Godown candidates still use the existing local sequence and legacy-reservation compatibility, but stop after **100 candidates** with a clear `reservation-limit` error and a rolled-back local transaction. Candidate lookup is at most 200 reservation reads, all SQLite in production.

## Backoff, observability and deployment

HTTP 429, RESOURCE_EXHAUSTED and quota messages stop the current pull pass immediately and persist exponential cooldown from **one hour to 24 hours**. Manual sync, reconnects, resumes, bootstrap misses and new writes respect this cooldown. Migration also honors pre-existing quota errors in the outbox or query registry. Pending records remain Pending and fully usable locally. Other failures use persisted exponential delay from five seconds to 15 minutes; authorization failures wait an hour. Explicit manual retry may bypass transient delay but not known quota cooldown. Automatic retries upload only; pure pull failures wait for another explicit event.

Debug-only instrumentation at the HTTP read boundary records collection, logical query/batch ID, scope, reason, cursor, returned-document count and duration. Sync pages, bootstrap reads and outbox prerequisite reads supply explicit context. Tokens, request headers and document payloads are not logged. REST aliases are logged only at the actual HTTP boundary, so one request does not produce duplicate read entries.

`firestore.indexes.json` includes indexes for the actual scoped initial/incremental query shapes. Deployment to `test1-bcebe` succeeded, without deleting pre-existing remote indexes absent from the local file. A bounded Firestore Admin check reports all **110 remote indexes READY**. Index readiness is not a document-read or synchronization success.

The cursor request follows the official [StructuredQuery cursor/order specification](https://firebase.google.com/docs/firestore/reference/rest/v1/StructuredQuery), [runQuery readTime contract](https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/runQuery) and [Write server timestamp transform](https://firebase.google.com/docs/firestore/reference/rest/v1/Write).

## Controlled measurements and validation

The fake REST backend uses the exact audited 98-query registry, 511 old SYSTEM templates and two old scoped products. The old algorithm is replayed rather than contacting live Firestore.

| Measurement | Old registry algorithm | New engine |
|---|---:|---:|
| Requests in one healthy old cycle / new initial scoped snapshot | 98 | 38 |
| Returned documents in that cycle / initial snapshot | 515 (overlapping reads) | 513 |
| Requests across 13 old idle ticks / initialized new idle work | 1,274 | 0 |
| Documents across those ticks / initialized new idle work | 6,695 | 0 |

A separate virtual-clock ten-minute idle test, repeated local product/dashboard navigation, searches and filters generates zero new requests. These are controlled tests, not live billing measurements. Tests also cover initial/incremental pulls, 401 equal timestamps, failed second-page rollback, scope reactivation, stale resume, reconnect, upload-only behavior, durable quota/transient backoff, catalogue releases, restart persistence, pending conflicts, tombstones/recreation, first-load coalescing, Godown collision rollback and schema migration.

Final `flutter test --no-pub`: **66 passed, exit 0**. Final `flutter analyze --no-pub`: **0 errors, 5 pre-existing warnings, 39 pre-existing info findings; exit 1**. No findings are reported in the new sync code or sync tests. The remaining findings are in existing purchase/storage/controller UI code. `git diff --check` passes. Machine-readable results are in [sync-validation-results.json](sync-validation-results.json).

Live backend verification used **one bounded GET** and still returned **HTTP 429**, REST error status **RESOURCE_EXHAUSTED**, message **Quota exceeded.** No live document was marked Synced as part of this verification. The quota has not been resolved by this code change. A full restart of the updated app is required to apply the additive schema migration and replace existing engine timers. An actual restarted-app ten-minute run and live upload/incremental acceptance cannot be claimed while quota is exhausted. The report distinguishes those outstanding live checks from passing simulated tests.

## Files changed for this synchronization task

- `lib/data/sync/sync_engine.dart`: event dispatch, active pulls, bounded uploads, durable cursor/cooldown policy and mutation acknowledgement.
- `lib/data/sync/connectivity_service.dart`: reconnect transition deduplication.
- `lib/data/services/offline_firestore_service.dart`: canonical scope registration, SQLite query isolation and coalesced paginated bootstrap reads.
- `lib/data/services/firestore_rest_service.dart`: snapshot-pinned sync pages and server updatedAt transforms.
- `lib/core/network/api_client.dart`: debug-only read instrumentation.
- `lib/data/local/local_database.dart`: additive version-3 migration, registry/control metadata, justified indexes and reservation table.
- `lib/data/local/local_data_source.dart`: caller-owned atomic transactions and remote tombstone handling.
- `lib/data/repositories/storage_repository.dart`: bounded Godown collision search.
- `lib/main.dart`: lifecycle freshness trigger.
- `lib/presentation/dashboard/admin_dashboard_page.dart`: explicit SYSTEM catalogue refresh action beside existing sync state/control.
- `firestore.indexes.json`: scoped initial/incremental query indexes.
- `test/offline_sync_test.dart`, `test/firestore_sync_rest_test.dart`, `test/connectivity_service_test.dart`: regression, integrity, request encoding and controlled read measurements.
- This report, `firestore-read-call-sites.txt`, `sync-query-inventory-before.json`, `sync-read-estimate-before.json`, and `sync-validation-results.json`: reviewable audit and validation artifacts. The earlier `firestore-read-audit.md` remains the original pre-change audit.

Product module edits already present before this synchronization task are separate from this file list.

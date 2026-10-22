# Firestore fetch and retry audit — 2026-10-02

Scope: repository-wide search for asynchronous loops, timers, listeners, UI loading triggers and Firestore/HTTP entry points; tracing through all repositories, the controller, runtime service wiring, SQLite query registry, REST transport, sync engine and outbox. Generated build/dependency files are excluded. The 72 application Dart files were searched. The active account SQLite database was inspected read-only. No live Firestore calls were made for this audit.

## Confirmed high-priority findings

1. **Unconditional background polling every 45 seconds.** `SyncEngine.start` installs a periodic timer without checking whether anything is pending, stale or newly registered. Once connected with an attached account, it continues for the lifetime of the engine. `sync` prevents concurrent engine runs, but does not prevent repeated sequential runs.
2. **Every registered query is downloaded again.** `_sync` loads all `sync_queries` rows and executes each remotely without consulting `lastSyncedAt`/`lastAttemptAt` for freshness, using a catalogue release version, or requesting only changed documents. This happens after the outbox phase succeeds, including when the outbox was empty. The current database contains 98 registered queries. At a 45-second cadence, a fast successful full pass could produce approximately 7,840 pull requests/hour, excluding outbox reads and additional triggers. Requests are not equivalent to billed document reads.
3. **Quota failures are retried indefinitely without backoff.** `_push` returns non-conflict failures, including HTTP 429, to PENDING. No next-attempt time, exponential delay, maximum automatic retry window, or quota cooldown exists. The live oldest batch has attemptCount=277 and lastError=`Quota exceeded. (HTTP 429)`. Its last attempt at inspection was `2026-10-02T16:41:50.154415Z`. A failed push aborts the current run before pulls; therefore the app is currently repeatedly attempting the first failing batch, rather than necessarily fetching all 98 queries on every timer tick.
4. **Pulls continue after HTTP 429.** The pull catch block stops only for error code `network`. Quota, authorization and server errors can cause requests against all remaining registered queries in the same pass. There are 91 persisted query errors with the same HTTP 429 message.
5. **Overlapping and historical registrations accumulate.** Scope registration downloads broad SYSTEM/business collections; repositories additionally register ACTIVE-only, per-attribute, per-subcategory and differently scoped queries. There is no query expiry/removal or restriction to the currently selected workspace. The active registry has 20 attribute-option queries, 8 template queries, 6 subcategory queries and 9 invoice queries (7 date-specific). New daily dashboard date filters create further persistent registrations. A broad SYSTEM template query overlaps narrower template queries; the local cache currently contains 511 SYSTEM template documents.
6. **Remote synchronization loses requested query limits/order.** `OfflineFirestoreService.queryDocuments` registers only filters; the sync engine supplies only these filters to REST. `orderBy`, `descending` and `limit` apply to the SQLite result but are absent from the remote pull specification. Consequently a UI request such as recent invoices with limit=100 does not limit the background Firestore download.

## Additional amplification paths

- Lifecycle resume, connectivity events, local writes and new registrations all schedule synchronization. The 400ms timer debounces closely spaced schedules; `_running` coalesces overlapping engine runs. Neither supplies rate limiting after a previous run finishes.
- Successful pulls set `changed=true` even if remote payloads are unchanged, causing `changes` events and broad controller refreshes. Product forms also reload masters/templates on these events. Ordinary module repository reads use SQLite, so these reloads are not themselves direct Firestore fetch loops. However, new query specifications discovered during reload register and schedule another pass.
- Missing/uninitialized bootstrap queries/documents can call REST directly. Concurrent identical first-load requests are not coalesced. Failed queries without `lastSyncedAt` can be attempted again by subsequent callers.
- Outbox synchronization performs document GETs to verify whole-batch idempotency, verify transaction baselines and capture post-commit versions. It caches GETs within a batch, but an automatic retry repeats them. These reads protect correctness and should be retained when fixing retry scheduling.

## Loops that are not an uncontrolled Firestore fetch loop

- The outbox `while` exits for an empty/blocked queue. Successful batches are removed; conflicts become FAILED and are excluded; other failures abort the run. No tight infinite retry was found inside that loop.
- The 30-second heartbeat writes only the SQLite lease and is cancelled in `finally`.
- The Godown `while(true)` increments a candidate number and breaks when it finds a free reservation. In production, its transaction reads are SQLite reads. It is user-triggered rather than a background polling loop; it has no explicit collision iteration cap.
- Storage hierarchy traversal detects cycles; purchase paste loops shrink their input or have a 500-row cap.
- REST transaction retries are bounded by maxAttempts=3. HTTP transport does not have an automatic retry loop.
- No Firestore snapshot listeners, FutureBuilder/StreamBuilder fetch loops or unconditional fetch-on-build path were found in application code. The Windows message loop is normal platform event processing, not a data-fetch loop.

## Recommended remediation order

1. Stop the current request storm with a persisted HTTP 429 cooldown shared by push/pull scheduling. Respect server retry timing where available; use bounded exponential backoff with jitter for transient failures. Stop the current pull pass after quota/auth failures. Keep pending local records/outbox operations intact.
2. Separate scheduled write retries from collection refreshes. Automatic idle ticks must not fetch fresh unchanged collections. Use explicit freshness intervals, workspace-aware active subscriptions and catalogue release/version checks.
3. Consolidate overlapping registrations; expire historical dashboard queries and deactivate queries for inactive workspaces. Preserve broad catalogue pulls needed to detect deactivation/removal.
4. Preserve full remote query semantics or deliberately use one canonical scoped synchronization query and apply UI filters locally. Do not accidentally truncate a completeness-sensitive catalogue pull.
5. Emit UI refresh events only for actual local changes, coalesce bootstrap requests, and make timer/subscription startup idempotent.

This audit changes no runtime code, sync status, outbox rows, credentials or Firestore data. The evidence establishes repeated polling/retry behavior and excess-read risks; it cannot attribute the entire project's Firestore quota consumption to this process alone.

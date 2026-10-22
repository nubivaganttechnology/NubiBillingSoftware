# Project-wide recurring work audit

Audited authored Dart application code, platform runners, web files and repository tools for Timer, Stream.periodic, delayed futures, recurring callbacks, polling, while loops, retries and listener feedback. Generated SDK/build/vendor code is outside the application audit.

There is no active 45-second polling timer in the current project. Earlier Firestore audit documents describe an old 45-second sync implementation; those documents are historical. The Python catalogue repair tool's timeout=45 is a single-request network deadline, not an interval.

| Trigger or duration | Current behavior |
| --- | --- |
| 400 ms | One-shot sync debounce after login, reconnect, local write, scope change or requested continuation. Replaces previous debounce timer. |
| 30 seconds | The only Timer.periodic: SQLite sync-lease heartbeat during an active sync operation. It renews a local lease and is cancelled in finally. No Firestore polling. |
| 5 seconds–15 minutes | One-shot exponential retry for transient failures with pending uploads. Retries may continue while work remains and the remote keeps failing; this is pending-work recovery, not idle catalogue polling. |
| 1–24 hours | Quota backoff; persisted cooldown blocks remote attempts. A one-shot retry is scheduled only when pending uploads exist. |
| 1 hour | Authentication failure cooldown for sync. |
| 15 minutes | Freshness threshold tested on app resume or scope change; no timer runs every 15 minutes. |
| 30 seconds in auth repository | Retry eligibility timestamp, checked when callers request a usable session; no recurring timer. |
| 15 seconds | HTTP timeout, not a poll. |
| 5 minutes | Sync lease expiry, not an independent scheduled sync. |
| 1 hour in local database | Legacy failure cooldown timestamp, not a poll. |

The outbox processes at most ten batches per pass and schedules a continuation for backlog. Remote pagination stops after 500 pages and throws on the limit. REST transactions have a default maximum of three attempts. Storage traversal has cycle detection; purchase-import loops remove entries or are capped at 500 rows. The Windows GetMessage loop is the required native event loop. Purchase-grid scroll synchronization has a reentrancy guard. Controller/form subscriptions have disposal paths.

## Applied fixes

- Cancel an obsolete sync retry when a new sync pass starts and when the workspace scope changes.
- Bind retry callbacks to their original local source and scope generation so old callbacks cannot trigger work in a new scope.
- Prevent scheduling/start/sync calls and connectivity callbacks after sync-engine disposal.
- Make connectivity start idempotent, preventing duplicate subscriptions on repeated initialization.
- Ignore late initial network-check results and callbacks after connectivity disposal.
- Add a regression test for repeated connectivity initialization and post-disposal signals.

Files changed for this audit: lib/data/sync/sync_engine.dart, lib/data/sync/connectivity_service.dart, test/connectivity_service_test.dart, docs/recurring-work-audit.md. Existing working-tree changes were retained.

Changed-file Flutter analysis passes. Connectivity, offline sync and offline authentication tests passed (37 tests), including ten simulated idle minutes with zero remote reads. The full project test suite also passed: 69 tests. Static review and simulated tests do not constitute live Firestore billing measurements.

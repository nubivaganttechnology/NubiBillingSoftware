# Phase 10I — Production Clone Migration Rehearsal

**Outcome: clone-only rehearsal passed. Production Release 4 installation and migration remain unapproved.**

## Scope and safety boundary

Two SQLite source files were byte-copied into `/tmp/phase10i-production-clones-20261005-092618`. The source and copy sizes and SHA-256 hashes matched exactly, and read-only SQLite integrity checks returned `ok` for both pairs. Both copies started at schema version 3. Only further disposable copies were opened writable through the app's `LocalDatabase` migrations and Release 4 importer. The two original files remained unchanged; a separate 121-second guarded observation also found no checksum, sidecar, or process violation.

No Firestore adapter, HTTP client, or sync engine was constructed in the clone rehearsal. Remote calls: **0**. No production database was opened writable; there was no production migration or Release 4 install, and Phase 11 was not started. Detailed source/copy paths, byte counts, hashes, clone locations, and the machine-readable evidence are in [docs/phase10i-production-clone-rehearsal.json](docs/phase10i-production-clone-rehearsal.json).

## Rehearsal results

- Both disposable app copies migrated from schema version 3 to 4.
- The account copy retained all 4 Products, 7 Variants, 195 sync-query definitions (including all 10 protected legacy queries), and its original empty outbox.
- The import archived **3,903** exact legacy catalogue rows keyed by legacy fingerprint, collection, and document ID. The archived payload IDs and JSON matched the source rows; the known document/payload ID mismatches were preserved rather than normalized.
- Release `PAINT_V1` installed with data version 4, schema revision 1, and compiler revision 6. All **137** canonical selectors resolved, and all **137** candidate forms were READY and validated.
- Existing Products without provenance resolved as `provenanceMissing`. They were not inferred, remapped, or silently resolved against Release 4.
- Replaying the identical Release 4 import produced no database-state change.
- SQLite `PRAGMA integrity_check` returned `ok` for both migrated copies, and again for the account copy after the Release 4 import.
- All six injected import-failure checkpoints restored the complete clone database state, including the release marker. A restore drill recreated the original v3 account/public-config pair from the preserved source images and verified hashes and SQLite integrity.

## Compatibility interpretation

The compatibility inventory contains **242 `LEGACY_RETAIN_REQUIRED`** and **2,506 `REVIEW_REQUIRED`** rows. These are evidence for retention and later human review—not migration approval. Historical identifiers and values remain untouched. No name-, timestamp-, or current-catalogue-based remapping is allowed. The 10 protected query definitions likewise remain intact pending explicit approval.

The rehearsal exposed an installed-Release-4 case where active canonical template rows coexist with inactive legacy rows for the same attribute. The resolver now prefers active rows only when an installed SYSTEM catalogue marker confirms version 4 or newer; without that marker it preserves the previous pre-Release-4 row-order behavior. The pre-Release-4 audit and Release 4 form simulations passed after this compatibility guard.

## Verification and limits

The dedicated clone rehearsal passed. Focused resolver/audit/form coverage passed **305 tests**. The full Flutter suite passed **663 tests**, with one environment-gated Phase 10I test skipped when the clone environment variables were absent; the clone test was separately run with the verified clone environment and passed. Sequential execution and an extended timeout were needed for the existing long catalogue simulations and the 120-second safety observation. `flutter analyze` reported 48 repository-wide infos/warnings and no errors; none of the remaining findings were attributed to the Phase 10I test or resolver change.

This rehearsal verifies byte identity at clone creation followed by clone-local migration/import invariants. It is not a separate semantic reconstruction of every source table. It also does not exercise creation of a new Product/Variant; it proves snapshot/import transaction rollback and preservation of existing Product/Variant state instead.

## Gate decision

Phase 10I is complete as a **disposable-copy rehearsal only**. A separate, explicit approval is still required before any production migration or Release 4 installation. No production write, Firestore access, or Phase 11 work is authorized by these results.

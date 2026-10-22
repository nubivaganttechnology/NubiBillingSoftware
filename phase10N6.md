# Phase 10N6 — Final Verification Postflight

**Status: COMPLETE.** The sequential Flutter suite passed with 698 passed,
1 skipped, and exit code 0. The Phase 9C observation passed in-suite. Fresh
postflight checks confirmed the account DB, public-config DB, and account
backup hashes are unchanged; no SQLite sidecars or open DB handles were found.

## Sequential Full Suite

The suite ran with Phase 10I environment gates unset:

```sh
env -u PHASE10I_CLONE_DIR -u PHASE10I_ACCOUNT_PROJECT -u PHASE10I_ACCOUNT_UID -u PHASE10I_CONFIG_PROJECT -u PHASE10I_CONFIG_UID flutter test --no-pub --timeout 5m --concurrency 1 --reporter compact
```

Result: **698 passed, 1 skipped, all other tests passed.** The command emitted
`FLUTTER_TEST_EXIT_CODE=0`.

The suite includes migration-runner tests that perform dry-run and execute-mode
checks against disposable databases under the system temporary directory. No
production DB path was passed to the runner. No production dry-run or migration
execution was manually invoked.

## Phase 9C Guard

The in-suite guarded observation completed for 120 seconds with 23 samples.
The account DB hash matched at observation start and end, as did the backup
hash. Both `processViolation` and `checksumViolation` were `false`.

| Artifact | Observation SHA-256 | Expected SHA-256 | Match |
|---|---|---|---|
| Account DB | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | **YES** |
| Account backup | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | **YES** |

## Read-Only Production Postflight

Fresh `shasum -a 256` results after the suite:

| Artifact | SHA-256 | Expected SHA-256 | Match |
|---|---|---|---|
| Account DB | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | **YES** |
| Public-config DB | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | **YES** |
| Account backup | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | `853c9fd6dd9a9032a25bfb0e742f1a3b5acb30fb60cb6211f7218b2783cdf651` | **YES** |

The database-path listing showed no `.db-wal`, `.db-shm`, or `.db-journal`
sidecars for either production DB. `lsof` reported no open handles for either
DB. No production DB or backup was written during this verification phase.

## Disposition

Verification is complete. No application or test source was edited in this
phase, and no production dry-run, migration execution, or live Firestore/network
operation was performed. Existing unrelated worktree changes were left intact.

## Phase 10O5 Candidate Verification

**Candidate:** `8e3658690ddb142717c7e9a75246a27fcb2bb877` on
`fix/product-master-audit`, commit message
`release(product-master): bind Release 4 production candidate`. The candidate
tree was clean before post-commit verification. This O5 section supplements
the historical N6 result above; it does not replace it.

### Sequential Post-Commit Suite

The suite ran at the candidate commit with all Phase 10I clone variables unset:

```sh
env -u PHASE10I_CLONE_DIR -u PHASE10I_ACCOUNT_PROJECT -u PHASE10I_ACCOUNT_UID -u PHASE10I_CONFIG_PROJECT -u PHASE10I_CONFIG_UID flutter test --no-pub --timeout 5m --concurrency 1 --reporter compact
```

**Result:** 698 passed, 0 failed, 1 skipped; terminal reported “All other tests
passed” and the command completed successfully (exit code 0). The one skip is
the environment-gated legacy Phase 10I/10IB clone rehearsal, whose source pins
an older schema-v3 preimage; it skips when `PHASE10I_CLONE_DIR` is unset as
required for this O5 run. Current v4/R3 disposable-clone runner/CLI, rollback,
and failure-injection cases passed in the Phase 10M/N4 tests. Production DB
paths were not passed to a migration runner. No production DRY_RUN,
`--execute`, migration, write, Firestore, or network operation was performed.

### Analyzer

`flutter analyze --no-pub`: **0 errors, 5 warnings, 42 infos** (47 total
findings). All five warnings are in the unchanged procurement UI files
`lib/presentation/procurement/purchase_entry_page.dart` and
`lib/presentation/procurement/purchase_pages.dart`; the Release 4 runner and
catalogue have no analyzer errors. The informational findings are recorded in
the analyzer output and do not change the candidate source tree.

### Candidate Artifact SHA-256

These hashes identify the files as committed in candidate
`8e3658690ddb142717c7e9a75246a27fcb2bb877`. Governance/report hashes below are
the candidate-commit versions, before this post-commit evidence update.

| Artifact | SHA-256 |
|---|---|
| `bin/production_migration_runner.dart` | `0303c1cc31a07772489e7c89ecc88f55d32476814426fa8bed460075e40e371a` |
| `lib/data/migration/production_migration_runner.dart` | `0827dfcf9f164b11acaba835203ab6f7037e5dfd60af408b7fc1a56450ead4fb` |
| `tool/paired_database_restore.py` | `69bc6cb201fe299b0bb465038c54c0db2d962422aa21e0cbaf408d2bd9914249` |
| `test/fixtures/system_catalogue_v4.json` | `f9b6cb7711df6fe6af740750eca816f2e0a1d76074e7dd3ba930b8dd5d094bd8` |
| `lib/data/catalogue/catalogue_contract.dart` | `2a341937c0d79d73aed26957025d159e1374028784bfcede6b4479153ceaafd0` |
| `lib/data/catalogue/catalogue_fingerprint.dart` | `87978dc7bb86b41732ce0a1ccc24821e40381e70d9b47700d5a8d82065abdc33` |
| `lib/data/catalogue/system_catalogue_metadata.dart` | `4040a5ffb53df7d7740c0d613f1be90d515e46d33dc6e5628dbd388e79f187e8` |
| `lib/data/catalogue/system_catalogue_snapshot.dart` | `c06a18d078b8a3ff4fdb5ae190e8e4743ad62e0ce2ef13c23417c520974ec3fc` |
| `docs/phase10f-migration-approval-manifest.json` | `4baaffaad071e29efc6c3371a8fcfc6c918754def4ef287c45fd17fb3e919b46` |
| `docs/phase10l-legacy-retention-policy.json` | `8e7f9dfcf12135d302c296639ba245ca57c1402c58073919097c99887d690fd7` |
| `docs/phase10j-go-no-go-checklist.json` at candidate | `c007eddc164e91a5c43549eb03fd09a41821d1671324b567e1819378c79ac0dc` |
| `docs/phase10j-production-deployment-runbook.md` at candidate | `9de382a1e0a991e91c18ac3215a92d822f8d62820e531118cdcd3f29303644d0` |
| `docs/phase10o2-deployment-authorization.json` at candidate | `e834c67dd25dbbbfacc1a6ec07adec546c6b32a05db4acef2cec90bbca2e6cb1` |

### Fresh Read-Only Production Postflight

Checked at `2026-10-05T20:41:48Z`. The exact source and approved paired
backup hashes matched. All four read-only integrity checks returned `ok`; no
WAL/SHM/journal sidecars or exact-path open handles were found.

| Database | SHA-256 | Bytes | Mode | Integrity | Open handles |
|---|---|---:|---:|---|---|
| Production account | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | 9,748,480 | `0644` | `ok` | none |
| Production public-config | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | 946,176 | `0644` | `ok` | none |
| Approved account backup | `2a0474f4bdda64b7bb31614bd983d7f730f9595fdafcae8bea9385bbd7122fa8` | 9,748,480 | `0600` | `ok` | none |
| Approved public-config backup | `9b9e4d0abeadcd9d0783f07888137a5021cfb183ab4b5922e4886dfce0590289` | 946,176 | `0600` | `ok` | none |

**Disposition:** Release 4 candidate is ready for the separately controlled
deployment phase. The candidate SHA remains immutable; checklist, runbook,
authorization overlay, and this report are recorded afterward in a separate
documentation-only verification commit. Production migration remains NOT RUN.
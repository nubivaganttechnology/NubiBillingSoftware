# Phase 10L — Legacy retention policy approval

**Phase:** `PHASE_10L_LEGACY_RETENTION_POLICY_APPROVAL`
**Policy:** `RETAIN_LEGACY_NO_AUTOMATIC_MIGRATION_NO_RETIREMENT`, version `1.0.0`
**Decision:** retention approved only; migration, retirement, Release-4 production installation, and execution remain unapproved.

## Governance decision

The Phase 10F row-by-row semantic migration approval blocker is closed **for retention only**. The decision approves preservation of unresolved historical metadata and exclusion of that metadata from new Release-4 Product creation. It does not certify semantic correctness, approve any mapping, or authorize any production operation. This is a governance record update, not an application architecture or migration change.

The versioned policy is recorded in [docs/phase10l-legacy-retention-policy.json](docs/phase10l-legacy-retention-policy.json). Its separate approval overlay is recorded in [docs/phase10f-migration-approval-manifest.json](docs/phase10f-migration-approval-manifest.json). Existing source dispositions, before-images, references, evidence, and false row-level migration/retirement approvals remain unchanged. The overlay binds to the original Phase 10E inventory SHA-256 `3af5a17dd23b8aae66385c75519ca01bd007e4b9e742138317d053f9b553b50f`.

## Exact disposition coverage

The Phase 10E ledger still contains 4,958 unique `(collection, documentId)` rows. Phase 10L covers the following four mutually exclusive classifications exactly once by their original classification and verifies their source-row counts:

| Original classification | Rows | Phase 10L decision | Migration approved | Retirement approved |
| --- | ---: | --- | --- | --- |
| `LEGACY_RETAIN_REQUIRED` | 242 | `APPROVE_RETENTION_ONLY` | No | No |
| `REVIEW_REQUIRED` | 2,506 | `APPROVE_RETENTION_PENDING_FUTURE_REVIEW` | No | No |
| `MIGRATION_REQUIRED` | 2 | `NO_AUTOMATIC_MIGRATION_RETAIN_HISTORICAL_IDENTITY` | No | No |
| `SAFE_UNREFERENCED_RETIREMENT_CANDIDATE` | 25 | `RETAIN_FOR_THIS_RELEASE` | No | No |
| **Phase 10L policy-covered rows** | **2,775** | **Retention/preservation overlay only** | **No** | **No** |

The remaining 2,183 rows are 1,128 `CANONICAL_KEEP` and 1,055 `NEW_CANONICAL`; they remain exactly as classified in the source ledger. The two `referenceOnlyIdentities` are preserved independently and are not counted as additional ledger rows. Coverage is selected by single-valued classification over unique source row keys, not by display name or a newly authored row action.

## Approved preservation rules

- Release 4 is authoritative only for new Product creation. Retained historical metadata is not selectable in Release-4 Create Product flows.
- Preserve historical SYSTEM metadata and raw saved Product/Variant values; unresolved metadata is never automatically migrated, retired, deleted, reclassified, merged, or remapped.
- Never guess or backfill a null `catalogueFingerprint`; historical Products with null provenance remain fail-closed and receive no Release-4 provenance.
- No `REVIEW_REQUIRED` row is approved for deletion; no `LEGACY_RETAIN_REQUIRED` row is deleted; no retirement candidate is retired in this release.
- Keep the four existing Products and seven existing Variants unchanged, including all SKU/barcode and saved values.
- Preserve Ceiling `documentId` and historical payload identity independently. Do not infer mapping by ID similarity.
- Preserve Basement document and payload identity independently; do not map either automatically to Release-4 Liquid or Cementitious.
- Do not automatically merge any of the ten legacy duplicate pairs.
- Preserve all 195 sync queries, including the ten protected queries. No query deletion, reactivation, rewrite, or migration-time cursor/tracking mutation is approved.
- Future legacy cleanup requires a separate explicit cleanup approval.

The policy authorizes preservation as the governance disposition; it does not assert that a new archive store or a historical resolver was implemented in this phase. Phase 10G's exact-version provenance blocker remains a technical constraint on any future implementation or installation. No architecture change was made to bypass that constraint.

## Approval and execution boundaries

The Phase 10F manifest now records `retentionPolicyApproved: true` in a separately versioned Phase 10L overlay. Its original `approvalDefaults` remain false, `preapprovedMappings` remains empty, all 14 identity review actions retain `targetId: null`, and row-level `migrationApproved` / `retirementApproved` remain false. The earlier Phase 10F blockers are superseded only as a prerequisite for approving retention; they are not removed as technical or execution safeguards.

Phase 10K sync-query preservation evidence is not modified. Its reported 195-query/10-protected-query parity remains separate technical evidence; Phase 10L does not reinterpret its clone digest as the Phase 10E source inventory digest.

Explicitly not performed or authorized:

- Production database reads or writes; Firestore access.
- Release-4 production installation or catalogue migration execution.
- Product/Variant writes, null-provenance backfill, or identity mapping.
- Sync-query changes or cursor/tracking mutation.
- Phase 11 work.

## Verification

- Source-ledger row count, unique identity count, full disposition reconciliation, policy coverage, false migration/retirement approvals, null targets, Product/Variant non-mutation declarations, protected query preservation, and production-safety declarations are covered by Phase 10L consistency tests.
- Focused Phase 10F/10L manifest and policy consistency tests: **17/17 passed**. Coverage checks reconcile all 4,958 source rows and prove the 2,775 policy-covered rows are selected exactly once, with no invented targets or newly approved migration/retirement.
- Full workspace regression suite: **677 passed, 7 failed, 1 skipped**. All seven failures are in the pre-existing Phase 10K migration-runner tests: fixtures carry SQLite `user_version=4` while the runner requires version 3, so it aborts before reaching the expected GO/migration/fault-injection outcome. No application code or Phase 10K evidence was changed in Phase 10L. These failures are unrelated to the governance JSON/test changes; they are recorded, not repaired, because this phase prohibits architecture or migration-runner work.

No technical production evidence from Phase 10K or historical source ledger was changed by this governance decision.

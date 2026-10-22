# Future PHP REST / MySQL design

Status: design only. No PHP endpoint, MySQL schema/migration, cloud biometric collection or upload has been implemented or deployed.

## Boundaries already present

```text
Camera → in-memory quality/alignment → FaceEmbeddingModel / PAD adapter
                                     ↓
                             FaceBiometricVault
                                     ↓
                    FaceVaultValueStore / atomic value-store interface
                                     ↓
                    Android Keystore + dedicated encrypted SQLite

Verified attendance → existing StaffAttendanceRepository
                    → existing SQLite transaction and durable outbox
                    → authenticated Firestore HTTPS REST transport
```

Biometric storage and attendance persistence remain separate. Neither the recognizer nor vault knows a Firestore collection schema. Employee/tenant/business/outlet IDs reuse existing entities; enrollment IDs are stable for that enrollment and change on explicit re-enrollment. Model, preprocessing and consent versions must accompany any future template representation.

## Attendance transport migration

- Add a PHP HTTPS transport behind the current repository/outbox contract. Keep SQLite-first commits, batch linkage, idempotency IDs, retry state, pending writes and cursor semantics. Do not create another attendance or payroll ledger.
- Server authentication derives tenant identity and employee permissions from the authenticated session, not request-body IDs. Enforce business/outlet assignment, attendance manage/approve separation, immutable event creation and authorized corrections.
- MySQL transactions must atomically apply a daily row and event, enforce unique event IDs and legal session transitions, and return durable acknowledgements. Cross-device/offline conflicting shifts require explicit conflict handling; a client match is not server authentication or proof of device integrity.
- Preserve original workday, UTC event instant, time-zone identifier, recording actor, device and verification-method metadata. Synchronize no template, image, score or consent document in ordinary attendance payloads.

## Optional protected biometric service — separate approval required

Current policy is **device-local templates only**. A PHP backend becoming available must not automatically enable template export or migration. Existing photographs do not exist in this implementation, and existing Android Keystore keys are non-exportable.

Any later server biometric store needs a new privacy/security/legal assessment, explicit authorization, reviewed purpose/consent and retention policy, breach response, deletion/backup design and employee manual alternative. Prefer fresh approved enrollment over silently moving current records.

Conceptual records, subject to a separately approved schema design:

| Record | Required information |
|---|---|
| Enrollment registry | Stable enrollment/employee/scope IDs, authorized devices, exact model hash and preprocessing version, consent evidence reference, status, expiry and revocation version. |
| Encrypted template | Enrollment/template ID, encrypted vector envelope, dimension/encoding, algorithm/key version and authenticated scope/model metadata. No ordinary plaintext vector columns. |
| Minimal lifecycle audit | Who authorized enrollment/replacement/revocation and when; no raw face, template, similarity score or sensitive capture diagnostics. |

- Use authenticated TLS, server-side authorization for every request, scoped encryption keys in a managed key service, envelope encryption and authenticated metadata. Never place face images on public URLs or expose decryption keys in ordinary MySQL rows, configuration shipped to Flutter, logs or responses.
- If images ever become operationally necessary, justify them separately, use restricted encrypted BLOB storage with strict limits, and provide independent retention/deletion controls. They must not become a default enrollment byproduct.
- Use explicit export/import authorization, request idempotency, signed/versioned manifests, per-record integrity verification, migration status and revocation propagation. Verify current employee assignments and renewed consent rather than copying stale scope grants.
- Template conversions/quantization or cross-device reuse require model/preprocessing equivalence testing and new calibration. Never compare different model versions because vector dimensions happen to match.
- Define scheduled expiry, key rotation/destruction, backup retention, secure deletion limitations and revocation caches before accepting the first server template. Offline cached templates must stop working on expiry/revocation according to a reviewed policy.
- Do not synchronize biometric records via the existing generic Firestore outbox. A future reviewed migration would use a separate restricted protocol with explicit data minimization, not a broad document-copy operation.

These are design constraints, not implemented security controls or an authorization to deploy/migrate employee biometrics.

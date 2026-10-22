# Staff Salary Khata Phase 3: Face Attendance Report

**Status:** Phase 2 REST synchronization verified in a local Firestore/Auth
emulator. Phase 3 attendance event and encrypted template-vault foundations are
implemented locally. Camera capture, recognition, liveness, and kiosk screens
are not complete and are not enabled.

## Completed locally

- Reused the existing Phase 2 `staff_attendance` daily record and approval
  workflow. Added immutable `staff_attendance_events` for face-kiosk check-in
  and check-out audit events. Both event creation and the corresponding daily
  row update are written through the existing SQLite transaction/outbox path.
- Added stable event IDs, duplicate check-in/check-out rejection, open-session
  checks, outlet/employee validation, UTC timestamps with a supplied shop time
  zone, overnight checkout support within 24 hours, and pending-only payroll
  attendance. Face input does not approve payroll.
- Registered attendance events in the existing local document mapping and
  attendance-scoped REST synchronization with tenant, business, outlet, and
  employee filters. Events are immutable in the local/outbox code.
- Added `BIOMETRIC_ENROLL` and `BIOMETRIC_REVOKE` permission checks to the
  existing application permission architecture.
- Added a consent-gated local template-vault service. It accepts only
  normalized embedding vectors, binds records to tenant/business/outlet/
  employee scope, rejects model-version mismatches, removes templates on
  revocation, and keeps a non-template revocation marker. Its Android adapter
  configures the existing secure-storage package with Android Keystore-wrapped
  keys and AES-GCM values. The dedicated preference file is excluded from
  Android cloud backup and device transfer.
- Manual attendance remains available through the Phase 2 attendance page.

## Phase 2 SQLite/REST verification

The existing opt-in smoke test was extended and run against local Firebase
Auth and Firestore emulators using the app's actual REST client and a disposable
SQLite database. It created emulator-only identities and verified:

- Salary profile and approved period writes through SQLite/outbox to Firestore.
- Offline check-in/out events and the updated pending attendance row through
  SQLite/outbox to Firestore, then read back through authenticated REST.
- A `STORE_PURCHASE` staff-khata record through SQLite/outbox to Firestore.
- Stable daily attendance identity and duplicate check-in rejection.
- Outbox acknowledgment after remote success.
- Owner reads succeed while a second emulator identity is denied salary and
  attendance reads by the temporary emulator rules.
- The test reported `productionTouched: false`.

The emulator ran as `demo-nubibill-phase3` with test rules under
`/private/tmp/nubibill_salary_emulator`; neither those rules nor emulator data
were deployed or written to production. The REST test exercises owner versus
other-user denial, but it is not a complete employee-role or all-outlet Rules
matrix. Production Firestore Rules previously audited for this project remain
public read/write and must be replaced and separately approved before use.

## Recognition model, license, and accuracy

No recognition or liveness model is installed or selected. Google ML Kit Face
Detection is only a detector and does not identify individuals. The inspected
Flutter `face_recognition_engine` package brings camera/detection/runtime code
but requires the app to supply its own MobileFaceNet weights; its README says
the passive spoof detector is also bring-your-own. That is not evidence of
independent accuracy or PAD validation. A separate inspected MobileFaceNet
example lists Apache-2.0 for source, but its README cites MS-Celeb-1M training
data and does not establish redistribution rights for every model weight. No
weights were downloaded or added. See [ML Kit Face Detection](https://developers.google.com/ml-kit/vision/face-detection),
[the package's model requirements](https://github.com/arnb13/face_recognition_engine),
and [MobileFaceNet repository](https://github.com/foamliu/MobileFaceNet).

There is no false-match/false-reject evidence, demographic evaluation,
photo/screen/video replay test, or recognized-identity test. No blinking,
head-turn, or other cue is represented as reliable liveness. The vault tests use
synthetic vectors and a fake storage adapter; they prove validation and
lifecycle behavior only, not encryption on physical hardware or biometric
accuracy.

## Platform and storage verification

- The application has no camera permission, camera plugin, recognition model,
  PAD dependency, kiosk provisioning screen, enrollment UI, check-in/out camera
  screens, or recognition-result screen. Android camera support and minimum
  device version have not been validated.
- The vault's value-store interface and lifecycle tests pass with an in-memory
  fake. The Android implementation is configured for RSA-OAEP key wrapping and
  AES-GCM value encryption in `flutter_secure_storage` 9.2.4. No Android device
  test was available, so Keystore operations, restore behavior, and encrypted
  persistence were not physically verified.
- Templates never enter SQLite document tables, synchronization outbox,
  Firestore, PDFs, or logs. The vault is not connected to an enrollment or
  recognition UI, so no template was created during this work.
- Consent and revocation functions are implemented in the vault, but employee
  consent capture, administrator screen authorization, and secure deletion
  behavior on a real device remain unverified.

## Tests and analysis

- `flutter test test/face_biometric_vault_test.dart test/staff_attendance_repository_test.dart test/staff_salary_repository_test.dart test/sales_posting_repository_test.dart --reporter expanded` — 21 passed.
- `flutter test test/offline_sync_test.dart --plain-name 'attendance sync uses the dedicated access scope and outlet isolation' --reporter expanded` — passed.
- `flutter test test/staff_salary_firestore_emulator_test.dart` with demo project/Auth/Firestore emulator defines — passed; actual authenticated REST round trip, not mocked.
- Flutter analysis found no compile errors or warnings. It reported 15 info-level style lints in the selected files.
- No real employees or biometric data were used. No production SQLite database or live Firestore data was touched.

## New and modified files

- `lib/data/repositories/staff_attendance_repository.dart`
- `lib/data/services/face_biometric_vault.dart`
- `lib/data/services/offline_firestore_service.dart`
- `lib/data/local/local_data_source.dart`
- `lib/data/local/local_database_tables.dart`
- `lib/data/sync/sync_outbox_repository.dart`
- `lib/core/constants/firebase_constants.dart`
- `lib/core/permissions/permission_catalog.dart`
- `lib/presentation/app_controller.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/res/xml/backup_rules.xml`
- `android/app/src/main/res/xml/data_extraction_rules.xml`
- `test/face_biometric_vault_test.dart`
- `test/staff_attendance_repository_test.dart`
- `test/sales_posting_repository_test.dart`
- `test/offline_sync_test.dart`
- `tool/staff_salary_firestore_emulator_smoke.dart`
- `docs/firestore-staff-salary-rules-proposal.md`
- `STAFF_SALARY_PHASE3_FACE_ATTENDANCE_REPORT.md`

## Remaining production blockers

1. Select and independently validate a recognition model with commercial
   redistribution rights and supported Android device requirements.
2. Select and test a presentation-attack detection model against print, screen,
   and video replay attempts. Do not enable face attendance when PAD is absent
   or uncertain.
3. Complete privacy/legal review, employee consent capture, retention policy,
   device-loss/re-enrollment process, and security threat review.
4. Add the camera flow, face-count/quality checks, model adapter, ambiguous and
   unknown identity rejection, confirmation screens, administrator-only
   enrollment/replacement, revocation UI, and accessible manual/PIN fallback.
5. Extend and approve the complete Firestore Rules; the currently deployed
   public rules do not protect attendance or salary information.
6. Test Android Keystore/backup exclusion and device-specific enrollment on
   supported shared shop devices, then run the full permission/outlet emulator
   matrix. Do not use real employee enrollment until a separate approval.

No production biometric attendance was enabled. No database migration, Firestore
Rules deployment, commit, push, or application deployment was performed.

## Follow-up: camera, model, PAD, and device evaluation

This follow-up did not add camera capture or an identity model. The prior
architecture explicitly requires privacy, security, and applicable legal
review before activating biometric processing. No such review evidence was
provided, and there is no Android device attached to this development host
(`adb devices -l` returned an empty device list). Therefore real camera
performance, hardware-backed vault persistence, and offline on-device
recognition could not be verified here.

### Model licensing and runtime findings

- The TensorFlow-maintained `tflite_flutter` runtime is Apache-2.0 and provides
  an Android inference runtime, but a runtime license does not grant rights to
  a face-recognition model or its training data. See
  [tflite_flutter](https://pub.dev/packages/tflite_flutter).
- The EdgeFace repository publishes pretrained checkpoints and source code,
  but its README does not clearly document checkpoint redistribution and
  commercial-use terms. It also provides PyTorch checkpoints rather than a
  ready-to-integrate TFLite asset. It was not selected or converted.
  See [EdgeFace](https://github.com/otroshi/edgeface).
- MobileFaceNet implementations likewise do not prove that the pretrained
  weights or underlying training data carry the same permissive license as the
  source. No model artifact was copied into the app.
- OpenPAD documents candidate PAD model licenses, including Apache-2.0 and
  MIT components, but its documented pipeline also lists an AGPL-3.0 component.
  Its reported capabilities are not independent test evidence for this
  project, its devices, or the print/screen/video attack types of interest.
  It was not integrated. See [OpenPAD](https://github.com/iamjosephmj/OpenPAD).

### PAD evaluation limits

NIST's evaluation reports variation in PAD accuracy by algorithm and attack
type, including cases where error remains high; it is not a substitute for
testing the actual kiosk camera, screen/print media, lighting, and participants.
ISO/IEC 30107-1 establishes terminology and an evaluation framework, but does
not certify a particular detector. See the [NISTIR 8491 evaluation](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=956456)
and [ISO/IEC 30107-1](https://www.iso.org/standard/83828.html).

### Current decision

Keep the camera and face-match path disabled. The next implementation gate
needs: (1) documented privacy/security/legal approval, (2) a selected model
whose exact weights and training-data terms are documented for the intended
commercial use, (3) an independently specified match/ambiguity policy and PAD
test protocol, and (4) a connected, disposable Android test device. Until then,
manual attendance remains the usable fallback. No photos, embeddings, or real
employee biometric data were captured or stored in this follow-up.

# Android face attendance implementation

Date: 2026-10-21. Project: NubiBillingSoftware-main.

## Delivery status

**Local implementation and Android compilation completed. Real biometric enrollment, identity recognition and unattended attendance are NOT activated.** No commercially reviewed embedding weights, device-specific matching calibration or validated presentation-attack detector have been installed. The production controller uses `OfflineFaceRecognition.disabled`. This follows the requested fallback when exact model rights cannot be established; no real employee recognition results are fabricated.

Navigation: **Staff Salary Khata → Attendance → face icon → Face attendance / Face enrollment**. Authorized operators can see the selected business, outlet and assigned existing employees, including temporary workers. Manual attendance remains available through the existing register. With documented participant consent, the Android screen provides camera/quality preview; it cannot save an enrollment or mark face attendance in this build.

## Architecture inspection and corrections

| Existing foundation | Finding and implementation |
|---|---|
| `staff_salary_repository.dart` | Approved attendance remains the salary input; recognition never approves a salary period. No salary formula or transaction changed. |
| `staff_attendance_repository.dart` | Existing daily `staff_attendance` and immutable `staff_attendance_events`, stable IDs, atomic SQLite/outbox writes and REST sync were retained. Previously, model/PAD version strings alone permitted face writes. A fresh, scope-bound, single-use verification object is now required. |
| `app_controller.dart` | Existing attendance/enroll/revoke permissions are reused. Controller actions validate active local employee assignment and workspace identity, and recheck permission after asynchronous operations. |
| `staff_attendance_page.dart` | Existing manual register and approval panel retained; added face attendance navigation. |
| `local_database.dart` | Existing document schema version 13, table mapping and migrations unchanged. Biometrics are not registered as synced document collections. |
| `face_biometric_vault.dart` | Existing consent/template lifecycle extended with enrollment IDs, device binding, retention, corruption checks and explicit replacement. The old preference adapter is retained solely for scoped prototype-record erasure. No prototype templates are imported automatically. |
| Android setup | CAMERA already existed. Added pinned camera/detection packages, front-camera availability handling and API 24 minimum. Removed newly inherited audio/legacy storage permission requests. AGP 9 built-in Kotlin required matching the existing Java 17 target. |

The authenticated offline session logic already permits local writes while disconnected, including an expired cached token when the network is unavailable. The ordinary attendance transaction persists locally before the sync worker sends REST requests. The template vault and matcher have no Firestore, HTTP or sync-outbox integration; ordinary attendance metadata retains the existing REST synchronization.

## Implemented components

- **Camera:** Android front-facing live preview, explicit open action, runtime denial message, serialized camera lifecycle, pause/resume cleanup, one camera lease, throttled processing and no `takePicture`/video/file/gallery calls. Capture routes request Android `FLAG_SECURE`; the camera refuses to start if protected preview setup fails.
- **Detection and quality:** bundled on-device ML Kit, exactly one detected face, frame-layout/orientation/bounds checks, minimum face/eye size, visible-landmark and pose checks, crop illumination/clipping and blur heuristics. These are pilot heuristics, not measured recognition or obstruction detection guarantees.
- **Preprocessing:** packed NV21, unmirrored upright coordinates, eye-based similarity alignment, nearest-neighbor RGB sampling at 112 × 112. Contract: `nv21-upright-eye-similarity-rgb112-v1`. Future model selection must validate this exact contract or replace it consistently for enrollment and verification.
- **Enrollment interface:** existing active employee and temporary worker IDs; visible business/outlet; consent policy and recording actor; five guided sample steps; explicit replacement; no retained photographs; revocation by selected employee or stable ID after deactivation/reassignment. Saving remains blocked without the approved model.
- **Matching interface:** normalized cosine similarity, explicit calibration and ambiguity margin, unknown/ambiguous rejection, model/device/retention checks. No production threshold is supplied. Test thresholds exist only in clearly labeled synthetic adapters under `test/support`.
- **Liveness interface:** unavailable and rejected PAD results cannot issue an attendance ticket. Neither blinking nor head pose is treated as liveness. The fallback is the existing authorized manual register.
- **Attendance integration:** private-constructor verification ticket binds tenant, business, outlet, employee, device, model, PAD and capture time; 30-second age limit and single use. Repository rejects inactive/unassigned employees, duplicate events, another open shift, missing checkout session and invalid durations. Checkout locates the original open workday for overnight shifts; rows remain pending approval.
- **Clock guard:** encrypted wall/monotonic/boot anchor. Missing anchor, changed boot, reversed elapsed time or a wall-clock discrepancy over two minutes blocks automatic recognition. An owner must explicitly check and confirm device time to establish/reestablish the baseline. This detects changes after a trusted baseline; it cannot establish correct civil time without trusted provisioning.

## Protected local SQLite storage

`AndroidSqliteFaceVaultStore` implements the existing value-store abstraction with native `FaceVaultChannel`:

```text
context.noBackupFilesDir/face_vault/
  tenant_binding               # nonsecret SHA-256 tenant binding, no face material
  biometric_v1.sqlite          # dedicated schema version 1

vault_records(record_key TEXT PRIMARY KEY, iv BLOB, ciphertext BLOB)
```

- AES-256-GCM, platform-generated IV on each write, 128-bit tag, record-key/schema associated data. Scope hashes are opaque lookup keys; they are not claimed to anonymize identifiers. The full consent/enrollment/template payload is encrypted.
- A non-exportable `AndroidKeyStore` key is generated on the device. No encryption key is stored in Dart, source code or SQLite. On the attached Pixel 6a (Android 17 / API 37), Android `KeyInfo` reported `insideSecureHardware: true` and `securityLevel: 1`. Signed key attestation was not performed; this is a device-reported property, not a certification.
- Maximum native payload is 256 KiB. No image storage endpoint exists. SQLite journals contain ciphertext; `secure_delete` is enabled. Logical deletion is not a claim of physical flash erasure.
- Native compare-and-swap runs in a SQLite transaction, preventing competing callers from silently overwriting an enrollment. Normal enrollment refuses duplicates; replacement requires the explicit administrator flow.
- One tenant provisions a device vault; that tenant's businesses/outlets remain separately scoped. A different tenant cannot open or reset it. Reprovisioning to another tenant requires a separately managed installation/profile; ordinary logout does not rebind it.
- Operational retention is 90 days, subject to organizational/legal review before activation. Expired records are rejected on reads and purged on vault opening; no claim is made that an idle device runs a background deletion job. Revocation markers contain no vectors and also expire.
- Unreadable records/key loss fail closed. The owning tenant's owner can explicitly reset the current vault, destroy its key and re-enroll with renewed consent. Tenant binding is retained across reset. Legacy preference templates are withdrawn separately by scoped employee ID; they are not silently migrated or globally erased.
- The no-backup directory is excluded by Android's backup mechanism. Existing legacy preference backup/transfer exclusions remain. Native methods do not log exceptions or values; templates are absent from reports, general document tables and outbox messages. Managed-memory copies and a compromised/rooted process remain threat-model limitations.

Android documents [non-exportable Keystore keys](https://developer.android.com/privacy-and-security/keystore) and [Auto Backup exclusions](https://developer.android.com/identity/data/autobackup). The protected file location and native encryption/reopening were verified using synthetic records on the Pixel; full cloud-backup/device-transfer restore testing remains not run.

## Dependencies and model decision

- `camera` **0.12.1**, endorsed Android CameraX **0.7.5+1**; Android API 24+ per the [camera package](https://pub.dev/packages/camera).
- `google_mlkit_face_detection` **0.15.1**, `google_mlkit_commons` **0.13.0**. Inspected installed Android dependencies use bundled `com.google.mlkit:face-detection:16.1.7`; no first-run model download is required by this selected detector dependency. Device offline behavior remains to be tested.
- ML Kit detects faces and features, [not employee identity](https://developers.google.com/ml-kit/vision/face-detection). Its [privacy terms](https://developers.google.com/ml-kit/terms) state input/output processing stays on the device while performance/usage metrics may be sent. The consent screen discloses that distinction. This app does not upload images or embeddings.
- TFLite was evaluated as a runtime candidate, **not installed**, because no exact weight artifact/preprocessing contract is approved. Its runtime license does not establish model rights. The recognition/liveness validation report records candidate decisions and licensing references.
- No Firebase Storage, `cloud_firestore`, `firebase_database`, paid service or biometric cloud collection was added.

## Validation and evidence

- Automated synthetic/disposable suite: **122 tests passed**, including existing salary, manual attendance, SQLite upgrade, synchronization and financial report regressions. Evidence: `docs/face_attendance/automated_tests.jsonl`.
- Android arm64 debug APK builds. Evidence: `docs/face_attendance/android_build.log`; artifact: `build/app/outputs/flutter-apk/app-debug.apk`. The regular billing APK has not been installed or deployed by this work. A separately named synthetic fixture app was installed for native storage testing and then uninstalled.
- Full-project analysis has pre-existing errors in the OCR subpackage and two stale sales UI test overrides. Changed-file analysis passes with zero diagnostics. Full analysis reports 731 diagnostics: 527 errors, 27 warnings and 177 infos; all 527 errors remain in the previously failing areas.
- The separate REST emulator smoke test **passed (1 test)** using synthetic verification adapters, loopback-only hosts, a `demo-` project, temporary SQLite and restrictive temporary rules. It verified both attendance events, pending daily attendance, acknowledged outbox batches and cross-owner read denial. It is not evidence of production server authorization or biometric recognition. Reproducible test-only emulator fixtures are included under `docs/face_attendance/emulator`.
- A Pixel 6a became available during final validation. **23 physical native storage checks passed**, plus independent inspection of seven encrypted SQLite records. Camera capture, real recognition, PAD, full backup/restore and performance measurements remain **NOT RUN / BLOCKED**. See `FACE_ATTENDANCE_ANDROID_DEVICE_TEST_REPORT.md`.

## Changed source and tests

| Files | Purpose |
|---|---|
| `pubspec.yaml`, `pubspec.lock` | Pinned camera/ML Kit dependencies; generated plugin registration follows these dependencies. |
| `android/app/build.gradle.kts`, `android/build.gradle.kts`, Android manifest | SDK/permission compatibility and Java/Kotlin target alignment. |
| `MainActivity.kt`, new `FaceVaultChannel.kt` | Native SQLite/Keystore, clock, tenant binding and capture privacy channel. Synthetic destructive test hooks require both a debug build and the isolated fixture package. |
| `face_biometric_vault.dart`, new `android_sqlite_face_vault_store.dart` | Existing lifecycle plus protected SQLite adapter. |
| New `offline_face_recognition.dart`, `face_capture_processor.dart` | Recognition/PAD interfaces, matcher, tickets and in-memory quality/alignment. |
| `staff_attendance_repository.dart`, `app_controller.dart`, new `face_attendance_controller.dart` | Existing attendance/permissions integration. |
| `staff_attendance_page.dart`, new `face_attendance_page.dart`, `face_capture_page.dart` | Navigation, consent, enrollment/revocation, preview and manual fallback. |
| New recognition, processor, channel and screen tests; extended vault/attendance/sales-posting tests | Synthetic control flow and disposable SQLite regression coverage. |
| `test/support/synthetic_face_verification.dart`, `tool/staff_salary_firestore_emulator_smoke.dart` | Explicit test-only model/PAD fixtures; emulator endpoint safety and REST validation. |
| `lib/face_attendance_device_fixture_main.dart`, Android fixture build guards | Standalone synthetic storage harness, separate application ID/label, no ordinary account database or camera capture. |

Paths above are relative to `lib/data/services`, `lib/data/repositories`, `lib/presentation/staff_salary` or the Android source directory as appropriate. No product catalogue releases, Billing/Sales/Inventory implementation, production SQLite database, live Firestore document, rules deployment, production sync cursor/outbox, salary transaction, commit or push was changed. Disposable test databases/outboxes and the separate synthetic device fixture were used for validation.

## Remaining activation decisions

1. Approve a specific model artifact and SHA-256, commercial redistribution/conversion/attribution terms and training-data provenance; integrate its actual inference adapter. Review cross-sample enrollment consistency and duplicate-identity enrollment policy using that model.
2. Measure false accept/reject behavior and ambiguity margins on consenting test identities and the actual Pixel 6a; install reviewed calibration. No accuracy percentage is currently available.
3. Select a commercially cleared PAD solution, adapt its required frame/session inputs, and validate print/screen/video attacks on that device. Without it, continue authorized manual attendance.
4. Complete privacy/legal, retention and shared-device provisioning review and obtain separate permission for real employee capture/enrollment and payroll use. Review server-side attendance authorization separately before any production synchronization activation; historical rules findings in the Phase 3 documents were not reverified or deployed in this task.
5. Obtain approved participant/camera test data and execute the remaining physical camera/recognition/PAD protocol. Native synthetic storage tests on the connected Pixel have passed. Review future PHP/MySQL biometric migration separately; no automatic upload is implemented.

Companion reports: `FACE_ATTENDANCE_RECOGNITION_LIVENESS_VALIDATION_REPORT.md`, `FACE_ATTENDANCE_ANDROID_DEVICE_TEST_REPORT.md`, `FACE_ATTENDANCE_PHP_MYSQL_MIGRATION_DESIGN.md`.

## Physical-test correction and fixture isolation

The first Pixel fixture run exposed vault initialization failure: row-returning SQLite PRAGMAs were invoked through `execSQL`. The implementation now consumes and verifies those results with `rawQuery`; the rerun and process-restart tests passed. The initial failure and subsequent successful JSON evidence are retained, rather than replacing the result with a mocked success.

The fixture target requires `--target lib/face_attendance_device_fixture_main.dart --dart-define=NUBIBILL_FACE_FIXTURE=true`. Gradle enforces that both are present together and assigns `com.example.testflutter.attendancefixture` / **NubiBill Storage Tests**. Native destructive test hooks require that package suffix and a debuggable application before accessing the vault. The default billing app cannot call them. The harness verifies its package before creating synthetic records, imports no account initialization or network client, and never opens a camera. Its app/data were uninstalled after collecting nonbiometric results.

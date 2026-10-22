# Android physical-device test report

Date: 2026-10-21. Device: **Google Pixel 6a, Android 17 / API 37**.

**Native synthetic storage: PASS. Real camera/recognition/PAD: NOT RUN.** The device was initially absent and became visible during final validation. A standalone fixture was installed under `com.example.testflutter.attendancefixture`, labeled **NubiBill Storage Tests**, and removed after testing. The regular billing application was not installed, launched or accessed by these tests. No real employee faces, embeddings, payroll records or production database were used.

## Host and emulator validation

| Test | Result |
|---|---|
| Pinned camera / bundled detector dependency resolution | PASS |
| Regular Android arm64 debug APK and separate fixture compilation | PASS |
| Changed-file Dart analysis, including standalone fixture | PASS — zero diagnostics |
| Synthetic biometric/widget/attendance/salary/SQLite/sync/financial regressions | PASS — 122 tests |
| Local Auth/Firestore REST synchronization | PASS — 1 additional disposable test, including cross-owner denial |
| Full-project analysis | FAIL — 527 pre-existing errors, 27 warnings, 177 infos; no repository-wide pass claimed |

Regular build: `flutter build apk --debug --target-platform android-arm64 --no-pub`.

Fixture build: `flutter build apk --debug --target-platform android-arm64 --no-pub --target lib/face_attendance_device_fixture_main.dart --dart-define=NUBIBILL_FACE_FIXTURE=true`.

Gradle requires the fixture target/flag together and assigns a separate application ID. Native destructive fixture operations require both that ID suffix and a debuggable installation, before accessing a vault. The harness additionally checks its package before creating synthetic records. It has no normal account initialization, network client, payroll logic or camera capture.

## Physical native checks — 23 passed

| Before process restart: 10 checks | Result |
|---|---|
| Missing clock baseline requires owner confirmation; confirmed baseline accepted | PASS — 2 |
| Consent required; five synthetic vectors round-trip; duplicate enrollment refused | PASS — 3 |
| Compare-and-swap create, stale-value rejection, update and persistence | PASS — 4 |
| Another tenant cannot open the device vault | PASS — 1 |

The fixture was stopped with `am force-stop` and cold-started to test actual process persistence.

| After process restart: 13 checks | Result |
|---|---|
| Encrypted value, device identity, enrollment and clock anchor survive restart | PASS — 4 |
| Withdrawal removes templates; native opening purges expired encrypted enrollment | PASS — 2 |
| Ciphertext tampering and copying ciphertext/IV to another record are rejected | PASS — 2 |
| Lost key prevents reads and new writes; no silent replacement over existing ciphertext | PASS — 2 |
| Explicit reset recovers the vault; old enrollment absent; synthetic re-enrollment succeeds | PASS — 3 |

Evidence: `docs/face_attendance/pixel6a_phase1.json`, `pixel6a_phase2.json`.

## At-rest inspection and key properties

- Extracted **only the isolated fixture's synthetic SQLite file** from `no_backup/face_vault/biometric_v1.sqlite`; no billing database was accessed.
- Independently opened the extracted file read-only on the host: schema version 1, seven records, BLOB IV/ciphertext columns, 12-byte IVs and all seven IVs distinct.
- The known synthetic sentinel, employee ID, model version and serialized template field were absent in the SQLite file's plaintext bytes. This supports the tested implementation; it is not a claim of formal cryptographic analysis or physical flash erasure.
- Android `KeyInfo` reported `insideSecureHardware=true`, `securityLevel=1`. These are local device-reported key properties. No signed key attestation or biometric security certification was performed. See [Android KeyInfo](https://developer.android.com/reference/android/security/keystore/KeyInfo).
- Evidence: `pixel6a_sqlite_inspection.json`. The source's no-backup location and existing backup exclusions were inspected; complete backup/restore/device-transfer testing was not performed.

## Failure found and corrected

The first physical run failed during vault initialization, before enrollment. The native implementation used `execSQL` for row-returning PRAGMAs. It now uses `rawQuery` and checks that `secure_delete=1` and journal mode `delete` actually take effect. The rebuilt fixture then passed both phases. `pixel6a_initial_failure.json` is retained alongside the passing results.

## Not run / blocked

| Area | Remaining checks / reason |
|---|---|
| Camera permission, live preview and lifecycle on hardware | Camera capture was not opened. Runtime permission state was recorded, but real grant/denial, preview, rotation, pause/resume and screenshot behavior were not exercised. Mock failure-path tests pass. |
| Face sample quality on Pixel | No real participant capture; NV21 layout, pose guidance, lighting/blur/occlusion and alignment require approved camera test data. |
| On-device recognition and measured FAR/FRR | No commercially reviewed embedding weights or installed device calibration. Synthetic matching tests do not establish accuracy. |
| Print, display and video replay attacks | No approved PAD model/session adapter or authorized participant protocol. |
| Full backup/device-transfer restore | Not performed; fixture uses the platform's no-backup directory. |
| Clock changes across actual reboot and changed wall time | Owner-confirmation and process-restart behavior tested; reboot/time-setting manipulations were not performed on the user's device. |
| Full delegated staff/outlet permission matrix and production server rules | Host/emulator tests cover narrower cases; no production policy was queried or deployed. |
| Real payroll activation | Not authorized and not enabled; all production recognition remains disabled. |

## Cleanup and remaining protocol

Fixture uninstallation succeeded (`pixel6a_fixture_cleanup.log`). Only its own synthetic test data/key lifecycle was exercised. Nonbiometric result JSON and build/test logs remain in the workspace. The generated regular APK is not a production biometric release and must not be installed over a working employee app for further tests.

Before real camera/enrollment testing, obtain separate approval for consenting adult participants and privacy/retention/device provisioning. Use an isolated installation/profile, integrate an exact commercially reviewed model, validate preprocessing and calibration, and select/test the actual PAD adapter. Record genuine/impostor/attack denominators, confidence intervals, failure cases and latency. Do not enable attendance by changing an unavailable result to success.

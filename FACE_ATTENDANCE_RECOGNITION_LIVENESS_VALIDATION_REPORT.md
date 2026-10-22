# Recognition and liveness validation

Date: 2026-10-21. Status: **synthetic control flow verified; real recognition and PAD NOT VERIFIED**.

## Model and license review

| Candidate | Primary evidence | Decision |
|---|---|---|
| ML Kit face detection | [Google documentation](https://developers.google.com/ml-kit/vision/face-detection) describes detection/features, not identity recognition. Installed Android plugin uses the bundled detection dependency. | Adopted for detection/quality only. Never used as employee recognition or PAD. |
| `tflite_flutter` 0.12.1 | [TensorFlow package](https://pub.dev/packages/tflite_flutter) supplies an interpreter and documents Android API 26 minimum for its current setup. | Runtime candidate only; not added without approved weights. A future integration may need a further minimum-SDK change from the present camera API 24 baseline. |
| InsightFace pretrained recognition packages | [Maintainer license statement](https://github.com/deepinsight/insightface#license) distinguishes MIT code from research-only training data/models and directs commercial recognition users to licensing contacts. | No bundled weights. A runtime/source license is insufficient. No licensing request was sent. |
| OpenCV SFace/MobileFaceNet | [OpenCV model README](https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface) states that directory files are Apache-2.0 and identifies MobileFaceNet/SFace instances. [Upstream SFace](https://github.com/zhongyy/SFace) reports experiments on CASIA-WebFace, VGGFace2 and MS-Celeb-1M. | Potential lightweight candidate. Exact selected checkpoint's training provenance, redistribution/conversion review, required notices and preprocessing equivalence remain unresolved. No claim is made that OpenCV forbids commercial use; this review did not establish all requested provenance requirements. No artifact downloaded, hashed, converted or installed. |
| MiniFASNet / Silent-Face-Anti-Spoofing | [Maintainer repository](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing) presents an Apache-2.0 project; its [English README](https://github.com/minivision-ai/Silent-Face-Anti-Spoofing/blob/master/README_EN.md) describes camera/scene dependence and multiscale inputs. | PAD candidate only. Exact weights/data and component rights need review; its full-frame/multiscale capture requirements need an actual adapter. No Pixel 6a attack evaluation, so no production liveness result is issued. |

The absence of a selected weight artifact is deliberate. There is no placeholder embedding generator in `lib`, model download service, fabricated nearest employee, inferred zero confidence or recognition success screen. Synthetic matching adapters are isolated in `test/support`; only tests and the opt-in disposable emulator runner import them. The separate, build-gated device fixture uses labeled synthetic vectors to test storage only; the production controller never imports that entry point.

## Verification gates

1. Same model and preprocessing contract for enrollment and verification.
2. Valid finite, nonzero vectors; model dimension and profile retention/device checks.
3. Explicit model/device calibration, minimum cosine and second-candidate margin.
4. Unique accepted employee; unknown and ambiguous results do not produce a ticket.
5. Fresh capture within 30 seconds, trusted device-clock continuity and validated live PAD with an evaluation reference.
6. Single-use ticket bound to tenant/business/outlet/employee/device/model/PAD/time.
7. Attendance repository independently validates active assignment, session rules and pending-only attendance creation.

The production controller installs no model or calibration and uses unavailable PAD. These gates therefore reject actual biometric attendance. Version text alone is no longer sufficient. The supported fallback is manager-recorded manual attendance; no face match is mislabeled as manual approval.

## Test outcomes

| Check | Result | Evidence limits |
|---|---|---|
| Consent required, bounded samples, normalized vectors, model mismatch, revocation, renewal, retention and corrupt record handling | PASS | Synthetic in-memory store; not native encryption proof. |
| Unique/unknown/ambiguous matches; malformed/expired/wrong-device profiles | PASS | Synthetic vectors and explicitly fictional thresholds only. |
| Absent/rejected PAD, missing calibration, wrong preprocessing and suspect clock | PASS | Injected decisions; not spoof-resistance measurements. |
| Ticket scope, age, capture time and one-use constraints | PASS | Unit control flow. |
| Frame orientation, malformed layouts, multiple-face/missing-landmark rejection, lighting and blur heuristics | PASS | Synthetic frames and mocked detector responses. Real camera quality remains unmeasured. |
| Consent UI and disabled recognition/enrollment; attendance permission guard | PASS | Flutter widget fixtures. |
| Manual attendance, overnight checkout, duplicate protection, inactive staff, pending approval and SQLite/outbox persistence | PASS | Disposable SQLite or repository fixtures. |
| Existing salary, synchronization, financial report regressions | PASS | Included in the 122-test final automated suite. |
| Camera permission denial and missing protected preview | PASS | Mock platform channels; not physical permission/lifecycle evidence. |
| Authenticated REST attendance/salary synchronization and cross-owner denial | PASS | One separate loopback emulator test with disposable records and synthetic verification; not production rules validation. |
| Native encrypted storage, process restart, revocation/expiry, tamper/AAD rejection and key-loss recovery | PASS | 23 physical checks using synthetic records on the Pixel 6a, plus encrypted-file inspection; no real face enrollment. |
| Full backup/device-transfer restore and signed hardware attestation | NOT RUN | No-backup file location and reported hardware key properties observed; complete restore/attestation not established. |
| Matching FAR/FRR and PAD print/video/screen attack evaluation | BLOCKED | No approved model, PAD adapter, participant approval or approved real camera/participant test data. |
| Full production permission/outlet/server authorization matrix | NOT RUN | Production rules were neither queried nor deployed. Local and emulator coverage is narrower. |

Evidence: `docs/face_attendance/automated_tests.jsonl`, `targeted_analyze.log`, `full_analyze.log`, `android_build.log`, `rest_emulator.log`, `pixel6a_phase1.json`, `pixel6a_phase2.json`, `pixel6a_sqlite_inspection.json`. Final logs are authoritative for exact command outcomes. Changed-file analysis is clean (zero diagnostics). Full analysis remains unsuccessful: 731 diagnostics, including 527 pre-existing errors, 27 warnings and 177 infos. The errors are in the OCR subpackage and stale sales test overrides; it is not represented as a passing full-project check.

## Measurements required before activation

- Use explicitly consenting adult test identities and an isolated installation. Keep enrollment and evaluation sessions distinct; test multiple days, glasses/lighting/pose variation and unknown identities. Do not mix synthetic cases into measured recognition rates.
- Record genuine attempts, false rejects, impostor attempts and false accepts, including confidence intervals and selection protocol. FAR = accepted impostor attempts / impostor attempts; FRR = rejected genuine attempts / genuine attempts. Report ambiguous/unavailable outcomes separately. Set thresholds on calibration data and evaluate once on held-out data.
- Evaluate the selected PAD on printed photographs, phone/tablet displays, replayed videos and other relevant media using the actual Pixel 6a camera. Record attack and bona-fide trial counts, attack acceptance, bona-fide rejection and processing latency, stratified by medium and lighting.
- Establish enrollment consistency/duplicate-identity controls, quality thresholds, calibrated sample counts, model input normalization and low-end device performance before approving real enrollment. The five pose prompts alone do not ensure a single identity across samples.
- [NIST's PAD evaluation](https://pages.nist.gov/frvt/html/frvt_pad.html) evaluates different software algorithms and attack types; its results do not certify this application. Blink/head-motion prompts are not accepted as a substitute for validated PAD.

**Measured FAR: unavailable. Measured FRR: unavailable. Measured PAD error rates: unavailable. Pixel 6a inference latency: unavailable. No biometric accuracy or certification claim is made.**

The attached Pixel reported Android 17 / API 37 and hardware-backed Keystore storage (`insideSecureHardware=true`, `securityLevel=1`). This verifies storage behavior for synthetic records only. It does not establish face recognition, presentation-attack resistance or a signed attestation. The isolated fixture was uninstalled after testing.

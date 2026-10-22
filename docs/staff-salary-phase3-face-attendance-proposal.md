# Staff Salary Khata Phase 3: Face Attendance Proposal

**State:** Architecture reviewed; biometric enrollment and recognition remain
disabled. This document does not add a camera plugin, collect face data, alter
database schemas, write Firestore data, or deploy rules.

## Existing architecture findings

- Phase 2 attendance is handled by
  `StaffAttendanceRepository` and the existing `staff_attendance` document
  cache. `OfflineFirestoreService` stores local changes in the existing SQLite
  document store and durable sync outbox; Firestore communication uses the
  authenticated REST service.
- Attendance rows already have stable employee/business/outlet/day identities,
  pending and approval states, check-in/check-out timestamps, worked minutes,
  approver metadata, and approved wage units. Phase 3 should submit attendance
  evidence through this repository path and preserve its approval and salary
  snapshot rules.
- There is no camera, face embedding/matching, liveness, biometric enrollment,
  or biometric key-management package in `pubspec.yaml` or production Dart
  sources. Android has a manifest but no attendance camera flow or app camera
  permission declaration. The current app's secure-storage dependency is used
  for tokens; it is not by itself a biometric-template vault.
- The Android target currently inherits Flutter's `minSdk` value and has no
  declared camera feature or biometric-specific permission key. Device
  compatibility cannot be declared until an Android model/runtime and camera
  pipeline are selected.
- The existing client requires an authenticated operator context for local
  writes and outbox events. Offline kiosk operation must use an authorized
  shop-device account and must not assume that every employee has an app login.
- The last Firestore rules audit found unauthenticated public read/write rules.
  Client-side checks cannot make biometric or attendance writes safe while that
  server policy remains. No biometric feature can be enabled against those
  rules.

## Proposed experience

1. An authorized owner/admin provisions a shared Android kiosk for one business
   and outlet using the existing account and permission model.
2. Staff see a concise privacy notice and can use face attendance only after
   separately recorded, revocable consent and enrollment. Declining, failing a
   match, camera denial, unsupported device, or unavailable local model routes
   to Phase 2 manual attendance; there is no penalty or forced face retry.
3. The device captures a live camera stream, detects a single face, runs the
   separately validated on-device matcher and an independently evaluated
   liveness check, then identifies an existing employee ID. Detection alone is
   not identity recognition. A match or liveness failure never silently marks
   attendance.
4. A successful check-in/out creates or updates a pending Phase 2 attendance
   record using the employee ID, kiosk business/outlet, capture time, and
   method metadata. Existing approval controls, salary calculation, and
   duplicate attendance identity remain authoritative.
5. A pending event is committed locally together with its existing REST sync
   outbox operation. Once online, only the attendance record is sent through
   authenticated Firestore REST. Face images and templates are not synced.

## Biometric storage and safety proposal (requires review)

- Store recognition templates only on the enrolled kiosk, encrypted with a
  device-protected key. Do not store raw face images. Do not put templates,
  embeddings, liveness frames, or consent artefacts in Firestore or the
  ordinary document/outbox tables.
- Template creation, replacement, access, revocation, and deletion need a
  versioned local vault with documented backup/restore and device-loss
  behavior. Losing the kiosk key must invalidate and require re-enrollment; it
  must not fall back to plaintext or cloud backup.
- Use an independently selected and validated recognition model. Google ML
  Kit Face Detection locates and analyzes faces but does not identify people;
  ML Kit face tracking is not face recognition. See [Google ML Kit Face
  Detection](https://developers.google.com/ml-kit/vision/face-detection) and
  [face detection concepts](https://developers.google.com/ml-kit/vision/face-detection/face-detection-concepts).
- Liveness needs a separately validated anti-spoof method. Eye-open/blink or
  head-turn signals from a detector may provide a challenge, but do not by
  themselves establish liveness or prove identity. Keep manual attendance
  available if the liveness check is inconclusive.
- Before enrollment/matching is enabled, complete privacy and applicable legal
  review, consent/retention policy, device threat model, model/license review,
  demographic accuracy and false-match testing, liveness attack testing,
  accessibility review, and authorization-rule replacement with emulator
  tests. Obtain a separate product/security approval for the chosen model and
  encrypted vault.

## Proposed record mapping (no schema change made)

Continue using `staff_attendance` for attendance outcomes, optionally extending
the Phase 2 record with non-biometric metadata such as `captureMethod`
(`MANUAL` or `FACE_KIOSK`), `kioskDeviceId`, `recognitionModelVersion`, and
`livenessCheckVersion`. Do not store embeddings, images, raw camera frames,
biometric scores, or secrets in this document. A separate local-only biometric
vault and consent/revocation lifecycle require a reviewed design before any
table or record is added. Attendance document fields and matching server Rules
must be agreed before schema changes.

## Required verification before activation

- Android device capability checks, camera permission denial, camera loss,
  model load failure, no face, multiple faces, low confidence, offline check-in
  and check-out, and manual fallback.
- Repeated scans and simultaneous check-ins must not create duplicate daily
  records; check-out updates the same pending row. Approved attendance must
  require the existing correction/approval process.
- Template encryption at rest, no template in SQLite document tables/outbox,
  no template in logs/crash reports/backups, revocation/deletion, app restart,
  device loss, reinstall, and account/outlet switch behavior.
- Spoof tests with printed photos, screen replays, and video replays. Report
  false acceptance and false rejection by representative device and
  demographic test cohorts; do not describe the system as secure based only on
  detector landmarks or a successful demo.
- Outbox retry and restart tests using disposable SQLite plus an isolated
  Firestore emulator after Rules are corrected. Do not test against production.

## Model/runtime selection status

No production-grade provider is selected by this audit. A TensorFlow Lite
runtime can execute a supplied model on Android, but that alone provides no
recognition accuracy, liveness/PAD, demographic performance, template security,
model provenance, or license assurances. A generic face-embedding model plus
threshold comparison is not an acceptable production decision without those
evaluations. Google ML Kit can remain a face detector only. NIST biometric
guidance treats facial recognition and presentation-attack detection as
separate capabilities and recommends deployment-specific performance and PAD
testing; this is useful as a benchmark reference, not a claim of legal
applicability to employee attendance. See [NIST SP 800-63B]
(https://pages.nist.gov/800-63-4/sp800-63b/authenticators/) and the [NIST Face
Recognition Vendor Test](https://www.nist.gov/programs-projects/face-recognition-vendor-test-frvt).

Before implementation selects a runtime/model, require a supplier or model
package that documents offline inference, supported Android versions/devices,
embedding handling and deletion, commercial redistribution rights, PAD
performance by attack type, and independent demographic accuracy results.
Then evaluate it on disposable test devices with consented participants. Do
not put face photos or test embeddings into fixtures, source control, logs, or
the normal application database.

## Current activation blockers

1. Deployed Firestore Rules are public read/write and must be replaced and
   separately approved before any production attendance sync.
2. No face-recognition model or liveness provider has been selected or
   independently validated for shared Android hardware.
3. Applicable privacy/legal review, consent wording, retention/deletion policy,
   and threat model have not been completed in this workspace.
4. No encrypted local biometric vault or kiosk provisioning/lifecycle exists.

Accordingly, Phase 3 is currently an architecture proposal only. Existing
manual attendance remains the supported workflow. No biometric data was
collected or processed, and no production database or Firestore configuration
was changed.

# Mobile Face Attendance with GPS Geofencing and Anti-Fraud Security Report

**Project**: NubiBillingSoftware-main
**Platform**: Flutter Android (Tested on Google Pixel 6a)
**Date**: October 22, 2026
**Status**: Feature Complete & Unit Verified Prototype (Payroll Auto-Approval Disabled)

---

## 1. Executive Summary & Objective

The objective of this project is to allow retail and shop employees to mark attendance using their existing Android mobile devices—without requiring owners to purchase expensive biometric wall kiosks or subscribe to costly cloud facial recognition APIs.

The implementation delivers:
1. **Offline GPS Geofencing**: Validates employee presence within a configurable radius (default 100m) of the shop/outlet using on-device GPS, checking for freshness (<120s), high accuracy (<=50m), and mock location injection.
2. **On-Device OpenCV SFace Face Recognition**: Uses the authentic 128-D OpenCV SFace ONNX model executed via Android ONNX Runtime 1.18.0 with calibrated cosine similarity thresholds (0.363 match, 0.05 margin).
3. **Randomized Active Liveness Challenges**: Prompts employees with randomized active micro-gestures ("Blink eyes", "Turn head left", "Turn head right") with a strict 7-second countdown per challenge.
4. **Android Keystore Hardware Device Binding**: Supports binding attendance to owner-approved employee devices with Android Keystore hardware protection.
5. **Manager Review & Salary Khata Protection**: Suspicious, out-of-geofence, or low-confidence attendance events are automatically flagged (`FLAGGED_FOR_REVIEW`) and require manager review. Unattended automatic payroll approval remains disabled (`approvalStatus = 'PENDING'`).
6. **Strict Biometric Privacy**: Biometric templates and photos remain 100% offline, encrypted in a local SQLite vault with Android Keystore AES-256 GCM. No face photos or embeddings are ever uploaded to Firestore.

---

## 2. Architecture & Component Diagram

```
+-----------------------------------------------------------------------------------+
|                           Android Mobile Phone (Pixel 6a)                         |
+-----------------------------------------------------------------------------------+
|  1. GPS Location Channel (nubibill/location)                                      |
|     - Android FusedLocationProvider / LocationManager                             |
|     - Mock Location Detection (API 31+ isMock / isFromMockProvider)               |
|     - Freshness & Accuracy Guard (<120s, <=50m)                                   |
+-----------------------------------------------------------------------------------+
|  2. Live Camera & Google ML Kit                                                   |
|     - Front-facing camera feed                                                    |
|     - Face Detection & Landmarks (Eyes, Nose, Mouth)                              |
|     - Head Euler Angles (Yaw, Pitch, Roll)                                        |
|     - Eye Open Probabilities (Left & Right classification)                        |
+-----------------------------------------------------------------------------------+
|  3. Randomized Liveness Challenge Engine (FaceLivenessService)                    |
|     - Random challenge sequence (Blink state machine, Turn Left >16°, Right <-16°) |
|     - 7-second timeout per challenge                                              |
|     - Explicit anti-spoofing security disclaimer                                  |
+-----------------------------------------------------------------------------------+
|  4. On-Device SFace Embeddings & Matcher (FaceRecognitionService)                 |
|     - opencv-sface-2021dec (128-D ONNX, SHA256 verified)                          |
|     - Native ONNX Runtime C++ / JNI execution                                     |
|     - Cosine Similarity >= 0.363, Ambiguity Margin >= 0.05                        |
+-----------------------------------------------------------------------------------+
|  5. Android Keystore Encrypted Local Vault (FaceVaultStore)                       |
|     - AES-256 GCM hardware-backed keystore encryption                             |
|     - SQLite encrypted BLOB storage (templates, enrollment photo)                 |
|     - Outlet geofence configurations & device bindings                            |
+-----------------------------------------------------------------------------------+
|  6. Offline SQLite Attendance & Durable Sync Outbox                               |
|     - staffAttendance (local_staff_attendance)                                    |
|     - staffAttendanceEvents (local_staff_attendance_events)                       |
|     - Flags: OUTSIDE_GEOFENCE, MOCK_LOCATION, LOW_ACCURACY, LIVENESS_FAILED, etc.  |
|     - Review Status: VERIFIED vs FLAGGED_FOR_REVIEW (Requires Manager Review)     |
+-----------------------------------------------------------------------------------+
```

---

## 3. Detailed Security & Fraud Mitigation Evaluation

### 3.1 GPS Geofencing & Location Spoofing Resistance
* **On-Demand Capture Only**: Location is requested solely when the employee taps Check-In or Check-Out. Background location tracking is strictly forbidden to preserve employee privacy and battery life.
* **Accuracy Threshold**: GPS accuracy must be within 50.0 meters. Readouts with accuracy > 50m (common in indoor signal drift) are flagged with `LOW_GPS_ACCURACY` and routed to manager review.
* **Freshness Check**: Location age must be within 120 seconds. Cached or replayed location signals older than 2 minutes are rejected or flagged with `STALE_GPS_LOCATION`.
* **Mock Location Detection**: The Android native channel inspects `Location.isMock()` (on API 31+) and `Location.isFromMockProvider()` (legacy API). Fake GPS apps (e.g. Fake GPS Location, Mock Locations) are immediately flagged with `MOCK_LOCATION_DETECTED`.
* **Configurable Outlet Geofence**: Shop owners can define exact latitude/longitude and custom radius (default 100m) with a one-tap "Use Current Device GPS" tool.

### 3.2 Active Liveness Challenge Protection
* **Randomized Sequences**: The challenge order is unpredictable (`createRandom`), preventing attackers from preparing static gestures in advance.
* **Blink State Machine**: Validates a genuine 3-phase biological blink:
  1. Phase 1: Eyes verified open (`leftEyeOpenProbability > 0.65` and `rightEyeOpenProbability > 0.65`).
  2. Phase 2: Eyes verified closed (`< 0.25` on either eye).
  3. Phase 3: Eyes reopened (`> 0.65`).
* **Head Rotation Checks**: Validates genuine 3D spatial rotation (Yaw angle > 16.0° for Left, < -16.0° for Right).
* **Strict Timeouts**: Challenges must be completed within 7 seconds, preventing slow video transitions or photo swaps.
* **Security Disclaimer & Realism**: Simple micro-gestures reduce basic 2D printed photo attacks, but **do not guarantee protection against recorded video replay, deepfakes, or 3D silicone masks**. Therefore, attendance remains non-autonomous and subject to approval.

### 3.3 Hardware-Backed Device Registration
* **Device Identity**: Uses an Android Keystore hardware-derived unique fingerprint (`FaceVaultStore.deviceId()`).
* **Owner Approval**: Employee devices can be bound and explicitly approved by the shop owner/manager.
* **Device Mismatch Routing**: If an employee registers a device and later marks attendance from an unauthorized phone, the event is flagged with `UNREGISTERED_DEVICE_DETECTED` and routed to manager review.
* **Play Integrity Grounding**: Note that while Google Play Integrity provides hardware and binary tamper attestations, **it does not independently guarantee the physical veracity of satellite GPS signals**.

### 3.4 Biometric Privacy & Legal Compliance
* **Zero Cloud Biometrics**: No face photographs or numerical embeddings are ever uploaded to Firestore, Cloud Storage, or external AI APIs.
* **Encrypted Vault**: All biometric data is encrypted on-device with AES-256 GCM using keys stored in the Android Keystore.
* **Consent & Revocation**: Biometric enrollment requires explicit employee consent under policy `local-face-attendance-v1-90-days`. Enrollment photos and templates can be viewed, replaced, or revoked at any time by the owner or employee.
* **Equal Manual Attendance**: Employees who decline biometric enrollment can mark attendance using the existing manual attendance register without penalty.

---

## 4. Verification & Testing Evidence

All unit test suites covering the mobile face attendance, geofencing, and anti-fraud modules were executed with 100% pass rate:

| Test Suite | Test Focus | Result |
| :--- | :--- | :---: |
| `test/geofence_service_test.dart` | Haversine distance, inside vs outside geofence, stale GPS, mock location detection, low accuracy, missing geofence | **10 / 10 Passed** |
| `test/face_liveness_service_test.dart` | Turn left/right yaw thresholds, blink 3-phase state machine, session progression, timeout enforcement, randomization | **8 / 8 Passed** |
| `test/device_registration_service_test.dart` | Device binding, owner approval, device mismatch, revocation, Play Integrity disclaimer | **6 / 6 Passed** |
| `test/staff_attendance_repository_test.dart` | Atomic check-in/out, geofence audit attributes, fraud flags, manager review routing, salary khata idempotency | **8 / 8 Passed** |
| `test/face_attendance_page_test.dart` | Scoped employee visibility, geofence & anti-fraud UI controls, review dialog, permission gates | **2 / 2 Passed** |
| `test/face_biometric_vault_test.dart` | SQLite AES-256 GCM biometric vault persistence, revocation, time confirmation | **9 / 9 Passed** |
| `test/offline_face_recognition_test.dart` | OpenCV SFace 128-D cosine matcher, threshold 0.363 calibration, ambiguous candidate rejection | **7 / 7 Passed** |
| `test/face_capture_processor_test.dart` | ML Kit landmarks, head pose angles, classification eye open probabilities | **3 / 3 Passed** |
| **Total** | **Comprehensive Full Suite** | **53 / 53 Passed (100%)** |

---

## 5. What Works vs. What Remains Required Before Production Activation

### What Is Working & Operational:
- [x] Front camera live stream with real-time ML Kit face landmark and pose tracking.
- [x] OpenCV SFace 128-D ONNX local inference on Android (ONNX Runtime 1.18.0).
- [x] Photo enrollment with explicit consent, 5 sample embedding generation, and local encrypted SQLite BLOB storage.
- [x] On-demand Android GPS location acquisition with accuracy and freshness validation.
- [x] Mock GPS detection via native Android platform channel (`nubibill/location`).
- [x] Randomized liveness challenges with countdown timer and prompt UI.
- [x] Device binding with Android Keystore device fingerprint.
- [x] Geofence configuration dialog with one-click "Use Current GPS" button.
- [x] Manager Review Dialog in Face Attendance Page with override approval capabilities.
- [x] Idempotent SQLite attendance records linked with Salary Khata.

### What Remains Required Before Autonomous Production Activation:
1. **Certified Presentation Attack Detection (PAD)**:
   - Simple blinking and head turns are heuristic anti-spoofing filters, NOT certified ISO/IEC 30107-3 PAD.
   - For unattended, automated payroll check-in without manager oversight, a certified active PAD engine or 3D depth sensor is required.
2. **Device Time Baseline Enforcement**:
   - The shop owner must confirm the device time baseline upon first setup to ensure Android system clock tampering is detected.
3. **Field Calibration in Poor Lighting**:
   - Outlets with dim lighting or direct backlight should be tested to tune ML Kit landmark confidence and camera exposure.
4. **Permanent MySQL / PHP REST Backend**:
   - While local SQLite and authenticated Firestore sync are fully operational, future backend migration to MySQL + PHP REST API should preserve the exact schema attributes (`geofenceDistanceMeters`, `fraudFlags`, `verificationStatus`, `kioskDeviceId`).

---

## 6. Conclusion

The mobile face attendance system with GPS geofencing and anti-fraud protection is fully implemented, verified, and operational in prototype mode on Android Google Pixel 6a. It provides a robust, zero-hardware-cost, privacy-preserving biometric attendance solution for NubiBilling.

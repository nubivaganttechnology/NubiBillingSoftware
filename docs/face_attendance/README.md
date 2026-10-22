# Face attendance evidence

Synthetic test logs, static analysis and Android build evidence for the local-only face attendance implementation. No employee photographs, templates, production databases, tokens or payroll data belong in this directory.

See the implementation, recognition/liveness validation, Android physical-device and future PHP/MySQL design reports in the project root.

## Reproduce REST synchronization

The `emulator` directory contains restrictive **test-only** rules (owner scope, immutable events and default deny), not a production policy. Do not deploy them. Start local Auth and Firestore emulators with that configuration and project `demo-nubibill-face-attendance`. From the Flutter project root, run:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 flutter test test/staff_salary_firestore_emulator_test.dart --dart-define=FIREBASE_PROJECT_ID=demo-nubibill-face-attendance --dart-define=FIREBASE_API_KEY=disposable-emulator-key --reporter expanded
```

The runner rejects other project prefixes and non-loopback hosts and refuses unexpected remote endpoints. It creates disposable identities/documents and a temporary SQLite database. Its synthetic model/PAD adapters establish attendance/sync control flow only. Stop the emulators after testing; never substitute production hosts or credentials.

## Reproduce the physical synthetic storage test

`lib/face_attendance_device_fixture_main.dart` is a separate debug entry point. Build it with both `--target lib/face_attendance_device_fixture_main.dart` and `--dart-define=NUBIBILL_FACE_FIXTURE=true`. Gradle requires the pair and sets package `com.example.testflutter.attendancefixture`, label **NubiBill Storage Tests**. Verify that package in the APK before installation; never install a fixture over the regular billing application.

The harness does not initialize an account database, use employee records, open a camera or perform network operations. On the first run it writes synthetic templates/sentinels to its own protected vault and produces `files/face_fixture_report.json` with result `READY_FOR_PROCESS_RESTART`. Collect that report and inspect only its `no_backup/face_vault/biometric_v1.sqlite` if needed. Force-stop only the fixture and cold-start it; the second phase validates persistence, withdrawal, expiry, ciphertext/AAD tampering and key-loss/reset recovery. Collect the second report, then uninstall only the fixture package.

Native destructive test hooks require the fixture package suffix **and** a debuggable installation. They are refused in the regular billing application, including its debug build. Do not repurpose this synthetic test for real employee enrollment. The captured Pixel results contain nonbiometric pass/fail metadata only.

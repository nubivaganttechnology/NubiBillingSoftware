import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../tool/staff_salary_firestore_emulator_smoke.dart';

void main() {
  final enabled =
      Platform.environment['FIRESTORE_EMULATOR_HOST'] != null &&
      Platform.environment['FIREBASE_AUTH_EMULATOR_HOST'] != null;
  test(
    'salary profile and approved accrual synchronize via authenticated Firestore REST',
    runStaffSalaryFirestoreEmulatorSmoke,
    skip: enabled ? null : 'Requires explicitly configured local Firebase emulators.',
  );
}

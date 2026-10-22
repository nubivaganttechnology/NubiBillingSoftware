import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/employee_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/services/offline_face_recognition.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/presentation/app_controller.dart';
import 'package:testflutter/presentation/staff_salary/face_attendance_page.dart';

class _Controller implements AppController {
  _Controller({this.allowed = true});
  final bool allowed;
  @override
  AppContext? appContext = const AppContext(
    uid: 'OWNER',
    accountType: 'owner',
    ownerUid: 'TEN',
    businessId: 'BUS',
    outletId: 'OUT',
  );
  @override
  List<BusinessModel> businesses = [];
  @override
  OutletModel? get currentOutlet => null;
  @override
  bool canViewStaffAttendance() => allowed;
  @override
  bool canManageStaffAttendance() => allowed;
  @override
  bool canEnrollBiometricAttendance() => allowed;
  @override
  bool canRevokeBiometricAttendance() => allowed;
  @override
  OfflineFaceRecognition get faceRecognition => OfflineFaceRecognition.disabled;
  @override
  Future<List<EmployeeModel>> loadStaffKhataEmployees() async => const [
    EmployeeModel(
      employeeId: 'EMP',
      uid: '',
      ownerUid: 'TEN',
      name: 'Synthetic temporary worker',
      email: '',
      status: 'ACTIVE',
      businessIds: ['BUS'],
      outletIds: ['OUT'],
      roleIds: [],
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected fixture operation');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vault = MethodChannel('nubibill/face_vault');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          vault,
          (call) async => call.method == 'deviceId' ? 'SYNTHETIC-DEVICE' : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null);
  });
  testWidgets(
    'assigned staff and scope are visible; missing model blocks enrollment and attendance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: FaceAttendancePage(controller: _Controller())),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic temporary worker'), findsWidgets);
      expect(find.textContaining('Business: BUS'), findsOneWidget);
      expect(
        find.textContaining(
          'No face match can automatically record attendance',
        ),
        findsOneWidget,
      );
      final checkin = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check in'),
      );
      expect(checkin.onPressed, isNull);
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll face (5 samples)'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Camera and quality preview'),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        find.textContaining(
          'Manual attendance is equally available without penalty',
        ),
        findsOneWidget,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'attendance permission is required before showing staff or enrollment actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FaceAttendancePage(controller: _Controller(allowed: false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Attendance permission and a selected business/outlet',
        ),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

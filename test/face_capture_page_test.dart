import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/offline_face_recognition.dart';
import 'package:testflutter/presentation/staff_salary/face_capture_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const privacy = MethodChannel('nubibill/face_capture_privacy');
  const camera = MethodChannel('plugins.flutter.io/camera');
  const detector = MethodChannel('google_mlkit_face_detector');
  final privacyCalls = <String>[];
  final cameraCalls = <String>[];
  setUp(() {
    privacyCalls.clear();
    cameraCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(privacy, (call) async {
      privacyCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(detector, (_) async => null);
    messenger.setMockMethodCallHandler(camera, (call) async {
      cameraCalls.add(call.method);
      if (call.method == 'availableCameras') {
        return [
          {
            'name': 'SYNTHETIC-FRONT',
            'lensFacing': 'front',
            'sensorOrientation': 270,
          },
        ];
      }
      if (call.method == 'create') {
        throw PlatformException(
          code: 'CameraAccessDenied',
          message: 'synthetic permission denial',
        );
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [privacy, camera, detector]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  testWidgets(
    'permission denial leaves capture disabled and closes preview privacy on exit',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FaceCapturePage(
            recognition: OfflineFaceRecognition.disabled,
            enrollment: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final open = find.text('Open camera');
      await tester.scrollUntilVisible(
        open,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Camera permission was denied'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Capture suitable sample'),
            )
            .onPressed,
        isNull,
      );
      expect(cameraCalls, containsAllInOrder(['availableCameras', 'create']));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(privacyCalls, ['open', 'close']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('missing protected preview prevents any camera access', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          privacy,
          (_) async => throw PlatformException(code: 'UNAVAILABLE'),
        );
    await tester.pumpWidget(
      const MaterialApp(
        home: FaceCapturePage(
          recognition: OfflineFaceRecognition.disabled,
          enrollment: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final open = find.text('Open camera');
    await tester.scrollUntilVisible(
      open,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Protected Android camera preview is unavailable'),
      findsOneWidget,
    );
    expect(cameraCalls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

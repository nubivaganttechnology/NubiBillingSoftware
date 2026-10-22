
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/face_capture_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('google_mlkit_face_detector');
  var faces = <Map<String, Object?>>[];
  final face = <String, Object?>{
    'rect': {'left': 100.0, 'top': 100.0, 'right': 300.0, 'bottom': 320.0},
    'landmarks': <String, Object?>{},
    'headEulerAngleX': 0.0,
    'headEulerAngleY': 0.0,
    'headEulerAngleZ': 0.0,
  };
  setUp(() {
    faces = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'vision#closeFaceDetector' ? null : faces,
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('inverse upright coordinates cover all four sensor rotations', () {
    expect(
      FaceCaptureProcessor.rawPoint(12, 20, 640, 480, 0),
      const Offset(12, 20),
    );
    expect(
      FaceCaptureProcessor.rawPoint(12, 20, 640, 480, 90),
      const Offset(20, 467),
    );
    expect(
      FaceCaptureProcessor.rawPoint(12, 20, 640, 480, 180),
      const Offset(627, 459),
    );
    expect(
      FaceCaptureProcessor.rawPoint(12, 20, 640, 480, 270),
      const Offset(619, 12),
    );
  });
  test(
    'quality heuristics reject darkness, glare, blur and malformed crops',
    () {
      expect(
        FaceCaptureProcessor.qualityIssue(Uint8List(12 * 12 * 3), 12),
        contains('lighting'),
      );
      expect(
        FaceCaptureProcessor.qualityIssue(
          Uint8List.fromList(List.filled(432, 255)),
          12,
        ),
        contains('lighting'),
      );
      expect(
        FaceCaptureProcessor.qualityIssue(
          Uint8List.fromList(List.filled(432, 128)),
          12,
        ),
        contains('blurred'),
      );
      expect(
        FaceCaptureProcessor.qualityIssue(Uint8List(2), 12),
        contains('Invalid'),
      );
      final textured = Uint8List.fromList(
        List.generate(432, (i) => ((i ~/ 3) + (i ~/ 36)).isEven ? 100 : 160),
      );
      expect(FaceCaptureProcessor.qualityIssue(textured, 12), isNull);
    },
  );
  test('malformed frames, no face, multiple faces and obscured landmarks are rejected', () async {
    final processor = FaceCaptureProcessor();
    expect((await processor.assess(Uint8List(2), 640, 480, 0)).sample, isNull);
    final frame = Uint8List(640 * 480 * 3 ~/ 2);
    expect(
      (await processor.assess(frame, 640, 480, 0)).message,
      contains('Position one'),
    );
    faces = [face, face];
    expect(
      (await processor.assess(frame, 640, 480, 0)).message,
      contains('Only one'),
    );
    faces = [face];
    expect((await processor.assess(frame, 640, 480, 0)).sample, isNull);
    await processor.close();
  });
}

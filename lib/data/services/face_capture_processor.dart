import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'offline_face_recognition.dart';

class FaceCaptureAssessment {
  const FaceCaptureAssessment(
    this.message, {
    this.sample,
    this.yaw = 0,
    this.pitch = 0,
    this.roll = 0,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.faceDetected = false,
  });
  final String message;
  final AlignedFaceSample? sample;
  final double yaw;
  final double pitch;
  final double roll;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final bool faceDetected;
}

/// In-memory NV21 -> upright face -> eye-aligned RGB. The camera preview alone
/// is mirrored; detector input, landmarks and model tensors are not mirrored.
/// Heuristic quality thresholds require device evaluation; they are not PAD.
class FaceCaptureProcessor {
  FaceCaptureProcessor()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.08,
        ),
      );
  final FaceDetector _detector;
  static const edge = 112;
  static const preprocessingVersion = 'nv21-upright-eye-similarity-rgb112-v1';

  Future<FaceCaptureAssessment> assess(
    Uint8List nv21,
    int width,
    int height,
    int rotation,
  ) async {
    final capturedAt = DateTime.now().toUtc();
    if (width.isOdd ||
        height.isOdd ||
        nv21.length != width * height * 3 ~/ 2 ||
        !{0, 90, 180, 270}.contains(rotation)) {
      return const FaceCaptureAssessment(
        'Unsupported camera frame. Use manual attendance.',
      );
    }
    final faces = await _detector.processImage(
      InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(rotation)!,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      ),
    );
    if (faces.length != 1) {
      return FaceCaptureAssessment(
        faces.isEmpty
            ? 'Position one face inside the frame.'
            : 'Only one person may be in the frame.',
      );
    }
    final face = faces.single;
    final uprightWidth = rotation % 180 == 0 ? width : height;
    final uprightHeight = rotation % 180 == 0 ? height : width;
    final box = face.boundingBox;
    if (box.width < 100 ||
        box.height < 100 ||
        box.left < 2 ||
        box.top < 2 ||
        box.right > uprightWidth - 2 ||
        box.bottom > uprightHeight - 2 ||
        (box.center.dx / uprightWidth - 0.5).abs() > 0.22 ||
        (box.center.dy / uprightHeight - 0.5).abs() > 0.25) {
      return const FaceCaptureAssessment(
        'Move closer and center your whole face.',
      );
    }
    final left = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final right = face.landmarks[FaceLandmarkType.rightEye]?.position;
    final nose = face.landmarks[FaceLandmarkType.noseBase]?.position;
    final mouth = face.landmarks[FaceLandmarkType.bottomMouth]?.position;
    if (left == null ||
        right == null ||
        nose == null ||
        mouth == null ||
        face.headEulerAngleY == null ||
        face.headEulerAngleX == null ||
        face.headEulerAngleZ == null ||
        face.headEulerAngleY!.abs() > 25 ||
        face.headEulerAngleX!.abs() > 20 ||
        face.headEulerAngleZ!.abs() > 15) {
      return FaceCaptureAssessment(
        'Keep eyes, nose and mouth visible; hold your head upright.',
        yaw: face.headEulerAngleY ?? 0.0,
        pitch: face.headEulerAngleX ?? 0.0,
        roll: face.headEulerAngleZ ?? 0.0,
        leftEyeOpenProbability: face.leftEyeOpenProbability,
        rightEyeOpenProbability: face.rightEyeOpenProbability,
        faceDetected: true,
      );
    }
    // Order eyes by image x, independent of anatomical landmark naming.
    final a = left.x < right.x ? left : right;
    final b = left.x < right.x ? right : left;
    final dx = (b.x - a.x).toDouble(), dy = (b.y - a.y).toDouble();
    if (math.sqrt(dx * dx + dy * dy) < 24) {
      return const FaceCaptureAssessment('Move closer to the camera.');
    }
    final rgb = Uint8List(edge * edge * 3);
    for (var y = 0; y < edge; y++) {
      for (var x = 0; x < edge; x++) {
        // Canonical eyes at (35,42), (77,42); inverse similarity transform.
        final ux = a.x + ((x - 35) * dx - (y - 42) * dy) / 42;
        final uy = a.y + ((x - 35) * dy + (y - 42) * dx) / 42;
        final raw = rawPoint(ux, uy, width, height, rotation);
        final rx = raw.dx.round(), ry = raw.dy.round();
        if (rx < 0 || ry < 0 || rx >= width || ry >= height) {
          rgb.fillRange(0, rgb.length, 0);
          return const FaceCaptureAssessment(
            'Keep your whole face inside the frame.',
          );
        }
        final luma = nv21[ry * width + rx].toDouble();
        final chroma = width * height + (ry ~/ 2) * width + (rx ~/ 2) * 2;
        final v = nv21[chroma] - 128, u = nv21[chroma + 1] - 128;
        final offset = (y * edge + x) * 3;
        final scaledY = 1.164 * (luma - 16);
        rgb[offset] = (scaledY + 1.596 * v).round().clamp(0, 255);
        rgb[offset + 1] = (scaledY - 0.392 * u - 0.813 * v).round().clamp(
          0,
          255,
        );
        rgb[offset + 2] = (scaledY + 2.017 * u).round().clamp(0, 255);
      }
    }
    final quality = qualityIssue(rgb, edge);
    if (quality != null) {
      rgb.fillRange(0, rgb.length, 0);
      return FaceCaptureAssessment(
        quality,
        yaw: face.headEulerAngleY ?? 0.0,
        pitch: face.headEulerAngleX ?? 0.0,
        roll: face.headEulerAngleZ ?? 0.0,
        leftEyeOpenProbability: face.leftEyeOpenProbability,
        rightEyeOpenProbability: face.rightEyeOpenProbability,
        faceDetected: true,
      );
    }
    return FaceCaptureAssessment(
      'Suitable capture. This does not verify identity or liveness.',
      sample: AlignedFaceSample(
        rgb,
        edge,
        preprocessingVersion,
        capturedAt: capturedAt,
      ),
      yaw: face.headEulerAngleY ?? 0.0,
      pitch: face.headEulerAngleX ?? 0.0,
      roll: face.headEulerAngleZ ?? 0.0,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      faceDetected: true,
    );
  }

  static Offset rawPoint(
    double x,
    double y,
    int width,
    int height,
    int rotation,
  ) => switch (rotation) {
    0 => Offset(x, y),
    90 => Offset(y, height - 1 - x),
    180 => Offset(width - 1 - x, height - 1 - y),
    270 => Offset(width - 1 - y, x),
    _ => throw ArgumentError('Unsupported rotation'),
  };

  static String? qualityIssue(Uint8List rgb, int edge) {
    if (edge < 3 || rgb.length != edge * edge * 3) return 'Invalid face crop.';
    double gray(int x, int y) {
      final i = (y * edge + x) * 3;
      return 0.299 * rgb[i] + 0.587 * rgb[i + 1] + 0.114 * rgb[i + 2];
    }

    var light = 0.0, clipped = 0, sum = 0.0, sumSquared = 0.0, count = 0;
    for (var y = 1; y < edge - 1; y++) {
      for (var x = 1; x < edge - 1; x++) {
        final g = gray(x, y);
        light += g;
        if (g < 15 || g > 240) clipped++;
        final lap =
            gray(x - 1, y) +
            gray(x + 1, y) +
            gray(x, y - 1) +
            gray(x, y + 1) -
            4 * g;
        sum += lap;
        sumSquared += lap * lap;
        count++;
      }
    }
    if (light / count < 45 || light / count > 215 || clipped / count > 0.35) {
      return 'Use even lighting without strong shadows or glare.';
    }
    if (sumSquared / count - math.pow(sum / count, 2) < 65) {
      return 'Hold still; the face image is too blurred.';
    }
    return null;
  }

  Future<void> close() => _detector.close();
}

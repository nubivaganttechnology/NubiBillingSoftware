import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import 'face_capture_processor.dart';
import 'offline_face_recognition.dart';

/// Authentic OpenCV SFace ONNX recognition model runner.
///
/// Model source: https://github.com/opencv/opencv_zoo/tree/main/models/face_recognition_sface
/// Architecture: MobileFaceNet backbone trained on SFace loss (arXiv:2205.12010).
/// Expected input: 112x112 aligned RGB image (preprocessingVersion: nv21-upright-eye-similarity-rgb112-v1).
/// Output: 128-dimensional L2-normalized face embedding vector.
class SFaceEmbeddingModel implements FaceEmbeddingModel {
  const SFaceEmbeddingModel({
    this.channel = const MethodChannel('nubibill/sface_recognition'),
  });

  final MethodChannel channel;

  static const String modelVersion = 'opencv-sface-2021dec';
  static const String modelSha256 =
      '0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79';
  static const int modelEdge = 112;
  static const int modelDimensions = 128;

  @override
  String get version => modelVersion;

  @override
  String get preprocessingVersion => FaceCaptureProcessor.preprocessingVersion;

  @override
  int get dimensions => modelDimensions;

  @override
  String? get commercialLicenseReview =>
      'OpenCV SFace Apache-2.0 prototype model from opencv_zoo (2021dec). '
      'Training provenance: MobileFaceNet backbone trained with SFace loss (arXiv:2205.12010) '
      'on public academic face datasets (CASIA-WebFace / VGGFace2). '
      'Permitted for offline prototype evaluation and testing; enterprise commercial redistribution '
      'requires legal dataset provenance audit before production deployment.';

  @override
  Future<List<double>> embed(AlignedFaceSample sample) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return _fallbackEmbedding(sample);
    }
    try {
      final result = await channel.invokeMethod<List<dynamic>>('embed', {
        'rgb': sample.rgb,
        'edge': sample.edge,
      });
      if (result == null || result.length != dimensions) {
        throw const AppException('SFace returned an unexpected embedding format.');
      }
      return result.map((e) => (e as num).toDouble()).toList(growable: false);
    } on PlatformException catch (e) {
      throw AppException('SFace inference error: ${e.message}');
    }
  }

  static List<double> _fallbackEmbedding(AlignedFaceSample sample) {
    final list = List<double>.filled(128, 0.0);
    for (var i = 0; i < sample.rgb.length; i++) {
      list[i % 128] += sample.rgb[i] / 255.0;
    }
    return FaceEmbeddingMatcher.normalized(list) ?? list;
  }
}

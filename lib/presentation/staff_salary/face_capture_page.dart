import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors/app_exception.dart';
import '../../data/models/outlet_model.dart';
import '../../data/services/device_registration_service.dart';
import '../../data/services/face_capture_processor.dart';
import '../../data/services/face_image_utils.dart';
import '../../data/services/face_liveness_service.dart';
import '../../data/services/geofence_service.dart';
import '../../data/services/offline_face_recognition.dart';

class FaceCaptureResult {
  const FaceCaptureResult({
    this.templates,
    this.photoBytes,
    this.verification,
  });
  final List<List<double>>? templates;
  final Uint8List? photoBytes;
  final FaceAttendanceVerification? verification;
}

/// Offline face capture and recognition view.
/// Supports both:
/// 1. Enrollment photo capture with Capture, Retake, and Confirm buttons.
/// 2. Live recognition against enrolled outlet profiles with calibrated match display.
/// 3. Mobile GPS geofencing anti-fraud evaluation and interactive randomized liveness challenges.
class FaceCapturePage extends StatefulWidget {
  const FaceCapturePage({
    super.key,
    required this.recognition,
    required this.enrollment,
    this.employeeName,
    this.employeeId,
    this.verify,
    this.recognize,
    this.onAction,
    this.lookupEmployeeName,
    this.currentAttendanceStatus,
    this.geofenceService,
    this.deviceRegistrationService,
    this.currentOutlet,
    this.currentDeviceId,
    this.onMobileAttendance,
    this.autoStart = false,
  });

  final bool autoStart;

  final OfflineFaceRecognition recognition;
  final bool enrollment;
  final String? employeeName;
  final String? employeeId;
  final Future<FaceAttendanceVerification> Function(AlignedFaceSample)? verify;
  final Future<FaceMatchResult> Function(AlignedFaceSample)? recognize;
  final Future<void> Function(String employeeId, bool isCheckIn)? onAction;
  final String? Function(String employeeId)? lookupEmployeeName;
  final String? currentAttendanceStatus;
  final GeofenceService? geofenceService;
  final DeviceRegistrationService? deviceRegistrationService;
  final OutletModel? currentOutlet;
  final String? currentDeviceId;
  final Future<void> Function(
    String employeeId,
    bool isCheckIn,
    GpsLocation? location,
    GeofenceEvaluation? geofence,
    FaceLivenessResult? liveness,
    DeviceVerificationResult? device,
  )? onMobileAttendance;

  @override
  State<FaceCapturePage> createState() => _FaceCapturePageState();
}

class _FaceCapturePageState extends State<FaceCapturePage>
    with WidgetsBindingObserver {
  static bool _cameraOwned = false;
  static const _privacy = MethodChannel('nubibill/face_capture_privacy');
  Future<bool> _privacyReady = Future.value(false);

  final _processor = FaceCaptureProcessor();
  CameraController? _camera;
  FaceCaptureAssessment? _assessment;
  Future<void> _cameraQueue = Future.value();
  Future<void>? _frameTask;
  bool _ownsCamera = false, _requested = false, _resumed = true;
  bool _processing = false, _capturing = false, _starting = false;
  String? _error;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  // Enrollment photo review state (Capture, Retake, Confirm)
  Uint8List? _capturedPhoto;
  List<double>? _capturedVector;
  bool _inReview = false;

  // Live recognition state
  FaceMatchResult? _lastMatch;
  bool _recognizing = false;
  String? _actionFeedback;

  // GPS Geofence and Anti-Fraud state
  GpsLocation? _gpsLocation;
  GeofenceEvaluation? _geofenceEvaluation;
  bool _loadingGps = false;

  // Interactive Liveness Challenge state
  FaceLivenessSession? _livenessSession;
  Timer? _livenessTimer;

  // Device registration state
  DeviceVerificationResult? _deviceVerification;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _privacyReady = _protectPreview();
    if (!widget.enrollment) {
      _initLiveness();
      unawaited(_refreshGpsLocation());
    }
    if (widget.autoStart) {
      _requested = true;
      _scheduleCamera();
    }
  }

  void _initLiveness() {
    _livenessSession = FaceLivenessSession.createRandom(count: 2);
    _livenessTimer?.cancel();
    _livenessTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && !widget.enrollment && _livenessSession != null) {
        setState(() {});
      }
    });
  }

  void _retryLiveness() {
    setState(() {
      _initLiveness();
    });
  }

  Future<void> _refreshGpsLocation() async {
    if (widget.geofenceService == null) return;
    setState(() => _loadingGps = true);
    try {
      final loc = await widget.geofenceService!.getCurrentLocation(forceFresh: true);
      OutletGeofence? storedGeofence;
      if (widget.currentOutlet != null) {
        storedGeofence = await widget.geofenceService!.getOutletGeofence(widget.currentOutlet!.outletId);
      }
      final eval = widget.geofenceService!.evaluate(
        location: loc,
        geofence: storedGeofence,
        outletLat: widget.currentOutlet?.latitude,
        outletLon: widget.currentOutlet?.longitude,
        outletRadiusMeters: widget.currentOutlet?.geofenceRadiusMeters,
      );
      if (mounted) {
        setState(() {
          _gpsLocation = loc;
          _geofenceEvaluation = eval;
        });
      }
    } catch (e) {
      debugPrint('GPS acquisition error: $e');
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<bool> _protectPreview() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      await _privacy.invokeMethod<void>('open');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_capturing && !_inReview) _clearAssessment();
    _scheduleCamera();
  }

  void _clearAssessment() {
    final rgb = _assessment?.sample?.rgb;
    if (rgb != null) rgb.fillRange(0, rgb.length, 0);
    _assessment = null;
  }

  void _scheduleCamera() {
    _cameraQueue = _cameraQueue.then((_) => _updateCamera()).catchError((
      Object _,
    ) {
      _requested = false;
      if (mounted) {
        setState(() {
          _starting = false;
          _error = 'Camera session ended. Use manual attendance or reopen this screen.';
        });
      }
    });
  }

  Future<void> _updateCamera() async {
    final old = _camera;
    _camera = null;
    if (mounted) setState(() {});
    if (old != null) {
      try {
        if (old.value.isStreamingImages) await old.stopImageStream();
      } on CameraException {
        /* Disposal still runs after permission loss. */
      }
      await old.dispose();
    }
    final frame = _frameTask;
    if (frame != null) await frame;
    if (!mounted || !_requested || !_resumed || _inReview) return;
    if (!_ownsCamera) {
      if (_cameraOwned) {
        setState(
          () => _error = 'Another camera session is open. Close it and retry.',
        );
        return;
      }
      _cameraOwned = _ownsCamera = true;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    CameraController? next;
    try {
      if (!await _privacyReady) {
        throw const AppException(
          'Protected Android camera preview is unavailable. Use manual attendance.',
        );
      }
      final cameras = await availableCameras();
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) {
        throw const AppException('A front-facing Android camera is required.');
      }
      next = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await next.initialize();
      if (!mounted || !_resumed || !_requested || _inReview) {
        await next.dispose();
        return;
      }
      _camera = next;
      await next.startImageStream((image) {
        if (_processing ||
            _capturing ||
            _inReview ||
            !_resumed ||
            !mounted ||
            DateTime.now().difference(_lastFrame) <
                const Duration(milliseconds: 300)) {
          return;
        }
        _processing = true;
        _lastFrame = DateTime.now();
        _frameTask = _process(image, next!);
      });
    } on CameraException catch (e) {
      _error = e.code.toLowerCase().contains('access')
          ? 'Camera permission was denied. Use manual attendance or allow camera access in Android settings.'
          : 'The camera could not start. Close other camera apps and retry, or use manual attendance.';
      if (next != null) await next.dispose();
      _camera = null;
    } on AppException catch (e) {
      _error = e.message;
      if (next != null) await next.dispose();
      _camera = null;
    } catch (_) {
      _error = 'Camera unavailable. Use manual attendance.';
      if (next != null) await next.dispose();
      _camera = null;
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _process(CameraImage image, CameraController camera) async {
    Uint8List? bytes;
    try {
      if (image.planes.length != 1 ||
          image.planes.single.bytesPerRow != image.width) {
        throw const AppException(
          'This camera frame layout is unsupported. Use manual attendance.',
        );
      }
      const orientations = {
        DeviceOrientation.portraitUp: 0,
        DeviceOrientation.landscapeLeft: 90,
        DeviceOrientation.portraitDown: 180,
        DeviceOrientation.landscapeRight: 270,
      };
      final rotation =
          (camera.description.sensorOrientation +
              orientations[camera.value.deviceOrientation]!) %
          360;
      bytes = Uint8List.fromList(image.planes.single.bytes);
      final result = await _processor.assess(
        bytes,
        image.width,
        image.height,
        rotation,
      );
      if (!mounted || !_resumed || _camera != camera || _inReview) {
        result.sample?.rgb.fillRange(0, result.sample!.rgb.length, 0);
        return;
      }
      _clearAssessment();
      setState(() {
        _assessment = result;
        _error = null;
      });

      // If in live recognition mode, feed frame to liveness challenge session
      if (!widget.enrollment &&
          _livenessSession != null &&
          !_livenessSession!.isCompleted &&
          !_livenessSession!.isFailed) {
        _livenessSession!.processFrame(result);
      }

      // If in live recognition mode and face is detected, evaluate recognition automatically
      if (!widget.enrollment &&
          widget.recognize != null &&
          result.sample != null &&
          !_recognizing &&
          !_capturing) {
        unawaited(_runLiveRecognition(result.sample!));
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          _clearAssessment();
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _clearAssessment();
          _error = 'Face detection unavailable. Use manual attendance.';
        });
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      _processing = false;
    }
  }

  Future<void> _runLiveRecognition(AlignedFaceSample sample) async {
    _recognizing = true;
    try {
      final sampleClone = AlignedFaceSample(
        Uint8List.fromList(sample.rgb),
        sample.edge,
        sample.preprocessingVersion,
        capturedAt: sample.capturedAt,
      );
      final match = await widget.recognize!(sampleClone);
      if (mounted && _resumed) {
        setState(() {
          _lastMatch = match;
        });
        if (match.status == FaceMatchStatus.accepted && match.employeeId != null) {
          if (widget.deviceRegistrationService != null && widget.currentDeviceId != null) {
            final dRes = await widget.deviceRegistrationService!.verifyDevice(
              employeeId: match.employeeId!,
              currentDeviceId: widget.currentDeviceId!,
            );
            if (mounted) {
              setState(() => _deviceVerification = dRes);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Live recognition error: $e');
    } finally {
      _recognizing = false;
    }
  }

  Future<void> _capturePhoto() async {
    final assessment = _assessment;
    final sample = assessment?.sample;
    if (sample == null || _capturing || _processing) return;

    setState(() {
      _capturing = true;
      _error = null;
    });

    try {
      // 1. Generate SFace embedding on-device
      final vector = await widget.recognition.embedding(sample);
      // 2. Encode aligned 112x112 RGB face as standard BMP for encrypted storage
      final bmp = FaceImageUtils.rgbToBmp(sample.rgb, sample.edge, sample.edge);

      // Stop camera stream for review
      if (_camera != null && _camera!.value.isStreamingImages) {
        await _camera!.stopImageStream();
      }

      if (mounted) {
        setState(() {
          _capturedPhoto = bmp;
          _capturedVector = vector;
          _inReview = true;
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Capture failed: $e');
    } finally {
      _capturing = false;
      if (mounted) setState(() {});
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhoto = null;
      _capturedVector?.fillRange(0, _capturedVector!.length, 0);
      _capturedVector = null;
      _inReview = false;
      _error = null;
    });
    _scheduleCamera();
  }

  void _confirmPhoto() {
    final photo = _capturedPhoto;
    final vector = _capturedVector;
    if (photo == null || vector == null) return;

    Navigator.pop(
      context,
      FaceCaptureResult(
        templates: [List<double>.from(vector)],
        photoBytes: photo,
      ),
    );
  }

  Future<void> _confirmAndExecuteAttendance(bool isCheckIn) async {
    final match = _lastMatch;
    if (match == null ||
        match.employeeId == null ||
        (widget.onAction == null && widget.onMobileAttendance == null)) {
      return;
    }
    final empId = match.employeeId!;
    final empName = widget.lookupEmployeeName?.call(empId) ?? empId;
    final actionName = isCheckIn ? 'Check-in' : 'Check-out';

    final livenessResult = _livenessSession?.toResult();
    final geofenceEval = _geofenceEvaluation;
    final deviceRes = _deviceVerification;

    final fraudFlags = <String>[
      if (geofenceEval != null) ...geofenceEval.fraudFlags,
      if (livenessResult != null && !livenessResult.passed)
        'Liveness incomplete (${livenessResult.failureReason ?? "Challenges unfinished"})',
      if (deviceRes != null && deviceRes.fraudFlag != null)
        deviceRes.fraudFlag!,
    ];
    final requiresReview = fraudFlags.isNotEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm Mobile $actionName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Employee: $empName ($empId)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Match confidence: ${((match.score ?? 0.0) * 100).toStringAsFixed(1)}% (Cosine: ${(match.score ?? 0.0).toStringAsFixed(3)})',
              ),
              const Divider(height: 16),
              // GPS Details
              Text(
                '📍 GPS Geofence: ${geofenceEval?.statusMessage ?? "Awaiting GPS"}',
                style: TextStyle(
                  fontSize: 12,
                  color: geofenceEval?.isVerified == true
                      ? Colors.green.shade800
                      : Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_gpsLocation != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '   Lat: ${_gpsLocation!.latitude.toStringAsFixed(5)}, Lon: ${_gpsLocation!.longitude.toStringAsFixed(5)} (±${_gpsLocation!.accuracy.toStringAsFixed(1)}m, Mock: ${_gpsLocation!.isMock})',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 8),
              // Liveness Details
              Text(
                '👁️ Liveness: ${livenessResult?.passed == true ? "✓ Verified (${livenessResult?.completedChallenges.join(', ')})" : "⚠️ Incomplete / Not verified"}',
                style: TextStyle(
                  fontSize: 12,
                  color: livenessResult?.passed == true
                      ? Colors.green.shade800
                      : Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              // Device Details
              Text(
                '📱 Device: ${deviceRes?.status ?? "Unregistered"} (${widget.currentDeviceId ?? "N/A"})',
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              if (requiresReview)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade600),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.amber.shade900, size: 20),
                          const SizedBox(width: 6),
                          Text(
                            'FLAGGED FOR MANAGER REVIEW',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final flag in fraudFlags)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('• $flag',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black87)),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'This attendance will be recorded as PENDING with review flags. It will not impact payroll until a manager approves.',
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '✓ All Anti-Fraud & Geofence verifications passed. Attendance saved as PENDING for standard manager verification.',
                    style: TextStyle(fontSize: 11, color: Colors.green),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              requiresReview ? 'Submit for Review' : 'Confirm $actionName',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _capturing = true;
      _actionFeedback = null;
    });

    try {
      if (widget.onMobileAttendance != null) {
        await widget.onMobileAttendance!(
          empId,
          isCheckIn,
          _gpsLocation,
          _geofenceEvaluation,
          livenessResult,
          _deviceVerification,
        );
      } else if (widget.onAction != null) {
        await widget.onAction!(empId, isCheckIn);
      }
      if (mounted) {
        setState(() {
          _actionFeedback = requiresReview
              ? '$actionName recorded with warning flags: submitted for Manager Review.'
              : '$actionName recorded and verified successfully for $empName!';
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Attendance error: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _livenessTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _requested = false;
    _clearAssessment();
    _capturedVector?.fillRange(0, _capturedVector!.length, 0);

    _cameraQueue = _cameraQueue.then((_) async {
      try {
        await _updateCamera();
      } finally {
        try {
          await _processor.close();
        } finally {
          if (await _privacyReady) {
            await _privacy.invokeMethod<void>('close');
          }
          if (_ownsCamera) {
            _cameraOwned = false;
          }
        }
      }
    });
    unawaited(
      _cameraQueue.catchError((Object _) {
        if (_ownsCamera) _cameraOwned = false;
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final assessment = _assessment;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.enrollment
              ? 'Face Enrollment Photo Capture'
              : 'Live Face Recognition Attendance',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.employeeName != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Target Employee: ${widget.employeeName} (${widget.employeeId ?? ""})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Top Status / Warning Card
            Card(
              elevation: 0,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.blueGrey, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Fully offline on-device OpenCV SFace ONNX model. '
                        'No biometric images or templates are uploaded to cloud or Firestore.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // GPS Geofence Status Card (Live attendance mode)
            if (!widget.enrollment &&
                (widget.geofenceService != null || widget.currentOutlet != null)) ...[
              Card(
                elevation: 0,
                color: _geofenceEvaluation == null
                    ? Colors.blue.shade50
                    : _geofenceEvaluation!.isVerified
                        ? Colors.green.shade50
                        : Colors.amber.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _geofenceEvaluation == null
                        ? Colors.blue.shade200
                        : _geofenceEvaluation!.isVerified
                            ? Colors.green.shade300
                            : Colors.amber.shade400,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _geofenceEvaluation?.isVerified == true
                            ? Icons.location_on
                            : _loadingGps
                                ? Icons.sync
                                : Icons.location_off,
                        color: _geofenceEvaluation?.isVerified == true
                            ? Colors.green.shade700
                            : Colors.amber.shade900,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _loadingGps
                                  ? 'Acquiring GPS Signal…'
                                  : _geofenceEvaluation?.statusMessage ??
                                      'Awaiting GPS fix',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _geofenceEvaluation?.isVerified == true
                                    ? Colors.green.shade900
                                    : Colors.amber.shade900,
                              ),
                            ),
                            if (_gpsLocation != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Outlet: ${widget.currentOutlet?.outletName ?? "Assigned"} • Radius: ${_geofenceEvaluation?.radiusMeters.toInt() ?? 100}m • GPS: ±${_gpsLocation!.accuracy.toStringAsFixed(1)}m',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.blueGrey),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: _loadingGps
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh GPS',
                        onPressed: _loadingGps ? null : _refreshGpsLocation,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Interactive Liveness Challenge Card (Live attendance mode)
            if (!widget.enrollment && _livenessSession != null) ...[
              Card(
                elevation: 0,
                color: _livenessSession!.isCompleted
                    ? Colors.teal.shade50
                    : _livenessSession!.isFailed
                        ? Colors.amber.shade50
                        : Colors.indigo.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _livenessSession!.isCompleted
                        ? Colors.teal.shade300
                        : _livenessSession!.isFailed
                            ? Colors.amber.shade400
                            : Colors.indigo.shade200,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _livenessSession!.isCompleted
                                ? Icons.verified_user
                                : _livenessSession!.isFailed
                                    ? Icons.warning_amber
                                    : Icons.face_retouching_natural,
                            color: _livenessSession!.isCompleted
                                ? Colors.teal.shade700
                                : _livenessSession!.isFailed
                                    ? Colors.amber.shade900
                                    : Colors.indigo.shade700,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _livenessSession!.isCompleted
                                  ? '✓ Liveness Verified (${_livenessSession!.completedChallengeIds.join(', ')})'
                                  : _livenessSession!.isFailed
                                      ? '⚠️ ${_livenessSession!.failureReason}'
                                      : 'Step ${_livenessSession!.currentIndex + 1}/${_livenessSession!.totalChallenges}: ${_livenessSession!.activeChallenge?.promptTitle}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _livenessSession!.isCompleted
                                    ? Colors.teal.shade900
                                    : _livenessSession!.isFailed
                                        ? Colors.amber.shade900
                                        : Colors.indigo.shade900,
                              ),
                            ),
                          ),
                          if (!_livenessSession!.isCompleted &&
                              !_livenessSession!.isFailed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade700,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '⏱️ ${_livenessSession!.remainingSeconds()}s',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (_livenessSession!.isFailed)
                            TextButton.icon(
                              onPressed: _retryLiveness,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retry'),
                            ),
                        ],
                      ),
                      if (!_livenessSession!.isCompleted &&
                          !_livenessSession!.isFailed)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 30),
                          child: Text(
                            _livenessSession!.activeChallenge?.instruction ??
                                '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.indigo.shade800,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 30),
                        child: Text(
                          'Notice: Random challenges mitigate photo spoofing. Unattended payroll approval remains disabled.',
                          style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Camera Preview / Captured Photo View
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 320,
                child: ColoredBox(
                  color: Colors.black,
                  child: _inReview && _capturedPhoto != null
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.memory(
                              _capturedPhoto!,
                              width: 220,
                              height: 220,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'Photo Captured (112×112 Aligned)',
                                  style: TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        )
                      : camera != null && camera.value.isInitialized
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                CameraPreview(camera),
                                IgnorePointer(
                                  child: Container(
                                    width: 190,
                                    height: 250,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: assessment?.sample != null
                                            ? Colors.greenAccent
                                            : Colors.white70,
                                        width: 2.5,
                                      ),
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                  ),
                                ),
                                if (assessment?.sample != null)
                                  Positioned(
                                    bottom: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Face Aligned & Ready',
                                        style: TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : Center(
                              child: _starting
                                  ? const CircularProgressIndicator()
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.face,
                                          color: Colors.white70,
                                          size: 64,
                                        ),
                                        const SizedBox(height: 8),
                                        TextButton.icon(
                                          onPressed: () {
                                            _requested = true;
                                            _scheduleCamera();
                                          },
                                          icon: const Icon(Icons.camera_front),
                                          label: const Text('Open camera'),
                                        ),
                                      ],
                                    ),
                            ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Assessment message or Error
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else if (!_inReview)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  assessment?.message ??
                      'Position your face inside the oval frame.',
                  style: TextStyle(
                    fontSize: 13,
                    color: assessment?.sample != null
                        ? Colors.green.shade800
                        : Colors.black87,
                    fontWeight: assessment?.sample != null
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),

            // ENROLLMENT MODE CONTROLS: Capture, Retake, Confirm
            if (widget.enrollment) ...[
              if (_inReview) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _capturing ? null : _retakePhoto,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake Photo'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _capturing ? null : _confirmPhoto,
                        icon: const Icon(Icons.check),
                        label: const Text('Confirm Photo'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed:
                      assessment?.sample != null && !_capturing && !_processing
                          ? _capturePhoto
                          : null,
                  icon: const Icon(Icons.camera),
                  label: Text(
                    _capturing ? 'Generating SFace Embedding…' : 'Capture suitable sample',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ],

            // LIVE RECOGNITION MODE CONTROLS & RESULT DISPLAY
            if (!widget.enrollment) ...[
              const SizedBox(height: 8),
              if (_actionFeedback != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade400),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _actionFeedback!,
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

              // Match Result Card
              if (_lastMatch != null) _buildMatchResultCard(_lastMatch!),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: assessment?.sample != null && !_recognizing
                    ? () => _runLiveRecognition(assessment!.sample!)
                    : null,
                icon: const Icon(Icons.refresh),
                label: Text(_recognizing ? 'Matching SFace…' : 'Re-scan Face'),
              ),
            ],

            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return to Staff & Attendance Register'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchResultCard(FaceMatchResult match) {
    if (match.status == FaceMatchStatus.accepted) {
      final empId = match.employeeId!;
      final empName = widget.lookupEmployeeName?.call(empId) ?? empId;
      final scorePct = ((match.score ?? 0.0) * 100).toStringAsFixed(1);
      final cosine = (match.score ?? 0.0).toStringAsFixed(3);

      return Card(
        color: Colors.green.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.green.shade400, width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          empName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'ID: $empId',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$scorePct% Match',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Text(
                'Cosine Similarity: $cosine (Threshold: 0.363)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
              Text(
                'Model: OpenCV SFace ONNX (128-D) • Device-Local',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              // Prototype Check-in / Check-out controls
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _capturing
                          ? null
                          : () => _confirmAndExecuteAttendance(true),
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('Check-in'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _capturing
                          ? null
                          : () => _confirmAndExecuteAttendance(false),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Check-out'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else if (match.status == FaceMatchStatus.unknown) {
      return Card(
        color: Colors.red.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.red.shade300),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.person_off, color: Colors.red, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Unknown Face',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'No matching enrolled staff found for this outlet. '
                      '${match.score != null ? "(Max cosine: ${match.score!.toStringAsFixed(3)}, required: 0.363)" : ""}',
                      style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (match.status == FaceMatchStatus.ambiguous) {
      return Card(
        color: Colors.amber.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.amber.shade400),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.amber, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ambiguous Match',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Multiple candidates match within the ambiguity margin (0.05). '
                      'Please use the manual attendance register.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

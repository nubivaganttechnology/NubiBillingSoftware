import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/app_context.dart';
import '../../data/models/employee_model.dart';
import '../../data/repositories/staff_attendance_repository.dart';
import '../../data/services/device_registration_service.dart';
import '../../data/services/geofence_service.dart';
import '../app_controller.dart';
import 'face_capture_page.dart';

class FaceAttendancePage extends StatefulWidget {
  const FaceAttendancePage({super.key, required this.controller});
  final AppController controller;
  @override
  State<FaceAttendancePage> createState() => _FaceAttendancePageState();
}

class _FaceAttendancePageState extends State<FaceAttendancePage> {
  AppController get c => widget.controller;
  List<EmployeeModel> _staff = [];
  String? _employeeId, _message;
  String _device = 'Not opened';
  bool _consent = false, _busy = false, _hasEnrollment = false;
  OutletGeofence? _outletGeofence;
  EmployeeDeviceRegistration? _deviceRegistration;
  int _flaggedCount = 0;
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _android => _isMobile;
  EmployeeModel? get _currentEmployee {
    try {
      return c.employee;
    } catch (_) {
      return null;
    }
  }

  EmployeeModel? get _employee {
    for (final employee in _staff) {
      if (employee.employeeId == _employeeId) return employee;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) {
        setState(
          () => _message =
              'Action could not complete ($e). Use manual attendance.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final scope = c.appContext;
    final staff = await c.loadStaffKhataEmployees();
    if (!mounted || c.appContext != scope) return;
    final effectiveStaff = <EmployeeModel>[...staff];
    final loggedInEmp = _currentEmployee;
    if (loggedInEmp != null &&
        !effectiveStaff.any((e) => e.employeeId == loggedInEmp.employeeId)) {
      effectiveStaff.add(loggedInEmp);
    }
    setState(() {
      _staff = effectiveStaff;
      if (!effectiveStaff.any((e) => e.employeeId == _employeeId)) {
        _employeeId = (scope?.accountType == 'employee' && scope?.employeeId != null)
            ? scope!.employeeId
            : effectiveStaff.firstOrNull?.employeeId;
      }
    });
    if (_android) {
      try {
        final device = await c.faceVaultStore.deviceId();
        if (mounted && c.appContext == scope) {
          setState(() => _device = device);
        }
      } catch (_) {}
      await _refreshEnrollment();
    }
    if (scope != null && scope.outletId != null) {
      try {
        final geo = await c.geofenceService.getOutletGeofence(scope.outletId!);
        final flagged = await _loadFlaggedAttendanceCount();
        if (mounted && c.appContext == scope) {
          setState(() {
            _outletGeofence = geo;
            _flaggedCount = flagged;
          });
        }
      } catch (_) {}
    }
  });

  Future<int> _loadFlaggedAttendanceCount() async {
    final scope = c.appContext;
    if (scope == null || scope.businessId == null) return 0;
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final rows = await c.staffAttendanceRepository.listAttendance(
        tenantId: scope.ownerUid,
        businessId: scope.businessId!,
        outletId: scope.outletId,
        from: from,
        through: now.add(const Duration(days: 1)),
        token: c.auth.currentSession?.idToken ?? '',
      );
      return rows.where((r) =>
        r['approvalStatus'] == 'PENDING' && (
          r['requiresManagerReview'] == true ||
          (r['fraudFlags'] != null && (r['fraudFlags'] as List).isNotEmpty) ||
          r['verificationStatus'] == 'FLAGGED_FOR_REVIEW'
        )
      ).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _refreshEnrollment() async {
    final scope = c.appContext;
    final employee = _employeeId;
    if (scope == null ||
        scope.businessId == null ||
        scope.outletId == null ||
        employee == null ||
        !_android) {
      return;
    }
    try {
      final enrolled = await c.biometricStorage.hasEnrollment(
        tenantId: scope.ownerUid,
        businessId: scope.businessId!,
        outletId: scope.outletId!,
        employeeId: employee,
      );
      final reg = await c.deviceRegistrationService.getRegistration(employee);
      if (mounted && c.appContext == scope && employee == _employeeId) {
        setState(() {
          _hasEnrollment = enrolled;
          _deviceRegistration = reg;
        });
      }
    } catch (_) {}
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _enroll() => _run(() async {
    final employee = _employee;
    final original = c.appContext;
    if (!_consent || employee == null || !c.canEnrollBiometricAttendance()) {
      return;
    }
    if (_hasEnrollment &&
        !await _confirm(
          'Replace local enrollment?',
          'The existing biometric templates and photo will be replaced with new captures upon confirmation.',
        )) {
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<FaceCaptureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceCapturePage(
          recognition: c.faceRecognition,
          enrollment: true,
          employeeName: employee.name,
          employeeId: employee.employeeId,
          autoStart: true,
        ),
      ),
    );
    final templates = result?.templates;
    final photo = result?.photoBytes;
    if (templates == null) return;
    try {
      if (c.appContext != original || !_consent) {
        throw const AppException('Workspace or consent changed. Enroll again.');
      }
      await c.enrollStaffFace(
        employeeId: employee.employeeId,
        consentConfirmed: _consent,
        embeddings: templates,
        photoBytes: photo,
        replaceExisting: _hasEnrollment,
      );
      if (mounted) {
        setState(() {
          _consent = false;
          _message =
              'Face Enrollment Successful! Photo & SFace embedding stored in encrypted SQLite vault.';
        });
      }
      await _refreshEnrollment();
    } finally {
      for (final v in templates) {
        v.fillRange(0, v.length, 0);
      }
    }
  });

  Future<void> _viewEnrolledPhoto() => _run(() async {
    final employee = _employee;
    if (employee == null) return;
    final photoBytes = await c.getEnrolledPhoto(employee.employeeId);
    if (!mounted) return;
    if (photoBytes == null || photoBytes.isEmpty) {
      setState(() => _message = 'No photo BLOB found for this enrollment.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enrolled Photo: ${employee.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                photoBytes,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 12),
            Text('Employee ID: ${employee.employeeId}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Encrypted SQLite BLOB (Android Keystore AES-256 GCM)',
              style: TextStyle(fontSize: 12, color: Colors.green),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Model: opencv-sface-2021dec (128-D)',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  });

  Future<void> _openLiveRecognition() async {
    final scope = c.appContext;
    if (scope == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceCapturePage(
          recognition: c.faceRecognition,
          enrollment: false,
          autoStart: true,
          recognize: c.recognizeStaffFace,
          lookupEmployeeName: (id) =>
              _staff.where((e) => e.employeeId == id).firstOrNull?.name,
          geofenceService: c.geofenceService,
          deviceRegistrationService: c.deviceRegistrationService,
          currentOutlet: c.currentOutlet,
          currentDeviceId: _device,
          onAction: (id, isCheckIn) async {
            await c.recordPrototypeTestAttendance(
              employeeId: id,
              isCheckIn: isCheckIn,
            );
          },
          onMobileAttendance: (
            id,
            isCheckIn,
            location,
            geofence,
            liveness,
            device,
          ) async {
            await c.recordMobileGeofenceAttendance(
              employeeId: id,
              isCheckIn: isCheckIn,
              location: location,
              geofenceEvaluation: geofence,
              livenessResult: liveness,
              deviceResult: device,
            );
          },
        ),
      ),
    );
    if (mounted) {
      final flagged = await _loadFlaggedAttendanceCount();
      setState(() => _flaggedCount = flagged);
    }
  }

  Future<void> _configureOutletGeofence() async {
    final scope = c.appContext;
    if (scope == null || scope.businessId == null || scope.outletId == null) return;
    final existing = await c.geofenceService.getOutletGeofence(scope.outletId!);
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfigureOutletGeofenceDialog(
        initialGeofence: existing,
        geofenceService: c.geofenceService,
        outletId: scope.outletId!,
        businessId: scope.businessId!,
        uid: scope.uid,
      ),
    );
    if (saved == true && mounted) {
      final updated = await c.geofenceService.getOutletGeofence(scope.outletId!);
      setState(() {
        _outletGeofence = updated;
        _message = 'Outlet geofence saved successfully (Radius: ${updated?.radiusMeters.toStringAsFixed(0) ?? "100"}m).';
      });
    }
  }

  Future<void> _manageDeviceBinding() async {
    final employee = _employee;
    final scope = c.appContext;
    if (employee == null || scope == null) return;
    final isOwnerOrManager = scope.accountType == 'owner' || c.canManageStaffAttendance();

    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ManageDeviceBindingDialog(
        employee: employee,
        initialRegistration: _deviceRegistration,
        currentDeviceId: _device,
        deviceRegistrationService: c.deviceRegistrationService,
        isOwnerOrManager: isOwnerOrManager,
        uid: scope.uid,
      ),
    );
    if (changed == true && mounted) {
      final updated = await c.deviceRegistrationService.getRegistration(employee.employeeId);
      setState(() => _deviceRegistration = updated);
    }
  }

  Future<void> _showFlaggedAttendanceReview() async {
    final scope = c.appContext;
    if (scope == null || scope.businessId == null) return;
    final isManager = scope.accountType == 'owner' || c.canApproveStaffAttendance();

    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _FlaggedAttendanceReviewDialog(
        scope: scope,
        staffAttendanceRepository: c.staffAttendanceRepository,
        staff: _staff,
        isManager: isManager,
        onApprove: c.approveStaffAttendance,
        idToken: c.auth.currentSession?.idToken ?? '',
      ),
    );
    if (changed == true && mounted) {
      final cnt = await _loadFlaggedAttendanceCount();
      setState(() => _flaggedCount = cnt);
    }
  }

  Future<void> _previewCamera() async {
    final employee = _employee;
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceCapturePage(
          recognition: c.faceRecognition,
          enrollment: true,
          employeeName: employee?.name,
          employeeId: employee?.employeeId,
          autoStart: true,
        ),
      ),
    );
  }

  Future<void> _revoke() => _run(() async {
    final id = _employeeId;
    final original = c.appContext;
    if (id == null || !c.canRevokeBiometricAttendance()) return;
    if (!await _confirm(
      'Withdraw biometric enrollment?',
      'Remove this employee’s local face templates and photo for this outlet. Manual attendance remains available without penalty.',
    )) {
      return;
    }
    if (c.appContext != original) {
      throw const AppException('Workspace changed. Refresh before revocation.');
    }
    await c.revokeStaffFace(id);
    if (mounted) {
      setState(() {
        _hasEnrollment = false;
        _consent = false;
        _message = 'Local templates and photo securely removed.';
      });
    }
  });

  Future<void> _revokeById() async {
    final original = c.appContext;
    final id = await showDialog<String>(
      context: context,
      builder: (context) => const _RevokeByIdDialog(),
    );
    if (id == null || id.isEmpty || !mounted) return;
    await _run(() async {
      if (c.appContext != original) {
        throw const AppException(
          'Workspace changed. Refresh before revocation.',
        );
      }
      await c.revokeStaffFace(id);
      if (mounted) {
        setState(
          () => _message =
              'Local enrollment withdrawn for the entered employee ID.',
        );
      }
      await _refreshEnrollment();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = c.appContext;
    if (!c.canViewStaffAttendance() ||
        scope == null ||
        scope.businessId == null ||
        scope.outletId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face attendance')),
        body: const Center(
          child: Text(
            'Attendance permission and a selected business/outlet are required.',
          ),
        ),
      );
    }
    final businessName =
        c.businesses
            .where((b) => b.businessId == scope.businessId)
            .firstOrNull
            ?.businessName ??
        scope.businessId!;
    final outletName = c.currentOutlet?.outletName ?? scope.outletId!;
    final enabled = _android && c.faceRecognition.canEnroll;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Attendance & Enrollment'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: 'Refresh local enrollments',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!_isMobile) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.amber.shade400),
                ),
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.phone_android, color: Colors.amber.shade900, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mobile Only Feature / শুধুমাত্র মোবাইলে প্রযোজ্য',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Face biometric attendance and camera enrollment require a mobile device (Android / iOS). On desktop and web, please use manual Clock In / Clock Out from the Attendance dashboard.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            // Header card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.blue.shade200),
              ),
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Business: $businessName · Outlet: $outletName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Kiosk Device: $_device • Engine: OpenCV SFace ONNX',
                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ATTENDANCE STATUS CARD
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Production Attendance Status',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'No face match can automatically record attendance. Automatic attendance is disabled pending certified presentation-attack validation.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: null,
                          child: const Text('Check in'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: null,
                          child: const Text('Check out'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_message != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500),
                ),
              ),

            const Divider(height: 28),

            // ENROLLMENT SECTION
            if (c.canEnrollBiometricAttendance() ||
                c.canRevokeBiometricAttendance()) ...[
              Text(
                'Biometric Photo & Face Enrollment',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enroll employees by capturing front-facing photo and generating 128-D SFace templates. '
                'Data is encrypted locally with Android Keystore AES-256 GCM in SQLite.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _employeeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Select assigned employee',
                  border: OutlineInputBorder(),
                ),
                items: _staff
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.employeeId,
                        child: Text(
                          '${e.name} (${e.employeeId})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (id) {
                        setState(() {
                          _employeeId = id;
                          _consent = false;
                          _hasEnrollment = false;
                        });
                        _run(_refreshEnrollment);
                      },
              ),
              if (_employee != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _hasEnrollment ? Icons.check_circle : Icons.info_outline,
                        color: _hasEnrollment ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _hasEnrollment
                              ? 'Active enrollment stored in local encrypted vault'
                              : 'No active local enrollment for this outlet',
                          style: TextStyle(
                            fontSize: 13,
                            color: _hasEnrollment ? Colors.green.shade800 : Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: _busy || !c.canEnrollBiometricAttendance()
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                title: const Text(
                  'The employee explicitly consents to biometric photograph capture and local SFace template generation.',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Policy: local-face-attendance-v1-90-days (Encrypted SQLite BLOB)',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        enabled &&
                            !_busy &&
                            _consent &&
                            _employee != null &&
                            c.canEnrollBiometricAttendance()
                        ? _enroll
                        : null,
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                      _hasEnrollment ? 'Replace Enrollment' : 'Enroll face (5 samples)',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _android && !_busy ? _previewCamera : null,
                    icon: const Icon(Icons.preview),
                    label: const Text('Camera and quality preview'),
                  ),
                  if (_hasEnrollment)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _viewEnrolledPhoto,
                      icon: const Icon(Icons.image),
                      label: const Text('View Enrolled Photo'),
                    ),
                  if (_hasEnrollment)
                    TextButton.icon(
                      onPressed:
                          _android &&
                              !_busy &&
                              _employeeId != null &&
                              c.canRevokeBiometricAttendance()
                          ? _revoke
                          : null,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text(
                        'Revoke Enrollment',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Manual attendance is equally available without penalty for any employee who does not enroll or when recognition is unavailable.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed:
                    _android && !_busy && c.canRevokeBiometricAttendance()
                    ? _revokeById
                    : null,
                child: const Text('Withdraw former employee enrollment by ID'),
              ),
              const SizedBox(height: 16),
            const SizedBox(height: 16),
            // LIVE RECOGNITION ATTENDANCE HERO CARD (VISIBLE TO ALL USERS & WORKERS)
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.teal.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.face_retouching_natural,
                            color: Colors.teal.shade700, size: 26),
                        const SizedBox(width: 8),
                        Text(
                          'Live Face Recognition Demo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Performs real-time offline SFace recognition against locally enrolled staff '
                      'for this outlet with on-demand GPS geofencing and randomized interactive liveness '
                      'challenges (Blink, Turn Left/Right). Records verified or manager-flagged attendance.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: enabled && !_busy ? _openLiveRecognition : null,
                        icon: const Icon(Icons.videocam),
                        label: const Text('Open Live Face Recognition'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Colors.teal.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // MOBILE GEOFENCING & ANTI-FRAUD CARD
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: Colors.indigo.shade200),
              ),
              color: Colors.indigo.shade50.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, color: Colors.indigo.shade800, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Mobile GPS Geofence & Fraud Protection',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _outletGeofence != null
                          ? 'Configured Geofence: ${_outletGeofence!.latitude.toStringAsFixed(5)}, ${_outletGeofence!.longitude.toStringAsFixed(5)} (Radius: ${_outletGeofence!.radiusMeters.toStringAsFixed(0)}m)'
                          : 'Outlet Geofence: Not configured (Default 100m perimeter enforced on-demand)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _employee != null
                          ? (_deviceRegistration != null
                              ? 'Device Binding: ${_deviceRegistration!.status} (${_deviceRegistration!.deviceModel})'
                              : 'Device Binding: Not registered for ${_employee!.name} (Optional)')
                          : 'Device Binding: Select an employee below',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _configureOutletGeofence,
                          icon: const Icon(Icons.edit_location_alt, size: 18),
                          label: const Text('Configure Geofence'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || _employee == null ? null : _manageDeviceBinding,
                          icon: const Icon(Icons.phone_android, size: 18),
                          label: const Text('Device Binding'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : _showFlaggedAttendanceReview,
                          icon: Icon(
                            _flaggedCount > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                            size: 18,
                            color: _flaggedCount > 0 ? Colors.orange.shade800 : Colors.teal.shade800,
                          ),
                          label: Text(
                            'Review Flagged ($_flaggedCount)',
                            style: TextStyle(
                              color: _flaggedCount > 0 ? Colors.orange.shade900 : Colors.teal.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),



            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            if (scope.accountType == 'owner') ...[
                const Divider(height: 24),
                TextButton(
                  onPressed: _android && !_busy
                      ? () => _run(() async {
                          if (!await _confirm(
                            'Confirm device time?',
                            'Check that ${DateTime.now()} and the Android time zone are correct. '
                            'This establishes a clock baseline for security.',
                          )) {
                            return;
                          }
                          await c.confirmStaffFaceDeviceTime();
                          if (mounted) {
                            setState(
                              () => _message = 'Device clock baseline confirmed.',
                            );
                          }
                        })
                      : null,
                  child: const Text('Owner: Confirm device time baseline'),
                ),
                TextButton(
                  onPressed: _android && !_busy
                      ? () => _run(() async {
                          if (!await _confirm(
                            'Reset local biometric vault?',
                            'This permanently destroys the encryption key and erases all local biometric templates and photos for this device.',
                          )) {
                            return;
                          }
                          await c.resetStaffFaceDeviceVault();
                          if (mounted) {
                            setState(() {
                              _hasEnrollment = false;
                              _message = 'Biometric vault reset.';
                            });
                          }
                        })
                      : null,
                  child: const Text(
                    'Owner: Reset local biometric vault',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Return to Manual Attendance Register'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigureOutletGeofenceDialog extends StatefulWidget {
  const _ConfigureOutletGeofenceDialog({
    required this.initialGeofence,
    required this.geofenceService,
    required this.outletId,
    required this.businessId,
    required this.uid,
  });

  final OutletGeofence? initialGeofence;
  final GeofenceService geofenceService;
  final String outletId;
  final String businessId;
  final String uid;

  @override
  State<_ConfigureOutletGeofenceDialog> createState() =>
      _ConfigureOutletGeofenceDialogState();
}

class _ConfigureOutletGeofenceDialogState
    extends State<_ConfigureOutletGeofenceDialog> {
  late final TextEditingController _latCtrl;
  late final TextEditingController _lonCtrl;
  late final TextEditingController _radiusCtrl;
  String? _statusMsg;
  bool _fetchingGps = false;

  @override
  void initState() {
    super.initState();
    _latCtrl = TextEditingController(
      text: widget.initialGeofence?.latitude.toString() ?? '',
    );
    _lonCtrl = TextEditingController(
      text: widget.initialGeofence?.longitude.toString() ?? '',
    );
    _radiusCtrl = TextEditingController(
      text: (widget.initialGeofence?.radiusMeters ?? 100.0).toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configure Outlet Geofence'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Define the geographic perimeter for mobile attendance. Attendance marked outside this radius will be flagged for manager review.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _latCtrl,
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g. 22.572646',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lonCtrl,
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g. 88.363895',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _radiusCtrl,
              decoration: const InputDecoration(
                labelText: 'Geofence Radius (meters)',
                hintText: 'Default: 100',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            if (_statusMsg != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _statusMsg!,
                  style: TextStyle(
                    fontSize: 12,
                    color: _statusMsg!.contains('failed') ||
                            _statusMsg!.contains('Please enter')
                        ? Colors.red
                        : Colors.green,
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _fetchingGps
                  ? null
                  : () async {
                      setState(() {
                        _fetchingGps = true;
                        _statusMsg = 'Acquiring GPS location...';
                      });
                      try {
                        final loc = await widget.geofenceService
                            .getCurrentLocation(forceFresh: true);
                        _latCtrl.text = loc.latitude.toStringAsFixed(6);
                        _lonCtrl.text = loc.longitude.toStringAsFixed(6);
                        if (mounted) {
                          setState(() {
                            _statusMsg =
                                'Location acquired (Accuracy: ±${loc.accuracy.toStringAsFixed(1)}m, Mock: ${loc.isMock})';
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _statusMsg = 'GPS acquisition failed: $e';
                          });
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _fetchingGps = false;
                          });
                        }
                      }
                    },
              icon: _fetchingGps
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Use Current Device GPS'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final lat = double.tryParse(_latCtrl.text.trim());
            final lon = double.tryParse(_lonCtrl.text.trim());
            final radius = double.tryParse(_radiusCtrl.text.trim()) ?? 100.0;
            if (lat == null ||
                lon == null ||
                lat < -90 ||
                lat > 90 ||
                lon < -180 ||
                lon > 180) {
              setState(() {
                _statusMsg =
                    'Please enter valid latitude (-90 to 90) and longitude (-180 to 180).';
              });
              return;
            }
            await widget.geofenceService.saveOutletGeofence(
              outletId: widget.outletId,
              businessId: widget.businessId,
              latitude: lat,
              longitude: lon,
              radiusMeters: radius,
              configuredBy: widget.uid,
            );
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Save Geofence'),
        ),
      ],
    );
  }
}

class _ManageDeviceBindingDialog extends StatefulWidget {
  const _ManageDeviceBindingDialog({
    required this.employee,
    required this.initialRegistration,
    required this.currentDeviceId,
    required this.deviceRegistrationService,
    required this.isOwnerOrManager,
    required this.uid,
  });

  final EmployeeModel employee;
  final EmployeeDeviceRegistration? initialRegistration;
  final String currentDeviceId;
  final DeviceRegistrationService deviceRegistrationService;
  final bool isOwnerOrManager;
  final String uid;

  @override
  State<_ManageDeviceBindingDialog> createState() =>
      _ManageDeviceBindingDialogState();
}

class _ManageDeviceBindingDialogState extends State<_ManageDeviceBindingDialog> {
  late EmployeeDeviceRegistration? _reg;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _reg = widget.initialRegistration;
  }

  @override
  Widget build(BuildContext context) {
    final reg = _reg;
    final status = reg?.status ?? 'NOT_REGISTERED';
    final isCurrentDevice = reg?.deviceId == widget.currentDeviceId;
    return AlertDialog(
      title: Text('Device Binding: ${widget.employee.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee ID: ${widget.employee.employeeId}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'Current Device ID:\n${widget.currentDeviceId}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.blueGrey,
                fontFamily: 'monospace',
              ),
            ),
            const Divider(height: 20),
            Text(
              'Registration Status: $status',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: status == 'APPROVED'
                    ? Colors.green
                    : (status == 'PENDING' ? Colors.orange : Colors.grey),
              ),
            ),
            if (reg != null) ...[
              const SizedBox(height: 4),
              Text(
                'Bound Device ID: ${reg.deviceId}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
              Text(
                'Model: ${reg.deviceModel} • Keystore Protected: ${reg.keystoreProtected}',
                style: const TextStyle(fontSize: 11),
              ),
              if (reg.approvedBy != null)
                Text(
                  'Approved by: ${reg.approvedBy}',
                  style: const TextStyle(fontSize: 11, color: Colors.green),
                ),
              if (!isCurrentDevice)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Notice: This phone is NOT the registered device. Attendance from this phone will be flagged as DEVICE_MISMATCH.',
                    style: TextStyle(fontSize: 11, color: Colors.brown),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Optional device registration binds attendance to approved Android hardware. If unregistered, attendance proceeds with an audit flag.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('Close'),
        ),
        if (reg == null || reg.status == 'REVOKED' || !isCurrentDevice)
          FilledButton(
            onPressed: () async {
              await widget.deviceRegistrationService.registerDevice(
                employeeId: widget.employee.employeeId,
                deviceId: widget.currentDeviceId,
                autoApprove: widget.isOwnerOrManager,
                approvedBy: widget.uid,
              );
              final updated = await widget.deviceRegistrationService
                  .getRegistration(widget.employee.employeeId);
              if (mounted) {
                setState(() {
                  _reg = updated;
                  _changed = true;
                });
              }
            },
            child: Text(
              widget.isOwnerOrManager
                  ? 'Register & Approve This Device'
                  : 'Register This Device',
            ),
          ),
        if (reg != null && reg.status == 'PENDING' && widget.isOwnerOrManager)
          FilledButton(
            onPressed: () async {
              await widget.deviceRegistrationService.approveDevice(
                employeeId: widget.employee.employeeId,
                approvedBy: widget.uid,
              );
              final updated = await widget.deviceRegistrationService
                  .getRegistration(widget.employee.employeeId);
              if (mounted) {
                setState(() {
                  _reg = updated;
                  _changed = true;
                });
              }
            },
            child: const Text('Approve Device'),
          ),
        if (reg != null && reg.status != 'REVOKED' && widget.isOwnerOrManager)
          TextButton(
            onPressed: () async {
              await widget.deviceRegistrationService.revokeDevice(
                employeeId: widget.employee.employeeId,
                revokedBy: widget.uid,
              );
              final updated = await widget.deviceRegistrationService
                  .getRegistration(widget.employee.employeeId);
              if (mounted) {
                setState(() {
                  _reg = updated;
                  _changed = true;
                });
              }
            },
            child: const Text(
              'Revoke Binding',
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }
}

class _FlaggedAttendanceReviewDialog extends StatefulWidget {
  const _FlaggedAttendanceReviewDialog({
    required this.scope,
    required this.staffAttendanceRepository,
    required this.staff,
    required this.isManager,
    required this.onApprove,
    required this.idToken,
  });

  final AppContext scope;
  final StaffAttendanceRepository staffAttendanceRepository;
  final List<EmployeeModel> staff;
  final bool isManager;
  final Future<void> Function(String attendanceId) onApprove;
  final String idToken;

  @override
  State<_FlaggedAttendanceReviewDialog> createState() =>
      _FlaggedAttendanceReviewDialogState();
}

class _FlaggedAttendanceReviewDialogState
    extends State<_FlaggedAttendanceReviewDialog> {
  List<Map<String, dynamic>> _flaggedRows = [];
  bool _loading = true;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _fetchRows();
  }

  Future<void> _fetchRows() async {
    try {
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: 30));
      final rows = await widget.staffAttendanceRepository.listAttendance(
        tenantId: widget.scope.ownerUid,
        businessId: widget.scope.businessId!,
        outletId: widget.scope.outletId,
        from: from,
        through: now.add(const Duration(days: 1)),
        token: widget.idToken,
      );
      final filtered = rows
          .where((r) =>
              r['approvalStatus'] == 'PENDING' &&
              (r['requiresManagerReview'] == true ||
                  (r['fraudFlags'] != null &&
                      (r['fraudFlags'] as List).isNotEmpty) ||
                  r['verificationStatus'] == 'FLAGGED_FOR_REVIEW'))
          .toList();
      if (mounted) {
        setState(() {
          _flaggedRows = filtered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Manager Review: Flagged Attendance',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            : _flaggedRows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No flagged attendance events requiring review.\nAll recent attendance passed geofence and anti-fraud checks.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.green),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _flaggedRows.length,
                    separatorBuilder: (context, _) => const Divider(),
                    itemBuilder: (context, idx) {
                      final row = _flaggedRows[idx];
                      final empId = row['employeeId']?.toString() ?? '';
                      final empName = widget.staff
                              .where((e) => e.employeeId == empId)
                              .firstOrNull
                              ?.name ??
                          empId;
                      final attId = row['attendanceId']?.toString() ?? '';
                      final workDate =
                          row['workDate']?.toString().split('T').first ?? '';
                      final flags = (row['fraudFlags'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          [];
                      final checkIn = row['checkInAt']?.toString() ?? '';
                      final dist = row['geofenceDistanceMeters'] != null
                          ? '${(row['geofenceDistanceMeters'] as num).toStringAsFixed(1)}m'
                          : 'N/A';
                      final radius = row['geofenceRadiusMeters'] != null
                          ? '${(row['geofenceRadiusMeters'] as num).toStringAsFixed(0)}m'
                          : '100m';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                empName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'FLAGGED',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Date: $workDate • ID: $empId',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          if (checkIn.isNotEmpty)
                            Text('Check-in: $checkIn',
                                style: const TextStyle(fontSize: 11)),
                          Text('Distance: $dist (Allowed: $radius)',
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: flags
                                .map((f) => Chip(
                                      label: Text(f,
                                          style: const TextStyle(
                                              fontSize: 10, color: Colors.red)),
                                      backgroundColor: Colors.red.shade50,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: EdgeInsets.zero,
                                    ))
                                .toList(),
                          ),
                          if (widget.isManager) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () async {
                                    await widget.onApprove(attId);
                                    _changed = true;
                                    setState(() => _loading = true);
                                    await _fetchRows();
                                  },
                                  style: FilledButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('Approve (Override Flag)'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RevokeByIdDialog extends StatefulWidget {
  const _RevokeByIdDialog();

  @override
  State<_RevokeByIdDialog> createState() => _RevokeByIdDialogState();
}

class _RevokeByIdDialogState extends State<_RevokeByIdDialog> {
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Withdraw a former employee’s enrollment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter the stable employee ID. Only templates and photos for the current tenant, business and outlet are removed.',
          ),
          TextField(
            controller: _input,
            decoration: const InputDecoration(labelText: 'Employee ID'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _input.text.trim()),
          child: const Text('Withdraw / delete'),
        ),
      ],
    );
  }
}

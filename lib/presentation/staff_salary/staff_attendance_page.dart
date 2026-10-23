import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/employee_model.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import 'face_attendance_page.dart';

/// Modern, professional Staff Attendance & Approvals dashboard.
///
/// Enforces:
/// 1. Exactly one check-in and one check-out per employee per day.
/// 2. Clear visual lifecycle: Not Clocked In -> Active Shift -> Shift Completed (Locked).
/// 3. Dedicated Admin/Owner Approval Panel with 1-click batch approval and exceptions review.
class StaffAttendancePage extends StatefulWidget {
  const StaffAttendancePage({
    super.key,
    required this.controller,
    this.initialTab = 0,
  });
  final AppController controller;
  final int initialTab;

  @override
  State<StaffAttendancePage> createState() => _StaffAttendancePageState();
}

class _StaffAttendancePageState extends State<StaffAttendancePage>
    with SingleTickerProviderStateMixin {
  AppController get c => widget.controller;

  late final TabController _tabController;
  DateTime _date = DateTime.now();
  DateTime _approvalMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  List<Map<String, dynamic>> _monthlyRows = const [];
  List<EmployeeModel> _employees = const [];
  bool _employeesLoaded = false;
  bool _loading = false;
  bool _saving = false;
  bool _approving = false;
  String? _error;

  String _searchQuery = '';
  String _approvalFilter = 'PENDING'; // 'PENDING', 'APPROVED', 'ALL'
  String _statusFilter = 'ALL'; // 'ALL', 'ACTIVE', 'COMPLETED', 'NOT_MARKED', 'LEAVE'
  String? _approvalOutletFilter; // null = All Outlets

  String? get _outlet => c.appContext?.outletId;
  bool get _canApprove => c.canApproveStaffAttendance();
  bool get _canManage => c.canManageStaffAttendance();
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool _canClock(EmployeeModel emp) {
    if (_canManage) return true;
    final myId = c.appContext?.employeeId ?? c.employee?.employeeId;
    return myId != null && myId == emp.employeeId;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    if (c.appContext?.accountType == 'employee') {
      _approvalFilter = 'ALL';
    }
    _loadEmployees();
    _load();
  }

  @override
  void didUpdateWidget(covariant StaffAttendancePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _tabController.animateTo(widget.initialTab.clamp(0, 1));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _loadingEmployees = false;
  Future<void> _loadEmployees() async {
    if (_loadingEmployees) return;
    if (c.employees.isNotEmpty) {
      if (mounted) {
        setState(() {
          _employees = c.employees;
          _employeesLoaded = true;
        });
      }
      return;
    }
    _loadingEmployees = true;
    try {
      if (c.appContext?.accountType == 'owner') {
        if (c.activeRoles.isEmpty && !c.employeeMastersLoading) {
          await c.loadEmployeeMasters();
        }
        await c.loadEmployees();
        if (!mounted) return;
        setState(() {
          _employees = c.employeesError == null ? c.employees : const [];
          _employeesLoaded = true;
          if (c.employeesError != null) _error = c.employeesError;
        });
        return;
      }
      final employees = await c.loadStaffKhataEmployees();
      final effective = <EmployeeModel>[...employees];
      if (c.employee != null &&
          !effective.any((e) => e.employeeId == c.employee!.employeeId)) {
        effective.add(c.employee!);
      }
      if (mounted) {
        setState(() {
          _employees = effective;
          _employeesLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _employeesLoaded = true;
        });
      }
    } finally {
      _loadingEmployees = false;
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    if (c.appContext?.businessId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Determine date range spanning both selected daily date and approval month
      final firstDay = DateTime(
        _date.year < _approvalMonth.year ||
                (_date.year == _approvalMonth.year &&
                    _date.month <= _approvalMonth.month)
            ? _date.year
            : _approvalMonth.year,
        _date.year == _approvalMonth.year
            ? (_date.month < _approvalMonth.month
                ? _date.month
                : _approvalMonth.month)
            : (_date.year < _approvalMonth.year
                ? _date.month
                : _approvalMonth.month),
        1,
      );
      final lastDay = DateTime(
        _date.year > _approvalMonth.year ||
                (_date.year == _approvalMonth.year &&
                    _date.month >= _approvalMonth.month)
            ? _date.year
            : _approvalMonth.year,
        _date.year == _approvalMonth.year
            ? (_date.month > _approvalMonth.month
                ? _date.month + 1
                : _approvalMonth.month + 1)
            : (_date.year > _approvalMonth.year
                ? _date.month + 1
                : _approvalMonth.month + 1),
        0,
        23,
        59,
        59,
      );

      final rows = await c.loadStaffAttendance(
        from: firstDay,
        through: lastDay,
        employeeId: null,
        allOutlets: true, // Fetch across all outlets for comprehensive management & approval
      );
      if (mounted) {
        setState(() {
          _monthlyRows = rows;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Attendance Record Helpers ---

  List<EmployeeModel> get _outletEmployees {
    final list = _employeesLoaded ? _employees : c.employees;
    final all = <EmployeeModel>[
      ...list,
      if (c.employee != null &&
          !list.any((e) => e.employeeId == c.employee!.employeeId))
        c.employee!,
    ];
    if (c.appContext?.accountType == 'employee') {
      final myId = c.appContext?.employeeId ?? c.employee?.employeeId;
      final myEmployees = all.where((e) => e.employeeId == myId).toList();
      if (myEmployees.isNotEmpty) return myEmployees;
      if (c.employee != null) return [c.employee!];
      if (myId != null) {
        return [
          EmployeeModel(
            employeeId: myId,
            uid: c.appContext?.uid ?? '',
            ownerUid: c.appContext?.ownerUid ?? '',
            name: c.user?.name ?? 'My Attendance',
            email: c.user?.email ?? '',
            status: 'active',
            businessIds: [c.appContext?.businessId ?? ''],
            outletIds: [c.appContext?.outletId ?? ''],
            roleIds: const [],
          ),
        ];
      }
    }
    return all.where((e) {
      final matchesBusiness = c.appContext?.businessId == null ||
          e.businessIds.isEmpty ||
          e.businessIds.contains(c.appContext?.businessId);
      final matchesOutlet = _outlet == null ||
          e.outletIds.isEmpty ||
          e.outletIds.contains(_outlet);
      return e.isActive && matchesBusiness && matchesOutlet;
    }).toList();
  }

  Map<String, dynamic>? _getDailyRecord(String employeeId, DateTime date) {
    return _monthlyRows.where((row) {
      if (row['employeeId']?.toString() != employeeId) return false;
      final workDate = _parseDate(row['workDate']);
      return workDate != null &&
          workDate.year == date.year &&
          workDate.month == date.month &&
          workDate.day == date.day;
    }).firstOrNull;
  }

  DateTime? _parseDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toLocal();
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '--:--';
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  String _formatMinutes(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  // --- Clock In & Clock Out Actions (Strict Once-a-Day Enforcement) ---

  Future<void> _clockIn(EmployeeModel employee) async {
    final existing = _getDailyRecord(employee.employeeId, _date);
    if (existing != null && existing['checkInAt'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)?.attendanceCheckInRecorded ?? 'Attendance check-in is already recorded for today.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await c.saveStaffAttendance(
        employeeId: employee.employeeId,
        workDate: _date,
        status: 'PRESENT',
        checkIn: DateTime.now(),
        checkOut: null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Clocked in ${employee.name} at ${_formatTime(DateTime.now())}'),
              ],
            ),
            backgroundColor: const Color(0xFF0D9488),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clockOut(EmployeeModel employee, Map<String, dynamic> record) async {
    final checkIn = _parseDate(record['checkInAt']);
    if (checkIn == null) {
      if (mounted) setState(() => _error = 'Cannot check out without check-in.');
      return;
    }
    if (record['checkOutAt'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)?.checkoutCompletedToday ?? 'Checkout is already completed for today. Only 1 checkout allowed per day.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final now = DateTime.now();
    final isEarly = now.isBefore(checkIn.add(const Duration(minutes: 480)));
    var earlyReason = '';

    if (isEarly) {
      final controller = TextEditingController();
      final workedMins = now.difference(checkIn).inMinutes;
      final dialogResult = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
              ),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context)?.earlyCheckoutNotice ?? 'Early Checkout Notice'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${employee.name} has worked ${_formatMinutes(workedMins)} (standard shift is 8 hours).',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please provide a mandatory reason for checking out before the 8-hour shift ends:',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Reason for early departure *',
                  hintText: 'e.g., Medical appointment, personal emergency...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Confirm Checkout'),
            ),
          ],
        ),
      );
      controller.dispose();

      if (dialogResult == null || dialogResult.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('A valid reason is required for early checkout.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
      earlyReason = dialogResult;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await c.saveStaffAttendance(
        employeeId: employee.employeeId,
        workDate: _date,
        status: record['attendanceStatus']?.toString() ?? 'PRESENT',
        checkIn: checkIn,
        checkOut: now,
        earlyCheckoutReason: earlyReason.isNotEmpty ? earlyReason : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('Shift completed for ${employee.name}. Checkout recorded at ${_formatTime(now)}.'),
              ],
            ),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markLeaveStatus(EmployeeModel employee, String status, {bool includeOffDay = false}) async {
    final existing = _getDailyRecord(employee.employeeId, _date);
    if (existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Attendance is already recorded for this employee today.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await c.saveStaffAttendance(
        employeeId: employee.employeeId,
        workDate: _date,
        status: status,
        includeOffDayAsPaidWork: includeOffDay,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${employee.name} marked as $status.'),
            backgroundColor: const Color(0xFF475569),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // --- Approval Panel Actions ---

  Future<void> _approveSingle(Map<String, dynamic> row) async {
    final attendanceId = row['attendanceId']?.toString();
    if (attendanceId == null) return;

    setState(() => _approving = true);
    try {
      await c.approveStaffAttendance(
        attendanceId,
        standardShiftMinutes: 480,
        halfDayPayableUnitsMilli: 500,
        overtimeRatePaisePerHour: 0,
        overtimeMultiplierBasisPoints: 10000,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance approved successfully!'),
            backgroundColor: Color(0xFF16A34A),
            duration: Duration(seconds: 2),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _openSetCheckoutDialog(Map<String, dynamic> row) async {
    final checkIn = _parseDate(row['checkInAt']);
    final initialTime = checkIn != null
        ? TimeOfDay.fromDateTime(checkIn.add(const Duration(hours: 8)))
        : const TimeOfDay(hour: 17, minute: 0);

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Record Shift Check-out Time',
    );
    if (pickedTime == null) return;

    final workDate = _parseDate(row['workDate']) ?? DateTime.now();
    final checkOutDateTime = DateTime(
      workDate.year,
      workDate.month,
      workDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() => _approving = true);
    try {
      final empId = row['employeeId']?.toString() ?? '';
      await c.saveStaffAttendance(
        employeeId: empId,
        workDate: workDate,
        status: 'PRESENT',
        checkIn: checkIn,
        checkOut: checkOutDateTime,
      );
      final attendanceId = row['attendanceId']?.toString();
      if (attendanceId != null) {
        await c.approveStaffAttendance(
          attendanceId,
          standardShiftMinutes: 480,
          halfDayPayableUnitsMilli: 500,
          overtimeRatePaisePerHour: 0,
          overtimeMultiplierBasisPoints: 10000,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checkout recorded and attendance approved!'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _openCustomApproveDialog(Map<String, dynamic> row) async {
    final rateController = TextEditingController();
    final multiplierController = TextEditingController(text: '1.0');
    final shiftMinutesController = TextEditingController(text: '480');
    final halfDayUnitsController = TextEditingController(text: '500');

    final values = await showDialog<(String, String, String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Approve with Custom Wage Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Overtime Rate per Hour (₹)',
                  helperText: 'Leave empty for ₹0 (no extra overtime pay)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: multiplierController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Overtime Multiplier (1.0 = standard, 1.5 = 1.5x)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: shiftMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Standard Shift Minutes (Default: 480 / 8h)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: halfDayUnitsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Half-Day Payable Units (Default: 500 = 0.5 day)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              rateController.text.trim(),
              multiplierController.text.trim(),
              shiftMinutesController.text.trim(),
              halfDayUnitsController.text.trim(),
            )),
            child: const Text('Authorize & Approve'),
          ),
        ],
      ),
    );

    if (values == null) return;
    final (rateStr, multStr, shiftStr, halfStr) = values;
    final parsedRate = rateStr.isEmpty ? 0.0 : double.tryParse(rateStr);
    final parsedMultiplier = double.tryParse(multStr) ?? 1.0;
    final shiftMinutes = int.tryParse(shiftStr) ?? 480;
    final halfDayUnits = int.tryParse(halfStr) ?? 500;

    if (parsedRate == null || parsedRate < 0 || shiftMinutes <= 0 || halfDayUnits < 0 || halfDayUnits > 1000) {
      if (mounted) setState(() => _error = 'Please enter valid overtime settings.');
      return;
    }

    setState(() => _approving = true);
    try {
      await c.approveStaffAttendance(
        row['attendanceId'].toString(),
        standardShiftMinutes: shiftMinutes,
        halfDayPayableUnitsMilli: halfDayUnits,
        overtimeRatePaisePerHour: (parsedRate * 100).round(),
        overtimeMultiplierBasisPoints: (parsedMultiplier * 10000).round(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance approved with custom overtime settings.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _approveAllPending() async {
    final pendingRows = _filteredApprovalRows.where((r) => r['approvalStatus'] == 'PENDING').toList();
    if (pendingRows.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.done_all_rounded, color: Color(0xFF0284C7)),
            const SizedBox(width: 10),
            Text('Approve ${pendingRows.length} Attendances?'),
          ],
        ),
        content: Text(
          'This will authorize all ${pendingRows.length} pending attendance records with standard 8-hour shift rules and immediately qualify them for payroll calculation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.verified),
            label: Text('Approve All (${pendingRows.length})'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _approving = true);
    final ids = pendingRows.map((r) => r['attendanceId'].toString()).toList();
    try {
      final approvedCount = await c.approveAllStaffAttendance(ids);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully approved $approvedCount attendance record(s)!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  List<Map<String, dynamic>> get _filteredApprovalRows {
    final isEmployee = c.appContext?.accountType == 'employee';
    final myId = c.appContext?.employeeId ?? c.employee?.employeeId;
    return _monthlyRows.where((row) {
      if (isEmployee && myId != null && row['employeeId']?.toString() != myId) {
        return false;
      }
      final workDate = _parseDate(row['workDate']);
      if (workDate == null) return false;
      final inMonth = workDate.year == _approvalMonth.year && workDate.month == _approvalMonth.month;
      if (!inMonth) return false;

      final status = row['approvalStatus']?.toString() ?? 'PENDING';
      if (_approvalFilter == 'PENDING' && status != 'PENDING') return false;
      if (_approvalFilter == 'APPROVED' && status != 'APPROVED') return false;

      if (_approvalOutletFilter != null &&
          row['outletId']?.toString() != _approvalOutletFilter) {
        return false;
      }

      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final empId = row['employeeId']?.toString();
        final emp = _employees.where((e) => e.employeeId == empId).firstOrNull ??
            c.employees.where((e) => e.employeeId == empId).firstOrNull;
        final name = emp?.name.toLowerCase() ?? '';
        final code = emp?.employeeCode?.toLowerCase() ?? '';
        if (!name.contains(query) && !code.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    if (!c.canViewStaffAttendance()) {
      return const Scaffold(
        body: Center(
          child: Text('Attendance permission is required to view this page.'),
        ),
      );
    }

    final pendingCount = _monthlyRows.where((r) {
      final workDate = _parseDate(r['workDate']);
      return workDate != null &&
          workDate.year == _approvalMonth.year &&
          workDate.month == _approvalMonth.month &&
          r['approvalStatus'] == 'PENDING';
    }).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Staff Attendance & Approvals',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        actions: [
          if (_isMobile)
            IconButton(
              tooltip: 'Face attendance and enrollment',
              icon: const Icon(Icons.face_retouching_natural),
              onPressed: (_loading || _saving || _approving)
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FaceAttendancePage(controller: c),
                        ),
                      );
                      if (mounted) await _load();
                    },
            ),
          if (_loading || _saving || _approving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Refresh attendance data',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: (_loading || _saving || _approving) ? null : () => _load(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF0284C7),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF0284C7),
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
              tabs: [
                const Tab(
                  icon: Icon(Icons.schedule_rounded),
                  text: 'Daily Shift Register',
                ),
                Tab(
                  icon: Badge(
                    isLabelVisible: pendingCount > 0,
                    label: Text(
                      pendingCount.toString(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: const Color(0xFFEA580C),
                    child: const Icon(Icons.verified_user_rounded),
                  ),
                  text: c.appContext?.accountType == 'employee'
                      ? 'Attendance History'
                      : 'Approval Panel',
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _error = null),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDailyRegisterTab(),
                _buildApprovalPanelTab(pendingCount),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: DAILY REGISTER ---

  Widget _buildDailyRegisterTab() {
    final baseEmployees = _outletEmployees;
    final knownEmployeeIds = baseEmployees.map((e) => e.employeeId).toSet();
    final extraEmployees = <EmployeeModel>[];
    for (final row in _monthlyRows) {
      final workDate = _parseDate(row['workDate']);
      if (workDate != null &&
          workDate.year == _date.year &&
          workDate.month == _date.month &&
          workDate.day == _date.day) {
        final id = row['employeeId']?.toString();
        if (id != null && !knownEmployeeIds.contains(id)) {
          final existing = _employees.where((e) => e.employeeId == id).firstOrNull ??
              c.employees.where((e) => e.employeeId == id).firstOrNull;
          if (existing != null) {
            extraEmployees.add(existing);
            knownEmployeeIds.add(id);
          } else {
            extraEmployees.add(EmployeeModel(
              employeeId: id,
              uid: row['recordedBy']?.toString() ?? '',
              ownerUid: c.appContext?.ownerUid ?? '',
              name: row['employeeName']?.toString() ?? id,
              email: '',
              status: 'active',
              businessIds: [c.appContext?.businessId ?? ''],
              outletIds: [row['outletId']?.toString() ?? ''],
              roleIds: const [],
            ));
            knownEmployeeIds.add(id);
          }
        }
      }
    }
    final employees = [...baseEmployees, ...extraEmployees];
    final isToday = _date.year == DateTime.now().year &&
        _date.month == DateTime.now().month &&
        _date.day == DateTime.now().day;

    // Calculate daily metrics
    var activeNow = 0;
    var completedShifts = 0;
    var onLeaveOrOff = 0;
    var notMarked = 0;

    for (final emp in employees) {
      final rec = _getDailyRecord(emp.employeeId, _date);
      if (rec == null) {
        notMarked++;
      } else if (rec['checkInAt'] != null && rec['checkOutAt'] == null) {
        activeNow++;
      } else if (rec['checkInAt'] != null && rec['checkOutAt'] != null) {
        completedShifts++;
      } else {
        onLeaveOrOff++;
      }
    }

    // Filter employees by status and search
    final filtered = employees.where((emp) {
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final name = emp.name.toLowerCase();
        final code = emp.employeeCode?.toLowerCase() ?? '';
        if (!name.contains(q) && !code.contains(q)) return false;
      }
      final rec = _getDailyRecord(emp.employeeId, _date);
      if (_statusFilter == 'ACTIVE') {
        return rec != null && rec['checkInAt'] != null && rec['checkOutAt'] == null;
      }
      if (_statusFilter == 'COMPLETED') {
        return rec != null && rec['checkInAt'] != null && rec['checkOutAt'] != null;
      }
      if (_statusFilter == 'NOT_MARKED') {
        return rec == null;
      }
      if (_statusFilter == 'LEAVE') {
        return rec != null && rec['checkInAt'] == null;
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // 0. Face Attendance Quick Punch Banner (Mobile Only)
          if (_isMobile) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
              ),
              color: const Color(0xFFF0F9FF),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.face_retouching_natural, color: Color(0xFF0284C7), size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Face Attendance Punch / ফেস উপস্থিতি পাঞ্চ',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Use phone camera to punch check-in or checkout with AI face recognition',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FaceAttendancePage(controller: c),
                          ),
                        );
                        if (mounted) await _load();
                      },
                      icon: const Icon(Icons.videocam_rounded, size: 18),
                      label: const Text('Open Face Punch'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          // 1. Date Navigator Bar
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Previous day',
                    onPressed: () {
                      setState(() => _date = _date.subtract(const Duration(days: 1)));
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => _date = picked);
                          await _load();
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isToday)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'TODAY',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF0284C7),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              _fullDateLabel(_date),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next day',
                    onPressed: () {
                      setState(() => _date = _date.add(const Duration(days: 1)));
                      _load();
                    },
                  ),
                  const SizedBox(width: 8),
                  if (!isToday)
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _date = DateTime.now());
                        _load();
                      },
                      icon: const Icon(Icons.today, size: 16),
                      label: const Text('Today'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Metric Ribbon Cards (4 Stats)
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final cards = [
                _buildStatCard('Total Staff', employees.length.toString(), Icons.people_outline, const Color(0xFF475569)),
                _buildStatCard('On Duty (Active)', activeNow.toString(), Icons.timer_outlined, const Color(0xFF0284C7)),
                _buildStatCard('Completed Shifts', completedShifts.toString(), Icons.verified_outlined, const Color(0xFF16A34A)),
                _buildStatCard('Leave / Off / Absent', onLeaveOrOff.toString(), Icons.event_busy_outlined, const Color(0xFF9333EA)),
              ];
              if (isWide) {
                return Row(
                  children: cards.map((card) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: card))).toList(),
                );
              }
              return Column(
                children: [
                  Row(children: [Expanded(child: cards[0]), const SizedBox(width: 8), Expanded(child: cards[1])]),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: cards[2]), const SizedBox(width: 8), Expanded(child: cards[3])]),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // 3. Search and Status Filters
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search employee...',
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              FilterChip(
                selected: _statusFilter == 'ALL',
                label: Text('All (${employees.length})'),
                onSelected: (_) => setState(() => _statusFilter = 'ALL'),
              ),
              FilterChip(
                selected: _statusFilter == 'ACTIVE',
                label: Text('Active ($activeNow)'),
                onSelected: (_) => setState(() => _statusFilter = 'ACTIVE'),
              ),
              FilterChip(
                selected: _statusFilter == 'COMPLETED',
                label: Text('Completed ($completedShifts)'),
                onSelected: (_) => setState(() => _statusFilter = 'COMPLETED'),
              ),
              FilterChip(
                selected: _statusFilter == 'NOT_MARKED',
                label: Text('Not Clocked ($notMarked)'),
                onSelected: (_) => setState(() => _statusFilter = 'NOT_MARKED'),
              ),
              FilterChip(
                selected: _statusFilter == 'LEAVE',
                label: Text('Leave / Off ($onLeaveOrOff)'),
                onSelected: (_) => setState(() => _statusFilter = 'LEAVE'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4. Employee Attendance List (Enforcing strict once-per-day lifecycle)
          if (filtered.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No employees found for this filter or outlet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            ),
          for (final emp in filtered)
            _buildEmployeeAttendanceCard(emp),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeAttendanceCard(EmployeeModel emp) {
    final record = _getDailyRecord(emp.employeeId, _date);
    final checkIn = _parseDate(record?['checkInAt']);
    final checkOut = _parseDate(record?['checkOutAt']);
    final status = record?['attendanceStatus']?.toString();
    final approvalStatus = record?['approvalStatus']?.toString();
    final earlyReason = record?['earlyCheckoutReason']?.toString();

    // Check states:
    // State 1: Not Marked
    final isNotMarked = record == null;
    // State 2: Active Shift (Check-in done, checkout pending)
    final isActiveShift = record != null && checkIn != null && checkOut == null;
    // State 3: Completed (Both check-in and checkout done -> LOCKED FOR TODAY)
    final isCompleted = record != null && checkIn != null && checkOut != null;
    // State 4: Other (e.g. Leave / Absent without timestamps)
    final isLeave = record != null && checkIn == null;

    final workedMinutes = (record?['workedMinutes'] as num?)?.toInt() ??
        (checkIn != null && checkOut != null
            ? checkOut.difference(checkIn).inMinutes
            : (checkIn != null ? DateTime.now().difference(checkIn).inMinutes : 0));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActiveShift
              ? const Color(0xFF38BDF8)
              : (isCompleted ? const Color(0xFF86EFAC) : Colors.grey.shade200),
          width: isActiveShift || isCompleted ? 1.5 : 1.0,
        ),
      ),
      color: isActiveShift ? const Color(0xFFF0F9FF) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Avatar, Name, Role, and Lifecycle Badge
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF0F172A),
                  radius: 20,
                  child: Text(
                    _initial(emp.name),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              emp.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _roleLabel(emp),
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      if (emp.mobile != null && emp.mobile!.isNotEmpty)
                        Text(
                          emp.mobile!,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),
                // Lifecycle State Chip
                if (isActiveShift)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_filled, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'IN SHIFT',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                else if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'COMPLETED',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                else if (isLeave)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9333EA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status ?? 'LEAVE',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'NOT CLOCKED',
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),

            // Middle Section: Time details and notices
            if (isActiveShift) ...[
              Row(
                children: [
                  const Icon(Icons.login, size: 16, color: Color(0xFF0284C7)),
                  const SizedBox(width: 6),
                  Text(
                    'Checked in at ${_formatTime(checkIn)}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    'Current Duration: ${_formatMinutes(workedMinutes)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF0284C7)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '• Active shift in progress. Check-in is recorded and locked for today.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ] else if (isCompleted) ...[
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.login, size: 16, color: Color(0xFF16A34A)),
                      const SizedBox(width: 4),
                      Text('In: ${_formatTime(checkIn)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.logout, size: 16, color: Color(0xFFEA580C)),
                      const SizedBox(width: 4),
                      Text('Out: ${_formatTime(checkOut)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 16, color: Color(0xFF475569)),
                      const SizedBox(width: 4),
                      Text('Total: ${_formatMinutes(workedMinutes)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: approvalStatus == 'APPROVED' ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: approvalStatus == 'APPROVED' ? Colors.green.shade200 : Colors.amber.shade200),
                    ),
                    child: Text(
                      approvalStatus == 'APPROVED' ? '✓ Approved' : '⏳ Pending Approval',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: approvalStatus == 'APPROVED' ? Colors.green.shade800 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              if (earlyReason != null && earlyReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade800, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Early departure reason: "$earlyReason"',
                          style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '• Shift closed. Check-in and checkout can only be recorded once per day.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
            ] else if (isLeave) ...[
              Text(
                'Marked as $status for this date.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ] else ...[
              Text(
                'No attendance marked yet for this day.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],

            const SizedBox(height: 14),

            // Bottom Actions Bar (Strict 1-Check-in & 1-Checkout Enforced)
            Row(
              children: [
                if (isNotMarked) ...[
                  // Action 1: Clock In
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: (_saving || !_canClock(emp)) ? null : () => _clockIn(emp),
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Clock In'),
                  ),
                  if (_isMobile) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FaceAttendancePage(controller: c),
                          ),
                        );
                        if (mounted) await _load();
                      },
                      icon: const Icon(Icons.face_retouching_natural, size: 18),
                      label: const Text('Face Punch'),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // Action 2: Mark Leave / Status Dropdown Menu
                  PopupMenuButton<String>(
                    tooltip: 'Mark other attendance status',
                    onSelected: (val) {
                      if (val == 'WEEKLY_OFF_WORKED') {
                        _markLeaveStatus(emp, 'WEEKLY_OFF', includeOffDay: true);
                      } else {
                        _markLeaveStatus(emp, val);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'HALF_DAY', child: Text('Mark Half Day')),
                      const PopupMenuItem(value: 'PAID_LEAVE', child: Text('Mark Paid Leave')),
                      const PopupMenuItem(value: 'UNPAID_LEAVE', child: Text('Mark Unpaid Leave')),
                      const PopupMenuItem(value: 'WEEKLY_OFF', child: Text('Mark Weekly Off')),
                      const PopupMenuItem(value: 'WEEKLY_OFF_WORKED', child: Text('Weekly Off (Worked as Paid Day)')),
                      const PopupMenuItem(value: 'HOLIDAY', child: Text('Mark Holiday')),
                      const PopupMenuItem(value: 'ABSENT', child: Text('Mark Absent (0 Pay)')),
                    ],
                    child: OutlinedButton.icon(
                      onPressed: null, // intercepted by popup
                      icon: const Icon(Icons.more_horiz, size: 18),
                      label: const Text('Mark Status'),
                    ),
                  ),
                ] else if (isActiveShift) ...[
                  // Action: Clock Out (Active shift)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: (_saving || !_canClock(emp)) ? null : () => _clockOut(emp, record),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Clock Out'),
                  ),
                  if (_isMobile) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEA580C),
                        side: const BorderSide(color: Color(0xFFEA580C)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => FaceAttendancePage(controller: c),
                          ),
                        );
                        if (mounted) await _load();
                      },
                      icon: const Icon(Icons.face_retouching_natural, size: 18),
                      label: const Text('Face Punch Out'),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Text(
                    'Checked in ✓',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ] else if (isCompleted) ...[
                  // Both done: Permanently locked for today!
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: Colors.green.shade800),
                        const SizedBox(width: 6),
                        Text(
                          'Attendance Complete — Locked for Today',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Attendance status locked for today',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: APPROVAL PANEL (Admin / Owner Dedicated Hub) ---

  Widget _buildApprovalPanelTab(int pendingCount) {
    final rows = _filteredApprovalRows;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // 1. Month Picker & Filter Header
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: 'Previous month',
                        onPressed: () {
                          setState(() {
                            _approvalMonth = DateTime(_approvalMonth.year, _approvalMonth.month - 1, 1);
                          });
                          _load();
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_monthName(_approvalMonth.month)} ${_approvalMonth.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: 'Next month',
                        onPressed: () {
                          setState(() {
                            _approvalMonth = DateTime(_approvalMonth.year, _approvalMonth.month + 1, 1);
                          });
                          _load();
                        },
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (c.outlets.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: _approvalOutletFilter,
                              isDense: true,
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('All Outlets', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                                ...c.outlets.map(
                                  (o) => DropdownMenuItem<String?>(
                                    value: o.outletId,
                                    child: Text(o.outletName, style: const TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ],
                              onChanged: (val) => setState(() => _approvalOutletFilter = val),
                            ),
                          ),
                        ),
                      FilterChip(
                        selected: _approvalFilter == 'PENDING',
                        label: Text('Pending Approval ($pendingCount)'),
                        selectedColor: const Color(0xFFFEF3C7),
                        checkmarkColor: const Color(0xFFD97706),
                        onSelected: (_) => setState(() => _approvalFilter = 'PENDING'),
                      ),
                      FilterChip(
                        selected: _approvalFilter == 'APPROVED',
                        label: const Text('Approved'),
                        selectedColor: const Color(0xFFDCFCE7),
                        checkmarkColor: const Color(0xFF16A34A),
                        onSelected: (_) => setState(() => _approvalFilter = 'APPROVED'),
                      ),
                      FilterChip(
                        selected: _approvalFilter == 'ALL',
                        label: const Text('All Records'),
                        onSelected: (_) => setState(() => _approvalFilter = 'ALL'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Batch Action Banner (If pending records exist)
          if (pendingCount > 0 && _canApprove) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.verified_user_rounded, color: Color(0xFF38BDF8), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$pendingCount Attendance Record(s) Pending Review',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Approved attendances automatically calculate work units and unlock monthly payroll settlement.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: _approving ? null : _approveAllPending,
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Approve All Pending'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 3. Search Bar
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Filter by employee name or code...',
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // 4. Pending / Approved Records List
          if (rows.isEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade300),
                      const SizedBox(height: 12),
                      Text(
                        _approvalFilter == 'PENDING'
                            ? 'All caught up! No attendance records pending approval.'
                            : 'No attendance records found for this selection.',
                        style: TextStyle(fontSize: 15, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          for (final row in rows)
            _buildApprovalRowCard(row),
        ],
      ),
    );
  }

  Widget _buildApprovalRowCard(Map<String, dynamic> row) {
    final empId = row['employeeId']?.toString();
    final employee = _employees.where((e) => e.employeeId == empId).firstOrNull ??
        c.employees.where((e) => e.employeeId == empId).firstOrNull;
    final workDate = _parseDate(row['workDate']);
    final checkIn = _parseDate(row['checkInAt']);
    final checkOut = _parseDate(row['checkOutAt']);
    final workedMinutes = (row['workedMinutes'] as num?)?.toInt() ?? 0;
    final approvalStatus = row['approvalStatus']?.toString() ?? 'PENDING';
    final isApproved = approvalStatus == 'APPROVED';
    final earlyReason = row['earlyCheckoutReason']?.toString();
    final attendanceStatus = row['attendanceStatus']?.toString() ?? 'PRESENT';
    final hasOvertime = workedMinutes > 480;
    final isOpenShift = checkIn != null && checkOut == null;

    final outletName = c.outlets
            .where((o) => o.outletId == row['outletId'])
            .firstOrNull
            ?.outletName ??
        row['outletId'] ??
        'Main Outlet';

    final displayName = employee?.name ?? empId ?? 'Employee';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isApproved ? Colors.grey.shade200 : const Color(0xFFFDE68A),
        ),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF0F172A),
                  radius: 18,
                  child: Text(
                    _initial(displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${_fullDateLabel(workDate ?? DateTime.now())} • Outlet: $outletName',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isApproved
                        ? const Color(0xFFDCFCE7)
                        : (isOpenShift ? const Color(0xFFEFF6FF) : const Color(0xFFFEF3C7)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isApproved
                          ? const Color(0xFF86EFAC)
                          : (isOpenShift ? const Color(0xFF93C5FD) : const Color(0xFFFCD34D)),
                    ),
                  ),
                  child: Text(
                    isApproved
                        ? '✓ APPROVED'
                        : (isOpenShift ? '🕒 IN SHIFT / PENDING' : '⏳ PENDING'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isApproved
                          ? const Color(0xFF15803D)
                          : (isOpenShift ? const Color(0xFF1D4ED8) : const Color(0xFFB45309)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // In-shift warning / info banner
            if (isOpenShift) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF16A34A), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Clocked In at ${_formatTime(checkIn)}. Check-out not recorded yet. You can approve as a standard 8-hour shift, or record checkout.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF166534), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Shift metrics
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  Text('Status: $attendanceStatus', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  if (checkIn != null)
                    Text('In: ${_formatTime(checkIn)}', style: const TextStyle(fontSize: 12)),
                  if (checkOut != null)
                    Text('Out: ${_formatTime(checkOut)}', style: const TextStyle(fontSize: 12))
                  else if (checkIn != null)
                    Text(
                      'Out: Pending (${_formatMinutes(DateTime.now().toUtc().difference(checkIn.toUtc()).inMinutes)} elapsed)',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFD97706), fontWeight: FontWeight.w500),
                    ),
                  if (checkOut != null)
                    Text(
                      'Worked: ${_formatMinutes(workedMinutes)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasOvertime ? const Color(0xFF0284C7) : Colors.black87,
                      ),
                    ),
                  if (hasOvertime)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Overtime +${_formatMinutes(workedMinutes - 480)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                    ),
                ],
              ),
            ),

            if (earlyReason != null && earlyReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Early Departure Reason: "$earlyReason"',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Actions Area
            if (!isApproved) ...[
              if (_canApprove)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (isOpenShift)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _approving ? null : () => _openSetCheckoutDialog(row),
                        icon: const Icon(Icons.schedule, size: 16),
                        label: const Text('Record Checkout'),
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _approving ? null : () => _openCustomApproveDialog(row),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('Custom Settings'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _approving ? null : () => _approveSingle(row),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: Text(isOpenShift ? 'Approve Standard 8h Shift' : 'Approve'),
                    ),
                  ],
                )
              else
                Text(
                  'Approval requires owner or ATTENDANCE_APPROVE permission.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.verified, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Approved by ${row['approvedBy'] ?? 'Manager'} • Standard Shift Credited',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- Helper Formatting ---

  static String _initial(String name) =>
      name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'E';

  String _roleLabel(EmployeeModel employee) {
    if (employee.roleIds.isEmpty) return 'Staff';
    return employee.roleIds.map((id) {
      final role = c.activeRoles.where((item) => item.roleId == id).firstOrNull;
      return role?.roleName ?? id;
    }).join(', ');
  }

  static String _fullDateLabel(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  static String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}

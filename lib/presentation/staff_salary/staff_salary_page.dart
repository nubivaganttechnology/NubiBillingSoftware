import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/id_generator.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/outlet_model.dart';
import '../../data/repositories/staff_salary_repository.dart';
import '../../data/repositories/staff_attendance_repository.dart';
import '../../data/services/salary_document_service.dart';
import '../app_controller.dart';
import 'staff_attendance_page.dart';

class StaffSalaryPage extends StatefulWidget {
  const StaffSalaryPage({super.key, required this.controller, this.employeeId});
  final AppController controller;
  final String? employeeId;

  @override
  State<StaffSalaryPage> createState() => _StaffSalaryPageState();
}

class _StaffSalaryPageState extends State<StaffSalaryPage>
    with SingleTickerProviderStateMixin {
  EmployeeModel? _employee;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _entries = [];
  bool _loading = false;
  String? _error;
  String _searchStaffQuery = '';
  String _passbookFilter = 'ALL';
  String _selectedOutletFilter = 'ALL';
  String? _lastBusinessId;
  String? _lastOutletId;
  late TabController _tabController;

  AppController get c => widget.controller;
  String? get tenant => c.appContext?.ownerUid;
  String? get business => c.appContext?.businessId;
  String? get outlet => c.appContext?.outletId;
  String? get token => c.idToken;
  bool get owner => c.appContext?.accountType == 'owner';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _lastBusinessId = business;
    _lastOutletId = outlet;
    _selectedOutletFilter = outlet ?? 'ALL';
    widget.controller.addListener(_onControllerChanged);
    _initializeEmployee();
  }

  @override
  void didUpdateWidget(covariant StaffSalaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (oldWidget.employeeId != widget.employeeId &&
        widget.employeeId != null) {
      final businessEmployees = c.employees
          .where((e) => e.businessIds.contains(business))
          .toList();
      final match = businessEmployees
          .where((e) => e.employeeId == widget.employeeId)
          .firstOrNull;
      if (match != null) {
        setState(() {
          _employee = match;
          if (match.outletIds.isNotEmpty) {
            _selectedOutletFilter = match.outletIds.first;
          }
        });
        _load();
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final currentBusiness = business;
    final currentOutlet = outlet;

    if (currentBusiness != _lastBusinessId) {
      _lastBusinessId = currentBusiness;
      _lastOutletId = currentOutlet;
      _selectedOutletFilter = currentOutlet ?? 'ALL';
      _initializeEmployee();
    } else if (currentOutlet != _lastOutletId) {
      _lastOutletId = currentOutlet;
      if (currentOutlet != null && _selectedOutletFilter != 'ALL') {
        setState(() {
          _selectedOutletFilter = currentOutlet;
          final inOutlet = c.employees
              .where(
                (e) =>
                    e.businessIds.contains(business) &&
                    e.outletIds.contains(currentOutlet),
              )
              .toList();
          if (_employee == null ||
              !_employee!.outletIds.contains(currentOutlet)) {
            _employee = inOutlet.firstOrNull;
            _load();
          }
        });
      } else {
        setState(() {});
      }
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _initializeEmployee() {
    if (owner && c.activeRoles.isEmpty && !c.employeeMastersLoading) {
      c.loadEmployeeMasters();
    }
    final businessEmployees = c.employees
        .where((e) => e.businessIds.contains(business))
        .toList();

    if (owner) {
      if (widget.employeeId != null) {
        _employee = businessEmployees
            .where((e) => e.employeeId == widget.employeeId)
            .firstOrNull;
        if (_employee != null && _employee!.outletIds.isNotEmpty) {
          _selectedOutletFilter = _employee!.outletIds.first;
        }
      }

      if (_employee == null) {
        final inSelectedOutlet = _selectedOutletFilter == 'ALL'
            ? businessEmployees
            : businessEmployees
                .where((e) => e.outletIds.contains(_selectedOutletFilter))
                .toList();
        if (inSelectedOutlet.isNotEmpty) {
          _employee = inSelectedOutlet.first;
        } else {
          _selectedOutletFilter = 'ALL';
          _employee = businessEmployees.firstOrNull;
        }
      }

      if (c.employees.isEmpty) {
        c.loadEmployees().then((_) {
          if (!mounted) {
            return;
          }
          final refreshed = c.employees
              .where((e) => e.businessIds.contains(business))
              .toList();
          setState(() {
            if (widget.employeeId != null) {
              _employee = refreshed
                  .where((e) => e.employeeId == widget.employeeId)
                  .firstOrNull;
              if (_employee != null && _employee!.outletIds.isNotEmpty) {
                _selectedOutletFilter = _employee!.outletIds.first;
              }
            }
            if (_employee == null) {
              final inSelectedOutlet = _selectedOutletFilter == 'ALL'
                  ? refreshed
                  : refreshed
                      .where((e) => e.outletIds.contains(_selectedOutletFilter))
                      .toList();
              _employee =
                  inSelectedOutlet.firstOrNull ?? refreshed.firstOrNull;
            }
          });
          _load();
        });
        return;
      }
    } else {
      _employee = c.employee;
    }
    _load();
  }

  Future<void> _load() async {
    final repository = c.staffSalaryRepository;
    if (repository == null ||
        tenant == null ||
        business == null ||
        token == null) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profiles = await repository.getSalaryProfiles(
        tenantId: tenant!,
        businessId: business!,
        token: token!,
        employeeId: owner ? null : c.appContext?.employeeId,
      );
      final periods = await repository.getSalaryPeriods(
        tenantId: tenant!,
        businessId: business!,
        token: token!,
        employeeId: owner ? null : c.appContext?.employeeId,
      );
      final employee = _employee;
      final entries = employee == null
          ? <Map<String, dynamic>>[]
          : await repository.getKhataTransactions(
              tenantId: tenant!,
              businessId: business!,
              employeeId: employee.employeeId,
              token: token!,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _profiles = profiles
            .where((p) => p['employeeId'] == employee?.employeeId)
            .toList();
        _periods = periods
            .where((p) => p['employeeId'] == employee?.employeeId)
            .toList();
        _entries = entries;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<OutletModel> get _employeeOutlets => c.outlets
      .where(
        (o) =>
            o.businessId == business &&
            _employee?.outletIds.contains(o.outletId) == true,
      )
      .toList();

  List<OutletModel> get _businessOutlets =>
      c.outlets.where((o) => o.businessId == business).toList();

  String _getOutletNames(List<String> outletIds) {
    if (outletIds.isEmpty) {
      return 'Unassigned';
    }
    final names = <String>[];
    for (final id in outletIds) {
      final match = c.outlets.where((o) => o.outletId == id).firstOrNull;
      if (match != null) {
        names.add(match.outletName);
      }
    }
    if (names.isEmpty) {
      return outletIds.length == 1 ? '1 Outlet' : '${outletIds.length} Outlets';
    }
    return names.join(', ');
  }

  String _formatEmployeeOutletLabel(EmployeeModel emp) {
    if (emp.outletIds.isEmpty) {
      return 'Unassigned';
    }
    if (emp.outletIds.length == 1) {
      final match =
          c.outlets.where((o) => o.outletId == emp.outletIds.first).firstOrNull;
      return match?.outletName ?? '1 Outlet';
    }
    return 'Multi (${emp.outletIds.length})';
  }

  int _rupeesToPaise(String text) {
    final cleaned = text.trim().replaceAll(',', '');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed <= 0 || !parsed.isFinite) {
      throw const FormatException('Enter an amount greater than zero.');
    }
    return (parsed * 100).round();
  }

  String _money(Object? value) {
    final paise = (value as num?)?.toInt() ?? 0;
    final rupees = paise / 100.0;
    final parts = rupees.toStringAsFixed(2).split('.');
    final integerPart = parts[0];
    final decimalPart = parts[1];

    // Format Indian comma separation
    final reg = RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))');
    final formattedInt = integerPart.replaceAllMapped(reg, (m) => '${m[1]},');
    return '₹$formattedInt.$decimalPart';
  }

  String _formatDateString(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '-';
    }
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) {
      return raw.split('T').first;
    }
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(error.toString().replaceAll('Exception: ', ''))),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DIALOGS & ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _advance() async {
    if (!c.canPayStaffSalary() || _employee == null || outlet == null) {
      return;
    }

    final result = await showDialog<_AdvanceInput>(
      context: context,
      builder: (context) => _RecordAdvanceDialog(
        employeeName: _employee!.name,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      await c.staffSalaryRepository!.recordAdvance(
        tenantId: tenant!,
        businessId: business!,
        outletId: outlet!,
        employeeId: _employee!.employeeId,
        amountPaise: result.amountPaise,
        date: result.date,
        paymentMode: result.paymentMode,
        requestId: IdGenerator.create('REQ'),
        createdBy: c.appContext!.employeeId ?? c.user!.uid,
        referenceNo: result.reference.isEmpty ? null : result.reference,
        notes: result.notes.isEmpty ? null : result.notes,
        token: token!,
      );
      if (mounted) {
        _showSuccess(
          'Advance of ${_money(result.amountPaise)} recorded for ${_employee!.name}',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _profile() async {
    if (!c.canManageStaffSalary() || _employee == null) {
      return;
    }

    final currentActive = _profiles
        .where((p) => p['status'] == 'ACTIVE')
        .firstOrNull;

    final result = await showDialog<_SalaryProfileInput>(
      context: context,
      builder: (context) => _SalaryProfileDialog(
        employeeName: _employee!.name,
        outlets: _employeeOutlets,
        existingProfile: currentActive,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      final repo = c.staffSalaryRepository!;
      final now = DateTime.now();
      final effectiveFrom = DateTime(
        now.year,
        now.month + (_profiles.isEmpty ? 0 : 1),
        1,
      );

      await repo.saveSalaryProfile(
        tenantId: tenant!,
        businessId: business!,
        employeeId: _employee!.employeeId,
        salaryType: result.salaryType,
        baseRatePaise: result.baseRatePaise,
        paymentCycle: result.paymentCycle,
        initialOutletBasisPoints: result.outletBasisPoints,
        effectiveFrom: effectiveFrom,
        createdBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );

      if (mounted) {
        _showSuccess(
          'Salary rate of ${_money(result.baseRatePaise)}/${result.salaryType.toLowerCase()} saved.',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _futureAllocation() async {
    if (!c.canManageStaffSalary() || _employee == null) {
      return;
    }
    final outlets = _employeeOutlets;
    if (outlets.isEmpty) {
      _showError('This employee has no outlet assignments.');
      return;
    }

    final weights = await _showOutletAllocationDialog(outlets);
    if (weights == null || !mounted) {
      return;
    }

    try {
      final now = DateTime.now();
      final effective = DateTime(now.year, now.month + 1, 1);
      await c.staffSalaryRepository!.saveOutletAllocation(
        tenantId: tenant!,
        businessId: business!,
        employeeId: _employee!.employeeId,
        effectiveFrom: effective,
        outletBasisPoints: weights,
        createdBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );
      if (mounted) {
        _showSuccess('Future outlet allocation split updated.');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<Map<String, int>?> _showOutletAllocationDialog(
    List<OutletModel> outlets,
  ) async {
    if (outlets.length == 1) {
      return {outlets.single.outletId: 10000};
    }

    final controllers = [
      for (var i = 0; i < outlets.length; i++)
        TextEditingController(text: outlets.length == 1 ? '100' : '0'),
    ];

    return showDialog<Map<String, int>>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) {
          int currentTotalPct() {
            var total = 0.0;
            for (final ctrl in controllers) {
              total += double.tryParse(ctrl.text) ?? 0.0;
            }
            return total.round();
          }

          final total = currentTotalPct();
          final isValid = total == 100;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF132B45).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.pie_chart_outline_rounded,
                    color: Color(0xFF132B45),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('Outlet Allocation (%)'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Specify the percentage split of salary expense across outlets. Must total exactly 100%.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < outlets.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            outlets[i].outletName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: controllers[i],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              suffixText: '%',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isValid
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total Allocation:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isValid
                                ? const Color(0xFF166534)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                        Text(
                          '$total%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isValid
                                ? const Color(0xFF166534)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isValid
                    ? () {
                        final result = <String, int>{};
                        for (var i = 0; i < outlets.length; i++) {
                          final pct =
                              double.tryParse(controllers[i].text) ?? 0.0;
                          if (pct > 0) {
                            result[outlets[i].outletId] = (pct * 100).round();
                          }
                        }
                        Navigator.pop(dialogCtx, result);
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF132B45),
                ),
                child: const Text('Save 100% Split'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _approve() async {
    if (!c.canApproveStaffSalary() || _employee == null) {
      return;
    }
    final active = _profiles.where((p) => p['status'] == 'ACTIVE').toList()
      ..sort(
        (a, b) => (b['effectiveFrom']?.toString() ?? '').compareTo(
          a['effectiveFrom']?.toString() ?? '',
        ),
      );
    if (active.isEmpty) {
      _showError('Please configure a salary rate profile for this staff first.');
      return;
    }
    final profile = active.first;
    final type = profile['salaryType'] as String? ?? 'MONTHLY';
    final now = DateTime.now();
    final cycle = profile['paymentCycle'] as String? ?? 'MONTHLY';
    late final DateTime start;
    late final DateTime end;
    if (cycle == 'WEEKLY') {
      start = DateTime(now.year, now.month, now.day - now.weekday + 1);
      end = start.add(const Duration(days: 6));
    } else if (cycle == 'FORTNIGHTLY') {
      final anchor =
          DateTime.tryParse(profile['effectiveFrom'] as String? ?? '')
              ?.toLocal() ??
          DateTime(now.year, now.month, 1);
      final days = DateTime(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime(anchor.year, anchor.month, anchor.day)).inDays;
      final offset = (days < 0 ? 0 : days ~/ 14) * 14;
      start = DateTime(anchor.year, anchor.month, anchor.day + offset);
      end = start.add(const Duration(days: 13));
    } else {
      start = DateTime(now.year, now.month, 1);
      end = DateTime(now.year, now.month + 1, 0);
    }
    var units = 0;
    List<Map<String, dynamic>> attendance = const [];
    try {
      attendance = (await c.loadStaffAttendance(
        from: start,
        through: end,
        employeeId: _employee!.employeeId,
      )).where((row) => row['approvalStatus'] == 'APPROVED').toList();
    } catch (_) {
      // Handled silently if user doesn't have attendance view permissions
    }
    final attendanceIds = attendance
        .map((row) => row['attendanceId'].toString())
        .toList();
    late final int attendanceOvertimePaise;
    try {
      attendanceOvertimePaise =
          StaffAttendanceRepository.calculateOvertimePaise(attendance);
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
      return;
    }
    if (type == 'MONTHLY' && attendance.isNotEmpty) {
      units = attendance.fold<int>(
        0,
        (sum, row) => sum + ((row['payableUnitsMilli'] as num?)?.toInt() ?? 0),
      );
    } else if (type != 'MONTHLY' && attendance.isNotEmpty) {
      units = attendance.fold<int>(0, (sum, row) {
        if (type == 'HOURLY') {
          final minutes = (row['workedMinutes'] as num?)?.toInt() ?? 0;
          return sum + ((minutes * 1000 + 30) ~/ 60);
        }
        return sum + ((row['payableUnitsMilli'] as num?)?.toInt() ?? 0);
      });
    }

    if (!mounted) {
      return;
    }

    final approvalInput = await showDialog<_ApprovalAdjustmentsInput>(
      context: context,
      builder: (context) => _ApprovePeriodDialog(
        employeeName: _employee!.name,
        salaryType: type,
        baseRatePaise: (profile['baseRatePaise'] as num?)?.toInt() ?? 0,
        start: start,
        end: end,
        attendanceCount: attendance.length,
        attendanceOvertimePaise: attendanceOvertimePaise,
        initialUnits: units,
        moneyFormatter: _money,
      ),
    );

    if (approvalInput == null || !mounted) {
      return;
    }

    final totalOvertimePaise =
        attendanceOvertimePaise + approvalInput.additionalOvertimePaise;
    final unpaidLeaveUnits = attendance.fold<int>(0, (sum, row) {
      if (row['attendanceStatus'] == 'ABSENT' ||
          row['attendanceStatus'] == 'UNPAID_LEAVE') {
        return sum + 1000;
      }
      if (row['attendanceStatus'] == 'HALF_DAY') {
        return sum + 500;
      }
      return sum;
    });

    final unpaidLeaveDeductionPaise =
        (approvalInput.deductionPerUnpaidLeavePaise * unpaidLeaveUnits + 500) ~/
        1000;
    final totalApprovedDeductionsPaise =
        approvalInput.otherDeductionsPaise + unpaidLeaveDeductionPaise;

    try {
      final weights = <String, int>{};
      await c.staffSalaryRepository!.approveSalaryPeriod(
        tenantId: tenant!,
        businessId: business!,
        employeeId: _employee!.employeeId,
        profileId: profile['profileId'] as String,
        periodStart: start,
        periodEnd: end,
        workUnitsMilli: approvalInput.workUnitsMilli,
        bonusPaise: approvalInput.bonusPaise,
        overtimePaise: totalOvertimePaise,
        attendanceRecordIds: attendanceIds.isEmpty ? null : attendanceIds,
        approvedDeductionsPaise: totalApprovedDeductionsPaise,
        fallbackOutletBasisPoints:
            weights.isEmpty && _employeeOutlets.length == 1
            ? {_employeeOutlets.single.outletId: 10000}
            : weights,
        approvedBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );

      if (mounted) {
        _showSuccess(
          'Salary period approved successfully for ${_employee!.name}.',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _pay(Map<String, dynamic> period) async {
    if (!c.canPayStaffSalary() || _employee == null || outlet == null) {
      return;
    }

    final earned = (period['netEarnedPaise'] as num?)?.toInt() ?? 0;
    final paid = (period['paidAmountPaise'] as num?)?.toInt() ?? 0;
    final advAdj = (period['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
    final purcAdj =
        (period['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
    final remaining = earned - paid - advAdj - purcAdj;

    if (remaining <= 0) {
      _showError('This salary period is already fully settled.');
      return;
    }

    final result = await showDialog<_PaymentInput>(
      context: context,
      builder: (context) => _RecordPaymentDialog(
        employeeName: _employee!.name,
        periodLabel:
            '${_formatDateString(period['periodStart']?.toString())} – ${_formatDateString(period['periodEnd']?.toString())}',
        remainingPayablePaise: remaining,
        moneyFormatter: _money,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      await c.staffSalaryRepository!.recordSalaryPayment(
        tenantId: tenant!,
        businessId: business!,
        outletId: outlet!,
        employeeId: _employee!.employeeId,
        periodId: period['periodId'] as String,
        amountPaise: result.amountPaise,
        date: result.date,
        paymentMode: result.paymentMode,
        requestId: IdGenerator.create('REQ'),
        paidBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );
      if (mounted) {
        _showSuccess(
          'Salary payment of ${_money(result.amountPaise)} recorded.',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _adjustAdvance(Map<String, dynamic> period) async {
    if (!c.canApproveStaffSalary() || _employee == null || outlet == null) {
      return;
    }

    final earned = (period['netEarnedPaise'] as num?)?.toInt() ?? 0;
    final paid = (period['paidAmountPaise'] as num?)?.toInt() ?? 0;
    final advAdj = (period['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
    final purcAdj =
        (period['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
    final remainingPayable = earned - paid - advAdj - purcAdj;

    final availableAdvance = _entries
        .where((e) => e['status'] == 'POSTED')
        .fold<int>(0, (sum, e) {
          final amount = (e['amountPaise'] as num?)?.toInt() ?? 0;
          return sum +
              (e['transactionType'] == 'CASH_ADVANCE' ||
                      e['transactionType'] == 'UPI_ADVANCE' ||
                      e['transactionType'] == 'BANK_ADVANCE'
                  ? amount
                  : e['transactionType'] == 'ADVANCE_ADJUSTMENT'
                  ? -amount
                  : 0);
        });

    if (availableAdvance <= 0) {
      _showError('No outstanding advance balance available to adjust.');
      return;
    }
    if (remainingPayable <= 0) {
      _showError('This salary period has no remaining balance due.');
      return;
    }

    final maxAdjustable = availableAdvance < remainingPayable
        ? availableAdvance
        : remainingPayable;

    final adjustedPaise = await showDialog<int>(
      context: context,
      builder: (context) => _AdjustAdvanceDialog(
        availableAdvancePaise: availableAdvance,
        remainingPayablePaise: remainingPayable,
        maxAdjustablePaise: maxAdjustable,
        moneyFormatter: _money,
      ),
    );

    if (adjustedPaise == null || !mounted) {
      return;
    }

    try {
      await c.staffSalaryRepository!.adjustAdvanceAgainstSalary(
        tenantId: tenant!,
        businessId: business!,
        outletId: outlet!,
        employeeId: _employee!.employeeId,
        periodId: period['periodId'] as String,
        amountPaise: adjustedPaise,
        requestId: IdGenerator.create('REQ'),
        approvedBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );
      if (mounted) {
        _showSuccess(
          'Advance adjustment of ${_money(adjustedPaise)} applied to period.',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _offsetStaffPurchases(Map<String, dynamic> period) async {
    if (!c.canApproveStaffSalary() || _employee == null || outlet == null) {
      return;
    }

    final earned = (period['netEarnedPaise'] as num?)?.toInt() ?? 0;
    final paid = (period['paidAmountPaise'] as num?)?.toInt() ?? 0;
    final advAdj = (period['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
    final purcAdj =
        (period['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
    final remainingPayable = earned - paid - advAdj - purcAdj;

    final staffPurchaseBalance = _entries
        .where((e) => e['status'] == 'POSTED')
        .fold<int>(0, (sum, e) {
          final amount = (e['amountPaise'] as num?)?.toInt() ?? 0;
          if (e['transactionType'] == 'STORE_PURCHASE') {
            return sum + amount;
          }
          if (e['transactionType'] == 'STORE_CREDIT_ADJUSTMENT') {
            return sum - amount;
          }
          return sum;
        });

    if (staffPurchaseBalance <= 0) {
      _showError('No staff store purchase balance available to offset.');
      return;
    }

    final maxOffset = staffPurchaseBalance < remainingPayable
        ? staffPurchaseBalance
        : remainingPayable;

    final offsetAmountPaise = await showDialog<int>(
      context: context,
      builder: (context) => _OffsetPurchaseDialog(
        availableReceivablePaise: staffPurchaseBalance,
        remainingPayablePaise: remainingPayable,
        maxOffsetPaise: maxOffset,
        moneyFormatter: _money,
      ),
    );

    if (offsetAmountPaise == null || !mounted) {
      return;
    }

    try {
      await c.staffSalaryRepository!.adjustStaffPurchasesAgainstSalary(
        tenantId: tenant!,
        businessId: business!,
        outletId: outlet!,
        employeeId: _employee!.employeeId,
        periodId: period['periodId'] as String,
        amountPaise: offsetAmountPaise,
        requestId: IdGenerator.create('REQ'),
        approvedBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );
      if (mounted) {
        _showSuccess(
          'Store purchase offset of ${_money(offsetAmountPaise)} applied.',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _payStaffPurchase(Map<String, dynamic> entry) async {
    if (!c.canPayStaffSalary() || _employee == null || outlet == null) {
      return;
    }
    final invoiceId = entry['referenceId']?.toString();
    if (invoiceId == null) {
      return;
    }

    final controller = TextEditingController(
      text: ((((entry['amountPaise'] as num?)?.toInt() ?? 0)) / 100)
          .toStringAsFixed(2),
    );
    String mode = 'CASH';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Receive Staff Invoice Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Receive payment from ${_employee!.name} for Store Invoice $invoiceId.',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Payment Amount (₹)',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(
                  labelText: 'Payment Mode',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(
                    value: 'BANK_TRANSFER',
                    child: Text('Bank Transfer'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => mode = v ?? 'CASH'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF132B45),
              ),
              child: const Text('Receive Payment'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await c.staffSalaryRepository!.recordStaffPurchasePayment(
        tenantId: tenant!,
        businessId: business!,
        outletId: outlet!,
        employeeId: _employee!.employeeId,
        invoiceId: invoiceId,
        amountPaise: _rupeesToPaise(controller.text),
        paymentMode: mode,
        requestId: IdGenerator.create('REQ'),
        recordedBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );
      if (mounted) {
        _showSuccess('Staff invoice payment received successfully.');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _shareStatement(
    Map<String, dynamic> period,
    SalaryDocumentType type,
  ) async {
    final lang = await showDialog<SalaryDocumentLanguage>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.language_rounded, color: Color(0xFF132B45)),
            const SizedBox(width: 8),
            const Text('Document Language'),
          ],
        ),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, SalaryDocumentLanguage.english),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 18),
                  SizedBox(width: 10),
                  Text('English (Default)'),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, SalaryDocumentLanguage.bengali),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.translate, size: 18),
                  SizedBox(width: 10),
                  Text('বাংলা (Bengali)'),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.pop(context, SalaryDocumentLanguage.hindi),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.translate, size: 18),
                  SizedBox(width: 10),
                  Text('हिन्दी (Hindi)'),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (lang == null || _employee == null) {
      return;
    }

    try {
      final businessRecord = c.businesses
          .where((b) => b.businessId == business)
          .firstOrNull;
      final bytes = await SalaryDocumentService.buildStatement(
        business: {
          'name': businessRecord?.businessName ?? 'Business',
          'address': businessRecord?.address,
          'phone': businessRecord?.phone,
          'gstin': businessRecord?.gstin,
        },
        employee: {
          'name': _employee!.name,
          'employeeId': _employee!.employeeId,
          'mobile': _employee!.mobile,
          'employeeCode': _employee!.employeeCode,
        },
        period: period,
        language: lang,
        type: type,
        transactions: _entries,
      );
      final id = period['periodId']?.toString() ?? 'salary';
      final label = type == SalaryDocumentType.payslip
          ? 'Salary Slip'
          : 'Salary Statement';

      await SharePlus.instance.share(
        ShareParams(
          subject: '$label $id',
          text: '$label for ${_employee!.name} ($id)',
          files: [
            XFile.fromData(bytes, name: '$id.pdf', mimeType: 'application/pdf'),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _recordAcknowledgment(Map<String, dynamic> period) async {
    if (!c.canManageStaffSalary() || _employee == null) {
      return;
    }

    final controller = TextEditingController(text: _employee!.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.draw_outlined, color: Color(0xFF132B45)),
            SizedBox(width: 8),
            Text('Confirm In-Person Acknowledgment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record this only after the employee has reviewed and confirmed receipt of the salary statement in person.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Employee Name Confirming Receipt',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF132B45),
            ),
            child: const Text('Confirm Acknowledgment'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await c.staffSalaryRepository!.acknowledgeSalaryStatement(
        tenantId: tenant!,
        businessId: business!,
        employeeId: _employee!.employeeId,
        periodId: period['periodId'] as String,
        acknowledgedByName: controller.text.trim(),
        recordedBy: c.appContext!.employeeId ?? c.user!.uid,
        token: token!,
      );
      if (mounted) {
        _showSuccess('Employee acknowledgment recorded successfully.');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  Future<void> _addTemporaryWorker() async {
    if (!c.canManageStaffSalary() ||
        tenant == null ||
        business == null ||
        token == null) {
      return;
    }

    final availableOutlets = _businessOutlets;
    if (availableOutlets.isEmpty) {
      _showError(
        'No outlets found for this business. Please create an outlet first.',
      );
      return;
    }

    final nameController = TextEditingController();
    final mobileController = TextEditingController();
    final codeController = TextEditingController();

    // Default outlet selection:
    final defaultOutlet = _selectedOutletFilter != 'ALL' &&
            availableOutlets.any((o) => o.outletId == _selectedOutletFilter)
        ? _selectedOutletFilter
        : (outlet != null && availableOutlets.any((o) => o.outletId == outlet)
            ? outlet!
            : availableOutlets.first.outletId);

    final selectedOutletIds = <String>{defaultOutlet};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF132B45)),
              SizedBox(width: 8),
              Text('Add Daily-Wage Worker'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Onboard daily-wage or temporary labor. They do not require an app login account and are assigned to your chosen outlet(s).',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Worker Full Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mobileController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Worker / Badge Code (Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Assigned Outlet(s) *',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    children: [
                      for (final out in availableOutlets)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            out.outletName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: out.outletCode != null &&
                                  out.outletCode!.isNotEmpty
                              ? Text(
                                  out.outletCode!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                )
                              : null,
                          value: selectedOutletIds.contains(out.outletId),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedOutletIds.add(out.outletId);
                              } else {
                                if (selectedOutletIds.length > 1) {
                                  selectedOutletIds.remove(out.outletId);
                                }
                              }
                            });
                          },
                        ),
                    ],
                  ),
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
              onPressed: () {
                if (nameController.text.trim().isNotEmpty &&
                    selectedOutletIds.isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF132B45),
              ),
              child: const Text('Save Worker'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final created = await c.employeesRepository.createTemporaryWorker(
        ownerUid: tenant!,
        name: nameController.text.trim(),
        mobile: mobileController.text.trim().isEmpty
            ? ''
            : mobileController.text.trim(),
        employeeCode: codeController.text.trim().isEmpty
            ? ''
            : codeController.text.trim(),
        businessIds: [business!],
        outletIds: selectedOutletIds.toList(),
        status: 'active',
        token: token!,
      );
      await c.loadEmployees();
      if (!mounted) {
        return;
      }
      setState(() {
        if (_selectedOutletFilter != 'ALL' &&
            !selectedOutletIds.contains(_selectedOutletFilter)) {
          _selectedOutletFilter = selectedOutletIds.first;
        }
        _employee = c.employees
            .where((e) => e.employeeId == created.employeeId)
            .firstOrNull;
      });
      _showSuccess('Worker ${nameController.text} added to Staff Khata.');
      await _load();
    } catch (e) {
      if (mounted) {
        _showError(e);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI BUILD METHOD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!c.canViewStaffSalary()) {
      return const Scaffold(
        body: Center(
          child: Text('You do not have permission to view salary information.'),
        ),
      );
    }

    final allBusinessEmployees = owner
        ? c.employees.where((e) => e.businessIds.contains(business)).toList()
        : (_employee == null ? <EmployeeModel>[] : [_employee!]);

    final outletCandidates = allBusinessEmployees.where((e) {
      if (_selectedOutletFilter == 'ALL') {
        return true;
      }
      return e.outletIds.contains(_selectedOutletFilter);
    }).toList();

    final filteredCandidates = outletCandidates.where((e) {
      if (_searchStaffQuery.isEmpty) {
        return true;
      }
      final query = _searchStaffQuery.toLowerCase();
      final name = e.name.toLowerCase();
      final code = (e.employeeCode ?? '').toLowerCase();
      final phone = (e.mobile ?? '').toLowerCase();
      return name.contains(query) ||
          code.contains(query) ||
          phone.contains(query);
    }).toList();

    // Calculate Balances for Selected Employee
    final advancePaise = _entries
        .where((e) => e['status'] == 'POSTED')
        .fold<int>(0, (sum, e) {
          final amount = (e['amountPaise'] as num?)?.toInt() ?? 0;
          return sum +
              (e['transactionType'] == 'CASH_ADVANCE' ||
                      e['transactionType'] == 'UPI_ADVANCE' ||
                      e['transactionType'] == 'BANK_ADVANCE'
                  ? amount
                  : e['transactionType'] == 'ADVANCE_ADJUSTMENT'
                  ? -amount
                  : 0);
        });

    final staffPurchaseBalancePaise = _entries
        .where((e) => e['status'] == 'POSTED')
        .fold<int>(0, (sum, e) {
          final amount = (e['amountPaise'] as num?)?.toInt() ?? 0;
          if (e['transactionType'] == 'STORE_PURCHASE') {
            return sum + amount;
          }
          if (e['transactionType'] == 'STORE_CREDIT_ADJUSTMENT') {
            return sum - amount;
          }
          return sum;
        });

    // Total Unpaid Salary across periods
    final totalUnpaidSalaryPaise = _periods
        .where((p) => p['status'] != 'PAID')
        .fold<int>(0, (sum, p) {
          final earned = (p['netEarnedPaise'] as num?)?.toInt() ?? 0;
          final paid = (p['paidAmountPaise'] as num?)?.toInt() ?? 0;
          final advAdj = (p['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
          final purcAdj =
              (p['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
          final remaining = earned - paid - advAdj - purcAdj;
          return sum + (remaining > 0 ? remaining : 0);
        });

    final activeProfile = _profiles
        .where((p) => p['status'] == 'ACTIVE')
        .firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF132B45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: Color(0xFFD9A441),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Staff Salary Khata',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Advance ledger, attendance reconciliation & payroll settlements',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (c.canManageStaffAttendance())
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StaffAttendancePage(controller: c),
                ),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 16),
              label: const Text('Attendance Register'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF132B45),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            style: IconButton.styleFrom(
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading && _employee == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _employee == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF132B45),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // 1. Staff Selector Carousel / Grid (when owner)
                  if (owner) ...[
                    _buildStaffSelectorSection(
                      candidates: outletCandidates,
                      filtered: filteredCandidates,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_employee == null)
                    _buildNoEmployeeSelectedState()
                  else ...[
                    // 2. Selected Employee Profile & Executive KPI Summary
                    _buildEmployeeExecutiveSummary(
                      employee: _employee!,
                      activeProfile: activeProfile,
                      advancePaise: advancePaise,
                      staffPurchaseBalancePaise: staffPurchaseBalancePaise,
                      totalUnpaidSalaryPaise: totalUnpaidSalaryPaise,
                    ),
                    const SizedBox(height: 16),

                    // 3. Quick Action Buttons Bar
                    _buildActionBar(),
                    const SizedBox(height: 16),

                    // 4. Tab Navigation
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF132B45),
                        unselectedLabelColor: const Color(0xFF64748B),
                        indicatorColor: const Color(0xFF132B45),
                        indicatorWeight: 3,
                        tabs: [
                          Tab(
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                            ),
                            text: 'Salary Periods (${_periods.length})',
                          ),
                          Tab(
                            icon: const Icon(
                              Icons.menu_book_outlined,
                              size: 18,
                            ),
                            text: 'Khata Passbook (${_entries.length})',
                          ),
                          Tab(
                            icon: const Icon(
                              Icons.tune_rounded,
                              size: 18,
                            ),
                            text: 'Salary Profile & Splits',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5. Tab Content
                    AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, _) {
                        return switch (_tabController.index) {
                          0 => _buildSalaryPeriodsTab(
                              periods: _periods,
                              availableAdvancePaise: advancePaise,
                              staffPurchaseBalancePaise:
                                  staffPurchaseBalancePaise,
                            ),
                          1 => _buildPassbookTab(entries: _entries),
                          _ => _buildProfilesAndSplitsTab(
                              profiles: _profiles,
                              outlets: _employeeOutlets,
                            ),
                        };
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMPONENT: STAFF SELECTOR CAROUSEL
  // ---------------------------------------------------------------------------

  Widget _buildStaffSelectorSection({
    required List<EmployeeModel> candidates,
    required List<EmployeeModel> filtered,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.people_alt_outlined,
                size: 18,
                color: Color(0xFF132B45),
              ),
              const SizedBox(width: 8),
              const Text(
                'Select Staff Member',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              if (c.canManageStaffSalary())
                TextButton.icon(
                  onPressed: _addTemporaryWorker,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text(
                    '+ Add Daily Worker',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (candidates.length > 3) ...[
            TextField(
              decoration: InputDecoration(
                hintText: 'Search staff by name or code...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              onChanged: (val) => setState(() => _searchStaffQuery = val),
            ),
            const SizedBox(height: 10),
          ],
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No staff members match the criteria.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final emp in filtered) ...[
                    _StaffSelectionChip(
                      employee: emp,
                      roleLabel: _roleNames(emp),
                      isSelected: emp.employeeId == _employee?.employeeId,
                      onTap: () {
                        setState(() => _employee = emp);
                        _load();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _roleNames(EmployeeModel employee) {
    if (employee.roleIds.isEmpty) return 'No role assigned';
    return employee.roleIds.map((id) {
      final role = c.activeRoles.where((item) => item.roleId == id).firstOrNull;
      return role?.roleName ?? id;
    }).join(', ');
  }

  // ---------------------------------------------------------------------------
  // COMPONENT: EXECUTIVE SUMMARY & KPI CARDS
  // ---------------------------------------------------------------------------

  Widget _buildEmployeeExecutiveSummary({
    required EmployeeModel employee,
    required Map<String, dynamic>? activeProfile,
    required int advancePaise,
    required int staffPurchaseBalancePaise,
    required int totalUnpaidSalaryPaise,
  }) {
    final initials = employee.name.isNotEmpty
        ? employee.name.split(' ').map((n) => n.isNotEmpty ? n[0] : '').take(2).join()
        : 'EM';

    final baseRatePaise =
        (activeProfile?['baseRatePaise'] as num?)?.toInt() ?? 0;
    final salaryType =
        activeProfile?['salaryType'] as String? ?? 'NOT_SET';
    final paymentCycle =
        activeProfile?['paymentCycle'] as String? ?? 'MONTHLY';

    return Column(
      children: [
        // Employee Info Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF132B45), Color(0xFF1E3A5F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF132B45).withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFD9A441),
                child: Text(
                  initials.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF132B45),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            employee.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            employee.employeeCode ?? 'STAFF',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 12,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Role: ${_roleNames(employee)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                          ],
                        ),
                        if (employee.mobile != null &&
                            employee.mobile!.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phone_android_rounded,
                                size: 12,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                employee.mobile!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                            ],
                          ),
                        if (employee.email.isNotEmpty &&
                            !employee.email.contains('temp_'))
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.email_outlined,
                                size: 12,
                                color: Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                employee.email,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 4 Executive Metric Cards Row
        LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 650;
            final cards = [
              _SalaryKpiMetricCard(
                title: 'Base Rate & Type',
                value: baseRatePaise > 0
                    ? '${_money(baseRatePaise)} / ${salaryType.toLowerCase()}'
                    : 'Not Configured',
                subtitle: baseRatePaise > 0
                    ? '$paymentCycle cycle'
                    : 'Tap to configure rate',
                icon: Icons.payments_rounded,
                accentColor: const Color(0xFF2563EB),
                onTap: c.canManageStaffSalary() ? _profile : null,
              ),
              _SalaryKpiMetricCard(
                title: 'Outstanding Advances',
                value: _money(advancePaise),
                subtitle: advancePaise > 0
                    ? 'Mid-month cash/UPI advances'
                    : 'No advance due',
                icon: Icons.arrow_outward_rounded,
                accentColor: advancePaise > 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF64748B),
                isAlert: advancePaise > 0,
                onTap: c.canPayStaffSalary() ? _advance : null,
              ),
              _SalaryKpiMetricCard(
                title: 'Store Purchases Credit',
                value: _money(staffPurchaseBalancePaise),
                subtitle: staffPurchaseBalancePaise > 0
                    ? 'Store goods on credit'
                    : 'No store credit due',
                icon: Icons.shopping_bag_outlined,
                accentColor: staffPurchaseBalancePaise > 0
                    ? const Color(0xFFD97706)
                    : const Color(0xFF64748B),
                isAlert: staffPurchaseBalancePaise > 0,
              ),
              _SalaryKpiMetricCard(
                title: 'Net Salary Payable',
                value: _money(totalUnpaidSalaryPaise),
                subtitle: totalUnpaidSalaryPaise > 0
                    ? 'Across unpaid approved periods'
                    : 'All periods settled',
                icon: Icons.account_balance_rounded,
                accentColor: totalUnpaidSalaryPaise > 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF64748B),
              ),
            ];

            if (isMobile) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 8),
                  ],
                ],
              );
            }

            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COMPONENT: ACTION BAR
  // ---------------------------------------------------------------------------

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (c.canPayStaffSalary())
            FilledButton.icon(
              onPressed: _advance,
              icon: const Icon(Icons.payments_outlined, size: 16),
              label: const Text('+ Give Advance (Peshgi)'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          if (c.canApproveStaffSalary())
            FilledButton.icon(
              onPressed: _approve,
              icon: const Icon(Icons.verified_outlined, size: 16),
              label: const Text('Approve Period Salary'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF132B45),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          if (c.canManageStaffSalary())
            OutlinedButton.icon(
              onPressed: _profile,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Salary Profile & Rate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
              ),
            ),
          if (c.canManageStaffSalary() && _employeeOutlets.length > 1)
            OutlinedButton.icon(
              onPressed: _futureAllocation,
              icon: const Icon(Icons.pie_chart_outline, size: 16),
              label: const Text('Outlet Allocation Split'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: SALARY PERIODS & SETTLEMENTS
  // ---------------------------------------------------------------------------

  Widget _buildSalaryPeriodsTab({
    required List<Map<String, dynamic>> periods,
    required int availableAdvancePaise,
    required int staffPurchaseBalancePaise,
  }) {
    if (periods.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 42,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Salary Periods Approved Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Click "Approve Period Salary" above to calculate and lock this month’s earnings.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            if (c.canApproveStaffSalary()) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _approve,
                icon: const Icon(Icons.verified_outlined, size: 16),
                label: const Text('Approve Current Period'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF132B45),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final period in periods) ...[
          _SalaryPeriodCard(
            period: period,
            availableAdvancePaise: availableAdvancePaise,
            staffPurchaseBalancePaise: staffPurchaseBalancePaise,
            canPay: c.canPayStaffSalary(),
            canApprove: c.canApproveStaffSalary(),
            canManage: c.canManageStaffSalary(),
            onPay: () => _pay(period),
            onAdjustAdvance: () => _adjustAdvance(period),
            onOffsetPurchase: () => _offsetStaffPurchases(period),
            onShareSlip: () => _shareStatement(period, SalaryDocumentType.payslip),
            onShareStatement: () =>
                _shareStatement(period, SalaryDocumentType.statement),
            onAcknowledge: () => _recordAcknowledgment(period),
            moneyFormatter: _money,
            dateFormatter: _formatDateString,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: PASSBOOK TRANSACTIONS LEDGER
  // ---------------------------------------------------------------------------

  Widget _buildPassbookTab({
    required List<Map<String, dynamic>> entries,
  }) {
    final filtered = entries.where((e) {
      final type = (e['transactionType'] as String? ?? '').toUpperCase();
      return switch (_passbookFilter) {
        'ADVANCES' =>
          type.contains('ADVANCE') && !type.contains('ADJUSTMENT'),
        'STORE' => type.contains('STORE') || type.contains('PURCHASE'),
        'SETTLEMENTS' =>
          type.contains('PAYMENT') || type.contains('ADJUSTMENT'),
        _ => true,
      };
    }).toList();

    return Column(
      children: [
        // Filter Chips Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Text(
                'Filter: ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final opt in [
                    ('ALL', 'All Events'),
                    ('ADVANCES', 'Advances'),
                    ('STORE', 'Store Purchases'),
                    ('SETTLEMENTS', 'Payments & Offsets'),
                  ])
                    ChoiceChip(
                      label: Text(
                        opt.$2,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: _passbookFilter == opt.$1
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: _passbookFilter == opt.$1,
                      onSelected: (_) => setState(() => _passbookFilter = opt.$1),
                      selectedColor:
                          const Color(0xFF132B45).withValues(alpha: 0.12),
                      backgroundColor: const Color(0xFFF1F5F9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 40,
                  color: Color(0xFF94A3B8),
                ),
                SizedBox(height: 10),
                Text(
                  'No Ledger Transactions Found',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Advances, store credits, and salary payments will appear here.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
              itemBuilder: (context, index) {
                final entry = filtered[index];
                return _PassbookTile(
                  entry: entry,
                  canPayStaffSalary: c.canPayStaffSalary(),
                  onPayInvoice: () => _payStaffPurchase(entry),
                  moneyFormatter: _money,
                  dateFormatter: _formatDateString,
                );
              },
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: SALARY PROFILES & ALLOCATION SPLITS
  // ---------------------------------------------------------------------------

  Widget _buildProfilesAndSplitsTab({
    required List<Map<String, dynamic>> profiles,
    required List<OutletModel> outlets,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Salary Rate History',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            if (c.canManageStaffSalary())
              FilledButton.icon(
                onPressed: _profile,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Update Rate / Add Profile'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF132B45),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (profiles.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Text('No salary rate profile configured.'),
          )
        else
          for (final prof in profiles) ...[
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: prof['status'] == 'ACTIVE'
                      ? const Color(0xFF16A34A).withValues(alpha: 0.5)
                      : const Color(0xFFCBD5E1),
                ),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: prof['status'] == 'ACTIVE'
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.payments_rounded,
                    color: prof['status'] == 'ACTIVE'
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF64748B),
                  ),
                ),
                title: Text(
                  '${_money(prof['baseRatePaise'])} · ${prof['salaryType']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Effective: ${_formatDateString(prof['effectiveFrom']?.toString())} – ${prof['effectiveTo'] == null ? 'Present' : _formatDateString(prof['effectiveTo']?.toString())}  •  Cycle: ${prof['paymentCycle']}',
                ),
                trailing: Chip(
                  label: Text(
                    prof['status'] ?? 'ACTIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: prof['status'] == 'ACTIVE'
                          ? const Color(0xFF166534)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  backgroundColor: prof['status'] == 'ACTIVE'
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFF1F5F9),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _buildNoEmployeeSelectedState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.person_search_rounded,
            size: 48,
            color: Color(0xFF94A3B8),
          ),
          const SizedBox(height: 12),
          const Text(
            'No Staff Member Selected',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Select a staff member from the top list or onboard a new worker.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          if (c.canManageStaffSalary()) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _addTemporaryWorker,
              icon: const Icon(Icons.person_add_alt_1, size: 16),
              label: const Text('Add Daily-Wage Worker'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF132B45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET: STAFF SELECTION CHIP
// -----------------------------------------------------------------------------

class _StaffSelectionChip extends StatelessWidget {
  const _StaffSelectionChip({
    required this.employee,
    required this.roleLabel,
    required this.isSelected,
    required this.onTap,
  });

  final EmployeeModel employee;
  final String roleLabel;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = employee.name.isNotEmpty
        ? employee.name.split(' ').map((n) => n.isNotEmpty ? n[0] : '').take(2).join()
        : 'EM';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF132B45).withValues(alpha: 0.08)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF132B45)
                : const Color(0xFFCBD5E1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: isSelected
                  ? const Color(0xFF132B45)
                  : const Color(0xFFE2E8F0),
              child: Text(
                initials.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  employee.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? const Color(0xFF132B45)
                        : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  employee.employeeCode ?? 'Staff',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
                Text(
                  roleLabel,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET: EXECUTIVE KPI CARD
// -----------------------------------------------------------------------------

class _SalaryKpiMetricCard extends StatelessWidget {
  const _SalaryKpiMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.isAlert = false,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isAlert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isAlert
                ? accentColor.withValues(alpha: 0.5)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isAlert ? accentColor : const Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET: SALARY PERIOD CARD
// -----------------------------------------------------------------------------

class _SalaryPeriodCard extends StatelessWidget {
  const _SalaryPeriodCard({
    required this.period,
    required this.availableAdvancePaise,
    required this.staffPurchaseBalancePaise,
    required this.canPay,
    required this.canApprove,
    required this.canManage,
    required this.onPay,
    required this.onAdjustAdvance,
    required this.onOffsetPurchase,
    required this.onShareSlip,
    required this.onShareStatement,
    required this.onAcknowledge,
    required this.moneyFormatter,
    required this.dateFormatter,
  });

  final Map<String, dynamic> period;
  final int availableAdvancePaise;
  final int staffPurchaseBalancePaise;
  final bool canPay;
  final bool canApprove;
  final bool canManage;
  final VoidCallback onPay;
  final VoidCallback onAdjustAdvance;
  final VoidCallback onOffsetPurchase;
  final VoidCallback onShareSlip;
  final VoidCallback onShareStatement;
  final VoidCallback onAcknowledge;
  final String Function(Object?) moneyFormatter;
  final String Function(String?) dateFormatter;

  @override
  Widget build(BuildContext context) {
    final earned = (period['netEarnedPaise'] as num?)?.toInt() ?? 0;
    final paid = (period['paidAmountPaise'] as num?)?.toInt() ?? 0;
    final advAdj = (period['advanceAdjustedPaise'] as num?)?.toInt() ?? 0;
    final purcAdj =
        (period['staffPurchaseAdjustedPaise'] as num?)?.toInt() ?? 0;
    final remaining = earned - paid - advAdj - purcAdj;

    final isPaid = period['status'] == 'PAID' || remaining <= 0;
    final isAcknowledged = period['employeeAcknowledgedAt'] != null;

    final settledPaise = paid + advAdj + purcAdj;
    final settledRatio = earned > 0 ? (settledPaise / earned).clamp(0.0, 1.0) : 1.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.date_range_rounded,
                  size: 18,
                  color: Color(0xFF132B45),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dateFormatter(period['periodStart']?.toString())}  –  ${dateFormatter(period['periodEnd']?.toString())}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                if (isAcknowledged) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Color(0xFF166534),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Acknowledged',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF166534),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPaid ? 'PAID / SETTLED' : 'PAYABLE DUE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isPaid
                          ? const Color(0xFF166534)
                          : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Settlement Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: settledRatio,
                minHeight: 6,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isPaid ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                ),
              ),
            ),
          ),

          // Financial Breakdown Grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildBreakdownItem(
                  'Net Earned',
                  moneyFormatter(earned),
                  const Color(0xFF0F172A),
                ),
                _buildBreakdownItem(
                  'Advances Deducted',
                  '- ${moneyFormatter(advAdj)}',
                  advAdj > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                ),
                _buildBreakdownItem(
                  'Store Offset',
                  '- ${moneyFormatter(purcAdj)}',
                  purcAdj > 0 ? const Color(0xFFD97706) : const Color(0xFF64748B),
                ),
                _buildBreakdownItem(
                  'Paid Out',
                  moneyFormatter(paid),
                  const Color(0xFF2563EB),
                ),
                _buildBreakdownItem(
                  'Remaining Balance',
                  moneyFormatter(remaining > 0 ? remaining : 0),
                  remaining > 0
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF16A34A),
                  isBold: true,
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Actions Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isPaid && canPay)
                  FilledButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.add_card_rounded, size: 15),
                    label: const Text('Record Payment'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                if (!isPaid && canApprove && availableAdvancePaise > 0)
                  OutlinedButton.icon(
                    onPressed: onAdjustAdvance,
                    icon: const Icon(Icons.remove_circle_outline, size: 15),
                    label: const Text('Adjust Advance'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                if (!isPaid && canApprove && staffPurchaseBalancePaise > 0)
                  OutlinedButton.icon(
                    onPressed: onOffsetPurchase,
                    icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                    label: const Text('Offset Shop Goods'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0xFFD97706)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: onShareSlip,
                  icon: const Icon(Icons.receipt_long_outlined, size: 15),
                  label: const Text('Salary Slip (PDF)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onShareStatement,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                  label: const Text('Statement'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                if (!isAcknowledged && canManage)
                  TextButton.icon(
                    onPressed: onAcknowledge,
                    icon: const Icon(Icons.draw_outlined, size: 15),
                    label: const Text('Acknowledge Receipt'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF132B45),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownItem(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// WIDGET: PASSBOOK LEDGER TILE
// -----------------------------------------------------------------------------

class _PassbookTile extends StatelessWidget {
  const _PassbookTile({
    required this.entry,
    required this.canPayStaffSalary,
    required this.onPayInvoice,
    required this.moneyFormatter,
    required this.dateFormatter,
  });

  final Map<String, dynamic> entry;
  final bool canPayStaffSalary;
  final VoidCallback onPayInvoice;
  final String Function(Object?) moneyFormatter;
  final String Function(String?) dateFormatter;

  @override
  Widget build(BuildContext context) {
    final type = (entry['transactionType'] as String? ?? 'TRANSACTION')
        .toUpperCase();
    final amountPaise = (entry['amountPaise'] as num?)?.toInt() ?? 0;
    final date = dateFormatter(entry['transactionDate']?.toString());
    final notes = entry['notes']?.toString();
    final ref = entry['referenceNo']?.toString();
    final mode = entry['paymentMode']?.toString() ?? 'CASH';

    final isStorePurchase = type == 'STORE_PURCHASE';

    final (color, icon, displayType, sign) = switch (type) {
      'CASH_ADVANCE' => (
        const Color(0xFFDC2626),
        Icons.payments_outlined,
        'Cash Advance Given',
        '− ',
      ),
      'UPI_ADVANCE' => (
        const Color(0xFFDC2626),
        Icons.qr_code_2_rounded,
        'UPI Advance Given',
        '− ',
      ),
      'BANK_ADVANCE' => (
        const Color(0xFFDC2626),
        Icons.account_balance_outlined,
        'Bank Advance Given',
        '− ',
      ),
      'STORE_PURCHASE' => (
        const Color(0xFFD97706),
        Icons.shopping_bag_outlined,
        'Store Goods Credit',
        '− ',
      ),
      'SALARY_PAYMENT' => (
        const Color(0xFF16A34A),
        Icons.check_circle_outline_rounded,
        'Salary Payment Paid',
        '+ ',
      ),
      'ADVANCE_ADJUSTMENT' => (
        const Color(0xFF2563EB),
        Icons.sync_rounded,
        'Advance Adjusted in Salary',
        '✓ ',
      ),
      'STORE_CREDIT_ADJUSTMENT' => (
        const Color(0xFF7C3AED),
        Icons.sync_rounded,
        'Store Credit Offset in Salary',
        '✓ ',
      ),
      'STAFF_PURCHASE_PAYMENT' => (
        const Color(0xFF16A34A),
        Icons.paid_outlined,
        'Staff Invoice Direct Paid',
        '✓ ',
      ),
      _ => (
        const Color(0xFF64748B),
        Icons.receipt_outlined,
        type.replaceAll('_', ' '),
        '',
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayType,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        mode.replaceAll('_', ' '),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    date,
                    if (ref != null && ref.isNotEmpty) 'Ref: $ref',
                    if (notes != null && notes.isNotEmpty) notes,
                  ].join(' • '),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${moneyFormatter(amountPaise)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (isStorePurchase && canPayStaffSalary) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: onPayInvoice,
                  child: const Text(
                    'Receive payment',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// INPUT MODELS & RECORD DIALOGS
// -----------------------------------------------------------------------------

class _AdvanceInput {
  const _AdvanceInput({
    required this.amountPaise,
    required this.date,
    required this.paymentMode,
    required this.reference,
    required this.notes,
  });

  final int amountPaise;
  final DateTime date;
  final String paymentMode;
  final String reference;
  final String notes;
}

class _RecordAdvanceDialog extends StatefulWidget {
  const _RecordAdvanceDialog({required this.employeeName});
  final String employeeName;

  @override
  State<_RecordAdvanceDialog> createState() => _RecordAdvanceDialogState();
}

class _RecordAdvanceDialogState extends State<_RecordAdvanceDialog> {
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _date = DateTime.now();
  String _mode = 'CASH';
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Record Staff Advance (Peshgi)'),
                Text(
                  'Employee: ${widget.employeeName}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  labelText: 'Advance Amount (₹) *',
                  prefixText: '₹ ',
                  prefixStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _mode,
                      decoration: InputDecoration(
                        labelText: 'Payment Mode *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(
                          value: 'BANK_TRANSFER',
                          child: Text('Bank Transfer'),
                        ),
                        DropdownMenuItem(
                          value: 'CHEQUE',
                          child: Text('Cheque'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _mode = v ?? 'CASH'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _date = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Advance Date *',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          suffixIcon: const Icon(Icons.calendar_month, size: 18),
                        ),
                        child: Text(
                          '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _refController,
                decoration: InputDecoration(
                  labelText: 'Reference Number / UPI Transaction ID',
                  hintText: 'e.g. UPI-928421 or Cheque #102',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Reason / Notes',
                  hintText: 'e.g. Family medical emergency, festival advance',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed =
                double.tryParse(_amountController.text.trim().replaceAll(',', ''));
            if (parsed == null || parsed <= 0) {
              setState(() => _error = 'Enter a valid amount greater than 0');
              return;
            }
            Navigator.pop(
              context,
              _AdvanceInput(
                amountPaise: (parsed * 100).round(),
                date: _date,
                paymentMode: _mode,
                reference: _refController.text.trim(),
                notes: _notesController.text.trim(),
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          child: const Text('Record Advance'),
        ),
      ],
    );
  }
}

class _SalaryProfileInput {
  const _SalaryProfileInput({
    required this.baseRatePaise,
    required this.salaryType,
    required this.paymentCycle,
    required this.outletBasisPoints,
  });

  final int baseRatePaise;
  final String salaryType;
  final String paymentCycle;
  final Map<String, int>? outletBasisPoints;
}

class _SalaryProfileDialog extends StatefulWidget {
  const _SalaryProfileDialog({
    required this.employeeName,
    required this.outlets,
    this.existingProfile,
  });

  final String employeeName;
  final List<OutletModel> outlets;
  final Map<String, dynamic>? existingProfile;

  @override
  State<_SalaryProfileDialog> createState() => _SalaryProfileDialogState();
}

class _SalaryProfileDialogState extends State<_SalaryProfileDialog> {
  final _rateController = TextEditingController();
  String _type = 'MONTHLY';
  String _cycle = 'MONTHLY';
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.existingProfile != null) {
      final ratePaise =
          (widget.existingProfile!['baseRatePaise'] as num?)?.toInt() ?? 0;
      _rateController.text = (ratePaise / 100).toStringAsFixed(2);
      _type = widget.existingProfile!['salaryType'] as String? ?? 'MONTHLY';
      _cycle = widget.existingProfile!['paymentCycle'] as String? ?? 'MONTHLY';
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF132B45).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tune_rounded, color: Color(0xFF132B45)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Configure Salary Rate Profile'),
                Text(
                  'Employee: ${widget.employeeName}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _rateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: 'Base Salary Rate (₹) *',
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: InputDecoration(
                      labelText: 'Wage Type *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'MONTHLY',
                        child: Text('Monthly Fixed'),
                      ),
                      DropdownMenuItem(
                        value: 'DAILY',
                        child: Text('Daily Wage'),
                      ),
                      DropdownMenuItem(
                        value: 'HOURLY',
                        child: Text('Hourly Rate'),
                      ),
                      DropdownMenuItem(
                        value: 'SHIFT_BASED',
                        child: Text('Shift-based'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? 'MONTHLY'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _cycle,
                    decoration: InputDecoration(
                      labelText: 'Payment Cycle *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'MONTHLY',
                        child: Text('Monthly'),
                      ),
                      DropdownMenuItem(
                        value: 'FORTNIGHTLY',
                        child: Text('14 Days'),
                      ),
                      DropdownMenuItem(
                        value: 'WEEKLY',
                        child: Text('Weekly'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _cycle = v ?? 'MONTHLY'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Changes become effective from the start of the next calendar month.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed =
                double.tryParse(_rateController.text.trim().replaceAll(',', ''));
            if (parsed == null || parsed <= 0) {
              setState(() => _error = 'Enter a valid rate greater than 0');
              return;
            }
            Map<String, int>? basisPoints;
            if (widget.outlets.length == 1) {
              basisPoints = {widget.outlets.single.outletId: 10000};
            }
            Navigator.pop(
              context,
              _SalaryProfileInput(
                baseRatePaise: (parsed * 100).round(),
                salaryType: _type,
                paymentCycle: _cycle,
                outletBasisPoints: basisPoints,
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF132B45),
          ),
          child: const Text('Save Salary Profile'),
        ),
      ],
    );
  }
}

class _PaymentInput {
  const _PaymentInput({
    required this.amountPaise,
    required this.date,
    required this.paymentMode,
  });

  final int amountPaise;
  final DateTime date;
  final String paymentMode;
}

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({
    required this.employeeName,
    required this.periodLabel,
    required this.remainingPayablePaise,
    required this.moneyFormatter,
  });

  final String employeeName;
  final String periodLabel;
  final int remainingPayablePaise;
  final String Function(Object?) moneyFormatter;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _amountController;
  DateTime _date = DateTime.now();
  String _mode = 'CASH';
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.remainingPayablePaise / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.add_card_rounded,
              color: Color(0xFF16A34A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Record Salary Payment'),
                Text(
                  '${widget.employeeName}  •  ${widget.periodLabel}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Remaining Net Payable:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF166534),
                    ),
                  ),
                  Text(
                    widget.moneyFormatter(widget.remainingPayablePaise),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF166534),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: 'Payment Amount (₹) *',
                prefixText: '₹ ',
                prefixStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: InputDecoration(
                      labelText: 'Payment Mode *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                      DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                      DropdownMenuItem(
                        value: 'BANK_TRANSFER',
                        child: Text('Bank Transfer'),
                      ),
                      DropdownMenuItem(
                        value: 'CHEQUE',
                        child: Text('Cheque'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _mode = v ?? 'CASH'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() => _date = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Payment Date *',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        suffixIcon: const Icon(Icons.calendar_month, size: 18),
                      ),
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed =
                double.tryParse(_amountController.text.trim().replaceAll(',', ''));
            if (parsed == null || parsed <= 0) {
              setState(() => _error = 'Enter a valid amount greater than 0');
              return;
            }
            final amountPaise = (parsed * 100).round();
            if (amountPaise > widget.remainingPayablePaise) {
              setState(() => _error = 'Payment cannot exceed remaining payable.');
              return;
            }
            Navigator.pop(
              context,
              _PaymentInput(
                amountPaise: amountPaise,
                date: _date,
                paymentMode: _mode,
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF16A34A),
          ),
          child: const Text('Disburse Payment'),
        ),
      ],
    );
  }
}

class _AdjustAdvanceDialog extends StatefulWidget {
  const _AdjustAdvanceDialog({
    required this.availableAdvancePaise,
    required this.remainingPayablePaise,
    required this.maxAdjustablePaise,
    required this.moneyFormatter,
  });

  final int availableAdvancePaise;
  final int remainingPayablePaise;
  final int maxAdjustablePaise;
  final String Function(Object?) moneyFormatter;

  @override
  State<_AdjustAdvanceDialog> createState() => _AdjustAdvanceDialogState();
}

class _AdjustAdvanceDialogState extends State<_AdjustAdvanceDialog> {
  late final TextEditingController _amountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.maxAdjustablePaise / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.remove_circle_outline, color: Color(0xFFDC2626)),
          SizedBox(width: 10),
          Text('Adjust Mid-Month Advance'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deduct mid-month cash/UPI advances against this approved salary period.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Advance:',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                  widget.moneyFormatter(widget.availableAdvancePaise),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Deduction Amount (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed =
                double.tryParse(_amountController.text.trim().replaceAll(',', ''));
            if (parsed == null || parsed <= 0) {
              setState(() => _error = 'Enter a valid amount');
              return;
            }
            final amountPaise = (parsed * 100).round();
            if (amountPaise > widget.maxAdjustablePaise) {
              setState(() => _error = 'Amount exceeds maximum adjustable balance.');
              return;
            }
            Navigator.pop(context, amountPaise);
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          child: const Text('Apply Advance Deduction'),
        ),
      ],
    );
  }
}

class _OffsetPurchaseDialog extends StatefulWidget {
  const _OffsetPurchaseDialog({
    required this.availableReceivablePaise,
    required this.remainingPayablePaise,
    required this.maxOffsetPaise,
    required this.moneyFormatter,
  });

  final int availableReceivablePaise;
  final int remainingPayablePaise;
  final int maxOffsetPaise;
  final String Function(Object?) moneyFormatter;

  @override
  State<_OffsetPurchaseDialog> createState() => _OffsetPurchaseDialogState();
}

class _OffsetPurchaseDialogState extends State<_OffsetPurchaseDialog> {
  late final TextEditingController _amountController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.maxOffsetPaise / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.shopping_bag_outlined, color: Color(0xFFD97706)),
          SizedBox(width: 10),
          Text('Offset Store Purchase Credit'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deduct shop goods taken on credit by this staff member against their salary.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Store Credit Due:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                ),
                Text(
                  widget.moneyFormatter(widget.availableReceivablePaise),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF92400E),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Offset Amount (₹)',
              prefixText: '₹ ',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final parsed =
                double.tryParse(_amountController.text.trim().replaceAll(',', ''));
            if (parsed == null || parsed <= 0) {
              setState(() => _error = 'Enter a valid amount');
              return;
            }
            final amountPaise = (parsed * 100).round();
            if (amountPaise > widget.maxOffsetPaise) {
              setState(() => _error = 'Amount exceeds maximum offsettable balance.');
              return;
            }
            Navigator.pop(context, amountPaise);
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD97706),
          ),
          child: const Text('Apply Purchase Offset'),
        ),
      ],
    );
  }
}

class _ApprovalAdjustmentsInput {
  const _ApprovalAdjustmentsInput({
    required this.workUnitsMilli,
    required this.bonusPaise,
    required this.additionalOvertimePaise,
    required this.otherDeductionsPaise,
    required this.deductionPerUnpaidLeavePaise,
  });

  final int workUnitsMilli;
  final int bonusPaise;
  final int additionalOvertimePaise;
  final int otherDeductionsPaise;
  final int deductionPerUnpaidLeavePaise;
}

class _ApprovePeriodDialog extends StatefulWidget {
  const _ApprovePeriodDialog({
    required this.employeeName,
    required this.salaryType,
    required this.baseRatePaise,
    required this.start,
    required this.end,
    required this.attendanceCount,
    required this.attendanceOvertimePaise,
    required this.initialUnits,
    required this.moneyFormatter,
  });

  final String employeeName;
  final String salaryType;
  final int baseRatePaise;
  final DateTime start;
  final DateTime end;
  final int attendanceCount;
  final int attendanceOvertimePaise;
  final int initialUnits;
  final String Function(Object?) moneyFormatter;

  @override
  State<_ApprovePeriodDialog> createState() => _ApprovePeriodDialogState();
}

class _ApprovePeriodDialogState extends State<_ApprovePeriodDialog> {
  late final TextEditingController _unitsController;
  final _bonusController = TextEditingController(text: '0');
  final _overtimeController = TextEditingController(text: '0');
  final _deductionsController = TextEditingController(text: '0');
  final _leaveDeductionController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _unitsController = TextEditingController(
      text: widget.initialUnits > 0
          ? (widget.initialUnits / 1000).toStringAsFixed(1)
          : (widget.salaryType == 'MONTHLY' ? '1' : '30'),
    );
  }

  @override
  void dispose() {
    _unitsController.dispose();
    _bonusController.dispose();
    _overtimeController.dispose();
    _deductionsController.dispose();
    _leaveDeductionController.dispose();
    super.dispose();
  }

  int _calcNet() {
    final unitsMilli =
        ((double.tryParse(_unitsController.text.trim()) ?? 0.0) * 1000).round();
    final bonus =
        ((double.tryParse(_bonusController.text.trim()) ?? 0.0) * 100).round();
    final extraOvertime =
        ((double.tryParse(_overtimeController.text.trim()) ?? 0.0) * 100)
            .round();
    final deductions =
        ((double.tryParse(_deductionsController.text.trim()) ?? 0.0) * 100)
            .round();

    try {
      final calc = StaffSalaryRepository.previewPeriodCalculation(
        salaryType: widget.salaryType,
        baseRatePaise: widget.baseRatePaise,
        periodStart: widget.start,
        periodEnd: widget.end,
        workUnitsMilli: unitsMilli,
        bonusPaise: bonus,
        overtimePaise: widget.attendanceOvertimePaise + extraOvertime,
        approvedDeductionsPaise: deductions,
      );
      return calc['netEarnedPaise'] ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final netEarned = _calcNet();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF132B45).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.verified_outlined,
              color: Color(0xFF132B45),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Approve Period Salary'),
                Text(
                  '${widget.employeeName}  •  ${widget.start.day}/${widget.start.month} to ${widget.end.day}/${widget.end.month}/${widget.end.year}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Base Rate: ${widget.moneyFormatter(widget.baseRatePaise)} (${widget.salaryType.toLowerCase()})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Approved Attendance: ${widget.attendanceCount} records',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    if (widget.attendanceOvertimePaise > 0)
                      Text(
                        'OT: +${widget.moneyFormatter(widget.attendanceOvertimePaise)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (widget.salaryType != 'MONTHLY') ...[
                TextField(
                  controller: _unitsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'Approved Work Units (${widget.salaryType == 'HOURLY' ? 'Hours' : 'Days/Shifts'})',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bonusController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Bonus (₹)',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _overtimeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Extra Overtime (₹)',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _leaveDeductionController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Deduction per Absent Day (₹)',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _deductionsController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Other Deductions (₹)',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Net preview box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF16A34A)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Calculated Net Earned:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF166534),
                      ),
                    ),
                    Text(
                      widget.moneyFormatter(netEarned),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF166534),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final units =
                ((double.tryParse(_unitsController.text.trim()) ?? 0.0) * 1000)
                    .round();
            final bonus =
                ((double.tryParse(_bonusController.text.trim()) ?? 0.0) * 100)
                    .round();
            final extraOT =
                ((double.tryParse(_overtimeController.text.trim()) ?? 0.0) * 100)
                    .round();
            final deductions =
                ((double.tryParse(_deductionsController.text.trim()) ?? 0.0) *
                        100)
                    .round();
            final perLeave =
                ((double.tryParse(_leaveDeductionController.text.trim()) ?? 0.0) *
                        100)
                    .round();

            Navigator.pop(
              context,
              _ApprovalAdjustmentsInput(
                workUnitsMilli: units,
                bonusPaise: bonus,
                additionalOvertimePaise: extraOT,
                otherDeductionsPaise: deductions,
                deductionPerUnpaidLeavePaise: perLeave,
              ),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF132B45),
          ),
          child: const Text('Confirm & Approve Salary'),
        ),
      ],
    );
  }
}

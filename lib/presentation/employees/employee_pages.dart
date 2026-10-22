import 'package:flutter/material.dart';

import '../../core/permissions/permission_id_matcher.dart';
import '../../core/utils/validators.dart';
import '../../data/models/employee_model.dart';
import '../staff_salary/staff_salary_page.dart';
import '../../data/models/permission_model.dart';
import '../app_controller.dart';

class EmployeeManagementPage extends StatefulWidget {
  const EmployeeManagementPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<EmployeeManagementPage> createState() => _EmployeeManagementPageState();
}

class _EmployeeManagementPageState extends State<EmployeeManagementPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.loadEmployees();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller.appContext?.accountType != 'owner') {
      return const Center(child: Text('Only an owner can manage employees.'));
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final businessId = controller.appContext?.businessId;
        final outletId = controller.appContext?.outletId;
        final visibleEmployees = controller.employees.where((employee) {
          final matchesBusiness =
              businessId == null || employee.businessIds.contains(businessId);
          final matchesOutlet =
              outletId == null || employee.outletIds.contains(outletId);
          return matchesBusiness && matchesOutlet;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: compact ? WrapAlignment.end : WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Refresh employees',
                      onPressed: controller.loadEmployees,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openAddEmployee(context),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add Employee'),
                    ),
                  ],
                );
                final title = Text(
                  'Employees',
                  style: Theme.of(context).textTheme.headlineSmall,
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [title, const SizedBox(height: 8), actions],
                      )
                    : Row(
                        children: [
                          Expanded(child: title),
                          actions,
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),
            if (controller.employeesLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (controller.employeesError != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(controller.employeesError!),
                  trailing: TextButton(
                    onPressed: controller.loadEmployees,
                    child: const Text('Retry'),
                  ),
                ),
              )
            else if (controller.employees.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'No employees yet. Add an employee to grant business access.',
                  ),
                ),
              )
            else if (visibleEmployees.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'No employees are assigned to this outlet. Add an employee '
                    'or edit an existing employee to grant outlet access.',
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < visibleEmployees.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(_initial(visibleEmployees[i].name)),
                        ),
                        title: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(visibleEmployees[i].name),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                visibleEmployees[i].isActive
                                    ? 'Active'
                                    : 'Inactive',
                              ),
                              backgroundColor: visibleEmployees[i].isActive
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              labelStyle: TextStyle(
                                color: visibleEmployees[i].isActive
                                    ? Colors.green.shade900
                                    : Colors.red.shade900,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          [
                            visibleEmployees[i].isTemporaryWorker
                                ? 'Temporary staff · no app login${visibleEmployees[i].mobile == null ? '' : ' · ${visibleEmployees[i].mobile}'}'
                                : '${visibleEmployees[i].email}  •  ${visibleEmployees[i].mobile ?? ''}',
                            'Business: ${_assignedNames(visibleEmployees[i].businessIds, controller.businesses.map((item) => (item.businessId, item.businessName)).toList())}',
                            'Outlet: ${_assignedNames(visibleEmployees[i].outletIds, controller.outlets.map((item) => (item.outletId, item.outletName)).toList())}',
                            'Role: ${_assignedNames(visibleEmployees[i].roleIds, controller.activeRoles.map((item) => (item.roleId, item.roleName)).toList())}',
                          ].join('\n'),
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Employee actions',
                          onSelected: (action) {
                            switch (action) {
                              case 'salary':
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => StaffSalaryPage(
                                      controller: controller,
                                      employeeId:
                                          visibleEmployees[i].employeeId,
                                    ),
                                  ),
                                );
                                break;
                              case 'status':
                                _toggleEmployeeStatus(
                                  context,
                                  visibleEmployees[i],
                                );
                                break;
                              case 'edit':
                                _openEditEmployee(context, visibleEmployees[i]);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (controller.canViewStaffSalary())
                              const PopupMenuItem(
                                value: 'salary',
                                child: Text('Open salary khata'),
                              ),
                            PopupMenuItem(
                              value: 'status',
                              child: Text(
                                visibleEmployees[i].isActive
                                    ? 'Deactivate employee'
                                    : 'Activate employee',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit employee'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _assignedNames(
    List<String> ids,
    List<(String, String)> names,
  ) {
    if (ids.isEmpty) return 'None';
    return ids.map((id) {
      for (final (knownId, name) in names) {
        if (knownId == id) return name;
      }
      return id;
    }).join(', ');
  }

  Future<void> _openAddEmployee(BuildContext context) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddEmployeePage(controller: widget.controller),
      ),
    );
    if (created == true) await widget.controller.loadEmployees();
  }

  Future<void> _toggleEmployeeStatus(
    BuildContext context,
    EmployeeModel employee,
  ) async {
    final activate = !employee.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${activate ? 'Activate' : 'Deactivate'} employee?'),
        content: Text(
          activate
              ? '${employee.name} will be able to sign in again.'
              : '${employee.name} will be unable to sign in while inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final saved = await widget.controller.setEmployeeActive(employee, activate);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? '${employee.name} ${activate ? 'activated' : 'deactivated'}.'
                : widget.controller.error,
          ),
        ),
      );
    }
  }

  Future<void> _openEditEmployee(
    BuildContext context,
    EmployeeModel employee,
  ) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            AddEmployeePage(controller: widget.controller, employee: employee),
      ),
    );
  }
}

class AddEmployeePage extends StatefulWidget {
  const AddEmployeePage({super.key, required this.controller, this.employee});
  final AppController controller;
  final EmployeeModel? employee;

  @override
  State<AddEmployeePage> createState() => _AddEmployeePageState();
}

class _AddEmployeePageState extends State<AddEmployeePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final Set<String> _businessIds = {};
  final Set<String> _outletIds = {};
  final Set<String> _roleIds = {};
  final Set<String> _permissionIds = {};
  bool _dirty = false;
  String _status = 'active';

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    if (employee != null) {
      _name.text = employee.name;
      _mobile.text = employee.mobile ?? '';
      _email.text = employee.email;
      _code.text = employee.employeeCode ?? '';
      _businessIds.addAll(employee.businessIds);
      _outletIds.addAll(employee.outletIds);
      _roleIds.addAll(employee.roleIds);
      _status = employee.status.toLowerCase() == 'inactive'
          ? 'inactive'
          : 'active';
    }
    for (final field in [_name, _mobile, _email, _code, _password]) {
      field.addListener(() => _dirty = true);
    }
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await widget.controller.loadEmployeeMasters();
    final employee = widget.employee;
    if (!mounted || employee == null) return;
    setState(() {
      _businessIds.retainAll(
        widget.controller.businesses.map((business) => business.businessId),
      );
      _roleIds.retainAll(
        widget.controller.activeRoles.map((role) => role.roleId),
      );
      _permissionIds
        ..clear()
        ..addAll(employee.permissionIds);
    });
    await widget.controller.loadEmployeeOutlets(_businessIds.toList());
    if (!mounted) return;
    setState(() {
      _outletIds.removeWhere(
        (id) => !widget.controller.employeeOutlets.any(
          (outlet) => outlet.outletId == id,
        ),
      );
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_dirty ||
        _businessIds.isNotEmpty ||
        _outletIds.isNotEmpty ||
        _roleIds.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Changes?'),
          content: const Text(
            'Your entered employee information will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _toggleBusiness(String id, bool selected) async {
    setState(() {
      selected ? _businessIds.add(id) : _businessIds.remove(id);
      _dirty = true;
    });
    await widget.controller.loadEmployeeOutlets(_businessIds.toList());
    if (mounted) {
      setState(
        () => _outletIds.removeWhere(
          (id) => !widget.controller.employeeOutlets.any(
            (outlet) => outlet.outletId == id,
          ),
        ),
      );
    }
  }

  void _toggleRole(String id, bool selected) {
    setState(() {
      selected ? _roleIds.add(id) : _roleIds.remove(id);
      _dirty = true;
    });
  }

  Set<String> get _selectedRolePermissionIds => widget.controller.activeRoles
      .where((role) => _roleIds.contains(role.roleId))
      .expand((role) => role.permissions)
      .toSet();

  Set<String> get _unmatchedRolePermissions {
    final activePermissions = widget.controller.activePermissions;
    if (activePermissions.isEmpty) return const {};
    return _selectedRolePermissionIds
        .where(
          (rolePermission) => !activePermissions.any(
            (permission) => PermissionIdMatcher.matches(
              permission.permissionId,
              rolePermission,
            ),
          ),
        )
        .toSet();
  }

  Future<void> _submit() async {
    if (_form.currentState?.validate() != true) return;
    if (_unmatchedRolePermissions.isNotEmpty) {
      setState(() {});
      return;
    }
    final employee = widget.employee;
    final succeeded = employee == null
        ? await widget.controller.createEmployee(
            name: _name.text,
            mobile: _mobile.text,
            email: _email.text,
            password: _password.text,
            employeeCode: _code.text,
            businessIds: _businessIds.toList(),
            outletIds: _outletIds.toList(),
            roleIds: _roleIds.toList(),
            permissionIds: _permissionIds.toList(),
            status: _status,
          )
        : await widget.controller.updateEmployee(
            employee: employee,
            name: _name.text,
            mobile: _mobile.text,
            employeeCode: _code.text,
            businessIds: _businessIds.toList(),
            outletIds: _outletIds.toList(),
            roleIds: _roleIds.toList(),
            permissionIds: _permissionIds.toList(),
            status: _status,
          );
    if (succeeded && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(
              widget.employee == null ? 'Add Employee' : 'Edit Employee',
            ),
            leading: IconButton(
              onPressed: controller.employeeSaving ? null : _close,
              icon: const Icon(Icons.close),
            ),
          ),
          body: controller.employeeMastersLoading
              ? const Center(child: CircularProgressIndicator())
              : controller.employeeMastersError != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.employeeMastersError!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: controller.loadEmployeeMasters,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      _sectionTitle(context, 'Basic information'),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Employee Name *',
                        ),
                        validator: (value) =>
                            AppValidators.required(value, 'employee name'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _mobile,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Number *',
                        ),
                        validator: AppValidators.indianPhone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        readOnly: widget.employee != null,
                        decoration: const InputDecoration(labelText: 'Email *'),
                        validator: AppValidators.email,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                          labelText: 'Employee Code (optional)',
                        ),
                      ),
                      if (widget.employee == null) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Temporary Password *',
                          ),
                          validator: (value) => (value?.length ?? 0) < 6
                              ? 'Enter a temporary password with at least 6 characters.'
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Share this temporary password securely with the employee.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 20),
                      _sectionTitle(context, 'Business access'),
                      if (controller.businesses.isEmpty)
                        const Text(
                          'No active businesses are available for this owner.',
                        ),
                      for (final business in controller.businesses)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _businessIds.contains(business.businessId),
                          title: Text(business.businessName),
                          subtitle: Text(business.businessTypeName),
                          onChanged: (value) => _toggleBusiness(
                            business.businessId,
                            value == true,
                          ),
                        ),
                      const SizedBox(height: 12),
                      _sectionTitle(context, 'Outlet access'),
                      if (controller.employeeOutletError != null)
                        Text(
                          controller.employeeOutletError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (_businessIds.isEmpty)
                        const Text('Select one or more businesses first.'),
                      if (controller.employeeOutletsLoading)
                        const LinearProgressIndicator(),
                      if (_businessIds.isNotEmpty &&
                          controller.employeeOutlets.isEmpty &&
                          controller.employeeOutletError == null)
                        const Text(
                          'No active outlets are available for the selected businesses.',
                        ),
                      for (final outlet in controller.employeeOutlets)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _outletIds.contains(outlet.outletId),
                          title: Text(outlet.outletName),
                          subtitle: Text(
                            '${outlet.outletTypeName} · ${controller.businesses.firstWhere((b) => b.businessId == outlet.businessId).businessName}',
                          ),
                          onChanged: (value) => setState(() {
                            value == true
                                ? _outletIds.add(outlet.outletId)
                                : _outletIds.remove(outlet.outletId);
                            _dirty = true;
                          }),
                        ),
                      const SizedBox(height: 12),
                      _sectionTitle(context, 'Roles'),
                      if (controller.activeRoles.isEmpty)
                        const Text(
                          'No active roles are configured in Firestore.',
                        ),
                      for (final role in controller.activeRoles)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _roleIds.contains(role.roleId),
                          title: Text(role.roleName),
                          subtitle: role.description == null
                              ? null
                              : Text(role.description!),
                          onChanged: (value) =>
                              _toggleRole(role.roleId, value == true),
                        ),
                      const SizedBox(height: 12),
                      _PermissionTree(
                        permissions: controller.activePermissions,
                        selectedIds: _permissionIds,
                        onChanged: (id, selected) => setState(() {
                          selected
                              ? _permissionIds.add(id)
                              : _permissionIds.remove(id);
                          _dirty = true;
                        }),
                      ),
                      if (_unmatchedRolePermissions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Some selected-role permissions have no matching active entries in the permissions collection: ${_unmatchedRolePermissions.join(', ')}. Fix the permission IDs or activate those permission records before saving.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Account Status',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text(
                              'Active',
                              style: TextStyle(color: Colors.green),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text(
                              'Inactive',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _status = value ?? 'active';
                          _dirty = true;
                        }),
                      ),
                      if (controller.error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          controller.error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: controller.employeeSaving ? null : _submit,
                        icon: controller.employeeSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1),
                        label: Text(
                          widget.employee == null
                              ? 'Create Employee'
                              : 'Save Changes',
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PermissionTree extends StatelessWidget {
  const _PermissionTree({
    required this.permissions,
    required this.selectedIds,
    required this.onChanged,
  });
  final List<PermissionModel> permissions;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    if (permissions.isEmpty) {
      return const Text('No active permissions are configured.');
    }
    final groups = <String, List<PermissionModel>>{};
    for (final permission in permissions) {
      groups.putIfAbsent(permission.groupName, () => []).add(permission);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(context, 'Additional Permissions'),
        for (final entry in groups.entries)
          Builder(
            builder: (context) {
              final ids = entry.value
                  .map((permission) => permission.permissionId)
                  .toList();
              final selectedCount = ids.where(selectedIds.contains).length;
              final parentValue = selectedCount == 0
                  ? false
                  : selectedCount == ids.length
                  ? true
                  : null;
              return Card(
                child: ExpansionTile(
                  leading: Checkbox(
                    tristate: true,
                    value: parentValue,
                    onChanged: (value) {
                      final select = value != false;
                      for (final id in ids) {
                        onChanged(id, select);
                      }
                    },
                  ),
                  title: Text(entry.key),
                  subtitle: Text('$selectedCount of ${ids.length} selected'),
                  children: [
                    for (final permission in entry.value)
                      CheckboxListTile(
                        contentPadding: const EdgeInsets.only(
                          left: 28,
                          right: 12,
                        ),
                        value: selectedIds.contains(permission.permissionId),
                        title: Text(permission.name),
                        subtitle: permission.description == null
                            ? null
                            : Text(permission.description!),
                        onChanged: (value) =>
                            onChanged(permission.permissionId, value == true),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

Widget _sectionTitle(BuildContext context, String title) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    title,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700),
  ),
);

String _initial(String value) =>
    value.trim().isEmpty ? '?' : value.trim().characters.first.toUpperCase();

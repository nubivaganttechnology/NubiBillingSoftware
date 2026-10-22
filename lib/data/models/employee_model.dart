class EmployeeModel {
  const EmployeeModel({
    required this.employeeId,
    required this.uid,
    required this.ownerUid,
    required this.name,
    required this.email,
    required this.status,
    required this.businessIds,
    required this.outletIds,
    required this.roleIds,
    this.mobile,
    this.employeeCode,
    this.permissionIds = const [],
    this.hasPermissionIds = false,
    this.joiningDate,
  });

  final String employeeId, uid, ownerUid, name, email, status;
  final String? mobile, employeeCode;
  final List<String> businessIds, outletIds, roleIds, permissionIds;
  final bool hasPermissionIds;
  final DateTime? joiningDate;
  bool get loginEnabled => uid.isNotEmpty && email.isNotEmpty;
  bool get isTemporaryWorker => !loginEnabled;
  String? get phone => mobile;
  String? get roleId => roleIds.isEmpty ? null : roleIds.first;

  bool get isActive => status.toLowerCase() == 'active';

  factory EmployeeModel.fromData(String id, Map<String, dynamic> data) {
    String requiredString(String key, {bool allowEmpty = false}) {
      final value = data[key];
      if (value is! String || (!allowEmpty && value.isEmpty)) {
        throw FormatException('Invalid employee $key');
      }
      return value;
    }

    List<String> strings(String key) =>
        (data[key] as List? ?? const []).whereType<String>().toList();
    final storedRoleIds = strings('roleIds');
    final storedPermissionIds = strings('permissionIds');
    final legacyRoleId = data['roleId'] as String?;
    final roleIds = storedRoleIds.isNotEmpty
        ? storedRoleIds
        : legacyRoleId == null || legacyRoleId.isEmpty
        ? const <String>[]
        : <String>[legacyRoleId];

    return EmployeeModel(
      // The Firestore document ID is the canonical employee key. A stale or
      // malformed employeeId field must not make reads target a different doc.
      employeeId: id,
      uid: requiredString('uid', allowEmpty: data['loginEnabled'] == false),
      ownerUid: requiredString('ownerUid'),
      name: requiredString('name'),
      email: requiredString('email', allowEmpty: data['loginEnabled'] == false),
      status: requiredString('status'),
      roleIds: roleIds,
      mobile: (data['mobile'] ?? data['phone']) as String?,
      employeeCode: data['employeeCode'] as String?,
      permissionIds: storedPermissionIds,
      hasPermissionIds: storedPermissionIds.isNotEmpty,
      joiningDate: data['joiningDate'] as DateTime?,
      businessIds: strings('businessIds'),
      outletIds: strings('outletIds'),
    );
  }
}

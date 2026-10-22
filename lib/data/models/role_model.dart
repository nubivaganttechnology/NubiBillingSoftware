class RoleModel {
  const RoleModel({
    required this.roleId,
    required this.roleName,
    required this.permissions,
    required this.status,
    this.description,
  });
  final String roleId, roleName, status;
  final String? description;
  final List<String> permissions;
  bool get isActive => status.toLowerCase() == 'active';

  factory RoleModel.fromData(String id, Map<String, dynamic> data) {
    final rawPermissions = data['permissionIds'] ?? data['permissions'];
    return RoleModel(
      roleId: (data['roleId'] as String?) ?? id,
      roleName: data['roleName'] as String? ?? data['name'] as String? ?? '',
      permissions: (rawPermissions as List? ?? const [])
          .whereType<String>()
          .toList(),
      status: data['isActive'] == true
          ? 'active'
          : data['isActive'] == false
          ? 'inactive'
          : data['status'] as String? ?? '',
      description: data['description'] as String?,
    );
  }
}

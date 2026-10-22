class PermissionModel {
  const PermissionModel({
    required this.permissionId,
    required this.groupId,
    required this.groupName,
    required this.name,
    required this.isActive,
    required this.displayOrder,
    this.description,
  });

  final String permissionId, groupId, groupName, name;
  final bool isActive;
  final int displayOrder;
  final String? description;

  factory PermissionModel.fromData(String id, Map<String, dynamic> data) {
    final active = data['isActive'];
    final status = (data['status'] as String?)?.toLowerCase();
    return PermissionModel(
      permissionId: data['permissionId'] as String? ?? id,
      groupId: data['groupId'] as String? ?? 'other',
      groupName: data['groupName'] as String? ?? 'Other',
      name: data['name'] as String? ?? id,
      isActive: active is bool ? active : status == 'active',
      displayOrder: data['displayOrder'] is int
          ? data['displayOrder'] as int
          : 0,
      description: data['description'] as String?,
    );
  }
}

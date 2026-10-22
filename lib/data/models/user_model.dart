class UserModel {
  const UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.accountType,
    required this.isActive,
    this.phone,
    this.roleId,
    this.createdAt,
    this.updatedAt,
  });

  final String uid, email, name, accountType;
  final String? phone, roleId;
  final bool isActive;
  final DateTime? createdAt, updatedAt;

  factory UserModel.fromData(String authUid, Map<String, dynamic> fields) {
    String? string(String key) => fields[key] as String?;
    final uid = string('uid') ?? authUid;
    final type = string('accountType')?.toLowerCase();
    final active = fields['isActive'];
    if (uid != authUid ||
        type == null ||
        !const {'owner', 'employee'}.contains(type) ||
        active is! bool ||
        string('name') == null ||
        string('email') == null) {
      throw const FormatException('Invalid user profile');
    }
    return UserModel(
      uid: uid,
      email: string('email')!,
      name: string('name')!,
      accountType: type,
      isActive: active,
      phone: string('phone') ?? string('mobile'),
      roleId: string('roleId'),
      createdAt: fields['createdAt'] as DateTime?,
      updatedAt: fields['updatedAt'] as DateTime?,
    );
  }
}

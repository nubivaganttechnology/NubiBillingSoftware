class AppContext {
  const AppContext({
    required this.uid,
    required this.accountType,
    required this.ownerUid,
    this.employeeId,
    this.roleId,
    this.businessId,
    this.outletId,
    this.permissions = const [],
  });

  final String uid, accountType, ownerUid;
  final String? employeeId, roleId, businessId, outletId;
  final List<String> permissions;

  AppContext copyWith({
    String? businessId,
    String? outletId,
    bool clearOutlet = false,
  }) => AppContext(
    uid: uid,
    accountType: accountType,
    ownerUid: ownerUid,
    employeeId: employeeId,
    roleId: roleId,
    businessId: businessId ?? this.businessId,
    outletId: clearOutlet ? null : outletId ?? this.outletId,
    permissions: permissions,
  );
}

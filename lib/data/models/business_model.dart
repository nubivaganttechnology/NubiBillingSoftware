class BusinessModel {
  const BusinessModel({
    required this.businessId,
    required this.ownerUid,
    required this.businessName,
    required this.normalizedBusinessName,
    required this.businessTypeId,
    required this.businessTypeName,
    required this.isActive,
    this.email,
    this.phone,
    this.gstin,
    this.gstinVerified = false,
    this.gstinVerifiedAt,
    this.gstLegalName,
    this.gstTradeName,
    this.gstStatus,
    this.gstState,
    this.logoUrl,
    this.address,
  });

  final String businessId, ownerUid, businessName, normalizedBusinessName;
  final String businessTypeId, businessTypeName;
  final bool isActive, gstinVerified;
  final String? email, phone, gstin, gstLegalName, gstTradeName, gstStatus;
  final String? gstState, logoUrl, address;
  final DateTime? gstinVerifiedAt;

  // Compatibility getters for existing selector/dashboard widgets and old records.
  String get businessType => businessTypeName;
  String get status => isActive ? 'active' : 'inactive';

  factory BusinessModel.fromData(String id, Map<String, dynamic> data) {
    final storedId = data['businessId'] as String?;
    final oldType = data['businessType'];
    final typeId =
        data['businessTypeId'] as String? ??
        (oldType is String ? oldType : null);
    final typeName =
        data['businessTypeName'] as String? ??
        (oldType is String ? oldType : null);
    final active = data['isActive'] is bool
        ? data['isActive'] as bool
        : (data['status'] as String?)?.toLowerCase() == 'active';
    if ((storedId != null && storedId != id) ||
        data['ownerUid'] is! String ||
        data['businessName'] is! String ||
        typeId == null ||
        typeName == null) {
      throw const FormatException('Invalid business record');
    }
    final name = data['businessName'] as String;
    return BusinessModel(
      businessId: id,
      ownerUid: data['ownerUid'] as String,
      businessName: name,
      normalizedBusinessName:
          data['normalizedBusinessName'] as String? ??
          name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      businessTypeId: typeId,
      businessTypeName: typeName,
      isActive: active,
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      gstin: data['gstin'] as String?,
      gstinVerified: data['gstinVerified'] == true,
      gstinVerifiedAt: data['gstinVerifiedAt'] as DateTime?,
      gstLegalName: data['gstLegalName'] as String?,
      gstTradeName: data['gstTradeName'] as String?,
      gstStatus: data['gstStatus'] as String?,
      gstState: data['gstState'] as String?,
      logoUrl: data['logoUrl'] as String?,
      address: data['address'] as String?,
    );
  }
}

class OutletModel {
  const OutletModel({
    required this.outletId,
    required this.businessId,
    required this.ownerUid,
    required this.tenantId,
    required this.outletName,
    this.outletCode,
    required this.outletTypeId,
    required this.outletTypeName,
    required this.isActive,
    this.address,
    this.contactNumber,
    this.gstin,
    this.gstinVerified = false,
    this.gstinVerifiedAt,
    this.gstLegalName,
    this.gstTradeName,
    this.gstStatus,
    this.gstState,
    this.latitude,
    this.longitude,
    this.geofenceRadiusMeters = 100.0,
  });

  final String outletId, tenantId, businessId, ownerUid, outletName;
  final String? outletCode;
  final String outletTypeId, outletTypeName;
  final bool isActive, gstinVerified;
  final String? address, contactNumber, gstin;
  final String? gstLegalName, gstTradeName, gstStatus, gstState;
  final DateTime? gstinVerifiedAt;
  final double? latitude, longitude;
  final double geofenceRadiusMeters;

  String get outletType => outletTypeName;
  String get status => isActive ? 'active' : 'inactive';

  OutletModel copyWith({
    double? latitude,
    double? longitude,
    double? geofenceRadiusMeters,
  }) => OutletModel(
    outletId: outletId,
    businessId: businessId,
    ownerUid: ownerUid,
    tenantId: tenantId,
    outletName: outletName,
    outletCode: outletCode,
    outletTypeId: outletTypeId,
    outletTypeName: outletTypeName,
    isActive: isActive,
    address: address,
    contactNumber: contactNumber,
    gstin: gstin,
    gstinVerified: gstinVerified,
    gstinVerifiedAt: gstinVerifiedAt,
    gstLegalName: gstLegalName,
    gstTradeName: gstTradeName,
    gstStatus: gstStatus,
    gstState: gstState,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    geofenceRadiusMeters: geofenceRadiusMeters ?? this.geofenceRadiusMeters,
  );

  factory OutletModel.fromData(String id, Map<String, dynamic> data) {
    final storedId = data['outletId'] as String?;
    final ownerUid = data['ownerUid'] as String? ?? data['tenantId'] as String?;
    final tenantId = data['tenantId'] as String? ?? ownerUid;
    final oldType = data['outletType'];
    final typeId =
        data['outletTypeId'] as String? ??
        data['businessSubTypeId'] as String? ??
        (oldType is String ? oldType : null);
    final typeName =
        data['outletTypeName'] as String? ??
        (oldType is String ? oldType : null);
    final storedStatus = (data['status'] as String?)?.toUpperCase();
    final active = data['isActive'] is bool
        ? data['isActive'] as bool
        : storedStatus == 'ACTIVE';
    if ((storedId != null && storedId != id) ||
        data['businessId'] is! String ||
        ownerUid == null ||
        tenantId == null ||
        data['outletName'] is! String ||
        typeId == null ||
        typeName == null) {
      throw const FormatException('Invalid outlet record');
    }
    return OutletModel(
      outletId: id,
      tenantId: tenantId,
      businessId: data['businessId'] as String,
      ownerUid: ownerUid,
      outletName: data['outletName'] as String,
      outletCode: data['outletCode'] as String? ?? data['code'] as String?,
      outletTypeId: typeId,
      outletTypeName: typeName,
      isActive: active,
      address: data['address'] as String?,
      contactNumber: data['contactNumber'] as String?,
      gstin: data['gstin'] as String?,
      gstinVerified: data['gstinVerified'] == true,
      gstinVerifiedAt: data['gstinVerifiedAt'] as DateTime?,
      gstLegalName: data['gstLegalName'] as String?,
      gstTradeName: data['gstTradeName'] as String?,
      gstStatus: data['gstStatus'] as String?,
      gstState: data['gstState'] as String?,
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      geofenceRadiusMeters:
          (data['geofenceRadiusMeters'] as num?)?.toDouble() ?? 100.0,
    );
  }
}

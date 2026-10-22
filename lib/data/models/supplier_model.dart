class SupplierModel {
  const SupplierModel({
    required this.supplierId,
    required this.tenantId,
    required this.name,
    required this.status,
    this.contactPerson,
    this.mobile,
    this.whatsapp,
    this.email,
    this.gstin,
    this.pan,
    this.stateCode,
    this.supplierType,
    this.address,
  });

  final String supplierId, tenantId, name, status;
  final String? contactPerson, mobile, whatsapp, email, gstin, pan;
  final String? stateCode, supplierType, address;
  bool get isActive => status.toUpperCase() == 'ACTIVE' || status == 'active';

  factory SupplierModel.fromData(String id, Map<String, dynamic> data) =>
      SupplierModel(
        supplierId: data['supplierId'] as String? ?? id,
        tenantId:
            data['tenantId'] as String? ?? data['ownerUid'] as String? ?? '',
        name: data['name'] as String? ?? '',
        status: data['status'] as String? ?? 'ACTIVE',
        contactPerson:
            data['contactName'] as String? ?? data['contactPerson'] as String?,
        mobile: data['mobile'] as String?,
        whatsapp: data['whatsapp'] as String?,
        email: data['email'] as String?,
        gstin: data['gstin'] as String?,
        pan: data['pan'] as String?,
        stateCode: data['stateCode'] as String?,
        supplierType: data['supplierType'] as String?,
        address: data['address'] as String?,
      );
}

class SupplierBusinessModel {
  const SupplierBusinessModel({
    required this.supplierBusinessId,
    required this.tenantId,
    required this.supplierId,
    required this.businessId,
    required this.creditLimit,
    required this.paymentTerms,
    required this.openingBalance,
    required this.preferred,
    required this.status,
  });

  final String supplierBusinessId, tenantId, supplierId, businessId, status;
  final int creditLimit, paymentTerms, openingBalance;
  int get paymentTermsDays => paymentTerms;
  final bool preferred;
  bool get isActive => status.toUpperCase() == 'ACTIVE' || status == 'active';

  factory SupplierBusinessModel.fromData(
    String id,
    Map<String, dynamic> data,
  ) => SupplierBusinessModel(
    supplierBusinessId: data['supplierBusinessId'] as String? ?? id,
    tenantId: data['tenantId'] as String? ?? '',
    supplierId: data['supplierId'] as String? ?? '',
    businessId: data['businessId'] as String? ?? '',
    creditLimit: (data['creditLimit'] as num?)?.toInt() ?? 0,
    paymentTerms:
        (data['paymentTerms'] as num?)?.toInt() ??
        (data['paymentTermsDays'] as num?)?.toInt() ??
        0,
    openingBalance: (data['openingBalance'] as num?)?.toInt() ?? 0,
    preferred: data['preferred'] == true,
    status: data['status'] as String? ?? 'ACTIVE',
  );
}

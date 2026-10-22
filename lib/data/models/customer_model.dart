class CustomerModel {
  const CustomerModel({
    required this.customerId,
    required this.businessId,
    required this.name,
    required this.phone,
    required this.nameLower,
    this.stateCode,
    this.gstin,
    this.address,
    this.creditLimitPaise,
    this.duePaise = 0,
    this.advancePaise = 0,
    this.status = 'ACTIVE',
  });

  final String customerId;
  final String businessId;
  final String name;
  final String phone;
  final String nameLower;
  final String? stateCode;
  final String? gstin;
  final String? address;
  final int? creditLimitPaise;
  final int duePaise;
  final int advancePaise;
  final String status;

  factory CustomerModel.fromData(String id, Map<String, dynamic> data) =>
      CustomerModel(
        customerId: data['customerId'] as String? ?? id,
        businessId: data['businessId'] as String? ?? '',
        name: data['name'] as String? ?? '',
        phone: data['phone'] as String? ?? '',
        nameLower: data['nameLower'] as String? ?? '',
        stateCode: data['stateCode'] as String?,
        gstin: data['gstin'] as String?,
        address: data['address'] as String?,
        creditLimitPaise: (data['creditLimitPaise'] as num?)?.toInt(),
        duePaise: (data['duePaise'] as num?)?.toInt() ?? 0,
        advancePaise: (data['advancePaise'] as num?)?.toInt() ?? 0,
        status: data['status'] as String? ?? 'ACTIVE',
      );
}

import '../../domain/customers/customer_validators.dart';

class CustomerModel {
  const CustomerModel({
    required this.customerId,
    required this.businessId,
    this.tenantId,
    required this.name,
    required this.phone,
    required this.nameLower,
    this.customerType = typeIndividual,
    this.isGstRegistered = false,
    this.stateCode,
    this.gstin,
    this.address,
    this.creditLimitPaise,
    this.duePaise = 0,
    this.advancePaise = 0,
    this.status = 'ACTIVE',
    this.updatedAt,
    this.syncMutationId,
  });

  static const String typeIndividual = 'INDIVIDUAL';
  static const String typeBusiness = 'BUSINESS';
  static const String typeUnspecified = 'UNSPECIFIED';

  static const List<String> allowedCustomerTypes = [
    typeIndividual,
    typeBusiness,
    typeUnspecified,
  ];

  final String customerId;
  final String businessId;
  final String? tenantId;
  final String name;
  final String phone;
  final String nameLower;
  final String customerType;
  final bool isGstRegistered;
  final String? stateCode;
  final String? gstin;
  final String? address;
  final int? creditLimitPaise;
  final int duePaise;
  final int advancePaise;
  final String status;
  final String? updatedAt;
  final String? syncMutationId;

  bool get isBusiness => customerType == typeBusiness;
  bool get isIndividual => customerType == typeIndividual;
  bool get isUnspecified => customerType == typeUnspecified;

  factory CustomerModel.fromData(String id, Map<String, dynamic> data) {
    final rawCustomerType = data['customerType']?.toString();
    final rawIsGstRegistered = data['isGstRegistered'] as bool?;
    final rawGstin = data['gstin']?.toString();
    final normalizedGstin = rawGstin?.trim().isEmpty == true ? null : rawGstin?.trim().toUpperCase();

    // Backward compatibility:
    // Missing or invalid customerType defaults to UNSPECIFIED.
    // Never infer INDIVIDUAL or BUSINESS solely from GSTIN absence!
    final customerType = (rawCustomerType != null &&
            allowedCustomerTypes.contains(rawCustomerType))
        ? rawCustomerType
        : typeUnspecified;

    // Provisional registration status for legacy records:
    // If isGstRegistered is explicitly stored as boolean, honor it.
    // Otherwise, derive provisional registration status from existing GSTIN,
    // subject to format and checksum validation.
    final bool isGstRegistered;
    if (rawIsGstRegistered != null) {
      isGstRegistered = rawIsGstRegistered;
    } else {
      isGstRegistered = normalizedGstin != null &&
          CustomerValidators.isValidGstin(normalizedGstin);
    }

    final rawUpdatedAt = data['updatedAt'];
    final updatedAt = rawUpdatedAt is DateTime
        ? rawUpdatedAt.toIso8601String()
        : rawUpdatedAt?.toString();

    return CustomerModel(
      customerId: data['customerId']?.toString() ?? id,
      businessId: data['businessId']?.toString() ?? '',
      tenantId: data['tenantId']?.toString(),
      name: data['name']?.toString() ?? '',
      phone: data['phone']?.toString() ?? '',
      nameLower: data['nameLower']?.toString() ?? '',
      customerType: customerType,
      isGstRegistered: isGstRegistered,
      stateCode: data['stateCode']?.toString(),
      gstin: normalizedGstin,
      address: data['address']?.toString(),
      creditLimitPaise: (data['creditLimitPaise'] as num?)?.toInt(),
      duePaise: (data['duePaise'] as num?)?.toInt() ?? 0,
      advancePaise: (data['advancePaise'] as num?)?.toInt() ?? 0,
      status: data['status']?.toString() ?? 'ACTIVE',
      updatedAt: updatedAt,
      syncMutationId: data['_syncMutationId']?.toString() ?? data['syncMutationId']?.toString(),
    );
  }

  Map<String, dynamic> toData() => {
    'customerId': customerId,
    'businessId': businessId,
    if (tenantId != null) 'tenantId': tenantId,
    'name': name,
    'phone': phone,
    'nameLower': nameLower,
    'customerType': customerType,
    'isGstRegistered': isGstRegistered,
    if (stateCode != null) 'stateCode': stateCode,
    if (gstin != null) 'gstin': gstin,
    if (address != null) 'address': address,
    if (creditLimitPaise != null) 'creditLimitPaise': creditLimitPaise,
    'duePaise': duePaise,
    'advancePaise': advancePaise,
    'status': status,
    if (updatedAt != null) 'updatedAt': updatedAt,
    if (syncMutationId != null) '_syncMutationId': syncMutationId,
  };

  CustomerModel copyWith({
    String? customerId,
    String? businessId,
    String? tenantId,
    String? name,
    String? phone,
    String? nameLower,
    String? customerType,
    bool? isGstRegistered,
    String? stateCode,
    String? gstin,
    String? address,
    int? creditLimitPaise,
    int? duePaise,
    int? advancePaise,
    String? status,
    String? updatedAt,
    String? syncMutationId,
  }) =>
      CustomerModel(
        customerId: customerId ?? this.customerId,
        businessId: businessId ?? this.businessId,
        tenantId: tenantId ?? this.tenantId,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        nameLower: nameLower ?? this.nameLower,
        customerType: customerType ?? this.customerType,
        isGstRegistered: isGstRegistered ?? this.isGstRegistered,
        stateCode: stateCode ?? this.stateCode,
        gstin: gstin ?? this.gstin,
        address: address ?? this.address,
        creditLimitPaise: creditLimitPaise ?? this.creditLimitPaise,
        duePaise: duePaise ?? this.duePaise,
        advancePaise: advancePaise ?? this.advancePaise,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        syncMutationId: syncMutationId ?? this.syncMutationId,
      );
}

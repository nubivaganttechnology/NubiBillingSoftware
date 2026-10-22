enum StorageLocationType {
  godown('GODOWN'),
  rack('RACK'),
  shelf('SHELF');

  const StorageLocationType(this.value);
  final String value;

  static StorageLocationType? fromValue(String? value) {
    for (final type in values) {
      if (type.value == value?.toUpperCase()) return type;
    }
    return null;
  }

  String get label => switch (this) {
    godown => 'Godown',
    rack => 'Rack',
    shelf => 'Shelf',
  };
}

enum StorageLocationStatus {
  active('ACTIVE'),
  inactive('INACTIVE');

  const StorageLocationStatus(this.value);
  final String value;

  static StorageLocationStatus fromValue(String? value) =>
      value?.toUpperCase() == 'INACTIVE'
      ? StorageLocationStatus.inactive
      : StorageLocationStatus.active;
}

enum GodownScope {
  central('CENTRAL'),
  outlet('OUTLET');

  const GodownScope(this.value);
  final String value;

  static GodownScope? fromValue(String? value) =>
      switch (value?.toUpperCase()) {
        'CENTRAL' => GodownScope.central,
        'OUTLET' => GodownScope.outlet,
        _ => null,
      };
}

class StorageLocationModel {
  const StorageLocationModel({
    required this.storageLocationId,
    required this.tenantId,
    required this.businessId,
    required this.name,
    required this.code,
    required this.type,
    required this.status,
    required this.createdBy,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.parentLocationId,
    this.description,
    this.address,
    this.addressDetails,
    this.godownScope,
    this.outletId,
    this.capacity,
    this.contact,
    this.godownId,
    this.rackId,
    this.parentLocationType,
    this.parentLocationName,
    this.parentLocationCode,
    this.rackNumber,
  });

  final String storageLocationId;
  final String tenantId, businessId;
  final String name, code;
  final StorageLocationType type;
  final StorageLocationStatus status;
  final String createdBy, updatedBy;
  final DateTime? createdAt, updatedAt;
  final int version;
  final String? parentLocationId, description, address, godownId, rackId;
  final String? parentLocationType;
  final String? parentLocationName, parentLocationCode;
  final int? rackNumber;
  final Map<String, dynamic>? addressDetails, capacity, contact;
  final GodownScope? godownScope;
  final String? outletId;

  bool get isActive => status == StorageLocationStatus.active;
  String get godownCode => code;

  factory StorageLocationModel.fromData(
    String id,
    Map<String, dynamic> data, {
    required StorageLocationType type,
  }) {
    final addressValue = data['address'];
    final addressDetails = addressValue is Map
        ? Map<String, dynamic>.from(addressValue)
        : null;
    final addressText = addressValue is String
        ? addressValue
        : addressDetails == null
        ? null
        : [
                addressDetails['addressLine1'],
                addressDetails['addressLine2'],
                addressDetails['city'],
                addressDetails['state'],
                addressDetails['postalCode'],
              ]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .join(', ');
    final capacityValue = data['capacity'];
    final contactValue = data['contact'];
    final parentId = switch (type) {
      StorageLocationType.godown => null,
      StorageLocationType.rack =>
        data['parentLocationId'] as String? ?? data['godownId'] as String?,
      StorageLocationType.shelf => data['rackId'] as String?,
    };
    return StorageLocationModel(
      storageLocationId: switch (type) {
        StorageLocationType.godown => data['godownId'] as String? ?? id,
        StorageLocationType.rack => data['rackId'] as String? ?? id,
        StorageLocationType.shelf => data['shelfId'] as String? ?? id,
      },
      tenantId: data['tenantId'] as String? ?? '',
      businessId: data['businessId'] as String? ?? '',
      parentLocationId: parentId,
      name: type == StorageLocationType.godown
          ? data['godownName'] as String? ?? data['name'] as String? ?? ''
          : data['name'] as String? ?? '',
      code: type == StorageLocationType.godown
          ? data['godownCode'] as String? ?? data['code'] as String? ?? ''
          : data['code'] as String? ?? '',
      type: type,
      description: data['description'] as String?,
      address: addressText,
      addressDetails: addressDetails,
      godownScope: type == StorageLocationType.godown
          ? GodownScope.fromValue(data['godownScope'] as String?)
          : null,
      outletId: type == StorageLocationType.godown
          ? data['outletId'] as String?
          : type == StorageLocationType.rack &&
                (data['parentLocationType'] as String?)?.toUpperCase() ==
                    'OUTLET'
          ? data['outletId'] as String? ?? parentId
          : null,
      capacity: capacityValue is Map
          ? Map<String, dynamic>.from(capacityValue)
          : type == StorageLocationType.godown
          ? const {'enabled': false}
          : null,
      contact: contactValue is Map
          ? Map<String, dynamic>.from(contactValue)
          : null,
      godownId: data['godownId'] as String?,
      rackId: data['rackId'] as String?,
      parentLocationType: type == StorageLocationType.rack
          ? (data['parentLocationType'] as String? ?? 'GODOWN')
          : null,
      parentLocationName: data['parentLocationName'] as String?,
      parentLocationCode: data['parentLocationCode'] as String?,
      rackNumber: type == StorageLocationType.rack
          ? (data['rackNumber'] as num?)?.toInt()
          : null,
      status: StorageLocationStatus.fromValue(data['status'] as String?),
      createdBy: data['createdBy'] as String? ?? '',
      updatedBy: data['updatedBy'] as String? ?? '',
      createdAt: data['createdAt'] as DateTime?,
      updatedAt: data['updatedAt'] as DateTime?,
      version: (data['version'] as num?)?.toInt() ?? 1,
    );
  }
}

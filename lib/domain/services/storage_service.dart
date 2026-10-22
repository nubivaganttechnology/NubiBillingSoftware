import '../../core/errors/app_exception.dart';
import '../../core/utils/validators.dart';
import '../../data/models/storage_location_model.dart';
import '../../data/repositories/storage_repository.dart';

class StorageService {
  StorageService(this.repository);

  final StorageRepository repository;

  Future<List<StorageLocationModel>> getLocations({
    required String tenantId,
    required String businessId,
    required String token,
  }) => repository.getStorageLocations(
    tenantId: tenantId,
    businessId: businessId,
    token: token,
  );

  Future<List<StorageLocationModel>> createRacks({
    required String tenantId,
    required String businessId,
    required String parentLocationType,
    required String parentLocationId,
    required int count,
    required String actorUid,
    required String token,
  }) => repository.createRacks(
    tenantId: tenantId,
    businessId: businessId,
    parentLocationType: parentLocationType,
    parentLocationId: parentLocationId,
    count: count,
    actorUid: actorUid,
    token: token,
  );

  Future<StorageLocationModel> createLocation({
    required String tenantId,
    required String businessId,
    required StorageLocationType type,
    required String? parentLocationId,
    String parentLocationType = 'GODOWN',
    required String name,
    required String? code,
    required String? description,
    Map<String, dynamic>? addressDetails,
    Map<String, dynamic>? capacity,
    Map<String, dynamic>? contact,
    GodownScope? godownScope,
    String? outletId,
    required String actorUid,
    required String token,
  }) async {
    final cleanName = _validateName(name);
    final cleanCode =
        type == StorageLocationType.godown || type == StorageLocationType.rack
        ? null
        : _validateCode(code ?? '');
    final locations = type == StorageLocationType.godown
        ? <StorageLocationModel>[]
        : await repository.getStorageLocations(
            tenantId: tenantId,
            businessId: businessId,
            token: token,
          );
    if (type == StorageLocationType.shelf &&
        _codeExists(locations, type, parentLocationId, cleanCode!)) {
      throw const AppException(
        'A location with this code already exists at this level.',
      );
    }
    _validateParent(
      type: type,
      parentLocationId: parentLocationId,
      parentLocationType: parentLocationType,
      locations: locations,
    );
    return repository.createStorageLocation(
      tenantId: tenantId,
      businessId: businessId,
      parentLocationId: parentLocationId,
      name: cleanName,
      code: cleanCode,
      type: type,
      description: _optional(description),
      addressDetails: type == StorageLocationType.godown
          ? _validateAddress(addressDetails)
          : null,
      capacity: type == StorageLocationType.godown
          ? _validateCapacity(capacity)
          : type == StorageLocationType.rack
          ? _validateRackCapacity(capacity)
          : null,
      contact: type == StorageLocationType.godown
          ? _validateContact(contact)
          : null,
      godownScope: godownScope,
      outletId: outletId,
      actorUid: actorUid,
      token: token,
    );
  }

  Future<StorageLocationModel> updateLocation({
    required StorageLocationModel current,
    required String tenantId,
    required String businessId,
    required String name,
    required String? code,
    required String? description,
    Map<String, dynamic>? addressDetails,
    Map<String, dynamic>? capacity,
    Map<String, dynamic>? contact,
    GodownScope? godownScope,
    String? outletId,
    required String actorUid,
    required String token,
  }) async {
    _requireScope(current, tenantId, businessId);
    final cleanName = _validateName(name);
    final cleanCode =
        current.type == StorageLocationType.godown ||
            current.type == StorageLocationType.rack
        ? current.code
        : _validateCode(code ?? '');
    if (current.type == StorageLocationType.shelf) {
      final locations = await repository.getStorageLocations(
        tenantId: tenantId,
        businessId: businessId,
        token: token,
      );
      if (locations.any(
        (item) =>
            item.storageLocationId != current.storageLocationId &&
            item.type == current.type &&
            item.parentLocationId == current.parentLocationId &&
            item.code.toUpperCase() == cleanCode.toUpperCase(),
      )) {
        throw const AppException(
          'A location with this code already exists at this level.',
        );
      }
    }
    return repository.updateStorageLocation(
      storageLocationId: current.storageLocationId,
      tenantId: tenantId,
      businessId: businessId,
      type: current.type,
      name: cleanName,
      code: cleanCode,
      description: _optional(description),
      addressDetails: current.type == StorageLocationType.godown
          ? _validateAddress(addressDetails)
          : null,
      capacity: current.type == StorageLocationType.godown
          ? _validateCapacity(capacity)
          : current.type == StorageLocationType.rack
          ? _validateRackCapacity(capacity)
          : null,
      contact: current.type == StorageLocationType.godown
          ? _validateContact(contact)
          : null,
      godownScope: godownScope,
      outletId: outletId,
      actorUid: actorUid,
      token: token,
    );
  }

  Future<StorageLocationModel> setLocationActive({
    required StorageLocationModel location,
    required String tenantId,
    required String businessId,
    required bool isActive,
    required String actorUid,
    required String token,
  }) {
    _requireScope(location, tenantId, businessId);
    return repository.setStorageLocationStatus(
      storageLocationId: location.storageLocationId,
      type: location.type,
      tenantId: tenantId,
      businessId: businessId,
      isActive: isActive,
      actorUid: actorUid,
      token: token,
    );
  }

  void _validateParent({
    required StorageLocationType type,
    required String? parentLocationId,
    required String parentLocationType,
    required List<StorageLocationModel> locations,
  }) {
    if (type == StorageLocationType.godown) {
      if (parentLocationId != null) {
        throw const AppException('A Godown cannot have a parent location.');
      }
      return;
    }
    if (parentLocationId == null || parentLocationId.isEmpty) {
      throw AppException(
        '${type.label} must be assigned to its required parent.',
      );
    }
    if (type == StorageLocationType.rack &&
        parentLocationType.toUpperCase() == 'OUTLET') {
      return;
    }
    final parent = locations.where(
      (item) => item.storageLocationId == parentLocationId,
    );
    if (parent.isEmpty) {
      throw const AppException('Select a parent in this business.');
    }
    final value = parent.first;
    if (!value.isActive) {
      throw const AppException('The parent storage location must be active.');
    }
    final requiredParentType = type == StorageLocationType.rack
        ? StorageLocationType.godown
        : StorageLocationType.rack;
    if (value.type != requiredParentType) {
      throw AppException(
        '${type.label} must be inside a ${requiredParentType.label}.',
      );
    }

    final byId = {
      for (final location in locations) location.storageLocationId: location,
    };
    final visited = <String>{};
    var childType = requiredParentType;
    StorageLocationModel? cursor = value;
    while (cursor != null) {
      if (!visited.add(cursor.storageLocationId)) {
        throw const AppException(
          'The selected parent has a circular storage hierarchy.',
        );
      }
      final parentId = cursor.parentLocationId;
      final expectedAncestorType = childType == StorageLocationType.rack
          ? StorageLocationType.godown
          : childType == StorageLocationType.shelf
          ? StorageLocationType.rack
          : null;
      if (expectedAncestorType == null) {
        if (parentId != null) {
          throw const AppException('A Godown cannot have a parent location.');
        }
        cursor = null;
        continue;
      }
      if (parentId == null) {
        throw AppException(
          '${childType.label} must be assigned to its required parent.',
        );
      }
      final ancestor = byId[parentId];
      if (ancestor == null || ancestor.type != expectedAncestorType) {
        throw AppException(
          '${childType.label} must be inside a ${expectedAncestorType.label}.',
        );
      }
      if (!ancestor.isActive) {
        throw const AppException(
          'All parent storage locations must be active.',
        );
      }
      childType = expectedAncestorType;
      cursor = ancestor;
    }
  }

  String _validateName(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length < 2 || clean.length > 100) {
      throw const AppException(
        'Storage name must be between 2 and 100 characters.',
      );
    }
    return clean;
  }

  String _validateCode(String value) {
    final clean = value.trim().toUpperCase();
    if (clean.length < 2 || clean.length > 30) {
      throw const AppException(
        'Storage code must be between 2 and 30 characters.',
      );
    }
    return clean;
  }

  String? _optional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  Map<String, dynamic> _validateAddress(Map<String, dynamic>? value) {
    final address = value ?? const <String, dynamic>{};
    for (final key in [
      'addressLine1',
      'city',
      'state',
      'postalCode',
      'country',
    ]) {
      if ((address[key] as String? ?? '').trim().isEmpty) {
        throw AppException('Enter ${_addressLabel(key)}.');
      }
    }
    return {
      for (final entry in address.entries)
        entry.key: entry.value is String
            ? (entry.value as String).trim()
            : entry.value,
    };
  }

  String _addressLabel(String key) => switch (key) {
    'addressLine1' => 'Address Line 1',
    'postalCode' => 'PIN Code',
    _ => key[0].toUpperCase() + key.substring(1),
  };

  Map<String, dynamic> _validateCapacity(Map<String, dynamic>? value) {
    final capacity = value ?? const <String, dynamic>{'enabled': false};
    if (capacity['enabled'] != true) return const {'enabled': false};
    final type = capacity['capacityType'] as String?;
    final unit = capacity['capacityUnit'] as String?;
    final maximum = capacity['maximumCapacity'];
    final warning =
        (capacity['warningThresholdPercent'] as num?)?.toInt() ?? 80;
    final critical =
        (capacity['criticalThresholdPercent'] as num?)?.toInt() ?? 95;
    const units = {
      'VOLUME': {'CUBIC_METER', 'CUBIC_FEET'},
      'WEIGHT': {'KG', 'TON'},
      'UNITS': {'UNIT'},
    };
    if (type == null ||
        !units.containsKey(type) ||
        !units[type]!.contains(unit)) {
      throw const AppException(
        'Select a capacity unit that matches the capacity type.',
      );
    }
    if (maximum is! num || maximum <= 0) {
      throw const AppException('Maximum capacity must be greater than zero.');
    }
    if (warning < 1 || warning > 100 || critical <= warning || critical > 100) {
      throw const AppException(
        'Check the warning and critical capacity thresholds.',
      );
    }
    return {
      'enabled': true,
      'capacityType': type,
      'maximumCapacity': maximum,
      'capacityUnit': unit,
      'warningThresholdPercent': warning,
      'criticalThresholdPercent': critical,
    };
  }

  Map<String, dynamic> _validateRackCapacity(Map<String, dynamic>? value) {
    final capacity = value ?? const <String, dynamic>{'enabled': false};
    if (capacity['enabled'] != true)
      return const {
        'enabled': false,
        'capacityType': null,
        'maximumCapacity': null,
        'capacityUnit': null,
      };
    const units = {
      'VOLUME': {'CUBIC_METER', 'CUBIC_FEET'},
      'WEIGHT': {'KG', 'TON'},
      'UNITS': {'UNIT'},
    };
    final type = capacity['capacityType'] as String?;
    final unit = capacity['capacityUnit'] as String?;
    final maximum = capacity['maximumCapacity'];
    if (type == null ||
        !units.containsKey(type) ||
        !units[type]!.contains(unit))
      throw const AppException(
        'Select a Rack capacity unit that matches its type.',
      );
    if (maximum is! num || maximum <= 0)
      throw const AppException(
        'Rack maximum capacity must be greater than zero.',
      );
    return {
      'enabled': true,
      'capacityType': type,
      'maximumCapacity': maximum,
      'capacityUnit': unit,
    };
  }

  Map<String, dynamic> _validateContact(Map<String, dynamic>? value) {
    final contact = value ?? const <String, dynamic>{};
    final phone = (contact['phone'] as String? ?? '').trim();
    final email = (contact['email'] as String? ?? '').trim();
    if (phone.isNotEmpty && AppValidators.indianPhone(phone) != null) {
      throw const AppException('Enter a valid contact phone number.');
    }
    if (email.isNotEmpty && AppValidators.email(email) != null) {
      throw const AppException('Enter a valid contact email.');
    }
    return {
      'contactPerson': (contact['contactPerson'] as String? ?? '').trim(),
      'phone': phone.isEmpty ? '' : AppValidators.normalizeIndianPhone(phone),
      'email': email.toLowerCase(),
    };
  }

  bool _codeExists(
    List<StorageLocationModel> locations,
    StorageLocationType type,
    String? parentId,
    String code,
  ) => locations.any(
    (item) =>
        item.type == type &&
        item.parentLocationId == parentId &&
        item.code.toUpperCase() == code,
  );

  void _requireScope(
    StorageLocationModel location,
    String tenantId,
    String businessId,
  ) {
    if (location.tenantId != tenantId || location.businessId != businessId) {
      throw const AppException('Storage location is outside this business.');
    }
  }
}

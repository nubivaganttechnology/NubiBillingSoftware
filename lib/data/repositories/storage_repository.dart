import 'dart:convert';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/storage_location_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

class StorageRepository {
  StorageRepository(this.firestore, this.atomicWrites);

  final FirestoreDataService firestore;
  final FirestoreTransactionService atomicWrites;

  Future<List<StorageLocationModel>> getStorageLocations({
    required String tenantId,
    required String businessId,
    required String token,
  }) async {
    final documents = await Future.wait([
      _query(FirebaseConstants.godowns, tenantId, businessId, token),
      _query(FirebaseConstants.racks, tenantId, businessId, token),
      _query(FirebaseConstants.shelves, tenantId, businessId, token),
    ]);
    final locations = <StorageLocationModel>[
      for (final document in documents[0])
        _decode(document, StorageLocationType.godown),
      for (final document in documents[1])
        _decode(document, StorageLocationType.rack),
      for (final document in documents[2])
        _decode(document, StorageLocationType.shelf),
    ];
    return locations..sort((a, b) {
      final type = a.type.index.compareTo(b.type.index);
      return type == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : type;
    });
  }

  Future<List<Map<String, dynamic>>> getStockBuckets({
    required String tenantId,
    required String businessId,
    required String locationType,
    required String locationId,
    String? variantId,
    String? rackId,
    required String token,
  }) async {
    final filters = <FirestoreFilter>[
      FirestoreFilter('tenantId', 'EQUAL', tenantId),
      FirestoreFilter('businessId', 'EQUAL', businessId),
      FirestoreFilter('locationType', 'EQUAL', locationType.toUpperCase()),
      FirestoreFilter('locationId', 'EQUAL', locationId),
      if (variantId != null) FirestoreFilter('variantId', 'EQUAL', variantId),
      if (rackId != null) FirestoreFilter('rackId', 'EQUAL', rackId),
    ];
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.stockBalances,
      filters: filters,
      idToken: token,
    );
    final all = [...docs];
    if (locationType.toUpperCase() == 'OUTLET' && rackId == null) {
      final legacyFilters = <FirestoreFilter>[
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', locationId),
        if (variantId != null) FirestoreFilter('variantId', 'EQUAL', variantId),
      ];
      final legacy = await firestore.queryDocuments(
        collection: FirebaseConstants.stockBalances,
        filters: legacyFilters,
        idToken: token,
      );
      final seen = all.map((doc) => doc['name']).toSet();
      all.addAll(legacy.where((doc) => !seen.contains(doc['name'])));
    }
    return [
      for (final doc in all)
        {
          ...FirestoreRestService.decodeFields(doc['fields']),
          '_documentId': (doc['name'] as String? ?? '').split('/').last,
          'locationType':
              FirestoreRestService.decodeFields(
                doc['fields'],
              )['locationType'] ??
              locationType.toUpperCase(),
          'locationId':
              FirestoreRestService.decodeFields(doc['fields'])['locationId'] ??
              locationId,
        },
    ];
  }

  Future<List<Map<String, dynamic>>> _query(
    String collection,
    String tenantId,
    String businessId,
    String token,
  ) => firestore.queryDocuments(
    collection: collection,
    filters: [
      FirestoreFilter('tenantId', 'EQUAL', tenantId),
      FirestoreFilter('businessId', 'EQUAL', businessId),
    ],
    idToken: token,
  );

  Future<StorageLocationModel> createStorageLocation({
    required String tenantId,
    required String businessId,
    required String? parentLocationId,
    String parentLocationType = 'GODOWN',
    required String name,
    required String? code,
    required StorageLocationType type,
    required String? description,
    Map<String, dynamic>? addressDetails,
    Map<String, dynamic>? capacity,
    Map<String, dynamic>? contact,
    GodownScope? godownScope,
    String? outletId,
    required String actorUid,
    required String token,
  }) async {
    final id = IdGenerator.create(
      type == StorageLocationType.godown
          ? 'GDN'
          : type == StorageLocationType.rack
          ? 'RACK'
          : 'LOC',
    );
    final now = DateTime.now().toUtc();
    var cleanCode = code?.trim().toUpperCase();
    late Map<String, dynamic> fields;
    await atomicWrites.runAtomicOperation((transaction) async {
      if (type == StorageLocationType.godown) {
        if (godownScope == null) {
          throw const AppException('Select a Godown scope.');
        }
        if (godownScope == GodownScope.central && outletId != null) {
          throw const AppException(
            'A Central Godown cannot be assigned an Outlet.',
          );
        }
        if (godownScope == GodownScope.outlet) {
          final selectedOutletId = outletId;
          if (selectedOutletId == null || selectedOutletId.isEmpty) {
            throw const AppException('Select an Outlet for this Godown.');
          }
          final outlet = await transaction.get(
            FirebaseConstants.outlets,
            selectedOutletId,
          );
          final outletTenant =
              outlet.fields['tenantId'] as String? ??
              outlet.fields['ownerUid'] as String?;
          final outletActive = outlet.fields['isActive'] is bool
              ? outlet.fields['isActive'] == true
              : (outlet.fields['status'] as String?)?.toUpperCase() == 'ACTIVE';
          if (!outlet.exists ||
              outletTenant != tenantId ||
              outlet.fields['businessId'] != businessId ||
              !outletActive) {
            throw const AppException(
              'Select an active Outlet from this Business.',
            );
          }
        } else {
          outletId = null;
        }

        final sequenceId = _godownSequenceId(tenantId, businessId);
        final sequence = await transaction.get(
          FirebaseConstants.documentSequences,
          sequenceId,
        );
        var number = sequence.exists
            ? _readGodownNextNumber(sequence.fields)
            : await _highestExistingGodownSequence(
                    tenantId,
                    businessId,
                    token,
                  ) +
                  1;
        for (var attempt = 0; attempt < 100; attempt++) {
          cleanCode = _formatGodownCode(number);
          final reservationId = _godownCodeReservationId(
            tenantId,
            businessId,
            cleanCode!,
          );
          final oldReservationId = _legacyGodownCodeReservationId(
            businessId,
            cleanCode!,
          );
          final reservation = await transaction.get(
            FirebaseConstants.godownCodeReservations,
            reservationId,
          );
          final oldReservation = reservationId == oldReservationId
              ? reservation
              : await transaction.get(
                  FirebaseConstants.godownCodeReservations,
                  oldReservationId,
                );
          if (!reservation.exists && !oldReservation.exists) {
            transaction.create(
              FirebaseConstants.godownCodeReservations,
              reservationId,
              {
                'tenantId': tenantId,
                'businessId': businessId,
                'code': cleanCode,
                'godownId': id,
              },
            );
            break;
          }
          if (attempt == 99) {
            throw const AppException(
              'Unable to reserve a Godown code after 100 attempts. Refresh the sequence and retry.',
              code: 'reservation-limit',
            );
          }
          number++;
        }
        final sequenceFields = <String, dynamic>{
          'tenantId': tenantId,
          'businessId': businessId,
          'sequenceType': 'GODOWN',
          'prefix': 'GD',
          'nextNumber': number + 1,
          'padding': 4,
          'updatedAt': now,
          if (!sequence.exists) 'createdAt': now,
        };
        if (sequence.exists) {
          if (sequence.fields['tenantId'] != tenantId ||
              sequence.fields['businessId'] != businessId ||
              sequence.fields['sequenceType'] != 'GODOWN') {
            throw const AppException('Invalid Godown sequence document.');
          }
          transaction.update(
            FirebaseConstants.documentSequences,
            sequenceId,
            sequenceFields,
            updateTime: sequence.updateTime,
          );
        } else {
          transaction.create(
            FirebaseConstants.documentSequences,
            sequenceId,
            sequenceFields,
          );
        }
      }
      String? godownId;
      String? rackId;
      String? normalizedParentType;
      String? parentLocationName;
      String? parentLocationCode;
      int? rackNumber;
      if (type == StorageLocationType.rack) {
        normalizedParentType = parentLocationType.toUpperCase();
        if (!['GODOWN', 'OUTLET'].contains(normalizedParentType)) {
          throw const AppException('Rack parent must be a Godown or Outlet.');
        }
        final parentCollection = normalizedParentType == 'GODOWN'
            ? FirebaseConstants.godowns
            : FirebaseConstants.outlets;
        final parent = await transaction.get(
          parentCollection,
          parentLocationId!,
        );
        final parentTenantId =
            parent.fields['tenantId'] as String? ??
            parent.fields['ownerUid'] as String?;
        if (!parent.exists ||
            parent.fields['businessId'] != businessId ||
            parentTenantId != tenantId) {
          throw AppException(
            'Selected ${normalizedParentType == 'GODOWN' ? 'Godown' : 'Outlet'} is outside this business.',
          );
        }
        parentLocationName = normalizedParentType == 'GODOWN'
            ? parent.fields['godownName'] as String? ??
                  parent.fields['name'] as String? ??
                  ''
            : parent.fields['outletName'] as String? ??
                  parent.fields['name'] as String? ??
                  '';
        parentLocationCode = normalizedParentType == 'GODOWN'
            ? parent.fields['godownCode'] as String? ??
                  parent.fields['code'] as String? ??
                  ''
            : parent.fields['outletCode'] as String? ??
                  parent.fields['code'] as String? ??
                  '';
        final active = parent.fields['isActive'] is bool
            ? parent.fields['isActive'] == true
            : (parent.fields['status'] as String?)?.toUpperCase() != 'INACTIVE';
        if (!active) {
          throw const AppException('The parent location must be active.');
        }
        if (normalizedParentType == 'GODOWN') godownId = parentLocationId;
        final sequenceId = _rackSequenceId(
          tenantId,
          businessId,
          normalizedParentType,
          parentLocationId,
        );
        final sequence = await transaction.get(
          FirebaseConstants.documentSequences,
          sequenceId,
        );
        rackNumber = sequence.exists
            ? _readNextNumber(sequence.fields)
            : await _highestRackNumber(
                    tenantId,
                    businessId,
                    normalizedParentType,
                    parentLocationId,
                    token,
                  ) +
                  1;
        final sequenceFields = <String, dynamic>{
          'tenantId': tenantId,
          'businessId': businessId,
          'sequenceType': 'RACK',
          'parentLocationType': normalizedParentType,
          'parentLocationId': parentLocationId,
          'nextNumber': rackNumber + 1,
          'padding': 3,
          'prefix': 'RACK',
          'updatedAt': now,
          if (!sequence.exists) 'createdAt': now,
        };
        if (sequence.exists) {
          transaction.update(
            FirebaseConstants.documentSequences,
            sequenceId,
            sequenceFields,
            updateTime: sequence.updateTime,
          );
        } else {
          transaction.create(
            FirebaseConstants.documentSequences,
            sequenceId,
            sequenceFields,
          );
        }
        cleanCode = _formatRackCode(rackNumber);
      } else if (type == StorageLocationType.shelf) {
        final parent = await transaction.get(
          FirebaseConstants.racks,
          parentLocationId!,
        );
        if (!parent.exists ||
            parent.fields['businessId'] != businessId ||
            parent.fields['tenantId'] != tenantId) {
          throw const AppException('Selected Rack is outside this business.');
        }
        if (parent.fields['status'] != StorageLocationStatus.active.value) {
          throw const AppException('The parent Rack must be active.');
        }
        godownId = parent.fields['godownId'] as String?;
        rackId = parentLocationId;
      }
      fields = {
        switch (type) {
          StorageLocationType.godown => 'godownId',
          StorageLocationType.rack => 'rackId',
          StorageLocationType.shelf => 'shelfId',
        }: id,
        'tenantId': tenantId,
        'businessId': businessId,
        ...?(godownId == null ? null : {'godownId': godownId}),
        ...?(rackId == null ? null : {'rackId': rackId}),
        'name': type == StorageLocationType.rack
            ? (name.trim().isEmpty
                  ? 'Rack ${rackNumber!.toString().padLeft(2, '0')}'
                  : name.trim())
            : name,
        if (type == StorageLocationType.godown) 'godownName': name,
        'code': cleanCode,
        if (type == StorageLocationType.rack) ...{
          'rackCode': cleanCode,
          'rackNumber': rackNumber,
          'rackName': name.trim().isEmpty
              ? 'Rack ${rackNumber!.toString().padLeft(2, '0')}'
              : name.trim(),
          'parentLocationType': normalizedParentType,
          'parentLocationId': parentLocationId,
          'parentLocationName': parentLocationName,
          'parentLocationCode': parentLocationCode,
          if (normalizedParentType == 'GODOWN') ...{
            'godownName': parentLocationName,
            'godownCode': parentLocationCode,
          },
          if (normalizedParentType == 'OUTLET') ...{
            'outletId': parentLocationId,
            'outletName': parentLocationName,
            'outletCode': parentLocationCode,
          },
          'capacity':
              capacity ??
              const {
                'enabled': false,
                'capacityType': null,
                'maximumCapacity': null,
                'capacityUnit': null,
              },
        },
        if (type == StorageLocationType.godown) ...{
          'godownCode': cleanCode,
          'godownScope': godownScope!.value,
          'outletId': outletId,
          'address': addressDetails,
          'capacity': capacity ?? const {'enabled': false},
          'contact': contact ?? const <String, dynamic>{},
        },
        'description': description,
        'status': StorageLocationStatus.active.value,
        'createdBy': actorUid,
        'updatedBy': actorUid,
        'createdAt': now,
        'updatedAt': now,
        'version': 1,
      };
      transaction.create(_collection(type), id, fields);
    }, idToken: token);
    return StorageLocationModel.fromData(id, fields, type: type);
  }

  Future<List<StorageLocationModel>> createRacks({
    required String tenantId,
    required String businessId,
    required String parentLocationType,
    required String parentLocationId,
    required int count,
    required String actorUid,
    required String token,
  }) async {
    if (count < 1 || count > 100)
      throw const AppException('Create between 1 and 100 racks at a time.');
    final created = <StorageLocationModel>[];
    for (var i = 0; i < count; i++) {
      created.add(
        await createStorageLocation(
          tenantId: tenantId,
          businessId: businessId,
          parentLocationId: parentLocationId,
          parentLocationType: parentLocationType,
          name: '',
          code: null,
          type: StorageLocationType.rack,
          description: null,
          actorUid: actorUid,
          token: token,
        ),
      );
    }
    return created;
  }

  Future<StorageLocationModel> updateStorageLocation({
    required String storageLocationId,
    required StorageLocationType type,
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
    final now = DateTime.now().toUtc();
    late StorageLocationModel updated;
    final collection = _collection(type);
    await atomicWrites.runAtomicOperation((transaction) async {
      final document = await transaction.get(collection, storageLocationId);
      if (!document.exists) throw const AppException('Location was not found.');
      final current = StorageLocationModel.fromData(
        storageLocationId,
        document.fields,
        type: type,
      );
      _requireScope(current, tenantId, businessId);
      if (type == StorageLocationType.godown) {
        if (godownScope == null) {
          throw const AppException('Select a Godown scope.');
        }
        if (godownScope == GodownScope.central && outletId != null) {
          throw const AppException(
            'A Central Godown cannot be assigned an Outlet.',
          );
        }
        if (godownScope == GodownScope.outlet) {
          final selectedOutletId = outletId;
          if (selectedOutletId == null || selectedOutletId.isEmpty) {
            throw const AppException('Select an Outlet for this Godown.');
          }
          final outlet = await transaction.get(
            FirebaseConstants.outlets,
            selectedOutletId,
          );
          final outletTenant =
              outlet.fields['tenantId'] as String? ??
              outlet.fields['ownerUid'] as String?;
          final outletActive = outlet.fields['isActive'] is bool
              ? outlet.fields['isActive'] == true
              : (outlet.fields['status'] as String?)?.toUpperCase() == 'ACTIVE';
          if (!outlet.exists ||
              outletTenant != tenantId ||
              outlet.fields['businessId'] != businessId ||
              !outletActive) {
            throw const AppException(
              'Select an active Outlet from this Business.',
            );
          }
        } else {
          outletId = null;
        }
      }
      final values = <String, dynamic>{
        'name': name,
        if (type == StorageLocationType.godown) 'godownName': name,
        'description': description,
        if (type == StorageLocationType.godown) ...{
          'godownScope': godownScope!.value,
          'outletId': outletId,
          'address': addressDetails,
          'capacity': capacity ?? const {'enabled': false},
          'contact': contact ?? const <String, dynamic>{},
        } else if (type == StorageLocationType.shelf)
          'code': code,
        if (type == StorageLocationType.rack)
          'capacity':
              capacity ??
              const {
                'enabled': false,
                'capacityType': null,
                'maximumCapacity': null,
                'capacityUnit': null,
              },
        if (type == StorageLocationType.rack) ...{
          'rackName': name,
          'name': name,
        },
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': current.version + 1,
      };
      transaction.update(
        collection,
        storageLocationId,
        values,
        updateTime: document.updateTime,
      );
      updated = StorageLocationModel.fromData(storageLocationId, {
        ...document.fields,
        ...values,
      }, type: type);
    }, idToken: token);
    return updated;
  }

  Future<StorageLocationModel> setStorageLocationStatus({
    required String storageLocationId,
    required StorageLocationType type,
    required String tenantId,
    required String businessId,
    required bool isActive,
    required String actorUid,
    required String token,
  }) async {
    if (type == StorageLocationType.rack && !isActive) {
      final occupied = await firestore.queryDocuments(
        collection: FirebaseConstants.stockBalances,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('rackId', 'EQUAL', storageLocationId),
        ],
        idToken: token,
      );
      final hasStock = occupied.any((document) {
        final values = FirestoreRestService.decodeFields(document['fields']);
        return ((values['quantityOnHand'] as num?)?.toInt() ?? 0) > 0;
      });
      if (hasStock)
        throw const AppException(
          'Transfer the stock out of this Rack before deactivating it.',
        );
    }
    final now = DateTime.now().toUtc();
    late StorageLocationModel updated;
    final collection = _collection(type);
    await atomicWrites.runAtomicOperation((transaction) async {
      final document = await transaction.get(collection, storageLocationId);
      if (!document.exists) throw const AppException('Location was not found.');
      final current = StorageLocationModel.fromData(
        storageLocationId,
        document.fields,
        type: type,
      );
      _requireScope(current, tenantId, businessId);
      final values = <String, dynamic>{
        'status': isActive ? 'ACTIVE' : 'INACTIVE',
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': current.version + 1,
      };
      transaction.update(
        collection,
        storageLocationId,
        values,
        updateTime: document.updateTime,
      );
      updated = StorageLocationModel.fromData(storageLocationId, {
        ...document.fields,
        ...values,
      }, type: type);
    }, idToken: token);
    return updated;
  }

  StorageLocationModel _decode(
    Map<String, dynamic> document,
    StorageLocationType type,
  ) {
    final id = (document['name'] as String? ?? '').split('/').last;
    return StorageLocationModel.fromData(
      id,
      FirestoreRestService.decodeFields(document['fields']),
      type: type,
    );
  }

  String _collection(StorageLocationType type) => switch (type) {
    StorageLocationType.godown => FirebaseConstants.godowns,
    StorageLocationType.rack => FirebaseConstants.racks,
    StorageLocationType.shelf => FirebaseConstants.shelves,
  };

  String _godownCodeReservationId(
    String tenantId,
    String businessId,
    String code,
  ) => base64Url
      .encode(utf8.encode('$tenantId|$businessId|${code.toUpperCase()}'))
      .replaceAll('=', '');

  String _legacyGodownCodeReservationId(String businessId, String code) =>
      base64Url
          .encode(utf8.encode('$businessId|${code.toUpperCase()}'))
          .replaceAll('=', '');

  String _godownSequenceId(String tenantId, String businessId) =>
      '${tenantId}_${businessId}_GODOWN';

  int _readGodownNextNumber(Map<String, dynamic> fields) {
    final value = fields['nextNumber'];
    if (value is int && value > 0) return value;
    throw const AppException('Invalid Godown sequence number.');
  }

  String _formatGodownCode(int value) =>
      'GD-${value.toString().padLeft(4, '0')}';

  String _rackSequenceId(
    String tenantId,
    String businessId,
    String parentType,
    String parentId,
  ) => '${tenantId}_${businessId}_${parentType}_${parentId}_RACK';
  String _formatRackCode(int value) =>
      'RACK-${value.toString().padLeft(3, '0')}';
  int _readNextNumber(Map<String, dynamic> fields) {
    final value = fields['nextNumber'];
    if (value is int && value > 0) return value;
    throw const AppException('Invalid Rack sequence number.');
  }

  Future<int> _highestRackNumber(
    String tenantId,
    String businessId,
    String parentType,
    String parentId,
    String token,
  ) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.racks,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    var highest = 0;
    for (final doc in docs) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      final actualType = (data['parentLocationType'] as String? ?? 'GODOWN')
          .toUpperCase();
      final actualParent =
          data['parentLocationId'] as String? ?? data['godownId'] as String?;
      if (actualType != parentType || actualParent != parentId) continue;
      final number =
          (data['rackNumber'] as num?)?.toInt() ??
          int.tryParse(
            RegExp(
                  r'RACK-(\d+)',
                  caseSensitive: false,
                ).firstMatch('${data['rackCode'] ?? data['code']}')?.group(1) ??
                '',
          ) ??
          0;
      if (number > highest) highest = number;
    }
    return highest;
  }

  Future<int> _highestExistingGodownSequence(
    String tenantId,
    String businessId,
    String token,
  ) async {
    var highest = 0;
    for (final field in ['godownCode', 'code']) {
      final scoped = await firestore.queryDocuments(
        collection: FirebaseConstants.godowns,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
        ],
        orderBy: field,
        descending: true,
        limit: 1,
        idToken: token,
      );
      final legacy = await firestore.queryDocuments(
        collection: FirebaseConstants.godowns,
        filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
        orderBy: field,
        descending: true,
        limit: 1,
        idToken: token,
      );
      for (final document in [...scoped, ...legacy]) {
        final values = FirestoreRestService.decodeFields(document['fields']);
        final documentTenant =
            values['tenantId'] as String? ?? values['ownerUid'] as String?;
        if (values['businessId'] != businessId || documentTenant != tenantId) {
          continue;
        }
        final storedCode =
            values['godownCode'] as String? ?? values['code'] as String?;
        final match = RegExp(
          r'^GD-(\d+)$',
          caseSensitive: false,
        ).firstMatch(storedCode?.trim() ?? '');
        final number = int.tryParse(match?.group(1) ?? '');
        if (number != null && number > highest) highest = number;
      }
    }
    return highest;
  }

  void _requireScope(
    StorageLocationModel location,
    String tenantId,
    String businessId,
  ) {
    if (location.tenantId != tenantId || location.businessId != businessId) {
      throw const AppException('Location is outside this business.');
    }
  }
}

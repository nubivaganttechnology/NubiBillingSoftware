import 'dart:convert';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/business_model.dart';
import '../models/business_type_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_transaction_service.dart';
import '../services/firestore_rest_service.dart';

class BusinessRepository {
  BusinessRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<BusinessModel>> getBusinessesByOwnerUid(
    String ownerUid,
    String token,
  ) async {
    final docs = await firestore.queryEqual(
      FirebaseConstants.businesses,
      'ownerUid',
      ownerUid,
      idToken: token,
    );
    return docs.map(_model).where((business) => business.isActive).toList();
  }

  Future<BusinessModel?> getBusinessByIdOrNull(String id, String token) async {
    try {
      final doc = await firestore.getDocument(
        FirebaseConstants.businesses,
        id,
        idToken: token,
      );
      return _model(doc);
    } on AppException catch (error) {
      if (error.code == 'not-found') return null;
      rethrow;
    }
  }

  Future<BusinessModel> getBusinessById(String id, String token) async =>
      _model(
        await firestore.getDocument(
          FirebaseConstants.businesses,
          id,
          idToken: token,
        ),
      );

  Future<bool> businessNameExists(
    String ownerUid,
    String normalizedBusinessName,
    String token,
  ) async {
    final docs = await firestore.queryEqual(
      FirebaseConstants.businesses,
      'ownerUid',
      ownerUid,
      idToken: token,
    );
    return docs.any((doc) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final name =
          fields['normalizedBusinessName'] as String? ??
          (fields['businessName'] as String? ?? '')
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' ');
      final active = fields['isActive'] is bool
          ? fields['isActive'] as bool
          : (fields['status'] as String?)?.toLowerCase() == 'active';
      return active && name == normalizedBusinessName;
    });
  }

  Future<BusinessModel> createBusiness({
    required String ownerUid,
    required String businessName,
    required String normalizedBusinessName,
    required BusinessTypeModel businessType,
    required String email,
    required String phone,
    required String address,
    String? gstin,
    bool gstinVerified = false,
    DateTime? gstinVerifiedAt,
    String? gstLegalName,
    String? gstTradeName,
    String? gstStatus,
    String? gstState,
    required String token,
  }) async {
    final typeDoc = await firestore.getDocument(
      FirebaseConstants.businessTypes,
      businessType.id,
      idToken: token,
    );
    final verifiedType = BusinessTypeModel.fromData(
      businessType.id,
      FirestoreRestService.decodeFields(typeDoc['fields']),
    );
    if (!verifiedType.isActive) {
      throw const AppException('Select an active business type.');
    }
    if (await businessNameExists(ownerUid, normalizedBusinessName, token)) {
      throw const AppException('A business with this name already exists.');
    }

    // A deterministic create-only reservation makes concurrent requests for the
    // same owner/name contend on one Firestore document. Security rules should
    // restrict this collection to authenticated owner creation.
    final reservationId = base64Url
        .encode(utf8.encode('$ownerUid|$normalizedBusinessName'))
        .replaceAll('=', '');
    final id = IdGenerator.create('BUS');
    final now = DateTime.now().toUtc();
    final fields = <String, dynamic>{
      'businessId': id,
      'ownerUid': ownerUid,
      'businessName': businessName.trim().replaceAll(RegExp(r'\s+'), ' '),
      'normalizedBusinessName': normalizedBusinessName,
      'businessTypeId': businessType.id,
      'businessTypeName': verifiedType.name,
      'email': email.trim().toLowerCase(),
      'phone': phone,
      'gstin': gstin,
      'gstinVerified': gstinVerified,
      'gstinVerifiedAt': gstinVerifiedAt,
      'gstLegalName': gstLegalName,
      'gstTradeName': gstTradeName,
      'gstStatus': gstStatus,
      'gstState': gstState,
      'address': address.trim(),
      'isActive': true,
      'status': 'active',
      'createdAt': now,
      'updatedAt': now,
    };
    final atomic = firestore;
    if (atomic is FirestoreTransactionService) {
      await (atomic as FirestoreTransactionService).runAtomicOperation((
        transaction,
      ) async {
        final reservation = await transaction.get(
          FirebaseConstants.businessNameReservations,
          reservationId,
        );
        if (reservation.exists) {
          throw const AppException('A business with this name already exists.');
        }
        transaction.create(
          FirebaseConstants.businessNameReservations,
          reservationId,
          {
            'ownerUid': ownerUid,
            'normalizedBusinessName': normalizedBusinessName,
            'createdAt': now,
          },
        );
        transaction.create(FirebaseConstants.businesses, id, fields);
      }, idToken: token);
    } else {
      // Compatibility for read/write-only external implementations.
      await firestore.createDocument(
        FirebaseConstants.businessNameReservations,
        reservationId,
        {
          'ownerUid': ownerUid,
          'normalizedBusinessName': normalizedBusinessName,
          'createdAt': now,
        },
        idToken: token,
      );
      await firestore.createDocument(
        FirebaseConstants.businesses,
        id,
        fields,
        idToken: token,
      );
    }
    return BusinessModel.fromData(id, fields);
  }

  BusinessModel _model(Map<String, dynamic> doc) => BusinessModel.fromData(
    (doc['name'] as String? ?? '').split('/').last,
    FirestoreRestService.decodeFields(doc['fields']),
  );
}

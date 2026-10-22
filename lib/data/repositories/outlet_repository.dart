import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/business_sub_type_model.dart';
import '../models/outlet_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

class OutletRepository {
  OutletRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<OutletModel>> getOutletsByBusinessId(
    String businessId,
    String token, {
    required String tenantId,
  }) async {
    // Query the canonical tenant/business scope first. Merge the legacy
    // business-only query so existing Outlet records without tenantId remain
    // visible; the model's ownerUid fallback is still checked below.
    final scopedDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.outlets,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    final legacyDocs = await firestore.queryEqual(
      FirebaseConstants.outlets,
      'businessId',
      businessId,
      idToken: token,
    );
    final docsByName = <String, Map<String, dynamic>>{
      for (final doc in legacyDocs) (doc['name'] as String? ?? ''): doc,
      for (final doc in scopedDocs) (doc['name'] as String? ?? ''): doc,
    };
    final docs = docsByName.values;
    return docs
        .map(_model)
        .where(
          (outlet) =>
              outlet.businessId == businessId &&
              outlet.isActive &&
              outlet.tenantId == tenantId,
        )
        .toList();
  }

  Future<List<OutletModel>> getOutletsByBusinessIds(
    List<String> businessIds,
    String token, {
    required String tenantId,
  }) async {
    final results = await Future.wait(
      businessIds.map(
        (id) => getOutletsByBusinessId(id, token, tenantId: tenantId),
      ),
    );
    final outletsById = <String, OutletModel>{};
    for (final outlet in results.expand((items) => items)) {
      outletsById[outlet.outletId] = outlet;
    }
    return outletsById.values.toList();
  }

  Future<OutletModel> getOutletById(String id, String token) async => _model(
    await firestore.getDocument(FirebaseConstants.outlets, id, idToken: token),
  );

  Future<OutletModel> createOutlet({
    required String businessId,
    required String ownerUid,
    required String createdBy,
    required String businessTypeId,
    required String outletName,
    required BusinessSubTypeModel outletType,
    required String address,
    required String contactNumber,
    String? gstin,
    bool gstinVerified = false,
    DateTime? gstinVerifiedAt,
    String? gstLegalName,
    String? gstTradeName,
    String? gstStatus,
    String? gstState,
    required String token,
  }) async {
    final businessDoc = await firestore.getDocument(
      FirebaseConstants.businesses,
      businessId,
      idToken: token,
    );
    final businessFields = FirestoreRestService.decodeFields(
      businessDoc['fields'],
    );
    final storedOwner = businessFields['ownerUid'];
    final storedTypeId =
        businessFields['businessTypeId'] ?? businessFields['businessType'];
    final activeBusiness = businessFields['isActive'] is bool
        ? businessFields['isActive'] == true
        : (businessFields['status'] as String?)?.toLowerCase() == 'active';
    final subTypeDoc = await firestore.getDocument(
      FirebaseConstants.businessSubTypes,
      outletType.id,
      idToken: token,
    );
    final verifiedType = BusinessSubTypeModel.fromData(
      outletType.id,
      FirestoreRestService.decodeFields(subTypeDoc['fields']),
    );
    if (storedOwner != ownerUid ||
        storedTypeId != businessTypeId ||
        !activeBusiness ||
        !verifiedType.isActive ||
        verifiedType.businessTypeId != businessTypeId) {
      throw const AppException('Select a valid outlet type for this business.');
    }
    final id = IdGenerator.create('OUT');
    final now = DateTime.now().toUtc();
    final transactionService = _transactions;
    late Map<String, dynamic> fields;
    await transactionService.runAtomicOperation<void>((transaction) async {
      final sequence = await transaction.get(
        FirebaseConstants.documentSequences,
        _sequenceId(ownerUid, businessId),
      );
      final nextNumber = sequence.exists
          ? _readNextNumber(sequence.fields)
          : await _highestExistingOutletSequence(ownerUid, businessId, token) +
                1;
      final sequenceFields = <String, dynamic>{
        'tenantId': ownerUid,
        'businessId': businessId,
        'sequenceType': 'OUTLET',
        'prefix': 'OUT',
        'nextNumber': nextNumber + 1,
        'padding': 4,
        'updatedAt': now,
        if (!sequence.exists) 'createdAt': now,
      };
      if (sequence.exists) {
        if (sequence.fields['tenantId'] != ownerUid ||
            sequence.fields['businessId'] != businessId ||
            sequence.fields['sequenceType'] != 'OUTLET') {
          throw const AppException('Invalid Outlet sequence document.');
        }
        transaction.update(
          FirebaseConstants.documentSequences,
          _sequenceId(ownerUid, businessId),
          sequenceFields,
          updateTime: sequence.updateTime,
        );
      } else {
        transaction.create(
          FirebaseConstants.documentSequences,
          _sequenceId(ownerUid, businessId),
          sequenceFields,
        );
      }
      final outletCode = _formatOutletCode(nextNumber);
      fields = <String, dynamic>{
        'outletId': id,
        'outletCode': outletCode,
        'tenantId': ownerUid,
        'businessId': businessId,
        'ownerUid': ownerUid,
        'outletName': outletName.trim(),
        'name': outletName.trim(),
        'outletTypeId': outletType.id,
        'businessSubTypeId': outletType.id,
        'outletTypeName': verifiedType.name,
        'contactNumber': contactNumber,
        'gstin': gstin,
        'gstinVerified': gstinVerified,
        'gstinVerifiedAt': gstinVerifiedAt,
        'gstLegalName': gstLegalName,
        'gstTradeName': gstTradeName,
        'gstStatus': gstStatus,
        'gstState': gstState,
        'address': address.trim(),
        'isActive': true,
        'status': 'ACTIVE',
        'createdAt': now,
        'updatedAt': now,
        'createdBy': createdBy,
        'updatedBy': createdBy,
        'version': 1,
      };
      transaction.create(FirebaseConstants.outlets, id, fields);
    }, idToken: token);
    return OutletModel.fromData(id, fields);
  }

  FirestoreTransactionService get _transactions {
    final service = firestore;
    if (service is FirestoreTransactionService) {
      return service as FirestoreTransactionService;
    }
    throw const AppException(
      'Atomic Outlet code generation is unavailable for this data service.',
    );
  }

  String _sequenceId(String tenantId, String businessId) =>
      '${tenantId}_${businessId}_OUTLET';

  int _readNextNumber(Map<String, dynamic> fields) {
    final value = fields['nextNumber'];
    if (value is int && value > 0) return value;
    throw const AppException('Invalid Outlet sequence number.');
  }

  String _formatOutletCode(int value) =>
      'OUT-${value.toString().padLeft(4, '0')}';

  Future<int> _highestExistingOutletSequence(
    String tenantId,
    String businessId,
    String token,
  ) async {
    var highest = 0;
    // Avoid an orderBy on outletCode/code here. Those legacy fields are not
    // consistently populated, and ordering with the business filter requires
    // composite indexes that may not yet be deployed. A single equality query
    // uses Firestore's automatic field index; scope each result to the tenant
    // before considering its sequence.
    final candidates = await firestore.queryEqual(
      FirebaseConstants.outlets,
      'businessId',
      businessId,
      idToken: token,
    );
    for (final document in candidates) {
      final values = FirestoreRestService.decodeFields(document['fields']);
      final documentTenant =
          values['tenantId'] as String? ?? values['ownerUid'] as String?;
      if (documentTenant != tenantId) continue;

      final code = values['outletCode'] as String? ?? values['code'] as String?;
      final match = RegExp(
        r'^OUT-(\d+)$',
        caseSensitive: false,
      ).firstMatch(code?.trim() ?? '');
      final number = int.tryParse(match?.group(1) ?? '');
      if (number != null && number > highest) highest = number;
    }
    return highest;
  }

  OutletModel _model(Map<String, dynamic> doc) => OutletModel.fromData(
    (doc['name'] as String? ?? '').split('/').last,
    FirestoreRestService.decodeFields(doc['fields']),
  );
}

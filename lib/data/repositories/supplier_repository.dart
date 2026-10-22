import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/supplier_model.dart';
import '../models/supplier_refund_model.dart';
import '../models/financial_transaction_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

class SupplierRepository {
  SupplierRepository(this.firestore, this.transactions);
  final FirestoreDataService firestore;
  final FirestoreTransactionService transactions;

  Future<Map<String, dynamic>> getSupplierFinancialSnapshot({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String supplierBusinessId,
    required String token,
  }) async {
    final balanceDoc = await firestore.getDocument(
      FirebaseConstants.supplierBalances,
      supplierBusinessId,
      idToken: token,
    );
    final balance = FirestoreRestService.decodeFields(balanceDoc['fields']);
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.supplierRefunds,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    final refunds =
        docs
            .map(
              (doc) => SupplierRefundModel.fromData(
                (doc['name'] as String? ?? '').split('/').last,
                FirestoreRestService.decodeFields(doc['fields']),
              ),
            )
            .where((refund) => refund.supplierBusinessId == supplierBusinessId)
            .toList()
          ..sort((a, b) => b.refundDate.compareTo(a.refundDate));
    return {
      'unallocatedAdvance':
          (balance['unallocatedAdvance'] as num?)?.toInt() ?? 0,
      'refunds': refunds,
    };
  }

  Future<SupplierRefundModel> recordSupplierRefund({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String supplierId,
    required String supplierBusinessId,
    required int amount,
    required DateTime refundDate,
    required String paymentMode,
    required String referenceNo,
    required String reason,
    required String notes,
    required String createdByUid,
    required String requestId,
    required String token,
  }) async {
    if (amount <= 0 ||
        reason.trim().isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(requestId.trim())) {
      throw const AppException(
        'Enter a refund amount, reason, and request identifier.',
      );
    }
    if (!{
      'CASH',
      'UPI',
      'BANK_TRANSFER',
      'CHEQUE',
      'CARD',
    }.contains(paymentMode)) {
      throw const AppException('Select a valid refund payment mode.');
    }

    final refundId = 'SREF-${requestId.trim()}';
    final financialTransactionId = 'FIN-$refundId';
    final ledgerEntryId = 'SUPPLIER_REFUND_$refundId';
    late SupplierRefundModel result;
    await transactions.runAtomicOperation((tx) async {
      final existing = await tx.get(
        FirebaseConstants.supplierRefunds,
        refundId,
      );
      if (existing.exists) {
        if (existing.fields['requestId'] != requestId.trim() ||
            existing.fields['supplierBusinessId'] != supplierBusinessId ||
            (existing.fields['amount'] as num?)?.toInt() != amount ||
            existing.fields['paymentMode'] != paymentMode ||
            existing.fields['reason'] != reason.trim() ||
            existing.fields['referenceNo'] !=
                (referenceNo.trim().isEmpty ? null : referenceNo.trim()) ||
            existing.fields['notes'] !=
                (notes.trim().isEmpty ? null : notes.trim()) ||
            existing.fields['refundDate'] != refundDate.toUtc()) {
          throw const AppException(
            'This refund request identifier was already used for different details.',
          );
        }
        result = SupplierRefundModel.fromData(refundId, existing.fields);
        return;
      }

      final relation = await tx.get(
        FirebaseConstants.supplierBusinesses,
        supplierBusinessId,
      );
      if (!relation.exists ||
          relation.fields['tenantId'] != tenantId ||
          relation.fields['businessId'] != businessId ||
          relation.fields['supplierId'] != supplierId ||
          relation.fields['status'] != 'ACTIVE') {
        throw const AppException(
          'This supplier is not active for the current business.',
        );
      }
      final balance = await tx.get(
        FirebaseConstants.supplierBalances,
        supplierBusinessId,
      );
      if (!balance.exists ||
          balance.fields['tenantId'] != tenantId ||
          balance.fields['businessId'] != businessId ||
          balance.fields['supplierBusinessId'] != supplierBusinessId) {
        throw const AppException('Supplier advance is unavailable.');
      }
      final advance =
          (balance.fields['unallocatedAdvance'] as num?)?.toInt() ?? 0;
      if (amount > advance) {
        throw const AppException(
          'Refund amount cannot exceed the available supplier advance.',
        );
      }

      final now = DateTime.now().toUtc();
      final refund = SupplierRefundModel(
        refundId: refundId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        supplierBusinessId: supplierBusinessId,
        amount: amount,
        refundDate: refundDate,
        paymentMode: paymentMode,
        referenceNo: referenceNo.trim().isEmpty ? null : referenceNo.trim(),
        reason: reason.trim(),
        notes: notes.trim().isEmpty ? null : notes.trim(),
        status: 'POSTED',
        financialTransactionId: financialTransactionId,
        createdByUid: createdByUid,
        createdAt: now,
        requestId: requestId.trim(),
      );
      final financial = FinancialTransactionModel(
        transactionId: financialTransactionId,
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        direction: 'IN',
        transactionType: 'SUPPLIER_REFUND',
        partyType: 'SUPPLIER',
        partyId: supplierId,
        amount: amount,
        paymentMode: paymentMode,
        referenceType: 'SUPPLIER_REFUND',
        referenceId: refundId,
        transactionDate: refundDate,
        referenceNo: referenceNo.trim().isEmpty ? null : referenceNo.trim(),
        notes: notes.trim().isEmpty ? null : notes.trim(),
        createdByUid: createdByUid,
        createdAt: now,
        status: 'POSTED',
      );
      tx.create(FirebaseConstants.supplierRefunds, refundId, refund.toData());
      tx.create(
        FirebaseConstants.financialTransactions,
        financialTransactionId,
        financial.toData(),
      );
      tx.update(FirebaseConstants.supplierBalances, supplierBusinessId, {
        'unallocatedAdvance': advance - amount,
        'lastLedgerEntryId': ledgerEntryId,
        'updatedAt': now,
      }, updateTime: balance.updateTime);
      // This event is an audit/trace record, not a second payable posting.
      // The advance bucket is reduced directly; nonzero ledger sides could
      // incorrectly recreate or reduce the supplier payable balance.
      tx.create(FirebaseConstants.supplierLedgerEntries, ledgerEntryId, {
        'ledgerEntryId': ledgerEntryId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'supplierId': supplierId,
        'supplierBusinessId': supplierBusinessId,
        'entryType': 'SUPPLIER_REFUND',
        'referenceType': 'SUPPLIER_REFUND',
        'referenceId': refundId,
        'refundId': refundId,
        'financialTransactionId': financialTransactionId,
        'amount': amount,
        'debit': 0,
        'credit': 0,
        'paymentMode': paymentMode,
        'referenceNo': referenceNo.trim().isEmpty ? null : referenceNo.trim(),
        'reason': reason.trim(),
        'isReversal': false,
        'reversalOfId': null,
        'transactionDate': refundDate.toUtc(),
        'createdBy': createdByUid,
        'createdAt': now,
      });
      result = refund;
    }, idToken: token);
    return result;
  }

  Future<List<SupplierModel>> getForBusiness(
    String tenantId,
    String businessId,
    String token, {
    bool includeInactive = false,
  }) async {
    final relations = await firestore.queryDocuments(
      collection: FirebaseConstants.supplierBusinesses,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    final activeRelations = relations
        .map(_relation)
        .where(
          (relation) =>
              relation.tenantId == tenantId &&
              relation.businessId == businessId &&
              relation.isActive,
        )
        .toList();
    final values = await Future.wait(
      activeRelations.map((relation) async {
        final document = await firestore.getDocument(
          FirebaseConstants.suppliers,
          relation.supplierId,
          idToken: token,
        );
        final supplier = _supplier(document);
        return (includeInactive || supplier.isActive) &&
                supplier.tenantId == tenantId
            ? supplier
            : null;
      }),
    );
    return values.whereType<SupplierModel>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<List<SupplierModel>> getTenantSuppliers(
    String tenantId,
    String token,
  ) async {
    final documents = await firestore.queryEqual(
      FirebaseConstants.suppliers,
      'tenantId',
      tenantId,
      idToken: token,
    );
    return documents
        .map(_supplier)
        .where((supplier) => supplier.tenantId == tenantId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<SupplierBusinessModel> getSupplierBusiness(
    String tenantId,
    String businessId,
    String supplierId,
    String token,
  ) async {
    final id = relationId(supplierId, businessId);
    final document = await firestore.getDocument(
      FirebaseConstants.supplierBusinesses,
      id,
      idToken: token,
    );
    final relation = _relation(document);
    if (relation.tenantId != tenantId ||
        relation.businessId != businessId ||
        relation.supplierId != supplierId ||
        !relation.isActive) {
      throw const AppException(
        'This supplier is not available for this business.',
      );
    }
    return relation;
  }

  Future<void> updateSupplier({
    required String tenantId,
    required String businessId,
    required String supplierId,
    required String name,
    required String mobile,
    required String contactPerson,
    required String email,
    required String whatsapp,
    required String gstin,
    required String pan,
    required String stateCode,
    required String supplierType,
    required String address,
    required int creditLimit,
    required int paymentTermsDays,
    required bool preferred,
    required String updatedBy,
    required String token,
  }) async {
    if (tenantId.isEmpty ||
        businessId.isEmpty ||
        supplierId.isEmpty ||
        name.trim().length < 2 ||
        creditLimit < 0 ||
        paymentTermsDays < 0) {
      throw const AppException('Check the supplier details and try again.');
    }

    final existing = await getTenantSuppliers(tenantId, token);
    final normalizedName = _clean(name).toLowerCase();
    final normalizedMobile = _digits(mobile);
    final normalizedGstin = gstin.trim().toUpperCase();
    final normalizedEmail = email.trim().toLowerCase();
    for (final other in existing.where(
      (item) => item.supplierId != supplierId,
    )) {
      if (_clean(other.name).toLowerCase() == normalizedName) {
        throw const AppException('A supplier with this name already exists.');
      }
      if (normalizedMobile.isNotEmpty &&
          _digits(other.mobile ?? '') == normalizedMobile) {
        throw const AppException(
          'This contact number is already used by another supplier.',
        );
      }
      if (normalizedGstin.isNotEmpty &&
          other.gstin?.toUpperCase() == normalizedGstin) {
        throw const AppException('A supplier with this GSTIN already exists.');
      }
      if (normalizedEmail.isNotEmpty &&
          other.email?.toLowerCase() == normalizedEmail) {
        throw const AppException('A supplier with this email already exists.');
      }
    }

    final now = DateTime.now().toUtc();
    final supplierFields = <String, dynamic>{
      'name': _clean(name),
      'contactName': _optional(contactPerson),
      'mobile': _optional(mobile),
      'whatsapp': _optional(whatsapp),
      'email': _optional(normalizedEmail),
      'gstin': _optional(normalizedGstin),
      'pan': _optional(pan.trim().toUpperCase()),
      'stateCode': _optional(stateCode.trim()),
      'supplierType': _optional(supplierType.trim()),
      'address': _optional(address.trim()),
      'updatedAt': now,
      'updatedBy': updatedBy,
    };
    final relationshipId = relationId(supplierId, businessId);
    final relationFields = <String, dynamic>{
      'creditLimit': creditLimit,
      'paymentTerms': paymentTermsDays,
      'preferred': preferred,
      'updatedAt': now,
      'updatedBy': updatedBy,
    };

    await transactions.runAtomicOperation((transaction) async {
      final supplier = await transaction.get(
        FirebaseConstants.suppliers,
        supplierId,
      );
      if (!supplier.exists ||
          (supplier.fields['tenantId'] ?? supplier.fields['ownerUid']) !=
              tenantId) {
        throw const AppException('This supplier is not available to edit.');
      }
      final relationship = await transaction.get(
        FirebaseConstants.supplierBusinesses,
        relationshipId,
      );
      if (!relationship.exists ||
          relationship.fields['tenantId'] != tenantId ||
          relationship.fields['businessId'] != businessId ||
          relationship.fields['supplierId'] != supplierId ||
          (relationship.fields['status'] as String? ?? '').toUpperCase() !=
              'ACTIVE') {
        throw const AppException(
          'This supplier is not active for the selected business.',
        );
      }
      transaction.update(
        FirebaseConstants.suppliers,
        supplierId,
        supplierFields,
        updateTime: supplier.updateTime,
      );
      transaction.update(
        FirebaseConstants.supplierBusinesses,
        relationshipId,
        relationFields,
        updateTime: relationship.updateTime,
      );
    }, idToken: token);
  }

  Future<void> updateSupplierStatus({
    required String tenantId,
    required String supplierId,
    required bool isActive,
    required String updatedBy,
    required String token,
  }) async {
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((transaction) async {
      final supplier = await transaction.get(
        FirebaseConstants.suppliers,
        supplierId,
      );
      if (!supplier.exists ||
          (supplier.fields['tenantId'] ?? supplier.fields['ownerUid']) !=
              tenantId) {
        throw const AppException('This supplier is not available to update.');
      }
      transaction.update(FirebaseConstants.suppliers, supplierId, {
        'status': isActive ? 'ACTIVE' : 'INACTIVE',
        'updatedAt': now,
        'updatedBy': updatedBy,
      }, updateTime: supplier.updateTime);
    }, idToken: token);
  }

  Future<SupplierModel> createSupplier({
    required String tenantId,
    required String businessId,
    required String name,
    required String mobile,
    required String contactPerson,
    required String email,
    required String whatsapp,
    required String gstin,
    required String pan,
    required String stateCode,
    required String supplierType,
    required String address,
    required int creditLimit,
    required int paymentTermsDays,
    required int openingBalance,
    required bool preferred,
    required String createdBy,
    required String token,
  }) async {
    if (name.trim().length < 2 ||
        businessId.isEmpty ||
        tenantId.isEmpty ||
        creditLimit < 0 ||
        openingBalance < 0 ||
        paymentTermsDays < 0) {
      throw const AppException('Check the supplier details and try again.');
    }
    final existing = await getTenantSuppliers(tenantId, token);
    final normalizedMobile = _digits(mobile);
    final normalizedGstin = gstin.trim().toUpperCase();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedName = _clean(name).toLowerCase();
    if (existing.any(
      (supplier) => _clean(supplier.name).toLowerCase() == normalizedName,
    )) {
      throw const AppException(
        'A supplier with this name already exists in this tenant. Link the existing supplier to this business instead.',
      );
    }
    if (normalizedGstin.isNotEmpty &&
        existing.any(
          (supplier) => supplier.gstin?.toUpperCase() == normalizedGstin,
        )) {
      throw const AppException(
        'A supplier with this GSTIN already exists. Link that supplier to this business instead.',
      );
    }
    if (normalizedMobile.isNotEmpty &&
        existing.any(
          (supplier) => _digits(supplier.mobile ?? '') == normalizedMobile,
        )) {
      throw const AppException(
        'This contact number is already used by another supplier. Use a unique contact number or link the existing supplier.',
      );
    }
    if (normalizedEmail.isNotEmpty &&
        existing.any(
          (supplier) => supplier.email?.toLowerCase() == normalizedEmail,
        )) {
      throw const AppException(
        'A supplier with this email already exists. Link that supplier to this business instead.',
      );
    }
    final supplierId = IdGenerator.create('SUP');
    final supplierBusinessId = relationId(supplierId, businessId);
    final now = DateTime.now().toUtc();
    final supplierFields = <String, dynamic>{
      'supplierId': supplierId,
      'tenantId': tenantId,
      // Compatibility with this app's existing ownerUid-based Firestore
      // ownership rules. tenantId remains the canonical tenant key.
      'ownerUid': tenantId,
      'name': _clean(name),
      'contactName': _optional(contactPerson),
      'mobile': _optional(mobile),
      'whatsapp': _optional(whatsapp),
      'email': _optional(normalizedEmail),
      'gstin': _optional(normalizedGstin),
      'pan': _optional(pan.trim().toUpperCase()),
      'stateCode': _optional(stateCode.trim()),
      'supplierType': _optional(supplierType.trim()),
      'address': _optional(address.trim()),
      'status': 'ACTIVE',
      'createdAt': now,
      'createdBy': createdBy,
      'updatedAt': now,
      'updatedBy': createdBy,
    };
    final relationFields = <String, dynamic>{
      'supplierBusinessId': supplierBusinessId,
      'tenantId': tenantId,
      'ownerUid': tenantId,
      'supplierId': supplierId,
      'businessId': businessId,
      'creditLimit': creditLimit,
      'paymentTerms': paymentTermsDays,
      'openingBalance': openingBalance,
      'preferred': preferred,
      'status': 'ACTIVE',
      'createdAt': now,
      'createdBy': createdBy,
      'updatedAt': now,
      'updatedBy': createdBy,
    };
    await transactions.runAtomicOperation((transaction) async {
      final business = await transaction.get(
        FirebaseConstants.businesses,
        businessId,
      );
      if (!_businessIsActive(
        business.fields,
        exists: business.exists,
        tenantId: tenantId,
      )) {
        throw const AppException(
          'Select an active business that belongs to this tenant.',
        );
      }
      final relation = await transaction.get(
        FirebaseConstants.supplierBusinesses,
        supplierBusinessId,
      );
      if (relation.exists) {
        throw const AppException(
          'This supplier is already linked to the business.',
        );
      }
      transaction.create(
        FirebaseConstants.suppliers,
        supplierId,
        supplierFields,
      );
      transaction.create(
        FirebaseConstants.supplierBusinesses,
        supplierBusinessId,
        relationFields,
      );
      transaction.create(
        FirebaseConstants.supplierBalances,
        supplierBusinessId,
        _balanceFields(
          tenantId,
          businessId,
          supplierBusinessId,
          openingBalance,
          now,
        ),
      );
      if (openingBalance > 0) {
        transaction.create(
          FirebaseConstants.supplierLedgerEntries,
          'OPENING_$supplierBusinessId',
          _ledgerFields(
            tenantId: tenantId,
            businessId: businessId,
            supplierBusinessId: supplierBusinessId,
            supplierId: supplierId,
            entryType: 'OPENING_BALANCE',
            referenceType: 'OPENING_BALANCE',
            referenceId: supplierBusinessId,
            credit: openingBalance,
            createdBy: createdBy,
            now: now,
          ),
        );
      }
    }, idToken: token);
    return SupplierModel.fromData(supplierId, supplierFields);
  }

  Future<SupplierBusinessModel> linkExistingSupplier({
    required String tenantId,
    required String businessId,
    required String supplierId,
    required int creditLimit,
    required int paymentTermsDays,
    required int openingBalance,
    bool preferred = false,
    required String userId,
    required String token,
  }) async {
    final id = relationId(supplierId, businessId);
    final now = DateTime.now().toUtc();
    final relationFields = <String, dynamic>{
      'supplierBusinessId': id,
      'tenantId': tenantId,
      'ownerUid': tenantId,
      'supplierId': supplierId,
      'businessId': businessId,
      'creditLimit': creditLimit,
      'paymentTerms': paymentTermsDays,
      'openingBalance': openingBalance,
      'preferred': preferred,
      'status': 'ACTIVE',
      'createdAt': now,
      'createdBy': userId,
      'updatedAt': now,
      'updatedBy': userId,
    };
    await transactions.runAtomicOperation((transaction) async {
      final business = await transaction.get(
        FirebaseConstants.businesses,
        businessId,
      );
      if (!_businessIsActive(
        business.fields,
        exists: business.exists,
        tenantId: tenantId,
      )) {
        throw const AppException(
          'Select an active business that belongs to this tenant.',
        );
      }
      final supplier = await transaction.get(
        FirebaseConstants.suppliers,
        supplierId,
      );
      if (!supplier.exists ||
          (supplier.fields['tenantId'] ?? supplier.fields['ownerUid']) !=
              tenantId ||
          (supplier.fields['status'] as String? ?? '').toUpperCase() !=
              'ACTIVE') {
        throw const AppException('Select an active supplier from this tenant.');
      }
      final relation = await transaction.get(
        FirebaseConstants.supplierBusinesses,
        id,
      );
      if (relation.exists) {
        throw const AppException(
          'This supplier is already linked to the business.',
        );
      }
      transaction.create(
        FirebaseConstants.supplierBusinesses,
        id,
        relationFields,
      );
      transaction.create(
        FirebaseConstants.supplierBalances,
        id,
        _balanceFields(tenantId, businessId, id, openingBalance, now),
      );
      if (openingBalance > 0) {
        transaction.create(
          FirebaseConstants.supplierLedgerEntries,
          'OPENING_$id',
          _ledgerFields(
            tenantId: tenantId,
            businessId: businessId,
            supplierBusinessId: id,
            supplierId: supplierId,
            entryType: 'OPENING_BALANCE',
            referenceType: 'OPENING_BALANCE',
            referenceId: id,
            credit: openingBalance,
            createdBy: userId,
            now: now,
          ),
        );
      }
    }, idToken: token);
    return SupplierBusinessModel.fromData(id, relationFields);
  }

  static String relationId(String supplierId, String businessId) =>
      '${supplierId}_$businessId';

  Future<List<Map<String, dynamic>>> getSupplierBusinessDocuments(
    String tenantId,
    String businessId,
    String token,
  ) => firestore.queryDocuments(
    collection: FirebaseConstants.supplierBusinesses,
    filters: [
      FirestoreFilter('tenantId', 'EQUAL', tenantId),
      FirestoreFilter('businessId', 'EQUAL', businessId),
    ],
    idToken: token,
  );

  SupplierModel _supplier(Map<String, dynamic> document) =>
      SupplierModel.fromData(
        (document['name'] as String? ?? '').split('/').last,
        FirestoreRestService.decodeFields(document['fields']),
      );

  SupplierBusinessModel _relation(Map<String, dynamic> document) =>
      SupplierBusinessModel.fromData(
        (document['name'] as String? ?? '').split('/').last,
        FirestoreRestService.decodeFields(document['fields']),
      );

  static Map<String, dynamic> _balanceFields(
    String tenantId,
    String businessId,
    String relationId,
    int openingBalance,
    DateTime now,
  ) => {
    'tenantId': tenantId,
    'ownerUid': tenantId,
    'businessId': businessId,
    'supplierBusinessId': relationId,
    'totalPayable': openingBalance,
    'unallocatedAdvance': 0,
    'unallocatedReturnCredit': 0,
    'unallocatedSupplierCredit': 0,
    'lastLedgerEntryId': openingBalance > 0 ? 'OPENING_$relationId' : null,
    'updatedAt': now,
  };

  static Map<String, dynamic> _ledgerFields({
    required String tenantId,
    required String businessId,
    required String supplierBusinessId,
    required String supplierId,
    required String entryType,
    required String referenceType,
    required String referenceId,
    int debit = 0,
    int credit = 0,
    required String createdBy,
    required DateTime now,
  }) => {
    'ledgerEntryId': entryType == 'OPENING_BALANCE'
        ? 'OPENING_$supplierBusinessId'
        : '${referenceType}_$referenceId',
    'tenantId': tenantId,
    'ownerUid': tenantId,
    'businessId': businessId,
    'outletId': null,
    'supplierId': supplierId,
    'supplierBusinessId': supplierBusinessId,
    'entryType': entryType,
    'referenceType': referenceType,
    'referenceId': referenceId,
    'debit': debit,
    'credit': credit,
    'isReversal': false,
    'reversalOfId': null,
    'transactionDate': now,
    'createdBy': createdBy,
    'createdAt': now,
  };

  static String _clean(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');
  static String? _optional(String value) =>
      value.trim().isEmpty ? null : value.trim();
  static String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  static bool _businessIsActive(
    Map<String, dynamic> fields, {
    required bool exists,
    required String tenantId,
  }) =>
      exists &&
      (fields['tenantId'] ?? fields['ownerUid']) == tenantId &&
      (fields['isActive'] == true ||
          (fields['status'] as String? ?? '').toUpperCase() == 'ACTIVE');
}

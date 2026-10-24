import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/supplier_model.dart';
import '../models/supplier_refund_model.dart';
import '../models/financial_transaction_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

import 'dart:convert';
import '../local/local_data_source.dart';
import '../models/purchase_bill_model.dart';
import '../models/supplier_payment_receipt_model.dart';
import '../models/supplier_ledger_entry_model.dart';
import '../services/offline_firestore_service.dart';

class SupplierRepository {
  SupplierRepository(this.firestore, this.transactions);
  final FirestoreDataService firestore;
  final FirestoreTransactionService transactions;

  /// Authoritative server transaction runner for online-only financial operations.
  FirestoreTransactionService get serverTransactions {
    if (transactions is OfflineFirestoreService) {
      return (transactions as OfflineFirestoreService).serverTransactions;
    }
    if (firestore is OfflineFirestoreService) {
      return (firestore as OfflineFirestoreService).serverTransactions;
    }
    return transactions;
  }

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
    await serverTransactions.runAtomicOperation((tx) async {
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

  /// Retrieves approved outstanding purchase bills for this supplier relation in chronological FIFO order.
  Future<List<PurchaseBillModel>> getOutstandingPurchaseBills({
    required String tenantId,
    required String businessId,
    required String supplierBusinessId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.purchaseBills,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('supplierBusinessId', 'EQUAL', supplierBusinessId),
      ],
      idToken: token,
    );

    final bills = docs
        .map((doc) => PurchaseBillModel.fromData(
              (doc['name'] as String? ?? '').split('/').last,
              FirestoreRestService.decodeFields(doc['fields']),
            ))
        .where((b) {
          if (b.status != 'APPROVED') return false;
          final effDue = b.outstandingAmount > 0
              ? b.outstandingAmount
              : (b.grandTotal - b.paidAmount);
          return effDue > 0;
        })
        .toList();

    bills.sort((a, b) => a.invoiceDate.compareTo(b.invoiceDate));
    return bills;
  }

  /// Settles supplier dues using a FIFO (first-in, first-out) multi-bill strategy,
  /// updating approved bills in chronological order, recording payment and ledger entries,
  /// adjusting totalPayable in supplierBalances, and returning full receipt metadata.
  Future<SupplierPaymentReceiptModel> settleSupplierDues({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String supplierId,
    required String supplierBusinessId,
    required int amountPaise,
    required String paymentMode,
    required String transactionReference,
    DateTime? paymentDate,
    required String userId,
    required String token,
    String? businessName,
    String? outletName,
  }) async {
    if (amountPaise <= 0) {
      throw const AppException('Enter a payment amount greater than zero.');
    }
    final validModes = {'CASH', 'UPI', 'BANK_TRANSFER', 'CHEQUE', 'CARD'};
    if (!validModes.contains(paymentMode)) {
      throw const AppException('Select a valid payment mode.');
    }

    final now = paymentDate ?? DateTime.now().toUtc();
    final paymentId = IdGenerator.create('SPAY');
    final ledgerId = 'SUPPLIER_PAYMENT_$paymentId';

    late SupplierPaymentReceiptModel receipt;
    final localBillsToUpdate = <Map<String, dynamic>>[];

    await serverTransactions.runAtomicOperation((tx) async {
      final relationDoc = await tx.get(
        FirebaseConstants.supplierBusinesses,
        supplierBusinessId,
      );
      if (!relationDoc.exists ||
          relationDoc.fields['tenantId'] != tenantId ||
          relationDoc.fields['businessId'] != businessId ||
          relationDoc.fields['supplierId'] != supplierId ||
          relationDoc.fields['status'] != 'ACTIVE') {
        throw const AppException(
          'This supplier is not active for the current business.',
        );
      }

      final supplierDoc = await tx.get(
        FirebaseConstants.suppliers,
        supplierId,
      );
      final supplierFields =
          supplierDoc.exists ? supplierDoc.fields : <String, dynamic>{};
      final supplierName = supplierFields['name'] as String? ??
          relationDoc.fields['supplierName'] as String? ??
          'Supplier';
      final supplierPhone = supplierFields['phone'] as String?;

      final balanceDoc = await tx.get(
        FirebaseConstants.supplierBalances,
        supplierBusinessId,
      );
      final oldPayable =
          (balanceDoc.fields['totalPayable'] as num?)?.toInt() ?? 0;
      final oldAdvance =
          (balanceDoc.fields['unallocatedAdvance'] as num?)?.toInt() ?? 0;

      final billDocs = await tx.query(FirebaseConstants.purchaseBills, [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('supplierBusinessId', 'EQUAL', supplierBusinessId),
      ]);

      final outstandingBills = billDocs.where((doc) {
        final status = doc.fields['status']?.toString() ?? '';
        if (status != 'APPROVED') return false;
        final grandTotal = (doc.fields['grandTotal'] as num?)?.toInt() ?? 0;
        final paid = (doc.fields['paidAmount'] as num?)?.toInt() ?? 0;
        final out = (doc.fields['outstandingAmount'] as num?)?.toInt() ??
            (grandTotal - paid);
        return out > 0;
      }).toList();

      outstandingBills.sort((a, b) {
        final dateA = DateTime.tryParse(
              a.fields['invoiceDate']?.toString() ??
                  a.fields['createdAt']?.toString() ??
                  '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(
              b.fields['invoiceDate']?.toString() ??
                  b.fields['createdAt']?.toString() ??
                  '',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = dateA.compareTo(dateB);
        if (cmp != 0) return cmp;
        final idA = a.id ?? '';
        final idB = b.id ?? '';
        return idA.compareTo(idB);
      });

      var remainingToAllocate = amountPaise;
      final settledBills = <SupplierSettledBillInfo>[];

      for (final bDoc in outstandingBills) {
        if (remainingToAllocate <= 0) break;
        final bId = bDoc.id ?? bDoc.fields['purchaseBillId']?.toString() ?? '';
        if (bId.isEmpty) continue;
        final grandTotal = (bDoc.fields['grandTotal'] as num?)?.toInt() ?? 0;
        final currentPaid = (bDoc.fields['paidAmount'] as num?)?.toInt() ?? 0;
        final effectiveDue = ((bDoc.fields['outstandingAmount'] as num?)?.toInt() ??
                (grandTotal - currentPaid))
            .clamp(0, grandTotal);
        if (effectiveDue <= 0) continue;

        final alloc =
            remainingToAllocate > effectiveDue ? effectiveDue : remainingToAllocate;
        remainingToAllocate -= alloc;
        final newDue = effectiveDue - alloc;
        final newPaid = currentPaid + alloc;
        final newPaymentStatus = newDue == 0 ? 'PAID' : 'PARTIAL';
        final version = (bDoc.fields['version'] as num?)?.toInt() ?? 1;

        final updatedBillFields = {
          'paidAmount': newPaid,
          'outstandingAmount': newDue,
          'paymentStatus': newPaymentStatus,
          'updatedBy': userId,
          'updatedAt': now,
          'version': version + 1,
        };
        tx.update(
          FirebaseConstants.purchaseBills,
          bId,
          updatedBillFields,
          updateTime: bDoc.updateTime,
        );

        localBillsToUpdate.add({
          'id': bId,
          'fields': {
            ...bDoc.fields,
            ...updatedBillFields,
          },
        });

        final allocId = '${paymentId}_$bId';
        tx.create(FirebaseConstants.paymentAllocations, allocId, {
          'allocationId': allocId,
          'tenantId': tenantId,
          'businessId': businessId,
          'supplierBusinessId': supplierBusinessId,
          'sourceType': 'PAYMENT',
          'sourceId': paymentId,
          'purchaseBillId': bId,
          'allocatedAmount': alloc,
          'createdBy': userId,
          'createdAt': now,
        });

        final invNum = bDoc.fields['supplierInvoiceNumber'] as String? ??
            bDoc.fields['purchaseNumber'] as String? ??
            bId;
        final invDateStr = bDoc.fields['invoiceDate']?.toString();
        final invDate = invDateStr != null ? DateTime.tryParse(invDateStr) : null;

        settledBills.add(SupplierSettledBillInfo(
          billId: bId,
          invoiceNumber: invNum,
          invoiceDate: invDate,
          billTotalPaise: grandTotal,
          paidBeforePaise: currentPaid,
          allocatedPaise: alloc,
          remainingDuePaise: newDue,
          isFullyPaid: newDue == 0,
        ));
      }

      final totalAllocated = amountPaise - remainingToAllocate;
      final newPayable =
          (oldPayable - totalAllocated).clamp(0, double.infinity).toInt();
      final newAdvance = oldAdvance + remainingToAllocate;

      tx.create(FirebaseConstants.supplierPayments, paymentId, {
        'paymentId': paymentId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'supplierId': supplierId,
        'supplierBusinessId': supplierBusinessId,
        'paymentType': settledBills.isNotEmpty ? 'AGAINST_BILL' : 'ADVANCE',
        'amount': amountPaise,
        'allocatedAmount': totalAllocated,
        'unallocatedAmount': remainingToAllocate,
        'purchaseBillId':
            settledBills.length == 1 ? settledBills.first.billId : null,
        'paymentDate': now,
        'paymentMode': paymentMode,
        'transactionReference': transactionReference.trim(),
        'status': 'POSTED',
        'createdBy': userId,
        'createdAt': now,
        'updatedBy': userId,
        'updatedAt': now,
      });

      final vchNumber = paymentId;
      final refStr = transactionReference.trim();
      tx.create(FirebaseConstants.supplierLedgerEntries, ledgerId, {
        'ledgerEntryId': ledgerId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'supplierId': supplierId,
        'supplierBusinessId': supplierBusinessId,
        'entryType': 'SUPPLIER_PAYMENT',
        'referenceType': 'SUPPLIER_PAYMENT',
        'referenceId': paymentId,
        'voucherNumber': vchNumber,
        'referenceNo': refStr,
        'transactionReference': refStr,
        'paymentMode': paymentMode,
        'particulars': refStr.isNotEmpty
            ? 'Due Payment ($paymentMode) Ref: $refStr'
            : 'Due Payment ($paymentMode)',
        'debit': amountPaise,
        'credit': 0,
        'isReversal': false,
        'reversalOfId': null,
        'transactionDate': now,
        'createdBy': userId,
        'createdAt': now,
      });

      final balanceFields = {
        'tenantId': tenantId,
        'businessId': businessId,
        'supplierBusinessId': supplierBusinessId,
        'totalPayable': newPayable,
        'unallocatedAdvance': newAdvance,
        'unallocatedReturnCredit':
            (balanceDoc.fields['unallocatedReturnCredit'] as num?)?.toInt() ?? 0,
        'unallocatedSupplierCredit':
            (balanceDoc.fields['unallocatedSupplierCredit'] as num?)?.toInt() ?? 0,
        'lastLedgerEntryId': ledgerId,
        'updatedAt': now,
      };

      if (balanceDoc.exists) {
        tx.update(
          FirebaseConstants.supplierBalances,
          supplierBusinessId,
          balanceFields,
          updateTime: balanceDoc.updateTime,
        );
      } else {
        tx.create(
          FirebaseConstants.supplierBalances,
          supplierBusinessId,
          balanceFields,
        );
      }

      receipt = SupplierPaymentReceiptModel(
        paymentId: paymentId,
        voucherNumber: paymentId,
        paymentDate: now,
        supplierId: supplierId,
        supplierName: supplierName,
        supplierPhone: supplierPhone,
        businessName: businessName ?? '',
        outletName: outletName,
        paymentMode: paymentMode,
        referenceNo: transactionReference.trim().isEmpty
            ? null
            : transactionReference.trim(),
        previousDuePaise: oldPayable,
        amountPaidPaise: amountPaise,
        remainingDuePaise: newPayable,
        unallocatedAdvancePaise: remainingToAllocate,
        settledBills: settledBills,
      );
    }, idToken: token);

    // Sync offline cache if available
    if (firestore is OfflineFirestoreService && localBillsToUpdate.isNotEmpty) {
      final local = (firestore as OfflineFirestoreService).localDataSource;
      if (local != null) {
        try {
          await local.db.transaction((localTx) async {
            for (final item in localBillsToUpdate) {
              final bId = item['id'] as String;
              final bFields = item['fields'] as Map<String, dynamic>;
              await LocalDataSource.put(
                localTx,
                FirebaseConstants.purchaseBills,
                {
                  'remoteId': bId,
                  'payloadJson':
                      jsonEncode(FirestoreRestService.encodeFields(bFields)),
                  ...LocalDataSource.scopeColumns(bFields),
                  'syncStatus': 'SYNCED',
                  'localUpdatedAt': LocalDataSource.now(),
                  'isDeleted': 0,
                },
              );
            }
          });
        } catch (_) {}
      }
    }

    return receipt;
  }

  /// Retrieves supplier ledger transactions chronologically with computed running balance.
  /// Enriches transactions with actual invoice numbers, voucher numbers, payment modes,
  /// and items summary from purchase bills and supplier payments.
  Future<List<SupplierLedgerEntryModel>> getSupplierLedger({
    required String tenantId,
    required String businessId,
    required String supplierId,
    required String token,
  }) async {
    final ledgerDocsFuture = firestore.queryDocuments(
      collection: FirebaseConstants.supplierLedgerEntries,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('supplierId', 'EQUAL', supplierId),
      ],
      idToken: token,
    );

    final purchaseDocsFuture = firestore.queryDocuments(
      collection: FirebaseConstants.purchaseBills,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('supplierId', 'EQUAL', supplierId),
      ],
      idToken: token,
    ).catchError((_) => <Map<String, dynamic>>[]);

    final paymentDocsFuture = firestore.queryDocuments(
      collection: FirebaseConstants.supplierPayments,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('supplierId', 'EQUAL', supplierId),
      ],
      idToken: token,
    ).catchError((_) => <Map<String, dynamic>>[]);

    final results = await Future.wait([
      ledgerDocsFuture,
      purchaseDocsFuture,
      paymentDocsFuture,
    ]);

    final ledgerDocs = results[0];
    final purchaseDocs = results[1];
    final paymentDocs = results[2];

    // Build lookup maps for enrichment
    final billMap = <String, Map<String, dynamic>>{};
    for (final doc in purchaseDocs) {
      final docId = (doc['name'] as String? ?? '').split('/').last;
      final f = FirestoreRestService.decodeFields(doc['fields']);
      billMap[docId] = f;
      final pBillId = f['purchaseBillId'] as String?;
      if (pBillId != null && pBillId.isNotEmpty) {
        billMap[pBillId] = f;
      }
    }

    final paymentMap = <String, Map<String, dynamic>>{};
    for (final doc in paymentDocs) {
      final docId = (doc['name'] as String? ?? '').split('/').last;
      final f = FirestoreRestService.decodeFields(doc['fields']);
      paymentMap[docId] = f;
      final pmId = f['supplierPaymentId'] as String?;
      if (pmId != null && pmId.isNotEmpty) {
        paymentMap[pmId] = f;
      }
    }

    final entries = ledgerDocs.map((doc) {
      final id = (doc['name'] as String? ?? '').split('/').last;
      final fields = FirestoreRestService.decodeFields(doc['fields']);

      final refId = fields['referenceId'] as String? ?? '';
      final entryType = fields['entryType'] as String? ?? '';

      // Clean refId in case of prefixes
      final cleanRefId = refId
          .replaceFirst('PURCHASE_BILL_', '')
          .replaceFirst('SUPPLIER_PAYMENT_', '')
          .replaceFirst(RegExp(r'_\d+$'), '');

      String? fallbackVch;
      String? fallbackRef;
      String? fallbackMode;
      String? fallbackParticulars;
      String? fallbackItems;

      if (entryType == 'PURCHASE_BILL' || (fields['credit'] as num? ?? 0) > 0) {
        final b = billMap[refId] ?? billMap[cleanRefId] ?? billMap[id];
        if (b != null) {
          final supInv = (b['supplierInvoiceNumber'] as String?)?.trim();
          final pNum = (b['purchaseNumber'] as String?)?.trim();
          fallbackVch = (supInv != null && supInv.isNotEmpty)
              ? supInv
              : ((pNum != null && pNum.isNotEmpty) ? pNum : (refId.isNotEmpty ? refId : id));

          final items = (b['items'] as List?) ?? [];
          final names = items.map((i) {
            if (i is Map) {
              return i['productName']?.toString().trim() ?? '';
            }
            return '';
          }).where((s) => s.isNotEmpty).take(3).join(', ');

          fallbackItems = names.isNotEmpty ? names : null;
          fallbackParticulars = fallbackVch.isNotEmpty
              ? 'Purchase Bill #$fallbackVch${names.isNotEmpty ? ' ($names)' : ''}'
              : 'Purchase Bill';
        } else if (refId.isNotEmpty) {
          fallbackVch = refId;
          fallbackParticulars = 'Purchase Bill #$refId';
        }
      } else if (entryType == 'SUPPLIER_PAYMENT' || (fields['debit'] as num? ?? 0) > 0) {
        final pm = paymentMap[refId] ?? paymentMap[cleanRefId] ?? paymentMap[id];
        if (pm != null) {
          final vch = (pm['voucherNumber'] as String?)?.trim();
          final ref = (pm['transactionReference'] as String?)?.trim();
          fallbackVch = (vch != null && vch.isNotEmpty)
              ? vch
              : (refId.isNotEmpty ? refId : id);
          fallbackRef = ref;
          fallbackMode = pm['paymentMode'] as String?;

          final modeStr = fallbackMode ?? 'PAYMENT';
          if (ref != null && ref.isNotEmpty) {
            fallbackParticulars = 'Payment ($modeStr) Ref: $ref';
          } else {
            fallbackParticulars = 'Supplier Payment ($modeStr)';
          }
        } else if (refId.isNotEmpty) {
          fallbackVch = refId;
          fallbackParticulars = 'Supplier Payment #$refId';
        }
      } else if (entryType == 'OPENING_BALANCE') {
        fallbackParticulars = 'Opening Balance';
        fallbackVch = 'OPENING';
      }

      return SupplierLedgerEntryModel.fromData(
        id,
        fields,
        fallbackVoucherNumber: fallbackVch,
        fallbackReferenceNo: fallbackRef,
        fallbackPaymentMode: fallbackMode,
        fallbackParticulars: fallbackParticulars,
        fallbackItemsSummary: fallbackItems,
      );
    }).toList();

    entries.sort((a, b) {
      final cmp = a.transactionDate.compareTo(b.transactionDate);
      if (cmp != 0) return cmp;
      return a.createdAt.compareTo(b.createdAt);
    });

    var running = 0;
    final computed = <SupplierLedgerEntryModel>[];
    for (final e in entries) {
      running += (e.creditPaise - e.debitPaise);
      computed.add(e.copyWith(runningBalancePaise: running));
    }
    return computed;
  }


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

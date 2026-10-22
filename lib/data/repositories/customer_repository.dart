import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/permissions/permission_catalog.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/customers/customer_validators.dart';
import '../models/customer_ledger_entry_model.dart';
import '../models/customer_model.dart';
import '../models/customer_payment_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';

class CustomerRepository {
  CustomerRepository(this.firestore, {FirestoreTransactionService? transactions})
      : _transactions = transactions ??
            (firestore is FirestoreTransactionService
                ? firestore as FirestoreTransactionService
                : null);

  final FirestoreDataService firestore;
  final FirestoreTransactionService? _transactions;

  FirestoreTransactionService get transactions {
    final tx = _transactions;
    if (tx == null) {
      throw const AppException('Atomic transaction service is unavailable.');
    }
    return tx;
  }

  Future<List<CustomerModel>> search({
    required String tenantId,
    required String businessId,
    required String token,
    String? phone,
    String? nameLowerPrefix,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (phone != null) FirestoreFilter('phone', 'EQUAL', phone),
      ],
      orderBy: nameLowerPrefix == null ? 'nameLower' : null,
      idToken: token,
    );
    return [
      for (final doc in docs)
        CustomerModel.fromData(
          (doc['name'] as String? ?? '').split('/').last,
          FirestoreRestService.decodeFields(doc['fields']),
        ),
    ].where((customer) {
      final prefix = nameLowerPrefix?.toLowerCase();
      return prefix == null || customer.nameLower.startsWith(prefix);
    }).toList();
  }

  Future<CustomerModel> create({
    required String tenantId,
    required String businessId,
    required String token,
    required String name,
    required String phone,
    String customerType = CustomerModel.typeIndividual,
    bool isGstRegistered = false,
    String? gstin,
    String? stateCode,
    String? address,
    int? creditLimitPaise,
    int openingBalancePaise = 0,
    String? actorUid,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{10}$').hasMatch(normalizedPhone)) {
      throw const AppException('Enter a valid 10-digit phone number.');
    }
    final duplicates = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('phone', 'EQUAL', normalizedPhone),
      ],
      idToken: token,
    );
    if (duplicates.isNotEmpty) {
      throw const AppException('A customer with this phone already exists.');
    }

    final String? effectiveGstin;
    if (isGstRegistered) {
      final validationError =
          CustomerValidators.validateGstinForRegistration(gstin);
      if (validationError != null) {
        throw AppException(validationError);
      }
      effectiveGstin = CustomerValidators.normalizeGstin(gstin);
    } else if (gstin != null && gstin.trim().isNotEmpty) {
      final normalized = CustomerValidators.normalizeGstin(gstin);
      if (!CustomerValidators.isValidGstin(normalized)) {
        throw const AppException('Enter a valid GSTIN or leave it blank.');
      }
      effectiveGstin = normalized;
    } else {
      effectiveGstin = null;
    }

    final id = IdGenerator.create('CUS');
    final now = DateTime.now().toUtc().toIso8601String();
    final customer = CustomerModel(
      customerId: id,
      businessId: businessId,
      tenantId: tenantId,
      name: name.trim(),
      phone: normalizedPhone,
      nameLower: name.trim().toLowerCase(),
      customerType: customerType,
      isGstRegistered: isGstRegistered,
      gstin: effectiveGstin,
      stateCode: stateCode?.trim().isEmpty == true ? null : stateCode?.trim().toUpperCase(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      creditLimitPaise: creditLimitPaise,
      duePaise: openingBalancePaise > 0 ? openingBalancePaise : 0,
      advancePaise: openingBalancePaise < 0 ? -openingBalancePaise : 0,
      updatedAt: now,
    );
    await firestore.createDocument(FirebaseConstants.customers, id, {
      'customerId': id,
      'tenantId': tenantId,
      'businessId': businessId,
      'name': customer.name,
      'nameLower': customer.nameLower,
      'phone': customer.phone,
      'customerType': customer.customerType,
      'isGstRegistered': customer.isGstRegistered,
      if (customer.gstin != null) 'gstin': customer.gstin,
      if (customer.stateCode != null) 'stateCode': customer.stateCode,
      if (customer.address != null) 'address': customer.address,
      if (customer.creditLimitPaise != null)
        'creditLimitPaise': customer.creditLimitPaise,
      'duePaise': customer.duePaise,
      'advancePaise': customer.advancePaise,
      'status': customer.status,
      'updatedAt': now,
    }, idToken: token);

    // If opening balance was provided, record an immutable opening balance ledger entry
    if (openingBalancePaise != 0) {
      final openingLedgerId = 'LED_OPENING_$id';
      await firestore.createDocument(
        FirebaseConstants.customerLedgerEntries,
        openingLedgerId,
        {
          'transactionId': openingLedgerId,
          'businessId': businessId,
          'tenantId': tenantId,
          'customerId': id,
          'outletId': '',
          'transactionType': CustomerLedgerEntryModel.typeOpeningBalance,
          'amountPaise': openingBalancePaise.abs(),
          'debitPaise': openingBalancePaise > 0 ? openingBalancePaise : 0,
          'creditPaise': openingBalancePaise < 0 ? -openingBalancePaise : 0,
          'advanceCreditPaise': openingBalancePaise < 0 ? -openingBalancePaise : 0,
          'createdAt': now,
          'createdBy': actorUid ?? 'SYSTEM',
          'status': 'POSTED',
          'immutable': true,
        },
        idToken: token,
      );
    }

    return customer;
  }

  Future<CustomerModel> update({
    required String tenantId,
    required String businessId,
    required String token,
    required CustomerModel customer,
    required String name,
    required String phone,
    String? customerType,
    bool? isGstRegistered,
    String? gstin,
    String? stateCode,
    String? address,
    int? creditLimitPaise,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^\d{10}$').hasMatch(normalizedPhone)) {
      throw const AppException('Enter a valid 10-digit phone number.');
    }
    final duplicates = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('phone', 'EQUAL', normalizedPhone),
      ],
      idToken: token,
    );
    if (duplicates.any((doc) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      final id = data['customerId'] as String? ?? '';
      return id != customer.customerId;
    })) {
      throw const AppException('A customer with this phone already exists.');
    }

    final effectiveCustomerType = customerType ?? customer.customerType;
    final effectiveIsGstRegistered = isGstRegistered ?? customer.isGstRegistered;
    final String? candidateGstin = gstin ?? customer.gstin;
    final String? effectiveGstin;
    if (effectiveIsGstRegistered) {
      final validationError =
          CustomerValidators.validateGstinForRegistration(candidateGstin);
      if (validationError != null) {
        throw AppException(validationError);
      }
      effectiveGstin = CustomerValidators.normalizeGstin(candidateGstin);
    } else if (candidateGstin != null && candidateGstin.trim().isNotEmpty) {
      final normalized = CustomerValidators.normalizeGstin(candidateGstin);
      if (!CustomerValidators.isValidGstin(normalized)) {
        throw const AppException('Enter a valid GSTIN or leave it blank.');
      }
      effectiveGstin = normalized;
    } else {
      effectiveGstin = null;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final updated = CustomerModel(
      customerId: customer.customerId,
      businessId: businessId,
      tenantId: tenantId,
      name: name.trim(),
      phone: normalizedPhone,
      nameLower: name.trim().toLowerCase(),
      customerType: effectiveCustomerType,
      isGstRegistered: effectiveIsGstRegistered,
      gstin: effectiveGstin,
      stateCode: stateCode?.trim().isEmpty == true ? null : stateCode?.trim().toUpperCase(),
      address: address?.trim().isEmpty == true ? null : address?.trim(),
      creditLimitPaise: creditLimitPaise,
      duePaise: customer.duePaise,
      advancePaise: customer.advancePaise,
      status: customer.status,
      updatedAt: now,
    );
    await firestore.updateDocument(
      FirebaseConstants.customers,
      customer.customerId,
      {
        'customerId': updated.customerId,
        'tenantId': tenantId,
        'businessId': businessId,
        'name': updated.name,
        'nameLower': updated.nameLower,
        'phone': updated.phone,
        'customerType': updated.customerType,
        'isGstRegistered': updated.isGstRegistered,
        'gstin': updated.gstin,
        'stateCode': updated.stateCode,
        'address': updated.address,
        'creditLimitPaise': updated.creditLimitPaise,
        'duePaise': updated.duePaise,
        'advancePaise': updated.advancePaise,
        'status': updated.status,
        'updatedAt': now,
      },
      idToken: token,
    );
    return updated;
  }

  /// Retrieves outstanding invoices for [customerId] across the business.
  /// If the user is an employee without cross-outlet permissions, results are
  /// restricted to the employee's assigned outlet.
  Future<List<Map<String, dynamic>>> getOutstandingInvoices({
    required String tenantId,
    required String businessId,
    required String customerId,
    String? outletId,
    required String token,
    List<String>? employeePermissions,
    String? employeeOutletId,
    bool isOwner = false,
  }) async {
    if (!isOwner && employeePermissions != null) {
      final canViewDue = PermissionCatalog.allows('DUE_VIEW', employeePermissions) ||
          PermissionCatalog.allows('CUSTOMER_VIEW', employeePermissions) ||
          PermissionCatalog.allows('customers', employeePermissions);
      if (!canViewDue) {
        throw const AppException(
          'You do not have permission to view customer dues (DUE_VIEW required).',
        );
      }
    }

    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.invoices,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('customerId', 'EQUAL', customerId),
        if (outletId != null) FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );

    final invoices = docs
        .map((doc) => FirestoreRestService.decodeFields(doc['fields']))
        .where((inv) {
          final status = inv['status']?.toString() ?? '';
          final due = _int(inv['dueAmount']);
          return status != 'CANCELLED' && due > 0;
        })
        .toList();

    // Respect employee outlet visibility restrictions
    if (!isOwner && employeePermissions != null && employeeOutletId != null) {
      final hasCrossOutlet = PermissionCatalog.allows(
        'CROSS_OUTLET_DUE_COLLECT',
        employeePermissions,
      );
      if (!hasCrossOutlet) {
        return invoices
            .where((inv) => inv['outletId'] == employeeOutletId)
            .toList();
      }
    }

    return invoices;
  }

  /// Reads the chronological customer ledger entries across the business.
  Future<List<CustomerLedgerEntryModel>> getCustomerLedger({
    required String tenantId,
    required String businessId,
    required String customerId,
    required String token,
    List<String>? employeePermissions,
    bool isOwner = false,
  }) async {
    if (!isOwner && employeePermissions != null) {
      final canViewLedger = PermissionCatalog.allows(
            'CUSTOMER_LEDGER_VIEW',
            employeePermissions,
          ) ||
          PermissionCatalog.allows('customers', employeePermissions);
      if (!canViewLedger) {
        throw const AppException(
          'You do not have permission to view customer ledger (CUSTOMER_LEDGER_VIEW required).',
        );
      }
    }

    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.customerLedgerEntries,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('customerId', 'EQUAL', customerId),
      ],
      idToken: token,
    );

    final entries = docs.map((doc) {
      final id = (doc['name'] as String? ?? '').split('/').last;
      return CustomerLedgerEntryModel.fromData(
        id,
        FirestoreRestService.decodeFields(doc['fields']),
      );
    }).toList();

    entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return entries;
  }

  /// Collects payment from a customer at [collectedAtOutletId] to settle dues.
  /// Settles eligible invoices across outlets using FIFO (oldest first) or [manualAllocations].
  ///
  /// Permission rules enforced at data access layer:
  /// - Requires DUE_COLLECT permission.
  /// - Invoices from other outlets require explicit CROSS_OUTLET_DUE_COLLECT permission.
  /// - Idempotent: repeated submission with same [idempotencyKey] returns existing payment record.
  Future<CustomerPaymentRecord> collectPayment({
    required String tenantId,
    required String businessId,
    required String customerId,
    required String collectedAtOutletId,
    required int amountPaise,
    required String paymentMethod,
    required String actorUid,
    required String token,
    List<String>? employeePermissions,
    List<PaymentAllocationRequest>? manualAllocations,
    bool allowAdvance = false,
    String? idempotencyKey,
    String? notes,
    bool isOwner = false,
  }) async {
    if (amountPaise <= 0) {
      throw const AppException('Payment amount must be greater than zero.');
    }

    // Permission enforcement at the data-access layer
    final hasCollectPermission = isOwner ||
        PermissionCatalog.allows('DUE_COLLECT', employeePermissions ?? const []) ||
        PermissionCatalog.allows('billing', employeePermissions ?? const []);
    if (!hasCollectPermission) {
      throw const AppException(
        'You do not have permission to collect dues (DUE_COLLECT required).',
      );
    }

    final hasCrossOutletPermission = isOwner ||
        PermissionCatalog.allows(
          'CROSS_OUTLET_DUE_COLLECT',
          employeePermissions ?? const [],
        );

    if (manualAllocations != null) {
      for (final alloc in manualAllocations) {
        if (alloc.originalOutletId != collectedAtOutletId &&
            !hasCrossOutletPermission) {
          throw const AppException(
            'You do not have permission to collect dues for other outlets (CROSS_OUTLET_DUE_COLLECT required).',
          );
        }
      }
    }

    final paymentId = (idempotencyKey != null && idempotencyKey.trim().isNotEmpty)
        ? 'PAY_${idempotencyKey.trim()}'
        : IdGenerator.create('PAY');

    return transactions.runAtomicOperation((tx) async {
      // 1. Check idempotency: If payment already recorded, return it without duplicate writes
      final existingPayment =
          await tx.get(FirebaseConstants.payments, paymentId);
      if (existingPayment.exists) {
        return CustomerPaymentRecord.fromData(paymentId, existingPayment.fields);
      }

      // 2. Load customer document
      final customerDoc = await tx.get(FirebaseConstants.customers, customerId);
      if (!customerDoc.exists ||
          customerDoc.fields['tenantId'] != tenantId ||
          customerDoc.fields['businessId'] != businessId) {
        throw const AppException('Customer not found in this Business.');
      }

      // 3. Query eligible outstanding invoices for this customer
      final invoiceDocs = await tx.query(FirebaseConstants.invoices, [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('customerId', 'EQUAL', customerId),
      ]);

      final outstandingInvoices = invoiceDocs.where((doc) {
        final status = doc.fields['status']?.toString() ?? '';
        final due = _int(doc.fields['dueAmount']);
        return status != 'CANCELLED' && due > 0;
      }).toList();

      final now = DateTime.now().toUtc();
      final nowIso = now.toIso8601String();
      final allocationsToPost = <CustomerPaymentAllocation>[];

      // 4. Calculate invoice allocations
      if (manualAllocations != null && manualAllocations.isNotEmpty) {
        var runningAllocated = 0;
        for (final req in manualAllocations) {
          if (req.allocatedPaise <= 0) {
            throw const AppException(
              'Each invoice allocation must be a positive amount.',
            );
          }
          final match = outstandingInvoices
              .where((doc) => doc.fields['invoiceId'] == req.invoiceId)
              .firstOrNull;
          if (match == null) {
            throw AppException(
              'Invoice "${req.invoiceId}" is not currently outstanding for this customer.',
            );
          }
          final remDue = _int(match.fields['dueAmount']);
          if (req.allocatedPaise > remDue) {
            throw AppException(
              'Allocated amount (₹${_formatMoney(req.allocatedPaise)}) exceeds remaining due (₹${_formatMoney(remDue)}) on invoice ${match.fields['invoiceNumber'] ?? req.invoiceId}.',
            );
          }
          final invOutlet = match.fields['outletId']?.toString() ?? '';
          if (invOutlet != collectedAtOutletId && !hasCrossOutletPermission) {
            throw const AppException(
              'You do not have permission to collect dues for other outlets (CROSS_OUTLET_DUE_COLLECT required).',
            );
          }
          runningAllocated += req.allocatedPaise;
          if (runningAllocated > amountPaise) {
            throw const AppException(
              'Sum of allocations exceeds available payment amount.',
            );
          }
          allocationsToPost.add(
            CustomerPaymentAllocation(
              allocationId: '${paymentId}_${req.invoiceId}',
              paymentId: paymentId,
              invoiceId: req.invoiceId,
              originalOutletId: invOutlet,
              allocatedPaise: req.allocatedPaise,
              status: 'POSTED',
              createdAt: now,
            ),
          );
        }
      } else {
        // FIFO Allocation Strategy:
        // Filter by outlet if cross-outlet permission is missing
        final eligible = hasCrossOutletPermission
            ? List<FirestoreTransactionDocument>.from(outstandingInvoices)
            : outstandingInvoices
                .where((doc) => doc.fields['outletId'] == collectedAtOutletId)
                .toList();

        // Deterministic sorting: earliest invoiceDate, then stable invoiceId
        eligible.sort((a, b) {
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
          final idA = a.fields['invoiceId']?.toString() ?? '';
          final idB = b.fields['invoiceId']?.toString() ?? '';
          return idA.compareTo(idB);
        });

        var remainingToAllocate = amountPaise;
        for (final inv in eligible) {
          if (remainingToAllocate <= 0) break;
          final remDue = _int(inv.fields['dueAmount']);
          if (remDue <= 0) continue;
          final alloc = remainingToAllocate > remDue ? remDue : remainingToAllocate;
          final invoiceId = inv.fields['invoiceId']?.toString() ?? '';
          final originalOutletId = inv.fields['outletId']?.toString() ?? '';
          allocationsToPost.add(
            CustomerPaymentAllocation(
              allocationId: '${paymentId}_$invoiceId',
              paymentId: paymentId,
              invoiceId: invoiceId,
              originalOutletId: originalOutletId,
              allocatedPaise: alloc,
              status: 'POSTED',
              createdAt: now,
            ),
          );
          remainingToAllocate -= alloc;
        }
      }

      final totalAllocated =
          allocationsToPost.fold<int>(0, (sum, a) => sum + a.allocatedPaise);
      final excessAdvance = amountPaise - totalAllocated;

      if (excessAdvance > 0 && !allowAdvance) {
        throw AppException(
          'Payment of ₹${_formatMoney(amountPaise)} exceeds allocated invoice dues of ₹${_formatMoney(totalAllocated)}. Explicitly confirm saving excess as customer advance.',
        );
      }

      // 5. Update settled invoices and post individual allocations
      for (final alloc in allocationsToPost) {
        final invDoc = outstandingInvoices
            .firstWhere((doc) => doc.fields['invoiceId'] == alloc.invoiceId);
        final oldDue = _int(invDoc.fields['dueAmount']);
        final oldPaid = _int(invDoc.fields['paidPaise']);
        final newDue = oldDue - alloc.allocatedPaise;
        final newPaid = oldPaid + alloc.allocatedPaise;
        final newStatus = newDue == 0 ? 'PAID' : 'PARTIALLY_PAID';

        tx.update(
          FirebaseConstants.invoices,
          alloc.invoiceId,
          {
            'dueAmount': newDue,
            'paidPaise': newPaid,
            'status': newStatus,
            'paymentStatus': newStatus,
            'updatedAt': nowIso,
          },
          updateTime: invDoc.updateTime,
        );

        // Payment allocation record
        tx.create(
          FirebaseConstants.paymentAllocations,
          alloc.allocationId,
          alloc.toData(),
        );

        // Individual ledger entry retaining original invoice outlet and collecting outlet
        final ledgerTransactionId = 'LED_${paymentId}_${alloc.invoiceId}';
        tx.create(
          FirebaseConstants.customerLedgerEntries,
          ledgerTransactionId,
          {
            'transactionId': ledgerTransactionId,
            'businessId': businessId,
            'tenantId': tenantId,
            'customerId': customerId,
            'outletId': collectedAtOutletId, // Collecting outlet retained
            'originalOutletId': alloc.originalOutletId, // Selling outlet retained
            'invoiceId': alloc.invoiceId,
            'transactionType': CustomerLedgerEntryModel.typePayment,
            'amountPaise': alloc.allocatedPaise,
            'debitPaise': 0,
            'creditPaise': alloc.allocatedPaise,
            'advanceCreditPaise': 0,
            'paymentId': paymentId,
            'createdAt': nowIso,
            'createdBy': actorUid,
            'status': 'POSTED',
            'immutable': true,
          },
        );
      }

      // 6. Record advance ledger entry if excess payment
      if (excessAdvance > 0) {
        final advanceLedgerId = 'LED_${paymentId}_ADVANCE';
        tx.create(
          FirebaseConstants.customerLedgerEntries,
          advanceLedgerId,
          {
            'transactionId': advanceLedgerId,
            'businessId': businessId,
            'tenantId': tenantId,
            'customerId': customerId,
            'outletId': collectedAtOutletId,
            'transactionType': CustomerLedgerEntryModel.typePayment,
            'amountPaise': excessAdvance,
            'debitPaise': 0,
            'creditPaise': 0,
            'advanceCreditPaise': excessAdvance,
            'entryType': 'OVERPAYMENT_ADVANCE',
            'paymentId': paymentId,
            'createdAt': nowIso,
            'createdBy': actorUid,
            'status': 'POSTED',
            'immutable': true,
          },
        );
      }

      // 7. Update business customer master balances
      final currentCustomerDue = _int(customerDoc.fields['duePaise']);
      final currentCustomerAdvance = _int(customerDoc.fields['advancePaise']);
      final nextDue = (currentCustomerDue - totalAllocated).clamp(0, 1 << 50);
      final nextAdvance = currentCustomerAdvance + excessAdvance;

      tx.update(
        FirebaseConstants.customers,
        customerId,
        {
          'duePaise': nextDue,
          'advancePaise': nextAdvance,
          'updatedAt': nowIso,
        },
        updateTime: customerDoc.updateTime,
      );

      // 8. Create parent payment record
      final paymentRecord = CustomerPaymentRecord(
        paymentId: paymentId,
        businessId: businessId,
        tenantId: tenantId,
        customerId: customerId,
        collectedAtOutletId: collectedAtOutletId,
        amountPaise: amountPaise,
        paymentMethod: paymentMethod,
        receivedBy: actorUid,
        status: 'POSTED',
        allocations: allocationsToPost,
        excessAdvancePaise: excessAdvance,
        notes: notes,
        idempotencyKey: idempotencyKey,
        createdAt: now,
      );

      tx.create(
        FirebaseConstants.payments,
        paymentId,
        paymentRecord.toData(),
      );

      // 9. Financial reconciliation & audit log
      final auditId = 'FIN_PAY_$paymentId';
      tx.create(FirebaseConstants.financialTransactions, auditId, {
        'transactionId': auditId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': collectedAtOutletId,
        'transactionType': 'CUSTOMER_PAYMENT',
        'amountPaise': amountPaise,
        'paymentMode': paymentMethod,
        'referenceType': 'PAYMENT',
        'referenceId': paymentId,
        'customerId': customerId,
        'createdBy': actorUid,
        'createdAt': nowIso,
        'status': 'POSTED',
      });

      return paymentRecord;
    }, idToken: token);
  }

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  static String _formatMoney(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
}

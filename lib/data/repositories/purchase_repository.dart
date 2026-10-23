import 'dart:convert';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../local/local_data_source.dart';
import '../models/product_variant_model.dart';
import '../models/inventory_batch_movement_model.dart';
import '../models/purchase_bill_model.dart';
import '../models/purchase_correction_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';
import '../services/offline_firestore_service.dart';
import 'supplier_repository.dart';
import 'inventory_batch_movement_repository.dart';

class PurchaseRepository {
  PurchaseRepository(this.firestore, this.suppliers, this.transactions)
    : batchMovementRepository = InventoryBatchMovementRepository(firestore);
  final FirestoreDataService firestore;
  final SupplierRepository suppliers;
  final FirestoreTransactionService transactions;
  final InventoryBatchMovementRepository batchMovementRepository;

  FirestoreTransactionService get serverTransactions {
    if (transactions is OfflineFirestoreService) {
      return (transactions as OfflineFirestoreService).serverTransactions;
    }
    if (firestore is OfflineFirestoreService) {
      return (firestore as OfflineFirestoreService).serverTransactions;
    }
    return transactions;
  }

  Future<List<ProductVariantModel>> getProductsForBusiness(
    String businessId,
    String token, {
    String? tenantId,
    String? outletId,
  }) async {
    final variants = await firestore.queryEqual(
      FirebaseConstants.productVariants,
      'businessId',
      businessId,
      idToken: token,
    );
    final results = variants.isNotEmpty
        ? variants
              .map(_product)
              .where(
                (item) =>
                    item.businessId == businessId &&
                    item.status.toUpperCase() == 'ACTIVE',
              )
              .toList()
        : (await firestore.queryEqual(
                FirebaseConstants.products,
                'businessId',
                businessId,
                idToken: token,
              ))
              .map(_product)
              .where(
                (item) =>
                    item.businessId == businessId &&
                    item.status.toUpperCase() == 'ACTIVE',
              )
              .toList();
    if (outletId == null) return results;
    final placements = await firestore.queryDocuments(
      collection: FirebaseConstants.outletProducts,
      filters: [
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        if (tenantId != null) FirestoreFilter('tenantId', 'EQUAL', tenantId),
      ],
      idToken: token,
    );
    final allowed = <String, Set<String>?>{};
    for (final document in placements) {
      final fields = FirestoreRestService.decodeFields(document['fields']);
      if (fields['status'] != 'ACTIVE' || fields['isActive'] == false) continue;
      final productId = fields['productId'] as String?;
      if (productId == null) continue;
      final rawVariants = fields['variantIds'];
      allowed[productId] = rawVariants is List
          ? rawVariants.map((value) => value.toString()).toSet()
          : null;
    }
    return results.where((variant) {
      final placement = allowed[variant.productId];
      return allowed.containsKey(variant.productId) &&
          (placement == null || placement.contains(variant.variantId));
    }).toList();
  }

  Future<List<PurchaseBillModel>> getBills({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.purchaseBills,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    return docs
        .map(_bill)
        .where(
          (bill) =>
              bill.tenantId == tenantId &&
              bill.businessId == businessId &&
              bill.outletId == outletId,
        )
        .toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  }

  Future<List<PurchaseCorrectionModel>> getCorrections({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String purchaseId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.purchaseCorrections,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        FirestoreFilter('purchaseId', 'EQUAL', purchaseId),
      ],
      idToken: token,
    );
    return docs
        .map(
          (doc) => PurchaseCorrectionModel.fromData(
            (doc['name'] as String? ?? '').split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .toList()
      ..sort((a, b) => a.correctionNumber.compareTo(b.correctionNumber));
  }

  Future<List<Map<String, dynamic>>> getPaymentHistory({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String purchaseId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.supplierPayments,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        FirestoreFilter('purchaseBillId', 'EQUAL', purchaseId),
      ],
      idToken: token,
    );
    final rows = docs
        .map(
          (doc) => {
            'paymentId': (doc['name'] as String? ?? '').split('/').last,
            ...FirestoreRestService.decodeFields(doc['fields']),
          },
        )
        .toList();
    rows.sort(
      (a, b) => (a['paymentDate'] as DateTime? ?? DateTime(1970)).compareTo(
        b['paymentDate'] as DateTime? ?? DateTime(1970),
      ),
    );
    return rows;
  }

  Future<Map<String, int>> getPaymentReleasePreview({
    required String tenantId,
    required String businessId,
    required String purchaseId,
    required String supplierBusinessId,
    required String token,
  }) async {
    final allocations = await firestore.queryDocuments(
      collection: FirebaseConstants.paymentAllocations,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('purchaseBillId', 'EQUAL', purchaseId),
      ],
      idToken: token,
    );
    final allocatedAmount = allocations.fold<int>(
      0,
      (sum, row) =>
          sum +
          ((FirestoreRestService.decodeFields(row['fields'])['allocatedAmount']
                      as num?)
                  ?.toInt() ??
              0),
    );
    final response = await firestore.getDocument(
      FirebaseConstants.supplierBalances,
      supplierBusinessId,
      idToken: token,
    );
    final balance = FirestoreRestService.decodeFields(response['fields']);
    return {
      'allocatedAmount': allocatedAmount,
      'unallocatedAdvance':
          (balance['unallocatedAdvance'] as num?)?.toInt() ?? 0,
    };
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  /// Local-first eligibility/impact facts for the advanced correction form.
  /// Quantity can be edited only when the receipt baseline, correction events,
  /// and current batch balance reconcile from the exact batch movement ledger.
  Future<Map<String, Map<String, dynamic>>> getAdvancedCorrectionContext({
    required String tenantId,
    required String businessId,
    required String outletId,
    required PurchaseBillModel bill,
    required String token,
  }) async {
    final result = <String, Map<String, dynamic>>{};
    for (final item in bill.items) {
      final batchId = 'BATCH_${bill.purchaseBillId}_${item.goodsReceiptItemId}';
      final batchResponse = await firestore.getDocument(
        FirebaseConstants.inventoryBatches,
        batchId,
        idToken: token,
      );
      final batchFields = FirestoreRestService.decodeFields(
        batchResponse['fields'],
      );
      final movementDocs = await firestore.queryDocuments(
        collection: FirebaseConstants.inventoryBatchMovements,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('outletId', 'EQUAL', outletId),
          FirestoreFilter('batchId', 'EQUAL', batchId),
        ],
        idToken: token,
      );
      final movements = movementDocs
          .map((doc) => FirestoreRestService.decodeFields(doc['fields']))
          .where((m) => m['status'] == 'POSTED' && m['isDeleted'] != true)
          .toList();
      final receiptIds = bill.purchaseBillId == ''
          ? const <String>[]
          : <String>[bill.purchaseBillId];
      final grnId = receiptIds.isEmpty ? null : 'AUTO_GRN_${receiptIds.first}';
      final grnItemId = grnId == null
          ? null
          : '${grnId}_${item.goodsReceiptItemId}';
      final receiptBase = movements
          .where(
            (m) =>
                m['movementType'] == 'PURCHASE_RECEIPT' &&
                m['direction'] == 'IN' &&
                m['referenceType'] == 'GOODS_RECEIPT' &&
                m['referenceLineId'] == grnItemId,
          )
          .fold<int>(
            0,
            (sum, m) => sum + ((m['quantity'] as num?)?.toInt() ?? 0),
          );
      final correctionIn = movements
          .where(
            (m) =>
                m['movementType'] == 'PURCHASE_CORRECTION_IN' &&
                m['direction'] == 'IN',
          )
          .fold<int>(
            0,
            (sum, m) => sum + ((m['quantity'] as num?)?.toInt() ?? 0),
          );
      final correctionOut = movements
          .where(
            (m) =>
                m['movementType'] == 'PURCHASE_CORRECTION_OUT' &&
                m['direction'] == 'OUT',
          )
          .fold<int>(
            0,
            (sum, m) => sum + ((m['quantity'] as num?)?.toInt() ?? 0),
          );
      final available = (batchFields['availableQty'] as num?)?.toInt() ?? 0;
      final received = (batchFields['receivedQty'] as num?)?.toInt() ?? 0;
      final derived = movements.fold<int>(0, (sum, m) {
        final quantity = (m['quantity'] as num?)?.toInt() ?? 0;
        if (m['direction'] == 'IN') return sum + quantity;
        if (m['direction'] == 'OUT') return sum - quantity;
        return sum;
      });
      final consumed = movements
          .where(
            (m) =>
                m['direction'] == 'OUT' &&
                const {
                  'SALE',
                  'PURCHASE_RETURN',
                  'TRANSFER_OUT',
                  'ADJUSTMENT_OUT',
                }.contains(m['movementType']),
          )
          .fold<int>(
            0,
            (sum, m) => sum + ((m['quantity'] as num?)?.toInt() ?? 0),
          );
      final covered =
          batchFields['tenantId'] == tenantId &&
          batchFields['businessId'] == businessId &&
          batchFields['outletId'] == outletId &&
          batchFields['variantId'] == item.variantId &&
          batchFields['purchaseId'] == bill.purchaseBillId &&
          batchFields['purchaseItemId'] == item.goodsReceiptItemId &&
          batchFields['internalBatchNo'] == item.internalBatchNo &&
          receiptBase > 0 &&
          receiptBase + correctionIn - correctionOut == received &&
          derived == available &&
          available >= 0;
      final stock = await firestore.getDocument(
        FirebaseConstants.stockBalances,
        stockBalanceId(tenantId, outletId, item.variantId),
        idToken: token,
      );
      final stockFields = FirestoreRestService.decodeFields(stock['fields']);
      final stockScoped =
          stockFields['tenantId'] == tenantId &&
          stockFields['businessId'] == businessId &&
          stockFields['outletId'] == outletId &&
          stockFields['variantId'] == item.variantId;
      result[item.goodsReceiptItemId] = {
        'batchId': batchId,
        'verified': covered,
        'blockedReason': covered
            ? null
            : 'This batch lacks complete verified movement-ledger coverage.',
        'receivedBaseQuantity': received,
        'consumedBaseQuantity': consumed,
        'availableBaseQuantity': available,
        'derivedAvailableBaseQuantity': derived,
        'stockQuantityOnHand': stockScoped
            ? (stockFields['quantityOnHand'] as num?)?.toInt() ?? 0
            : 0,
      };
    }
    return result;
  }

  Future<PurchaseBillModel> createDraft({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    DateTime? purchaseDate,
    required String purchaseType,
    required String placeOfSupplyStateCode,
    required String businessStateCode,
    required int discountAmount,
    required int chargesAmount,
    required int roundOff,
    required List<PurchaseBillItemModel> items,
    required String createdBy,
    required String token,
  }) async {
    if (items.isEmpty || supplierInvoiceNumber.trim().isEmpty) {
      throw const AppException(
        'Add at least one item and enter the supplier invoice number.',
      );
    }
    if (!const {'DIRECT', 'AGAINST_PO', 'AGAINST_GRN'}.contains(purchaseType)) {
      throw const AppException('Select a valid purchase type.');
    }
    final supplierBusiness = await suppliers.getSupplierBusiness(
      tenantId,
      businessId,
      supplierId,
      token,
    );
    if (!supplierBusiness.isActive) {
      throw const AppException('Select an active supplier for this business.');
    }
    final products = await getProductsForBusiness(
      businessId,
      token,
      tenantId: tenantId,
      outletId: outletId,
    );
    final productIds = products.map((product) => product.variantId).toSet();
    if (!items.every((item) => productIds.contains(item.variantId)) ||
        items.any((item) => item.quantity <= 0 || item.rate < 0)) {
      throw const AppException('A purchase item or quantity is invalid.');
    }
    final barcodeByVariant = <String, String?>{
      for (final variant in products)
        variant.variantId: variant.barcode?.trim().isNotEmpty == true
            ? variant.barcode!.trim()
            : null,
    };
    final batchDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.inventoryBatches,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    var nextBatch = 1;
    for (final doc in batchDocs) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      final parsed = int.tryParse(
        RegExp(r'^BAT-(\d+)$')
                .firstMatch(data['internalBatchNo'] as String? ?? '')
                ?.group(1) ??
            '',
      );
      if (parsed != null && parsed >= nextBatch) nextBatch = parsed + 1;
    }
    if (purchaseType != 'DIRECT') {
      throw const AppException(
        'Purchase orders and goods receipt entry are not configured yet. Use Direct purchase for now.',
      );
    }
    final associationDocs = await suppliers.getSupplierBusinessDocuments(
      tenantId,
      businessId,
      token,
    );
    final duplicate = associationDocs.any((document) {
      final fields = FirestoreRestService.decodeFields(document['fields']);
      return fields['tenantId'] == tenantId &&
          fields['supplierId'] == supplierId &&
          fields['supplierBusinessId'] == supplierBusiness.supplierBusinessId;
    });
    if (!duplicate)
      throw const AppException('Supplier is not linked to this business.');
    final existingDocs = await firestore.queryEqual(
      FirebaseConstants.purchaseBills,
      'supplierBusinessId',
      supplierBusiness.supplierBusinessId,
      idToken: token,
    );
    if (existingDocs.any((doc) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      return (fields['supplierInvoiceNumber'] as String?)
                  ?.trim()
                  .toLowerCase() ==
              supplierInvoiceNumber.trim().toLowerCase() &&
          fields['status'] != 'CANCELLED';
    })) {
      throw const AppException(
        'This supplier invoice number is already recorded.',
      );
    }

    final subtotal = items.fold<int>(
      0,
      (sum, item) => sum + item.taxableAmount,
    );
    if (discountAmount < 0 || discountAmount > subtotal || chargesAmount < 0) {
      throw const AppException(
        'Discount or charges are outside the allowed range.',
      );
    }
    final taxableAmount = subtotal - discountAmount;
    var tax = 0;
    var allocatedDiscount = 0;
    final normalizedItems = <PurchaseBillItemModel>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final itemDiscount = index == items.length - 1
          ? discountAmount - allocatedDiscount
          : subtotal == 0
          ? 0
          : _roundHalfUp(discountAmount * item.taxableAmount, subtotal);
      allocatedDiscount += itemDiscount;
      final lineTaxable = item.taxableAmount - itemDiscount;
      final lineTax = _roundHalfUp(lineTaxable * item.gstRateBps, 10000);
      tax += lineTax;
      normalizedItems.add(
        PurchaseBillItemModel(
          goodsReceiptItemId: item.goodsReceiptItemId,
          variantId: item.variantId,
          productName: item.productName,
          unitId: item.unitId,
          commercialUnitId: item.commercialUnitId,
          conversionFactor: item.conversionFactor,
          quantity: item.quantity,
          rate: item.rate,
          gstRateBps: item.gstRateBps,
          taxableAmount: lineTaxable,
          taxAmount: lineTax,
          hsnCode: item.hsnCode,
          mrp: item.mrp,
          sellingPrice: item.sellingPrice,
          productId:
              item.productId ??
              products
                  .where((p) => p.variantId == item.variantId)
                  .first
                  .productId,
          variantName:
              item.variantName ??
              products.where((p) => p.variantId == item.variantId).first.name,
          barcodeSnapshot: barcodeByVariant[item.variantId],
          internalBatchNo: 'BAT-${(nextBatch++).toString().padLeft(6, '0')}',
          supplierLotNo: item.supplierLotNo,
          manufacturingDate: item.manufacturingDate,
          expiryDate: item.expiryDate,
          storageType: item.storageType,
          storageLocationId: item.storageLocationId,
          rackId: item.rackId,
        ),
      );
    }
    final sameState =
        placeOfSupplyStateCode.trim().isNotEmpty &&
        placeOfSupplyStateCode.trim() == businessStateCode.trim();
    final cgst = sameState ? tax ~/ 2 : 0;
    final sgst = sameState ? tax - cgst : 0;
    final igst = sameState ? 0 : tax;
    final preRound = taxableAmount + tax + chargesAmount;
    final grandTotal = preRound + roundOff;
    if (grandTotal < 0)
      throw const AppException('Purchase bill total cannot be negative.');
    final now = DateTime.now().toUtc();
    final billId = IdGenerator.create('PB');
    final supplier = await firestore.getDocument(
      FirebaseConstants.suppliers,
      supplierId,
      idToken: token,
    );
    final supplierName =
        FirestoreRestService.decodeFields(supplier['fields'])['name']
            as String? ??
        '';
    final dueDate = invoiceDate.add(
      Duration(days: supplierBusiness.paymentTermsDays),
    );
    final fields = <String, dynamic>{
      'purchaseBillId': billId,
      'purchaseNumber': null,
      'tenantId': tenantId,
      'businessId': businessId,
      'outletId': outletId,
      'supplierId': supplierId,
      'supplierBusinessId': supplierBusiness.supplierBusinessId,
      'supplierName': supplierName,
      'supplierInvoiceNumber': supplierInvoiceNumber.trim(),
      'invoiceDate': invoiceDate.toUtc(),
      'purchaseDate': (purchaseDate ?? invoiceDate).toUtc(),
      'entryDate': now,
      'dueDate': dueDate.toUtc(),
      'purchaseOrderId': null,
      'goodsReceiptIds': <String>[],
      'autoGoodsReceiptId': null,
      'purchaseType': purchaseType,
      'taxType': sameState ? 'INTRA_STATE' : 'INTER_STATE',
      'placeOfSupplyStateCode': placeOfSupplyStateCode.trim(),
      'status': 'DRAFT',
      'subtotal': subtotal,
      'discountAmount': discountAmount,
      'taxableAmount': taxableAmount,
      'cgstAmount': cgst,
      'sgstAmount': sgst,
      'igstAmount': igst,
      'chargesAmount': chargesAmount,
      'roundOff': roundOff,
      'grandTotal': grandTotal,
      'paidAmount': 0,
      'outstandingAmount': grandTotal,
      'paymentStatus': 'UNPAID',
      'version': 1,
      'items': normalizedItems.map((item) => item.toData()).toList(),
      'createdBy': createdBy,
      'createdAt': now,
      'updatedBy': createdBy,
      'updatedAt': now,
    };
    late Map<String, dynamic> savedFields;
    final sequenceId = '${tenantId}_${businessId}_PURCHASE';
    final existingBills = await firestore.queryDocuments(
      collection: FirebaseConstants.purchaseBills,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    var highest = 0;
    for (final doc in existingBills) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      final match = RegExp(r'^PUR-(\d+)$')
          .firstMatch(data['purchaseNumber'] as String? ?? '');
      final number = int.tryParse(match?.group(1) ?? '') ?? 0;
      if (number > highest) highest = number;
    }
    await serverTransactions.runAtomicOperation((transaction) async {
      final sequence = await transaction.get(
        FirebaseConstants.documentSequences,
        sequenceId,
      );
      final next = sequence.exists
          ? ((sequence.fields['nextNumber'] as num?)?.toInt() ?? 1)
          : highest + 1;
      if (next < 1)
        throw const AppException('Invalid purchase number sequence.');
      final purchaseNumber = 'PUR-${next.toString().padLeft(6, '0')}';
      savedFields = {...fields, 'purchaseNumber': purchaseNumber};
      if (sequence.exists) {
        transaction.update(FirebaseConstants.documentSequences, sequenceId, {
          'tenantId': tenantId,
          'businessId': businessId,
          'sequenceType': 'PURCHASE',
          'prefix': 'PUR',
          'padding': 6,
          'nextNumber': next + 1,
          'updatedAt': now,
        }, updateTime: sequence.updateTime);
      } else {
        transaction.create(FirebaseConstants.documentSequences, sequenceId, {
          'tenantId': tenantId,
          'businessId': businessId,
          'sequenceType': 'PURCHASE',
          'prefix': 'PUR',
          'padding': 6,
          'nextNumber': next + 1,
          'createdAt': now,
          'updatedAt': now,
        });
      }
      transaction.create(FirebaseConstants.purchaseBills, billId, savedFields);
      for (final item in normalizedItems) {
        final barcode = barcodeByVariant[item.variantId];
        final itemId = item.goodsReceiptItemId;
        final detail = {
          ...item.toData(),
          'purchaseItemId': itemId,
          'purchaseId': billId,
          'purchaseBillId': billId,
          'supplierId': supplierId,
          'businessId': businessId,
          'outletId': outletId,
          'tenantId': tenantId,
          'createdAt': now,
        };
        transaction.create(FirebaseConstants.purchaseBillItems, itemId, detail);
        final batchId = 'BATCH_${billId}_$itemId';
        transaction.create(FirebaseConstants.inventoryBatches, batchId, {
          'batchId': batchId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'purchaseId': billId,
          'purchaseItemId': itemId,
          'supplierId': supplierId,
          'productId': item.productId,
          'variantId': item.variantId,
          'barcodeSnapshot': barcode,
          'barcode': barcode,
          'internalBatchNo': item.internalBatchNo,
          'supplierLotNo': item.supplierLotNo,
          'receivedQty': 0,
          'availableQty': 0,
          'purchaseRate': item.rate,
          'mrp': item.mrp,
          'sellingPrice': item.sellingPrice,
          'manufacturingDate': item.manufacturingDate,
          'expiryDate': item.expiryDate,
          'storageType': item.storageType,
          'storageLocationId': item.storageLocationId,
          'rackId': item.rackId,
          'receivedDate': now,
          'status': 'PENDING_RECEIPT',
          'isDeleted': false,
          'createdAt': now,
        });
      }
    }, idToken: token);

    if (firestore is OfflineFirestoreService) {
      final local = (firestore as OfflineFirestoreService).localDataSource;
      if (local != null) {
        try {
          await local.db.transaction((localTx) async {
            await LocalDataSource.put(
              localTx,
              FirebaseConstants.purchaseBills,
              {
                'remoteId': billId,
                'payloadJson': jsonEncode(
                  FirestoreRestService.encodeFields(savedFields),
                ),
                ...LocalDataSource.scopeColumns(savedFields),
                'syncStatus': 'SYNCED',
                'localUpdatedAt': LocalDataSource.now(),
                'isDeleted': 0,
              },
            );
          });
        } catch (_) {}
      }
    }
    return PurchaseBillModel.fromData(billId, savedFields);
  }

  Future<PurchaseBillModel> approveDirectBill({
    required String tenantId,
    required String billId,
    required String userId,
    required String token,
  }) async {
    Map<String, dynamic>? localMerged;
    final result = await serverTransactions.runAtomicOperation((transaction) async {
    var billDoc = await transaction.get(
      FirebaseConstants.purchaseBills,
      billId,
    );
    if (!billDoc.exists && firestore is OfflineFirestoreService) {
      final local = (firestore as OfflineFirestoreService).localDataSource;
      if (local != null) {
        try {
          final localDoc = await local.row(FirebaseConstants.purchaseBills, billId);
          if (localDoc != null && localDoc['isDeleted'] != 1) {
            final payload = jsonDecode(localDoc['payloadJson'] as String) as Map<String, dynamic>;
            final fields = FirestoreRestService.decodeFields(payload);
            transaction.create(FirebaseConstants.purchaseBills, billId, fields);
            billDoc = FirestoreTransactionDocument(
              id: billId,
              exists: true,
              fields: fields,
              updateTime: null,
            );
          }
        } catch (_) {}
      }
    }
    if (!billDoc.exists)
      throw const AppException('Purchase bill was not found.');
    final bill = PurchaseBillModel.fromData(billId, billDoc.fields);
    if (bill.tenantId != tenantId)
      throw const AppException('Purchase bill is outside this tenant.');
    if (bill.status == 'APPROVED') return bill;
    if (bill.status != 'DRAFT' || bill.purchaseType != 'DIRECT') {
      throw const AppException('Only direct draft bills can be approved here.');
    }
    final supplierDoc = await transaction.get(
      FirebaseConstants.suppliers,
      bill.supplierId,
    );
    final supplierBusinessDoc = await transaction.get(
      FirebaseConstants.supplierBusinesses,
      bill.supplierBusinessId,
    );
    if (!supplierDoc.exists ||
        !supplierBusinessDoc.exists ||
        supplierDoc.fields['tenantId'] != tenantId ||
        supplierBusinessDoc.fields['businessId'] != bill.businessId ||
        supplierBusinessDoc.fields['status'] != 'ACTIVE') {
      throw const AppException(
        'Supplier access is no longer active for this business.',
      );
    }
    final supplierBalanceDoc = await transaction.get(
      FirebaseConstants.supplierBalances,
      bill.supplierBusinessId,
    );
    final now = DateTime.now().toUtc();
    final inventoryLines = _aggregateLines(bill.items);
    final stockDocs = <String, FirestoreTransactionDocument>{};
    for (final line in inventoryLines) {
      final id = stockBalanceId(tenantId, bill.outletId, line.variantId);
      stockDocs[id] = await transaction.get(
        FirebaseConstants.stockBalances,
        id,
      );
    }
    final grnId = 'AUTO_GRN_${bill.purchaseBillId}';
    final grnDoc = await transaction.get(
      FirebaseConstants.goodsReceipts,
      grnId,
    );
    if (grnDoc.exists)
      throw const AppException(
        'Auto goods receipt exists without an approved purchase bill. Contact support.',
      );
    transaction.create(FirebaseConstants.goodsReceipts, grnId, {
      'goodsReceiptId': grnId,
      'tenantId': tenantId,
      'businessId': bill.businessId,
      'outletId': bill.outletId,
      'supplierId': bill.supplierId,
      'supplierBusinessId': bill.supplierBusinessId,
      'purchaseBillId': bill.purchaseBillId,
      'source': 'AUTO_FROM_DIRECT_BILL',
      'status': 'APPROVED',
      'receivedAt': bill.invoiceDate,
      'createdBy': userId,
      'createdAt': now,
      'approvedBy': userId,
      'approvedAt': now,
    });

    final incomingByVariant = <String, int>{};
    final costByVariant = <String, int>{};
    final supplierProductLines = <String, PurchaseBillItemModel>{};
    for (final item in bill.items) {
      final baseQuantity = _roundHalfUp(
        item.quantity * item.conversionFactor,
        1000,
      );
      final lineCost =
          item.taxableAmount +
          _proportionalShare(
            bill.chargesAmount,
            item.taxableAmount,
            bill.taxableAmount,
          );
      incomingByVariant.update(
        item.variantId,
        (v) => v + baseQuantity,
        ifAbsent: () => baseQuantity,
      );
      costByVariant.update(
        item.variantId,
        (v) => v + lineCost,
        ifAbsent: () => lineCost,
      );
      final itemId = item.goodsReceiptItemId;
      final grnItemId = '${grnId}_$itemId';
      transaction.create(FirebaseConstants.goodsReceiptItems, grnItemId, {
        'goodsReceiptItemId': grnItemId,
        'tenantId': tenantId,
        'businessId': bill.businessId,
        'outletId': bill.outletId,
        'goodsReceiptId': grnId,
        'purchaseBillId': bill.purchaseBillId,
        'variantId': item.variantId,
        'productId': item.productId,
        'barcode': item.barcodeSnapshot,
        'barcodeSnapshot': item.barcodeSnapshot,
        'internalBatchNo': item.internalBatchNo,
        'supplierLotNo': item.supplierLotNo,
        'manufacturingDate': item.manufacturingDate,
        'expiryDate': item.expiryDate,
        'storageType': item.storageType ?? 'OUTLET',
        'storageLocationId': item.storageLocationId ?? bill.outletId,
        'rackId': item.rackId,
        'unitId': item.unitId,
        if (item.commercialUnitId != null)
          'commercialUnitId': item.commercialUnitId,
        if (item.commercialUnitId != null) 'commercialQuantity': item.quantity,
        'conversionFactor': item.conversionFactor,
        'orderedQuantity': item.quantity,
        'receivedQuantity': item.quantity,
        'acceptedQuantity': item.quantity,
        'rejectedQuantity': 0,
        'rejectionReason': null,
        'rejectionValue': 0,
        'rejectionDisposition': 'RECORD_ONLY',
        'provisionalRate': item.rate,
        'billedBaseQuantity': baseQuantity,
      });
      final batchId = 'BATCH_${bill.purchaseBillId}_$itemId';
      final batchDoc = await transaction.get(
        FirebaseConstants.inventoryBatches,
        batchId,
      );
      if (batchDoc.exists) {
        transaction.update(FirebaseConstants.inventoryBatches, batchId, {
          'receivedQty': baseQuantity,
          'availableQty': baseQuantity,
          'receivedDate': now,
          'status': 'AVAILABLE',
          'goodsReceiptId': grnId,
          'updatedAt': now,
        }, updateTime: batchDoc.updateTime);
      }
      transaction.create(
        FirebaseConstants.inventoryTransactions,
        'PURCHASE_RECEIPT_${bill.purchaseBillId}_$itemId',
        {
          'inventoryTransactionId':
              'PURCHASE_RECEIPT_${bill.purchaseBillId}_$itemId',
          'tenantId': tenantId,
          'businessId': bill.businessId,
          'outletId': bill.outletId,
          'locationType': item.storageType ?? 'OUTLET',
          'locationId': item.storageLocationId ?? bill.outletId,
          'rackId': item.rackId,
          'productId': item.productId,
          'variantId': item.variantId,
          'transactionType': 'PURCHASE_RECEIPT',
          'sourceType': 'GOODS_RECEIPT',
          'sourceId': grnId,
          'sourceItemId': grnItemId,
          'direction': 'IN',
          'quantity': baseQuantity,
          'unitId': item.unitId,
          if (item.commercialUnitId != null)
            'commercialUnitId': item.commercialUnitId,
          if (item.commercialUnitId != null)
            'commercialQuantity': item.quantity,
          'conversionFactor': item.conversionFactor,
          'baseQuantity': baseQuantity,
          'unitCost': lineCost,
          'totalCost': lineCost,
          'isReversal': false,
          'reversalOfId': null,
          'createdBy': userId,
          'createdAt': now,
        },
      );
      await batchMovementRepository.record(
        transaction,
        InventoryBatchMovementModel(
          movementId:
              'BATCH_MOVEMENT_PURCHASE_RECEIPT_${bill.purchaseBillId}_$itemId',
          tenantId: tenantId,
          businessId: bill.businessId,
          outletId: bill.outletId,
          batchId: batchId,
          productId: item.productId,
          variantId: item.variantId,
          movementType: 'PURCHASE_RECEIPT',
          quantity: baseQuantity,
          direction: 'IN',
          referenceType: 'GOODS_RECEIPT',
          referenceId: grnId,
          referenceLineId: grnItemId,
          reason: 'Direct purchase receipt posted.',
          createdByUid: userId,
          occurredAt: now,
          status: 'POSTED',
          createdAt: now,
          updatedAt: now,
        ),
        token: token,
      );
      supplierProductLines[item.variantId] = item;
    }

    for (final entry in supplierProductLines.entries) {
      final item = entry.value;
      final supplierProductId = '${bill.supplierBusinessId}_${entry.key}';
      final supplierProduct = await transaction.get(
        FirebaseConstants.supplierProducts,
        supplierProductId,
      );
      final supplierProductFields = {
        'supplierProductId': supplierProductId,
        'tenantId': tenantId,
        'businessId': bill.businessId,
        'supplierBusinessId': bill.supplierBusinessId,
        'variantId': item.variantId,
        'lastCost': item.rate,
        'lastPurchaseDate': bill.invoiceDate,
        'status': 'ACTIVE',
        'updatedBy': userId,
        'updatedAt': now,
      };
      if (supplierProduct.exists) {
        transaction.update(
          FirebaseConstants.supplierProducts,
          supplierProductId,
          supplierProductFields,
          updateTime: supplierProduct.updateTime,
        );
      } else {
        transaction.create(
          FirebaseConstants.supplierProducts,
          supplierProductId,
          {
            ...supplierProductFields,
            'supplierSku': null,
            'leadTimeDays': 0,
            'preferred': false,
            'createdBy': userId,
            'createdAt': now,
          },
        );
      }

      final variantDoc = await transaction.get(
        FirebaseConstants.productVariants,
        item.variantId,
      );
      final variantPricingUpdates = <String, dynamic>{
        if (item.sellingPrice != null && item.sellingPrice! > 0)
          'sellingPrice': item.sellingPrice,
        if (item.mrp != null && item.mrp! > 0) 'mrp': item.mrp,
        if (item.rate > 0) 'purchaseRate': item.rate,
      };
      if (variantPricingUpdates.isNotEmpty) {
        variantPricingUpdates['updatedAt'] = now;
        variantPricingUpdates['updatedBy'] = userId;
        if (variantDoc.exists) {
          transaction.update(
            FirebaseConstants.productVariants,
            item.variantId,
            variantPricingUpdates,
            updateTime: variantDoc.updateTime,
          );
        } else {
          final productDoc = await transaction.get(
            FirebaseConstants.products,
            item.variantId,
          );
          if (productDoc.exists) {
            transaction.update(
              FirebaseConstants.products,
              item.variantId,
              variantPricingUpdates,
              updateTime: productDoc.updateTime,
            );
          }
        }
      }
    }

    for (final line in inventoryLines) {
      final id = stockBalanceId(tenantId, bill.outletId, line.variantId);
      final stock = stockDocs[id]!;
      final oldQuantity =
          (stock.fields['quantityOnHand'] as num?)?.toInt() ?? 0;
      final oldValue = (stock.fields['totalValue'] as num?)?.toInt() ?? 0;
      final quantity = incomingByVariant[line.variantId] ?? 0;
      final value = costByVariant[line.variantId] ?? 0;
      final nextQuantity = oldQuantity + quantity;
      final nextValue = oldValue + value;
      final fields = {
        'tenantId': tenantId,
        'businessId': bill.businessId,
        'outletId': bill.outletId,
        'locationType': 'OUTLET',
        'locationId': bill.outletId,
        'rackId': null,
        'variantId': line.variantId,
        'quantityOnHand': nextQuantity,
        'averageCost': nextQuantity == 0
            ? 0
            : _roundHalfUp(nextValue * 1000, nextQuantity),
        'totalValue': nextValue,
        'lastInventoryTransactionId':
            'PURCHASE_RECEIPT_${bill.purchaseBillId}_${line.goodsReceiptItemId}',
        'updatedAt': now,
      };
      if (stock.exists) {
        transaction.update(
          FirebaseConstants.stockBalances,
          id,
          fields,
          updateTime: stock.updateTime,
        );
      } else {
        transaction.create(FirebaseConstants.stockBalances, id, fields);
      }
    }

    final ledgerId = 'PURCHASE_BILL_${bill.purchaseBillId}_1';
    transaction.create(FirebaseConstants.supplierLedgerEntries, ledgerId, {
      'ledgerEntryId': ledgerId,
      'tenantId': tenantId,
      'businessId': bill.businessId,
      'outletId': bill.outletId,
      'supplierId': bill.supplierId,
      'supplierBusinessId': bill.supplierBusinessId,
      'entryType': 'PURCHASE_BILL',
      'referenceType': 'PURCHASE_BILL',
      'referenceId': bill.purchaseBillId,
      'debit': 0,
      'credit': bill.grandTotal,
      'isReversal': false,
      'reversalOfId': null,
      'transactionDate': bill.invoiceDate,
      'createdBy': userId,
      'createdAt': now,
    });
    final oldPayable =
        (supplierBalanceDoc.fields['totalPayable'] as num?)?.toInt() ?? 0;
    final balanceFields = {
      'tenantId': tenantId,
      'businessId': bill.businessId,
      'supplierBusinessId': bill.supplierBusinessId,
      'totalPayable': oldPayable + bill.grandTotal,
      'unallocatedAdvance':
          (supplierBalanceDoc.fields['unallocatedAdvance'] as num?)?.toInt() ??
          0,
      'unallocatedReturnCredit':
          (supplierBalanceDoc.fields['unallocatedReturnCredit'] as num?)
              ?.toInt() ??
          0,
      'unallocatedSupplierCredit':
          (supplierBalanceDoc.fields['unallocatedSupplierCredit'] as num?)
              ?.toInt() ??
          0,
      'lastLedgerEntryId': ledgerId,
      'updatedAt': now,
    };
    if (supplierBalanceDoc.exists) {
      transaction.update(
        FirebaseConstants.supplierBalances,
        bill.supplierBusinessId,
        balanceFields,
        updateTime: supplierBalanceDoc.updateTime,
      );
    } else {
      transaction.create(
        FirebaseConstants.supplierBalances,
        bill.supplierBusinessId,
        balanceFields,
      );
    }
    final effectiveDue = (bill.outstandingAmount > 0
        ? bill.outstandingAmount
        : (bill.grandTotal - bill.paidAmount)).clamp(0, bill.grandTotal);
    final approvedFields = {
      'status': 'APPROVED',
      'outstandingAmount': effectiveDue,
      'paymentStatus':
          bill.paidAmount >= bill.grandTotal && bill.grandTotal > 0
              ? 'PAID'
              : (bill.paidAmount > 0 ? 'PARTIAL' : 'UNPAID'),
      'autoGoodsReceiptId': grnId,
      'goodsReceiptIds': [grnId],
      'approvedBy': userId,
      'approvedAt': now,
      'updatedBy': userId,
      'updatedAt': now,
      'version': bill.version + 1,
    };
    transaction.update(
      FirebaseConstants.purchaseBills,
      billId,
      approvedFields,
      updateTime: billDoc.updateTime,
    );
    localMerged = {
      ...billDoc.fields,
      ...approvedFields,
    };
    return PurchaseBillModel.fromData(billId, localMerged!);
  }, idToken: token);

  if (localMerged != null && firestore is OfflineFirestoreService) {
    final local = (firestore as OfflineFirestoreService).localDataSource;
    if (local != null) {
      try {
        await local.db.transaction((localTx) async {
          await LocalDataSource.put(
            localTx,
            FirebaseConstants.purchaseBills,
            {
              'remoteId': billId,
              'payloadJson': jsonEncode(
                FirestoreRestService.encodeFields(localMerged!),
              ),
              ...LocalDataSource.scopeColumns(localMerged!),
              'syncStatus': 'SYNCED',
              'localUpdatedAt': LocalDataSource.now(),
              'isDeleted': 0,
            },
          );
        });
      } catch (_) {}
    }
  }
  return result;
}

  /// Updates an existing DRAFT in place. Existing line and batch identifiers
  /// are retained; removed draft lines are soft-deleted for sync/audit safety.
  Future<PurchaseBillModel> updateDraft({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String billId,
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime purchaseDate,
    required String placeOfSupplyStateCode,
    required String businessStateCode,
    required int discountAmount,
    required int chargesAmount,
    required int roundOff,
    required List<PurchaseBillItemModel> items,
    required String updatedBy,
    required String token,
  }) async {
    final current = await firestore.getDocument(
      FirebaseConstants.purchaseBills,
      billId,
      idToken: token,
    );
    final currentFields = FirestoreRestService.decodeFields(current['fields']);
    if (currentFields['tenantId'] != tenantId ||
        currentFields['businessId'] != businessId ||
        currentFields['outletId'] != outletId ||
        currentFields['status'] != 'DRAFT') {
      throw const AppException(
        'Only this outletâ€™s draft purchase can be edited.',
      );
    }
    final supplier = await firestore.getDocument(
      FirebaseConstants.suppliers,
      supplierId,
      idToken: token,
    );
    final supplierName =
        FirestoreRestService.decodeFields(supplier['fields'])['name']
            as String? ??
        '';
    final supplierBusiness = await suppliers.getSupplierBusiness(
      tenantId,
      businessId,
      supplierId,
      token,
    );
    if (!supplierBusiness.isActive) {
      throw const AppException('Select an active supplier for this business.');
    }
    final otherBills = await firestore.queryEqual(
      FirebaseConstants.purchaseBills,
      'supplierBusinessId',
      supplierBusiness.supplierBusinessId,
      idToken: token,
    );
    if (otherBills.any((doc) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      return (doc['name'] as String).split('/').last != billId &&
          data['status'] != 'CANCELLED' &&
          (data['supplierInvoiceNumber'] as String? ?? '')
                  .trim()
                  .toLowerCase() ==
              supplierInvoiceNumber.trim().toLowerCase();
    })) {
      throw const AppException(
        'This supplier invoice number is already recorded.',
      );
    }
    final products = await getProductsForBusiness(
      businessId,
      token,
      tenantId: tenantId,
      outletId: outletId,
    );
    final productsById = {for (final p in products) p.variantId: p};
    if (items.isEmpty ||
        items.any((i) => !productsById.containsKey(i.variantId))) {
      throw const AppException('A purchase item is invalid for this outlet.');
    }
    final oldBill = PurchaseBillModel.fromData(billId, currentFields);
    final oldItems = {
      for (final item in oldBill.items) item.goodsReceiptItemId: item,
    };
    final batchDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.inventoryBatches,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    var nextBatch = 1;
    for (final doc in batchDocs) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      final number = int.tryParse(
        RegExp(r'^BAT-(\d+)$')
                .firstMatch(data['internalBatchNo'] as String? ?? '')
                ?.group(1) ??
            '',
      );
      if (number != null && number >= nextBatch) nextBatch = number + 1;
    }
    final normalized = <PurchaseBillItemModel>[];
    for (final item in items) {
      final previous = oldItems[item.goodsReceiptItemId];
      if (previous != null && previous.variantId != item.variantId) {
        throw const AppException(
          'A saved draft line cannot change variant identity. Remove it and add a new line.',
        );
      }
      final variant = productsById[item.variantId]!;
      normalized.add(
        PurchaseBillItemModel(
          goodsReceiptItemId: item.goodsReceiptItemId,
          variantId: item.variantId,
          productName: item.productName,
          unitId: item.unitId,
          commercialUnitId: item.commercialUnitId,
          conversionFactor: item.conversionFactor,
          quantity: item.quantity,
          rate: item.rate,
          gstRateBps: item.gstRateBps,
          taxableAmount: item.taxableAmount,
          taxAmount: item.taxAmount,
          hsnCode: item.hsnCode,
          mrp: item.mrp,
          sellingPrice: item.sellingPrice,
          productId: variant.productId,
          variantName: variant.name,
          barcodeSnapshot: previous?.barcodeSnapshot ?? variant.barcode,
          internalBatchNo:
              previous?.internalBatchNo ??
              item.internalBatchNo ??
              'BAT-${(nextBatch++).toString().padLeft(6, '0')}',
          supplierLotNo: item.supplierLotNo,
          manufacturingDate: item.manufacturingDate,
          expiryDate: item.expiryDate,
          storageType: item.storageType,
          storageLocationId: item.storageLocationId,
          rackId: item.rackId,
        ),
      );
    }
    final subtotal = items.fold<int>(
      0,
      (sum, item) => sum + item.taxableAmount,
    );
    if (discountAmount < 0 || discountAmount > subtotal || chargesAmount < 0) {
      throw const AppException(
        'Discount or charges are outside the allowed range.',
      );
    }
    final taxable = subtotal - discountAmount;
    var allocatedDiscount = 0;
    final discounted = <PurchaseBillItemModel>[];
    for (var i = 0; i < normalized.length; i++) {
      final item = normalized[i];
      final itemDiscount = i == normalized.length - 1
          ? discountAmount - allocatedDiscount
          : subtotal == 0
          ? 0
          : _roundHalfUp(discountAmount * item.taxableAmount, subtotal);
      allocatedDiscount += itemDiscount;
      final lineTaxable = item.taxableAmount - itemDiscount;
      final lineTax = _roundHalfUp(lineTaxable * item.gstRateBps, 10000);
      discounted.add(
        PurchaseBillItemModel(
          goodsReceiptItemId: item.goodsReceiptItemId,
          variantId: item.variantId,
          productName: item.productName,
          unitId: item.unitId,
          commercialUnitId: item.commercialUnitId,
          conversionFactor: item.conversionFactor,
          quantity: item.quantity,
          rate: item.rate,
          gstRateBps: item.gstRateBps,
          taxableAmount: lineTaxable,
          taxAmount: lineTax,
          hsnCode: item.hsnCode,
          mrp: item.mrp,
          sellingPrice: item.sellingPrice,
          productId: item.productId,
          variantName: item.variantName,
          barcodeSnapshot: item.barcodeSnapshot,
          internalBatchNo: item.internalBatchNo,
          supplierLotNo: item.supplierLotNo,
          manufacturingDate: item.manufacturingDate,
          expiryDate: item.expiryDate,
          storageType: item.storageType,
          storageLocationId: item.storageLocationId,
          rackId: item.rackId,
        ),
      );
    }
    normalized
      ..clear()
      ..addAll(discounted);
    final tax = normalized.fold<int>(0, (sum, item) => sum + item.taxAmount);
    final sameState =
        placeOfSupplyStateCode.trim().isNotEmpty &&
        placeOfSupplyStateCode.trim() == businessStateCode.trim();
    final cgst = sameState ? tax ~/ 2 : 0;
    final sgst = sameState ? tax - cgst : 0;
    final grandTotal = taxable + tax + chargesAmount + roundOff;
    if (grandTotal < oldBill.paidAmount) {
      throw const AppException(
        'Draft total cannot be less than its recorded payment.',
      );
    }
    final now = DateTime.now().toUtc();
    final dueDays = supplierBusiness.paymentTermsDays;
    final dueDate = invoiceDate.add(Duration(days: dueDays));
    final savedItems = normalized.map((item) => item.toData()).toList();
    final updatedFields = <String, dynamic>{
      'supplierId': supplierId,
      'supplierBusinessId': supplierBusiness.supplierBusinessId,
      'supplierName': supplierName,
      'supplierInvoiceNumber': supplierInvoiceNumber.trim(),
      'invoiceDate': invoiceDate.toUtc(),
      'purchaseDate': purchaseDate.toUtc(),
      'dueDate': dueDate.toUtc(),
      'placeOfSupplyStateCode': placeOfSupplyStateCode.trim(),
      'taxType': sameState ? 'INTRA_STATE' : 'INTER_STATE',
      'subtotal': subtotal,
      'discountAmount': discountAmount,
      'taxableAmount': taxable,
      'cgstAmount': cgst,
      'sgstAmount': sgst,
      'igstAmount': sameState ? 0 : tax,
      'chargesAmount': chargesAmount,
      'roundOff': roundOff,
      'grandTotal': grandTotal,
      'paidAmount': oldBill.paidAmount,
      'outstandingAmount': grandTotal - oldBill.paidAmount,
      'paymentStatus': oldBill.paidAmount == 0 ? 'UNPAID' : 'PARTIAL',
      'items': savedItems,
      'updatedBy': updatedBy,
      'updatedAt': now,
      'version': oldBill.version + 1,
    };
    await serverTransactions.runAtomicOperation((tx) async {
      final billDoc = await tx.get(FirebaseConstants.purchaseBills, billId);
      if (!billDoc.exists ||
          billDoc.fields['status'] != 'DRAFT' ||
          billDoc.fields['version'] != oldBill.version) {
        throw const AppException('Draft changed. Reload it and try again.');
      }
      tx.update(
        FirebaseConstants.purchaseBills,
        billId,
        updatedFields,
        updateTime: billDoc.updateTime,
      );
      final keepIds = normalized.map((i) => i.goodsReceiptItemId).toSet();
      for (final old in oldBill.items) {
        final itemId = old.goodsReceiptItemId;
        final itemDoc = await tx.get(
          FirebaseConstants.purchaseBillItems,
          itemId,
        );
        final batchId = 'BATCH_${billId}_$itemId';
        final batchDoc = await tx.get(
          FirebaseConstants.inventoryBatches,
          batchId,
        );
        if (!keepIds.contains(itemId)) {
          if (itemDoc.exists)
            tx.update(FirebaseConstants.purchaseBillItems, itemId, {
              'status': 'DELETED',
              'isDeleted': true,
              'updatedAt': now,
            }, updateTime: itemDoc.updateTime);
          if (batchDoc.exists)
            tx.update(FirebaseConstants.inventoryBatches, batchId, {
              'status': 'DELETED',
              'isDeleted': true,
              'updatedAt': now,
            }, updateTime: batchDoc.updateTime);
        }
      }
      for (final item in normalized) {
        final itemId = item.goodsReceiptItemId;
        final itemDoc = await tx.get(
          FirebaseConstants.purchaseBillItems,
          itemId,
        );
        final itemFields = {
          ...item.toData(),
          'purchaseItemId': itemId,
          'purchaseId': billId,
          'purchaseBillId': billId,
          'supplierId': supplierId,
          'businessId': businessId,
          'outletId': outletId,
          'tenantId': tenantId,
          'updatedAt': now,
          'status': 'DRAFT',
          'isDeleted': false,
        };
        if (itemDoc.exists) {
          tx.update(
            FirebaseConstants.purchaseBillItems,
            itemId,
            itemFields,
            updateTime: itemDoc.updateTime,
          );
        } else {
          tx.create(FirebaseConstants.purchaseBillItems, itemId, {
            ...itemFields,
            'createdAt': now,
          });
        }
        final batchId = 'BATCH_${billId}_$itemId';
        final batchDoc = await tx.get(
          FirebaseConstants.inventoryBatches,
          batchId,
        );
        final batchFields = {
          'batchId': batchId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'purchaseId': billId,
          'purchaseItemId': itemId,
          'supplierId': supplierId,
          'productId': item.productId,
          'variantId': item.variantId,
          'barcodeSnapshot': item.barcodeSnapshot,
          'barcode': item.barcodeSnapshot,
          'internalBatchNo': item.internalBatchNo,
          'supplierLotNo': item.supplierLotNo,
          'receivedQty': 0,
          'availableQty': 0,
          'purchaseRate': item.rate,
          'mrp': item.mrp,
          'sellingPrice': item.sellingPrice,
          'manufacturingDate': item.manufacturingDate,
          'expiryDate': item.expiryDate,
          'storageType': item.storageType,
          'storageLocationId': item.storageLocationId,
          'rackId': item.rackId,
          'receivedDate': now,
          'status': 'PENDING_RECEIPT',
          'isDeleted': false,
          'updatedAt': now,
        };
        if (batchDoc.exists) {
          if (batchDoc.fields['status'] != 'PENDING_RECEIPT') {
            throw const AppException(
              'A draft batch was already received and cannot be replaced.',
            );
          }
          tx.update(
            FirebaseConstants.inventoryBatches,
            batchId,
            batchFields,
            updateTime: batchDoc.updateTime,
          );
        } else {
          tx.create(FirebaseConstants.inventoryBatches, batchId, {
            ...batchFields,
            'createdAt': now,
          });
        }
      }
    }, idToken: token);

    final merged = {
      ...currentFields,
      ...updatedFields,
    };
    if (firestore is OfflineFirestoreService) {
      final local = (firestore as OfflineFirestoreService).localDataSource;
      if (local != null) {
        try {
          await local.db.transaction((localTx) async {
            await LocalDataSource.put(
              localTx,
              FirebaseConstants.purchaseBills,
              {
                'remoteId': billId,
                'payloadJson': jsonEncode(
                  FirestoreRestService.encodeFields(merged),
                ),
                ...LocalDataSource.scopeColumns(merged),
                'syncStatus': 'SYNCED',
                'localUpdatedAt': LocalDataSource.now(),
                'isDeleted': 0,
              },
            );
          });
        } catch (_) {}
      }
    }
    return PurchaseBillModel.fromData(billId, merged);
  }

  /// Corrects an approved purchase using the local transactional snapshot and
  /// queues every changed document in the same SQLite/outbox batch.
  Future<PurchaseCorrectionModel> correctApprovedMetadata({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String billId,
    required String reason,
    required String correctedByUid,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime purchaseDate,
    required Map<String, Map<String, dynamic>> lineMetadata,
    required String token,
  }) async {
    if (reason.trim().isEmpty)
      throw const AppException('Enter a correction reason.');
    if (supplierInvoiceNumber.trim().isEmpty) {
      throw const AppException('Supplier invoice number is required.');
    }
    final current = await firestore.getDocument(
      FirebaseConstants.purchaseBills,
      billId,
      idToken: token,
    );
    final fields = FirestoreRestService.decodeFields(current['fields']);
    if (fields['tenantId'] != tenantId ||
        fields['businessId'] != businessId ||
        fields['outletId'] != outletId ||
        fields['status'] != 'APPROVED') {
      throw const AppException(
        'Only an approved purchase in this outlet can be corrected.',
      );
    }
    final bill = PurchaseBillModel.fromData(billId, fields);
    final allowedLineFields = {
      'supplierLotNo',
      'manufacturingDate',
      'expiryDate',
      'quantity',
      'rate',
      'gstRateBps',
      'mrp',
      'sellingPrice',
    };
    if (lineMetadata.values.any(
      (v) => v.keys.any((k) => !allowedLineFields.contains(k)),
    )) {
      throw const AppException(
        'This field requires the advanced correction workflow.',
      );
    }
    final duplicateBills = await firestore.queryEqual(
      FirebaseConstants.purchaseBills,
      'supplierBusinessId',
      bill.supplierBusinessId,
      idToken: token,
    );
    if (duplicateBills.any((doc) {
      final other = FirestoreRestService.decodeFields(doc['fields']);
      return (doc['name'] as String).split('/').last != billId &&
          other['status'] != 'CANCELLED' &&
          (other['supplierInvoiceNumber'] as String? ?? '')
                  .trim()
                  .toLowerCase() ==
              supplierInvoiceNumber.trim().toLowerCase();
    }))
      throw const AppException(
        'This supplier invoice number is already recorded.',
      );

    final before = <String, dynamic>{
      'supplierInvoiceNumber': bill.supplierInvoiceNumber,
      'invoiceDate': bill.invoiceDate,
      'purchaseDate': bill.purchaseDate,
      'items': [for (final item in bill.items) _correctionLineSnapshot(item)],
      'grandTotal': bill.grandTotal,
      'paidAmount': bill.paidAmount,
      'outstandingAmount': bill.outstandingAmount,
    };
    final afterItems = <PurchaseBillItemModel>[];
    final changed = <String>{};
    if (bill.supplierInvoiceNumber != supplierInvoiceNumber.trim())
      changed.add('supplierInvoiceNumber');
    if (!_sameDateOnly(bill.invoiceDate, invoiceDate))
      changed.add('invoiceDate');
    if (bill.purchaseDate == null ||
        !_sameDateOnly(bill.purchaseDate!, purchaseDate))
      changed.add('purchaseDate');
    final now = DateTime.now().toUtc();
    final afterItemSnapshots = <Map<String, dynamic>>[];
    final changedLineIds = <String>{};
    for (final item in bill.items) {
      final change = lineMetadata[item.goodsReceiptItemId] ?? const {};
      final quantity = change['quantity'] is int
          ? change['quantity'] as int
          : item.quantity;
      final rate = change['rate'] is int ? change['rate'] as int : item.rate;
      final gstRateBps = change['gstRateBps'] is int
          ? change['gstRateBps'] as int
          : item.gstRateBps;
      final next = PurchaseBillItemModel(
        goodsReceiptItemId: item.goodsReceiptItemId,
        variantId: item.variantId,
        productName: item.productName,
        unitId: item.unitId,
        conversionFactor: item.conversionFactor,
        quantity: quantity,
        rate: rate,
        gstRateBps: gstRateBps,
        taxableAmount: _roundHalfUp(quantity * rate, 1000),
        taxAmount: 0,
        commercialUnitId: item.commercialUnitId,
        hsnCode: item.hsnCode,
        mrp: change.containsKey('mrp') ? change['mrp'] as int? : item.mrp,
        sellingPrice: change.containsKey('sellingPrice')
            ? change['sellingPrice'] as int?
            : item.sellingPrice,
        productId: item.productId,
        variantName: item.variantName,
        barcodeSnapshot: item.barcodeSnapshot,
        internalBatchNo: item.internalBatchNo,
        supplierLotNo: change.containsKey('supplierLotNo')
            ? change['supplierLotNo'] as String?
            : item.supplierLotNo,
        manufacturingDate: change.containsKey('manufacturingDate')
            ? change['manufacturingDate'] as DateTime?
            : item.manufacturingDate,
        expiryDate: change.containsKey('expiryDate')
            ? change['expiryDate'] as DateTime?
            : item.expiryDate,
        storageType: item.storageType,
        storageLocationId: item.storageLocationId,
        rackId: item.rackId,
      );
      if (next.supplierLotNo != item.supplierLotNo)
        changed.add('items.${item.goodsReceiptItemId}.supplierLotNo');
      if (next.quantity != item.quantity)
        changed.add('items.${item.goodsReceiptItemId}.quantity');
      if (next.rate != item.rate)
        changed.add('items.${item.goodsReceiptItemId}.rate');
      if (next.gstRateBps != item.gstRateBps)
        changed.add('items.${item.goodsReceiptItemId}.gstRateBps');
      if (next.mrp != item.mrp)
        changed.add('items.${item.goodsReceiptItemId}.mrp');
      if (next.sellingPrice != item.sellingPrice)
        changed.add('items.${item.goodsReceiptItemId}.sellingPrice');
      if (!_sameDateNullable(next.manufacturingDate, item.manufacturingDate)) {
        changed.add('items.${item.goodsReceiptItemId}.manufacturingDate');
        changedLineIds.add(item.goodsReceiptItemId);
      }
      if (!_sameDateNullable(next.expiryDate, item.expiryDate)) {
        changed.add('items.${item.goodsReceiptItemId}.expiryDate');
        changedLineIds.add(item.goodsReceiptItemId);
      }
      if (next.supplierLotNo != item.supplierLotNo)
        changedLineIds.add(item.goodsReceiptItemId);
      if (next.quantity != item.quantity ||
          next.rate != item.rate ||
          next.gstRateBps != item.gstRateBps ||
          next.mrp != item.mrp ||
          next.sellingPrice != item.sellingPrice) {
        changedLineIds.add(item.goodsReceiptItemId);
      }
      afterItems.add(next);
    }
    // Reuse the same discount allocation and tax conventions as purchase
    // creation/editing. Item taxableAmount is stored net of the bill discount.
    final subtotal = afterItems.fold<int>(
      0,
      (sum, item) => sum + item.taxableAmount,
    );
    var allocatedDiscount = 0;
    var totalTax = 0;
    for (var index = 0; index < afterItems.length; index++) {
      final item = afterItems[index];
      final itemDiscount = index == afterItems.length - 1
          ? bill.discountAmount - allocatedDiscount
          : subtotal == 0
          ? 0
          : _roundHalfUp(bill.discountAmount * item.taxableAmount, subtotal);
      allocatedDiscount += itemDiscount;
      final lineTaxable = item.taxableAmount - itemDiscount;
      final lineTax = _roundHalfUp(lineTaxable * item.gstRateBps, 10000);
      totalTax += lineTax;
      afterItems[index] = PurchaseBillItemModel(
        goodsReceiptItemId: item.goodsReceiptItemId,
        variantId: item.variantId,
        productName: item.productName,
        unitId: item.unitId,
        conversionFactor: item.conversionFactor,
        quantity: item.quantity,
        rate: item.rate,
        gstRateBps: item.gstRateBps,
        taxableAmount: lineTaxable,
        taxAmount: lineTax,
        commercialUnitId: item.commercialUnitId,
        hsnCode: item.hsnCode,
        mrp: item.mrp,
        sellingPrice: item.sellingPrice,
        productId: item.productId,
        variantName: item.variantName,
        barcodeSnapshot: item.barcodeSnapshot,
        internalBatchNo: item.internalBatchNo,
        supplierLotNo: item.supplierLotNo,
        manufacturingDate: item.manufacturingDate,
        expiryDate: item.expiryDate,
        storageType: item.storageType,
        storageLocationId: item.storageLocationId,
        rackId: item.rackId,
      );
    }
    afterItemSnapshots.addAll(afterItems.map(_correctionLineSnapshot));
    final taxableAmount = subtotal - bill.discountAmount;
    final taxIsIntraState = bill.taxType == 'INTRA_STATE';
    final cgstAmount = taxIsIntraState ? totalTax ~/ 2 : 0;
    final sgstAmount = taxIsIntraState ? totalTax - cgstAmount : 0;
    final igstAmount = taxIsIntraState ? 0 : totalTax;
    final int grandTotal =
        (taxableAmount + totalTax + bill.chargesAmount + bill.roundOff).toInt();
    if (grandTotal != bill.grandTotal ||
        subtotal != bill.subtotal ||
        taxableAmount != bill.taxableAmount ||
        totalTax != bill.cgstAmount + bill.sgstAmount + bill.igstAmount) {
      changed.add('financialTotals');
    }
    if (changed.isEmpty)
      throw const AppException('No purchase values changed.');
    final after = <String, dynamic>{
      'supplierInvoiceNumber': supplierInvoiceNumber.trim(),
      'invoiceDate': invoiceDate.toUtc(),
      'purchaseDate': purchaseDate.toUtc(),
      'items': afterItemSnapshots,
      'subtotal': subtotal,
      'taxableAmount': taxableAmount,
      'cgstAmount': cgstAmount,
      'sgstAmount': sgstAmount,
      'igstAmount': igstAmount,
      'grandTotal': grandTotal,
      'paidAmount': bill.paidAmount,
      'outstandingAmount': grandTotal - bill.paidAmount,
    };
    final priorCorrections = await firestore.queryDocuments(
      collection: FirebaseConstants.purchaseCorrections,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        FirestoreFilter('outletId', 'EQUAL', outletId),
        FirestoreFilter('purchaseId', 'EQUAL', billId),
      ],
      idToken: token,
    );
    final correctionNumber =
        priorCorrections.fold<int>(0, (max, doc) {
          final data = FirestoreRestService.decodeFields(doc['fields']);
          final value = (data['correctionNumber'] as num?)?.toInt() ?? 0;
          return value > max ? value : max;
        }) +
        1;
    final nextBillVersion = bill.version + 1;
    final correctionId = 'COR_${billId}_$correctionNumber';
    final audit = PurchaseCorrectionModel(
      correctionId: correctionId,
      purchaseId: billId,
      correctionNumber: correctionNumber,
      reason: reason.trim(),
      correctedByUid: correctedByUid,
      correctedAt: now,
      changedFields: changed.toList()..sort(),
      beforeSnapshot: before,
      afterSnapshot: after,
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      createdAt: now,
      updatedAt: now,
    );
    var paidAfterCorrection = bill.paidAmount;
    var outstandingAfterCorrection = grandTotal - bill.paidAmount;
    var allocatedBeforeCorrection = 0;
    var releasedAllocationAmount = 0;
    var supplierAdvanceBefore = 0;
    var supplierAdvanceAfter = 0;
    var supplierPayableDelta = 0;
    final allocationReleaseReferences = <Map<String, dynamic>>[];
    await serverTransactions.runAtomicOperation((tx) async {
      final latest = await tx.get(FirebaseConstants.purchaseBills, billId);
      if (!latest.exists ||
          latest.fields['status'] != 'APPROVED' ||
          latest.fields['tenantId'] != tenantId ||
          latest.fields['businessId'] != businessId ||
          latest.fields['outletId'] != outletId ||
          latest.fields['version'] != bill.version) {
        throw const AppException(
          'Purchase changed. Reload it before correcting.',
        );
      }
      final paymentAllocations = await tx.query(
        FirebaseConstants.paymentAllocations,
        [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('purchaseBillId', 'EQUAL', billId),
        ],
      );
      final allocatedPayments = paymentAllocations.fold<int>(
        0,
        (sum, allocation) =>
            sum +
            ((allocation.fields['allocatedAmount'] as num?)?.toInt() ?? 0),
      );
      allocatedBeforeCorrection = allocatedPayments;
      if (grandTotal < bill.paidAmount || grandTotal < allocatedPayments) {
        if (allocatedPayments != bill.paidAmount) {
          throw const AppException(
            'Payment allocation records do not match the purchase paid amount. Reconcile payment history before correcting.',
          );
        }
        var remainingRelease = allocatedPayments - grandTotal;
        final releases = <Map<String, dynamic>>[];
        final seenPaymentIds = <String>{};
        for (final allocation in paymentAllocations) {
          final allocationId = allocation.fields['allocationId'] as String?;
          final paymentId = allocation.fields['sourceId'] as String?;
          if (allocationId == null ||
              allocationId.isEmpty ||
              paymentId == null ||
              paymentId.isEmpty ||
              allocation.fields['sourceType'] != 'PAYMENT' ||
              allocation.fields['purchaseBillId'] != billId ||
              !seenPaymentIds.add(paymentId)) {
            throw const AppException(
              'Payment allocations cannot be reconciled safely. Review payment history before correcting.',
            );
          }
          final payment = await tx.get(
            FirebaseConstants.supplierPayments,
            paymentId,
          );
          final allocationAmount =
              (allocation.fields['allocatedAmount'] as num?)?.toInt() ?? 0;
          final paymentAllocated =
              (payment.fields['allocatedAmount'] as num?)?.toInt() ?? 0;
          final paymentUnallocated =
              (payment.fields['unallocatedAmount'] as num?)?.toInt() ?? 0;
          final originalAmount =
              (payment.fields['amount'] as num?)?.toInt() ?? 0;
          if (!payment.exists ||
              payment.fields['paymentId'] != paymentId ||
              payment.fields['purchaseBillId'] != billId ||
              payment.fields['supplierBusinessId'] != bill.supplierBusinessId ||
              payment.fields['paymentType'] != 'AGAINST_BILL' ||
              paymentAllocated != allocationAmount ||
              paymentAllocated + paymentUnallocated != originalAmount ||
              allocationAmount <= 0) {
            throw const AppException(
              'A linked supplier payment is incomplete or inconsistent. Reconcile payment history before correcting.',
            );
          }
          releases.add({
            'allocationId': allocationId,
            'paymentId': paymentId,
            'allocation': allocation,
            'payment': payment,
            'amount': allocationAmount,
            'paymentDate': _dateValue(payment.fields['paymentDate']),
            'allocationDate': _dateValue(allocation.fields['createdAt']),
          });
        }
        if (seenPaymentIds.length != paymentAllocations.length ||
            releases.fold<int>(0, (sum, row) => sum + (row['amount'] as int)) !=
                allocatedPayments) {
          throw const AppException(
            'Payment allocations cannot be reconciled safely. Review payment history before correcting.',
          );
        }
        releases.sort((a, b) {
          final aPaymentDate =
              a['paymentDate'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bPaymentDate =
              b['paymentDate'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final paymentDateOrder = bPaymentDate.compareTo(aPaymentDate);
          if (paymentDateOrder != 0) return paymentDateOrder;
          final aAllocationDate =
              a['allocationDate'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bAllocationDate =
              b['allocationDate'] as DateTime? ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final allocationDateOrder = bAllocationDate.compareTo(
            aAllocationDate,
          );
          if (allocationDateOrder != 0) return allocationDateOrder;
          return (b['allocationId'] as String).compareTo(
            a['allocationId'] as String,
          );
        });
        for (final releaseRow in releases) {
          if (remainingRelease == 0) break;
          final allocationId = releaseRow['allocationId'] as String;
          final paymentId = releaseRow['paymentId'] as String;
          final allocationAmount = releaseRow['amount'] as int;
          final int releaseAmount = (allocationAmount < remainingRelease
              ? allocationAmount
              : remainingRelease).toInt();
          final allocation = await tx.get(
            FirebaseConstants.paymentAllocations,
            allocationId,
          );
          final payment = await tx.get(
            FirebaseConstants.supplierPayments,
            paymentId,
          );
          if (!allocation.exists ||
              !payment.exists ||
              (allocation.fields['allocatedAmount'] as num?)?.toInt() !=
                  allocationAmount ||
              (payment.fields['allocatedAmount'] as num?)?.toInt() !=
                  allocationAmount) {
            throw const AppException(
              'Payment allocation changed. Reload the purchase and retry.',
            );
          }
          tx.update(FirebaseConstants.paymentAllocations, allocationId, {
            'allocatedAmount': allocationAmount - releaseAmount,
          }, updateTime: allocation.updateTime);
          tx.update(FirebaseConstants.supplierPayments, paymentId, {
            'allocatedAmount': allocationAmount - releaseAmount,
            'unallocatedAmount':
                ((payment.fields['unallocatedAmount'] as num?)?.toInt() ?? 0) +
                releaseAmount,
            'updatedBy': correctedByUid,
            'updatedAt': now,
          }, updateTime: payment.updateTime);
          final releaseLedgerId =
              'PAYMENT_ALLOCATION_RELEASE_${correctionId}_$allocationId';
          tx.create(FirebaseConstants.supplierLedgerEntries, releaseLedgerId, {
            'ledgerEntryId': releaseLedgerId,
            'tenantId': tenantId,
            'businessId': businessId,
            'outletId': outletId,
            'supplierId': bill.supplierId,
            'supplierBusinessId': bill.supplierBusinessId,
            'entryType': 'PAYMENT_ALLOCATION_RELEASE',
            'referenceType': 'PURCHASE_CORRECTION',
            'referenceId': correctionId,
            'purchaseBillId': billId,
            'paymentId': paymentId,
            'allocationId': allocationId,
            'releasedAmount': releaseAmount,
            // Classification only: the original cash movement is unchanged.
            'debit': 0,
            'credit': 0,
            'reason': reason.trim(),
            'isReversal': false,
            'reversalOfId': null,
            'transactionDate': now,
            'createdBy': correctedByUid,
            'createdAt': now,
          });
          allocationReleaseReferences.add({
            'paymentId': paymentId,
            'allocationId': allocationId,
            'releasedAmount': releaseAmount,
            'ledgerEntryId': releaseLedgerId,
          });
          releasedAllocationAmount += releaseAmount;
          remainingRelease -= releaseAmount;
        }
        if (remainingRelease != 0) {
          throw const AppException(
            'Recorded payment allocations are insufficient to reconcile this purchase correction.',
          );
        }
      }
      paidAfterCorrection = allocatedPayments > grandTotal
          ? grandTotal
          : bill.paidAmount;
      outstandingAfterCorrection = grandTotal - paidAfterCorrection;
      after['paidAmount'] = paidAfterCorrection;
      after['outstandingAmount'] = outstandingAfterCorrection;
      final correctionMovements = <Map<String, dynamic>>[];
      for (final item in afterItems) {
        final oldItem = bill.items.firstWhere(
          (candidate) =>
              candidate.goodsReceiptItemId == item.goodsReceiptItemId,
        );
        final batchId = 'BATCH_${billId}_${item.goodsReceiptItemId}';
        final batch = await tx.get(FirebaseConstants.inventoryBatches, batchId);
        final receiptIds =
            latest.fields['goodsReceiptIds'] as List? ?? const [];
        final grnId =
            latest.fields['autoGoodsReceiptId'] as String? ??
            (receiptIds.isEmpty ? null : receiptIds.first as String?);
        final grnItemId = grnId == null
            ? null
            : '${grnId}_${item.goodsReceiptItemId}';
        final receipt = grnItemId == null
            ? null
            : await tx.get(FirebaseConstants.goodsReceiptItems, grnItemId);
        final purchaseItem = await tx.get(
          FirebaseConstants.purchaseBillItems,
          item.goodsReceiptItemId,
        );
        if (!batch.exists ||
            receipt == null ||
            !receipt.exists ||
            !purchaseItem.exists ||
            batch.fields['purchaseId'] != billId ||
            batch.fields['purchaseItemId'] != item.goodsReceiptItemId ||
            batch.fields['internalBatchNo'] != item.internalBatchNo) {
          throw const AppException(
            'Linked purchase receipt/batch records are incomplete; correction was not saved.',
          );
        }
        if (purchaseItem.fields['purchaseId'] != billId ||
            purchaseItem.fields['purchaseItemId'] != item.goodsReceiptItemId ||
            receipt.fields['purchaseBillId'] != billId ||
            receipt.fields['goodsReceiptId'] != grnId) {
          throw const AppException(
            'Purchase line and receipt linkage do not match; correction was not saved.',
          );
        }
        final oldBase = oldItem.baseQuantity;
        final newBase = item.baseQuantity;
        final delta = newBase - oldBase;
        final batchMovements = await tx.query(
          FirebaseConstants.inventoryBatchMovements,
          [
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
            FirestoreFilter('outletId', 'EQUAL', outletId),
            FirestoreFilter('batchId', 'EQUAL', batchId),
          ],
        );
        final movements = batchMovements
            .map((row) => row.fields)
            .where(
              (movement) =>
                  movement['status'] == 'POSTED' &&
                  movement['isDeleted'] != true,
            )
            .toList();
        final receiptBase = movements
            .where(
              (movement) =>
                  movement['movementType'] == 'PURCHASE_RECEIPT' &&
                  movement['direction'] == 'IN' &&
                  movement['referenceType'] == 'GOODS_RECEIPT' &&
                  movement['referenceLineId'] == grnItemId,
            )
            .fold<int>(
              0,
              (sum, movement) =>
                  sum + ((movement['quantity'] as num?)?.toInt() ?? 0),
            );
        final correctionIn = movements
            .where(
              (m) =>
                  m['movementType'] == 'PURCHASE_CORRECTION_IN' &&
                  m['direction'] == 'IN',
            )
            .fold<int>(
              0,
              (sum, m) => sum + ((m['quantity'] as num?)?.toInt() ?? 0),
            );
        final correctionOut = movements
            .where(
              (m) =>
                  m['movementType'] == 'PURCHASE_CORRECTION_OUT' &&
                  m['direction'] == 'OUT',
            )
            .fold<int>(
              0,
              (sum, m) => sum + ((m['quantity'] as num?)?.toInt() ?? 0),
            );
        final received = (batch.fields['receivedQty'] as num?)?.toInt() ?? 0;
        if (delta != 0 &&
            received != receiptBase + correctionIn - correctionOut) {
          throw const AppException(
            'Quantity correction is blocked because this batch lacks complete verified movement-ledger coverage.',
          );
        }
        final consumed = movements
            .where(
              (movement) =>
                  movement['direction'] == 'OUT' &&
                  const {
                    'SALE',
                    'PURCHASE_RETURN',
                    'TRANSFER_OUT',
                    'ADJUSTMENT_OUT',
                  }.contains(movement['movementType']),
            )
            .fold<int>(
              0,
              (sum, movement) =>
                  sum + ((movement['quantity'] as num?)?.toInt() ?? 0),
            );
        final derived = movements.fold<int>(0, (sum, movement) {
          final quantity = (movement['quantity'] as num?)?.toInt() ?? 0;
          if (movement['direction'] == 'IN') return sum + quantity;
          if (movement['direction'] == 'OUT') return sum - quantity;
          return sum;
        });
        final available = (batch.fields['availableQty'] as num?)?.toInt() ?? 0;
        if (delta != 0 && (derived != available || derived < 0)) {
          throw const AppException(
            'Batch ledger availability does not match the stored batch quantity. Refresh inventory and retry.',
          );
        }
        if (delta < 0 && (newBase < consumed || -delta > available)) {
          throw AppException(
            'Cannot reduce received quantity below quantity already consumed. Received ${_qtyText(oldBase)}, consumed ${_qtyText(consumed)}, available ${_qtyText(available)}, minimum ${_qtyText(consumed)}.',
          );
        }
        if (delta != 0) {
          final movementId =
              'BATCH_MOVEMENT_PURCHASE_CORRECTION_${billId}_${item.goodsReceiptItemId}_${bill.version + 1}';
          final correctionType = delta > 0
              ? 'PURCHASE_CORRECTION_IN'
              : 'PURCHASE_CORRECTION_OUT';
          final movementFields = {
            'movementId': movementId,
            'tenantId': tenantId,
            'businessId': businessId,
            'outletId': outletId,
            'batchId': batchId,
            'productId': item.productId,
            'variantId': item.variantId,
            'movementType': correctionType,
            'quantity': delta.abs(),
            'direction': delta > 0 ? 'IN' : 'OUT',
            'referenceType': 'PURCHASE_CORRECTION',
            'referenceId': correctionId,
            'referenceLineId': item.goodsReceiptItemId,
            'reason': reason.trim(),
            'createdByUid': correctedByUid,
            'occurredAt': now,
            'status': 'POSTED',
            'isDeleted': false,
            'createdAt': now,
            'updatedAt': now,
          };
          if ((await tx.get(
            FirebaseConstants.inventoryBatchMovements,
            movementId,
          )).exists) {
            throw const AppException(
              'This correction movement already exists. Reload and retry.',
            );
          }
          tx.create(
            FirebaseConstants.inventoryBatchMovements,
            movementId,
            movementFields,
          );
          correctionMovements.add({
            'movementId': movementId,
            'batchId': batchId,
            'quantity': delta.abs(),
          });
          final nextAvailable = available + delta;
          tx.update(FirebaseConstants.inventoryBatches, batchId, {
            'receivedQty': newBase,
            'availableQty': nextAvailable,
            'status': nextAvailable == 0 ? 'DEPLETED' : 'AVAILABLE',
            'updatedAt': now,
          }, updateTime: batch.updateTime);
          final stockId = stockBalanceId(tenantId, outletId, item.variantId);
          final stock = await tx.get(FirebaseConstants.stockBalances, stockId);
          if (!stock.exists ||
              stock.fields['tenantId'] != tenantId ||
              stock.fields['businessId'] != businessId ||
              stock.fields['outletId'] != outletId ||
              stock.fields['variantId'] != item.variantId ||
              (stock.fields['quantityOnHand'] as num?)?.toInt() == null) {
            throw const AppException(
              'Outlet stock balance is unavailable; correction was not saved.',
            );
          }
          final oldQty = (stock.fields['quantityOnHand'] as num).toInt();
          final nextQty = oldQty + delta;
          if (nextQty < 0)
            throw const AppException(
              'Correction would make outlet stock negative.',
            );
          final oldValue = (stock.fields['totalValue'] as num?)?.toInt() ?? 0;
          final lineCost =
              item.taxableAmount +
              _proportionalShare(
                bill.chargesAmount,
                item.taxableAmount,
                taxableAmount,
              );
          final unitCost = newBase == 0
              ? 0
              : _roundHalfUp(lineCost * 1000, newBase);
          final oldLineCost =
              oldItem.taxableAmount +
              _proportionalShare(
                bill.chargesAmount,
                oldItem.taxableAmount,
                bill.taxableAmount,
              );
          final oldUnitCost = oldBase == 0
              ? 0
              : _roundHalfUp(oldLineCost * 1000, oldBase);
          final valueDelta =
              _roundHalfUp(unitCost * delta, 1000) +
              (item.taxableAmount == oldItem.taxableAmount
                  ? 0
                  : _roundHalfUp((unitCost - oldUnitCost) * available, 1000));
          final nextValue = oldValue + valueDelta;
          if (nextValue < 0)
            throw const AppException(
              'Correction would make inventory valuation negative.',
            );
          final transactionId =
              'PURCHASE_CORRECTION_${billId}_${item.goodsReceiptItemId}_${bill.version + 1}';
          tx.create(FirebaseConstants.inventoryTransactions, transactionId, {
            'inventoryTransactionId': transactionId,
            'tenantId': tenantId,
            'businessId': businessId,
            'outletId': outletId,
            'locationType': batch.fields['storageType'] ?? 'OUTLET',
            'locationId': batch.fields['storageLocationId'] ?? outletId,
            'rackId': batch.fields['rackId'],
            'productId': item.productId,
            'variantId': item.variantId,
            'batchId': batchId,
            'transactionType': correctionType,
            'sourceType': 'PURCHASE_CORRECTION',
            'sourceId': correctionId,
            'sourceItemId': item.goodsReceiptItemId,
            'direction': delta > 0 ? 'IN' : 'OUT',
            'quantity': delta.abs(),
            'baseQuantity': delta.abs(),
            'unitId': item.unitId,
            'commercialUnitId': item.commercialUnitId,
            'commercialQuantity': (delta.abs() * 1000) / item.conversionFactor,
            'conversionFactor': item.conversionFactor,
            'unitCost': unitCost,
            'totalCost': valueDelta.abs(),
            'isReversal': false,
            'reversalOfId': null,
            'createdBy': correctedByUid,
            'createdAt': now,
          });
          tx.update(FirebaseConstants.stockBalances, stockId, {
            'quantityOnHand': nextQty,
            'totalValue': nextValue,
            'averageCost': nextQty == 0
                ? 0
                : _roundHalfUp(nextValue * 1000, nextQty),
            'lastInventoryTransactionId': transactionId,
            'updatedAt': now,
          }, updateTime: stock.updateTime);
        }
        if (delta == 0 && item.taxableAmount != oldItem.taxableAmount) {
          final stockId = stockBalanceId(tenantId, outletId, item.variantId);
          final stock = await tx.get(FirebaseConstants.stockBalances, stockId);
          if (!stock.exists) {
            throw const AppException(
              'Outlet stock balance is unavailable; correction was not saved.',
            );
          }
          if (stock.fields['tenantId'] != tenantId ||
              stock.fields['businessId'] != businessId ||
              stock.fields['outletId'] != outletId ||
              stock.fields['variantId'] != item.variantId) {
            throw const AppException(
              'Outlet stock scope does not match this purchase; correction was not saved.',
            );
          }
          final available =
              (batch.fields['availableQty'] as num?)?.toInt() ?? 0;
          final oldLineCost =
              oldItem.taxableAmount +
              _proportionalShare(
                bill.chargesAmount,
                oldItem.taxableAmount,
                bill.taxableAmount,
              );
          final newLineCost =
              item.taxableAmount +
              _proportionalShare(
                bill.chargesAmount,
                item.taxableAmount,
                taxableAmount,
              );
          final oldUnitCost = oldBase == 0
              ? 0
              : _roundHalfUp(oldLineCost * 1000, oldBase);
          final newUnitCost = newBase == 0
              ? 0
              : _roundHalfUp(newLineCost * 1000, newBase);
          final valueDelta = _roundHalfUp(
            (newUnitCost - oldUnitCost) * available,
            1000,
          );
          final oldValue = (stock.fields['totalValue'] as num?)?.toInt() ?? 0;
          final nextValue = oldValue + valueDelta;
          if (nextValue < 0) {
            throw const AppException(
              'Purchase rate correction would make inventory valuation negative.',
            );
          }
          final quantityOnHand =
              (stock.fields['quantityOnHand'] as num?)?.toInt() ?? 0;
          tx.update(FirebaseConstants.stockBalances, stockId, {
            'totalValue': nextValue,
            'averageCost': quantityOnHand == 0
                ? 0
                : _roundHalfUp(nextValue * 1000, quantityOnHand),
            'updatedAt': now,
          }, updateTime: stock.updateTime);
        }
        if (changedLineIds.contains(item.goodsReceiptItemId)) {
          tx.update(FirebaseConstants.inventoryBatches, batchId, {
            'purchaseRate': item.rate,
            'mrp': item.mrp,
            'sellingPrice': item.sellingPrice,
            'supplierLotNo': item.supplierLotNo,
            'manufacturingDate': item.manufacturingDate,
            'expiryDate': item.expiryDate,
            'updatedAt': now,
          }, updateTime: batch.updateTime);

          final variantPricingUpdates = <String, dynamic>{
            if (item.sellingPrice != null && item.sellingPrice! > 0)
              'sellingPrice': item.sellingPrice,
            if (item.mrp != null && item.mrp! > 0) 'mrp': item.mrp,
            if (item.rate > 0) 'purchaseRate': item.rate,
          };
          if (variantPricingUpdates.isNotEmpty) {
            variantPricingUpdates['updatedAt'] = now;
            variantPricingUpdates['updatedBy'] = correctedByUid;
            final variantDoc = await tx.get(
              FirebaseConstants.productVariants,
              item.variantId,
            );
            if (variantDoc.exists) {
              tx.update(
                FirebaseConstants.productVariants,
                item.variantId,
                variantPricingUpdates,
                updateTime: variantDoc.updateTime,
              );
            } else {
              final productDoc = await tx.get(
                FirebaseConstants.products,
                item.variantId,
              );
              if (productDoc.exists) {
                tx.update(
                  FirebaseConstants.products,
                  item.variantId,
                  variantPricingUpdates,
                  updateTime: productDoc.updateTime,
                );
              }
            }
          }
        }
        final lineFields = {
          ...item.toData(),
          'purchaseItemId': item.goodsReceiptItemId,
          'purchaseId': billId,
          'purchaseBillId': billId,
          'supplierId': bill.supplierId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'updatedAt': now,
        };
        tx.update(
          FirebaseConstants.purchaseBillItems,
          item.goodsReceiptItemId,
          lineFields,
          updateTime: purchaseItem.updateTime,
        );
        tx.update(FirebaseConstants.goodsReceiptItems, grnItemId!, {
          'orderedQuantity': item.quantity,
          'receivedQuantity': item.quantity,
          'acceptedQuantity': item.quantity,
          'provisionalRate': item.rate,
          'billedBaseQuantity': item.baseQuantity,
          'supplierLotNo': item.supplierLotNo,
          'manufacturingDate': item.manufacturingDate,
          'expiryDate': item.expiryDate,
          'updatedAt': now,
        }, updateTime: receipt.updateTime);
      }
      final supplierDelta = grandTotal - bill.grandTotal;
      supplierPayableDelta =
          outstandingAfterCorrection - bill.outstandingAmount;
      final balance = await tx.get(
        FirebaseConstants.supplierBalances,
        bill.supplierBusinessId,
      );
      if ((supplierDelta != 0 || releasedAllocationAmount > 0) &&
          !balance.exists) {
        throw const AppException(
          'Supplier balance is unavailable; correction was not saved.',
        );
      }
      if (balance.exists &&
          (supplierDelta != 0 || releasedAllocationAmount > 0)) {
        final oldPayable =
            (balance.fields['totalPayable'] as num?)?.toInt() ?? 0;
        supplierAdvanceBefore =
            (balance.fields['unallocatedAdvance'] as num?)?.toInt() ?? 0;
        supplierAdvanceAfter = supplierAdvanceBefore + releasedAllocationAmount;
        if (oldPayable + supplierPayableDelta < 0) {
          throw const AppException(
            'Correction would make supplier payable negative.',
          );
        }
        String? lastLedgerEntryId;
        if (supplierDelta != 0) {
          lastLedgerEntryId =
              'PURCHASE_CORRECTION_LEDGER_${billId}_${bill.version + 1}';
          tx.create(
            FirebaseConstants.supplierLedgerEntries,
            lastLedgerEntryId,
            {
              'ledgerEntryId': lastLedgerEntryId,
              'tenantId': tenantId,
              'businessId': businessId,
              'outletId': outletId,
              'supplierId': bill.supplierId,
              'supplierBusinessId': bill.supplierBusinessId,
              'entryType': 'PURCHASE_CORRECTION',
              'referenceType': 'PURCHASE_CORRECTION',
              'referenceId': correctionId,
              'debit': supplierDelta < 0 ? -supplierDelta : 0,
              'credit': supplierDelta > 0 ? supplierDelta : 0,
              'isReversal': false,
              'reversalOfId': null,
              'transactionDate': now,
              'createdBy': correctedByUid,
              'createdAt': now,
            },
          );
        }
        tx.update(FirebaseConstants.supplierBalances, bill.supplierBusinessId, {
          'totalPayable': oldPayable + supplierPayableDelta,
          'unallocatedAdvance': supplierAdvanceAfter,
          if (lastLedgerEntryId != null) 'lastLedgerEntryId': lastLedgerEntryId,
          'updatedAt': now,
        }, updateTime: balance.updateTime);
      }
      tx.update(FirebaseConstants.purchaseBills, billId, {
        'supplierInvoiceNumber': supplierInvoiceNumber.trim(),
        'invoiceDate': invoiceDate.toUtc(),
        'purchaseDate': purchaseDate.toUtc(),
        'items': afterItems.map((i) => i.toData()).toList(),
        'subtotal': subtotal,
        'taxableAmount': taxableAmount,
        'cgstAmount': cgstAmount,
        'sgstAmount': sgstAmount,
        'igstAmount': igstAmount,
        'grandTotal': grandTotal,
        'paidAmount': paidAfterCorrection,
        'outstandingAmount': outstandingAfterCorrection,
        'paymentStatus': paidAfterCorrection == 0
            ? 'UNPAID'
            : (outstandingAfterCorrection == 0 ? 'PAID' : 'PARTIAL'),
        'updatedBy': correctedByUid,
        'updatedAt': now,
        'version': nextBillVersion,
        'lastCorrectionId': correctionId,
        'lastCorrectionAt': now,
      }, updateTime: latest.updateTime);
      for (final item in afterItems) {
        final changes = lineMetadata[item.goodsReceiptItemId];
        if (changes == null ||
            changes.isEmpty ||
            !changedLineIds.contains(item.goodsReceiptItemId))
          continue;
        final purchaseItem = await tx.get(
          FirebaseConstants.purchaseBillItems,
          item.goodsReceiptItemId,
        );
        final batchId = 'BATCH_${billId}_${item.goodsReceiptItemId}';
        final batch = await tx.get(FirebaseConstants.inventoryBatches, batchId);
        final receiptIds = fields['goodsReceiptIds'] as List? ?? const [];
        final grnId =
            fields['autoGoodsReceiptId'] as String? ??
            (receiptIds.isEmpty ? null : receiptIds.first as String?);
        final grnItemId = grnId == null
            ? null
            : '${grnId}_${item.goodsReceiptItemId}';
        final receiptItem = grnItemId == null
            ? null
            : await tx.get(FirebaseConstants.goodsReceiptItems, grnItemId);
        if (!purchaseItem.exists ||
            !batch.exists ||
            receiptItem == null ||
            !receiptItem.exists ||
            batch.fields['purchaseId'] != billId ||
            batch.fields['internalBatchNo'] != item.internalBatchNo) {
          throw const AppException(
            'Linked purchase receipt/batch records are incomplete; correction was not saved.',
          );
        }
        tx.update(
          FirebaseConstants.purchaseBillItems,
          item.goodsReceiptItemId,
          {
            'supplierLotNo': item.supplierLotNo,
            'manufacturingDate': item.manufacturingDate,
            'expiryDate': item.expiryDate,
            'updatedAt': now,
          },
          updateTime: purchaseItem.updateTime,
        );
        tx.update(FirebaseConstants.inventoryBatches, batchId, {
          'supplierLotNo': item.supplierLotNo,
          'manufacturingDate': item.manufacturingDate,
          'expiryDate': item.expiryDate,
          'updatedAt': now,
        }, updateTime: batch.updateTime);
        tx.update(FirebaseConstants.goodsReceiptItems, grnItemId!, {
          'supplierLotNo': item.supplierLotNo,
          'manufacturingDate': item.manufacturingDate,
          'expiryDate': item.expiryDate,
        }, updateTime: receiptItem.updateTime);
      }
      tx.create(FirebaseConstants.purchaseCorrections, correctionId, {
        ...audit.toData(),
        'beforeSnapshot': before,
        'afterSnapshot': after,
        'inventoryReconciliationReferences': correctionMovements,
        'supplierPayableDelta': supplierPayableDelta,
        'purchaseTotalDelta': grandTotal - bill.grandTotal,
        'paymentValidation': {
          'paidAmountBefore': bill.paidAmount,
          'paidAmountAfter': paidAfterCorrection,
          'allocatedAmountBefore': allocatedBeforeCorrection,
          'correctedGrandTotal': grandTotal,
          'passed': true,
        },
        'paymentRelease': {
          'originalBillTotal': bill.grandTotal,
          'correctedBillTotal': grandTotal,
          'paidBefore': bill.paidAmount,
          'paidAfter': paidAfterCorrection,
          'outstandingBefore': bill.outstandingAmount,
          'outstandingAfter': outstandingAfterCorrection,
          'releasedAllocationAmount': releasedAllocationAmount,
          'supplierAdvanceBefore': supplierAdvanceBefore,
          'supplierAdvanceAfter': supplierAdvanceAfter,
          'allocations': allocationReleaseReferences,
          'reason': reason.trim(),
        },
      });
    }, idToken: token);
    return audit;
  }

  Map<String, dynamic> _correctionLineSnapshot(PurchaseBillItemModel item) => {
    'purchaseItemId': item.goodsReceiptItemId,
    'productId': item.productId,
    'variantId': item.variantId,
    'supplierLotNo': item.supplierLotNo,
    'quantity': item.quantity,
    'baseQuantity': item.baseQuantity,
    'rate': item.rate,
    'gstRateBps': item.gstRateBps,
    'taxableAmount': item.taxableAmount,
    'taxAmount': item.taxAmount,
    'mrp': item.mrp,
    'sellingPrice': item.sellingPrice,
    'manufacturingDate': item.manufacturingDate,
    'expiryDate': item.expiryDate,
    'barcodeSnapshot': item.barcodeSnapshot,
    'internalBatchNo': item.internalBatchNo,
  };

  static String _qtyText(int milli) {
    final value = milli / 1000;
    return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 3);
  }

  Future<void> recordPayment({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String supplierId,
    required String supplierBusinessId,
    required String? purchaseBillId,
    required int amount,
    required String paymentMode,
    required String transactionReference,
    required String userId,
    required String token,
  }) async {
    if (amount <= 0)
      throw const AppException('Enter a payment greater than zero.');
    final paymentId = IdGenerator.create('SPAY');
    Map<String, dynamic>? localMergedBill;
    await serverTransactions.runAtomicOperation((transaction) async {
      final relationDoc = await transaction.get(
        FirebaseConstants.supplierBusinesses,
        supplierBusinessId,
      );
      final balanceDoc = await transaction.get(
        FirebaseConstants.supplierBalances,
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
      final now = DateTime.now().toUtc();
      PurchaseBillModel? bill;
      FirestoreTransactionDocument? billDoc;
      if (purchaseBillId != null) {
        billDoc = await transaction.get(
          FirebaseConstants.purchaseBills,
          purchaseBillId,
        );
        if (!billDoc.exists && firestore is OfflineFirestoreService) {
          final local = (firestore as OfflineFirestoreService).localDataSource;
          if (local != null) {
            try {
              final localDoc = await local.row(
                FirebaseConstants.purchaseBills,
                purchaseBillId,
              );
              if (localDoc != null && localDoc['isDeleted'] != 1) {
                final payload =
                    jsonDecode(localDoc['payloadJson'] as String)
                        as Map<String, dynamic>;
                final fields = FirestoreRestService.decodeFields(payload);
                transaction.create(
                  FirebaseConstants.purchaseBills,
                  purchaseBillId,
                  fields,
                );
                billDoc = FirestoreTransactionDocument(
                  id: purchaseBillId,
                  exists: true,
                  fields: fields,
                  updateTime: null,
                );
              }
            } catch (_) {}
          }
        }
        if (billDoc == null || !billDoc.exists) {
          throw const AppException('Purchase bill was not found.');
        }
        bill = PurchaseBillModel.fromData(purchaseBillId, billDoc.fields);
        if (bill.tenantId != tenantId) {
          throw const AppException('Purchase bill belongs to another tenant.');
        }
        if (bill.supplierBusinessId != supplierBusinessId) {
          throw const AppException(
            'Purchase bill does not match this supplier relation.',
          );
        }
        if (bill.status != 'APPROVED') {
          throw AppException(
            'Purchase bill status is ${bill.status}; only APPROVED bills can be paid.',
          );
        }
        final effectiveOutstanding = (bill.outstandingAmount > 0
            ? bill.outstandingAmount
            : (bill.grandTotal - bill.paidAmount)).clamp(0, bill.grandTotal);
        if (amount > effectiveOutstanding) {
          throw AppException(
            'Payment exceeds the approved bill balance (₹${(amount / 100).toStringAsFixed(2)} > ₹${(effectiveOutstanding / 100).toStringAsFixed(2)}).',
          );
        }
      }
      final effectiveOutstanding = bill == null
          ? 0
          : ((bill.outstandingAmount > 0
                  ? bill.outstandingAmount
                  : (bill.grandTotal - bill.paidAmount))
              .clamp(0, bill.grandTotal));
      final newOutstanding =
          (effectiveOutstanding - amount).clamp(0, effectiveOutstanding);
      final oldPayable =
          (balanceDoc.fields['totalPayable'] as num?)?.toInt() ?? 0;
      final oldAdvance =
          (balanceDoc.fields['unallocatedAdvance'] as num?)?.toInt() ?? 0;
      final ledgerId = 'SUPPLIER_PAYMENT_$paymentId';
      transaction.create(FirebaseConstants.supplierPayments, paymentId, {
        'paymentId': paymentId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'supplierId': supplierId,
        'supplierBusinessId': supplierBusinessId,
        'paymentType': bill == null ? 'ADVANCE' : 'AGAINST_BILL',
        'amount': amount,
        'allocatedAmount': bill == null ? 0 : amount,
        'unallocatedAmount': bill == null ? amount : 0,
        'purchaseBillId': purchaseBillId,
        'paymentDate': now,
        'paymentMode': paymentMode,
        'transactionReference': transactionReference.trim(),
        'status': 'POSTED',
        'createdBy': userId,
        'createdAt': now,
        'updatedBy': userId,
        'updatedAt': now,
      });
      transaction.create(FirebaseConstants.supplierLedgerEntries, ledgerId, {
        'ledgerEntryId': ledgerId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'supplierId': supplierId,
        'supplierBusinessId': supplierBusinessId,
        'entryType': 'SUPPLIER_PAYMENT',
        'referenceType': 'SUPPLIER_PAYMENT',
        'referenceId': paymentId,
        'debit': amount,
        'credit': 0,
        'isReversal': false,
        'reversalOfId': null,
        'transactionDate': now,
        'createdBy': userId,
        'createdAt': now,
      });
      if (bill != null && billDoc != null) {
        final paymentStatus = newOutstanding == 0 ? 'PAID' : 'PARTIAL';
        final updatedBillFields = {
          'paidAmount': bill.paidAmount + amount,
          'outstandingAmount': newOutstanding,
          'paymentStatus': paymentStatus,
          'updatedBy': userId,
          'updatedAt': now,
          'version': bill.version + 1,
        };
        transaction.update(
          FirebaseConstants.purchaseBills,
          bill.purchaseBillId,
          updatedBillFields,
          updateTime: billDoc.updateTime,
        );
        localMergedBill = {
          ...billDoc.fields,
          ...updatedBillFields,
        };
        transaction.create(FirebaseConstants.paymentAllocations, ledgerId, {
          'allocationId': ledgerId,
          'tenantId': tenantId,
          'businessId': businessId,
          'supplierBusinessId': supplierBusinessId,
          'sourceType': 'PAYMENT',
          'sourceId': paymentId,
          'purchaseBillId': bill.purchaseBillId,
          'allocatedAmount': amount,
          'createdBy': userId,
          'createdAt': now,
        });
      }
      final balanceFields = {
        'tenantId': tenantId,
        'businessId': businessId,
        'supplierBusinessId': supplierBusinessId,
        'totalPayable': bill == null ? oldPayable : oldPayable - amount,
        'unallocatedAdvance': bill == null ? oldAdvance + amount : oldAdvance,
        'unallocatedReturnCredit':
            (balanceDoc.fields['unallocatedReturnCredit'] as num?)?.toInt() ??
            0,
        'unallocatedSupplierCredit':
            (balanceDoc.fields['unallocatedSupplierCredit'] as num?)?.toInt() ??
            0,
        'lastLedgerEntryId': ledgerId,
        'updatedAt': now,
      };
      if (balanceDoc.exists) {
        transaction.update(
          FirebaseConstants.supplierBalances,
          supplierBusinessId,
          balanceFields,
          updateTime: balanceDoc.updateTime,
        );
      } else {
        if (bill != null)
          throw const AppException('Supplier balance is not configured.');
        transaction.create(
          FirebaseConstants.supplierBalances,
          supplierBusinessId,
          balanceFields,
        );
      }
    }, idToken: token);

    if (localMergedBill != null &&
        purchaseBillId != null &&
        firestore is OfflineFirestoreService) {
      final local = (firestore as OfflineFirestoreService).localDataSource;
      if (local != null) {
        try {
          await local.db.transaction((localTx) async {
            await LocalDataSource.put(
              localTx,
              FirebaseConstants.purchaseBills,
              {
                'remoteId': purchaseBillId,
                'payloadJson': jsonEncode(
                  FirestoreRestService.encodeFields(localMergedBill!),
                ),
                ...LocalDataSource.scopeColumns(localMergedBill!),
                'syncStatus': 'SYNCED',
                'localUpdatedAt': LocalDataSource.now(),
                'isDeleted': 0,
              },
            );
          });
        } catch (_) {}
      }
    }
  }

  static String stockBalanceId(
    String tenantId,
    String outletId,
    String variantId,
  ) => '${tenantId}_${outletId}_$variantId';

  /// Canonical key for new location-aware stock buckets. Existing Outlet-only
  /// buckets keep their historical IDs and are upgraded in place on posting.
  static String stockLocationBalanceId({
    required String tenantId,
    required String businessId,
    required String locationType,
    required String locationId,
    required String variantId,
    String? rackId,
  }) =>
      '${tenantId}_${businessId}_${locationType}_${locationId}_${rackId ?? 'DIRECT'}_$variantId';

  static int _roundHalfUp(int numerator, int denominator) =>
      denominator <= 0 ? 0 : (numerator + denominator ~/ 2) ~/ denominator;

  static bool _sameDateOnly(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  static bool _sameDateNullable(DateTime? a, DateTime? b) =>
      a == null ? b == null : b != null && _sameDateOnly(a, b);

  static int _proportionalShare(int total, int lineValue, int subtotal) =>
      subtotal == 0 ? 0 : _roundHalfUp(total * lineValue, subtotal);

  static List<PurchaseBillItemModel> _aggregateLines(
    List<PurchaseBillItemModel> items,
  ) {
    final grouped = <String, PurchaseBillItemModel>{};
    for (final item in items) {
      final previous = grouped[item.variantId];
      grouped[item.variantId] = previous == null
          ? item
          : PurchaseBillItemModel(
              goodsReceiptItemId: previous.goodsReceiptItemId,
              variantId: item.variantId,
              productName: item.productName,
              unitId: item.unitId,
              commercialUnitId: item.commercialUnitId,
              conversionFactor: item.conversionFactor,
              quantity: previous.quantity + item.quantity,
              rate: previous.rate,
              gstRateBps: previous.gstRateBps,
              taxableAmount: previous.taxableAmount + item.taxableAmount,
              taxAmount: previous.taxAmount + item.taxAmount,
              storageType: previous.storageType,
              storageLocationId: previous.storageLocationId,
              rackId: previous.rackId,
            );
    }
    return grouped.values.toList();
  }

  ProductVariantModel _product(Map<String, dynamic> document) =>
      ProductVariantModel.fromData(
        (document['name'] as String? ?? '').split('/').last,
        FirestoreRestService.decodeFields(document['fields']),
      );

  PurchaseBillModel _bill(Map<String, dynamic> document) =>
      PurchaseBillModel.fromData(
        (document['name'] as String? ?? '').split('/').last,
        FirestoreRestService.decodeFields(document['fields']),
      );
}

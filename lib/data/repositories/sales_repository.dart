import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../models/inventory_batch_movement_model.dart';
import '../models/sales_invoice_model.dart';
import '../services/firestore_rest_service.dart';
import '../services/offline_firestore_service.dart';
import '../services/firestore_transaction_service.dart';

class SalesBatchOption {
  const SalesBatchOption({
    required this.batchId,
    required this.internalBatchNo,
    required this.supplierLotNo,
    required this.expiryDate,
    required this.storageType,
    required this.storageLocationId,
    required this.rackId,
    required this.availableBaseQuantity,
    required this.trusted,
  });

  final String batchId;
  final String internalBatchNo;
  final String? supplierLotNo, expiryDate, rackId;
  final String storageType, storageLocationId;
  final int availableBaseQuantity;
  final bool trusted;
}

class SalesRepository {
  SalesRepository(this.offline);
  final OfflineFirestoreService offline;

  Future<List<SalesBatchOption>> listBatches({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String productId,
    required String variantId,
  }) async {
    final scope = _scope(tenantId, businessId, outletId);
    final batchDocs = await offline.queryDocuments(
      collection: FirebaseConstants.inventoryBatches,
      filters: [
        ...scope,
        FirestoreFilter('productId', 'EQUAL', productId),
        FirestoreFilter('variantId', 'EQUAL', variantId),
      ],
    );
    final movementDocs = await offline.queryDocuments(
      collection: FirebaseConstants.inventoryBatchMovements,
      filters: [...scope, FirestoreFilter('variantId', 'EQUAL', variantId)],
    );
    final movements = movementDocs
        .map((doc) => FirestoreRestService.decodeFields(doc['fields']))
        .where(
          (fields) =>
              fields['status'] == 'POSTED' && fields['isDeleted'] != true,
        )
        .toList();
    return batchDocs
        .map((doc) => FirestoreRestService.decodeFields(doc['fields']))
        .where(
          (batch) =>
              batch['tenantId'] == tenantId &&
              batch['businessId'] == businessId &&
              batch['outletId'] == outletId &&
              batch['productId'] == productId &&
              batch['variantId'] == variantId,
        )
        .map((batch) {
          final batchId = batch['batchId']?.toString() ?? '';
          final batchMovements = movements
              .where((movement) => movement['batchId'] == batchId)
              .toList();
          final receiptQuantity = batchMovements
              .where(
                (movement) =>
                    movement['movementType'] == 'PURCHASE_RECEIPT' &&
                    movement['direction'] == 'IN' &&
                    movement['referenceType'] == 'GOODS_RECEIPT',
              )
              .fold<int>(
                0,
                (sum, movement) => sum + _int(movement['quantity']),
              );
          final receivedQty = _int(batch['receivedQty']);
          final derived = batchMovements.fold<int>(0, (sum, movement) {
            final quantity = _int(movement['quantity']);
            if (movement['direction'] == 'IN') return sum + quantity;
            if (movement['direction'] == 'OUT') return sum - quantity;
            return sum;
          });
          final trusted =
              batchId.isNotEmpty &&
              receivedQty > 0 &&
              receiptQuantity == receivedQty &&
              batch['status'] == 'AVAILABLE';
          return SalesBatchOption(
            batchId: batchId,
            internalBatchNo: batch['internalBatchNo']?.toString() ?? batchId,
            supplierLotNo: batch['supplierLotNo']?.toString(),
            expiryDate: batch['expiryDate']?.toString(),
            storageType: batch['storageType']?.toString() ?? 'OUTLET',
            storageLocationId:
                batch['storageLocationId']?.toString() ?? outletId,
            rackId: batch['rackId']?.toString(),
            availableBaseQuantity: trusted && derived > 0 ? derived : 0,
            trusted:
                trusted &&
                derived > 0 &&
                derived == _int(batch['availableQty']),
          );
        })
        .toList()
      ..sort((a, b) => a.internalBatchNo.compareTo(b.internalBatchNo));
  }

  Future<List<Map<String, dynamic>>> listLocalCustomers({
    required String tenantId,
    required String businessId,
    required String outletId,
  }) async {
    final documents = await offline.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
    );
    return documents
        .map((doc) {
          final id = (doc['name'] as String? ?? '').split('/').last;
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          return {
            'customerId': fields['customerId']?.toString() ?? id,
            'name': (fields['customerName'] ?? fields['name'] ?? 'Customer')
                .toString(),
            'fields': fields,
          };
        })
        .where((customer) {
          final fields = customer['fields'] as Map;
          return fields['isActive'] != false &&
              (fields['status']?.toString().toUpperCase() ?? 'ACTIVE') ==
                  'ACTIVE' &&
              (fields['outletId'] == null || fields['outletId'] == outletId);
        })
        .toList();
  }

  Future<String> postInvoice({
    required String invoiceId,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String actorUid,
    required DateTime invoiceDate,
    required String? customerId,
    required String? customerName,
    String? chargeToEmployeeId,
    required List<SalesInvoiceLine> lines,
    required String token,
  }) async {
    if (tenantId.isEmpty ||
        businessId.isEmpty ||
        outletId.isEmpty ||
        lines.isEmpty) {
      throw const AppException(
        'Select an Outlet and add at least one sale item.',
      );
    }
    if (invoiceId.trim().isEmpty) {
      throw const AppException('Invoice identity is required.');
    }
    if (lines.map((line) => line.invoiceLineId).toSet().length !=
        lines.length) {
      throw const AppException('Each sale line must have a unique identity.');
    }
    final postingFingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'invoiceDate': invoiceDate.toUtc().toIso8601String(),
              'customerId': customerId,
              'customerName': customerName,
              'chargeToEmployeeId': chargeToEmployeeId,
              'lines': lines.map((line) => line.toData()).toList(),
            }),
          ),
        )
        .toString();
    final now = DateTime.now().toUtc();
    late String invoiceNumber;
    await offline.runAtomicOperation((tx) async {
      final existingInvoice = await tx.get(
        FirebaseConstants.invoices,
        invoiceId,
      );
      if (existingInvoice.exists) {
        if (existingInvoice.fields['tenantId'] == tenantId &&
            existingInvoice.fields['businessId'] == businessId &&
            existingInvoice.fields['outletId'] == outletId &&
            existingInvoice.fields['createdByUid'] == actorUid &&
            existingInvoice.fields['postingFingerprint'] ==
                postingFingerprint) {
          invoiceNumber =
              existingInvoice.fields['invoiceNumber']?.toString() ?? '';
          return;
        }
        throw const AppException('This invoice has already been posted.');
      }
      final business = await tx.get(FirebaseConstants.businesses, businessId);
      if (!business.exists ||
          (business.fields['tenantId'] ?? business.fields['ownerUid']) !=
              tenantId ||
          business.fields['isActive'] == false ||
          business.fields['status'] == 'INACTIVE') {
        throw const AppException(
          'The selected Business is not active for this account.',
        );
      }
      final outlet = await tx.get(FirebaseConstants.outlets, outletId);
      if (!outlet.exists ||
          outlet.fields['tenantId'] != tenantId ||
          outlet.fields['businessId'] != businessId ||
          outlet.fields['isActive'] == false ||
          outlet.fields['status'] == 'INACTIVE') {
        throw const AppException(
          'The selected Outlet is not active for this Business.',
        );
      }
      String? staffEmployeeName;
      if (chargeToEmployeeId != null) {
        final employee = await tx.get(
          FirebaseConstants.employees,
          chargeToEmployeeId,
        );
        if (!employee.exists ||
            employee.fields['ownerUid'] != tenantId ||
            employee.fields['status']?.toString().toLowerCase() != 'active' ||
            !(employee.fields['businessIds'] as List? ?? const []).contains(
              businessId,
            ) ||
            !(employee.fields['outletIds'] as List? ?? const []).contains(
              outletId,
            )) {
          throw const AppException(
            'Select an active employee assigned to this outlet.',
          );
        }
        staffEmployeeName = employee.fields['name']?.toString();
      }

      final allocationsByBatch = <String, int>{};
      final batchOwnerById = <String, (String, String)>{};
      final baseByVariant = <String, int>{};
      final normalized = <SalesInvoiceLine>[];
      for (final line in lines) {
        if (line.quantity <= 0 ||
            line.conversionFactor <= 0 ||
            line.unitPrice < 0) {
          throw const AppException(
            'A sale item has an invalid quantity, unit conversion, or price.',
          );
        }
        final productDoc = await tx.get(
          FirebaseConstants.products,
          line.productId,
        );
        final product = productDoc.fields;
        if (!productDoc.exists ||
            product['tenantId'] != tenantId ||
            product['businessId'] != businessId ||
            product['status'] != 'ACTIVE' ||
            product['isDeleted'] == true) {
          throw const AppException(
            'A selected product is no longer active in this Business.',
          );
        }
        final variantDoc = await tx.get(
          FirebaseConstants.productVariants,
          line.variantId,
        );
        final variant = variantDoc.fields;
        if (!variantDoc.exists ||
            variant['tenantId'] != tenantId ||
            variant['businessId'] != businessId ||
            variant['productId'] != line.productId ||
            variant['status'] != 'ACTIVE') {
          throw const AppException(
            'A selected product variant is no longer available in this Business.',
          );
        }
        final currentGstBps = _int(
          variant['defaultGstRateBps'] ?? variant['defaultGstRate'],
        );
        if (line.gstPercent != currentGstBps / 100) {
          throw const AppException(
            'The GST rate changed while this sale was open. Refresh the form.',
          );
        }
        final expectedBase = _roundHalfUp(
          line.quantity * line.conversionFactor,
          1000,
        );
        final currentConversionFactor =
            ((variant['baseQuantityPerCommercialUnit'] as num?) ?? 1) * 1000;
        final currentBaseUnit =
            (variant['baseUnitId'] ?? variant['unitId'] ?? 'UNIT').toString();
        final currentCommercialUnit =
            (variant['commercialUnitId'] ?? currentBaseUnit).toString();
        if (expectedBase <= 0 || expectedBase != line.baseQuantity) {
          throw const AppException(
            'The sale quantity no longer matches the variant conversion. Refresh the form.',
          );
        }
        if (line.conversionFactor != currentConversionFactor.round() ||
            line.baseUnitId != currentBaseUnit ||
            line.commercialUnitId != currentCommercialUnit) {
          throw const AppException(
            'The selected variant units changed while this sale was open. Refresh the form.',
          );
        }
        final placementDocs = await tx.query(FirebaseConstants.outletProducts, [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('outletId', 'EQUAL', outletId),
          FirestoreFilter('productId', 'EQUAL', line.productId),
        ]);
        final placed = placementDocs.any((document) {
          final placement = document.fields;
          if (placement['status'] != 'ACTIVE' ||
              placement['isActive'] == false) {
            return false;
          }
          final variantIds = placement['variantIds'];
          return variantIds is! List ||
              variantIds.map((e) => e.toString()).contains(line.variantId);
        });
        if (!placed) {
          throw const AppException(
            'This product is not assigned to the selected Outlet.',
          );
        }
        final allocated = line.batchAllocations.fold<int>(0, (sum, item) {
          if (item.batchId.trim().isEmpty || item.baseQuantity <= 0) {
            throw const AppException(
              'Every batch allocation must have a batch and a positive quantity.',
            );
          }
          allocationsByBatch.update(
            item.batchId,
            (v) => v + item.baseQuantity,
            ifAbsent: () => item.baseQuantity,
          );
          final owner = batchOwnerById[item.batchId];
          if (owner != null && owner != (line.productId, line.variantId)) {
            throw const AppException(
              'A batch cannot be allocated to a different product variant.',
            );
          }
          batchOwnerById[item.batchId] = (line.productId, line.variantId);
          return sum + item.baseQuantity;
        });
        if (line.batchAllocations
                .map((allocation) => allocation.batchId)
                .toSet()
                .length !=
            line.batchAllocations.length) {
          throw const AppException(
            'Select each batch once per invoice line and adjust its allocation quantity.',
          );
        }
        if (line.batchAllocations.isEmpty || allocated != line.baseQuantity) {
          throw const AppException(
            'Batch allocations must exactly equal the sale line base quantity.',
          );
        }
        baseByVariant.update(
          line.variantId,
          (v) => v + line.baseQuantity,
          ifAbsent: () => line.baseQuantity,
        );
        final taxableAmount = line.quantity * line.unitPrice;
        final taxAmount = _roundHalfUp(taxableAmount * currentGstBps, 10000);
        normalized.add(
          SalesInvoiceLine(
            invoiceLineId: line.invoiceLineId,
            productId: line.productId,
            variantId: line.variantId,
            productName:
                (product['productName'] ?? product['name'] ?? line.productName)
                    .toString(),
            variantName:
                (variant['variantName'] ?? variant['name'] ?? line.variantName)
                    .toString(),
            quantity: line.quantity,
            baseUnitId: currentBaseUnit,
            commercialUnitId: currentCommercialUnit,
            conversionFactor: currentConversionFactor.round(),
            baseQuantity: expectedBase,
            unitPrice: line.unitPrice,
            mrp: line.mrp,
            gstPercent: currentGstBps / 100,
            taxableAmount: taxableAmount,
            lineTotal: taxableAmount + taxAmount,
            batchAllocations: List.unmodifiable(line.batchAllocations),
          ),
        );
      }

      final availableByBatch = <String, int>{};
      final batchDocs = <String, FirestoreTransactionDocument>{};
      for (final batchId in allocationsByBatch.keys) {
        final batchDoc = await tx.get(
          FirebaseConstants.inventoryBatches,
          batchId,
        );
        final batch = batchDoc.fields;
        if (!batchDoc.exists ||
            batch['tenantId'] != tenantId ||
            batch['businessId'] != businessId ||
            batch['outletId'] != outletId ||
            batch['status'] != 'AVAILABLE') {
          throw const AppException(
            'A selected batch does not belong to this active Outlet.',
          );
        }
        final owner = batchOwnerById[batchId];
        if (owner == null ||
            owner.$1 != batch['productId'] ||
            owner.$2 != batch['variantId']) {
          throw const AppException(
            'A selected batch belongs to a different product variant.',
          );
        }
        final movementDocs = await tx.query(
          FirebaseConstants.inventoryBatchMovements,
          [
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
            FirestoreFilter('outletId', 'EQUAL', outletId),
            FirestoreFilter('batchId', 'EQUAL', batchId),
          ],
        );
        final movements = movementDocs
            .map((document) => document.fields)
            .where(
              (movement) =>
                  movement['status'] == 'POSTED' &&
                  movement['isDeleted'] != true,
            )
            .toList();
        final receiptBaseline = movements
            .where(
              (movement) =>
                  movement['movementType'] == 'PURCHASE_RECEIPT' &&
                  movement['direction'] == 'IN' &&
                  movement['referenceType'] == 'GOODS_RECEIPT',
            )
            .fold<int>(0, (sum, movement) => sum + _int(movement['quantity']));
        final correctionIns = movements
            .where(
              (movement) =>
                  movement['movementType'] == 'PURCHASE_CORRECTION_IN' &&
                  movement['direction'] == 'IN',
            )
            .fold<int>(0, (sum, movement) => sum + _int(movement['quantity']));
        final correctionOuts = movements
            .where(
              (movement) =>
                  movement['movementType'] == 'PURCHASE_CORRECTION_OUT' &&
                  movement['direction'] == 'OUT',
            )
            .fold<int>(0, (sum, movement) => sum + _int(movement['quantity']));
        final received = _int(batch['receivedQty']);
        if (received <= 0 ||
            receiptBaseline + correctionIns - correctionOuts != received) {
          throw const AppException(
            'This batch does not have verified movement-ledger coverage and cannot be used for strict allocation yet.',
          );
        }
        final derived = movements.fold<int>(0, (sum, movement) {
          final quantity = _int(movement['quantity']);
          if (movement['direction'] == 'IN') return sum + quantity;
          if (movement['direction'] == 'OUT') return sum - quantity;
          return sum;
        });
        if (derived < 0 || derived != _int(batch['availableQty'])) {
          throw const AppException(
            'Batch ledger availability does not match the local batch balance. Refresh inventory and retry.',
          );
        }
        if (allocationsByBatch[batchId]! > derived) {
          throw const AppException(
            'Allocated quantity exceeds the trusted available quantity in a selected batch.',
          );
        }
        availableByBatch[batchId] = derived;
        batchDocs[batchId] = batchDoc;
      }

      final stockIds = <String, String>{};
      final stockDocs = <String, FirestoreTransactionDocument>{};
      for (final variantId in baseByVariant.keys) {
        final id = '${tenantId}_${outletId}_$variantId';
        final stock = await tx.get(FirebaseConstants.stockBalances, id);
        if (!stock.exists ||
            stock.fields['tenantId'] != tenantId ||
            stock.fields['businessId'] != businessId ||
            stock.fields['outletId'] != outletId ||
            _int(stock.fields['quantityOnHand']) < baseByVariant[variantId]!) {
          throw const AppException(
            'Insufficient outlet stock to post this sale.',
          );
        }
        stockIds[variantId] = id;
        stockDocs[variantId] = stock;
      }

      // Purchase posting stores averageCost scaled per 1,000 base units. Reuse
      // that established valuation for the corresponding stock-out rows.
      final costByAllocation = <String, int>{};
      final costByVariant = <String, int>{};
      final averageCostByVariant = <String, int>{};
      for (final variantId in baseByVariant.keys) {
        final stock = stockDocs[variantId]!.fields;
        final currentValue = _int(stock['totalValue']);
        final averageCost = _int(stock['averageCost']);
        if (currentValue > 0 && averageCost <= 0) {
          throw const AppException(
            'Stock valuation is incomplete. Reconcile inventory value before posting this sale.',
          );
        }
        averageCostByVariant[variantId] = averageCost;
        final allocations = <(String, int)>[
          for (final line in normalized)
            if (line.variantId == variantId)
              for (final allocation in line.batchAllocations)
                (
                  saleCostKey(line.invoiceLineId, allocation.batchId),
                  allocation.baseQuantity,
                ),
        ];
        var assignedCost = 0;
        for (var i = 0; i < allocations.length; i++) {
          final (key, baseQuantity) = allocations[i];
          final lastAllocation = i == allocations.length - 1;
          final sellingAll =
              baseByVariant[variantId] == _int(stock['quantityOnHand']);
          final proportional = _roundHalfUp(averageCost * baseQuantity, 1000);
          final cost = sellingAll && lastAllocation
              ? currentValue - assignedCost
              : proportional.clamp(0, currentValue - assignedCost);
          costByAllocation[key] = cost;
          assignedCost += cost;
        }
        costByVariant[variantId] = assignedCost;
      }

      final sequenceId = '${tenantId}_${businessId}_${outletId}_INVOICE';
      final sequence = await tx.get(
        FirebaseConstants.documentSequences,
        sequenceId,
      );
      final existingInvoices = await tx.query(
        FirebaseConstants.invoices,
        _scope(tenantId, businessId, outletId),
      );
      var highest = 0;
      for (final document in existingInvoices) {
        final match = RegExp(r'^INV-(\d+)$')
            .firstMatch(document.fields['invoiceNumber']?.toString() ?? '');
        final value = int.tryParse(match?.group(1) ?? '') ?? 0;
        if (value > highest) highest = value;
      }
      final nextNumber = sequence.exists
          ? (_int(sequence.fields['nextNumber']) > highest
                ? _int(sequence.fields['nextNumber'])
                : highest + 1)
          : highest + 1;
      invoiceNumber = 'INV-${nextNumber.toString().padLeft(6, '0')}';
      final outletStateDoc = await tx.get(FirebaseConstants.outlets, outletId);
      final outletState = _stateCode(
        outletStateDoc.fields['gstState'],
        outletStateDoc.fields['gstin'],
      );
      var customerState = outletState;
      if (customerId != null) {
        final customerDoc = await tx.get(
          FirebaseConstants.customers,
          customerId,
        );
        if (!customerDoc.exists ||
            customerDoc.fields['tenantId'] != tenantId ||
            customerDoc.fields['businessId'] != businessId ||
            customerDoc.fields['isActive'] == false ||
            (customerDoc.fields['status'] != null &&
                customerDoc.fields['status'] != 'ACTIVE') ||
            (customerDoc.fields['outletId'] != null &&
                customerDoc.fields['outletId'] != outletId)) {
          throw const AppException(
            'The selected customer is no longer available in this Outlet.',
          );
        }
        customerState = _stateCode(
          customerDoc.fields['gstState'] ?? customerDoc.fields['stateCode'],
          customerDoc.fields['gstin'],
        );
      }
      final intraState =
          outletState != null &&
          customerState != null &&
          outletState == customerState;
      if (normalized.any((line) => line.gstPercent > 0) &&
          (outletState == null || customerState == null)) {
        throw const AppException(
          'GST state is missing for the Outlet or Customer. Complete GST state details before posting this taxable sale.',
        );
      }
      final taxable = normalized.fold<int>(
        0,
        (sum, line) => sum + line.taxableAmount,
      );
      final tax = normalized.fold<int>(
        0,
        (sum, line) => sum + line.lineTotal - line.taxableAmount,
      );
      final halfTax = tax ~/ 2;
      final subtotal = normalized.fold<int>(
        0,
        (sum, line) => sum + line.quantity * line.unitPrice,
      );
      final grandTotal = taxable + tax;
      final invoice = {
        'invoiceId': invoiceId,
        'tenantId': tenantId,
        'businessId': businessId,
        'outletId': outletId,
        'customerId': customerId,
        'employeeId': chargeToEmployeeId,
        'chargeType': chargeToEmployeeId == null ? 'CUSTOMER' : 'STAFF_KHATA',
        'customerName': chargeToEmployeeId == null
            ? (customerName ?? 'Walk-in Customer')
            : (staffEmployeeName ?? 'Employee'),
        'invoiceNumber': invoiceNumber,
        'invoiceDate': invoiceDate.toUtc(),
        'status': 'POSTED',
        'subtotal': subtotal,
        'discount': 0,
        'taxableAmount': taxable,
        'cgst': intraState ? halfTax : 0,
        'sgst': intraState ? tax - halfTax : 0,
        'igst': intraState ? 0 : tax,
        'taxType': intraState ? 'INTRA_STATE' : 'INTER_STATE',
        'grandTotal': grandTotal,
        'paidAmount': 0,
        'outstandingAmount': grandTotal,
        'paymentStatus': 'UNPAID',
        'items': normalized.map((line) => line.toData()).toList(),
        'createdByUid': actorUid,
        'postingFingerprint': postingFingerprint,
        'createdAt': now,
        'updatedAt': now,
      };
      tx.create(FirebaseConstants.invoices, invoiceId, invoice);
      if (chargeToEmployeeId != null) {
        final purchaseId = 'SKH-POS-$invoiceId';
        tx.create(FirebaseConstants.staffKhataTransactions, purchaseId, {
          'recordId': purchaseId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'employeeId': chargeToEmployeeId,
          'transactionType': 'STORE_PURCHASE',
          'amountPaise': grandTotal,
          'paymentMode': 'NON_CASH',
          'transactionDate': invoiceDate.toUtc().toIso8601String(),
          'referenceType': 'INVOICE',
          'referenceId': invoiceId,
          'requestId': invoiceId,
          'status': 'POSTED',
          'createdBy': actorUid,
          'createdAt': now,
        });
      }
      final sequenceFields = {
        'tenantId': tenantId,
        'businessId': businessId,
        'sequenceType': 'INVOICE',
        'prefix': 'INV',
        'padding': 6,
        'nextNumber': nextNumber + 1,
        if (!sequence.exists) 'createdAt': now,
        'updatedAt': now,
      };
      if (sequence.exists) {
        tx.update(
          FirebaseConstants.documentSequences,
          sequenceId,
          sequenceFields,
          updateTime: sequence.updateTime,
        );
      } else {
        tx.create(
          FirebaseConstants.documentSequences,
          sequenceId,
          sequenceFields,
        );
      }

      for (final line in normalized) {
        for (final allocation in line.batchAllocations) {
          final batch = batchDocs[allocation.batchId]!.fields;
          final available = availableByBatch[allocation.batchId]!;
          final allocatedTotal = allocationsByBatch[allocation.batchId]!;
          final batchMovement = InventoryBatchMovementModel(
            movementId: saleMovementId(
              invoiceId,
              line.invoiceLineId,
              allocation.batchId,
            ),
            tenantId: tenantId,
            businessId: businessId,
            outletId: outletId,
            batchId: allocation.batchId,
            productId: line.productId,
            variantId: line.variantId,
            movementType: 'SALE',
            quantity: allocation.baseQuantity,
            direction: 'OUT',
            referenceType: 'INVOICE',
            referenceId: invoiceId,
            referenceLineId: line.invoiceLineId,
            reason: 'Manual batch allocation for posted sale.',
            createdByUid: actorUid,
            occurredAt: now,
            status: 'POSTED',
            createdAt: now,
            updatedAt: now,
          );
          final duplicateMovement = await tx.get(
            FirebaseConstants.inventoryBatchMovements,
            batchMovement.movementId,
          );
          if (duplicateMovement.exists) {
            throw const AppException(
              'This sale batch movement already exists.',
            );
          }
          tx.create(
            FirebaseConstants.inventoryBatchMovements,
            batchMovement.movementId,
            batchMovement.toData(),
          );
          final transactionId = saleInventoryTransactionId(
            invoiceId,
            line.invoiceLineId,
            allocation.batchId,
          );
          tx.create(FirebaseConstants.inventoryTransactions, transactionId, {
            'inventoryTransactionId': transactionId,
            'tenantId': tenantId,
            'businessId': businessId,
            'outletId': outletId,
            'locationType': batch['storageType'] ?? 'OUTLET',
            'locationId': batch['storageLocationId'] ?? outletId,
            'rackId': batch['rackId'],
            'productId': line.productId,
            'variantId': line.variantId,
            'batchId': allocation.batchId,
            'transactionType': 'SALE',
            'sourceType': 'INVOICE',
            'sourceId': invoiceId,
            'sourceItemId': line.invoiceLineId,
            'direction': 'OUT',
            'quantity': allocation.baseQuantity,
            'baseQuantity': allocation.baseQuantity,
            'unitId': line.baseUnitId,
            'commercialUnitId': line.commercialUnitId,
            'commercialQuantity':
                allocation.baseQuantity / line.conversionFactor * 1000,
            'conversionFactor': line.conversionFactor,
            'unitCost': averageCostByVariant[line.variantId] ?? 0,
            'totalCost':
                costByAllocation[saleCostKey(
                  line.invoiceLineId,
                  allocation.batchId,
                )] ??
                0,
            'isReversal': false,
            'reversalOfId': null,
            'createdBy': actorUid,
            'createdAt': now,
          });
          if (allocatedTotal > available) {
            throw const AppException(
              'Batch allocation exceeds trusted availability.',
            );
          }
        }
      }
      for (final entry in allocationsByBatch.entries) {
        final old = batchDocs[entry.key]!;
        final next = availableByBatch[entry.key]! - entry.value;
        tx.update(FirebaseConstants.inventoryBatches, entry.key, {
          'availableQty': next,
          'status': next == 0 ? 'DEPLETED' : 'AVAILABLE',
          'updatedAt': now,
        }, updateTime: old.updateTime);
      }
      for (final entry in baseByVariant.entries) {
        final old = stockDocs[entry.key]!;
        final oldQty = _int(old.fields['quantityOnHand']);
        final oldValue = _int(old.fields['totalValue']);
        final sold = entry.value;
        final nextQty = oldQty - sold;
        final costOut = costByVariant[entry.key] ?? 0;
        final nextValue = oldValue - costOut;
        tx.update(FirebaseConstants.stockBalances, stockIds[entry.key]!, {
          'quantityOnHand': nextQty,
          'totalValue': nextValue,
          'averageCost': nextQty == 0
              ? 0
              : _roundHalfUp(nextValue * 1000, nextQty),
          'lastInventoryTransactionId': saleInventoryTransactionId(
            invoiceId,
            'VARIANT',
            entry.key,
          ),
          'updatedAt': now,
        }, updateTime: old.updateTime);
      }
    }, idToken: token);
    return invoiceId;
  }

  static String saleMovementId(
    String invoiceId,
    String lineId,
    String batchId,
  ) => 'BATCH_MOVEMENT_SALE_${invoiceId}_${lineId}_$batchId';
  static String saleInventoryTransactionId(
    String invoiceId,
    String lineId,
    String batchId,
  ) => 'SALE_${invoiceId}_${lineId}_$batchId';

  static String saleCostKey(String lineId, String batchId) =>
      '$lineId::$batchId';

  static int _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
  static int _roundHalfUp(int numerator, int denominator) =>
      denominator <= 0 ? 0 : (numerator + denominator ~/ 2) ~/ denominator;
  static String? _stateCode(dynamic rawState, dynamic rawGstin) {
    final state = rawState?.toString().trim();
    if (state != null && state.isNotEmpty) return state.toUpperCase();
    final gstin = rawGstin?.toString().trim() ?? '';
    if (gstin.length >= 2) return gstin.substring(0, 2);
    return null;
  }

  static List<FirestoreFilter> _scope(
    String tenantId,
    String businessId,
    String outletId,
  ) => [
    FirestoreFilter('tenantId', 'EQUAL', tenantId),
    FirestoreFilter('businessId', 'EQUAL', businessId),
    FirestoreFilter('outletId', 'EQUAL', outletId),
  ];
}

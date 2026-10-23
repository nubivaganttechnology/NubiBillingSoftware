import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../domain/billing/bill_calculator.dart';
import '../../domain/billing/billing_models.dart';
import '../../domain/billing/invoice_number.dart';
import '../local/local_data_source.dart';
import '../models/invoice_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_transaction_service.dart';
import '../services/firestore_value_codec.dart';
import '../services/offline_firestore_service.dart';

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

Future<({FirestoreTransactionDocument doc, String id})> _resolveStockBalance(
  FirestoreTransactionContext tx, {
  required String tenantId,
  required String businessId,
  required String outletId,
  required String variantId,
}) async {
  final canonicalId = '${tenantId}_${outletId}_$variantId';
  var stock = await tx.get(FirebaseConstants.stockBalances, canonicalId);
  if (stock.exists) return (doc: stock, id: canonicalId);

  final legacyId =
      '${tenantId}_${businessId}_OUTLET_${outletId}_DIRECT_$variantId';
  stock = await tx.get(FirebaseConstants.stockBalances, legacyId);
  if (stock.exists) return (doc: stock, id: legacyId);

  return (
    doc: await tx.get(FirebaseConstants.stockBalances, canonicalId),
    id: canonicalId,
  );
}

class BillingRepository {
  BillingRepository(this.transactions);
  final FirestoreTransactionService transactions;

  /// Authoritative server transaction runner for online-only financial operations.
  FirestoreTransactionService get serverTransactions {
    if (transactions is OfflineFirestoreService) {
      return (transactions as OfflineFirestoreService).serverTransactions;
    }
    return transactions;
  }

  Future<void> settle({
    required String invoiceId,
    required String customerId,
    required int amountPaise,
    required String mode,
    required DateTime paymentAt,
    DateTime? nextDueDate,
    String? collectedAtOutletId,
    required String token,
  }) async {
    if (amountPaise <= 0) throw const AppException('Enter a payment amount.');
    late Map<String, dynamic> invoiceUpdatesToCache;
    late Map<String, dynamic> rawInvoiceFields;
    late Map<String, dynamic> rawCustomerFields;
    late int customerDueToCache;
    late int appliedToCache;
    late int customerAdvanceToCache;
    late int excessToCache;

    await serverTransactions.runAtomicOperation((tx) async {
      final invoice = await tx.get(FirebaseConstants.invoices, invoiceId);
      final customer = await tx.get(FirebaseConstants.customers, customerId);
      if (!invoice.exists || !customer.exists) {
        throw const AppException('The invoice or customer no longer exists.');
      }
      final due = (invoice.fields['dueAmount'] as num?)?.toInt() ?? 0;
      if (due <= 0) throw const AppException('This bill is already paid.');
      final applied = amountPaise > due ? due : amountPaise;
      final excess = amountPaise - applied;
      final customerDue = (customer.fields['duePaise'] as num?)?.toInt() ?? 0;
      final customerAdvance =
          (customer.fields['advancePaise'] as num?)?.toInt() ?? 0;
      final remaining = due - applied;
      final invoiceUpdates = <String, dynamic>{
        'dueAmount': remaining,
        'paidPaise':
            ((invoice.fields['paidPaise'] as num?)?.toInt() ?? 0) + applied,
        'status': remaining == 0 ? 'PAID' : 'PARTIALLY_PAID',
      };
      if (remaining == 0) {
        invoiceUpdates['dueDate'] = null;
      } else if (nextDueDate != null) {
        invoiceUpdates['dueDate'] = _dateOnly(nextDueDate);
      }
      tx.update(
        FirebaseConstants.invoices,
        invoiceId,
        invoiceUpdates,
        updateTime: invoice.updateTime,
      );
      tx.update(FirebaseConstants.customers, customerId, {
        'duePaise': customerDue - applied,
        'advancePaise': customerAdvance + excess,
      }, updateTime: customer.updateTime);

      rawInvoiceFields = Map<String, dynamic>.from(invoice.fields);
      rawCustomerFields = Map<String, dynamic>.from(customer.fields);
      invoiceUpdatesToCache = invoiceUpdates;
      customerDueToCache = customerDue;
      appliedToCache = applied;
      customerAdvanceToCache = customerAdvance;
      excessToCache = excess;

      final paymentId = IdGenerator.create('PAY');
      final ledgerId = IdGenerator.create('LED');
      final bid = invoice.fields['businessId'] as String? ?? '';
      final tid = invoice.fields['tenantId'] as String? ?? '';
      final oid = invoice.fields['outletId'] as String? ?? '';
      final collectingOutlet =
          (collectedAtOutletId != null && collectedAtOutletId.isNotEmpty)
              ? collectedAtOutletId
              : oid;

      tx.create(FirebaseConstants.payments, paymentId, {
        'paymentId': paymentId,
        'invoiceId': invoiceId,
        'customerId': customerId,
        'businessId': bid,
        'tenantId': tid,
        'outletId': oid,
        'collectedAtOutletId': collectingOutlet,
        'mode': mode,
        'paymentMethod': mode,
        'amountPaise': amountPaise,
        'appliedPaise': applied,
        'excessAdvancePaise': excess,
        'createdAt': paymentAt.toUtc().toIso8601String(),
        'immutable': true,
      });
      tx.create(
        FirebaseConstants.customerLedgerEntries,
        ledgerId,
        {
          'transactionId': ledgerId,
          'businessId': bid,
          'tenantId': tid,
          'outletId': collectingOutlet,
          'originalOutletId': oid,
          'invoiceId': invoiceId,
          'customerId': customerId,
          'transactionType': 'PAYMENT',
          'amountPaise': amountPaise,
          'debitPaise': 0,
          'creditPaise': applied,
          'advanceCreditPaise': excess,
          'paymentId': paymentId,
          'createdAt': paymentAt.toUtc().toIso8601String(),
          'status': 'POSTED',
          'immutable': true,
        },
      );
    }, idToken: token);

    // Update local read-only cache if available (as SYNCED)
    if (transactions is OfflineFirestoreService) {
      final local = (transactions as OfflineFirestoreService).localDataSource;
      if (local != null) {
        try {
          await local.db.transaction((localTx) async {
            final nowIso = DateTime.now().toUtc().toIso8601String();
            final updatedInv = {
              ...rawInvoiceFields,
              ...invoiceUpdatesToCache,
              'updatedAt': nowIso,
            };
            await LocalDataSource.put(localTx, FirebaseConstants.invoices, {
              'remoteId': invoiceId,
              'payloadJson': jsonEncode(
                FirestoreValueCodec.encodeFields(updatedInv),
              ),
              ...LocalDataSource.scopeColumns(updatedInv),
              'syncStatus': 'SYNCED',
              'localUpdatedAt': LocalDataSource.now(),
              'isDeleted': 0,
            });

            final updatedCust = {
              ...rawCustomerFields,
              'duePaise': (customerDueToCache - appliedToCache).clamp(0, 1 << 50),
              'advancePaise': customerAdvanceToCache + excessToCache,
              'updatedAt': nowIso,
            };
            await LocalDataSource.put(localTx, FirebaseConstants.customers, {
              'remoteId': customerId,
              'payloadJson': jsonEncode(
                FirestoreValueCodec.encodeFields(updatedCust),
              ),
              ...LocalDataSource.scopeColumns(updatedCust),
              'syncStatus': 'SYNCED',
              'localUpdatedAt': LocalDataSource.now(),
              'isDeleted': 0,
            });
          });
        } catch (e) {
          debugPrint('Failed to update local cache after billing settle: $e');
        }
      }
    }
  }

  Future<void> updateDueDate({
    required String invoiceId,
    required DateTime? dueDate,
    required String token,
  }) async {
    await serverTransactions.runAtomicOperation((tx) async {
      final invoice = await tx.get(FirebaseConstants.invoices, invoiceId);
      if (!invoice.exists) {
        throw const AppException('The invoice no longer exists.');
      }
      tx.update(FirebaseConstants.invoices, invoiceId, {
        'dueDate': dueDate == null ? null : _dateOnly(dueDate),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }, updateTime: invoice.updateTime);
    }, idToken: token);
  }

  Future<void> cancel({
    required String invoiceId,
    required String actorUid,
    required String reason,
    required String token,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const AppException('Enter a cancellation reason.');
    }
    await serverTransactions.runAtomicOperation((tx) async {
      final invoice = await tx.get(FirebaseConstants.invoices, invoiceId);
      if (!invoice.exists) throw const AppException('Bill no longer exists.');
      final status = invoice.fields['status'] as String? ?? '';
      if (status == 'CANCELLED') {
        throw const AppException('This bill is already cancelled.');
      }
      if (status == 'RETURN') {
        throw const AppException('Returned bills cannot be cancelled.');
      }

      final tenantId = invoice.fields['tenantId'] as String? ?? '';
      final businessId = invoice.fields['businessId'] as String? ?? '';
      final outletId = invoice.fields['outletId'] as String? ?? '';
      final customerId = invoice.fields['customerId'] as String?;
      final paidPaise = (invoice.fields['paidPaise'] as num?)?.toInt() ?? 0;
      final duePaise = (invoice.fields['dueAmount'] as num?)?.toInt() ?? 0;
      final advancePaise =
          (invoice.fields['advancePaise'] as num?)?.toInt() ?? 0;

      final items = <FirestoreTransactionDocument>[];
      for (var index = 0; index < 1000; index++) {
        final item = await tx.get(
          FirebaseConstants.invoiceItems,
          '${invoiceId}_$index',
        );
        if (!item.exists) break;
        items.add(item);
      }
      if (items.isEmpty) {
        throw const AppException('Bill items could not be found.');
      }

      final stockReads = <String, FirestoreTransactionDocument>{};
      final stockIds = <String, String>{};
      for (final item in items) {
        final variantId = item.fields['variantId'] as String?;
        final quantity = (item.fields['quantity'] as num?)?.toInt() ?? 0;
        if (variantId == null || quantity <= 0) continue;
        if (!stockReads.containsKey(variantId)) {
          final res = await _resolveStockBalance(
            tx,
            tenantId: tenantId,
            businessId: businessId,
            outletId: outletId,
            variantId: variantId,
          );
          stockReads[variantId] = res.doc;
          stockIds[variantId] = res.id;
        }
      }

      FirestoreTransactionDocument? customer;
      FirestoreTransactionDocument? balance;
      String? balanceId;
      if (customerId != null) {
        customer = await tx.get(FirebaseConstants.customers, customerId);
        balanceId = '${businessId}_${outletId}_$customerId';
        balance = await tx.get(FirebaseConstants.customerBalances, balanceId);
      }

      tx.update(FirebaseConstants.invoices, invoiceId, {
        'status': 'CANCELLED',
        'cancelledAt': DateTime.now().toUtc().toIso8601String(),
        'cancelledBy': actorUid,
        'cancellationReason': trimmedReason,
        'dueAmount': 0,
      }, updateTime: invoice.updateTime);

      final currentOnHand = <String, int>{
        for (final entry in stockReads.entries)
          entry.key:
              (entry.value.fields['quantityOnHand'] as num?)?.toInt() ?? 0,
      };
      for (final item in items) {
        final variantId = item.fields['variantId'] as String?;
        final quantity = (item.fields['quantity'] as num?)?.toInt() ?? 0;
        if (variantId == null || quantity <= 0) continue;
        final stock = stockReads[variantId]!;
        final stockId = stockIds[variantId]!;
        if (!stock.exists) {
          throw const AppException('Stock record is missing for this bill.');
        }
        final onHand = currentOnHand[variantId] ?? 0;
        final nextOnHand = onHand + quantity;
        currentOnHand[variantId] = nextOnHand;
        tx.update(FirebaseConstants.stockBalances, stockId, {
          ...stock.fields,
          'quantityOnHand': nextOnHand,
        }, updateTime: stock.updateTime);
      }

      if (customerId != null) {
        final oldDue =
            ((customer?.fields['duePaise'] as num?)?.toInt() ??
            (balance?.fields['duePaise'] as num?)?.toInt() ??
            0);
        final oldAdvance =
            ((customer?.fields['advancePaise'] as num?)?.toInt() ??
            (balance?.fields['advancePaise'] as num?)?.toInt() ??
            0);
        final nextDue = oldDue - duePaise;
        final nextAdvance = oldAdvance + advancePaise;
        if (nextDue < 0) {
          throw const AppException(
            'Customer due is inconsistent; cancellation was not applied.',
          );
        }
        final values = {'duePaise': nextDue, 'advancePaise': nextAdvance};
        if (customer?.exists == true) {
          tx.update(
            FirebaseConstants.customers,
            customerId,
            values,
            updateTime: customer!.updateTime,
          );
        }
        if (balance?.exists == true) {
          tx.update(
            FirebaseConstants.customerBalances,
            balanceId!,
            values,
            updateTime: balance!.updateTime,
          );
        }
        if (duePaise > 0 || advancePaise > 0) {
          final ledgerId = IdGenerator.create('LED');
          tx.create(
            FirebaseConstants.customerLedgerEntries,
            ledgerId,
            {
              'transactionId': ledgerId,
              'businessId': businessId,
              'tenantId': tenantId,
              'outletId': outletId,
              'customerId': customerId,
              'invoiceId': invoiceId,
              'transactionType': 'ADJUSTMENT',
              'amountPaise': duePaise + advancePaise,
              'debitPaise': advancePaise,
              'creditPaise': duePaise,
              'entryType': 'CANCELLATION_REVERSAL',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
              'createdBy': actorUid,
              'status': 'POSTED',
              'immutable': true,
            },
          );
        }
      }
      if (paidPaise > 0) {
        tx.create(FirebaseConstants.payments, IdGenerator.create('PAY'), {
          'invoiceId': invoiceId,
          'customerId': customerId,
          'mode': 'REVERSAL',
          'amountPaise': -paidPaise,
          'reversalOfInvoice': invoiceId,
          'reason': trimmedReason,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'immutable': true,
        });
      }
    }, idToken: token);
  }

  Future<FinalizeBillResult> finalize(
    FinalizeBillRequest request, {
    required String token,
  }) async {
    if (request.lines.isEmpty) {
      throw const AppException('Add an item before saving.');
    }
    final calculated = const BillCalculator().calculate(
      lines: request.lines,
      taxMode: request.taxMode,
      taxStructure: request.taxStructure,
    );
    final invoiceId = 'REQ_${request.requestId}';
    final runner = serverTransactions;
    return runner.runAtomicOperation((tx) async {
      final existing = await tx.get(FirebaseConstants.invoices, invoiceId);
      if (existing.exists) {
        return FinalizeBillResult(
          invoiceId: invoiceId,
          invoiceNumber: existing.fields['invoiceNumber'] as String? ?? '',
          existing: true,
        );
      }

      final sequenceId =
          '${request.businessId}_${InvoiceNumber.financialYearLabel(request.createdAt)}_SALES_INVOICE';
      final sequence = await tx.get(
        FirebaseConstants.documentSequences,
        sequenceId,
      );
      final nextSequence =
          ((sequence.fields['sequence'] as num?)?.toInt() ?? 0) + 1;
      final invoiceNumber = InvoiceNumber.format(
        businessShortCode: request.businessShortCode,
        date: request.createdAt,
        sequence: nextSequence,
      );

      final customer = request.customerId == null
          ? null
          : await tx.get(FirebaseConstants.customers, request.customerId!);
      final balanceId = request.customerId == null
          ? null
          : '${request.businessId}_${request.outletId}_${request.customerId}';
      final balance = balanceId == null
          ? null
          : await tx.get(FirebaseConstants.customerBalances, balanceId);
      final stockReads = <String, FirestoreTransactionDocument>{};
      final stockIds = <String, String>{};
      for (final line in calculated.lines) {
        if (!line.input.trackStock) continue;
        final variantId = line.input.variantId;
        if (!stockReads.containsKey(variantId)) {
          final res = await _resolveStockBalance(
            tx,
            tenantId: request.tenantId,
            businessId: request.businessId,
            outletId: request.outletId,
            variantId: variantId,
          );
          stockReads[variantId] = res.doc;
          stockIds[variantId] = res.id;
        }
      }

      final oldDue =
          ((customer?.fields['duePaise'] as num?)?.toInt() ??
          (balance?.fields['duePaise'] as num?)?.toInt() ??
          0);
      final oldAdvance =
          ((customer?.fields['advancePaise'] as num?)?.toInt() ??
          (balance?.fields['advancePaise'] as num?)?.toInt() ??
          0);
      var newDue = oldDue + request.duePaise;
      var newAdvance = oldAdvance - request.advancePaise;
      if (newAdvance < 0) {
        throw const AppException('Customer advance is insufficient.');
      }

      final totalPaidOnBill = request.cashPaise + request.upiPaise;
      final billTotal = calculated.grandTotalPaise;
      final excessPaise =
          (totalPaidOnBill > billTotal && request.customerId != null)
          ? (totalPaidOnBill - billTotal)
          : 0;

      if (excessPaise > 0) {
        if (newDue > 0) {
          if (excessPaise >= newDue) {
            final remainingAdvance = excessPaise - newDue;
            newDue = 0;
            newAdvance += remainingAdvance;
          } else {
            newDue -= excessPaise;
          }
        } else {
          newAdvance += excessPaise;
        }
      }

      final invoiceFields = <String, dynamic>{
        'invoiceId': invoiceId,
        'id': invoiceId,
        'requestId': request.requestId,
        'invoiceNumber': invoiceNumber,
        'tenantId': request.tenantId,
        'businessId': request.businessId,
        'outletId': request.outletId,
        'cashierUid': request.cashierUid,
        'createdAt': request.createdAt.toUtc().toIso8601String(),
        'customerId': request.customerId,
        'customerName': request.customerName,
        'customerNameLower': request.customerName?.toLowerCase(),
        'customerPhone': request.customerPhone,
        'customerGstin': request.customerGstin,
        'customerStateCode': request.customerStateCode,
        'customerAddress': request.customerAddress,
        'customerType': request.customerType,
        'invoiceGstType': (request.customerGstin != null &&
                request.customerGstin!.trim().isNotEmpty)
            ? 'B2B'
            : 'B2C',
        'subtotalPaise': calculated.subtotalPaise,
        'discountPaise': calculated.totalDiscountPaise,
        'taxablePaise': calculated.taxableTotalPaise,
        'cgstPaise': calculated.cgstPaise,
        'sgstPaise': calculated.sgstPaise,
        'igstPaise': calculated.igstPaise,
        'roundOffPaise': calculated.roundOffPaise,
        'grandTotalPaise': calculated.grandTotalPaise,
        'paidPaise':
            request.cashPaise + request.upiPaise + request.advancePaise,
        'advancePaise': request.advancePaise,
        'dueAmount': request.duePaise,
        'dueDate': request.dueDate == null ? null : _dateOnly(request.dueDate!),
        'status': request.duePaise == 0 ? 'PAID' : 'PENDING',
        'taxMode': request.taxMode.name,
        'paymentMode':
            request.paymentMode?.name ??
            (request.duePaise > 0
                ? 'udhaar'
                : (request.cashPaise > 0 && request.upiPaise > 0
                      ? 'split'
                      : (request.upiPaise > 0 ? 'upi' : 'cash'))),
        'items': calculated.lines
            .map(
              (l) => {
                'variantId': l.input.variantId,
                'sku': l.input.sku,
                'name': l.input.name,
                'productName': l.input.name,
                'hsn': l.input.hsn,
                'quantity': l.input.quantity,
                'quantityBase': l.input.quantityBase,
                'unit': l.input.unit,
                'unitPricePaise': l.input.unitPricePaise,
                'taxablePaise': l.taxablePaise,
                'taxableAmount': l.taxablePaise,
                'gstRateBps': l.input.gstRateBps,
                'taxPaise': l.taxPaise,
                'taxAmount': l.taxPaise,
                'cgstPaise': (l.taxPaise ~/ 2),
                'sgstPaise': (l.taxPaise - (l.taxPaise ~/ 2)),
                'totalPaise': l.lineTotalPaise,
                'totalAmount': l.lineTotalPaise,
              },
            )
            .toList(),
      };
      tx.create(FirebaseConstants.invoices, invoiceId, invoiceFields);
      for (var index = 0; index < calculated.lines.length; index++) {
        final line = calculated.lines[index];
        tx.create(FirebaseConstants.invoiceItems, '${invoiceId}_$index', {
          'invoiceId': invoiceId,
          'tenantId': request.tenantId,
          'businessId': request.businessId,
          'outletId': request.outletId,
          'variantId': line.input.variantId,
          'sku': line.input.sku,
          'name': line.input.name,
          'productName': line.input.name,
          'hsn': line.input.hsn,
          'quantity': line.input.quantity,
          'quantityBase': line.input.quantityBase,
          'unit': line.input.unit,
          'conversionFactor': line.input.conversionFactor,
          'trackStock': line.input.trackStock,
          'unitPricePaise': line.input.unitPricePaise,
          'discountPaise': line.input.discountPaise,
          'taxablePaise': line.taxablePaise,
          'gstRateBps': line.input.gstRateBps,
          'taxPaise': line.taxPaise,
          'cgstPaise': (line.taxPaise ~/ 2),
          'sgstPaise': (line.taxPaise - (line.taxPaise ~/ 2)),
          'totalPaise': line.lineTotalPaise,
          'lineTotalPaise': line.lineTotalPaise,
        });
      }
      final currentStockOnHand = <String, int>{
        for (final entry in stockReads.entries)
          entry.key:
              (entry.value.fields['quantityOnHand'] as num?)?.toInt() ?? 0,
      };
      for (final line in calculated.lines) {
        if (!line.input.trackStock) continue;
        final variantId = line.input.variantId;
        final stock = stockReads[variantId]!;
        final stockId = stockIds[variantId]!;
        final quantity = currentStockOnHand[variantId] ?? 0;
        final deduction = (quantity >= 1000 || line.input.conversionFactor == 1)
            ? line.input.quantityBase * 1000
            : line.input.quantityBase;
        if (quantity < deduction) {
          throw AppException(
            'Insufficient stock for "${line.input.name}". Available: ${quantity ~/ 1000}, Requested: ${line.input.quantity}.',
          );
        }
        final balanceAfter = quantity - deduction;
        currentStockOnHand[variantId] = balanceAfter;
        tx.update(FirebaseConstants.stockBalances, stockId, {
          ...stock.fields,
          'quantityOnHand': balanceAfter,
          'updatedAt': request.createdAt.toUtc().toIso8601String(),
        }, updateTime: stock.updateTime);
        tx.create(FirebaseConstants.stockMovements, IdGenerator.create('STM'), {
          'tenantId': request.tenantId,
          'businessId': request.businessId,
          'outletId': request.outletId,
          'productId': line.input.variantId,
          'type': 'SALE',
          'qtyBase': deduction,
          'reason': 'Sale $invoiceNumber',
          'referenceId': invoiceId,
          'userId': request.cashierUid,
          'createdAt': request.createdAt.toUtc().toIso8601String(),
          'balanceAfter': balanceAfter,
          'immutable': true,
        });

        // Decrement inventory batch if tracked
        String? targetBatchId = line.input.batchId;
        FirestoreTransactionDocument? batchDoc;
        if (targetBatchId != null && targetBatchId.isNotEmpty) {
          batchDoc = await tx.get(FirebaseConstants.inventoryBatches, targetBatchId);
          if (!batchDoc.exists) batchDoc = null;
        }
        if (batchDoc == null) {
          final batchDocs = await tx.query(FirebaseConstants.inventoryBatches, [
            FirestoreFilter('tenantId', 'EQUAL', request.tenantId),
            FirestoreFilter('outletId', 'EQUAL', request.outletId),
            FirestoreFilter('variantId', 'EQUAL', variantId),
          ]);
          final active = batchDocs.where((d) {
            final st = (d.fields['status'] as String? ?? '').toUpperCase();
            final qty = (d.fields['availableQty'] as num?)?.toInt() ?? 0;
            return !const {'DELETED', 'VOID', 'DEPLETED'}.contains(st) && qty > 0;
          }).toList();
          if (active.isNotEmpty) {
            final priceMatch = active.where((d) {
              final sp = (d.fields['sellingPrice'] as num?)?.toInt() ?? 0;
              return sp == line.input.unitPricePaise;
            }).firstOrNull;
            batchDoc = priceMatch ?? active.first;
            targetBatchId = batchDoc.id ?? batchDoc.fields['batchId'] as String?;
          }
        }
        if (batchDoc != null && batchDoc.exists && targetBatchId != null) {
          final curBatchQty = (batchDoc.fields['availableQty'] as num?)?.toInt() ?? 0;
          final nextBatchQty = (curBatchQty - deduction).clamp(0, 1 << 40);
          tx.update(FirebaseConstants.inventoryBatches, targetBatchId, {
            ...batchDoc.fields,
            'availableQty': nextBatchQty,
            'status': nextBatchQty == 0 ? 'DEPLETED' : 'AVAILABLE',
            'updatedAt': request.createdAt.toUtc().toIso8601String(),
          }, updateTime: batchDoc.updateTime);

          final ibmId = IdGenerator.create('IBM');
          tx.create(FirebaseConstants.inventoryBatchMovements, ibmId, {
            'movementId': ibmId,
            'tenantId': request.tenantId,
            'businessId': request.businessId,
            'outletId': request.outletId,
            'batchId': targetBatchId,
            'productId': variantId,
            'variantId': variantId,
            'movementType': 'SALE',
            'quantity': deduction,
            'direction': 'OUT',
            'referenceType': 'INVOICE',
            'referenceId': invoiceId,
            'reason': 'Sale $invoiceNumber',
            'createdByUid': request.cashierUid,
            'occurredAt': request.createdAt.toUtc().toIso8601String(),
            'status': 'POSTED',
            'createdAt': request.createdAt.toUtc().toIso8601String(),
            'immutable': true,
          });
        }
      }
      if (sequence.exists) {
        tx.update(FirebaseConstants.documentSequences, sequenceId, {
          'sequence': nextSequence,
          'businessId': request.businessId,
          'financialYear': InvoiceNumber.financialYearLabel(request.createdAt),
          'sequenceType': 'SALES_INVOICE',
        }, updateTime: sequence.updateTime);
      } else {
        tx.create(FirebaseConstants.documentSequences, sequenceId, {
          'businessId': request.businessId,
          'financialYear': InvoiceNumber.financialYearLabel(request.createdAt),
          'sequenceType': 'SALES_INVOICE',
          'sequence': nextSequence,
        });
      }
      for (final entry in [
        if (request.cashPaise > 0) ('CASH', request.cashPaise),
        if (request.upiPaise > 0) ('UPI', request.upiPaise),
        if (request.advancePaise > 0) ('ADVANCE', request.advancePaise),
      ]) {
        tx.create(FirebaseConstants.payments, IdGenerator.create('PAY'), {
          'invoiceId': invoiceId,
          'customerId': request.customerId,
          'mode': entry.$1,
          'amountPaise': entry.$2,
          'createdAt': request.createdAt.toUtc().toIso8601String(),
          'immutable': true,
        });
      }
      if (request.customerId != null) {
        final values = {'duePaise': newDue, 'advancePaise': newAdvance};
        if (customer?.exists == true) {
          tx.update(
            FirebaseConstants.customers,
            request.customerId!,
            values,
            updateTime: customer!.updateTime,
          );
        }
        if (balance?.exists == true) {
          tx.update(
            FirebaseConstants.customerBalances,
            balanceId!,
            values,
            updateTime: balance!.updateTime,
          );
        } else {
          tx.create(FirebaseConstants.customerBalances, balanceId!, {
            'tenantId': request.tenantId,
            'businessId': request.businessId,
            'outletId': request.outletId,
            'customerId': request.customerId,
            ...values,
          });
        }
        final ledgerEntryId = IdGenerator.create('LED');
        tx.create(
          FirebaseConstants.customerLedgerEntries,
          ledgerEntryId,
          {
            'transactionId': ledgerEntryId,
            'businessId': request.businessId,
            'tenantId': request.tenantId,
            'outletId': request.outletId,
            'customerId': request.customerId,
            'invoiceId': invoiceId,
            'transactionType': 'CREDIT_SALE',
            'amountPaise': request.duePaise,
            'debitPaise': request.duePaise,
            'creditPaise': request.advancePaise + excessPaise,
            if (excessPaise > 0) 'entryType': 'OVERPAYMENT_ADVANCE',
            'createdAt': request.createdAt.toUtc().toIso8601String(),
            'createdBy': request.cashierUid,
            'status': 'POSTED',
            'immutable': true,
          },
        );
      }
      return FinalizeBillResult(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        existing: false,
      );
    }, idToken: token);
  }

  Future<void> updateBill({
    required String invoiceId,
    required String? customerName,
    required String? customerPhone,
    required String? customerGstin,
    required DateTime? dueDate,
    required List<BillLineInput> lines,
    required BillingTaxMode taxMode,
    required TaxStructure taxStructure,
    required String token,
  }) async {
    if (lines.isEmpty) {
      throw const AppException('A bill must have at least one line item.');
    }
    final calculated = const BillCalculator().calculate(
      lines: lines,
      taxMode: taxMode,
      taxStructure: taxStructure,
    );

    await serverTransactions.runAtomicOperation((tx) async {
      final invoice = await tx.get(FirebaseConstants.invoices, invoiceId);
      if (!invoice.exists) throw const AppException('Bill no longer exists.');
      final status = invoice.fields['status'] as String? ?? '';
      if (status == 'CANCELLED') {
        throw const AppException('Cancelled bills cannot be edited.');
      }
      if (status == 'RETURN') {
        throw const AppException('Returned bills cannot be edited.');
      }

      final tenantId = invoice.fields['tenantId'] as String? ?? '';
      final businessId = invoice.fields['businessId'] as String? ?? '';
      final outletId = invoice.fields['outletId'] as String? ?? '';
      final customerId = invoice.fields['customerId'] as String?;
      final cashierUid = invoice.fields['cashierUid'] as String? ?? '';
      final invoiceNumber = invoice.fields['invoiceNumber'] as String? ?? '';
      final paidPaise = (invoice.fields['paidPaise'] as num?)?.toInt() ?? 0;
      final oldDuePaise = (invoice.fields['dueAmount'] as num?)?.toInt() ?? 0;

      final oldItems = <FirestoreTransactionDocument>[];
      for (var index = 0; index < 1000; index++) {
        final item = await tx.get(
          FirebaseConstants.invoiceItems,
          '${invoiceId}_$index',
        );
        if (!item.exists) break;
        oldItems.add(item);
      }

      final oldVariantBaseQty = <String, int>{};
      final oldTrackStock = <String, bool>{};
      for (final oldItem in oldItems) {
        final variantId = oldItem.fields['variantId'] as String?;
        final qtyBase =
            (oldItem.fields['quantityBase'] as num?)?.toInt() ??
            ((oldItem.fields['quantity'] as num?)?.toInt() ?? 0);
        final trackStock = oldItem.fields['trackStock'] as bool? ?? true;
        if (variantId != null) {
          oldVariantBaseQty[variantId] =
              (oldVariantBaseQty[variantId] ?? 0) + qtyBase;
          oldTrackStock[variantId] = trackStock;
        }
      }

      final newVariantBaseQty = <String, int>{};
      final newTrackStock = <String, bool>{};
      for (final line in calculated.lines) {
        final variantId = line.input.variantId;
        newVariantBaseQty[variantId] =
            (newVariantBaseQty[variantId] ?? 0) + line.input.quantityBase;
        newTrackStock[variantId] = line.input.trackStock;
      }

      final allVariants = <String>{
        ...oldVariantBaseQty.keys,
        ...newVariantBaseQty.keys,
      };
      final stockReads = <String, FirestoreTransactionDocument>{};
      final stockIds = <String, String>{};
      for (final variantId in allVariants) {
        final track =
            newTrackStock[variantId] ?? oldTrackStock[variantId] ?? true;
        if (!track) continue;
        if (!stockReads.containsKey(variantId)) {
          final res = await _resolveStockBalance(
            tx,
            tenantId: tenantId,
            businessId: businessId,
            outletId: outletId,
            variantId: variantId,
          );
          stockReads[variantId] = res.doc;
          stockIds[variantId] = res.id;
        }
      }

      FirestoreTransactionDocument? customer;
      FirestoreTransactionDocument? balance;
      String? balanceId;
      if (customerId != null) {
        customer = await tx.get(FirebaseConstants.customers, customerId);
        balanceId = '${businessId}_${outletId}_$customerId';
        balance = await tx.get(FirebaseConstants.customerBalances, balanceId);
      }

      final currentStockOnHand = <String, int>{
        for (final entry in stockReads.entries)
          entry.key:
              (entry.value.fields['quantityOnHand'] as num?)?.toInt() ?? 0,
      };

      for (final variantId in allVariants) {
        final track =
            newTrackStock[variantId] ?? oldTrackStock[variantId] ?? true;
        if (!track) continue;
        final stock = stockReads[variantId];
        final stockId = stockIds[variantId];
        if (stock == null || !stock.exists || stockId == null) continue;

        final oldQty = oldVariantBaseQty[variantId] ?? 0;
        final newQty = newVariantBaseQty[variantId] ?? 0;
        final netDeduction = newQty - oldQty;
        if (netDeduction == 0) continue;

        final onHand = currentStockOnHand[variantId] ?? 0;
        final scaledDeduction =
            (onHand >= 1000) ? netDeduction * 1000 : netDeduction;

        if (scaledDeduction > 0 && onHand < scaledDeduction) {
          throw AppException(
            'Insufficient stock for variant "$variantId". Available: ${onHand ~/ 1000}, Required: $netDeduction.',
          );
        }

        final balanceAfter = onHand - scaledDeduction;
        currentStockOnHand[variantId] = balanceAfter;
        tx.update(FirebaseConstants.stockBalances, stockId, {
          ...stock.fields,
          'quantityOnHand': balanceAfter,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }, updateTime: stock.updateTime);

        tx.create(FirebaseConstants.stockMovements, IdGenerator.create('STM'), {
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'productId': variantId,
          'type': netDeduction > 0 ? 'SALE_ADJUSTMENT' : 'RETURN_ADJUSTMENT',
          'qtyBase': netDeduction.abs(),
          'reason': 'Edit Bill $invoiceNumber',
          'referenceId': invoiceId,
          'userId': cashierUid,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'balanceAfter': balanceAfter,
          'immutable': true,
        });
      }

      final newGrandTotal = calculated.grandTotalPaise;
      final newDue = (newGrandTotal - paidPaise).clamp(0, newGrandTotal);
      final dueDelta = newDue - oldDuePaise;

      if (customerId != null && dueDelta != 0) {
        final curDue =
            ((customer?.fields['duePaise'] as num?)?.toInt() ??
            (balance?.fields['duePaise'] as num?)?.toInt() ??
            0);
        final nextDue = (curDue + dueDelta).clamp(0, 1 << 50);

        if (customer?.exists == true) {
          tx.update(FirebaseConstants.customers, customerId, {
            'duePaise': nextDue,
          }, updateTime: customer!.updateTime);
        }
        if (balance?.exists == true) {
          tx.update(FirebaseConstants.customerBalances, balanceId!, {
            'duePaise': nextDue,
          }, updateTime: balance!.updateTime);
        }
        final ledgerId = IdGenerator.create('LED');
        tx.create(
          FirebaseConstants.customerLedgerEntries,
          ledgerId,
          {
            'transactionId': ledgerId,
            'businessId': businessId,
            'tenantId': tenantId,
            'outletId': outletId,
            'customerId': customerId,
            'invoiceId': invoiceId,
            'transactionType': 'ADJUSTMENT',
            'amountPaise': dueDelta.abs(),
            'debitPaise': dueDelta > 0 ? dueDelta : 0,
            'creditPaise': dueDelta < 0 ? -dueDelta : 0,
            'entryType': 'INVOICE_EDIT_ADJUSTMENT',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'createdBy': cashierUid,
            'status': 'POSTED',
            'immutable': true,
          },
        );
      }

      for (var i = calculated.lines.length; i < oldItems.length; i++) {
        tx.delete(
          FirebaseConstants.invoiceItems,
          '${invoiceId}_$i',
          updateTime: oldItems[i].updateTime,
        );
      }

      for (var index = 0; index < calculated.lines.length; index++) {
        final line = calculated.lines[index];
        final itemData = {
          'invoiceId': invoiceId,
          'tenantId': tenantId,
          'businessId': businessId,
          'outletId': outletId,
          'variantId': line.input.variantId,
          'sku': line.input.sku,
          'name': line.input.name,
          'productName': line.input.name,
          'hsn': line.input.hsn,
          'quantity': line.input.quantity,
          'quantityBase': line.input.quantityBase,
          'unit': line.input.unit,
          'conversionFactor': line.input.conversionFactor,
          'trackStock': line.input.trackStock,
          'unitPricePaise': line.input.unitPricePaise,
          'discountPaise': line.input.discountPaise,
          'taxablePaise': line.taxablePaise,
          'gstRateBps': line.input.gstRateBps,
          'taxPaise': line.taxPaise,
          'cgstPaise': (line.taxPaise ~/ 2),
          'sgstPaise': (line.taxPaise - (line.taxPaise ~/ 2)),
          'totalPaise': line.lineTotalPaise,
          'lineTotalPaise': line.lineTotalPaise,
        };

        if (index < oldItems.length) {
          tx.update(FirebaseConstants.invoiceItems, '${invoiceId}_$index', {
            ...oldItems[index].fields,
            ...itemData,
          }, updateTime: oldItems[index].updateTime);
        } else {
          tx.create(
            FirebaseConstants.invoiceItems,
            '${invoiceId}_$index',
            itemData,
          );
        }
      }

      final newStatus = newDue == 0
          ? 'PAID'
          : (paidPaise > 0 ? 'PARTIALLY_PAID' : 'PENDING');

      final trimmedName = customerName?.trim();
      final finalName = (trimmedName == null || trimmedName.isEmpty)
          ? 'Walk-in'
          : trimmedName;

      tx.update(FirebaseConstants.invoices, invoiceId, {
        ...invoice.fields,
        'customerName': finalName,
        'customerNameLower': finalName.toLowerCase(),
        'customerPhone': customerPhone?.trim() ?? '',
        'customerGstin': customerGstin?.trim().isEmpty == true
            ? null
            : customerGstin?.trim().toUpperCase(),
        'dueDate': dueDate == null ? null : _dateOnly(dueDate),
        'subtotalPaise': calculated.subtotalPaise,
        'discountPaise': calculated.totalDiscountPaise,
        'taxablePaise': calculated.taxableTotalPaise,
        'cgstPaise': calculated.cgstPaise,
        'sgstPaise': calculated.sgstPaise,
        'igstPaise': calculated.igstPaise,
        'roundOffPaise': calculated.roundOffPaise,
        'grandTotalPaise': calculated.grandTotalPaise,
        'dueAmount': newDue,
        'status': newStatus,
        'items': calculated.lines
            .map(
              (l) => {
                'variantId': l.input.variantId,
                'sku': l.input.sku,
                'name': l.input.name,
                'productName': l.input.name,
                'hsn': l.input.hsn,
                'quantity': l.input.quantity,
                'quantityBase': l.input.quantityBase,
                'unit': l.input.unit,
                'unitPricePaise': l.input.unitPricePaise,
                'taxablePaise': l.taxablePaise,
                'taxableAmount': l.taxablePaise,
                'gstRateBps': l.input.gstRateBps,
                'taxPaise': l.taxPaise,
                'taxAmount': l.taxPaise,
                'cgstPaise': (l.taxPaise ~/ 2),
                'sgstPaise': (l.taxPaise - (l.taxPaise ~/ 2)),
                'totalPaise': l.lineTotalPaise,
                'totalAmount': l.lineTotalPaise,
              },
            )
            .toList(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }, updateTime: invoice.updateTime);
    }, idToken: token);
  }
}

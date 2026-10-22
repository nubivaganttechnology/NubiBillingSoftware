import '../../core/constants/firebase_constants.dart';
import '../models/outlet_product_model.dart';
import 'firestore_data_service.dart';
import 'firestore_rest_service.dart';
import 'firestore_transaction_service.dart';

class OutletPlacementAssignment {
  const OutletPlacementAssignment({
    required this.productId,
    required this.productName,
    required this.outletId,
    required this.evidence,
  });
  final String productId, productName, outletId;

  /// Collections that prove the product belongs to the outlet.
  final List<String> evidence;
}

class OutletPlacementBackfillReport {
  const OutletPlacementBackfillReport({
    required this.assignments,
    required this.alreadyPlaced,
    required this.unassigned,
    required this.applied,
  });

  /// Placements proven by existing data (created unless this was a dry run).
  final List<OutletPlacementAssignment> assignments;

  /// Proven placements that already had a row (active or deliberately inactive).
  final List<OutletPlacementAssignment> alreadyPlaced;

  /// Product id -> name for products with no proof and no placement anywhere.
  final Map<String, String> unassigned;
  final bool applied;

  String get summary =>
      '${assignments.length} placement(s) created from existing history, '
      '${unassigned.length} product(s) left unassigned';
}

/// One-time, evidence-only placement of pre-existing business products.
///
/// A product is placed at an outlet only when existing data proves it belongs
/// there (an explicit `outletId` on the product/variant, or stock, inventory,
/// goods-receipt, purchase or invoice records for that outlet). Nothing is
/// guessed: an unprovable product stays unassigned. Product and variant masters
/// are only read.
class OutletPlacementBackfill {
  OutletPlacementBackfill(this.firestore, this.transactions);
  final FirestoreDataService firestore;
  final FirestoreTransactionService transactions;

  /// Business-wide collections that must be fully synced before the evidence
  /// is complete enough to act on.
  static const requiredCollections = [
    FirebaseConstants.products,
    FirebaseConstants.productVariants,
    FirebaseConstants.outletProducts,
    FirebaseConstants.stockBalances,
    FirebaseConstants.inventoryTransactions,
    FirebaseConstants.goodsReceiptItems,
    FirebaseConstants.purchaseOrderItems,
  ];

  static const _evidenceCollections = [
    FirebaseConstants.stockBalances,
    FirebaseConstants.inventoryTransactions,
    FirebaseConstants.goodsReceiptItems,
    FirebaseConstants.purchaseOrderItems,
    FirebaseConstants.purchaseBills,
    FirebaseConstants.invoices,
  ];

  Future<List<Map<String, dynamic>>> _fields(
    String collection,
    String tenantId,
    String businessId,
    String token,
  ) async {
    final docs = await firestore.queryDocuments(
      collection: collection,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    return [
      for (final doc in docs)
        {
          ...FirestoreRestService.decodeFields(doc['fields']),
          '_id': (doc['name'] as String? ?? '').split('/').last,
        },
    ].where((f) => f['isDeleted'] != true && f['isDeleted'] != 1).toList();
  }

  Future<OutletPlacementBackfillReport> run({
    required String tenantId,
    required String businessId,
    required String actorUid,
    required String token,
    bool dryRun = false,
  }) async {
    final productDocs =
        (await _fields(
          FirebaseConstants.products,
          tenantId,
          businessId,
          token,
        )).where(
          (f) =>
              (f['status'] as String? ?? 'ACTIVE').toUpperCase() != 'DELETED',
        );
    final products = {
      for (final f in productDocs)
        (f['productId'] as String? ?? f['_id'] as String):
            (f['productName'] ?? f['name'] ?? '').toString(),
    };
    final owner = <String, String>{for (final id in products.keys) id: id};
    final variantDocs = await _fields(
      FirebaseConstants.productVariants,
      tenantId,
      businessId,
      token,
    );
    for (final f in variantDocs) {
      final productId = f['productId'] as String?;
      if (productId != null && products.containsKey(productId)) {
        owner[f['variantId'] as String? ?? f['_id'] as String] = productId;
      }
    }
    // `outlets` is a bootstrap collection registered by businessId only; use
    // that exact filter so this stays a pure local read.
    final outletDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.outlets,
      filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
      idToken: token,
    );
    final outletIds = <String>{};
    for (final doc in outletDocs) {
      final f = FirestoreRestService.decodeFields(doc['fields']);
      if ((f['tenantId'] ?? f['ownerUid']) == tenantId &&
          f['isDeleted'] != true) {
        outletIds.add(
          f['outletId'] as String? ??
              (doc['name'] as String? ?? '').split('/').last,
        );
      }
    }

    final evidence = <String, Map<String, Set<String>>>{};
    void prove(String source, Map<String, dynamic> row, String? productHint) {
      final outlet = (row['outletId'] as String? ?? '').trim();
      if (!outletIds.contains(outlet)) return;
      final location = row['locationType'];
      if (location != null && location != 'OUTLET') return;
      final ids = <Object?>{
        row['variantId'],
        row['productId'],
        productHint,
        if (row['items'] is List)
          for (final item in row['items'] as List)
            if (item is Map) ...[item['variantId'], item['productId']],
      };
      for (final id in ids.whereType<String>()) {
        final productId = owner[id];
        if (productId == null) continue;
        evidence
            .putIfAbsent(productId, () => {})
            .putIfAbsent(outlet, () => {})
            .add(source);
      }
    }

    for (final f in productDocs) {
      prove(
        'products.outletId',
        f,
        f['productId'] as String? ?? f['_id'] as String,
      );
    }
    for (final f in variantDocs) {
      prove('product_variants.outletId', f, f['productId'] as String?);
    }
    for (final collection in _evidenceCollections) {
      for (final row in await _fields(
        collection,
        tenantId,
        businessId,
        token,
      )) {
        prove(collection, row, null);
      }
    }

    final placements = await _existingPlacements(tenantId, businessId, token);
    final existing = {
      for (final p in placements) '${p.productId}\u0000${p.outletId}',
    };
    final anyPlacement = {for (final p in placements) p.productId};
    final assignments = <OutletPlacementAssignment>[];
    final already = <OutletPlacementAssignment>[];
    for (final entry in evidence.entries) {
      for (final outlet in entry.value.entries) {
        final assignment = OutletPlacementAssignment(
          productId: entry.key,
          productName: products[entry.key] ?? '',
          outletId: outlet.key,
          evidence: outlet.value.toList()..sort(),
        );
        (existing.contains('${entry.key}\u0000${outlet.key}')
                ? already
                : assignments)
            .add(assignment);
      }
    }
    final unassigned = {
      for (final p in products.entries)
        if (!evidence.containsKey(p.key) && !anyPlacement.contains(p.key))
          p.key: p.value,
    };
    if (!dryRun && assignments.isNotEmpty) {
      for (var start = 0; start < assignments.length; start += 200) {
        final chunk = assignments.skip(start).take(200).toList();
        await transactions.runAtomicOperation((tx) async {
          final now = DateTime.now().toUtc();
          for (final a in chunk) {
            final id = OutletProductModel.documentId(
              tenantId: tenantId,
              businessId: businessId,
              outletId: a.outletId,
              productId: a.productId,
            );
            if ((await tx.get(FirebaseConstants.outletProducts, id)).exists) {
              continue;
            }
            tx.create(FirebaseConstants.outletProducts, id, {
              ...OutletProductModel.newPlacementData(
                tenantId: tenantId,
                businessId: businessId,
                outletId: a.outletId,
                productId: a.productId,
                now: now,
              ),
              'placementSource': OutletProductModel.sourceLegacyBackfill,
              'placementEvidence': a.evidence,
              'createdBy': actorUid,
            });
          }
        }, idToken: token);
      }
    }
    return OutletPlacementBackfillReport(
      assignments: assignments,
      alreadyPlaced: already,
      unassigned: unassigned,
      applied: !dryRun,
    );
  }

  Future<List<OutletProductModel>> _existingPlacements(
    String tenantId,
    String businessId,
    String token,
  ) async => [
    for (final f in await _fields(
      FirebaseConstants.outletProducts,
      tenantId,
      businessId,
      token,
    ))
      OutletProductModel.fromData(f['_id'] as String, f),
  ];
}

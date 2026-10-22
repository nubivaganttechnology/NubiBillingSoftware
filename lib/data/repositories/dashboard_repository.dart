import 'package:flutter/foundation.dart';
import '../../core/constants/firebase_constants.dart';
import '../../domain/entities/app_context.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_data_service.dart';

class DashboardRepository {
  DashboardRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<DashboardSummary> load(
    AppContext context,
    String token, {
    required bool includeSales,
    required bool includePurchases,
    required bool includeProducts,
    required bool includeCustomers,
  }) async {
    final businessId = context.businessId;
    final outletId = context.outletId;
    if (businessId == null || outletId == null) {
      throw StateError(
        'A business and outlet must be selected before loading the dashboard.',
      );
    }

    // 1. Sales & Invoices
    final salesFuture = includeSales
        ? _loadSales(businessId, outletId, token)
        : Future.value(const _SalesLoadResult.empty());

    // 2. Purchases (purchase_bills)
    final purchasesFuture = includePurchases
        ? _loadPurchases(businessId, outletId, token)
        : Future.value(const _PurchasesLoadResult.empty());

    // 3. Products
    final productsFuture = includeProducts
        ? _loadProducts(businessId, outletId, token)
        : Future.value(const _ProductsLoadResult.empty());

    // 4. Customers
    final customersFuture = includeCustomers
        ? _loadCustomers(businessId, token)
        : Future.value(const _CustomersLoadResult.empty());

    final results = await Future.wait([
      salesFuture,
      purchasesFuture,
      productsFuture,
      customersFuture,
    ]);

    final salesResult = results[0] as _SalesLoadResult;
    final purchasesResult = results[1] as _PurchasesLoadResult;
    final productsResult = results[2] as _ProductsLoadResult;
    final customersResult = results[3] as _CustomersLoadResult;

    final effectiveProductCount = productsResult.activeCount > 0
        ? productsResult.activeCount
        : productsResult.totalCount;

    return DashboardSummary(
      salesTotal: salesResult.total,
      salesCount: salesResult.count,
      purchaseTotal: purchasesResult.total,
      purchaseCount: purchasesResult.count,
      productCount: effectiveProductCount,
      customerCount: customersResult.count,
      weeklySales: salesResult.weeklySales,
      recentSales: salesResult.recentSales,
      topProducts: salesResult.aggregates.topByQuantity,
      topProductsByRevenue: salesResult.aggregates.topByRevenue,
      bottomProducts: salesResult.aggregates.bottomProducts,
      salesDueTotal: salesResult.dueTotal,
      salesDueCount: salesResult.dueCount,
      purchaseDueTotal: purchasesResult.dueTotal,
      activeProductCount: productsResult.activeCount,
      inactiveProductCount: productsResult.inactiveCount,
      outOfStockCount: productsResult.outOfStockCount,
      lowStockCount: productsResult.lowStockCount,
      lowStockProducts: productsResult.lowStockProducts,
      customerDueTotal: customersResult.dueTotal,
      customersWithDueCount: customersResult.customersWithDueCount,
    );
  }

  Future<_SalesLoadResult> _loadSales(
    String businessId,
    String outletId,
    String token,
  ) async {
    try {
      List<Map<String, dynamic>> invoiceDocs = [];
      try {
        invoiceDocs = await firestore.queryDocuments(
          collection: FirebaseConstants.invoices,
          filters: _scope(businessId, outletId),
          orderBy: 'createdAt',
          descending: true,
          limit: 200,
          idToken: token,
        );
      } catch (e) {
        // Fallback without ordering if index is not present or collation differs
        invoiceDocs = await firestore.queryDocuments(
          collection: FirebaseConstants.invoices,
          filters: _scope(businessId, outletId),
          limit: 200,
          idToken: token,
        );
      }

      final invoices = invoiceDocs.map(_invoice).toList();
      // Sort descending by date in memory
      invoices.sort((a, b) {
        final da = a.sale.createdAt;
        final db = b.sale.createdAt;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });

      double totalSales = 0.0;
      double totalDue = 0.0;
      int salesCount = 0;
      int dueCount = 0;
      for (final inv in invoices) {
        if (inv.status.toUpperCase() == 'CANCELLED') continue;
        totalSales += inv.sale.amount;
        salesCount++;
        if (inv.dueAmount > 0) {
          totalDue += inv.dueAmount;
          dueCount++;
        }
      }

      // Generate last 7 days ending today (local time)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dates = List.generate(
        7,
        (index) => today.subtract(Duration(days: 6 - index)),
      );

      final dailyTotals = <int, double>{
        for (var i = 0; i < dates.length; i++) i: 0.0,
      };

      for (final inv in invoices) {
        if (inv.status.toUpperCase() == 'CANCELLED') continue;
        final date = inv.sale.createdAt;
        if (date == null) continue;
        final local = date.toLocal();
        final invDay = DateTime(local.year, local.month, local.day);
        for (var i = 0; i < dates.length; i++) {
          if (dates[i].year == invDay.year &&
              dates[i].month == invDay.month &&
              dates[i].day == invDay.day) {
            dailyTotals[i] = (dailyTotals[i] ?? 0.0) + inv.sale.amount;
            break;
          }
        }
      }

      final weeklySales = [
        for (var i = 0; i < dates.length; i++)
          SalesDaySummary(
            date: dates[i],
            amount: dailyTotals[i] ?? 0.0,
          ),
      ];

      // If invoices do not have embedded items, check invoiceItems collection
      final hasAnyItems = invoices.any((inv) => inv.items.isNotEmpty);
      List<_InvoiceData> finalInvoices = invoices;
      if (!hasAnyItems && invoices.isNotEmpty) {
        try {
          final itemDocs = await firestore.queryDocuments(
            collection: FirebaseConstants.invoiceItems,
            filters: _scope(businessId, outletId),
            limit: 500,
            idToken: token,
          );
          if (itemDocs.isNotEmpty) {
            final itemsByInvoice = <String, List<Map<String, dynamic>>>{};
            for (final doc in itemDocs) {
              final fields = FirestoreRestService.decodeFields(doc['fields']);
              final invId = fields['invoiceId']?.toString() ?? '';
              if (invId.isNotEmpty) {
                itemsByInvoice.putIfAbsent(invId, () => []).add(fields);
              }
            }
            finalInvoices = invoices.map((inv) {
              if (inv.items.isNotEmpty) return inv;
              final items = itemsByInvoice[inv.id] ??
                  itemsByInvoice[inv.sale.invoiceNumber] ??
                  [];
              return _InvoiceData(
                id: inv.id,
                status: inv.status,
                sale: inv.sale,
                items: items,
                dueAmount: inv.dueAmount,
              );
            }).toList();
          }
        } catch (_) {}
      }

      final productAggregates = _aggregateProducts(finalInvoices);

      return _SalesLoadResult(
        total: totalSales,
        count: salesCount,
        dueTotal: totalDue,
        dueCount: dueCount,
        weeklySales: weeklySales,
        recentSales: invoices.take(8).map((i) => i.sale).toList(),
        aggregates: productAggregates,
      );
    } catch (e, st) {
      debugPrint('[DashboardRepository] _loadSales error: $e\n$st');
      return const _SalesLoadResult.empty();
    }
  }

  Future<_PurchasesLoadResult> _loadPurchases(
    String businessId,
    String outletId,
    String token,
  ) async {
    try {
      final docs = await firestore.queryDocuments(
        collection: FirebaseConstants.purchaseBills,
        filters: _scope(businessId, outletId),
        limit: 200,
        idToken: token,
      );

      double total = 0.0;
      double dueTotal = 0.0;
      int count = 0;
      for (final doc in docs) {
        final fields = FirestoreRestService.decodeFields(doc['fields']);
        final status = (fields['status'] as String? ?? '').toUpperCase();
        if (status == 'CANCELLED' || status == 'REJECTED') continue;
        count++;
        if (fields['grandTotal'] is num) {
          total += (fields['grandTotal'] as num).toDouble() / 100.0;
        } else if (fields['totalAmount'] is num) {
          final amt = (fields['totalAmount'] as num).toDouble();
          total += amt > 10000 && amt % 100 == 0 ? amt / 100.0 : amt;
        }
        if (fields['outstandingAmount'] is num) {
          final out = (fields['outstandingAmount'] as num).toDouble();
          dueTotal += out > 10000 && out % 100 == 0 ? out / 100.0 : out / 100.0;
        }
      }
      return _PurchasesLoadResult(total: total, count: count, dueTotal: dueTotal);
    } catch (e) {
      debugPrint('[DashboardRepository] _loadPurchases error: $e');
      return const _PurchasesLoadResult.empty();
    }
  }

  Future<_ProductsLoadResult> _loadProducts(
    String businessId,
    String outletId,
    String token,
  ) async {
    try {
      // 1. Fetch outlet placements
      final outletDocs = await firestore.queryDocuments(
        collection: FirebaseConstants.outletProducts,
        filters: _scope(businessId, outletId),
        idToken: token,
      );

      int activeCount = 0;
      int inactiveCount = 0;
      final placedVariantIds = <String>{};

      for (final doc in outletDocs) {
        final fields = FirestoreRestService.decodeFields(doc['fields']);
        if (fields['isDeleted'] == true) continue;
        final status = (fields['status'] as String? ?? '').toLowerCase();
        final isActive = fields['isActive'] != false && status != 'inactive';
        if (isActive) {
          activeCount++;
        } else {
          inactiveCount++;
        }
        final vids = fields['variantIds'];
        if (vids is List) {
          for (final v in vids) {
            if (v is String && v.isNotEmpty) placedVariantIds.add(v);
          }
        }
      }

      // If no outlet_products, check master products collection
      if (outletDocs.isEmpty) {
        final productDocs = await firestore.queryDocuments(
          collection: FirebaseConstants.products,
          filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
          idToken: token,
        );
        for (final doc in productDocs) {
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          final status = (fields['status'] as String? ?? '').toLowerCase();
          if (status == 'active') {
            activeCount++;
          } else {
            inactiveCount++;
          }
        }
      }

      // 2. Fetch stock balances for this outlet
      final stockBalances = <Map<String, dynamic>>[];
      try {
        final stockDocs = await firestore.queryDocuments(
          collection: FirebaseConstants.stockBalances,
          filters: _scope(businessId, outletId),
          limit: 500,
          idToken: token,
        );
        for (final doc in stockDocs) {
          stockBalances.add(FirestoreRestService.decodeFields(doc['fields']));
        }
      } catch (e) {
        debugPrint('[DashboardRepository] stockBalances error: $e');
      }

      final stockByVariant = <String, int>{};
      for (final sb in stockBalances) {
        final vid = sb['variantId'] as String? ?? sb['productId'] as String? ?? '';
        final qty = (sb['quantityOnHand'] as num?)?.toInt() ?? 0;
        if (vid.isNotEmpty) {
          stockByVariant[vid] = (stockByVariant[vid] ?? 0) + qty;
        }
      }

      // 3. Fetch product variants for names, skus, reorder levels
      final variants = <Map<String, dynamic>>[];
      try {
        final variantDocs = await firestore.queryDocuments(
          collection: FirebaseConstants.productVariants,
          filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
          limit: 500,
          idToken: token,
        );
        for (final doc in variantDocs) {
          variants.add(FirestoreRestService.decodeFields(doc['fields']));
        }
      } catch (e) {
        debugPrint('[DashboardRepository] productVariants error: $e');
      }

      int outOfStockCount = 0;
      int lowStockCount = 0;
      final lowStockList = <LowStockProductSummary>[];

      for (final v in variants) {
        final vid = (v['variantId'] as String?) ?? '';
        if (vid.isEmpty) continue;
        final vStatus = (v['status'] as String? ?? '').toUpperCase();
        if (vStatus == 'INACTIVE' || v['isActive'] == false) continue;
        if (placedVariantIds.isNotEmpty && !placedVariantIds.contains(vid)) {
          continue;
        }

        final trackStock = v['trackStock'] != false;
        if (!trackStock) continue;

        final currentQty = stockByVariant[vid] ?? 0;
        final reorder = (v['reorderLevel'] as num?)?.toInt() ?? 0;
        final effectiveReorder = reorder > 0 ? reorder : 5;

        final name = (v['productName'] ?? v['name'] ?? 'Product') as String;
        final sku = (v['sku'] as String?) ?? '';
        final unit = (v['commercialUnitName'] ?? v['baseUnitId'] ?? '') as String;

        if (currentQty <= 0) {
          outOfStockCount++;
          lowStockList.add(
            LowStockProductSummary(
              variantId: vid,
              name: name,
              sku: sku,
              unit: unit,
              currentStock: currentQty,
              reorderLevel: effectiveReorder,
              isOutOfStock: true,
            ),
          );
        } else if (currentQty <= effectiveReorder) {
          lowStockCount++;
          lowStockList.add(
            LowStockProductSummary(
              variantId: vid,
              name: name,
              sku: sku,
              unit: unit,
              currentStock: currentQty,
              reorderLevel: effectiveReorder,
              isOutOfStock: false,
            ),
          );
        }
      }

      // If variants collection was empty, but stock balances exist
      if (variants.isEmpty && stockBalances.isNotEmpty) {
        for (final sb in stockBalances) {
          final vid = sb['variantId'] as String? ?? sb['productId'] as String? ?? '';
          final qty = (sb['quantityOnHand'] as num?)?.toInt() ?? 0;
          final name = (sb['productName'] ?? sb['name'] ?? 'Item') as String;
          final sku = (sb['sku'] as String?) ?? '';
          final unit = (sb['unit'] as String?) ?? '';
          if (qty <= 0) {
            outOfStockCount++;
            lowStockList.add(
              LowStockProductSummary(
                variantId: vid,
                name: name,
                sku: sku,
                unit: unit,
                currentStock: qty,
                reorderLevel: 5,
                isOutOfStock: true,
              ),
            );
          } else if (qty <= 5) {
            lowStockCount++;
            lowStockList.add(
              LowStockProductSummary(
                variantId: vid,
                name: name,
                sku: sku,
                unit: unit,
                currentStock: qty,
                reorderLevel: 5,
                isOutOfStock: false,
              ),
            );
          }
        }
      }

      lowStockList.sort((a, b) {
        if (a.isOutOfStock != b.isOutOfStock) {
          return a.isOutOfStock ? -1 : 1;
        }
        return a.currentStock.compareTo(b.currentStock);
      });

      return _ProductsLoadResult(
        totalCount: activeCount + inactiveCount,
        activeCount: activeCount,
        inactiveCount: inactiveCount,
        outOfStockCount: outOfStockCount,
        lowStockCount: lowStockCount,
        lowStockProducts: lowStockList.take(20).toList(),
      );
    } catch (e, st) {
      debugPrint('[DashboardRepository] _loadProducts error: $e\n$st');
      return const _ProductsLoadResult.empty();
    }
  }

  Future<_CustomersLoadResult> _loadCustomers(String businessId, String token) async {
    try {
      final docs = await firestore.queryDocuments(
        collection: FirebaseConstants.customers,
        filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
        idToken: token,
      );
      double totalDue = 0.0;
      int withDueCount = 0;
      for (final doc in docs) {
        final fields = FirestoreRestService.decodeFields(doc['fields']);
        final duePaise = (fields['duePaise'] as num?)?.toInt() ?? 0;
        if (duePaise > 0) {
          totalDue += duePaise / 100.0;
          withDueCount++;
        }
      }
      return _CustomersLoadResult(
        count: docs.length,
        dueTotal: totalDue,
        customersWithDueCount: withDueCount,
      );
    } catch (e) {
      debugPrint('[DashboardRepository] _loadCustomers error: $e');
      return const _CustomersLoadResult.empty();
    }
  }

  List<FirestoreFilter> _scope(String businessId, String outletId) => [
    FirestoreFilter('businessId', 'EQUAL', businessId),
    FirestoreFilter('outletId', 'EQUAL', outletId),
  ];

  _InvoiceData _invoice(Map<String, dynamic> document) {
    final fields = FirestoreRestService.decodeFields(document['fields']);
    final items = fields['items'];
    final id = (document['name'] as String? ?? '').split('/').last;

    double amount = 0.0;
    if (fields['grandTotalPaise'] is num) {
      amount = (fields['grandTotalPaise'] as num).toDouble() / 100.0;
    } else if (fields['totalPaise'] is num) {
      amount = (fields['totalPaise'] as num).toDouble() / 100.0;
    } else if (fields['totalAmount'] is num) {
      final raw = (fields['totalAmount'] as num).toDouble();
      amount = raw > 10000 && raw % 100 == 0 ? raw / 100.0 : raw;
    }

    double dueAmount = 0.0;
    if (fields['duePaise'] is num) {
      dueAmount = (fields['duePaise'] as num).toDouble() / 100.0;
    } else if (fields['dueAmount'] is num) {
      final raw = (fields['dueAmount'] as num).toDouble();
      if (fields['grandTotalPaise'] != null || fields['totalPaise'] != null) {
        dueAmount = raw / 100.0;
      } else {
        dueAmount = raw > 10000 && raw % 100 == 0 ? raw / 100.0 : raw;
      }
    }

    final rawStatus = (fields['status'] as String? ?? '').toUpperCase();
    final paymentStatus = rawStatus == 'PAID'
        ? 'PAID'
        : rawStatus == 'PENDING'
            ? 'PENDING'
            : (fields['paymentStatus'] != null
                ? (fields['paymentStatus'] as String).toUpperCase()
                : (dueAmount == 0
                    ? 'PAID'
                    : 'PENDING'));

    return _InvoiceData(
      id: id,
      status: fields['status'] as String? ?? 'ACTIVE',
      dueAmount: dueAmount,
      sale: RecentSaleSummary(
        invoiceNumber: fields['invoiceNumber'] as String? ?? 'Invoice',
        amount: amount,
        paymentStatus: paymentStatus,
        createdAt: _parseDate(fields['createdAt']),
      ),
      items: items is List
          ? items.whereType<Map<String, dynamic>>().toList()
          : const [],
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  _ProductAggregates _aggregateProducts(List<_InvoiceData> invoices) {
    final quantities = <String, double>{};
    final revenues = <String, double>{};
    final skus = <String, String>{};
    final units = <String, String>{};

    for (final invoice in invoices) {
      for (final item in invoice.items) {
        final name = (item['productName'] ?? item['name']) as String?;
        if (name == null || name.trim().isEmpty) continue;
        final cleanName = name.trim();
        final qty = _number(item['quantity']);

        double rev = 0.0;
        if (item['totalPaise'] is num) {
          rev = (item['totalPaise'] as num).toDouble() / 100.0;
        } else if (item['lineTotalPaise'] is num) {
          rev = (item['lineTotalPaise'] as num).toDouble() / 100.0;
        } else if (item['taxablePaise'] is num) {
          final tax = (item['taxPaise'] as num?)?.toDouble() ?? 0.0;
          rev = ((item['taxablePaise'] as num).toDouble() + tax) / 100.0;
        } else if (item['totalAmount'] is num) {
          final amt = (item['totalAmount'] as num).toDouble();
          rev = amt > 10000 && amt % 100 == 0 ? amt / 100.0 : amt;
        } else if (item['unitPricePaise'] is num) {
          rev = ((item['unitPricePaise'] as num).toDouble() * qty) / 100.0;
        }

        quantities.update(cleanName, (q) => q + qty, ifAbsent: () => qty);
        revenues.update(cleanName, (r) => r + rev, ifAbsent: () => rev);
        if (item['sku'] is String && (item['sku'] as String).isNotEmpty) {
          skus[cleanName] = item['sku'] as String;
        }
        if (item['unit'] is String && (item['unit'] as String).isNotEmpty) {
          units[cleanName] = item['unit'] as String;
        }
      }
    }

    final byQty = quantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topByQty = byQty.take(20).map((e) => TopProductSummary(
      name: e.key,
      quantity: e.value,
      revenue: revenues[e.key] ?? 0.0,
      sku: skus[e.key] ?? '',
      unit: units[e.key] ?? '',
    )).toList(growable: false);

    final byRev = revenues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topByRev = byRev.take(20).map((e) => TopProductSummary(
      name: e.key,
      quantity: quantities[e.key] ?? 0.0,
      revenue: e.value,
      sku: skus[e.key] ?? '',
      unit: units[e.key] ?? '',
    )).toList(growable: false);

    final bottomByQty = quantities.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final leastSelling = bottomByQty.take(20).map((e) => TopProductSummary(
      name: e.key,
      quantity: e.value,
      revenue: revenues[e.key] ?? 0.0,
      sku: skus[e.key] ?? '',
      unit: units[e.key] ?? '',
    )).toList(growable: false);

    return _ProductAggregates(
      topByQuantity: topByQty,
      topByRevenue: topByRev,
      bottomProducts: leastSelling,
    );
  }

  double _number(Object? value) => value is num ? value.toDouble() : 0;
}

class _ProductAggregates {
  const _ProductAggregates({
    required this.topByQuantity,
    required this.topByRevenue,
    required this.bottomProducts,
  });

  final List<TopProductSummary> topByQuantity;
  final List<TopProductSummary> topByRevenue;
  final List<TopProductSummary> bottomProducts;
}

class _InvoiceData {
  const _InvoiceData({
    required this.id,
    required this.status,
    required this.sale,
    required this.items,
    this.dueAmount = 0.0,
  });
  final String id;
  final String status;
  final RecentSaleSummary sale;
  final List<Map<String, dynamic>> items;
  final double dueAmount;
}

class _SalesLoadResult {
  const _SalesLoadResult({
    required this.total,
    required this.count,
    required this.weeklySales,
    required this.recentSales,
    required this.aggregates,
    this.dueTotal = 0.0,
    this.dueCount = 0,
  });

  const _SalesLoadResult.empty()
      : total = 0.0,
        count = 0,
        dueTotal = 0.0,
        dueCount = 0,
        weeklySales = const [],
        recentSales = const [],
        aggregates = const _ProductAggregates(
          topByQuantity: [],
          topByRevenue: [],
          bottomProducts: [],
        );

  final double total;
  final int count;
  final double dueTotal;
  final int dueCount;
  final List<SalesDaySummary> weeklySales;
  final List<RecentSaleSummary> recentSales;
  final _ProductAggregates aggregates;
}

class _PurchasesLoadResult {
  const _PurchasesLoadResult({
    required this.total,
    required this.count,
    this.dueTotal = 0.0,
  });
  const _PurchasesLoadResult.empty()
      : total = 0.0,
        count = 0,
        dueTotal = 0.0;
  final double total;
  final int count;
  final double dueTotal;
}

class _CustomersLoadResult {
  const _CustomersLoadResult({
    required this.count,
    this.dueTotal = 0.0,
    this.customersWithDueCount = 0,
  });
  const _CustomersLoadResult.empty()
      : count = 0,
        dueTotal = 0.0,
        customersWithDueCount = 0;
  final int count;
  final double dueTotal;
  final int customersWithDueCount;
}

class _ProductsLoadResult {
  const _ProductsLoadResult({
    required this.totalCount,
    required this.activeCount,
    required this.inactiveCount,
    required this.outOfStockCount,
    required this.lowStockCount,
    required this.lowStockProducts,
  });
  const _ProductsLoadResult.empty()
      : totalCount = 0,
        activeCount = 0,
        inactiveCount = 0,
        outOfStockCount = 0,
        lowStockCount = 0,
        lowStockProducts = const [];

  final int totalCount;
  final int activeCount;
  final int inactiveCount;
  final int outOfStockCount;
  final int lowStockCount;
  final List<LowStockProductSummary> lowStockProducts;
}

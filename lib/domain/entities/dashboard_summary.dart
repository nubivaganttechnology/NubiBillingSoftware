class DashboardSummary {
  const DashboardSummary({
    required this.salesTotal,
    required this.salesCount,
    required this.purchaseTotal,
    required this.purchaseCount,
    required this.productCount,
    required this.customerCount,
    required this.weeklySales,
    required this.recentSales,
    required this.topProducts,
    this.topProductsByRevenue = const [],
    this.bottomProducts = const [],
    this.salesDueTotal = 0.0,
    this.salesDueCount = 0,
    this.purchaseDueTotal = 0.0,
    this.activeProductCount = 0,
    this.inactiveProductCount = 0,
    this.outOfStockCount = 0,
    this.lowStockCount = 0,
    this.lowStockProducts = const [],
    this.customerDueTotal = 0.0,
    this.customersWithDueCount = 0,
  });

  final double salesTotal, purchaseTotal;
  final int salesCount, purchaseCount, productCount, customerCount;
  final List<SalesDaySummary> weeklySales;
  final List<RecentSaleSummary> recentSales;
  final List<TopProductSummary> topProducts;
  final List<TopProductSummary> topProductsByRevenue;
  final List<TopProductSummary> bottomProducts;

  // Commercial credit & dues (borrowed / receivables / payables)
  final double salesDueTotal;
  final int salesDueCount;
  final double purchaseDueTotal;
  final double customerDueTotal;
  final int customersWithDueCount;

  // Inventory & stock health
  final int activeProductCount;
  final int inactiveProductCount;
  final int outOfStockCount;
  final int lowStockCount;
  final List<LowStockProductSummary> lowStockProducts;

  /// Effective borrowed amount (unpaid customer dues)
  double get borrowedAmount =>
      salesDueTotal > 0 ? salesDueTotal : customerDueTotal;
}

class LowStockProductSummary {
  const LowStockProductSummary({
    required this.variantId,
    required this.name,
    this.sku = '',
    this.unit = '',
    required this.currentStock,
    required this.reorderLevel,
    this.isOutOfStock = false,
  });

  final String variantId;
  final String name;
  final String sku;
  final String unit;
  final int currentStock;
  final int reorderLevel;
  final bool isOutOfStock;
}

class SalesDaySummary {
  const SalesDaySummary({required this.date, required this.amount});
  final DateTime date;
  final double amount;
}

class RecentSaleSummary {
  const RecentSaleSummary({
    required this.invoiceNumber,
    required this.amount,
    required this.paymentStatus,
    required this.createdAt,
  });
  final String invoiceNumber, paymentStatus;
  final double amount;
  final DateTime? createdAt;
}

class TopProductSummary {
  const TopProductSummary({
    required this.name,
    required this.quantity,
    this.revenue = 0.0,
    this.sku = '',
    this.unit = '',
  });
  final String name;
  final double quantity;
  final double revenue;
  final String sku;
  final String unit;
}

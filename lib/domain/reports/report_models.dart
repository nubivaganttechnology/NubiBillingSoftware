export 'audit_report_models.dart';

enum DateRangePreset {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  thisMonth('This month'),
  lastMonth('Last month'),
  financialYear('Financial year'),
  custom('Custom range');

  const DateRangePreset(this.label);
  final String label;
}

class ReportDateRange {
  const ReportDateRange({
    required this.start,
    required this.end,
    required this.preset,
  });

  final DateTime start;
  final DateTime end;
  final DateRangePreset preset;

  static ReportDateRange fromPreset(
    DateRangePreset preset, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (preset) {
      case DateRangePreset.today:
        return ReportDateRange(
          start: todayStart,
          end: todayEnd,
          preset: preset,
        );
      case DateRangePreset.yesterday:
        final yStart = todayStart.subtract(const Duration(days: 1));
        final yEnd = DateTime(yStart.year, yStart.month, yStart.day, 23, 59, 59, 999);
        return ReportDateRange(
          start: yStart,
          end: yEnd,
          preset: preset,
        );
      case DateRangePreset.thisWeek:
        // Week starting Monday
        final weekday = now.weekday; // 1 = Mon, 7 = Sun
        final weekStart = todayStart.subtract(Duration(days: weekday - 1));
        return ReportDateRange(
          start: weekStart,
          end: todayEnd,
          preset: preset,
        );
      case DateRangePreset.thisMonth:
        final monthStart = DateTime(now.year, now.month, 1);
        return ReportDateRange(
          start: monthStart,
          end: todayEnd,
          preset: preset,
        );
      case DateRangePreset.lastMonth:
        final lastMonthStart = DateTime(now.year, now.month - 1, 1);
        final lastDayLastMonth = DateTime(lastMonthStart.year, lastMonthStart.month + 1, 0).day;
        final lastMonthEnd = DateTime(lastMonthStart.year, lastMonthStart.month, lastDayLastMonth, 23, 59, 59, 999);
        return ReportDateRange(
          start: lastMonthStart,
          end: lastMonthEnd,
          preset: preset,
        );
      case DateRangePreset.financialYear:
        // Indian FY: April 1 to March 31 (capped at today for current year)
        final fyStartYear = now.month >= 4 ? now.year : now.year - 1;
        final fyStart = DateTime(fyStartYear, 4, 1);
        final fyEnd = DateTime(fyStartYear + 1, 3, 31, 23, 59, 59, 999);
        return ReportDateRange(
          start: fyStart,
          end: fyEnd.isAfter(todayEnd) ? todayEnd : fyEnd,
          preset: preset,
        );
      case DateRangePreset.custom:
        final s = customStart ?? todayStart;
        final e = customEnd != null
            ? DateTime(customEnd.year, customEnd.month, customEnd.day, 23, 59, 59, 999)
            : todayEnd;
        return ReportDateRange(
          start: s,
          end: e,
          preset: preset,
        );
    }
  }

  ReportDateRange previousEquivalent() {
    final diff = end.difference(start);
    final prevEnd = start.subtract(const Duration(milliseconds: 1));
    final prevStart = prevEnd.subtract(diff);
    return ReportDateRange(
      start: prevStart,
      end: prevEnd,
      preset: preset,
    );
  }

  String formatLabel() {
    String pad(int n) => n.toString().padLeft(2, '0');
    final s = '${pad(start.day)}/${pad(start.month)}/${start.year}';
    final e = '${pad(end.day)}/${pad(end.month)}/${end.year}';
    if (s == e) return s;
    return '$s – $e';
  }
}

enum ReportTileId {
  // Audits & Statutory
  completeAuditReport('Financial reconciliation', 'Source evidence, outlet consolidation and unresolved differences', 'Financial review'),

  // Sales & Collections
  salesSummary('Sales summary', 'Gross sales, tax, discounts, daily trend', 'Sales and collections'),
  salesRegister('Sales register', 'One row per invoice', 'Sales and collections'),
  productSales('Product sales', 'Quantity and value by product', 'Sales and collections'),
  salesForecast('Sales forecast & predictions', 'Monthly trends, demand forecasting & stockout predictions', 'Sales and collections'),
  outstandingReceivables('Outstanding receivables', 'Customer-wise ageing', 'Sales and collections'),

  // Purchases & Inventory
  purchaseSummary('Purchase summary', 'Bills, tax, supplier split', 'Purchases and inventory'),
  stockMovement('Stock movement', 'Opening to closing by batch', 'Purchases and inventory'),
  batchExpiry('Batch and expiry', 'Days to expiry per batch', 'Purchases and inventory'),
  lowStockReorder('Low stock and reorder', 'Items below reorder level', 'Purchases and inventory'),

  // Tax & Profit
  gstSalesSummary('GST sales summary', 'CGST, SGST, IGST by rate and HSN', 'Tax and profit'),
  gstPurchaseSummary('GST purchase summary', 'Input tax by rate and HSN', 'Tax and profit'),
  profitEstimate('Profit estimate', 'Sales less cost, margin %', 'Tax and profit'),
  expenseCashFlow('Expense and cash flow', 'Money in, money out', 'Tax and profit');

  const ReportTileId(this.title, this.subtitle, this.group);
  final String title;
  final String subtitle;
  final String group;
}

enum ReportTileStatus {
  ready('Ready'),
  needsData('Needs data');

  const ReportTileStatus(this.label);
  final String label;
}

class ReportTrendPoint {
  const ReportTrendPoint({
    required this.label,
    required this.salesPaise,
    required this.purchasesPaise,
  });

  final String label;
  final int salesPaise;
  final int purchasesPaise;
}

class ReportCategoryDistribution {
  const ReportCategoryDistribution({
    required this.name,
    required this.amountPaise,
    required this.percentage,
  });

  final String name;
  final int amountPaise;
  final double percentage;
}

class ReportsOverviewData {
  const ReportsOverviewData({
    required this.netSalesPaise,
    required this.previousNetSalesPaise,
    required this.salesGrowthPercentage,
    required this.purchasesPaise,
    required this.purchasesToSalesRatio,
    required this.receivablesOutstandingPaise,
    required this.collectedPaise,
    required this.lowStockCount,
    required this.expiringBatchesCount,
    required this.generatedAt,
    required this.dataCutoffTime,
    required this.isSynced,
    required this.tileStatuses,
    this.trendPoints = const [],
    this.topCategories = const [],
    this.totalSkusCount = 0,
    this.overdueReceivablesPaise = 0,
    this.grossProfitPaise = 0,
    this.grossProfitMarginPercentage,
  });

  final int netSalesPaise;
  final int? previousNetSalesPaise;
  final double? salesGrowthPercentage;
  final int purchasesPaise;
  final double? purchasesToSalesRatio;
  final int receivablesOutstandingPaise;
  final int collectedPaise;
  final int lowStockCount;
  final int expiringBatchesCount;
  final DateTime generatedAt;
  final DateTime dataCutoffTime;
  final bool isSynced;
  final Map<ReportTileId, ReportTileStatus> tileStatuses;
  final List<ReportTrendPoint> trendPoints;
  final List<ReportCategoryDistribution> topCategories;
  final int totalSkusCount;
  final int overdueReceivablesPaise;
  final int grossProfitPaise;
  final double? grossProfitMarginPercentage;

  static ReportsOverviewData empty() => ReportsOverviewData(
    netSalesPaise: 0,
    previousNetSalesPaise: null,
    salesGrowthPercentage: null,
    purchasesPaise: 0,
    purchasesToSalesRatio: null,
    receivablesOutstandingPaise: 0,
    collectedPaise: 0,
    lowStockCount: 0,
    expiringBatchesCount: 0,
    generatedAt: DateTime.now(),
    dataCutoffTime: DateTime.now(),
    isSynced: true,
    tileStatuses: {
      for (final id in ReportTileId.values) id: ReportTileStatus.ready,
    },
    trendPoints: const [],
    topCategories: const [],
    totalSkusCount: 0,
    overdueReceivablesPaise: 0,
    grossProfitPaise: 0,
    grossProfitMarginPercentage: null,
  );
}

class ReportSummaryStat {
  const ReportSummaryStat({
    required this.label,
    required this.value,
    this.subValue,
  });

  final String label;
  final String value;
  final String? subValue;
}

class ReportDetailData {
  const ReportDetailData({
    required this.tileId,
    required this.title,
    required this.subtitle,
    required this.businessName,
    required this.outletName,
    required this.dateRange,
    required this.generatedAt,
    required this.columns,
    required this.rows,
    required this.summaryStats,
    this.columnTotals = const {},
    this.notes = const [],
    this.completenessIndicator,
  });

  final ReportTileId tileId;
  final String title;
  final String subtitle;
  final String businessName;
  final String outletName;
  final ReportDateRange dateRange;
  final DateTime generatedAt;
  final List<String> columns;
  final List<List<String>> rows;
  final List<ReportSummaryStat> summaryStats;
  final Map<int, String> columnTotals;
  final List<String> notes;
  final String? completenessIndicator;
}

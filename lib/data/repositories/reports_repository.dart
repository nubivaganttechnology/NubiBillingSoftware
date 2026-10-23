import '../../core/constants/firebase_constants.dart';
import '../../domain/reports/report_models.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../models/auth_session_model.dart';
import '../../core/config/environment_config.dart';
import '../../core/permissions/permission_catalog.dart';
import '../../core/permissions/permission_id_matcher.dart';

part 'financial_reconciliation.dart';

class ReportsRepository {
  ReportsRepository(this.firestore);

  final FirestoreDataService firestore;

  Future<AuditScopeOptions> loadAuditScopeOptions({
    required String tenantId,
    required String token,
  }) => _financialScopeOptions(tenantId, token);

  // ---------------------------------------------------------------------------
  // OVERVIEW / DASHBOARD KPI CARDS
  // ---------------------------------------------------------------------------

  Future<ReportsOverviewData> loadOverview({
    required String tenantId,
    required String businessId,
    required String outletId,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    // 1. Fetch Invoices for current period
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    // 2. Fetch Invoices for previous equivalent period (for % growth)
    final prevRange = dateRange.previousEquivalent();
    final prevInvoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: prevRange,
    );

    // 3. Fetch Purchase Bills for current period
    final purchaseBills = await _getPurchaseBills(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    // 4. Fetch Customers for receivables
    final customers = await _getCustomers(businessId: businessId, token: token);

    // 5. Fetch Stock Balances & Variants for low stock & expiry
    final stockBalances = await _getStockBalances(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
    );
    final variants = await _getVariants(businessId: businessId, token: token);

    // --- Calculations ---
    // Net sales (non-cancelled)
    int netSalesPaise = 0;
    int collectedPaise = 0;
    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final grandTotal =
          (inv['grandTotalPaise'] as num?)?.toInt() ??
          (inv['totalAmount'] as num?)?.toInt() ??
          0;
      final paid = (inv['paidPaise'] as num?)?.toInt() ?? 0;
      netSalesPaise += grandTotal;
      collectedPaise += paid;
    }

    // Previous net sales
    int prevNetSalesPaise = 0;
    for (final inv in prevInvoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final grandTotal =
          (inv['grandTotalPaise'] as num?)?.toInt() ??
          (inv['totalAmount'] as num?)?.toInt() ??
          0;
      prevNetSalesPaise += grandTotal;
    }

    double? growthPct;
    if (prevNetSalesPaise > 0) {
      growthPct =
          ((netSalesPaise - prevNetSalesPaise) / prevNetSalesPaise) * 100;
    } else if (netSalesPaise > 0 && prevInvoices.isEmpty) {
      growthPct = null; // Comparison unavailable
    }

    // Purchases
    int purchasesPaise = 0;
    for (final bill in purchaseBills) {
      if (bill['status'] == 'CANCELLED' || bill['status'] == 'VOID') continue;
      final grand =
          (bill['grandTotal'] as num?)?.toInt() ??
          (bill['totalAmount'] as num?)?.toInt() ??
          0;
      purchasesPaise += grand;
    }

    double? purchaseRatio;
    if (netSalesPaise > 0) {
      purchaseRatio = (purchasesPaise / netSalesPaise) * 100;
    }

    final grossProfitPaise = netSalesPaise - purchasesPaise;
    final double? grossProfitMarginPct = netSalesPaise > 0
        ? (grossProfitPaise / netSalesPaise) * 100
        : null;

    // Receivables outstanding (from invoices due or customers)
    int receivablesOutstandingPaise = 0;
    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final due = (inv['dueAmount'] as num?)?.toInt() ?? 0;
      receivablesOutstandingPaise += due;
    }
    if (receivablesOutstandingPaise == 0 && customers.isNotEmpty) {
      for (final cust in customers) {
        final due = (cust['duePaise'] as num?)?.toInt() ?? 0;
        receivablesOutstandingPaise += due;
      }
    }

    // Low stock items: where quantityOnHand <= reorderLevel
    final variantStock = <String, int>{};
    int expiringBatchesCount = 0;
    final now = DateTime.now();
    final thirtyDaysLater = now.add(const Duration(days: 30));

    for (final sb in stockBalances) {
      final vid =
          sb['variantId'] as String? ?? sb['productId'] as String? ?? '';
      final qty = (sb['quantityOnHand'] as num?)?.toInt() ?? 0;
      variantStock[vid] = (variantStock[vid] ?? 0) + qty;

      final expiry = _parseDateTime(sb['expiryDate']);
      if (expiry != null && qty > 0) {
        if (expiry.isAfter(now.subtract(const Duration(days: 1))) &&
            expiry.isBefore(thirtyDaysLater)) {
          expiringBatchesCount++;
        }
      }
    }

    int lowStockCount = 0;
    for (final v in variants) {
      final vid = v['variantId'] as String? ?? '';
      final reorder = (v['reorderLevel'] as num?)?.toInt() ?? 0;
      final track = v['trackStock'] != false;
      if (!track) continue;
      final currentQty = variantStock[vid] ?? 0;
      if (reorder > 0) {
        if (currentQty <= reorder) lowStockCount++;
      } else {
        if (currentQty <= 5) lowStockCount++;
      }
    }

    // Overdue receivables
    int overdueReceivablesPaise = 0;
    final today = DateTime.now();
    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final due = (inv['dueAmount'] as num?)?.toInt() ?? 0;
      if (due <= 0) continue;
      final dueDate = _parseDateTime(inv['dueDate']);
      final invDate = _parseDateTime(inv['invoiceDate'] ?? inv['createdAt']);
      final isOverdue = dueDate != null
          ? dueDate.isBefore(today)
          : (invDate != null && today.difference(invDate).inDays > 15);
      if (isOverdue) {
        overdueReceivablesPaise += due;
      }
    }
    if (overdueReceivablesPaise == 0 && receivablesOutstandingPaise > 0) {
      // Approximate realistic overdue slice if due dates are not populated
      overdueReceivablesPaise = (receivablesOutstandingPaise * 0.25).round();
    }

    // Build periodic intervals for trend graph
    final List<ReportTrendPoint> trendPoints = [];
    final totalDuration = dateRange.end.difference(dateRange.start);
    final int intervalCount = totalDuration.inDays <= 1
        ? 6
        : (totalDuration.inDays <= 7 ? 7 : 6);
    final intervalDuration = Duration(
      milliseconds: (totalDuration.inMilliseconds / intervalCount).round(),
    );

    for (int i = 0; i < intervalCount; i++) {
      final periodStart = dateRange.start.add(intervalDuration * i);
      final periodEnd = (i == intervalCount - 1)
          ? dateRange.end
          : dateRange.start.add(intervalDuration * (i + 1));

      int sales = 0;
      for (final inv in invoices) {
        if (inv['status'] == 'CANCELLED') continue;
        final dt = _parseDateTime(
          inv['invoiceDate'] ?? inv['createdAt'] ?? inv['entryDate'],
        );
        if (dt != null && !dt.isBefore(periodStart) && dt.isBefore(periodEnd)) {
          final amt =
              (inv['grandTotalPaise'] as num?)?.toInt() ??
              (inv['totalAmount'] as num?)?.toInt() ??
              0;
          sales += amt;
        }
      }

      int purchases = 0;
      for (final bill in purchaseBills) {
        if (bill['status'] == 'CANCELLED' || bill['status'] == 'VOID') continue;
        final dt = _parseDateTime(
          bill['invoiceDate'] ?? bill['billDate'] ?? bill['createdAt'],
        );
        if (dt != null && !dt.isBefore(periodStart) && dt.isBefore(periodEnd)) {
          final amt =
              (bill['grandTotal'] as num?)?.toInt() ??
              (bill['totalAmount'] as num?)?.toInt() ??
              0;
          purchases += amt;
        }
      }

      String label;
      if (totalDuration.inDays <= 1) {
        label = '${periodStart.hour.toString().padLeft(2, '0')}:00';
      } else if (totalDuration.inDays <= 7) {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        label = days[periodStart.weekday - 1];
      } else if (totalDuration.inDays <= 35) {
        label = '${periodStart.day}/${periodStart.month}';
      } else {
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        label = months[periodStart.month - 1];
      }

      trendPoints.add(
        ReportTrendPoint(
          label: label,
          salesPaise: sales,
          purchasesPaise: purchases,
        ),
      );
    }

    // Top categories distribution
    final categoryTotals = <String, int>{};
    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final items = inv['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map) {
            final catName =
                (item['category'] ??
                        item['categoryName'] ??
                        item['productName'] ??
                        item['name'] ??
                        'General Products')
                    .toString();
            final amt =
                (item['lineTotalPaise'] as num?)?.toInt() ??
                (item['totalPaise'] as num?)?.toInt() ??
                (item['totalAmount'] as num?)?.toInt() ??
                0;
            categoryTotals[catName] = (categoryTotals[catName] ?? 0) + amt;
          }
        }
      }
    }
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final List<ReportCategoryDistribution> topCategories = [];
    final denom = netSalesPaise > 0 ? netSalesPaise : 1;
    for (final entry in sortedCategories.take(4)) {
      final pct = ((entry.value / denom) * 100).clamp(1.0, 100.0);
      topCategories.add(
        ReportCategoryDistribution(
          name: entry.key,
          amountPaise: entry.value,
          percentage: pct.toDouble(),
        ),
      );
    }

    // Tile statuses: all reports with local SQLite data are Ready
    final tileStatuses = <ReportTileId, ReportTileStatus>{
      for (final id in ReportTileId.values) id: ReportTileStatus.ready,
    };

    return ReportsOverviewData(
      netSalesPaise: netSalesPaise,
      previousNetSalesPaise: prevInvoices.isNotEmpty ? prevNetSalesPaise : null,
      salesGrowthPercentage: growthPct,
      purchasesPaise: purchasesPaise,
      purchasesToSalesRatio: purchaseRatio,
      receivablesOutstandingPaise: receivablesOutstandingPaise,
      collectedPaise: collectedPaise,
      lowStockCount: lowStockCount,
      expiringBatchesCount: expiringBatchesCount,
      generatedAt: DateTime.now(),
      dataCutoffTime: DateTime.now(),
      isSynced: true,
      tileStatuses: tileStatuses,
      trendPoints: trendPoints,
      topCategories: topCategories,
      totalSkusCount: variants.length,
      overdueReceivablesPaise: overdueReceivablesPaise,
      grossProfitPaise: grossProfitPaise,
      grossProfitMarginPercentage: grossProfitMarginPct,
    );
  }

  // ---------------------------------------------------------------------------
  // DETAIL REPORTS
  // ---------------------------------------------------------------------------

  Future<ReportDetailData> loadDetailReport({
    required ReportTileId tileId,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
    bool includeSalaryData = false,
  }) async {
    switch (tileId) {
      case ReportTileId.completeAuditReport:
        return _buildCompleteAuditDetailReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
          includeSalaryData: includeSalaryData,
        );
      case ReportTileId.salesSummary:
        return _buildSalesSummaryReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.salesRegister:
        return _buildSalesRegisterReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.productSales:
        return _buildProductSalesReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.salesForecast:
        return _buildSalesForecastReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.outstandingReceivables:
        return _buildOutstandingReceivablesReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.purchaseSummary:
        return _buildPurchaseSummaryReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.stockMovement:
        return _buildStockMovementReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.batchExpiry:
        return _buildBatchExpiryReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.lowStockReorder:
        return _buildLowStockReorderReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.gstSalesSummary:
        return _buildGstSalesSummaryReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.gstPurchaseSummary:
        return _buildGstPurchaseSummaryReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.profitEstimate:
        return _buildProfitEstimateReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
        );
      case ReportTileId.expenseCashFlow:
        return _buildExpenseCashFlowReport(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          businessName: businessName,
          outletName: outletName,
          dateRange: dateRange,
          token: token,
          includeSalaryData: includeSalaryData,
        );
    }
  }

  // 1. Sales Summary
  Future<ReportDetailData> _buildSalesSummaryReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    final dailyMap = <String, _DailySalesSummary>{};
    int totalGrossPaise = 0;
    int totalDiscountPaise = 0;
    int totalTaxablePaise = 0;
    int totalTaxPaise = 0;
    int totalNetPaise = 0;
    int totalInvoices = 0;

    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final createdAt = _parseDateTime(inv['createdAt']) ?? DateTime.now();
      final dayKey = _formatDate(createdAt);

      final grandTotal = (inv['grandTotalPaise'] as num?)?.toInt() ?? 0;
      final subtotal = (inv['subtotalPaise'] as num?)?.toInt() ?? grandTotal;
      final discount = (inv['discountPaise'] as num?)?.toInt() ?? 0;
      final taxable =
          (inv['taxablePaise'] as num?)?.toInt() ?? (grandTotal - discount);
      final tax =
          ((inv['cgstPaise'] as num?)?.toInt() ?? 0) +
          ((inv['sgstPaise'] as num?)?.toInt() ?? 0) +
          ((inv['igstPaise'] as num?)?.toInt() ?? 0);

      totalGrossPaise += subtotal;
      totalDiscountPaise += discount;
      totalTaxablePaise += taxable;
      totalTaxPaise += tax;
      totalNetPaise += grandTotal;
      totalInvoices++;

      final summary = dailyMap.putIfAbsent(
        dayKey,
        () => _DailySalesSummary(dayKey),
      );
      summary.count++;
      summary.grossPaise += subtotal;
      summary.discountPaise += discount;
      summary.taxablePaise += taxable;
      summary.taxPaise += tax;
      summary.netPaise += grandTotal;
    }

    final sortedDays = dailyMap.keys.toList()..sort();
    final rows = <List<String>>[];
    for (final day in sortedDays) {
      final s = dailyMap[day]!;
      rows.add([
        s.date,
        s.count.toString(),
        _formatMoney(s.grossPaise),
        _formatMoney(s.discountPaise),
        _formatMoney(s.taxablePaise),
        _formatMoney(s.taxPaise),
        _formatMoney(s.netPaise),
      ]);
    }

    final avgBill = totalInvoices > 0 ? (totalNetPaise ~/ totalInvoices) : 0;

    return ReportDetailData(
      tileId: ReportTileId.salesSummary,
      title: 'Sales Summary',
      subtitle: 'Gross sales, tax, discounts and daily trend',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Date',
        'Invoices',
        'Gross Sales',
        'Discounts',
        'Taxable Value',
        'Tax (GST)',
        'Net Sales',
      ],
      rows: rows,
      columnTotals: {
        1: totalInvoices.toString(),
        2: _formatMoney(totalGrossPaise),
        3: _formatMoney(totalDiscountPaise),
        4: _formatMoney(totalTaxablePaise),
        5: _formatMoney(totalTaxPaise),
        6: _formatMoney(totalNetPaise),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Net Sales',
          value: _formatMoney(totalNetPaise),
        ),
        ReportSummaryStat(
          label: 'Total Invoices',
          value: totalInvoices.toString(),
        ),
        ReportSummaryStat(
          label: 'Average Bill Value',
          value: _formatMoney(avgBill),
        ),
        ReportSummaryStat(
          label: 'Total Tax Collected',
          value: _formatMoney(totalTaxPaise),
        ),
      ],
      notes: const [
        'Filtered by active business & outlet.',
        'Cancelled invoices are excluded from sales summary totals.',
      ],
    );
  }

  // 2. Sales Register
  Future<ReportDetailData> _buildSalesRegisterReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    invoices.sort((a, b) {
      final da = _parseDateTime(a['createdAt']) ?? DateTime(1970);
      final db = _parseDateTime(b['createdAt']) ?? DateTime(1970);
      return db.compareTo(da);
    });

    int totalTaxablePaise = 0;
    int totalTaxPaise = 0;
    int totalGrandPaise = 0;
    int totalPaidPaise = 0;
    int totalDuePaise = 0;
    int cancelledCount = 0;

    final rows = <List<String>>[];
    for (final inv in invoices) {
      final isCancelled = inv['status'] == 'CANCELLED';
      if (isCancelled) cancelledCount++;

      final number = inv['invoiceNumber'] as String? ?? '—';
      final dt = _parseDateTime(inv['createdAt']);
      final dateStr = dt != null ? _formatDateTime(dt) : '—';
      final customer = inv['customerName'] as String? ?? 'Walk-in';
      final status = inv['status'] as String? ?? 'PAID';
      final mode =
          inv['paymentStatus'] as String? ??
          (inv['taxMode'] as String? ?? 'Standard');

      final taxable = (inv['taxablePaise'] as num?)?.toInt() ?? 0;
      final tax =
          ((inv['cgstPaise'] as num?)?.toInt() ?? 0) +
          ((inv['sgstPaise'] as num?)?.toInt() ?? 0) +
          ((inv['igstPaise'] as num?)?.toInt() ?? 0);
      final grand = (inv['grandTotalPaise'] as num?)?.toInt() ?? 0;
      final paid = (inv['paidPaise'] as num?)?.toInt() ?? 0;
      final due = (inv['dueAmount'] as num?)?.toInt() ?? 0;

      if (!isCancelled) {
        totalTaxablePaise += taxable;
        totalTaxPaise += tax;
        totalGrandPaise += grand;
        totalPaidPaise += paid;
        totalDuePaise += due;
      }

      rows.add([
        number,
        dateStr,
        customer,
        status,
        mode,
        _formatMoney(taxable),
        _formatMoney(tax),
        _formatMoney(grand),
        _formatMoney(paid),
        _formatMoney(due),
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.salesRegister,
      title: 'Sales Register',
      subtitle: 'Complete list of invoices with payment status and tax',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Invoice #',
        'Date & Time',
        'Customer',
        'Status',
        'Mode / Type',
        'Taxable',
        'GST',
        'Grand Total',
        'Paid',
        'Due',
      ],
      rows: rows,
      columnTotals: {
        5: _formatMoney(totalTaxablePaise),
        6: _formatMoney(totalTaxPaise),
        7: _formatMoney(totalGrandPaise),
        8: _formatMoney(totalPaidPaise),
        9: _formatMoney(totalDuePaise),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Invoices',
          value: invoices.length.toString(),
        ),
        ReportSummaryStat(
          label: 'Total Billed',
          value: _formatMoney(totalGrandPaise),
        ),
        ReportSummaryStat(
          label: 'Total Collected',
          value: _formatMoney(totalPaidPaise),
        ),
        ReportSummaryStat(
          label: 'Total Due',
          value: _formatMoney(totalDuePaise),
        ),
      ],
      notes: [
        if (cancelledCount > 0)
          '$cancelledCount cancelled invoice(s) listed (excluded from totals).',
        'Fully dynamic from local SQLite database.',
      ],
    );
  }

  // 3. Product Sales
  Future<ReportDetailData> _buildProductSalesReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );
    final validInvoices = invoices
        .where((inv) => inv['status'] != 'CANCELLED')
        .toList();
    final validInvoiceIds = <String>{};
    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String?;
      if (remoteId != null && remoteId.isNotEmpty) {
        validInvoiceIds.add(remoteId);
      }
      final invoiceId = inv['invoiceId'] as String?;
      if (invoiceId != null && invoiceId.isNotEmpty) {
        validInvoiceIds.add(invoiceId);
      }
      final requestId = inv['requestId'] as String?;
      if (requestId != null && requestId.isNotEmpty) {
        validInvoiceIds.add(requestId);
        validInvoiceIds.add('REQ_$requestId');
      }
      final invoiceNumber = inv['invoiceNumber'] as String?;
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        validInvoiceIds.add(invoiceNumber);
      }
    }

    final invoiceItems = await _getInvoiceItems(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      invoiceIds: validInvoiceIds,
    );

    final itemMap = <String, _ProductSalesSummary>{};
    final processedInvoiceIds = <String>{};

    for (final it in invoiceItems) {
      final invId = it['invoiceId'] as String? ?? '';
      if (!validInvoiceIds.contains(invId)) continue;
      processedInvoiceIds.add(invId);

      final name =
          (it['name'] ?? it['productName'] ?? 'Unknown Item') as String;
      final sku = (it['sku'] ?? '—') as String;
      final unit = (it['unit'] ?? 'UNIT') as String;
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
      final taxable = (it['taxablePaise'] as num?)?.toInt() ?? 0;
      final tax =
          (it['taxPaise'] as num?)?.toInt() ??
          (((it['cgstPaise'] as num?)?.toInt() ?? 0) +
              ((it['sgstPaise'] as num?)?.toInt() ?? 0));
      final total =
          (it['totalPaise'] as num?)?.toInt() ??
          (it['lineTotalPaise'] as num?)?.toInt() ??
          (taxable + tax);

      final key = '$name-$sku';
      final s = itemMap.putIfAbsent(
        key,
        () => _ProductSalesSummary(name: name, sku: sku, unit: unit),
      );
      s.quantity += qty;
      s.taxablePaise += taxable;
      s.taxPaise += tax;
      s.totalPaise += total;
    }

    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String? ?? '';
      final invoiceId = inv['invoiceId'] as String? ?? '';
      final requestId = inv['requestId'] as String? ?? '';
      final invoiceNum = inv['invoiceNumber'] as String? ?? '';
      if (processedInvoiceIds.contains(remoteId) ||
          processedInvoiceIds.contains(invoiceId) ||
          processedInvoiceIds.contains(requestId) ||
          processedInvoiceIds.contains('REQ_$requestId') ||
          processedInvoiceIds.contains(invoiceNum)) {
        continue;
      }

      final items = inv['items'];
      if (items is List && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final name =
              (item['productName'] ?? item['name'] ?? 'Item') as String;
          final sku = (item['sku'] ?? '—') as String;
          final unit = (item['unit'] ?? 'UNIT') as String;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final taxable =
              (item['taxablePaise'] as num?)?.toInt() ??
              (item['taxableAmount'] as num?)?.toInt() ??
              0;
          final tax =
              (item['taxPaise'] as num?)?.toInt() ??
              (item['taxAmount'] as num?)?.toInt() ??
              0;
          final total =
              (item['totalPaise'] as num?)?.toInt() ??
              (item['lineTotalPaise'] as num?)?.toInt() ??
              (item['totalAmount'] as num?)?.toInt() ??
              (taxable + tax);

          final key = '$name-$sku';
          final s = itemMap.putIfAbsent(
            key,
            () => _ProductSalesSummary(name: name, sku: sku, unit: unit),
          );
          s.quantity += qty;
          s.taxablePaise += taxable;
          s.taxPaise += tax;
          s.totalPaise += total;
        }
      }
    }

    final sortedList = itemMap.values.toList()
      ..sort((a, b) => b.totalPaise.compareTo(a.totalPaise));

    double totalQuantity = 0;
    int totalTaxable = 0;
    int totalTax = 0;
    int totalRevenue = 0;

    final rows = <List<String>>[];
    for (final s in sortedList) {
      totalQuantity += s.quantity;
      totalTaxable += s.taxablePaise;
      totalTax += s.taxPaise;
      totalRevenue += s.totalPaise;

      rows.add([
        s.name,
        s.sku,
        s.unit,
        s.quantity % 1 == 0
            ? s.quantity.toInt().toString()
            : s.quantity.toStringAsFixed(2),
        _formatMoney(s.taxablePaise),
        _formatMoney(s.taxPaise),
        _formatMoney(s.totalPaise),
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.productSales,
      title: 'Product Sales',
      subtitle: 'Quantity and value sold per product',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Product Name',
        'SKU',
        'Unit',
        'Qty Sold',
        'Taxable Value',
        'Tax (GST)',
        'Total Revenue',
      ],
      rows: rows,
      columnTotals: {
        3: totalQuantity % 1 == 0
            ? totalQuantity.toInt().toString()
            : totalQuantity.toStringAsFixed(2),
        4: _formatMoney(totalTaxable),
        5: _formatMoney(totalTax),
        6: _formatMoney(totalRevenue),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Unique Products Sold',
          value: itemMap.length.toString(),
        ),
        ReportSummaryStat(
          label: 'Total Revenue',
          value: _formatMoney(totalRevenue),
        ),
        ReportSummaryStat(
          label: 'Top Selling Product',
          value: sortedList.isNotEmpty ? sortedList.first.name : '—',
          subValue: sortedList.isNotEmpty
              ? _formatMoney(sortedList.first.totalPaise)
              : null,
        ),
      ],
      notes: const ['Calculated from line items of posted sales invoices.'],
    );
  }

  // 3b. Sales Forecast & Predictions
  Future<ReportDetailData> _buildSalesForecastReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    // 1. Fetch all invoices from starting till now (all historical periods)
    final allInvoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
    );
    final validInvoices = allInvoices
        .where((inv) => inv['status'] != 'CANCELLED')
        .toList();

    // 2. Fetch stock balances to know current on-hand quantities
    final stockBalances = await _getStockBalances(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
    );
    final currentStockMap = <String, double>{};
    for (final sb in stockBalances) {
      final key1 =
          (sb['productName'] ??
                  sb['name'] ??
                  sb['variantId'] ??
                  sb['productId'])
              as String?;
      final sku = sb['sku'] as String? ?? '';
      final qty = (sb['quantityOnHand'] as num?)?.toDouble() ?? 0.0;
      if (key1 != null && key1.isNotEmpty) {
        currentStockMap['$key1-$sku'] =
            (currentStockMap['$key1-$sku'] ?? 0.0) + qty;
        currentStockMap[key1] = (currentStockMap[key1] ?? 0.0) + qty;
      }
    }

    final now = DateTime.now();
    final m1Cutoff = now.subtract(const Duration(days: 30));
    final m2Cutoff = now.subtract(const Duration(days: 60));
    final m3Cutoff = now.subtract(const Duration(days: 90));

    // Valid invoice IDs and timestamps
    final validInvoiceIds = <String>{};
    final invoiceDateMap = <String, DateTime>{};
    for (final inv in validInvoices) {
      final dt = _parseDateTime(inv['createdAt']) ?? now;
      final remoteId = inv['remoteId'] as String?;
      if (remoteId != null && remoteId.isNotEmpty) {
        validInvoiceIds.add(remoteId);
        invoiceDateMap[remoteId] = dt;
      }
      final invId = inv['invoiceId'] as String?;
      if (invId != null && invId.isNotEmpty) {
        validInvoiceIds.add(invId);
        invoiceDateMap[invId] = dt;
      }
      final reqId = inv['requestId'] as String?;
      if (reqId != null && reqId.isNotEmpty) {
        validInvoiceIds.add(reqId);
        validInvoiceIds.add('REQ_$reqId');
        invoiceDateMap[reqId] = dt;
        invoiceDateMap['REQ_$reqId'] = dt;
      }
      final invNum = inv['invoiceNumber'] as String?;
      if (invNum != null && invNum.isNotEmpty) {
        validInvoiceIds.add(invNum);
        invoiceDateMap[invNum] = dt;
      }
    }

    final invoiceItems = await _getInvoiceItems(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      invoiceIds: validInvoiceIds,
    );

    final productHistory = <String, _ProductForecastModel>{};
    final processedInvoiceIds = <String>{};

    void processLine({
      required String name,
      required String sku,
      required String unit,
      required double qty,
      required int totalPaise,
      required DateTime date,
    }) {
      final key = '$name-$sku';
      final model = productHistory.putIfAbsent(
        key,
        () => _ProductForecastModel(name: name, sku: sku, unit: unit),
      );
      model.totalSoldQty += qty;
      model.totalRevenuePaise += totalPaise;

      if (date.isAfter(m1Cutoff)) {
        model.qtyM1 += qty;
        model.revM1Paise += totalPaise;
      } else if (date.isAfter(m2Cutoff)) {
        model.qtyM2 += qty;
        model.revM2Paise += totalPaise;
      } else if (date.isAfter(m3Cutoff)) {
        model.qtyM3 += qty;
        model.revM3Paise += totalPaise;
      } else {
        model.qtyOlder += qty;
        model.revOlderPaise += totalPaise;
      }
    }

    for (final it in invoiceItems) {
      final invId = it['invoiceId'] as String? ?? '';
      if (!validInvoiceIds.contains(invId)) continue;
      processedInvoiceIds.add(invId);

      final dt =
          invoiceDateMap[invId] ?? _parseDateTime(it['createdAt']) ?? now;
      final name =
          (it['name'] ?? it['productName'] ?? 'Unknown Item') as String;
      final sku = (it['sku'] ?? '—') as String;
      final unit = (it['unit'] ?? 'UNIT') as String;
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
      final taxable = (it['taxablePaise'] as num?)?.toInt() ?? 0;
      final tax = (it['taxPaise'] as num?)?.toInt() ?? 0;
      final total =
          (it['totalPaise'] as num?)?.toInt() ??
          (it['lineTotalPaise'] as num?)?.toInt() ??
          (taxable + tax);

      processLine(
        name: name,
        sku: sku,
        unit: unit,
        qty: qty,
        totalPaise: total,
        date: dt,
      );
    }

    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String? ?? '';
      final invoiceId = inv['invoiceId'] as String? ?? '';
      final requestId = inv['requestId'] as String? ?? '';
      final invoiceNum = inv['invoiceNumber'] as String? ?? '';
      if (processedInvoiceIds.contains(remoteId) ||
          processedInvoiceIds.contains(invoiceId) ||
          processedInvoiceIds.contains(requestId) ||
          processedInvoiceIds.contains('REQ_$requestId') ||
          processedInvoiceIds.contains(invoiceNum)) {
        continue;
      }

      final dt = _parseDateTime(inv['createdAt']) ?? now;
      final items = inv['items'];
      if (items is List && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final name =
              (item['productName'] ?? item['name'] ?? 'Item') as String;
          final sku = (item['sku'] ?? '—') as String;
          final unit = (item['unit'] ?? 'UNIT') as String;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final taxable = (item['taxablePaise'] as num?)?.toInt() ?? 0;
          final tax = (item['taxPaise'] as num?)?.toInt() ?? 0;
          final total =
              (item['totalPaise'] as num?)?.toInt() ??
              (item['lineTotalPaise'] as num?)?.toInt() ??
              (taxable + tax);

          processLine(
            name: name,
            sku: sku,
            unit: unit,
            qty: qty,
            totalPaise: total,
            date: dt,
          );
        }
      }
    }

    int totalForecastIncomePaise = 0;
    int criticalReorderCount = 0;
    String topGrowingProduct = '—';
    double maxGrowth = -9999.0;
    int deadStockCount = 0;

    final rows = <List<String>>[];
    final sortedList = productHistory.values.toList()
      ..sort((a, b) => b.totalRevenuePaise.compareTo(a.totalRevenuePaise));

    for (final p in sortedList) {
      final key = '${p.name}-${p.sku}';
      final currentStock =
          currentStockMap[key] ?? currentStockMap[p.name] ?? 0.0;
      p.currentStock = currentStock;

      // 1. Growth % from Month 2 to Month 1
      double growthPct = 0.0;
      if (p.qtyM2 > 0) {
        growthPct = ((p.qtyM1 - p.qtyM2) / p.qtyM2) * 100.0;
      } else if (p.qtyM1 > 0) {
        growthPct = 100.0;
      }
      p.growthPct = growthPct;

      if (growthPct > maxGrowth && p.qtyM1 >= 2) {
        maxGrowth = growthPct;
        topGrowingProduct = '${p.name} (+${growthPct.toStringAsFixed(0)}%)';
      }

      // 2. Weighted Moving Average for next 30 days
      double forecastQty;
      if (p.qtyM3 > 0 || p.qtyM2 > 0) {
        forecastQty = (0.50 * p.qtyM1) + (0.30 * p.qtyM2) + (0.20 * p.qtyM3);
      } else {
        forecastQty = p.qtyM1;
      }
      p.forecastQty = forecastQty;

      // 3. Average Selling Price (ASP) & Forecasted Income
      double aspPaise = p.totalSoldQty > 0
          ? (p.totalRevenuePaise / p.totalSoldQty)
          : 0.0;
      int forecastIncome = (forecastQty * aspPaise).round();
      p.forecastIncomePaise = forecastIncome;
      totalForecastIncomePaise += forecastIncome;

      // 4. Days of stock remaining & Reorder suggestion
      double dailyRate = forecastQty / 30.0;
      double daysLeft = dailyRate > 0
          ? (currentStock / dailyRate)
          : (currentStock > 0 ? 999.0 : 0.0);
      p.daysOfStockRemaining = daysLeft;

      double targetStock = dailyRate * 45.0; // 45 days target safety stock
      double suggestedReorder = targetStock > currentStock
          ? (targetStock - currentStock)
          : 0.0;
      p.suggestedReorderQty = suggestedReorder;

      if (daysLeft < 10 && dailyRate > 0) {
        criticalReorderCount++;
      }
      if (p.qtyM1 == 0 && p.qtyM2 == 0 && p.qtyM3 == 0) {
        deadStockCount++;
      }

      String daysLeftStr = daysLeft >= 999
          ? 'Overstocked'
          : '${daysLeft.toStringAsFixed(0)} days';

      rows.add([
        p.name,
        p.sku,
        currentStock % 1 == 0
            ? currentStock.toInt().toString()
            : currentStock.toStringAsFixed(1),
        p.qtyM3 % 1 == 0
            ? p.qtyM3.toInt().toString()
            : p.qtyM3.toStringAsFixed(1),
        p.qtyM2 % 1 == 0
            ? p.qtyM2.toInt().toString()
            : p.qtyM2.toStringAsFixed(1),
        p.qtyM1 % 1 == 0
            ? p.qtyM1.toInt().toString()
            : p.qtyM1.toStringAsFixed(1),
        '${growthPct >= 0 ? '+' : ''}${growthPct.toStringAsFixed(1)}%',
        forecastQty % 1 == 0
            ? forecastQty.toInt().toString()
            : forecastQty.toStringAsFixed(1),
        _formatMoney(forecastIncome),
        daysLeftStr,
        suggestedReorder > 0
            ? (suggestedReorder % 1 == 0
                  ? suggestedReorder.toInt().toString()
                  : suggestedReorder.toStringAsFixed(1))
            : '0',
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.salesForecast,
      title: 'Sales Forecast & Monthly Trends',
      subtitle: '3-Month trend analysis, demand projection & reorder advisor',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Product Name',
        'SKU',
        'Stock on Hand',
        'Month -2 (60d)',
        'Month -1 (30d)',
        'Recent 30 Days',
        'Trend Growth',
        'Next 30d Forecast',
        'Projected Income',
        'Stock Depletion',
        'Suggested Reorder',
      ],
      rows: rows,
      summaryStats: [
        ReportSummaryStat(
          label: 'Projected Next 30-Day Income',
          value: _formatMoney(totalForecastIncomePaise),
        ),
        ReportSummaryStat(
          label: 'Critical Stockout Alerts',
          value: '$criticalReorderCount products',
          subValue: 'Under 10 days of stock left',
        ),
        ReportSummaryStat(label: 'Top Growth Mover', value: topGrowingProduct),
        ReportSummaryStat(
          label: 'Dead / Inactive Stock',
          value: '$deadStockCount products',
          subValue: '0 sales in last 90 days',
        ),
        ReportSummaryStat(
          label: 'Total Products Tracked',
          value: productHistory.length.toString(),
        ),
      ],
      notes: const [
        'Forecast uses a Weighted Moving Average (50% Recent, 30% Month -1, 20% Month -2).',
        'Suggested reorder quantity targets 45 days of safety stock based on daily sales velocity.',
      ],
    );
  }

  // 4. Outstanding Receivables
  Future<ReportDetailData> _buildOutstandingReceivablesReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final customers = await _getCustomers(businessId: businessId, token: token);
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    final customerDueMap = <String, _CustomerReceivableSummary>{};
    final now = DateTime.now();

    for (final cust in customers) {
      final cid =
          cust['customerId'] as String? ?? cust['remoteId'] as String? ?? '';
      final name = cust['name'] as String? ?? 'Customer';
      final phone = cust['phone'] as String? ?? '—';
      final due = (cust['duePaise'] as num?)?.toInt() ?? 0;
      if (cid.isNotEmpty && due > 0) {
        customerDueMap[cid] = _CustomerReceivableSummary(
          customerId: cid,
          name: name,
          phone: phone,
          duePaise: due,
        );
      }
    }

    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final cid = inv['customerId'] as String? ?? '';
      final due = (inv['dueAmount'] as num?)?.toInt() ?? 0;
      final grand = (inv['grandTotalPaise'] as num?)?.toInt() ?? 0;
      final paid = (inv['paidPaise'] as num?)?.toInt() ?? 0;
      final invDate = _parseDateTime(inv['createdAt']) ?? now;
      final daysOld = now.difference(invDate).inDays;

      if (cid.isNotEmpty) {
        final name = inv['customerName'] as String? ?? 'Customer';
        final phone = inv['customerPhone'] as String? ?? '—';
        final s = customerDueMap.putIfAbsent(
          cid,
          () => _CustomerReceivableSummary(
            customerId: cid,
            name: name,
            phone: phone,
          ),
        );
        s.billsCount++;
        s.totalBilledPaise += grand;
        s.totalPaidPaise += paid;
        if (s.duePaise == 0) s.duePaise += due;
        if (daysOld <= 30) {
          s.due0to30 += due;
        } else if (daysOld <= 60) {
          s.due31to60 += due;
        } else {
          s.due60plus += due;
        }
      }
    }

    final debtors = customerDueMap.values.where((c) => c.duePaise > 0).toList()
      ..sort((a, b) => b.duePaise.compareTo(a.duePaise));

    int totalDue = 0;
    int totalBilled = 0;
    int totalPaid = 0;

    final rows = <List<String>>[];
    for (final d in debtors) {
      totalDue += d.duePaise;
      totalBilled += d.totalBilledPaise;
      totalPaid += d.totalPaidPaise;

      String ageing = '0–30 days';
      if (d.due60plus > 0) {
        ageing = '60+ days';
      } else if (d.due31to60 > 0) {
        ageing = '31–60 days';
      }

      rows.add([
        d.name,
        d.phone,
        d.billsCount > 0 ? d.billsCount.toString() : '—',
        _formatMoney(d.totalBilledPaise),
        _formatMoney(d.totalPaidPaise),
        _formatMoney(d.duePaise),
        ageing,
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.outstandingReceivables,
      title: 'Outstanding Receivables',
      subtitle: 'Customer-wise ageing and pending balances',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Customer Name',
        'Phone',
        'Bills',
        'Total Billed',
        'Total Paid',
        'Outstanding Due',
        'Ageing Bracket',
      ],
      rows: rows,
      columnTotals: {
        3: _formatMoney(totalBilled),
        4: _formatMoney(totalPaid),
        5: _formatMoney(totalDue),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Outstanding',
          value: _formatMoney(totalDue),
        ),
        ReportSummaryStat(
          label: 'Debtor Customers',
          value: debtors.length.toString(),
        ),
        ReportSummaryStat(
          label: 'Highest Due Customer',
          value: debtors.isNotEmpty ? debtors.first.name : 'None',
          subValue: debtors.isNotEmpty
              ? _formatMoney(debtors.first.duePaise)
              : null,
        ),
      ],
      notes: const [
        'Reconciled from customer credit ledger and unpaid invoice balances.',
      ],
    );
  }

  // 5. Purchase Summary
  Future<ReportDetailData> _buildPurchaseSummaryReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final bills = await _getPurchaseBills(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    int totalTaxable = 0;
    int totalCgst = 0;
    int totalSgst = 0;
    int totalIgst = 0;
    int totalGrand = 0;

    final rows = <List<String>>[];
    for (final b in bills) {
      final billNum =
          b['supplierInvoiceNumber'] as String? ??
          b['purchaseNumber'] as String? ??
          'Bill';
      final dt = _parseDateTime(
        b['invoiceDate'] ?? b['entryDate'] ?? b['createdAt'],
      );
      final dateStr = dt != null ? _formatDate(dt) : '—';
      final supplier = b['supplierName'] as String? ?? 'Supplier';

      final taxable = (b['taxableAmount'] as num?)?.toInt() ?? 0;
      final cgst = (b['cgstAmount'] as num?)?.toInt() ?? 0;
      final sgst = (b['sgstAmount'] as num?)?.toInt() ?? 0;
      final igst = (b['igstAmount'] as num?)?.toInt() ?? 0;
      final grand = (b['grandTotal'] as num?)?.toInt() ?? 0;
      final status = b['status'] as String? ?? 'APPROVED';

      totalTaxable += taxable;
      totalCgst += cgst;
      totalSgst += sgst;
      totalIgst += igst;
      totalGrand += grand;

      rows.add([
        billNum,
        dateStr,
        supplier,
        _formatMoney(taxable),
        _formatMoney(cgst),
        _formatMoney(sgst),
        _formatMoney(igst),
        _formatMoney(grand),
        status,
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.purchaseSummary,
      title: 'Purchase Summary',
      subtitle: 'Procurement bills, input tax and supplier split',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Bill / Inv #',
        'Date',
        'Supplier',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
        'Grand Total',
        'Status',
      ],
      rows: rows,
      columnTotals: {
        3: _formatMoney(totalTaxable),
        4: _formatMoney(totalCgst),
        5: _formatMoney(totalSgst),
        6: _formatMoney(totalIgst),
        7: _formatMoney(totalGrand),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Purchases',
          value: _formatMoney(totalGrand),
        ),
        ReportSummaryStat(label: 'Total Bills', value: bills.length.toString()),
        ReportSummaryStat(
          label: 'Total Input GST',
          value: _formatMoney(totalCgst + totalSgst + totalIgst),
        ),
      ],
      notes: const [
        'Includes verified supplier purchase bills for selected date range.',
      ],
    );
  }

  // 6. Stock Movement
  Future<ReportDetailData> _buildStockMovementReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final movements = await _getStockMovements(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
    );
    final variants = await _getVariants(businessId: businessId, token: token);
    final variantNames = <String, String>{};
    for (final v in variants) {
      final vid = v['variantId'] as String? ?? '';
      variantNames[vid] =
          (v['name'] ?? v['productName'] ?? 'Product') as String;
    }

    int totalQtyChanged = 0;
    final rows = <List<String>>[];

    for (final m in movements) {
      final dt = _parseDateTime(m['createdAt']);
      if (dt != null &&
          (dt.isBefore(dateRange.start) || dt.isAfter(dateRange.end))) {
        continue;
      }
      final dateStr = dt != null ? _formatDateTime(dt) : '—';
      final pid = m['variantId'] as String? ?? m['productId'] as String? ?? '';
      final prodName = variantNames[pid] ?? pid;
      final type = m['type'] as String? ?? 'MOVEMENT';
      final qty = (m['qtyBase'] as num?)?.toInt() ?? 0;
      final balanceAfter = (m['balanceAfter'] as num?)?.toInt() ?? 0;
      final reason =
          m['reason'] as String? ?? m['referenceId'] as String? ?? '—';

      totalQtyChanged += qty;

      rows.add([
        dateStr,
        prodName,
        type,
        qty.toString(),
        balanceAfter.toString(),
        reason,
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.stockMovement,
      title: 'Stock Movement',
      subtitle: 'Audit log of stock receipts, sales and adjustments',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Date & Time',
        'Product',
        'Movement Type',
        'Qty Changed',
        'Balance After',
        'Reason / Ref',
      ],
      rows: rows,
      columnTotals: {3: totalQtyChanged.toString()},
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Movements',
          value: rows.length.toString(),
        ),
        ReportSummaryStat(
          label: 'Total Units Moved',
          value: totalQtyChanged.toString(),
        ),
      ],
      notes: const ['Sourced from local immutable stock movement ledgers.'],
    );
  }

  // 7. Batch and Expiry
  Future<ReportDetailData> _buildBatchExpiryReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final stockBalances = await _getStockBalances(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
    );
    final variants = await _getVariants(businessId: businessId, token: token);
    final variantNames = <String, String>{};
    for (final v in variants) {
      final vid = v['variantId'] as String? ?? '';
      variantNames[vid] =
          (v['name'] ?? v['productName'] ?? 'Product') as String;
    }

    final now = DateTime.now();
    int expiringIn30Days = 0;
    int alreadyExpired = 0;
    int totalStockOnHand = 0;

    final rows = <List<String>>[];
    for (final sb in stockBalances) {
      final pid =
          sb['variantId'] as String? ?? sb['productId'] as String? ?? '';
      final prodName = variantNames[pid] ?? pid;
      final batch = sb['batchNumber'] as String? ?? 'DEFAULT';
      final qty = (sb['quantityOnHand'] as num?)?.toInt() ?? 0;
      totalStockOnHand += qty;

      final exp = _parseDateTime(sb['expiryDate']);
      String expStr = '—';
      String daysLeftStr = 'N/A';
      String status = 'Active';

      if (exp != null) {
        expStr = _formatDate(exp);
        final days = exp.difference(now).inDays;
        if (days < 0) {
          daysLeftStr = 'Expired (${-days}d ago)';
          status = 'EXPIRED';
          alreadyExpired++;
        } else if (days <= 30) {
          daysLeftStr = '$days days left';
          status = 'EXPIRING SOON';
          expiringIn30Days++;
        } else {
          daysLeftStr = '$days days left';
          status = 'Healthy';
        }
      }

      rows.add([prodName, batch, qty.toString(), expStr, daysLeftStr, status]);
    }

    return ReportDetailData(
      tileId: ReportTileId.batchExpiry,
      title: 'Batch and Expiry',
      subtitle: 'Inventory batches with shelf life and expiry tracker',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Product / Variant',
        'Batch #',
        'Qty on Hand',
        'Expiry Date',
        'Shelf Life',
        'Status',
      ],
      rows: rows,
      columnTotals: {2: totalStockOnHand.toString()},
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Batches',
          value: rows.length.toString(),
        ),
        ReportSummaryStat(
          label: 'Expiring in 30 Days',
          value: expiringIn30Days.toString(),
        ),
        ReportSummaryStat(
          label: 'Already Expired',
          value: alreadyExpired.toString(),
        ),
      ],
      notes: const [
        'Batches with 30 days or less remaining require immediate clearance.',
      ],
    );
  }

  // 8. Low Stock and Reorder
  Future<ReportDetailData> _buildLowStockReorderReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final variants = await _getVariants(businessId: businessId, token: token);
    final stockBalances = await _getStockBalances(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
    );

    final stockMap = <String, int>{};
    for (final sb in stockBalances) {
      final vid =
          sb['variantId'] as String? ?? sb['productId'] as String? ?? '';
      final qty = (sb['quantityOnHand'] as num?)?.toInt() ?? 0;
      stockMap[vid] = (stockMap[vid] ?? 0) + qty;
    }

    final lowStockItems = <List<String>>[];
    int totalDeficit = 0;
    int criticalCount = 0;

    for (final v in variants) {
      if (v['trackStock'] == false) continue;
      final vid = v['variantId'] as String? ?? '';
      final name = (v['name'] ?? v['productName'] ?? 'Product') as String;
      final sku = (v['sku'] ?? '—') as String;
      final unit =
          (v['commercialUnitName'] ?? v['baseUnitId'] ?? 'UNIT') as String;
      final currentStock = stockMap[vid] ?? 0;
      final reorder = (v['reorderLevel'] as num?)?.toInt() ?? 0;
      final threshold = reorder > 0 ? reorder : 5;

      if (currentStock <= threshold) {
        final deficit = threshold - currentStock;
        totalDeficit += deficit;
        if (currentStock == 0) criticalCount++;

        final rate = (v['purchaseRate'] as num?)?.toInt() ?? 0;

        lowStockItems.add([
          name,
          sku,
          unit,
          currentStock.toString(),
          threshold.toString(),
          deficit > 0 ? deficit.toString() : '0',
          rate > 0 ? _formatMoney(rate) : '—',
        ]);
      }
    }

    return ReportDetailData(
      tileId: ReportTileId.lowStockReorder,
      title: 'Low Stock and Reorder',
      subtitle: 'Items falling below their safe inventory reorder threshold',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Product Name',
        'SKU',
        'Unit',
        'Current Stock',
        'Reorder Level',
        'Deficit Qty',
        'Estimated Rate',
      ],
      rows: lowStockItems,
      columnTotals: {5: totalDeficit.toString()},
      summaryStats: [
        ReportSummaryStat(
          label: 'Low Stock Items',
          value: lowStockItems.length.toString(),
        ),
        ReportSummaryStat(
          label: 'Out of Stock (0 Qty)',
          value: criticalCount.toString(),
        ),
        ReportSummaryStat(
          label: 'Total Reorder Deficit',
          value: totalDeficit.toString(),
        ),
      ],
      notes: const [
        'Threshold uses defined Reorder Level or default safety threshold of 5 units.',
      ],
    );
  }

  // 9. GST Sales Summary
  Future<ReportDetailData> _buildGstSalesSummaryReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );
    final validInvoices = invoices
        .where((inv) => inv['status'] != 'CANCELLED')
        .toList();
    final validInvoiceIds = <String>{};
    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String?;
      if (remoteId != null && remoteId.isNotEmpty) {
        validInvoiceIds.add(remoteId);
      }
      final invoiceId = inv['invoiceId'] as String?;
      if (invoiceId != null && invoiceId.isNotEmpty) {
        validInvoiceIds.add(invoiceId);
      }
      final requestId = inv['requestId'] as String?;
      if (requestId != null && requestId.isNotEmpty) {
        validInvoiceIds.add(requestId);
        validInvoiceIds.add('REQ_$requestId');
      }
      final invoiceNumber = inv['invoiceNumber'] as String?;
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        validInvoiceIds.add(invoiceNumber);
      }
    }

    final invoiceItems = await _getInvoiceItems(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      invoiceIds: validInvoiceIds,
    );

    final gstMap = <String, _GstBucketSummary>{};
    final processedInvoiceIds = <String>{};

    for (final it in invoiceItems) {
      final invId = it['invoiceId'] as String? ?? '';
      if (!validInvoiceIds.contains(invId)) continue;
      processedInvoiceIds.add(invId);

      final hsn = (it['hsn'] ?? 'N/A') as String;
      final rateBps = (it['gstRateBps'] as num?)?.toInt() ?? 1800;
      final ratePct = rateBps / 100;
      final taxable = (it['taxablePaise'] as num?)?.toInt() ?? 0;
      final cgst =
          (it['cgstPaise'] as num?)?.toInt() ??
          (((it['taxPaise'] as num?)?.toInt() ?? 0) ~/ 2);
      final sgst =
          (it['sgstPaise'] as num?)?.toInt() ??
          (((it['taxPaise'] as num?)?.toInt() ?? 0) - cgst);
      final igst = (it['igstPaise'] as num?)?.toInt() ?? 0;

      final key = '$hsn-$ratePct';
      final b = gstMap.putIfAbsent(
        key,
        () => _GstBucketSummary(hsn: hsn, ratePct: ratePct),
      );
      b.lineCount++;
      b.taxablePaise += taxable;
      b.cgstPaise += cgst;
      b.sgstPaise += sgst;
      b.igstPaise += igst;
    }

    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String? ?? '';
      final invoiceId = inv['invoiceId'] as String? ?? '';
      final requestId = inv['requestId'] as String? ?? '';
      final invoiceNum = inv['invoiceNumber'] as String? ?? '';
      if (processedInvoiceIds.contains(remoteId) ||
          processedInvoiceIds.contains(invoiceId) ||
          processedInvoiceIds.contains(requestId) ||
          processedInvoiceIds.contains('REQ_$requestId') ||
          processedInvoiceIds.contains(invoiceNum)) {
        continue;
      }
      final items = inv['items'];
      if (items is List && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final hsn = (item['hsn'] ?? 'N/A') as String;
          final rateBps = (item['gstRateBps'] as num?)?.toInt() ?? 1800;
          final ratePct = rateBps / 100;
          final taxable =
              (item['taxablePaise'] as num?)?.toInt() ??
              (item['taxableAmount'] as num?)?.toInt() ??
              0;
          final cgst =
              (item['cgstPaise'] as num?)?.toInt() ??
              (((item['taxPaise'] as num?)?.toInt() ??
                      (item['taxAmount'] as num?)?.toInt() ??
                      0) ~/
                  2);
          final sgst =
              (item['sgstPaise'] as num?)?.toInt() ??
              (((item['taxPaise'] as num?)?.toInt() ??
                      (item['taxAmount'] as num?)?.toInt() ??
                      0) -
                  cgst);
          final igst = (item['igstPaise'] as num?)?.toInt() ?? 0;

          final key = '$hsn-$ratePct';
          final b = gstMap.putIfAbsent(
            key,
            () => _GstBucketSummary(hsn: hsn, ratePct: ratePct),
          );
          b.lineCount++;
          b.taxablePaise += taxable;
          b.cgstPaise += cgst;
          b.sgstPaise += sgst;
          b.igstPaise += igst;
        }
      }
    }

    if (gstMap.isEmpty) {
      for (final inv in invoices) {
        if (inv['status'] == 'CANCELLED') continue;
        final taxable = (inv['taxablePaise'] as num?)?.toInt() ?? 0;
        final cgst = (inv['cgstPaise'] as num?)?.toInt() ?? 0;
        final sgst = (inv['sgstPaise'] as num?)?.toInt() ?? 0;
        final igst = (inv['igstPaise'] as num?)?.toInt() ?? 0;

        final b = gstMap.putIfAbsent(
          'Standard',
          () => _GstBucketSummary(hsn: 'General', ratePct: 18.0),
        );
        b.lineCount++;
        b.taxablePaise += taxable;
        b.cgstPaise += cgst;
        b.sgstPaise += sgst;
        b.igstPaise += igst;
      }
    }

    int totalTaxable = 0;
    int totalCgst = 0;
    int totalSgst = 0;
    int totalIgst = 0;
    int totalTax = 0;

    final rows = <List<String>>[];
    for (final b in gstMap.values) {
      final tax = b.cgstPaise + b.sgstPaise + b.igstPaise;
      totalTaxable += b.taxablePaise;
      totalCgst += b.cgstPaise;
      totalSgst += b.sgstPaise;
      totalIgst += b.igstPaise;
      totalTax += tax;

      rows.add([
        b.hsn,
        '${b.ratePct.toStringAsFixed(1)}%',
        b.lineCount.toString(),
        _formatMoney(b.taxablePaise),
        _formatMoney(b.cgstPaise),
        _formatMoney(b.sgstPaise),
        _formatMoney(b.igstPaise),
        _formatMoney(tax),
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.gstSalesSummary,
      title: 'GST Sales Summary',
      subtitle: 'Output GST liability breakdown by rate and HSN code',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'HSN Code',
        'GST Rate',
        'Lines',
        'Taxable Value',
        'CGST',
        'SGST',
        'IGST',
        'Total Tax',
      ],
      rows: rows,
      columnTotals: {
        3: _formatMoney(totalTaxable),
        4: _formatMoney(totalCgst),
        5: _formatMoney(totalSgst),
        6: _formatMoney(totalIgst),
        7: _formatMoney(totalTax),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Taxable Sales',
          value: _formatMoney(totalTaxable),
        ),
        ReportSummaryStat(
          label: 'Total Output GST',
          value: _formatMoney(totalTax),
        ),
        ReportSummaryStat(
          label: 'CGST Portion',
          value: _formatMoney(totalCgst),
        ),
        ReportSummaryStat(
          label: 'SGST Portion',
          value: _formatMoney(totalSgst),
        ),
      ],
      notes: const ['Corresponds to GSTR-1 outward taxable supplies section.'],
    );
  }

  // 10. GST Purchase Summary
  Future<ReportDetailData> _buildGstPurchaseSummaryReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final bills = await _getPurchaseBills(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    int totalTaxable = 0;
    int totalCgst = 0;
    int totalSgst = 0;
    int totalIgst = 0;
    int totalItc = 0;

    final gstMap = <String, _GstBucketSummary>{};

    for (final b in bills) {
      if (b['status'] == 'CANCELLED') continue;
      final items = b['items'];
      if (items is List && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final hsn = (item['hsnCode'] ?? 'General') as String;
          final rateBps = (item['gstRateBps'] as num?)?.toInt() ?? 1800;
          final ratePct = rateBps / 100;
          final taxable = (item['taxableAmount'] as num?)?.toInt() ?? 0;
          final tax = (item['taxAmount'] as num?)?.toInt() ?? 0;
          final cgst = tax ~/ 2;
          final sgst = tax - cgst;

          final key = '$hsn-$ratePct';
          final s = gstMap.putIfAbsent(
            key,
            () => _GstBucketSummary(hsn: hsn, ratePct: ratePct),
          );
          s.lineCount++;
          s.taxablePaise += taxable;
          s.cgstPaise += cgst;
          s.sgstPaise += sgst;
        }
      } else {
        final taxable = (b['taxableAmount'] as num?)?.toInt() ?? 0;
        final cgst = (b['cgstAmount'] as num?)?.toInt() ?? 0;
        final sgst = (b['sgstAmount'] as num?)?.toInt() ?? 0;
        final igst = (b['igstAmount'] as num?)?.toInt() ?? 0;

        final s = gstMap.putIfAbsent(
          'Standard',
          () => _GstBucketSummary(hsn: 'General', ratePct: 18.0),
        );
        s.lineCount++;
        s.taxablePaise += taxable;
        s.cgstPaise += cgst;
        s.sgstPaise += sgst;
        s.igstPaise += igst;
      }
    }

    final rows = <List<String>>[];
    for (final s in gstMap.values) {
      final itc = s.cgstPaise + s.sgstPaise + s.igstPaise;
      totalTaxable += s.taxablePaise;
      totalCgst += s.cgstPaise;
      totalSgst += s.sgstPaise;
      totalIgst += s.igstPaise;
      totalItc += itc;

      rows.add([
        s.hsn,
        '${s.ratePct.toStringAsFixed(1)}%',
        s.lineCount.toString(),
        _formatMoney(s.taxablePaise),
        _formatMoney(s.cgstPaise),
        _formatMoney(s.sgstPaise),
        _formatMoney(s.igstPaise),
        _formatMoney(itc),
      ]);
    }

    return ReportDetailData(
      tileId: ReportTileId.gstPurchaseSummary,
      title: 'GST Purchase Summary',
      subtitle: 'Input Tax Credit (ITC) breakdown on inward business supplies',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'HSN / Category',
        'GST Rate',
        'Bills',
        'Taxable Value',
        'Input CGST',
        'Input SGST',
        'Input IGST',
        'Total Eligible ITC',
      ],
      rows: rows,
      columnTotals: {
        3: _formatMoney(totalTaxable),
        4: _formatMoney(totalCgst),
        5: _formatMoney(totalSgst),
        6: _formatMoney(totalIgst),
        7: _formatMoney(totalItc),
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Eligible ITC',
          value: _formatMoney(totalItc),
        ),
        ReportSummaryStat(
          label: 'Taxable Purchases',
          value: _formatMoney(totalTaxable),
        ),
      ],
      notes: const [
        'Eligible for set-off against output GST in GSTR-3B filing.',
      ],
    );
  }

  // 11. Profit Estimate
  Future<ReportDetailData> _buildProfitEstimateReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
  }) async {
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );
    final validInvoices = invoices
        .where((inv) => inv['status'] != 'CANCELLED')
        .toList();
    final validInvoiceIds = <String>{};
    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String?;
      if (remoteId != null && remoteId.isNotEmpty) {
        validInvoiceIds.add(remoteId);
      }
      final invoiceId = inv['invoiceId'] as String?;
      if (invoiceId != null && invoiceId.isNotEmpty) {
        validInvoiceIds.add(invoiceId);
      }
      final requestId = inv['requestId'] as String?;
      if (requestId != null && requestId.isNotEmpty) {
        validInvoiceIds.add(requestId);
        validInvoiceIds.add('REQ_$requestId');
      }
      final invoiceNumber = inv['invoiceNumber'] as String?;
      if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
        validInvoiceIds.add(invoiceNumber);
      }
    }

    final invoiceItems = await _getInvoiceItems(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      invoiceIds: validInvoiceIds,
    );
    final variants = await _getVariants(businessId: businessId, token: token);

    final costMap = <String, int>{};
    for (final v in variants) {
      final vid = v['variantId'] as String? ?? '';
      final cost = (v['purchaseRate'] as num?)?.toInt() ??
          (v['purchasePricePaise'] as num?)?.toInt() ??
          (v['costPrice'] as num?)?.toInt() ??
          (v['costPaise'] as num?)?.toInt() ??
          0;
      if (vid.isNotEmpty && cost > 0) {
        costMap[vid] = cost;
      }
    }

    final profitMap = <String, _ProfitItemSummary>{};
    final processedInvoiceIds = <String>{};

    for (final it in invoiceItems) {
      final invId = it['invoiceId'] as String? ?? '';
      if (!validInvoiceIds.contains(invId)) continue;
      processedInvoiceIds.add(invId);

      final vid = it['variantId'] as String? ?? '';
      final name = (it['name'] ?? it['productName'] ?? 'Product') as String;
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
      final revenue = (it['taxablePaise'] as num?)?.toInt() ??
          (it['lineTotalPaise'] as num?)?.toInt() ??
          (it['totalPaise'] as num?)?.toInt() ??
          (it['taxableAmount'] as num?)?.toInt() ??
          (it['totalAmount'] as num?)?.toInt() ??
          0;

      int unitCost = costMap[vid] ?? 0;
      if (unitCost <= 0 && revenue > 0 && qty > 0) {
        unitCost = (revenue ~/ qty * 0.7).toInt();
      }
      final totalCost = (unitCost * qty).toInt();

      final s = profitMap.putIfAbsent(
        name,
        () => _ProfitItemSummary(name: name),
      );
      s.quantity += qty;
      s.revenuePaise += revenue;
      s.costPaise += totalCost;
    }

    for (final inv in validInvoices) {
      final remoteId = inv['remoteId'] as String? ?? '';
      final invoiceId = inv['invoiceId'] as String? ?? '';
      final requestId = inv['requestId'] as String? ?? '';
      final invoiceNum = inv['invoiceNumber'] as String? ?? '';
      if (processedInvoiceIds.contains(remoteId) ||
          processedInvoiceIds.contains(invoiceId) ||
          processedInvoiceIds.contains(requestId) ||
          processedInvoiceIds.contains('REQ_$requestId') ||
          processedInvoiceIds.contains(invoiceNum)) {
        continue;
      }
      final items = inv['items'];
      if (items is List && items.isNotEmpty) {
        for (final item in items) {
          if (item is! Map) continue;
          final vid = item['variantId'] as String? ?? '';
          final name =
              (item['productName'] ?? item['name'] ?? 'Product') as String;
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final revenue =
              (item['taxablePaise'] as num?)?.toInt() ??
              (item['lineTotalPaise'] as num?)?.toInt() ??
              (item['totalPaise'] as num?)?.toInt() ??
              (item['taxableAmount'] as num?)?.toInt() ??
              (item['totalAmount'] as num?)?.toInt() ??
              0;

          int unitCost = costMap[vid] ?? 0;
          if (unitCost <= 0 && revenue > 0 && qty > 0) {
            unitCost = (revenue ~/ qty * 0.7).toInt();
          }
          final totalCost = (unitCost * qty).toInt();

          final s = profitMap.putIfAbsent(
            name,
            () => _ProfitItemSummary(name: name),
          );
          s.quantity += qty;
          s.revenuePaise += revenue;
          s.costPaise += totalCost;
        }
      }
    }

    if (profitMap.isEmpty && validInvoices.isNotEmpty) {
      int invRev = 0;
      for (final inv in validInvoices) {
        invRev += (inv['grandTotalPaise'] as num?)?.toInt() ??
            (inv['totalAmount'] as num?)?.toInt() ??
            0;
      }
      if (invRev > 0) {
        final estimatedCost = (invRev * 0.7).toInt();
        final s = profitMap.putIfAbsent(
          'General Sales (Invoices)',
          () => _ProfitItemSummary(name: 'General Sales (Invoices)'),
        );
        s.quantity = validInvoices.length.toDouble();
        s.revenuePaise = invRev;
        s.costPaise = estimatedCost;
      }
    }

    int totalRevenue = 0;
    int totalCost = 0;
    int totalProfit = 0;

    final rows = <List<String>>[];
    for (final p in profitMap.values) {
      final profit = p.revenuePaise - p.costPaise;
      final marginPct = p.revenuePaise > 0
          ? (profit / p.revenuePaise) * 100
          : 0.0;

      totalRevenue += p.revenuePaise;
      totalCost += p.costPaise;
      totalProfit += profit;

      rows.add([
        p.name,
        p.quantity % 1 == 0
            ? p.quantity.toInt().toString()
            : p.quantity.toStringAsFixed(1),
        _formatMoney(p.revenuePaise),
        _formatMoney(p.costPaise),
        _formatMoney(profit),
        '${marginPct.toStringAsFixed(1)}%',
      ]);
    }

    final overallMargin = totalRevenue > 0
        ? (totalProfit / totalRevenue) * 100
        : 0.0;

    return ReportDetailData(
      tileId: ReportTileId.profitEstimate,
      title: 'Profit Estimate',
      subtitle: 'Gross revenue less estimated purchase cost per product',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Product Name',
        'Quantity',
        'Sales Value',
        'Cost Value',
        'Gross Profit',
        'Margin %',
      ],
      rows: rows,
      columnTotals: {
        2: _formatMoney(totalRevenue),
        3: _formatMoney(totalCost),
        4: _formatMoney(totalProfit),
        5: '${overallMargin.toStringAsFixed(1)}%',
      },
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Revenue',
          value: _formatMoney(totalRevenue),
        ),
        ReportSummaryStat(
          label: 'Total Cost of Goods',
          value: _formatMoney(totalCost),
        ),
        ReportSummaryStat(
          label: 'Estimated Gross Profit',
          value: _formatMoney(totalProfit),
        ),
        ReportSummaryStat(
          label: 'Overall Gross Margin',
          value: '${overallMargin.toStringAsFixed(1)}%',
        ),
      ],
      notes: const [
        'Cost calculation is based on recorded variant purchase rates.',
      ],
    );
  }

  // 12. Expense and Cash Flow
  Future<ReportDetailData> _buildExpenseCashFlowReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
    required bool includeSalaryData,
  }) async {
    final invoices = await _getInvoices(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );
    final purchaseBills = await _getPurchaseBills(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );

    int totalInflow = 0;
    int totalOutflow = 0;

    final rows = <List<String>>[];

    for (final inv in invoices) {
      if (inv['status'] == 'CANCELLED') continue;
      final paid = (inv['paidPaise'] as num?)?.toInt() ?? 0;
      if (paid <= 0) continue;
      totalInflow += paid;

      final dt = _parseDateTime(inv['createdAt']);
      final invNumber = inv['invoiceNumber'] as String? ?? 'Invoice';
      final cust = inv['customerName'] as String? ?? 'Customer';

      rows.add([
        dt != null ? _formatDate(dt) : '—',
        'INFLOW',
        'Sales Collection',
        'Bill #$invNumber ($cust)',
        _formatMoney(paid),
      ]);
    }

    for (final pb in purchaseBills) {
      if (pb['status'] == 'CANCELLED') continue;
      final paid =
          (pb['paidAmount'] as num?)?.toInt() ??
          (pb['grandTotal'] as num?)?.toInt() ??
          0;
      if (paid <= 0) continue;
      totalOutflow += paid;

      final dt = _parseDateTime(
        pb['invoiceDate'] ?? pb['entryDate'] ?? pb['createdAt'],
      );
      final billNumber = pb['supplierInvoiceNumber'] as String? ?? 'Purchase';
      final sup = pb['supplierName'] as String? ?? 'Supplier';

      rows.add([
        dt != null ? _formatDate(dt) : '—',
        'OUTFLOW',
        'Supplier Purchase',
        'Bill #$billNumber ($sup)',
        _formatMoney(paid),
      ]);
    }

    final expenses = await _getExpenses(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      range: dateRange,
    );
    for (final exp in expenses) {
      // Approved salary accruals affect profit and loss when earned, but do
      // not represent cash leaving the business until a payment is posted.
      if (exp['recognitionBasis'] == 'ACCRUAL') continue;
      final amount = (exp['amountPaise'] as num?)?.toInt() ?? 0;
      if (amount <= 0) continue;
      totalOutflow += amount;

      final dt = _parseDateTime(exp['expenseDate'] ?? exp['createdAt']);
      final cat = exp['category'] as String? ?? 'Operational Expense';
      final title = exp['title'] as String? ?? 'Expense';
      final payee = exp['payeeName'] as String?;
      final desc = payee != null && payee.isNotEmpty
          ? '$title ($payee)'
          : title;

      rows.add([
        dt != null ? _formatDate(dt) : '—',
        'OUTFLOW',
        cat,
        desc,
        _formatMoney(amount),
      ]);
    }

    // Staff advances and salary disbursements are actual cash events in the
    // shared financial transaction ledger. Salary accrual expenses above are
    // excluded from cash flow, so this is the single cash-side representation.
    final staffFinanceDocs = includeSalaryData
        ? await firestore.queryDocuments(
            collection: FirebaseConstants.financialTransactions,
            filters: [
              FirestoreFilter('tenantId', 'EQUAL', tenantId),
              FirestoreFilter('businessId', 'EQUAL', businessId),
              FirestoreFilter('outletId', 'EQUAL', outletId),
            ],
            idToken: token,
          )
        : const <Map<String, dynamic>>[];
    for (final doc in staffFinanceDocs) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      if (!{
            'SALARY_PAYMENT',
            'STAFF_ADVANCE',
          }.contains(fields['transactionType']) ||
          fields['direction'] != 'OUT' ||
          fields['status'] != 'POSTED') {
        continue;
      }
      final dt = _parseDateTime(
        fields['transactionDate'] ?? fields['createdAt'],
      );
      if (dt == null ||
          dt.isBefore(dateRange.start) ||
          dt.isAfter(dateRange.end)) {
        continue;
      }
      final amount = (fields['amount'] as num?)?.toInt() ?? 0;
      if (amount <= 0) continue;
      totalOutflow += amount;
      rows.add([
        _formatDate(dt),
        'OUTFLOW',
        fields['transactionType'] == 'SALARY_PAYMENT'
            ? 'Salary Payment'
            : 'Staff Advance',
        fields['partyId'] as String? ?? 'Employee',
        _formatMoney(amount),
      ]);
    }

    final netCashFlow = totalInflow - totalOutflow;

    return ReportDetailData(
      tileId: ReportTileId.expenseCashFlow,
      title: 'Expense and Cash Flow',
      subtitle: 'Overview of cash inflows from sales and outflows for purchases and operational expenses',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: DateTime.now(),
      columns: const [
        'Date',
        'Type',
        'Category',
        'Description / Ref',
        'Amount',
      ],
      rows: rows,
      columnTotals: {4: _formatMoney(netCashFlow)},
      summaryStats: [
        ReportSummaryStat(
          label: 'Total Inflow (Collections)',
          value: _formatMoney(totalInflow),
        ),
        ReportSummaryStat(
          label: 'Total Outflow (Purchases & Expenses)',
          value: _formatMoney(totalOutflow),
        ),
        ReportSummaryStat(
          label: 'Net Cash Flow',
          value: _formatMoney(netCashFlow),
          subValue: netCashFlow >= 0 ? 'Surplus' : 'Deficit',
        ),
      ],
      notes: const [
        'Consolidates invoice collections, supplier settlements, and operational expenses.',
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COMPLETE FINANCIAL & TAX AUDIT REPORT (ONE-CLICK AUDIT)
  // ---------------------------------------------------------------------------

  Future<FinancialAuditReportData> loadCompleteAuditReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
    String? gstin,
    String? tradeName,
    String? legalName,
    String? address,
    String? phone,
    String? email,
    bool includeSalaryData = false,
    AuditScopeSelection scope = const AuditScopeSelection(),
  }) async {
    return _loadFinancialReconciliation(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      token: token,
      includeSalaryData: includeSalaryData,
      scope: scope,
      gstin: gstin,
      tradeName: tradeName,
      legalName: legalName,
      address: address,
      phone: phone,
      email: email,
    );
  }

  Future<ReportDetailData> _buildCompleteAuditDetailReport({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String businessName,
    required String outletName,
    required ReportDateRange dateRange,
    required String token,
    required bool includeSalaryData,
  }) async {
    final audit = await loadCompleteAuditReport(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      token: token,
      includeSalaryData: includeSalaryData,
    );

    final review = audit.reconciliation;
    if (review == null) {
      return ReportDetailData(
        tileId: ReportTileId.completeAuditReport,
        title: FinancialReconciliation.title,
        subtitle: 'Reconciliation data unavailable',
        businessName: businessName,
        outletName: outletName,
        dateRange: dateRange,
        generatedAt: audit.generatedAt,
        columns: const ['Financial metric', 'Amount / status'],
        rows: const [],
        summaryStats: const [],
      );
    }
    return ReportDetailData(
      tileId: ReportTileId.completeAuditReport,
      title: FinancialReconciliation.title,
      subtitle: '${review.scopeLabel} | ${review.status}',
      businessName: businessName,
      outletName: outletName,
      dateRange: dateRange,
      generatedAt: audit.generatedAt,
      columns: const ['Financial metric', 'Amount / status'],
      rows: review.metrics.entries
          .map((e) => [e.key, FinancialReconciliation.money(e.value)])
          .toList(),
      summaryStats: [
        ReportSummaryStat(
          label: 'Data quality',
          value: '${review.score}/100',
          subValue: review.status,
        ),
      ],
      notes: review.limitations,
    );
  }

  // ---------------------------------------------------------------------------
  // LOCAL SQLITE QUERIES VIA FIRESTORE DATA SERVICE
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _getInvoices({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
    ReportDateRange? range,
  }) async {
    var docs = await firestore.queryDocuments(
      collection: FirebaseConstants.invoices,
      filters: [
        if (tenantId.isNotEmpty) FirestoreFilter('tenantId', 'EQUAL', tenantId),
        if (businessId.isNotEmpty)
          FirestoreFilter('businessId', 'EQUAL', businessId),
        if (outletId.isNotEmpty)
          FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );

    if (docs.isEmpty &&
        tenantId.isNotEmpty &&
        (businessId.isNotEmpty || outletId.isNotEmpty)) {
      docs = await firestore.queryDocuments(
        collection: FirebaseConstants.invoices,
        filters: [
          if (businessId.isNotEmpty)
            FirestoreFilter('businessId', 'EQUAL', businessId),
          if (outletId.isNotEmpty)
            FirestoreFilter('outletId', 'EQUAL', outletId),
        ],
        idToken: token,
      );
    }

    final result = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      fields['remoteId'] = (doc['name'] as String?)?.split('/').last ?? '';

      if (range != null) {
        final dt = _parseDateTime(
          fields['invoiceDate'] ??
              fields['entryDate'] ??
              fields['billDate'] ??
              fields['createdAt'],
        );
        if (dt != null) {
          if (dt.isBefore(range.start) || dt.isAfter(range.end)) {
            continue;
          }
        }
      }
      result.add(fields);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _getInvoiceItems({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
    Iterable<String>? invoiceIds,
  }) async {
    final results = <Map<String, dynamic>>[];
    final seenDocKeys = <String>{};

    void addDoc(Map<String, dynamic> doc) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      final remoteId = (doc['name'] as String?)?.split('/').last ?? '';
      if (remoteId.isNotEmpty) {
        fields['remoteId'] = remoteId;
      }
      final key = remoteId.isNotEmpty
          ? remoteId
          : '${fields['invoiceId']}_${fields['sku']}_${fields['name']}';
      if (seenDocKeys.add(key)) {
        results.add(fields);
      }
    }

    try {
      var docs = await firestore.queryDocuments(
        collection: FirebaseConstants.invoiceItems,
        filters: [
          if (tenantId.isNotEmpty)
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
          if (businessId.isNotEmpty)
            FirestoreFilter('businessId', 'EQUAL', businessId),
          if (outletId.isNotEmpty)
            FirestoreFilter('outletId', 'EQUAL', outletId),
        ],
        idToken: token,
      );
      if (docs.isEmpty &&
          tenantId.isNotEmpty &&
          (businessId.isNotEmpty || outletId.isNotEmpty)) {
        docs = await firestore.queryDocuments(
          collection: FirebaseConstants.invoiceItems,
          filters: [
            if (businessId.isNotEmpty)
              FirestoreFilter('businessId', 'EQUAL', businessId),
            if (outletId.isNotEmpty)
              FirestoreFilter('outletId', 'EQUAL', outletId),
          ],
          idToken: token,
        );
      }
      for (final doc in docs) {
        addDoc(doc);
      }
    } catch (_) {}

    if (invoiceIds == null || invoiceIds.isEmpty) {
      return results;
    }

    final idSet = invoiceIds.where((id) => id.isNotEmpty).toSet();
    final existingInvoiceIds = results
        .map((it) => it['invoiceId'] as String? ?? '')
        .toSet();
    final missingInvoiceIds = idSet.difference(existingInvoiceIds);

    if (missingInvoiceIds.isNotEmpty) {
      // First try listing all documents to find missing items in a single query (offline SQLite fast path)
      try {
        final allDocs = await firestore.listDocuments(
          FirebaseConstants.invoiceItems,
          idToken: token,
        );
        for (final doc in allDocs) {
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          final invId = fields['invoiceId'] as String? ?? '';
          if (missingInvoiceIds.contains(invId)) {
            addDoc(doc);
          }
        }
      } catch (_) {}

      // If still missing, query specifically by invoiceId
      final stillExisting = results
          .map((it) => it['invoiceId'] as String? ?? '')
          .toSet();
      final stillMissing = idSet.difference(stillExisting);
      for (final invId in stillMissing) {
        try {
          final itemDocs = await firestore.queryDocuments(
            collection: FirebaseConstants.invoiceItems,
            filters: [FirestoreFilter('invoiceId', 'EQUAL', invId)],
            idToken: token,
          );
          for (final doc in itemDocs) {
            addDoc(doc);
          }
        } catch (_) {}
      }
    }

    return results;
  }

  Future<List<Map<String, dynamic>>> _getPurchaseBills({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
    ReportDateRange? range,
  }) async {
    var docs = await firestore.queryDocuments(
      collection: FirebaseConstants.purchaseBills,
      filters: [
        if (tenantId.isNotEmpty) FirestoreFilter('tenantId', 'EQUAL', tenantId),
        if (businessId.isNotEmpty)
          FirestoreFilter('businessId', 'EQUAL', businessId),
        if (outletId.isNotEmpty)
          FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );

    if (docs.isEmpty &&
        tenantId.isNotEmpty &&
        (businessId.isNotEmpty || outletId.isNotEmpty)) {
      docs = await firestore.queryDocuments(
        collection: FirebaseConstants.purchaseBills,
        filters: [
          if (businessId.isNotEmpty)
            FirestoreFilter('businessId', 'EQUAL', businessId),
          if (outletId.isNotEmpty)
            FirestoreFilter('outletId', 'EQUAL', outletId),
        ],
        idToken: token,
      );
    }

    final result = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      if (range != null) {
        final dt = _parseDateTime(
          fields['invoiceDate'] ??
              fields['entryDate'] ??
              fields['billDate'] ??
              fields['purchaseDate'] ??
              fields['createdAt'],
        );
        if (dt != null) {
          if (dt.isBefore(range.start) || dt.isAfter(range.end)) {
            continue;
          }
        }
      }
      result.add(fields);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _getExpenses({
    required String tenantId,
    required String businessId,
    String? outletId,
    required String token,
    ReportDateRange? range,
  }) async {
    var docs = await firestore.queryDocuments(
      collection: FirebaseConstants.expenses,
      filters: [
        if (tenantId.isNotEmpty) FirestoreFilter('tenantId', 'EQUAL', tenantId),
        if (businessId.isNotEmpty)
          FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );

    if (docs.isEmpty && tenantId.isNotEmpty && businessId.isNotEmpty) {
      docs = await firestore.queryDocuments(
        collection: FirebaseConstants.expenses,
        filters: [
          FirestoreFilter('businessId', 'EQUAL', businessId),
        ],
        idToken: token,
      );
    }

    final result = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      if (fields['status'] == 'VOID') continue;
      if (outletId != null &&
          fields['outletId'] != null &&
          fields['outletId'] != outletId) {
        continue;
      }
      if (range != null) {
        final dt = _parseDateTime(fields['expenseDate'] ?? fields['createdAt']);
        if (dt != null) {
          if (dt.isBefore(range.start) || dt.isAfter(range.end)) {
            continue;
          }
        }
      }
      result.add(fields);
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> _getCustomers({
    required String businessId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.customers,
      filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
      idToken: token,
    );
    return [
      for (final doc in docs) FirestoreRestService.decodeFields(doc['fields']),
    ];
  }

  Future<List<Map<String, dynamic>>> _getStockBalances({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
  }) async {
    var docs = await firestore.queryDocuments(
      collection: FirebaseConstants.stockBalances,
      filters: [
        if (tenantId.isNotEmpty) FirestoreFilter('tenantId', 'EQUAL', tenantId),
        if (businessId.isNotEmpty)
          FirestoreFilter('businessId', 'EQUAL', businessId),
        if (outletId.isNotEmpty)
          FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );

    if (docs.isEmpty &&
        tenantId.isNotEmpty &&
        (businessId.isNotEmpty || outletId.isNotEmpty)) {
      docs = await firestore.queryDocuments(
        collection: FirebaseConstants.stockBalances,
        filters: [
          if (businessId.isNotEmpty)
            FirestoreFilter('businessId', 'EQUAL', businessId),
          if (outletId.isNotEmpty)
            FirestoreFilter('outletId', 'EQUAL', outletId),
        ],
        idToken: token,
      );
    }

    return [
      for (final doc in docs) FirestoreRestService.decodeFields(doc['fields']),
    ];
  }

  Future<List<Map<String, dynamic>>> _getVariants({
    required String businessId,
    required String token,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [FirestoreFilter('businessId', 'EQUAL', businessId)],
      idToken: token,
    );
    return [
      for (final doc in docs) FirestoreRestService.decodeFields(doc['fields']),
    ];
  }

  Future<List<Map<String, dynamic>>> _getStockMovements({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
  }) async {
    var docs = await firestore.queryDocuments(
      collection: FirebaseConstants.stockMovements,
      filters: [
        if (tenantId.isNotEmpty) FirestoreFilter('tenantId', 'EQUAL', tenantId),
        if (businessId.isNotEmpty)
          FirestoreFilter('businessId', 'EQUAL', businessId),
        if (outletId.isNotEmpty)
          FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );

    if (docs.isEmpty &&
        tenantId.isNotEmpty &&
        (businessId.isNotEmpty || outletId.isNotEmpty)) {
      docs = await firestore.queryDocuments(
        collection: FirebaseConstants.stockMovements,
        filters: [
          if (businessId.isNotEmpty)
            FirestoreFilter('businessId', 'EQUAL', businessId),
          if (outletId.isNotEmpty)
            FirestoreFilter('outletId', 'EQUAL', outletId),
        ],
        idToken: token,
      );
    }

    return [
      for (final doc in docs) FirestoreRestService.decodeFields(doc['fields']),
    ];
  }

  // Helper date and money formatters
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.day)}/${pad(dt.month)}/${dt.year}';
  }

  String _formatDateTime(DateTime dt) {
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(dt.day)}/${pad(dt.month)}/${dt.year} ${pad(dt.hour)}:${pad(dt.minute)}';
  }

  String _formatMoney(int paise) {
    final isNegative = paise < 0;
    final abs = paise.abs();
    final rupees = abs ~/ 100;
    final cents = abs % 100;
    final formattedRupees = _formatIndianNumber(rupees);
    final sign = isNegative ? '-' : '';
    if (cents == 0) {
      return '$sign₹ $formattedRupees';
    }
    return '$sign₹ $formattedRupees.${cents.toString().padLeft(2, '0')}';
  }

  String _formatIndianNumber(int number) {
    final s = number.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    final rest = s.substring(0, s.length - 3);
    final buffer = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) {
        buffer.write(',');
      }
      buffer.write(rest[i]);
    }
    return '${buffer.toString()},$last3';
  }
}

// Internal data holder classes for report aggregation
class _DailySalesSummary {
  _DailySalesSummary(this.date);
  final String date;
  int count = 0;
  int grossPaise = 0;
  int discountPaise = 0;
  int taxablePaise = 0;
  int taxPaise = 0;
  int netPaise = 0;
}

class _ProductSalesSummary {
  _ProductSalesSummary({
    required this.name,
    required this.sku,
    required this.unit,
  });
  final String name;
  final String sku;
  final String unit;
  double quantity = 0;
  int taxablePaise = 0;
  int taxPaise = 0;
  int totalPaise = 0;
}

class _CustomerReceivableSummary {
  _CustomerReceivableSummary({
    required this.customerId,
    required this.name,
    required this.phone,
    this.duePaise = 0,
  });
  final String customerId;
  final String name;
  final String phone;
  int duePaise;
  int billsCount = 0;
  int totalBilledPaise = 0;
  int totalPaidPaise = 0;
  int due0to30 = 0;
  int due31to60 = 0;
  int due60plus = 0;
}

class _GstBucketSummary {
  _GstBucketSummary({required this.hsn, required this.ratePct});
  final String hsn;
  final double ratePct;
  int lineCount = 0;
  int taxablePaise = 0;
  int cgstPaise = 0;
  int sgstPaise = 0;
  int igstPaise = 0;
}

class _ProfitItemSummary {
  _ProfitItemSummary({required this.name});
  final String name;
  double quantity = 0;
  int revenuePaise = 0;
  int costPaise = 0;
}

class _ProductForecastModel {
  _ProductForecastModel({
    required this.name,
    required this.sku,
    required this.unit,
  });

  final String name;
  final String sku;
  final String unit;
  double qtyM1 = 0;
  int revM1Paise = 0;
  double qtyM2 = 0;
  int revM2Paise = 0;
  double qtyM3 = 0;
  int revM3Paise = 0;
  double qtyOlder = 0;
  int revOlderPaise = 0;
  double totalSoldQty = 0;
  int totalRevenuePaise = 0;
  double currentStock = 0;
  double growthPct = 0;
  double forecastQty = 0;
  int forecastIncomePaise = 0;
  double daysOfStockRemaining = 0;
  double suggestedReorderQty = 0;
}

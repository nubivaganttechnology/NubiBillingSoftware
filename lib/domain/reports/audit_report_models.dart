import 'report_models.dart';

enum AuditScopeMode {
  selectedOutlet('SELECTED_OUTLET'),
  allOutletsInBusiness('ALL_OUTLETS_IN_BUSINESS'),
  selectedOutletsInBusiness('SELECTED_OUTLETS_IN_BUSINESS'),
  combinedAuthorizedBusinesses('COMBINED_AUTHORIZED_BUSINESSES');

  const AuditScopeMode(this.label);
  final String label;
}

class AuditScopeSelection {
  const AuditScopeSelection({
    this.mode = AuditScopeMode.selectedOutlet,
    this.outletsByBusiness = const {},
  });
  final AuditScopeMode mode;
  // Empty outlet list explicitly selects all authorized outlets in that business.
  final Map<String, List<String>> outletsByBusiness;
}

class AuditScopeOption {
  const AuditScopeOption(this.id, this.name, this.businessId, this.isActive);
  final String id, name, businessId;
  final bool isActive;
}

class AuditScopeOptions {
  const AuditScopeOptions(this.businesses, this.outlets);
  final List<AuditScopeOption> businesses, outlets;
}

class AuditSchedule {
  const AuditSchedule(this.title, this.columns, this.rows, {this.note = ''});
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final String note;
}

class AuditValidation {
  const AuditValidation(this.id, this.status, this.weight, this.details);
  final String id;
  final String status;
  final int weight;
  final String details;
}

class FinancialReconciliation {
  const FinancialReconciliation({
    required this.scopeLabel,
    required this.generatedBy,
    required this.metrics,
    required this.schedules,
    required this.checks,
    required this.limitations,
  });
  static const title = 'NubiBill Automated Financial Reconciliation Report';
  final String scopeLabel;
  final String generatedBy;
  // Null is unavailable. Never replace a missing accounting amount with zero.
  final Map<String, int?> metrics;
  final List<AuditSchedule> schedules;
  final List<AuditValidation> checks;
  final List<String> limitations;
  int get score =>
      checks.fold(0, (sum, c) => sum + (c.status == 'PASS' ? c.weight : 0));
  String get status => checks.any((c) => c.status == 'FAIL')
      ? 'NOT RECONCILED'
      : checks.any((c) => c.status == 'NOT_VERIFIED')
      ? 'INSUFFICIENT DATA'
      : 'RECONCILED';
  static String money(int? paise) => paise == null
      ? 'INSUFFICIENT DATA'
      : 'INR ${paise < 0 ? '-' : ''}${paise.abs() ~/ 100}.${(paise.abs() % 100).toString().padLeft(2, '0')}';
}

enum AuditRiskLevel { passed, info, warning, critical }

class AuditRiskCheck {
  const AuditRiskCheck({
    required this.id,
    required this.title,
    required this.description,
    required this.level,
    required this.statusLabel,
    this.flaggedCount = 0,
    this.flaggedDetails = const [],
    required this.recommendation,
  });

  final String id;
  final String title;
  final String description;
  final AuditRiskLevel level;
  final String statusLabel;
  final int flaggedCount;
  final List<String> flaggedDetails;
  final String recommendation;
}

class AuditHsnItem {
  const AuditHsnItem({
    required this.hsn,
    required this.description,
    required this.uqc,
    required this.quantity,
    required this.taxablePaise,
    required this.ratePct,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalTaxPaise,
    required this.totalAmountPaise,
  });

  final String hsn;
  final String description;
  final String uqc;
  final double quantity;
  final int taxablePaise;
  final double ratePct;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalTaxPaise;
  final int totalAmountPaise;
}

class AuditGstRateBucket {
  const AuditGstRateBucket({
    required this.ratePct,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.igstPaise,
    required this.totalTaxPaise,
    required this.invoiceCount,
  });

  final double ratePct;
  final int taxablePaise;
  final int cgstPaise;
  final int sgstPaise;
  final int igstPaise;
  final int totalTaxPaise;
  final int invoiceCount;
}

class AuditMonthlyPerformance {
  const AuditMonthlyPerformance({
    required this.monthKey,
    required this.monthLabel,
    required this.salesPaise,
    required this.purchasesPaise,
    required this.expensesPaise,
    required this.grossProfitPaise,
    required this.netProfitPaise,
    required this.taxLiabilityPaise,
  });

  final String monthKey;
  final String monthLabel;
  final int salesPaise;
  final int purchasesPaise;
  final int expensesPaise;
  final int grossProfitPaise;
  final int netProfitPaise;
  final int taxLiabilityPaise;
}

class AuditDebtorAgingItem {
  const AuditDebtorAgingItem({
    required this.customerName,
    required this.phone,
    required this.gstin,
    required this.bracket0To30Paise,
    required this.bracket31To60Paise,
    required this.bracket61To90Paise,
    required this.bracketAbove90Paise,
    required this.bracketAbove180Paise,
    required this.totalDuePaise,
  });

  final String customerName;
  final String phone;
  final String gstin;
  final int bracket0To30Paise;
  final int bracket31To60Paise;
  final int bracket61To90Paise;
  final int bracketAbove90Paise;
  final int bracketAbove180Paise;
  final int totalDuePaise;
}

class AuditCreditorAgingItem {
  const AuditCreditorAgingItem({
    required this.supplierName,
    required this.gstin,
    required this.phone,
    required this.pendingAmountPaise,
    required this.oldestBillDays,
    required this.isMsmeExceeded,
  });

  final String supplierName;
  final String gstin;
  final String phone;
  final int pendingAmountPaise;
  final int oldestBillDays;
  final bool isMsmeExceeded;
}

class AuditStockItem {
  const AuditStockItem({
    required this.sku,
    required this.name,
    required this.category,
    required this.openingQty,
    required this.inwardQty,
    required this.outwardQty,
    required this.damageQty,
    required this.closingQty,
    required this.unitCostPaise,
    required this.closingValuationPaise,
    required this.isLowStock,
    required this.isNearExpiry,
  });

  final String sku;
  final String name;
  final String category;
  final double openingQty;
  final double inwardQty;
  final double outwardQty;
  final double damageQty;
  final double closingQty;
  final int unitCostPaise;
  final int closingValuationPaise;
  final bool isLowStock;
  final bool isNearExpiry;
}

class FinancialAuditReportData {
  const FinancialAuditReportData({
    required this.businessId,
    required this.outletId,
    required this.businessName,
    required this.outletName,
    required this.tradeName,
    required this.legalName,
    required this.gstin,
    required this.pan,
    required this.stateCode,
    required this.address,
    required this.phone,
    required this.email,
    required this.dateRange,
    required this.financialYearLabel,
    required this.assessmentYearLabel,
    required this.generatedAt,
    required this.auditHealthScore,
    required this.auditReadiness,
    required this.auditorExecutiveSummary,
    required this.hasHighRiskFlags,
    required this.grossSalesPaise,
    required this.salesReturnsDiscountsPaise,
    required this.netTurnoverPaise,
    required this.openingStockPaise,
    required this.purchasesPaise,
    required this.directExpensesPaise,
    required this.closingStockPaise,
    required this.cogsPaise,
    required this.grossProfitPaise,
    required this.grossProfitMarginPct,
    required this.indirectExpensesPaise,
    required this.netProfitBeforeTaxPaise,
    required this.netProfitMarginPct,
    required this.presumptiveSection44AdProfitPaise,
    required this.isEligibleForSection44Ad,
    required this.ownersCapitalPaise,
    required this.retainedEarningsPaise,
    required this.sundryCreditorsPaise,
    required this.statutoryDuesPaise,
    required this.totalLiabilitiesPaise,
    required this.fixedAssetsPaise,
    required this.closingInventoryPaise,
    required this.sundryDebtorsPaise,
    required this.cashInHandPaise,
    required this.bankBalancesPaise,
    required this.totalAssetsPaise,
    required this.workingCapitalPaise,
    required this.currentRatio,
    required this.totalOutputTaxPaise,
    required this.totalInputTaxCreditPaise,
    required this.netGstPayablePaise,
    required this.b2bSalesPaise,
    required this.b2cSalesPaise,
    required this.digitalCollectionPaise,
    required this.cashCollectionPaise,
    required this.creditCollectionDuePaise,
    required this.gstRateBuckets,
    required this.hsnItems,
    required this.monthlyTrends,
    required this.stockAuditItems,
    required this.riskChecks,
    required this.debtorAgingList,
    required this.creditorAgingList,
    required this.expenseBreakdown,
    this.reconciliation,
  });

  // Business Metadata
  final String businessId;
  final String outletId;
  final String businessName;
  final String outletName;
  final String tradeName;
  final String legalName;
  final String gstin;
  final String pan;
  final String stateCode;
  final String address;
  final String phone;
  final String email;

  // Period Metadata
  final ReportDateRange dateRange;
  final String financialYearLabel;
  final String assessmentYearLabel;
  final DateTime generatedAt;

  // Audit Score & Summary
  final int auditHealthScore; // 0 - 100
  final String auditReadiness;
  final String auditorExecutiveSummary;
  final bool hasHighRiskFlags;

  // Trading & P&L Statement
  final int? grossSalesPaise;
  final int? salesReturnsDiscountsPaise;
  final int? netTurnoverPaise;
  final int? openingStockPaise;
  final int? purchasesPaise;
  final int? directExpensesPaise;
  final int? closingStockPaise;
  final int? cogsPaise;
  final int? grossProfitPaise;
  final double? grossProfitMarginPct;
  final int? indirectExpensesPaise;
  final int? netProfitBeforeTaxPaise;
  final double? netProfitMarginPct;
  final int? presumptiveSection44AdProfitPaise;
  final bool? isEligibleForSection44Ad;

  // Balance Sheet & Working Capital
  final int? ownersCapitalPaise;
  final int? retainedEarningsPaise;
  final int? sundryCreditorsPaise;
  final int? statutoryDuesPaise;
  final int? totalLiabilitiesPaise;
  final int? fixedAssetsPaise;
  final int? closingInventoryPaise;
  final int? sundryDebtorsPaise;
  final int? cashInHandPaise;
  final int? bankBalancesPaise;
  final int? totalAssetsPaise;
  final int? workingCapitalPaise;
  final double? currentRatio;

  // GST & Tax Breakdown
  final int? totalOutputTaxPaise;
  final int? totalInputTaxCreditPaise;
  final int? netGstPayablePaise;
  final int? b2bSalesPaise;
  final int? b2cSalesPaise;
  final int? digitalCollectionPaise;
  final int? cashCollectionPaise;
  final int? creditCollectionDuePaise;
  final List<AuditGstRateBucket> gstRateBuckets;
  final List<AuditHsnItem> hsnItems;

  // Detailed Schedules
  final List<AuditMonthlyPerformance> monthlyTrends;
  final List<AuditStockItem> stockAuditItems;
  final List<AuditRiskCheck> riskChecks;
  final List<AuditDebtorAgingItem> debtorAgingList;
  final List<AuditCreditorAgingItem> creditorAgingList;
  final Map<String, int> expenseBreakdown;
  final FinancialReconciliation? reconciliation;
}

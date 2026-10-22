class BusinessSettingsModel {
  const BusinessSettingsModel({
    required this.businessId,
    required this.tenantId,
    this.invoicePrefix = 'INV-',
    this.invoiceTerms = '1. Goods once sold will not be taken back without original bill.\n2. Warranty claims subject to manufacturer terms.',
    this.printFormat = 'A4_STANDARD', // A4_STANDARD, A5_COMPACT, THERMAL_80MM, THERMAL_58MM, CUSTOM
    this.customPrintWidthMm = 80.0,
    this.alwaysAskPrintFormat = true,
    this.showUpiQr = true,
    this.showBankDetails = true,
    this.bankName,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankAccountName,
    this.upiId,
    this.gstMode = 'REGULAR', // REGULAR, COMPOSITION
    this.showHsnSummary = true,
    this.defaultGstRate = 18.0,
    this.allowNegativeStock = false,
    this.lowStockThreshold = 5,
    this.autoGenerateBarcode = true,
    this.roundOffPaise = true,
    this.emailReceipts = false,
    this.updatedAt,
  });

  final String businessId;
  final String tenantId;
  final String invoicePrefix;
  final String invoiceTerms;
  final String printFormat;
  final double customPrintWidthMm;
  final bool alwaysAskPrintFormat;
  final bool showUpiQr;
  final bool showBankDetails;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? bankAccountName;
  final String? upiId;
  final String gstMode;
  final bool showHsnSummary;
  final double defaultGstRate;
  final bool allowNegativeStock;
  final int lowStockThreshold;
  final bool autoGenerateBarcode;
  final bool roundOffPaise;
  final bool emailReceipts;
  final DateTime? updatedAt;

  factory BusinessSettingsModel.defaultSettings({
    required String businessId,
    required String tenantId,
  }) =>
      BusinessSettingsModel(
        businessId: businessId,
        tenantId: tenantId,
      );

  factory BusinessSettingsModel.fromData(
    String id,
    Map<String, dynamic> data, {
    String? tenantId,
  }) =>
      BusinessSettingsModel(
        businessId: data['businessId'] as String? ?? id,
        tenantId: data['tenantId'] as String? ?? tenantId ?? '',
        invoicePrefix: data['invoicePrefix'] as String? ?? 'INV-',
        invoiceTerms: data['invoiceTerms'] as String? ??
            '1. Goods once sold will not be taken back without original bill.\n2. Warranty claims subject to manufacturer terms.',
        printFormat: data['printFormat'] as String? ?? 'A4_STANDARD',
        customPrintWidthMm:
            (data['customPrintWidthMm'] as num?)?.toDouble() ?? 80.0,
        alwaysAskPrintFormat:
            data['alwaysAskPrintFormat'] as bool? ?? true,
        showUpiQr: data['showUpiQr'] as bool? ?? true,
        showBankDetails: data['showBankDetails'] as bool? ?? true,
        bankName: data['bankName'] as String?,
        bankAccountNumber: data['bankAccountNumber'] as String?,
        bankIfsc: data['bankIfsc'] as String?,
        bankAccountName: data['bankAccountName'] as String?,
        upiId: data['upiId'] as String?,
        gstMode: data['gstMode'] as String? ?? 'REGULAR',
        showHsnSummary: data['showHsnSummary'] as bool? ?? true,
        defaultGstRate: (data['defaultGstRate'] as num?)?.toDouble() ?? 18.0,
        allowNegativeStock: data['allowNegativeStock'] as bool? ?? false,
        lowStockThreshold: (data['lowStockThreshold'] as num?)?.toInt() ?? 5,
        autoGenerateBarcode: data['autoGenerateBarcode'] as bool? ?? true,
        roundOffPaise: data['roundOffPaise'] as bool? ?? true,
        emailReceipts: data['emailReceipts'] as bool? ?? false,
        updatedAt: data['updatedAt'] is DateTime
            ? data['updatedAt'] as DateTime
            : DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
      );

  Map<String, dynamic> toMap() => {
    'businessId': businessId,
    'tenantId': tenantId,
    'invoicePrefix': invoicePrefix,
    'invoiceTerms': invoiceTerms,
    'printFormat': printFormat,
    'customPrintWidthMm': customPrintWidthMm,
    'alwaysAskPrintFormat': alwaysAskPrintFormat,
    'showUpiQr': showUpiQr,
    'showBankDetails': showBankDetails,
    if (bankName != null && bankName!.isNotEmpty) 'bankName': bankName,
    if (bankAccountNumber != null && bankAccountNumber!.isNotEmpty)
      'bankAccountNumber': bankAccountNumber,
    if (bankIfsc != null && bankIfsc!.isNotEmpty) 'bankIfsc': bankIfsc,
    if (bankAccountName != null && bankAccountName!.isNotEmpty)
      'bankAccountName': bankAccountName,
    if (upiId != null && upiId!.isNotEmpty) 'upiId': upiId,
    'gstMode': gstMode,
    'showHsnSummary': showHsnSummary,
    'defaultGstRate': defaultGstRate,
    'allowNegativeStock': allowNegativeStock,
    'lowStockThreshold': lowStockThreshold,
    'autoGenerateBarcode': autoGenerateBarcode,
    'roundOffPaise': roundOffPaise,
    'emailReceipts': emailReceipts,
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  BusinessSettingsModel copyWith({
    String? invoicePrefix,
    String? invoiceTerms,
    String? printFormat,
    double? customPrintWidthMm,
    bool? alwaysAskPrintFormat,
    bool? showUpiQr,
    bool? showBankDetails,
    String? bankName,
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankAccountName,
    String? upiId,
    String? gstMode,
    bool? showHsnSummary,
    double? defaultGstRate,
    bool? allowNegativeStock,
    int? lowStockThreshold,
    bool? autoGenerateBarcode,
    bool? roundOffPaise,
    bool? emailReceipts,
  }) =>
      BusinessSettingsModel(
        businessId: businessId,
        tenantId: tenantId,
        invoicePrefix: invoicePrefix ?? this.invoicePrefix,
        invoiceTerms: invoiceTerms ?? this.invoiceTerms,
        printFormat: printFormat ?? this.printFormat,
        customPrintWidthMm: customPrintWidthMm ?? this.customPrintWidthMm,
        alwaysAskPrintFormat: alwaysAskPrintFormat ?? this.alwaysAskPrintFormat,
        showUpiQr: showUpiQr ?? this.showUpiQr,
        showBankDetails: showBankDetails ?? this.showBankDetails,
        bankName: bankName ?? this.bankName,
        bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
        bankIfsc: bankIfsc ?? this.bankIfsc,
        bankAccountName: bankAccountName ?? this.bankAccountName,
        upiId: upiId ?? this.upiId,
        gstMode: gstMode ?? this.gstMode,
        showHsnSummary: showHsnSummary ?? this.showHsnSummary,
        defaultGstRate: defaultGstRate ?? this.defaultGstRate,
        allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        autoGenerateBarcode: autoGenerateBarcode ?? this.autoGenerateBarcode,
        roundOffPaise: roundOffPaise ?? this.roundOffPaise,
        emailReceipts: emailReceipts ?? this.emailReceipts,
        updatedAt: DateTime.now(),
      );
}

class PurchaseBillItemModel {
  const PurchaseBillItemModel({
    required this.goodsReceiptItemId,
    required this.variantId,
    required this.productName,
    required this.unitId,
    required this.conversionFactor,
    required this.quantity,
    required this.rate,
    required this.gstRateBps,
    required this.taxableAmount,
    required this.taxAmount,
    this.commercialUnitId,
    this.hsnCode,
    this.mrp,
    this.sellingPrice,
    this.productId,
    this.variantName,
    this.barcodeSnapshot,
    this.internalBatchNo,
    this.supplierLotNo,
    this.manufacturingDate,
    this.expiryDate,
    this.storageType,
    this.storageLocationId,
    this.rackId,
  });

  final String goodsReceiptItemId, variantId, productName, unitId;
  final int conversionFactor, quantity, rate, gstRateBps;
  final int taxableAmount, taxAmount;
  final String? hsnCode, commercialUnitId;
  int get baseQuantity => (quantity * conversionFactor + 500) ~/ 1000;
  final int? mrp, sellingPrice;
  final String? productId,
      variantName,
      barcodeSnapshot,
      internalBatchNo,
      supplierLotNo;
  final String? storageType, storageLocationId, rackId;
  final DateTime? manufacturingDate, expiryDate;

  Map<String, dynamic> toData() => {
    'goodsReceiptItemId': goodsReceiptItemId,
    'variantId': variantId,
    'productName': productName,
    'unitId': unitId,
    if (commercialUnitId != null) 'commercialUnitId': commercialUnitId,
    if (commercialUnitId != null) 'commercialQuantity': quantity,
    if (commercialUnitId != null) 'baseUnitId': unitId,
    if (commercialUnitId != null) 'baseQuantity': baseQuantity,
    'conversionFactor': conversionFactor,
    'quantity': quantity,
    'rate': rate,
    'gstRateBps': gstRateBps,
    'taxableAmount': taxableAmount,
    'taxAmount': taxAmount,
    'hsnCode': hsnCode,
    'mrp': mrp,
    'sellingPrice': sellingPrice,
    'productId': productId,
    'variantName': variantName,
    'barcodeSnapshot': barcodeSnapshot,
    'barcode': barcodeSnapshot,
    'internalBatchNo': internalBatchNo,
    'supplierLotNo': supplierLotNo,
    'manufacturingDate': manufacturingDate,
    'expiryDate': expiryDate,
    'storageType': storageType,
    'storageLocationId': storageLocationId,
    'rackId': rackId,
  };

  factory PurchaseBillItemModel.fromData(Map<String, dynamic> data) =>
      PurchaseBillItemModel(
        goodsReceiptItemId: data['goodsReceiptItemId'] as String? ?? '',
        variantId: data['variantId'] as String? ?? '',
        productName: data['productName'] as String? ?? '',
        unitId: data['unitId'] as String? ?? 'UNIT',
        commercialUnitId: data['commercialUnitId'] as String?,
        conversionFactor: (data['conversionFactor'] as num?)?.toInt() ?? 1000,
        quantity: (data['quantity'] as num?)?.toInt() ?? 0,
        rate: (data['rate'] as num?)?.toInt() ?? 0,
        gstRateBps: (data['gstRateBps'] as num?)?.toInt() ?? 0,
        taxableAmount: (data['taxableAmount'] as num?)?.toInt() ?? 0,
        taxAmount: (data['taxAmount'] as num?)?.toInt() ?? 0,
        hsnCode: data['hsnCode'] as String?,
        mrp: (data['mrp'] as num?)?.toInt(),
        sellingPrice: (data['sellingPrice'] as num?)?.toInt(),
        productId: data['productId'] as String?,
        variantName: data['variantName'] as String?,
        barcodeSnapshot:
            data['barcodeSnapshot'] as String? ?? data['barcode'] as String?,
        internalBatchNo: data['internalBatchNo'] as String?,
        supplierLotNo: data['supplierLotNo'] as String?,
        manufacturingDate: _date(data['manufacturingDate']),
        expiryDate: _date(data['expiryDate']),
        storageType: data['storageType'] as String?,
        storageLocationId: data['storageLocationId'] as String?,
        rackId: data['rackId'] as String?,
      );

  static DateTime? _date(dynamic value) =>
      value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
}

class PurchaseBillModel {
  const PurchaseBillModel({
    required this.purchaseBillId,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.supplierId,
    required this.supplierBusinessId,
    required this.supplierInvoiceNumber,
    required this.status,
    required this.purchaseType,
    required this.taxType,
    required this.invoiceDate,
    required this.entryDate,
    required this.subtotal,
    required this.discountAmount,
    required this.taxableAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.chargesAmount,
    required this.roundOff,
    required this.grandTotal,
    required this.paidAmount,
    required this.outstandingAmount,
    required this.paymentStatus,
    required this.version,
    required this.items,
    this.supplierName,
    this.dueDate,
    this.createdAt,
    this.approvedAt,
    this.createdBy,
    this.purchaseNumber,
    this.purchaseDate,
  });

  final String purchaseBillId, tenantId, businessId, outletId;
  final String supplierId, supplierBusinessId, supplierInvoiceNumber;
  final String status, purchaseType, taxType, paymentStatus;
  final int subtotal, discountAmount, taxableAmount, cgstAmount, sgstAmount;
  final int igstAmount, chargesAmount, roundOff, grandTotal, paidAmount;
  final int outstandingAmount, version;
  final List<PurchaseBillItemModel> items;
  final String? supplierName, createdBy;
  final String? purchaseNumber;
  final DateTime invoiceDate, entryDate;
  final DateTime? purchaseDate;
  final DateTime? dueDate, createdAt, approvedAt;

  factory PurchaseBillModel.fromData(String id, Map<String, dynamic> data) {
    DateTime date(String key) => data[key] is DateTime
        ? data[key] as DateTime
        : DateTime.tryParse('${data[key] ?? ''}') ?? DateTime.now();
    final rawItems = data['items'] as List? ?? const [];
    return PurchaseBillModel(
      purchaseBillId: data['purchaseBillId'] as String? ?? id,
      purchaseNumber: data['purchaseNumber'] as String?,
      tenantId: data['tenantId'] as String? ?? '',
      businessId: data['businessId'] as String? ?? '',
      outletId: data['outletId'] as String? ?? '',
      supplierId: data['supplierId'] as String? ?? '',
      supplierBusinessId: data['supplierBusinessId'] as String? ?? '',
      supplierInvoiceNumber: data['supplierInvoiceNumber'] as String? ?? '',
      status: data['status'] as String? ?? 'DRAFT',
      purchaseType: data['purchaseType'] as String? ?? 'DIRECT',
      taxType: data['taxType'] as String? ?? 'INTRA_STATE',
      invoiceDate: date('invoiceDate'),
      entryDate: date('entryDate'),
      purchaseDate: data['purchaseDate'] == null ? null : date('purchaseDate'),
      dueDate: data['dueDate'] is DateTime ? data['dueDate'] as DateTime : null,
      subtotal: (data['subtotal'] as num?)?.toInt() ?? 0,
      discountAmount: (data['discountAmount'] as num?)?.toInt() ?? 0,
      taxableAmount: (data['taxableAmount'] as num?)?.toInt() ?? 0,
      cgstAmount: (data['cgstAmount'] as num?)?.toInt() ?? 0,
      sgstAmount: (data['sgstAmount'] as num?)?.toInt() ?? 0,
      igstAmount: (data['igstAmount'] as num?)?.toInt() ?? 0,
      chargesAmount: (data['chargesAmount'] as num?)?.toInt() ?? 0,
      roundOff: (data['roundOff'] as num?)?.toInt() ?? 0,
      grandTotal: (data['grandTotal'] as num?)?.toInt() ?? 0,
      paidAmount: (data['paidAmount'] as num?)?.toInt() ?? 0,
      outstandingAmount: (data['outstandingAmount'] as num?)?.toInt() ?? 0,
      paymentStatus: data['paymentStatus'] as String? ?? 'UNPAID',
      version: (data['version'] as num?)?.toInt() ?? 1,
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => PurchaseBillItemModel.fromData(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(),
      supplierName: data['supplierName'] as String?,
      createdBy: data['createdBy'] as String?,
      createdAt: data['createdAt'] is DateTime
          ? data['createdAt'] as DateTime
          : null,
      approvedAt: data['approvedAt'] is DateTime
          ? data['approvedAt'] as DateTime
          : null,
    );
  }
}

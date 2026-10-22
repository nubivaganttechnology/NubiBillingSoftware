class SalesBatchAllocation {
  const SalesBatchAllocation({
    required this.batchId,
    required this.baseQuantity,
  });

  final String batchId;
  final int baseQuantity;

  Map<String, dynamic> toData() => {
    'batchId': batchId,
    'baseQuantity': baseQuantity,
  };
}

class SalesInvoiceLine {
  const SalesInvoiceLine({
    required this.invoiceLineId,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.baseUnitId,
    required this.commercialUnitId,
    required this.conversionFactor,
    required this.baseQuantity,
    required this.unitPrice,
    required this.mrp,
    required this.gstPercent,
    required this.taxableAmount,
    required this.lineTotal,
    required this.batchAllocations,
  });

  final String invoiceLineId, productId, variantId, productName, variantName;
  final int quantity, conversionFactor, baseQuantity, unitPrice, mrp;
  final num gstPercent;
  final int taxableAmount, lineTotal;
  final String commercialUnitId;
  final String baseUnitId;
  final List<SalesBatchAllocation> batchAllocations;

  Map<String, dynamic> toData() => {
    'invoiceLineId': invoiceLineId,
    'productId': productId,
    'variantId': variantId,
    'productName': productName,
    'variantName': variantName,
    'quantity': quantity,
    'commercialUnitId': commercialUnitId,
    'baseUnitId': baseUnitId,
    'conversionFactor': conversionFactor,
    'baseQuantity': baseQuantity,
    'unitPrice': unitPrice,
    'mrp': mrp,
    'gstPercent': gstPercent,
    'taxableAmount': taxableAmount,
    'lineTotal': lineTotal,
    'batchAllocations': batchAllocations.map((item) => item.toData()).toList(),
  };
}

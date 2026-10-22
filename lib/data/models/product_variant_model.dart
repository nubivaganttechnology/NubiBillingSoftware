class ProductVariantModel {
  const ProductVariantModel({
    required this.variantId,
    required this.businessId,
    required this.name,
    required this.baseUnitId,
    required this.defaultGstRateBps,
    this.tenantId = '',
    this.gstOverride,
    this.attributeValues = const {},
    this.commercialUnitName,
    this.packUnitId,
    this.commercialUnitId,
    this.baseQuantityPerCommercialUnit = 1,
    this.trackStock = true,
    this.priceIncludesTax = false,
    this.reorderLevel = 0,
    this.productId,
    this.productName,
    this.sku,
    this.hsnCode,
    this.barcode,
    this.brand,
    this.category,
    this.status = 'ACTIVE',
    this.purchaseRate = 0,
    this.sellingPrice = 0,
    this.mrp = 0,
    this.variantCode,
    this.shadeId,
    this.shadeCode,
    this.packSizeId,
    this.packSize,
    this.finishId,
    this.colourFamilyId,
    this.baseTypeId,
  });

  final String tenantId;
  final bool? gstOverride;
  final Map<String, dynamic> attributeValues;
  final String? packUnitId, commercialUnitId, commercialUnitName;
  final num baseQuantityPerCommercialUnit;
  final bool trackStock;
  final bool priceIncludesTax;
  final int reorderLevel;
  num toBaseQuantity(num commercialQuantity) =>
      commercialQuantity * baseQuantityPerCommercialUnit;
  final String variantId, businessId, name, baseUnitId;
  final int defaultGstRateBps;
  final String? productId, productName, sku, hsnCode, barcode, brand, category;
  String get displayName =>
      [if (productName?.trim().isNotEmpty == true) productName!, name]
          .where((value) => value.trim().isNotEmpty)
          .join(' • ');
  final String status;
  bool get isActive => status.toUpperCase() == 'ACTIVE';
  final int purchaseRate, sellingPrice, mrp;
  final String? variantCode,
      shadeId,
      shadeCode,
      packSizeId,
      packSize,
      finishId,
      colourFamilyId,
      baseTypeId;

  factory ProductVariantModel.fromData(
    String id,
    Map<String, dynamic> data,
  ) => ProductVariantModel(
    tenantId: data['tenantId'] as String? ?? '',
    gstOverride: data['gstOverride'] as bool?,
    attributeValues: {
      for (final key in [
        'shade',
        'shadeCode',
        'finish',
        'colourFamily',
        'baseType',
      ])
        if (data['${key}Id'] != null || data[key] != null)
          key: data['${key}Id'] ?? data[key],
      ...Map<String, dynamic>.from(data['attributeValues'] as Map? ?? {}),
    },
    packUnitId: data['packUnitId'] as String?,
    commercialUnitId: data['commercialUnitId'] as String?,
    commercialUnitName: data['commercialUnitName'] as String?,
    baseQuantityPerCommercialUnit:
        data['baseQuantityPerCommercialUnit'] as num? ?? 1,
    trackStock: data['trackStock'] as bool? ?? true,
    priceIncludesTax: data['priceIncludesTax'] as bool? ?? false,
    reorderLevel: (data['reorderLevel'] as num?)?.toInt() ?? 0,
    variantId: data['variantId'] as String? ?? id,
    businessId: data['businessId'] as String? ?? '',
    name: data['variantName'] as String? ?? data['name'] as String? ?? '',
    baseUnitId:
        data['baseUnitId'] as String? ?? data['unitId'] as String? ?? 'UNIT',
    defaultGstRateBps:
        (data['defaultGstRate'] as num?)?.toInt() ??
        (data['defaultGstRateBps'] as num?)?.toInt() ??
        0,
    productId: data['productId'] as String?,
    productName: data['productName'] as String?,
    sku: data['sku'] as String? ?? data['barcode'] as String?,
    hsnCode: data['hsnCode'] as String?,
    barcode: data['barcode'] as String?,
    brand: data['brand'] as String?,
    category: data['categoryName'] as String? ?? data['category'] as String?,
    status: data['status'] as String? ?? 'ACTIVE',
    purchaseRate: (data['purchaseRate'] as num?)?.toInt() ?? 0,
    sellingPrice: (data['sellingPrice'] as num?)?.toInt() ?? 0,
    mrp: (data['mrp'] as num?)?.toInt() ?? 0,
    variantCode: data['variantCode'] as String?,
    shadeId: data['shadeId'] as String?,
    shadeCode: data['shadeCode'] as String?,
    packSizeId: data['packSizeId'] as String?,
    packSize: data['packSize']?.toString(),
    finishId: data['finishId'] as String?,
    colourFamilyId: data['colourFamilyId'] as String?,
    baseTypeId: data['baseTypeId'] as String?,
  );
}

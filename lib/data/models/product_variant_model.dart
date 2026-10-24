import 'quantity_discount_slab.dart';

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
    this.quantitySlabs = const [],
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
  final List<QuantityDiscountSlab> quantitySlabs;
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
    quantitySlabs: (data['quantitySlabs'] as List?)
        ?.whereType<Map>()
        .map((e) => QuantityDiscountSlab.fromData(Map<String, dynamic>.from(e)))
        .toList() ??
        const [],
  );

  ProductVariantModel copyWith({
    String? tenantId,
    bool? gstOverride,
    Map<String, dynamic>? attributeValues,
    String? packUnitId,
    String? commercialUnitId,
    String? commercialUnitName,
    num? baseQuantityPerCommercialUnit,
    bool? trackStock,
    bool? priceIncludesTax,
    int? reorderLevel,
    String? variantId,
    String? businessId,
    String? name,
    String? baseUnitId,
    int? defaultGstRateBps,
    String? productId,
    String? productName,
    String? sku,
    String? hsnCode,
    String? barcode,
    String? brand,
    String? category,
    String? status,
    int? purchaseRate,
    int? sellingPrice,
    int? mrp,
    String? variantCode,
    String? shadeId,
    String? shadeCode,
    String? packSizeId,
    String? packSize,
    String? finishId,
    String? colourFamilyId,
    String? baseTypeId,
    List<QuantityDiscountSlab>? quantitySlabs,
  }) => ProductVariantModel(
    tenantId: tenantId ?? this.tenantId,
    gstOverride: gstOverride ?? this.gstOverride,
    attributeValues: attributeValues ?? this.attributeValues,
    packUnitId: packUnitId ?? this.packUnitId,
    commercialUnitId: commercialUnitId ?? this.commercialUnitId,
    commercialUnitName: commercialUnitName ?? this.commercialUnitName,
    baseQuantityPerCommercialUnit:
        baseQuantityPerCommercialUnit ?? this.baseQuantityPerCommercialUnit,
    trackStock: trackStock ?? this.trackStock,
    priceIncludesTax: priceIncludesTax ?? this.priceIncludesTax,
    reorderLevel: reorderLevel ?? this.reorderLevel,
    variantId: variantId ?? this.variantId,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    baseUnitId: baseUnitId ?? this.baseUnitId,
    defaultGstRateBps: defaultGstRateBps ?? this.defaultGstRateBps,
    productId: productId ?? this.productId,
    productName: productName ?? this.productName,
    sku: sku ?? this.sku,
    hsnCode: hsnCode ?? this.hsnCode,
    barcode: barcode ?? this.barcode,
    brand: brand ?? this.brand,
    category: category ?? this.category,
    status: status ?? this.status,
    purchaseRate: purchaseRate ?? this.purchaseRate,
    sellingPrice: sellingPrice ?? this.sellingPrice,
    mrp: mrp ?? this.mrp,
    variantCode: variantCode ?? this.variantCode,
    shadeId: shadeId ?? this.shadeId,
    shadeCode: shadeCode ?? this.shadeCode,
    packSizeId: packSizeId ?? this.packSizeId,
    packSize: packSize ?? this.packSize,
    finishId: finishId ?? this.finishId,
    colourFamilyId: colourFamilyId ?? this.colourFamilyId,
    baseTypeId: baseTypeId ?? this.baseTypeId,
    quantitySlabs: quantitySlabs ?? this.quantitySlabs,
  );
}

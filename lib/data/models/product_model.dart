import 'product_variant_model.dart';
import 'quantity_discount_slab.dart';
import '../services/historical_catalogue_resolver.dart';

class ProductModel {
  const ProductModel({
    required this.productId,
    required this.tenantId,
    required this.businessId,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.attributeValues = const {},
    this.brand,
    this.brandId,
    this.category,
    this.categoryId,
    this.subcategory,
    this.subcategoryId,
    this.description,
    this.baseUnitId,
    this.hsnCode,
    this.defaultGstRateBps = 0,
    this.variants = const [],
    this.quantitySlabs = const [],
    this.productCode,
    this.usageIds = const [],
    this.surfaceIds = const [],
    this.segmentId,
    this.finishId,
    this.hsnCodeId,
    this.numberOfCoats,
    this.dilutionTypeId,
    this.productImage,
    this.catalogueFingerprint,
    this.masterProductId,
    this.historicalCatalogueResolution,
    this.syncStatus = 'SYNCED',
  });

  final Map<String, dynamic> attributeValues;
  final String productId, tenantId, businessId, name, status;
  final String? brand,
      brandId,
      category,
      categoryId,
      subcategory,
      subcategoryId,
      description,
      baseUnitId,
      hsnCode,
      hsnCodeId,
      segmentId,
      finishId,
      dilutionTypeId,
      productImage,
      productCode,
      catalogueFingerprint,
      masterProductId;
  final List<String> usageIds, surfaceIds;
  final int? numberOfCoats;
  final int defaultGstRateBps;
  final DateTime? createdAt, updatedAt;
  final List<ProductVariantModel> variants;
  final List<QuantityDiscountSlab> quantitySlabs;

  final String syncStatus;
  final HistoricalCatalogueResolution? historicalCatalogueResolution;
  bool get isActive => status.toUpperCase() == 'ACTIVE';

  ProductModel withVariants(List<ProductVariantModel> value) =>
      copyWith(variants: value);

  ProductModel copyWith({
    String? productId,
    String? tenantId,
    String? businessId,
    String? name,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? attributeValues,
    String? brand,
    String? brandId,
    String? category,
    String? categoryId,
    String? subcategory,
    String? subcategoryId,
    String? description,
    String? baseUnitId,
    String? hsnCode,
    String? hsnCodeId,
    int? defaultGstRateBps,
    List<ProductVariantModel>? variants,
    List<QuantityDiscountSlab>? quantitySlabs,
    String? productCode,
    List<String>? usageIds,
    List<String>? surfaceIds,
    String? segmentId,
    String? finishId,
    int? numberOfCoats,
    String? dilutionTypeId,
    String? productImage,
    String? catalogueFingerprint,
    String? masterProductId,
    HistoricalCatalogueResolution? historicalCatalogueResolution,
    String? syncStatus,
  }) => ProductModel(
    productId: productId ?? this.productId,
    tenantId: tenantId ?? this.tenantId,
    businessId: businessId ?? this.businessId,
    name: name ?? this.name,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    attributeValues: attributeValues ?? this.attributeValues,
    brand: brand ?? this.brand,
    brandId: brandId ?? this.brandId,
    category: category ?? this.category,
    categoryId: categoryId ?? this.categoryId,
    subcategory: subcategory ?? this.subcategory,
    subcategoryId: subcategoryId ?? this.subcategoryId,
    description: description ?? this.description,
    baseUnitId: baseUnitId ?? this.baseUnitId,
    hsnCode: hsnCode ?? this.hsnCode,
    defaultGstRateBps: defaultGstRateBps ?? this.defaultGstRateBps,
    variants: variants ?? this.variants,
    quantitySlabs: quantitySlabs ?? this.quantitySlabs,
    productCode: productCode ?? this.productCode,
    usageIds: usageIds ?? this.usageIds,
    surfaceIds: surfaceIds ?? this.surfaceIds,
    segmentId: segmentId ?? this.segmentId,
    finishId: finishId ?? this.finishId,
    hsnCodeId: hsnCodeId ?? this.hsnCodeId,
    numberOfCoats: numberOfCoats ?? this.numberOfCoats,
    dilutionTypeId: dilutionTypeId ?? this.dilutionTypeId,
    productImage: productImage ?? this.productImage,
    catalogueFingerprint: catalogueFingerprint ?? this.catalogueFingerprint,
    masterProductId: masterProductId ?? this.masterProductId,
    historicalCatalogueResolution:
        historicalCatalogueResolution ?? this.historicalCatalogueResolution,
    syncStatus: syncStatus ?? this.syncStatus,
  );

  static String? parseProductImage(Map<String, dynamic> data) {
    final img = (data['productImage'] as String?)?.trim();
    if (img != null && img.isNotEmpty) return img;
    final url = (data['imageUrl'] as String?)?.trim();
    if (url != null && url.isNotEmpty) return url;
    return null;
  }

  factory ProductModel.fromData(Map<String, dynamic> data) => ProductModel(
    productId: data['productId'] as String? ?? '',
    tenantId: data['tenantId'] as String? ?? '',
    businessId: data['businessId'] as String? ?? '',
    name: data['productName'] as String? ?? data['name'] as String? ?? '',
    status: data['status'] as String? ?? 'ACTIVE',
    createdAt: data['createdAt'] as DateTime?,
    updatedAt: data['updatedAt'] as DateTime?,
    attributeValues: Map<String, dynamic>.from(
      data['attributeValues'] as Map? ?? const {},
    ),
    category: data['categoryName'] as String? ?? data['category'] as String?,
    categoryId: data['categoryId'] as String?,
    subcategory: data['subcategory'] as String?,
    subcategoryId: data['subcategoryId'] as String?,
    brand: data['brand'] as String?,
    brandId: data['brandId'] as String?,
    description: data['description'] as String?,
    baseUnitId: data['baseUnitId'] as String?,
    hsnCode: data['hsnCode'] as String?,
    productCode: data['productCode'] as String?,
    productImage: parseProductImage(data),
    catalogueFingerprint: data['catalogueFingerprint'] as String?,
    masterProductId: data['masterProductId'] as String?,
    defaultGstRateBps: (data['defaultGstRateBps'] as num?)?.toInt() ?? 0,
    quantitySlabs: (data['quantitySlabs'] as List?)
        ?.whereType<Map>()
        .map((e) => QuantityDiscountSlab.fromData(Map<String, dynamic>.from(e)))
        .toList() ??
        const [],
    syncStatus: data['syncStatus'] as String? ?? 'SYNCED',
  );

  Map<String, dynamic> toData() => {
    'productId': productId,
    'tenantId': tenantId,
    'businessId': businessId,
    'productName': name,
    'status': status,
    if (createdAt != null) 'createdAt': createdAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
    'attributeValues': attributeValues,
    if (category != null) 'categoryName': category,
    if (categoryId != null) 'categoryId': categoryId,
    if (subcategory != null) 'subcategory': subcategory,
    if (subcategoryId != null) 'subcategoryId': subcategoryId,
    if (brand != null) 'brand': brand,
    if (brandId != null) 'brandId': brandId,
    if (description != null) 'description': description,
    if (baseUnitId != null) 'baseUnitId': baseUnitId,
    if (hsnCode != null) 'hsnCode': hsnCode,
    if (productCode != null) 'productCode': productCode,
    if (productImage != null && productImage!.trim().isNotEmpty) ...{
      'productImage': productImage!.trim(),
      'imageUrl': productImage!.trim(),
    } else ...{
      'productImage': '',
      'imageUrl': '',
    },
    if (catalogueFingerprint != null)
      'catalogueFingerprint': catalogueFingerprint,
    if (masterProductId != null) 'masterProductId': masterProductId,
    'defaultGstRateBps': defaultGstRateBps,
    if (quantitySlabs.isNotEmpty)
      'quantitySlabs': quantitySlabs.map((s) => s.toMap()).toList(),
  };
}

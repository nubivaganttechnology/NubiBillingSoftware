/// Placement of a business-level product master at one outlet.
///
/// The product and its variants stay business-level masters; this record only
/// says "this outlet carries that product". The logical key is
/// tenantId + businessId + outletId + productId and is enforced by using the
/// deterministic [documentId] as the document identity.
class OutletProductModel {
  const OutletProductModel({
    required this.outletProductId,
    required this.tenantId,
    required this.businessId,
    required this.outletId,
    required this.productId,
    required this.status,
    required this.isActive,
    this.variantIds,
    this.createdAt,
    this.updatedAt,
  });

  static const statusActive = 'ACTIVE';
  static const statusInactive = 'INACTIVE';

  final String outletProductId,
      tenantId,
      businessId,
      outletId,
      productId,
      status;
  final bool isActive;

  /// Optional restriction. `null` means every variant of the product.
  final List<String>? variantIds;
  final DateTime? createdAt, updatedAt;

  /// Deterministic identity for the logical placement key.
  static String documentId({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String productId,
  }) {
    final source = [tenantId, businessId, outletId, productId].join('\u0000');
    var a = 0x811c9dc5;
    var b = 0x9e3779b9;
    for (final unit in source.codeUnits) {
      a = ((a ^ unit) * 0x01000193) & 0xffffffff;
      b = ((b ^ (unit + 0x9e37)) * 0x85ebca6b) & 0xffffffff;
    }
    return 'OP_${a.toRadixString(16).padLeft(8, '0')}'
        '${b.toRadixString(16).padLeft(8, '0')}';
  }

  factory OutletProductModel.fromData(String id, Map<String, dynamic> data) {
    final status = (data['status'] as String? ?? statusActive).toUpperCase();
    final variants = data['variantIds'];
    return OutletProductModel(
      outletProductId: data['outletProductId'] as String? ?? id,
      tenantId: data['tenantId'] as String? ?? '',
      businessId: data['businessId'] as String? ?? '',
      outletId: data['outletId'] as String? ?? '',
      productId: data['productId'] as String? ?? '',
      status: status,
      // A placement is live only when both flags agree.
      isActive: data['isActive'] != false && status == statusActive,
      variantIds: variants is List
          ? [for (final v in variants) v.toString()]
          : null,
      createdAt: data['createdAt'] as DateTime?,
      updatedAt: data['updatedAt'] as DateTime?,
    );
  }

  static Map<String, dynamic> newPlacementData({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String productId,
    required DateTime now,
    List<String>? variantIds,
    String? source,
    String? createdBy,
  }) => {
    'outletProductId': documentId(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      productId: productId,
    ),
    'tenantId': tenantId,
    'businessId': businessId,
    'outletId': outletId,
    'productId': productId,
    'status': statusActive,
    'isActive': true,
    if (variantIds != null) 'variantIds': variantIds,
    if (source != null) 'placementSource': source,
    if (createdBy != null) 'createdBy': createdBy,
    'createdAt': now,
    'updatedAt': now,
  };

  static const sourceNewProduct = 'NEW_PRODUCT';
  static const sourceManualAssignment = 'MANUAL_ASSIGNMENT';
  static const sourceLegacyBackfill = 'LEGACY_BACKFILL';
}

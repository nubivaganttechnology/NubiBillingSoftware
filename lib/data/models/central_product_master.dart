import '../services/firestore_rest_service.dart';

class CentralProductMaster {
  const CentralProductMaster({
    required this.masterProductId,
    required this.productName,
    required this.normalizedProductName,
    required this.businessTypeId,
    required this.businessTypeName,
    required this.businessSubTypeId,
    required this.businessSubTypeName,
    required this.brandId,
    required this.brandName,
    required this.categoryId,
    required this.categoryName,
    required this.subcategoryId,
    required this.subcategoryName,
    required this.searchTokens,
    required this.isActive,
    required this.status,
    this.rangeName,
    this.catalogueId,
    this.scopeType,
    this.seriesOrVariant,
    this.packSizes,
    this.finish,
    this.colour,
    this.colourCode,
    this.coverage,
    this.dryingRecoatTime,
    this.warranty,
    this.dilution,
    this.recommendedCoats,
    this.benefits,
    this.description,
    this.imageUrl,
    this.technicalDatasheetUrl,
    this.productUrl,
  });

  final String masterProductId;
  final String productName;
  final String normalizedProductName;
  final String businessTypeId;
  final String businessTypeName;
  final String businessSubTypeId;
  final String businessSubTypeName;
  final String brandId;
  final String brandName;
  final String? rangeName;
  final String categoryId;
  final String categoryName;
  final String subcategoryId;
  final String subcategoryName;
  final List<String> searchTokens;
  final bool isActive;
  final String status;
  final String? catalogueId;
  final String? scopeType;
  final String? seriesOrVariant;
  final Object? packSizes;
  final String? finish;
  final String? colour;
  final String? colourCode;
  final Object? coverage;
  final Object? dryingRecoatTime;
  final Object? warranty;
  final Object? dilution;
  final Object? recommendedCoats;
  final Object? benefits;
  final String? description;
  final String? imageUrl;
  final String? technicalDatasheetUrl;
  final String? productUrl;

  factory CentralProductMaster.fromFirestoreRest(
    Map<String, dynamic> document,
  ) {
    final fields = FirestoreRestService.decodeFields(
      document['fields'] as Map<String, dynamic>? ?? const {},
    );
    final documentId = (document['name'] as String? ?? '').split('/').last;
    return CentralProductMaster.fromData(documentId, fields);
  }

  factory CentralProductMaster.fromData(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final productName = data['productName'] as String? ?? '';
    final masterProductId = data['masterProductId'] as String? ?? documentId;
    final businessTypeId = data['businessTypeId'] as String? ?? '';
    final businessTypeName = data['businessTypeName'] as String? ?? '';
    final businessSubTypeId = data['businessSubTypeId'] as String? ?? '';
    final businessSubTypeName = data['businessSubTypeName'] as String? ?? '';
    final brandId = data['brandId'] as String? ?? '';
    final brandName = data['brandName'] as String? ?? '';
    final categoryId = data['categoryId'] as String? ?? '';
    final categoryName = data['categoryName'] as String? ?? '';
    final subcategoryId = data['subcategoryId'] as String? ?? '';
    final subcategoryName = data['subcategoryName'] as String? ?? '';
    if ([
      masterProductId,
      productName,
      businessTypeId,
      businessTypeName,
      businessSubTypeId,
      businessSubTypeName,
      brandId,
      brandName,
      categoryId,
      categoryName,
      subcategoryId,
      subcategoryName,
    ].any((value) => value.trim().isEmpty)) {
      throw const FormatException('Invalid central product master record.');
    }
    final rawTokens = data['searchTokens'];
    final searchTokens = rawTokens is List
        ? rawTokens.whereType<String>().toList(growable: false)
        : const <String>[];
    return CentralProductMaster(
      masterProductId: masterProductId,
      productName: productName,
      normalizedProductName:
          data['normalizedProductName'] as String? ??
          productName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
      businessTypeId: businessTypeId,
      businessTypeName: businessTypeName,
      businessSubTypeId: businessSubTypeId,
      businessSubTypeName: businessSubTypeName,
      brandId: brandId,
      brandName: brandName,
      rangeName: data['rangeName'] as String?,
      categoryId: categoryId,
      categoryName: categoryName,
      subcategoryId: subcategoryId,
      subcategoryName: subcategoryName,
      searchTokens: searchTokens,
      isActive: data['isActive'] == true,
      status: data['status'] as String? ?? '',
      catalogueId: data['catalogueId'] as String?,
      scopeType: data['scopeType'] as String?,
      seriesOrVariant: data['seriesOrVariant'] as String?,
      packSizes: data['packSizes'],
      finish: data['finish'] as String?,
      colour: data['colour'] as String?,
      colourCode: data['colourCode'] as String?,
      coverage: data['coverage'],
      dryingRecoatTime: data['dryingRecoatTime'],
      warranty: data['warranty'],
      dilution: data['dilution'],
      recommendedCoats: data['recommendedCoats'],
      benefits: data['benefits'],
      description: data['description'] as String?,
      imageUrl: data['imageUrl'] as String?,
      technicalDatasheetUrl: data['technicalDatasheetUrl'] as String?,
      productUrl: data['productUrl'] as String?,
    );
  }
}

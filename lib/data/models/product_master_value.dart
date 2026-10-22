class ProductMasterValue {
  const ProductMasterValue({
    required this.id,
    required this.name,
    required this.status,
    this.scopeType = 'BUSINESS',
    this.code,
    this.categoryId,
    this.type,
    this.measurementDimension,
    this.applicableAttributes = const [],
    this.rawFields,
  });

  final String scopeType;
  final String id;
  final String name;
  final String status;
  final String? code;
  final String? categoryId;
  final String? type;
  final String? measurementDimension;
  final List<String> applicableAttributes;
  final Map<String, dynamic>? rawFields;

  bool get isActive => status.toUpperCase() != 'INACTIVE';
}

class BusinessSubTypeModel {
  const BusinessSubTypeModel({
    required this.id,
    required this.businessTypeId,
    required this.name,
    required this.isActive,
    required this.displayOrder,
    this.description,
  });

  final String id;
  final String businessTypeId;
  final String name;
  final bool isActive;
  final int displayOrder;
  final String? description;

  factory BusinessSubTypeModel.fromData(String id, Map<String, dynamic> data) {
    if (data['businessTypeId'] is! String || data['name'] is! String) {
      throw const FormatException('Invalid business sub-type.');
    }
    return BusinessSubTypeModel(
      id: id,
      businessTypeId: data['businessTypeId'] as String,
      name: data['name'] as String,
      isActive: data['isActive'] == true,
      displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 0,
      description: data['description'] as String?,
    );
  }
}

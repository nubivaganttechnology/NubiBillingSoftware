class BusinessTypeModel {
  const BusinessTypeModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.displayOrder,
    this.description,
  });

  final String id;
  final String name;
  final bool isActive;
  final int displayOrder;
  final String? description;

  factory BusinessTypeModel.fromData(String id, Map<String, dynamic> data) {
    if (data['name'] is! String) {
      throw const FormatException('Invalid business type.');
    }
    return BusinessTypeModel(
      id: id,
      name: data['name'] as String,
      isActive: data['isActive'] == true,
      displayOrder: (data['displayOrder'] as num?)?.toInt() ?? 0,
      description: data['description'] as String?,
    );
  }
}

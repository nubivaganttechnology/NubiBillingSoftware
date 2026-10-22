class ReclassificationPlan {
  const ReclassificationPlan({
    required this.classificationChanged,
    this.originalCategoryId,
    this.originalSubcategoryId,
    required this.newCategoryId,
    required this.newSubcategoryId,
    this.preservedVariantIds = const [],
    this.updatedVariantIds = const [],
    this.newVariantCount = 0,
    this.retiredVariantIds = const [],
    this.removedProductAttributeIds = const [],
    this.removedVariantAttributeIds = const [],
    this.blockingIssues = const [],
    this.warnings = const [],
  });

  final bool classificationChanged;
  final String? originalCategoryId;
  final String? originalSubcategoryId;
  final String newCategoryId;
  final String newSubcategoryId;
  final List<String> preservedVariantIds;
  final List<String> updatedVariantIds;
  final int newVariantCount;
  final List<String> retiredVariantIds;
  final List<String> removedProductAttributeIds;
  final List<String> removedVariantAttributeIds;
  final List<String> blockingIssues;
  final List<String> warnings;

  bool get isDestructive =>
      retiredVariantIds.isNotEmpty ||
      removedProductAttributeIds.isNotEmpty ||
      removedVariantAttributeIds.isNotEmpty;

  bool get isValid => blockingIssues.isEmpty;

  String buildImpactSummary() {
    final parts = <String>[];
    if (preservedVariantIds.isNotEmpty) {
      parts.add('keep ${preservedVariantIds.length} SKU(s)');
    }
    if (newVariantCount > 0) {
      parts.add('add $newVariantCount new SKU(s)');
    }
    if (retiredVariantIds.isNotEmpty) {
      parts.add('retire ${retiredVariantIds.length} SKU(s)');
    }
    final droppedCount =
        removedProductAttributeIds.length + removedVariantAttributeIds.length;
    if (droppedCount > 0) {
      parts.add('remove $droppedCount attribute(s) that no longer apply');
    }
    if (parts.isEmpty) {
      return 'No structural changes to variants or attributes.';
    }
    return 'Changing classification will ${parts.join(", ")}.';
  }
}

class AppConfigModel {
  const AppConfigModel({
    required this.isActive,
    this.maintenanceImageUrl,
    this.maintenanceMessage,
    this.maintenanceTitle,
  });
  final bool isActive;
  final String? maintenanceImageUrl, maintenanceMessage, maintenanceTitle;
  factory AppConfigModel.fromFields(Map<String, dynamic> f) {
    final a = f['isActive']?['booleanValue'];
    if (a is! bool) throw const FormatException('Invalid config');
    String? s(String k) => f[k]?['stringValue'] as String?;
    return AppConfigModel(
      isActive: a,
      maintenanceImageUrl: s('maintenanceImageUrl'),
      maintenanceMessage: s('maintenanceMessage'),
      maintenanceTitle: s('maintenanceTitle'),
    );
  }
}

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../models/business_settings_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class SettingsRepository {
  SettingsRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<BusinessSettingsModel> loadSettings({
    required String businessId,
    required String tenantId,
    required String token,
  }) async {
    try {
      final doc = await firestore.getDocument(
        FirebaseConstants.businessSettings,
        businessId,
        idToken: token,
      );
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      return BusinessSettingsModel.fromData(
        businessId,
        fields,
        tenantId: tenantId,
      );
    } on AppException catch (e) {
      if (e.code == 'not-found') {
        return BusinessSettingsModel.defaultSettings(
          businessId: businessId,
          tenantId: tenantId,
        );
      }
      rethrow;
    } catch (_) {
      // Return default configuration if not initialized yet
      return BusinessSettingsModel.defaultSettings(
        businessId: businessId,
        tenantId: tenantId,
      );
    }
  }

  Future<BusinessSettingsModel> saveSettings({
    required BusinessSettingsModel settings,
    required String token,
  }) async {
    final payload = settings.toMap();
    try {
      await firestore.getDocument(
        FirebaseConstants.businessSettings,
        settings.businessId,
        idToken: token,
      );
      await firestore.updateDocument(
        FirebaseConstants.businessSettings,
        settings.businessId,
        payload,
        idToken: token,
      );
    } catch (_) {
      await firestore.createDocument(
        FirebaseConstants.businessSettings,
        settings.businessId,
        payload,
        idToken: token,
      );
    }
    return settings;
  }
}

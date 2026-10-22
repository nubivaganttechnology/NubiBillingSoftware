import '../../core/constants/firebase_constants.dart';
import '../models/app_config_model.dart';
import 'firestore_data_service.dart';

class AppConfigService {
  AppConfigService(this.firestore);
  final FirestoreDataService firestore;
  Future<AppConfigModel> load() async {
    final d = await firestore.getDocument(
      FirebaseConstants.appConfig,
      FirebaseConstants.system,
    );
    final f = d['fields'];
    if (f is! Map<String, dynamic>) {
      throw const FormatException('Invalid config');
    }
    return AppConfigModel.fromFields(f);
  }
}

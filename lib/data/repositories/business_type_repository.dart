import '../../core/constants/firebase_constants.dart';
import '../models/business_type_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class BusinessTypeRepository {
  BusinessTypeRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<BusinessTypeModel>> getActiveBusinessTypes(String token) async {
    final docs = await firestore.queryEqual(
      FirebaseConstants.businessTypes,
      'isActive',
      true,
      idToken: token,
    );
    final types = docs
        .map(
          (doc) => BusinessTypeModel.fromData(
            _id(doc),
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .where((item) => item.isActive)
        .toList();
    types.sort((a, b) {
      final order = a.displayOrder.compareTo(b.displayOrder);
      return order == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : order;
    });
    return types;
  }

  Future<BusinessTypeModel?> getBusinessTypeById(
    String id,
    String token,
  ) async {
    try {
      final doc = await firestore.getDocument(
        FirebaseConstants.businessTypes,
        id,
        idToken: token,
      );
      final model = BusinessTypeModel.fromData(
        id,
        FirestoreRestService.decodeFields(doc['fields']),
      );
      return model.isActive ? model : null;
    } catch (_) {
      return null;
    }
  }

  static String _id(Map<String, dynamic> doc) =>
      (doc['name'] as String? ?? '').split('/').last;
}

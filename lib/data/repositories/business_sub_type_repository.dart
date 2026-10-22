import '../../core/constants/firebase_constants.dart';
import '../models/business_sub_type_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class BusinessSubTypeRepository {
  BusinessSubTypeRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<BusinessSubTypeModel>> getActiveSubTypesByBusinessType(
    String businessTypeId,
    String token,
  ) async {
    final docs = await firestore.queryEqual(
      FirebaseConstants.businessSubTypes,
      'businessTypeId',
      businessTypeId,
      idToken: token,
    );
    final items = docs
        .map(
          (doc) => BusinessSubTypeModel.fromData(
            (doc['name'] as String? ?? '').split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .where((item) => item.isActive && item.businessTypeId == businessTypeId)
        .toList();
    items.sort((a, b) {
      final order = a.displayOrder.compareTo(b.displayOrder);
      return order == 0
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : order;
    });
    return items;
  }

  Future<BusinessSubTypeModel?> getSubTypeById(String id, String token) async {
    try {
      final doc = await firestore.getDocument(
        FirebaseConstants.businessSubTypes,
        id,
        idToken: token,
      );
      final item = BusinessSubTypeModel.fromData(
        id,
        FirestoreRestService.decodeFields(doc['fields']),
      );
      return item.isActive ? item : null;
    } catch (_) {
      return null;
    }
  }
}

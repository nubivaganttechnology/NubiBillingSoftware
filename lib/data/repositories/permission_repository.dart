import '../../core/constants/firebase_constants.dart';
import '../models/permission_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class PermissionRepository {
  PermissionRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<PermissionModel>> getActivePermissions(String token) async {
    final docs = await firestore.listDocuments(
      FirebaseConstants.permissions,
      idToken: token,
    );
    final permissions = docs
        .map(
          (doc) => PermissionModel.fromData(
            (doc['name'] as String? ?? '').split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .where(
          (permission) =>
              permission.permissionId.isNotEmpty && permission.isActive,
        )
        .toList();
    permissions.sort((a, b) {
      final group = a.groupName.compareTo(b.groupName);
      return group == 0 ? a.displayOrder.compareTo(b.displayOrder) : group;
    });
    return permissions;
  }
}

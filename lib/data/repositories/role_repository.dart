import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../models/role_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class RoleRepository {
  RoleRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<List<RoleModel>> getActiveRoles(String token) async {
    final docs = await firestore.listDocuments(
      FirebaseConstants.roles,
      idToken: token,
    );
    return docs
        .map(
          (doc) => RoleModel.fromData(
            (doc['name'] as String? ?? '').split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .where(
          (role) =>
              role.roleId.isNotEmpty &&
              role.roleName.isNotEmpty &&
              role.isActive,
        )
        .toList();
  }

  Future<RoleModel> getRoleById(String id, String token) async {
    late final Map<String, dynamic> doc;
    try {
      doc = await firestore.getDocument(
        FirebaseConstants.roles,
        id,
        idToken: token,
      );
    } on AppException catch (error) {
      if (error.code == 'not-found') {
        throw const AppException(
          'Your employee role is missing. Ask the owner to assign an active role.',
          code: 'role-not-found',
        );
      }
      rethrow;
    }
    final role = RoleModel.fromData(
      (doc['name'] as String? ?? '').split('/').last,
      FirestoreRestService.decodeFields(doc['fields']),
    );
    if (role.roleId != id ||
        role.roleName.isEmpty ||
        role.status.toLowerCase() != 'active') {
      throw const AppException(
        'The employee role is not configured or is inactive.',
      );
    }
    return role;
  }

  Future<List<RoleModel>> getRolesByIds(List<String> ids, String token) async {
    final roles = <RoleModel>[];
    for (final id in ids.toSet()) {
      roles.add(await getRoleById(id, token));
    }
    return roles;
  }

  Future<List<String>> getPermissions(String id, String token) async =>
      (await getRoleById(id, token)).permissions;
}

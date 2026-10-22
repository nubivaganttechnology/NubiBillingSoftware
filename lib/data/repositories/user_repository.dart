import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../models/user_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';

class UserRepository {
  UserRepository(this.firestore);
  final FirestoreDataService firestore;

  Future<void> createEmployeeProfile({
    required String uid,
    required String name,
    required String email,
    required String mobile,
    required bool isActive,
    required String token,
  }) => firestore.createDocument(FirebaseConstants.user, uid, {
    'uid': uid,
    'accountType': 'employee',
    'name': name.trim(),
    'email': email.trim().toLowerCase(),
    'mobile': mobile,
    'isActive': isActive,
    'createdAt': DateTime.now().toUtc(),
    'updatedAt': DateTime.now().toUtc(),
  }, idToken: token);

  Future<void> updateEmployeeProfile({
    required String uid,
    required String email,
    required String name,
    required String mobile,
    required bool isActive,
    required String token,
  }) async {
    final fields = {
      'name': name.trim(),
      'mobile': mobile,
      'isActive': isActive,
      'updatedAt': DateTime.now().toUtc(),
    };
    try {
      await firestore.updateDocument(
        FirebaseConstants.user,
        uid,
        fields,
        idToken: token,
      );
    } on AppException catch (error) {
      if (error.code != 'not-found') rethrow;
      await firestore.updateDocument(
        FirebaseConstants.user,
        email.trim().toLowerCase(),
        fields,
        idToken: token,
      );
    }
  }

  Future<UserModel> load(String uid, String email, String token) async {
    Map<String, dynamic> d;
    try {
      d = await firestore.getDocument(
        FirebaseConstants.user,
        uid,
        idToken: token,
      );
    } on AppException catch (x) {
      if (x.code != 'not-found') rethrow;
      try {
        d = await firestore.getDocument(
          FirebaseConstants.user,
          email,
          idToken: token,
        );
      } on AppException catch (legacyError) {
        if (legacyError.code == 'not-found') {
          throw const AppException(
            'Your NubiBill profile is missing. Ask your administrator to create the user record for this Firebase account.',
            code: 'user-profile-not-found',
          );
        }
        rethrow;
      }
    }
    final f = d['fields'];
    if (f is! Map<String, dynamic>) {
      throw const AppException('Your user profile is not configured.');
    }
    try {
      return UserModel.fromData(uid, FirestoreRestService.decodeFields(f));
    } on FormatException {
      throw const AppException(
        'Your user profile is not configured correctly.',
      );
    }
  }
}

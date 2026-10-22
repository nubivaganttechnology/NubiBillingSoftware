import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/business_model.dart';
import '../models/employee_model.dart';
import '../models/outlet_model.dart';
import '../models/role_model.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';
import 'business_repository.dart';
import 'outlet_repository.dart';

class EmployeeRepository {
  EmployeeRepository(
    this.firestore,
    this.businesses,
    this.outlets,
    this.transactions,
  );
  final FirestoreDataService firestore;
  final BusinessRepository businesses;
  final OutletRepository outlets;
  final FirestoreTransactionService transactions;

  Future<List<EmployeeModel>> getEmployeesByOwner(
    String ownerUid,
    String token,
  ) async {
    final docs = await firestore.queryEqual(
      FirebaseConstants.employees,
      'ownerUid',
      ownerUid,
      idToken: token,
    );
    return docs
        .map(
          (doc) => EmployeeModel.fromData(
            (doc['name'] as String? ?? '').split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .toList();
  }

  Future<List<OutletModel>> getOutletsForBusinesses(
    List<String> businessIds,
    String ownerUid,
    String token,
  ) async {
    final results = await outlets.getOutletsByBusinessIds(
      businessIds,
      token,
      tenantId: ownerUid,
    );
    return results.where((outlet) => outlet.ownerUid == ownerUid).toList();
  }

  Future<void> validateNewEmployee({
    required String ownerUid,
    required String name,
    required String email,
    required String mobile,
    required String employeeCode,
    required List<String> businessIds,
    required List<String> outletIds,
    required List<String> roleIds,
    required List<String> permissionIds,
    required String token,
    required List<RoleModel> activeRoles,
    String? excludeUid,
  }) async {
    final existing = (await getEmployeesByOwner(
      ownerUid,
      token,
    )).where((employee) => employee.uid != excludeUid).toList();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedMobile = mobile.replaceAll(RegExp(r'\D'), '');
    final normalizedCode = employeeCode.trim().toLowerCase();
    if (existing.any((e) => e.email.trim().toLowerCase() == normalizedEmail)) {
      throw const AppException('An employee with this email already exists.');
    }
    if (existing.any(
      (e) => (e.mobile ?? '').replaceAll(RegExp(r'\D'), '') == normalizedMobile,
    )) {
      throw const AppException(
        'An employee with this mobile number already exists.',
      );
    }
    if (normalizedCode.isNotEmpty &&
        existing.any(
          (e) => (e.employeeCode ?? '').trim().toLowerCase() == normalizedCode,
        )) {
      throw const AppException('This employee code is already in use.');
    }
    if (businessIds.isEmpty || outletIds.isEmpty || roleIds.isEmpty) {
      throw const AppException(
        'Select at least one business, outlet and role.',
      );
    }
    final uniqueBusinesses = businessIds.toSet();
    for (final id in uniqueBusinesses) {
      final business = await businesses.getBusinessById(id, token);
      if (business.ownerUid != ownerUid || !business.isActive) {
        throw const AppException('A selected business is unavailable.');
      }
    }
    final uniqueOutlets = outletIds.toSet();
    for (final id in uniqueOutlets) {
      final outlet = await outlets.getOutletById(id, token);
      if (outlet.ownerUid != ownerUid ||
          !outlet.isActive ||
          !uniqueBusinesses.contains(outlet.businessId)) {
        throw const AppException(
          'An outlet must belong to a selected business.',
        );
      }
    }
    final validRoles = activeRoles.map((role) => role.roleId).toSet();
    if (!validRoles.containsAll(roleIds)) {
      throw const AppException('A selected role is unavailable or inactive.');
    }
  }

  Future<EmployeeModel> createEmployee({
    required String uid,
    required String ownerUid,
    required String name,
    required String email,
    required String mobile,
    required String employeeCode,
    required List<String> businessIds,
    required List<String> outletIds,
    required List<String> roleIds,
    required List<String> permissionIds,
    required String status,
    required List<RoleModel> activeRoles,
    required String token,
  }) async {
    await validateNewEmployee(
      ownerUid: ownerUid,
      name: name,
      email: email,
      mobile: mobile,
      employeeCode: employeeCode,
      businessIds: businessIds,
      outletIds: outletIds,
      roleIds: roleIds,
      permissionIds: permissionIds,
      token: token,
      activeRoles: activeRoles,
    );
    final id = IdGenerator.create('EMP');
    final now = DateTime.now().toUtc();
    final fields = <String, dynamic>{
      'employeeId': id,
      'uid': uid,
      'ownerUid': ownerUid,
      'name': name.trim().replaceAll(RegExp(r'\s+'), ' '),
      'email': email.trim().toLowerCase(),
      'mobile': mobile,
      'employeeCode': employeeCode.trim().isEmpty ? null : employeeCode.trim(),
      'businessIds': businessIds.toSet().toList(),
      'outletIds': outletIds.toSet().toList(),
      'roleIds': roleIds.toSet().toList(),
      'permissionIds': permissionIds.toSet().toList(),
      'status': status,
      'createdAt': now,
      'updatedAt': now,
    };
    await firestore.createDocument(
      FirebaseConstants.employees,
      id,
      fields,
      idToken: token,
    );
    return EmployeeModel.fromData(id, fields);
  }

  /// Creates a staff record in the existing employee collection without
  /// provisioning an authentication account. Temporary workers keep the same
  /// employeeId linkage as all other payroll records.
  Future<EmployeeModel> createTemporaryWorker({
    required String ownerUid,
    required String name,
    required String mobile,
    required String employeeCode,
    required List<String> businessIds,
    required List<String> outletIds,
    required String status,
    required String token,
  }) async {
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty ||
        businessIds.isEmpty ||
        outletIds.isEmpty ||
        !const {'active', 'inactive'}.contains(status.toLowerCase())) {
      throw const AppException(
        'Enter a name and select a business and outlet.',
      );
    }
    final existing = await getEmployeesByOwner(ownerUid, token);
    final normalizedCode = employeeCode.trim().toLowerCase();
    if (normalizedCode.isNotEmpty &&
        existing.any(
          (employee) =>
              (employee.employeeCode ?? '').trim().toLowerCase() ==
              normalizedCode,
        )) {
      throw const AppException('This employee code is already in use.');
    }
    final uniqueBusinesses = businessIds.toSet();
    final uniqueOutlets = outletIds.toSet();
    for (final id in uniqueBusinesses) {
      final business = await businesses.getBusinessById(id, token);
      if (business.ownerUid != ownerUid || !business.isActive) {
        throw const AppException('A selected business is unavailable.');
      }
    }
    for (final id in uniqueOutlets) {
      final outlet = await outlets.getOutletById(id, token);
      if (outlet.ownerUid != ownerUid ||
          !outlet.isActive ||
          !uniqueBusinesses.contains(outlet.businessId)) {
        throw const AppException(
          'An outlet must belong to a selected business.',
        );
      }
    }
    final id = IdGenerator.create('EMP');
    final now = DateTime.now().toUtc();
    final fields = <String, dynamic>{
      'employeeId': id,
      'uid': '',
      'ownerUid': ownerUid,
      'name': cleanName,
      'email': '',
      'mobile': mobile.trim().isEmpty ? null : mobile.trim(),
      'employeeCode': employeeCode.trim().isEmpty ? null : employeeCode.trim(),
      'businessIds': uniqueBusinesses.toList(),
      'outletIds': uniqueOutlets.toList(),
      'roleIds': <String>[],
      'permissionIds': <String>[],
      'status': status,
      'loginEnabled': false,
      'employmentType': 'TEMPORARY',
      'createdAt': now,
      'updatedAt': now,
    };
    await firestore.createDocument(
      FirebaseConstants.employees,
      id,
      fields,
      idToken: token,
    );
    return EmployeeModel.fromData(id, fields);
  }

  Future<EmployeeModel> updateEmployee({
    required EmployeeModel employee,
    required String ownerUid,
    required String name,
    required String mobile,
    required String employeeCode,
    required List<String> businessIds,
    required List<String> outletIds,
    required List<String> roleIds,
    required List<String> permissionIds,
    required String status,
    required List<RoleModel> activeRoles,
    required String token,
  }) async {
    if (employee.ownerUid != ownerUid ||
        !const {'active', 'inactive'}.contains(status.toLowerCase())) {
      throw const AppException('This employee cannot be updated.');
    }
    if (employee.isTemporaryWorker) {
      final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleanName.isEmpty || businessIds.isEmpty || outletIds.isEmpty) {
        throw const AppException(
          'Enter a name and select a business and outlet.',
        );
      }
      final uniqueBusinesses = businessIds.toSet();
      final uniqueOutlets = outletIds.toSet();
      for (final id in uniqueBusinesses) {
        final business = await businesses.getBusinessById(id, token);
        if (business.ownerUid != ownerUid || !business.isActive) {
          throw const AppException('A selected business is unavailable.');
        }
      }
      for (final id in uniqueOutlets) {
        final outlet = await outlets.getOutletById(id, token);
        if (outlet.ownerUid != ownerUid ||
            !outlet.isActive ||
            !uniqueBusinesses.contains(outlet.businessId)) {
          throw const AppException(
            'An outlet must belong to a selected business.',
          );
        }
      }
      final normalizedCode = employeeCode.trim().toLowerCase();
      final duplicates = (await getEmployeesByOwner(ownerUid, token)).where(
        (candidate) =>
            candidate.employeeId != employee.employeeId &&
            normalizedCode.isNotEmpty &&
            (candidate.employeeCode ?? '').trim().toLowerCase() ==
                normalizedCode,
      );
      if (duplicates.isNotEmpty)
        throw const AppException('This employee code is already in use.');
      final fields = <String, dynamic>{
        'uid': '',
        'ownerUid': ownerUid,
        'name': cleanName,
        'email': '',
        'mobile': mobile.trim().isEmpty ? null : mobile.trim(),
        'employeeCode': employeeCode.trim().isEmpty
            ? null
            : employeeCode.trim(),
        'businessIds': uniqueBusinesses.toList(),
        'outletIds': uniqueOutlets.toList(),
        'roleIds': <String>[],
        'permissionIds': <String>[],
        'loginEnabled': false,
        'employmentType': 'TEMPORARY',
        'status': status.toLowerCase(),
        'updatedAt': DateTime.now().toUtc(),
      };
      await firestore.updateDocument(
        FirebaseConstants.employees,
        employee.employeeId,
        fields,
        idToken: token,
      );
      return EmployeeModel.fromData(employee.employeeId, {
        'employeeId': employee.employeeId,
        ...fields,
        'createdAt': null,
      });
    }
    await validateNewEmployee(
      ownerUid: ownerUid,
      name: name,
      email: employee.email,
      mobile: mobile,
      employeeCode: employeeCode,
      businessIds: businessIds,
      outletIds: outletIds,
      roleIds: roleIds,
      permissionIds: permissionIds,
      token: token,
      activeRoles: activeRoles,
      excludeUid: employee.uid,
    );
    final fields = <String, dynamic>{
      'uid': employee.uid,
      'ownerUid': ownerUid,
      'name': name.trim().replaceAll(RegExp(r'\s+'), ' '),
      'email': employee.email.trim().toLowerCase(),
      'mobile': mobile,
      'employeeCode': employeeCode.trim().isEmpty ? null : employeeCode.trim(),
      'businessIds': businessIds.toSet().toList(),
      'outletIds': outletIds.toSet().toList(),
      'roleIds': roleIds.toSet().toList(),
      'permissionIds': permissionIds.toSet().toList(),
      'status': status.toLowerCase(),
      'updatedAt': DateTime.now().toUtc(),
    };
    await firestore.updateDocument(
      FirebaseConstants.employees,
      employee.employeeId,
      fields,
      idToken: token,
    );
    return EmployeeModel.fromData(employee.employeeId, {
      'employeeId': employee.employeeId,
      ...fields,
      'createdAt': null,
    });
  }

  Future<void> updateEmployeeStatus({
    required EmployeeModel employee,
    required String ownerUid,
    required bool isActive,
    required String token,
  }) async {
    if (employee.ownerUid != ownerUid) {
      throw const AppException('This employee cannot be updated.');
    }
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((transaction) async {
      final employeeDocument = await transaction.get(
        FirebaseConstants.employees,
        employee.employeeId,
      );
      final userDocument = await transaction.get(
        FirebaseConstants.user,
        employee.uid,
      );
      if (!employeeDocument.exists ||
          employeeDocument.fields['uid'] != employee.uid ||
          employeeDocument.fields['ownerUid'] != ownerUid) {
        throw const AppException('This employee cannot be updated.');
      }
      if (!userDocument.exists ||
          userDocument.fields['uid'] != employee.uid ||
          userDocument.fields['accountType'] != 'employee') {
        throw const AppException('Employee login profile was not found.');
      }
      transaction.update(FirebaseConstants.employees, employee.employeeId, {
        'status': isActive ? 'active' : 'inactive',
        'updatedAt': now,
        'updatedBy': ownerUid,
      }, updateTime: employeeDocument.updateTime);
      transaction.update(FirebaseConstants.user, employee.uid, {
        'isActive': isActive,
        'updatedAt': now,
      }, updateTime: userDocument.updateTime);
    }, idToken: token);
  }

  Future<EmployeeModel?> getEmployeeByUid(String uid, String token) async {
    final docs = await firestore.queryEqual(
      FirebaseConstants.employees,
      'uid',
      uid,
      idToken: token,
    );
    if (docs.isEmpty) return null;
    final doc = docs.first;
    return EmployeeModel.fromData(
      (doc['name'] as String? ?? '').split('/').last,
      FirestoreRestService.decodeFields(doc['fields']),
    );
  }

  Future<List<BusinessModel>> getEmployeeBusinesses(
    EmployeeModel employee,
    String token,
  ) async {
    final authorized = <BusinessModel>[];
    for (final id in employee.businessIds) {
      try {
        final business = await businesses.getBusinessById(id, token);
        if (business.ownerUid == employee.ownerUid && business.isActive) {
          authorized.add(business);
        }
      } on AppException catch (error) {
        if (error.code != 'not-found') rethrow;
      }
    }
    return authorized;
  }

  Future<List<OutletModel>> getEmployeeOutlets(
    EmployeeModel employee,
    String businessId,
    String token,
  ) async {
    final assigned = employee.outletIds.toSet();
    final available = await outlets.getOutletsByBusinessId(
      businessId,
      token,
      tenantId: employee.ownerUid,
    );
    return available
        .where(
          (outlet) =>
              assigned.contains(outlet.outletId) &&
              outlet.ownerUid == employee.ownerUid,
        )
        .toList();
  }
}

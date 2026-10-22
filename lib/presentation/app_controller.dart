import 'dart:async';

import '../data/services/offline_firestore_service.dart';
import '../data/services/offline_face_recognition.dart';
import '../data/services/android_sqlite_face_vault_store.dart';
import '../data/services/face_biometric_vault.dart';
import '../data/services/sface_embedding_model.dart';
import '../data/services/face_capture_processor.dart';
import '../data/services/geofence_service.dart';
import '../data/services/face_liveness_service.dart';
import '../data/services/device_registration_service.dart';
import '../data/repositories/biometric_storage_repository.dart';
import '../data/sync/sync_engine.dart';
import '../data/models/product_attribute.dart';
import '../data/models/reclassification_plan.dart';
import '../data/models/resolved_product_template.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config/environment_config.dart';
import '../core/errors/app_exception.dart';
import '../core/permissions/permission_catalog.dart';
import '../core/permissions/permission_id_matcher.dart';
import '../core/utils/validators.dart';
import '../data/models/app_config_model.dart';
import '../data/models/auth_session_model.dart';
import '../data/models/business_model.dart';
import '../data/models/business_sub_type_model.dart';
import '../data/models/business_type_model.dart';
import '../data/models/employee_model.dart';
import '../data/models/outlet_model.dart';
import '../data/models/permission_model.dart';
import '../data/models/product_variant_model.dart';
import '../data/models/product_model.dart';
import '../data/models/product_master_value.dart';
import '../data/models/central_product_master.dart';
import '../data/models/purchase_bill_model.dart';
import '../data/models/purchase_correction_model.dart';
import '../data/models/role_model.dart';
import '../data/models/supplier_model.dart';
import '../data/models/sales_invoice_model.dart';
import '../data/models/storage_location_model.dart';
import '../data/models/user_model.dart';
import '../data/repositories/billing_repository.dart';
import '../data/repositories/customer_repository.dart';
import '../data/repositories/expense_repository.dart';
import '../data/repositories/staff_salary_repository.dart';
import '../data/repositories/staff_attendance_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/business_repository.dart';
import '../data/repositories/business_sub_type_repository.dart';
import '../data/repositories/business_type_repository.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/employee_repository.dart';
import '../data/repositories/outlet_repository.dart';
import '../data/repositories/permission_repository.dart';
import '../data/repositories/purchase_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/role_repository.dart';
import '../data/repositories/supplier_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/models/stock_transaction_audit_model.dart';
import '../data/repositories/sales_repository.dart';
import '../domain/services/storage_service.dart';
import '../data/repositories/user_repository.dart';
import '../data/services/app_config_service.dart';
import '../data/services/gst_verification_service.dart';
import '../data/services/firestore_rest_service.dart';
import '../data/catalogue/catalogue_contract.dart';
import '../data/catalogue/catalogue_readiness.dart';
import '../data/catalogue/system_catalogue_metadata.dart';
import '../domain/entities/app_context.dart';
import '../domain/entities/dashboard_summary.dart';

part 'staff_salary/face_attendance_controller.dart';

enum AppStatus {
  loading,
  login,
  maintenance,
  error,
  businessSelector,
  createBusiness,
  outletSelector,
  createOutlet,
  dashboard,
  denied,
}

({String businessTypeId, String businessSubTypeId})
resolveCentralProductSearchScope({
  required String businessId,
  required String businessTypeId,
  required String businessSubTypeId,
}) {
  if (businessId == 'BUS-001' &&
      businessTypeId == 'Hardware' &&
      businessSubTypeId == 'Hardware Outlet') {
    return (businessTypeId: 'BT-HARDWARE', businessSubTypeId: 'BST-PAINTS');
  }
  return (businessTypeId: businessTypeId, businessSubTypeId: businessSubTypeId);
}

class AppController extends ChangeNotifier {
  AppController(
    this.config,
    this.auth,
    this.users,
    this.businessesRepository,
    this.dashboardRepository,
    this.outletsRepository,
    this.employeesRepository,
    this.rolesRepository,
    this.permissionsRepository,
    this.supplierRepository,
    this.purchaseRepository,
    this.productRepository,
    this.businessTypesRepository,
    this.businessSubTypesRepository,
    this.gstVerificationService,
    this.storageService, {
    this.offline,
    this.sync,
    this.billingRepository,
    this.customerRepository,
    this.expenseRepository,
    this.staffSalaryRepository,
    this.settingsRepository,
    this.inventoryRepositoryOverride,
  }) {
    sync?.addListener(_syncStateChanged);
    _syncSubscription = sync?.changes.stream.listen((_) => _refreshAfterSync());
  }
  final OfflineFirestoreService? offline;
  final SyncEngine? sync;
  final BillingRepository? billingRepository;
  final CustomerRepository? customerRepository;
  final ExpenseRepository? expenseRepository;
  final StaffSalaryRepository? staffSalaryRepository;
  final SettingsRepository? settingsRepository;
  final InventoryRepository? inventoryRepositoryOverride;
  InventoryRepository get inventoryRepository =>
      inventoryRepositoryOverride ??
      InventoryRepository(
        firestore: offline ?? productRepository.firestore,
        transactions: productRepository.transactions,
      );
  String? get idToken => auth.currentSession?.idToken;
  StreamSubscription<void>? _syncSubscription;
  bool _refreshingSync = false;
  OfflineFaceRecognition? _faceRecognition;
  OfflineFaceRecognition get faceRecognition =>
      _faceRecognition ??
      const OfflineFaceRecognition(
        model: SFaceEmbeddingModel(),
        pad: UnavailablePresentationAttackDetector(),
      );
  set faceRecognition(OfflineFaceRecognition value) => _faceRecognition = value;

  /// Safe support diagnostics. In release builds, only an authenticated owner
  /// may inspect the runtime project and catalogue metadata.
  Future<Map<String, Object?>> runtimeDiagnostics() async {
    if (!kDebugMode && appContext?.accountType != 'owner') {
      throw const AppException(
        'Runtime diagnostics are available to authorized support only.',
        code: 'permission-denied',
      );
    }
    final result = <String, Object?>{
      ...EnvironmentConfig.diagnostics(),
      'runtimeIdentityStatus': EnvironmentConfig.projectId.isEmpty
          ? 'UNVERIFIED'
          : 'COMPILED_DEFINE',
      'platform': defaultTargetPlatform.name,
      'buildMode': kDebugMode
          ? 'debug'
          : kProfileMode
          ? 'profile'
          : 'release',
      'catalogueSchemaRevision': CatalogueContract.schemaRevision,
      'catalogueCompilerRevision': SystemCatalogueMetadata.revision,
      'syncState': sync?.state.name ?? 'unavailable',
      'syncError': _safeDiagnosticError(sync?.error),
      'catalogueReadiness': 'NOT_INITIALIZED',
    };
    try {
      final cached = await offline?.readCatalogueDiagnostics();
      if (cached == null) return result;
      final report = CatalogueReadiness.validateInstalled(cached.documents);
      final releases =
          CatalogueContract.decode(
                cached.documents,
              )['product_catalogue_releases']
              ?.where(CatalogueContract.active)
              .toList() ??
          const [];
      final release = releases.length == 1 ? releases.single : null;
      final hasCatalogueRows = cached.documents.values.any(
        (rows) => rows.isNotEmpty,
      );
      result.addAll({
        'catalogueReadiness': report.isReady
            ? (sync?.state == SyncState.offline
                  ? 'OFFLINE_VALID_CACHE'
                  : 'READY')
            : release == null
            ? hasCatalogueRows
                  ? 'INVALID_CACHE'
                  : 'NOT_INITIALIZED'
            : 'INVALID_CACHE',
        'catalogueReleaseId': release?['releaseId'] ?? release?['catalogueId'],
        'catalogueReleaseVersion': report.releaseVersion,
        'catalogueFingerprint': release?['catalogueFingerprint'],
        'catalogueDiagnostics': report.errors,
        'catalogueLastSyncError': _safeDiagnosticError(
          cached.queries
              .map((row) => row['lastError'])
              .whereType<String>()
              .firstOrNull,
        ),
        'catalogueQueryStates': [
          for (final row in cached.queries)
            {
              'collection': row['collectionName'],
              'lastSyncedAt': row['lastSyncedAt'],
              'lastAttemptAt': row['lastAttemptAt'],
              'releaseToken': row['catalogueVersion'],
              'active': row['active'],
              'hasError': (row['lastError'] as String?)?.isNotEmpty == true,
            },
        ],
      });
    } catch (_) {
      result['catalogueReadiness'] = 'FAILED';
      result['catalogueDiagnostics'] = const [
        'Unable to read local catalogue diagnostics.',
      ];
    }
    return result;
  }

  void retryCatalogueSynchronization() {
    sync?.schedule(pull: true, reason: 'CATALOGUE_RETRY');
  }

  static String? _safeDiagnosticError(String? error) {
    if (error == null || error.isEmpty) return null;
    return EnvironmentConfig.redactDiagnosticText(error);
  }

  bool _workspaceMatches(AppContext? context) =>
      context?.uid == appContext?.uid &&
      context?.ownerUid == appContext?.ownerUid &&
      context?.businessId == appContext?.businessId &&
      context?.outletId == appContext?.outletId;
  void _syncStateChanged() => notifyListeners();
  void _startupLog(String message) {
    if (kDebugMode) {
      debugPrint('[startup] $message');
    }
  }

  Future<void> _refreshAfterSync() async {
    if (_refreshingSync ||
        appContext?.businessId == null ||
        status != AppStatus.dashboard) {
      return;
    }
    _refreshingSync = true;
    try {
      if (!await _refreshCachedAuthorization()) return;
      if (canManageProducts()) {
        await loadProductMasters();
        await loadProducts();
      }
      if (canManageSuppliers()) await loadSuppliers();
      if (canViewStorage()) await loadStorageLocations();
      if (appContext?.outletId != null) {
        await refreshDashboard();
        if (canManagePurchases()) await loadPurchases();
      }
    } finally {
      _refreshingSync = false;
    }
  }

  Future<void> _setSyncScope({
    required String tenant,
    required String business,
    String? outlet,
  }) async {
    final permissions = appContext?.permissions ?? [];
    final owner = appContext?.accountType == 'owner';
    await offline?.setScope(
      tenant: tenant,
      business: business,
      outlet: outlet,
      products: canManageProducts(),
      productCreation: canCreateProducts(),
      suppliers: canManageSuppliers(),
      purchases: canManagePurchases(),
      storage: canViewStorage(),
      sales:
          owner ||
          PermissionCatalog.allows('sales', permissions) ||
          PermissionCatalog.allows('billing', permissions),
      customers: owner || PermissionCatalog.allows('customers', permissions),
      salaryAccess: canViewStaffSalary(),
      attendanceAccess: canViewStaffAttendance(),
      staffKhataAccess: canChargeStaffKhata(),
      salaryEmployeeId: owner ? null : appContext?.employeeId,
    );
  }

  Future<bool> _refreshCachedAuthorization() async {
    final context = appContext;
    final session = auth.currentSession;
    if (context == null || session == null) return false;
    try {
      final profile = await users.load(
        session.uid,
        session.email,
        session.idToken,
      );
      if (!profile.isActive || profile.accountType != context.accountType) {
        throw const AppException(
          'Your account access changed. Please sign in again.',
        );
      }
      if (context.accountType == 'employee') {
        final updatedEmployee = await employeesRepository.getEmployeeByUid(
          session.uid,
          session.idToken,
        );
        if (updatedEmployee == null ||
            !updatedEmployee.isActive ||
            updatedEmployee.ownerUid != context.ownerUid ||
            !updatedEmployee.businessIds.contains(context.businessId) ||
            context.outletId != null &&
                !updatedEmployee.outletIds.contains(context.outletId)) {
          throw const AppException(
            'Your access to this workspace has changed.',
          );
        }
        final roleIds = updatedEmployee.roleIds.isNotEmpty
            ? updatedEmployee.roleIds
            : [if (profile.roleId != null) profile.roleId!];
        if (roleIds.isEmpty) {
          throw const AppException('An active employee role is required.');
        }
        final assignedRoles = await rolesRepository.getRolesByIds(
          roleIds,
          session.idToken,
        );
        final definitions = await permissionsRepository.getActivePermissions(
          session.idToken,
        );
        final activeIds = definitions.map((p) => p.permissionId).toSet();
        final grants = {
          ...assignedRoles.expand((r) => r.permissions),
          ...updatedEmployee.permissionIds,
        };
        final effective = activeIds.isEmpty
            ? grants.toList()
            : grants
                  .where(
                    (id) => activeIds.any(
                      (active) => PermissionIdMatcher.matches(id, active),
                    ),
                  )
                  .toList();
        if (!_workspaceMatches(context)) return false;
        employee = updatedEmployee;
        role = assignedRoles.first;
        appContext = AppContext(
          uid: context.uid,
          accountType: context.accountType,
          ownerUid: context.ownerUid,
          employeeId: updatedEmployee.employeeId,
          roleId: role!.roleId,
          businessId: context.businessId,
          outletId: context.outletId,
          permissions: effective,
        );
      }
      final business = await businessesRepository.getBusinessByIdOrNull(
        context.businessId!,
        session.idToken,
      );
      if (business == null ||
          !business.isActive ||
          business.ownerUid != context.ownerUid) {
        throw const AppException('This business is no longer available.');
      }
      if (context.outletId != null) {
        final outlet = await outletsRepository.getOutletById(
          context.outletId!,
          session.idToken,
        );
        if (!outlet.isActive ||
            outlet.businessId != context.businessId ||
            outlet.tenantId != context.ownerUid) {
          throw const AppException('This outlet is no longer available.');
        }
      }
      if (!_workspaceMatches(context)) return false;
      user = profile;
      return true;
    } catch (e) {
      if (_workspaceMatches(context)) {
        appContext = null;
        await _deny(
          e is AppException
              ? e.message
              : 'Unable to validate workspace access.',
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    sync?.removeListener(_syncStateChanged);
    unawaited(_syncSubscription?.cancel());
    super.dispose();
  }

  final AppConfigService config;
  final AuthRepository auth;
  final UserRepository users;
  final BusinessRepository businessesRepository;
  final DashboardRepository dashboardRepository;
  final OutletRepository outletsRepository;
  final EmployeeRepository employeesRepository;
  final RoleRepository rolesRepository;
  final PermissionRepository permissionsRepository;
  final SupplierRepository supplierRepository;
  final PurchaseRepository purchaseRepository;
  final ProductRepository productRepository;
  final BusinessTypeRepository businessTypesRepository;
  final BusinessSubTypeRepository businessSubTypesRepository;
  final GSTVerificationService gstVerificationService;
  final StorageService storageService;

  SalesRepository get salesRepository {
    final source = offline;
    if (source == null) {
      throw const AppException('Offline sales storage is unavailable.');
    }
    return SalesRepository(source);
  }

  bool canViewInventory() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('inventory.view', context.permissions) ||
            PermissionCatalog.allows('inventory', context.permissions));
  }

  bool canAddOpeningStock() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows(
              'inventory.opening_stock',
              context.permissions,
            ));
  }

  bool canAdjustStock() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('inventory.adjust', context.permissions));
  }

  bool canApproveAdjustment() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows(
              'inventory.approve_adjustment',
              context.permissions,
            ));
  }

  bool canManageSales() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('sales', context.permissions) ||
            PermissionCatalog.allows('billing', context.permissions));
  }

  Future<List<ProductVariantModel>> loadSalesVariants() async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context == null ||
        context.businessId == null ||
        context.outletId == null ||
        !canManageSales()) {
      throw const AppException(
        'Select an Outlet and ensure you have Sales access.',
      );
    }
    final products = await productRepository.getOutletProducts(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      token: session.idToken,
    );
    return products
        .expand((product) => product.variants)
        .where((variant) => variant.status.toUpperCase() == 'ACTIVE')
        .toList();
  }

  Future<List<SalesBatchOption>> loadSalesBatches(
    String productId,
    String variantId,
  ) async {
    final context = appContext;
    if (context == null ||
        context.businessId == null ||
        context.outletId == null) {
      return const [];
    }
    return salesRepository.listBatches(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      productId: productId,
      variantId: variantId,
    );
  }

  Future<List<Map<String, dynamic>>> loadSalesCustomers() async {
    final context = appContext;
    if (context == null ||
        context.businessId == null ||
        context.outletId == null) {
      return const [];
    }
    return salesRepository.listLocalCustomers(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
    );
  }

  Future<List<EmployeeModel>> loadStaffKhataEmployees() async {
    final context = appContext;
    if (context == null ||
        (!canChargeStaffKhata() && !canViewStaffAttendance()) ||
        context.businessId == null ||
        context.outletId == null) {
      return const [];
    }
    final documents =
        await offline?.queryDocuments(
          collection: 'employees',
          filters: [FirestoreFilter('ownerUid', 'EQUAL', context.ownerUid)],
        ) ??
        const <Map<String, dynamic>>[];
    return documents
        .map(
          (doc) => EmployeeModel.fromData(
            (doc['name'] as String? ?? '').split('/').last,
            FirestoreRestService.decodeFields(doc['fields']),
          ),
        )
        .where(
          (employee) =>
              employee.isActive &&
              employee.businessIds.contains(context.businessId) &&
              employee.outletIds.contains(context.outletId),
        )
        .toList();
  }

  StaffAttendanceRepository get staffAttendanceRepository {
    final source = offline;
    if (source == null) {
      throw const AppException('Offline staff storage is unavailable.');
    }
    return StaffAttendanceRepository(source, source);
  }

  Future<String> saveStaffAttendance({
    required String employeeId,
    required DateTime workDate,
    required String status,
    DateTime? checkIn,
    DateTime? checkOut,
    bool includeOffDayAsPaidWork = false,
    String? earlyCheckoutReason,
  }) async {
    if (!canManageStaffAttendance()) {
      throw const AppException('Attendance permission is required.');
    }
    final context = appContext, session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.businessId == null ||
        context.outletId == null) {
      throw const AppException('Select an active Business and Outlet.');
    }
    return staffAttendanceRepository.recordManualAttendance(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      employeeId: employeeId,
      workDate: workDate,
      status: status,
      recordedBy: context.employeeId ?? context.uid,
      checkIn: checkIn,
      checkOut: checkOut,
      includeOffDayAsPaidWork: includeOffDayAsPaidWork,
      earlyCheckoutReason: earlyCheckoutReason,
      token: session.idToken,
    );
  }

  Future<void> approveStaffAttendance(
    String attendanceId, {
    int standardShiftMinutes = 480,
    int halfDayPayableUnitsMilli = 500,
    int? overtimeRatePaisePerHour,
    int overtimeMultiplierBasisPoints = 10000,
  }) async {
    if (!canApproveStaffAttendance()) {
      throw const AppException('Attendance approval permission is required.');
    }
    final context = appContext, session = await _getUsableSession();
    if (context == null || session == null || context.businessId == null) {
      throw const AppException('Select an active Business.');
    }
    await staffAttendanceRepository.approveAttendance(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      attendanceId: attendanceId,
      approvedBy: context.employeeId ?? context.uid,
      standardShiftMinutes: standardShiftMinutes,
      halfDayPayableUnitsMilli: halfDayPayableUnitsMilli,
      overtimeRatePaisePerHour: overtimeRatePaisePerHour,
      overtimeMultiplierBasisPoints: overtimeMultiplierBasisPoints,
      token: session.idToken,
    );
    await refreshPendingAttendanceCount();
  }

  Future<int> approveAllStaffAttendance(
    List<String> attendanceIds, {
    int standardShiftMinutes = 480,
    int halfDayPayableUnitsMilli = 500,
    int? overtimeRatePaisePerHour,
    int overtimeMultiplierBasisPoints = 10000,
  }) async {
    var count = 0;
    for (final id in attendanceIds) {
      await approveStaffAttendance(
        id,
        standardShiftMinutes: standardShiftMinutes,
        halfDayPayableUnitsMilli: halfDayPayableUnitsMilli,
        overtimeRatePaisePerHour: overtimeRatePaisePerHour,
        overtimeMultiplierBasisPoints: overtimeMultiplierBasisPoints,
      );
      count++;
    }
    return count;
  }

  int pendingAttendanceCount = 0;
  bool pendingAttendanceLoading = false;

  Future<void> refreshPendingAttendanceCount() async {
    if (pendingAttendanceLoading) return;
    final context = appContext;
    if (context == null ||
        context.businessId == null ||
        !canViewStaffAttendance()) {
      if (pendingAttendanceCount != 0) {
        pendingAttendanceCount = 0;
        notifyListeners();
      }
      return;
    }
    try {
      pendingAttendanceLoading = true;
      final session = await _getUsableSession();
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, 1);
      final through = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final rows = await staffAttendanceRepository.listAttendance(
        tenantId: context.ownerUid,
        businessId: context.businessId!,
        from: from,
        through: through,
        outletId: null,
        token: session?.idToken,
      );
      final newCount = rows
          .where((r) => r['approvalStatus'] == 'PENDING')
          .length;
      if (pendingAttendanceCount != newCount) {
        pendingAttendanceCount = newCount;
        notifyListeners();
      }
    } catch (_) {
      // Non-blocking background count
    } finally {
      pendingAttendanceLoading = false;
    }
  }

  Future<List<Map<String, dynamic>>> loadStaffAttendance({
    required DateTime from,
    required DateTime through,
    String? employeeId,
    String? outletId,
    bool allOutlets = false,
  }) async {
    if (!canViewStaffAttendance()) {
      throw const AppException('Attendance permission is required.');
    }
    final context = appContext;
    if (context == null || context.businessId == null) return const [];
    final session = await _getUsableSession();
    final effectiveOutlet = allOutlets ? null : (outletId ?? context.outletId);
    final rows = await staffAttendanceRepository.listAttendance(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      from: from,
      through: through,
      employeeId: employeeId,
      outletId: effectiveOutlet,
      token: session?.idToken,
    );
    if (effectiveOutlet == null) {
      final newCount = rows
          .where((r) => r['approvalStatus'] == 'PENDING')
          .length;
      if (pendingAttendanceCount != newCount) {
        pendingAttendanceCount = newCount;
        notifyListeners();
      }
    }
    return rows;
  }

  Future<String> postSalesInvoice({
    required String invoiceId,
    required DateTime invoiceDate,
    required String? customerId,
    required String? customerName,
    String? chargeToEmployeeId,
    required List<SalesInvoiceLine> lines,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context == null ||
        context.businessId == null ||
        context.outletId == null ||
        !canManageSales() ||
        (chargeToEmployeeId != null && !canChargeStaffKhata())) {
      throw const AppException(
        'Select an Outlet and ensure you have Sales access.',
      );
    }
    return salesRepository.postInvoice(
      invoiceId: invoiceId,
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      actorUid: context.uid,
      invoiceDate: invoiceDate,
      customerId: customerId,
      customerName: customerName,
      chargeToEmployeeId: chargeToEmployeeId,
      lines: lines,
      token: session.idToken,
    );
  }

  Future<String> recordStaffPurchasePayment({
    required String invoiceId,
    required String employeeId,
    required int amountPaise,
    required String paymentMode,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    final repository = staffSalaryRepository;
    if (session == null ||
        context == null ||
        context.businessId == null ||
        context.outletId == null ||
        repository == null ||
        !canChargeStaffKhata() ||
        !canManageSales()) {
      throw const AppException('Staff Khata payment access is unavailable.');
    }
    final requestId =
        'SP-${context.uid}-${DateTime.now().microsecondsSinceEpoch}';
    return repository.recordStaffPurchasePayment(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      employeeId: employeeId,
      invoiceId: invoiceId,
      amountPaise: amountPaise,
      paymentMode: paymentMode,
      requestId: requestId,
      recordedBy: context.uid,
      token: session.idToken,
    );
  }

  AppStatus status = AppStatus.loading;
  String error = '';
  AppConfigModel? appConfig;
  UserModel? user;
  EmployeeModel? employee;
  RoleModel? role;
  AppContext? appContext;
  DashboardSummary? dashboardSummary;
  bool dashboardLoading = false;
  String? dashboardError;
  List<BusinessModel> businesses = [];
  List<OutletModel> outlets = [];
  List<BusinessTypeModel> businessTypes = [];
  List<BusinessSubTypeModel> businessSubTypes = [];
  bool businessTypesLoading = false;
  bool businessSubTypesLoading = false;
  bool businessSaving = false;
  bool outletSaving = false;
  bool employeesLoading = false;
  bool employeeMastersLoading = false;
  bool employeeOutletsLoading = false;
  bool employeeSaving = false;
  String? employeesError, employeeMastersError, employeeOutletError;
  List<EmployeeModel> employees = [];
  List<RoleModel> activeRoles = [];
  List<PermissionModel> activePermissions = [];
  List<SupplierModel> suppliers = [];
  List<SupplierModel> tenantSuppliers = [];
  bool suppliersLoading = false;
  bool supplierSaving = false;
  String? suppliersError;
  List<StorageLocationModel> storageLocations = [];
  int _storageRequest = 0;
  bool storageLoading = false;
  bool storageSaving = false;
  String? storageError;
  List<ProductVariantModel> purchaseProducts = [];
  Map<String, int> productStock = {};
  List<ProductModel> products = [];
  final Map<String, List<ProductMasterValue>> productMasterValues = {};
  bool productMastersLoading = false;
  String? productMastersError;
  bool productsLoading = false;
  bool productSaving = false;
  String? productsError;
  List<PurchaseBillModel> purchaseBills = [];
  bool purchasesLoading = false;
  bool purchaseSaving = false;
  String? purchasesError;
  List<OutletModel> employeeOutlets = [];
  int _employeeOutletRequest = 0;
  String? businessTypesError;
  String? businessSubTypesError;
  GSTVerificationResult? gstVerificationResult;

  Locale _currentLocale = const Locale('en');
  Locale get currentLocale => _currentLocale;

  Future<void> setLocale(Locale locale) async {
    if (_currentLocale == locale) return;
    _currentLocale = locale;
    notifyListeners();
    try {
      await auth.saveLanguage(locale.languageCode);
    } catch (_) {}
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final code = await auth.readLanguage();
      if (code != null && (code == 'en' || code == 'hi' || code == 'bn')) {
        _currentLocale = Locale(code);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> start() async {
    _startupLog('AppController.start: loading');
    status = AppStatus.loading;
    await _loadSavedLanguage();
    notifyListeners();
    try {
      if (!EnvironmentConfig.isConfigured) {
        throw const AppException('Application configuration is incomplete.');
      }
      _startupLog('Loading app configuration');
      appConfig = await config.load();
      _startupLog('App configuration loaded');
      if (!appConfig!.isActive) {
        status = AppStatus.maintenance;
        _startupLog('Startup status: maintenance');
        notifyListeners();
        return;
      }
      _startupLog('Authentication restore started');
      final session = await auth.restore();
      _startupLog(
        'Authentication restore completed: ${session == null ? 'no session' : 'session restored'}',
      );
      if (session == null) {
        status = AppStatus.login;
        _startupLog('Startup status: login');
        notifyListeners();
        return;
      }
      await _authorize(session);
    } catch (e) {
      error = e is AppException ? e.message : 'Unable to load application settings. Check your connection and retry.';
      status = AppStatus.error;
      _startupLog(
        'Startup status: error (${e.runtimeType}${e is AppException ? ', code=${e.code}' : ''})',
      );
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  Future<void> signIn(
    String email,
    String password, {
    required bool remember,
  }) async {
    status = AppStatus.loading;
    error = '';
    notifyListeners();
    try {
      final session = await auth.signIn(email, password, remember: remember);
      if (kDebugMode) {}
      await _authorize(session);
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Something went wrong. Please try again.';
      status = AppStatus.login;
      notifyListeners();
    }
  }

  Future<void> _authorize(AuthSession session) async {
    try {
      _startupLog('Account database activation started');
      await offline?.activate(session.uid);
      _startupLog('Account database opened and sync attached');
      _startupLog('User profile restore started');
      user = await users.load(session.uid, session.email, session.idToken);
      _startupLog('User profile restore completed');
      if (user!.uid != session.uid) {
        throw const AppException(
          'The user profile does not match this account.',
        );
      }
      if (!user!.isActive) {
        throw const AppException(
          'This account is inactive. Contact your administrator.',
        );
      }

      final saved = await auth.readContext();
      _startupLog('Saved business/outlet context restored');
      employee = null;
      role = null;
      if (user!.accountType == 'owner') {
        appContext = AppContext(
          uid: session.uid,
          accountType: 'owner',
          ownerUid: session.uid,
          roleId: user!.roleId,
          permissions: const ['*'],
        );
        businesses = await businessesRepository.getBusinessesByOwnerUid(
          session.uid,
          session.idToken,
        );
        _startupLog(
          'Business restore completed: ${businesses.length} business(es)',
        );
      } else if (user!.accountType == 'employee') {
        employee = await employeesRepository.getEmployeeByUid(
          session.uid,
          session.idToken,
        );
        if (employee == null || employee!.uid != session.uid) {
          throw const AppException(
            'Your employee profile is not configured. Contact your owner.',
          );
        }
        if (!employee!.isActive) {
          throw const AppException(
            'Your employee account is inactive. Contact your owner.',
          );
        }
        final roleIds = employee!.roleIds.isNotEmpty
            ? employee!.roleIds
            : [if (user!.roleId != null) user!.roleId!];
        if (roleIds.isEmpty) {
          throw const AppException(
            'Your employee role is not configured. Contact your owner.',
          );
        }
        final assignedRoles = await rolesRepository.getRolesByIds(
          roleIds,
          session.idToken,
        );
        role = assignedRoles.first;
        final rolePermissions = assignedRoles
            .expand((assignedRole) => assignedRole.permissions)
            .toSet();
        final permissionDefinitions = await permissionsRepository
            .getActivePermissions(session.idToken);
        final activePermissionIds =
            permissionDefinitions
                .map((permission) => permission.permissionId)
                .toSet()
              ..addAll(PermissionCatalog.staffSalaryPermissions);
        // Roles supply their default permissions; explicitly assigned
        // employee permissions are additive grants.
        final effectivePermissionIds = {
          ...rolePermissions,
          ...employee!.permissionIds,
        }.toList();
        final effectivePermissions = activePermissionIds.isEmpty
            ? effectivePermissionIds.toSet().toList()
            : effectivePermissionIds
                  .where(
                    (id) => activePermissionIds.any(
                      (activeId) => PermissionIdMatcher.matches(id, activeId),
                    ),
                  )
                  .toSet()
                  .toList();
        appContext = AppContext(
          uid: session.uid,
          accountType: 'employee',
          ownerUid: employee!.ownerUid,
          employeeId: employee!.employeeId,
          roleId: role!.roleId,
          permissions: effectivePermissions,
        );
        businesses = await employeesRepository.getEmployeeBusinesses(
          employee!,
          session.idToken,
        );
        if (businesses.isEmpty) {
          throw const AppException(
            'No active businesses are assigned to your account.',
          );
        }
      } else {
        throw const AppException(
          'This account type is not authorized to use NubiBill.',
        );
      }

      if (businesses.isEmpty) {
        if (user!.accountType == 'owner') {
          await openCreateBusiness();
          return;
        }
        throw const AppException(
          'No active businesses are assigned to your account.',
        );
      }

      final savedBusiness = businesses.where(
        (b) => b.businessId == saved.businessId,
      );
      if (savedBusiness.isNotEmpty) {
        await selectBusiness(
          savedBusiness.first.businessId,
          preferredOutletId: saved.outletId,
        );
      } else if (businesses.length == 1) {
        await selectBusiness(businesses.single.businessId);
      } else {
        status = AppStatus.businessSelector;
        notifyListeners();
      }
    } catch (e) {
      _startupLog(
        'Authorization failed (${e.runtimeType}${e is AppException ? ', code=${e.code}' : ''})',
      );
      Object failure = e;
      try {
        await _clearSession();
      } catch (storageError) {
        failure = storageError;
      }
      user = null;
      employee = null;
      appContext = null;
      error = failure is AppException
          ? failure.message
          : 'Unable to validate your account.';
      status = AppStatus.denied;
      _startupLog('Startup status: denied');
      notifyListeners();
    }
  }

  Future<void> selectBusiness(
    String businessId, {
    String? preferredOutletId,
    bool businessLevelContext = false,
  }) async {
    final session = await _getUsableSession();
    final selected = businesses.where(
      (business) => business.businessId == businessId,
    );
    if (session == null || selected.isEmpty) {
      error = 'That business is not available to this account.';
      status = AppStatus.denied;
      notifyListeners();
      return;
    }
    final business = selected.first;
    if (user?.accountType == 'owner' && business.ownerUid != user?.uid) {
      return _deny('You are not authorized to access this business.');
    }
    appContext = appContext!.copyWith(
      businessId: businessId,
      clearOutlet: true,
    );
    _startupLog('Business selected; sync scope registration started');
    productStock = {};
    placementBackfillNotice = null;
    products = [];
    productMasterValues.clear();
    purchaseProducts = [];
    suppliers = [];
    tenantSuppliers = [];
    purchaseBills = [];
    await _setSyncScope(tenant: business.ownerUid, business: businessId);
    _startupLog('Business sync scope registration completed');
    outlets = [];
    storageLocations = [];
    _storageRequest++;
    storageError = null;
    storageLoading = false;
    dashboardSummary = null;
    dashboardError = null;
    if (!await _saveContext(businessId: businessId)) {
      return _deny('Unable to save workspace context.');
    }
    _startupLog('Business/outlet context saved; loading authorized outlets');
    status = AppStatus.loading;
    notifyListeners();
    try {
      outlets = user?.accountType == 'employee'
          ? await employeesRepository.getEmployeeOutlets(
              employee!,
              businessId,
              session.idToken,
            )
          : await outletsRepository.getOutletsByBusinessId(
              businessId,
              session.idToken,
              tenantId: business.ownerUid,
            );
      _startupLog('Outlet restore completed: ${outlets.length} outlet(s)');
      if (outlets.isEmpty) {
        if (user?.accountType == 'owner' || canViewStorage()) {
          // Business-level modules such as Godown Management do not need an
          // Outlet. Allow authorized users to configure the Business first.
          appContext = appContext!.copyWith(clearOutlet: true);
          status = AppStatus.dashboard;
          _startupLog('Startup status: dashboard (business-level workspace)');
          error = '';
          notifyListeners();
          return;
        }
        await _deny(
          'No outlets are assigned to your account for this business.',
        );
        return;
      }
      final preferred = outlets.where(
        (outlet) => outlet.outletId == preferredOutletId,
      );
      if (preferred.isNotEmpty) {
        await selectOutlet(preferred.first.outletId);
      } else if (outlets.length == 1) {
        await selectOutlet(outlets.single.outletId);
      } else if (businessLevelContext) {
        status = AppStatus.dashboard;
        _startupLog('Startup status: dashboard (outlet selected)');
        notifyListeners();
      } else {
        status = AppStatus.outletSelector;
        notifyListeners();
      }
    } catch (e) {
      await _deny(
        e is AppException ? e.message : 'Unable to load authorized outlets.',
      );
    }
  }

  Future<void> selectOutlet(String outletId) async {
    final session = await _getUsableSession();
    final selected = outlets.where((outlet) => outlet.outletId == outletId);
    if (session == null ||
        selected.isEmpty ||
        selected.first.businessId != appContext?.businessId ||
        selected.first.tenantId != appContext?.ownerUid ||
        !selected.first.isActive) {
      return _deny('That outlet is not available to this account.');
    }
    final outlet = selected.first;
    if (outlet.ownerUid != appContext?.ownerUid) {
      return _deny('You are not authorized to access this outlet.');
    }
    appContext = appContext!.copyWith(outletId: outletId);
    // Never show the previous outlet's products or stock for the new outlet.
    products = [];
    productStock = {};
    productsError = null;
    await _setSyncScope(
      tenant: appContext!.ownerUid,
      business: appContext!.businessId!,
      outlet: outletId,
    );
    dashboardSummary = null;
    dashboardError = null;
    if (!await _saveContext(
      businessId: appContext!.businessId,
      outletId: outletId,
    )) {
      return _deny('Unable to save workspace context.');
    }
    status = AppStatus.dashboard;
    error = '';
    notifyListeners();
    if (canManageProducts()) await loadProducts();
    await refreshDashboard();
    if (canManagePurchases()) await loadPurchases();
  }

  OutletModel? get currentOutlet {
    final outletId = appContext?.outletId;
    for (final outlet in outlets) {
      if (outlet.outletId == outletId) return outlet;
    }
    return null;
  }

  BusinessModel? get currentBusiness {
    final businessId = appContext?.businessId;
    for (final b in businesses) {
      if (b.businessId == businessId) return b;
    }
    return businesses.firstOrNull;
  }

  String get currentBusinessName => currentBusiness?.businessName ?? 'Suman Enterprise';

  bool canViewStaffSalary() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('SALARY_VIEW', context.permissions) ||
            PermissionCatalog.allows('SALARY_MANAGE', context.permissions) ||
            PermissionCatalog.allows('SALARY_APPROVE', context.permissions) ||
            PermissionCatalog.allows('SALARY_PAY', context.permissions) ||
            PermissionCatalog.allows('SALARY_REPORT', context.permissions));
  }

  bool canManageStaffAttendance() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('ATTENDANCE_MANAGE', context.permissions));
  }

  bool canEnrollBiometricAttendance() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('BIOMETRIC_ENROLL', context.permissions));
  }

  bool canRevokeBiometricAttendance() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('BIOMETRIC_REVOKE', context.permissions));
  }

  Future<String> recordFaceAttendanceCheckIn({
    required FaceAttendanceVerification verification,
    required String employeeId,
    required DateTime workDate,
    required DateTime occurredAt,
    required String timeZoneId,
    required String kioskDeviceId,
    required String modelVersion,
    required String livenessVersion,
  }) => _recordFaceAttendanceKioskEvent(
    verification: verification,
    checkOut: false,
    employeeId: employeeId,
    workDate: workDate,
    occurredAt: occurredAt,
    timeZoneId: timeZoneId,
    kioskDeviceId: kioskDeviceId,
    modelVersion: modelVersion,
    livenessVersion: livenessVersion,
  );

  Future<String> recordFaceAttendanceCheckOut({
    required FaceAttendanceVerification verification,
    required String employeeId,
    required DateTime workDate,
    required DateTime occurredAt,
    required String timeZoneId,
    required String kioskDeviceId,
    required String modelVersion,
    required String livenessVersion,
  }) => _recordFaceAttendanceKioskEvent(
    verification: verification,
    checkOut: true,
    employeeId: employeeId,
    workDate: workDate,
    occurredAt: occurredAt,
    timeZoneId: timeZoneId,
    kioskDeviceId: kioskDeviceId,
    modelVersion: modelVersion,
    livenessVersion: livenessVersion,
  );

  Future<String> _recordFaceAttendanceKioskEvent({
    required FaceAttendanceVerification verification,
    required bool checkOut,
    required String employeeId,
    required DateTime workDate,
    required DateTime occurredAt,
    required String timeZoneId,
    required String kioskDeviceId,
    required String modelVersion,
    required String livenessVersion,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    final repository = staffAttendanceRepository;
    if (session == null ||
        context == null ||
        context.businessId == null ||
        context.outletId == null ||
        !canManageStaffAttendance()) {
      throw const AppException(
        'Face attendance is unavailable for this account or outlet.',
      );
    }
    return checkOut
        ? repository.recordFaceCheckOut(
            verification: verification,
            tenantId: context.ownerUid,
            businessId: context.businessId!,
            outletId: context.outletId!,
            employeeId: employeeId,
            workDate: workDate,
            occurredAt: occurredAt,
            timeZoneId: timeZoneId,
            kioskDeviceId: kioskDeviceId,
            modelVersion: modelVersion,
            livenessVersion: livenessVersion,
            recordedBy: context.uid,
            token: session.idToken,
          )
        : repository.recordFaceCheckIn(
            verification: verification,
            tenantId: context.ownerUid,
            businessId: context.businessId!,
            outletId: context.outletId!,
            employeeId: employeeId,
            workDate: workDate,
            occurredAt: occurredAt,
            timeZoneId: timeZoneId,
            kioskDeviceId: kioskDeviceId,
            modelVersion: modelVersion,
            livenessVersion: livenessVersion,
            recordedBy: context.uid,
            token: session.idToken,
          );
  }

  bool canViewStaffAttendance() =>
      canManageStaffAttendance() ||
      canApproveStaffAttendance() ||
      canViewStaffSalary() ||
      (appContext != null &&
          (appContext!.accountType == 'owner' ||
              PermissionCatalog.allows(
                'ATTENDANCE_VIEW',
                appContext!.permissions,
              )));

  bool canApproveStaffAttendance() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows(
              'ATTENDANCE_APPROVE',
              context.permissions,
            ));
  }

  bool canChargeStaffKhata() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows(
              'STAFF_KHATA_CHARGE',
              context.permissions,
            ));
  }

  bool canManageStaffSalary() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('SALARY_MANAGE', context.permissions));
  }

  bool canApproveStaffSalary() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('SALARY_APPROVE', context.permissions));
  }

  bool canPayStaffSalary() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('SALARY_PAY', context.permissions));
  }

  bool canViewCustomers() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('CUSTOMER_VIEW', context.permissions) ||
            PermissionCatalog.allows('customers', context.permissions));
  }

  bool canEditCustomers() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('CUSTOMER_EDIT', context.permissions) ||
            PermissionCatalog.allows('customers', context.permissions));
  }

  bool canViewCustomerLedger() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('CUSTOMER_LEDGER_VIEW', context.permissions) ||
            PermissionCatalog.allows('customers', context.permissions));
  }

  bool canViewCustomerDue() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('DUE_VIEW', context.permissions) ||
            PermissionCatalog.allows('customers', context.permissions));
  }

  bool canCollectDue() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('DUE_COLLECT', context.permissions) ||
            PermissionCatalog.allows('billing', context.permissions));
  }

  bool canCollectCrossOutletDue() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('CROSS_OUTLET_DUE_COLLECT', context.permissions));
  }

  bool canViewStorage() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('godown.view', context.permissions) ||
            PermissionCatalog.allows('godown.read', context.permissions) ||
            PermissionCatalog.allows('storage', context.permissions) ||
            PermissionCatalog.allows('rack.read', context.permissions));
  }

  bool canCreateStorage() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('godown.create', context.permissions) ||
            PermissionCatalog.allows('storage.create', context.permissions));
  }

  bool canEditStorage() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('godown.edit', context.permissions) ||
            PermissionCatalog.allows('godown.update', context.permissions) ||
            PermissionCatalog.allows('godown.manage', context.permissions) ||
            PermissionCatalog.allows('storage.edit', context.permissions));
  }

  bool canDeleteStorage() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('godown.delete', context.permissions) ||
            PermissionCatalog.allows('godown.manage', context.permissions));
  }

  bool canReadRacks() =>
      user?.accountType == 'owner' ||
      PermissionCatalog.allows(
        'rack.read',
        appContext?.permissions ?? const <String>[],
      ) ||
      canViewStorage();
  bool canCreateRacks() =>
      user?.accountType == 'owner' ||
      PermissionCatalog.allows(
        'rack.create',
        appContext?.permissions ?? const <String>[],
      ) ||
      canCreateStorage();
  bool canUpdateRacks() =>
      user?.accountType == 'owner' ||
      PermissionCatalog.allows(
        'rack.update',
        appContext?.permissions ?? const <String>[],
      ) ||
      canEditStorage();
  bool canDeactivateRacks() =>
      user?.accountType == 'owner' ||
      PermissionCatalog.allows(
        'rack.delete',
        appContext?.permissions ?? const <String>[],
      ) ||
      canDeleteStorage();

  bool canCreateOutlet() =>
      user?.accountType == 'owner' ||
      PermissionCatalog.allows(
        'outlet.create',
        appContext?.permissions ?? const <String>[],
      );

  Future<void> loadStorageLocations() async {
    final request = ++_storageRequest;
    final session = await _getUsableSession();
    final context = appContext;
    if (request != _storageRequest) return;
    if (session == null || context?.businessId == null || !canViewStorage()) {
      storageError = 'You do not have storage access in this business.';
      notifyListeners();
      return;
    }
    storageLoading = true;
    storageError = null;
    notifyListeners();
    try {
      final result = await storageService.getLocations(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        token: session.idToken,
      );
      if (request == _storageRequest &&
          appContext?.businessId == context.businessId) {
        if (context.accountType == 'employee') {
          final assignedOutletIds = outlets
              .map((item) => item.outletId)
              .toSet();
          final visibleGodownIds = result
              .where(
                (item) =>
                    item.type == StorageLocationType.godown &&
                    item.godownScope == GodownScope.outlet &&
                    item.outletId != null &&
                    assignedOutletIds.contains(item.outletId),
              )
              .map((item) => item.storageLocationId)
              .toSet();
          storageLocations = result.where((item) {
            if (item.type == StorageLocationType.godown) {
              return visibleGodownIds.contains(item.storageLocationId);
            }
            if (item.type == StorageLocationType.rack) {
              return item.parentLocationType == 'OUTLET'
                  ? assignedOutletIds.contains(item.parentLocationId)
                  : item.godownId != null &&
                        visibleGodownIds.contains(item.godownId);
            }
            if (item.type == StorageLocationType.shelf) {
              final visibleRackIds = result
                  .where(
                    (rack) =>
                        rack.type == StorageLocationType.rack &&
                        (rack.parentLocationType == 'OUTLET'
                            ? assignedOutletIds.contains(rack.parentLocationId)
                            : visibleGodownIds.contains(rack.godownId)),
                  )
                  .map((rack) => rack.storageLocationId)
                  .toSet();
              return visibleRackIds.contains(item.rackId);
            }
            return false;
          }).toList();
        } else {
          storageLocations = result;
        }
      }
    } catch (e) {
      if (request == _storageRequest) {
        storageError = e is AppException
            ? e.message
            : 'Unable to load storage locations.';
      }
    } finally {
      if (request == _storageRequest) {
        storageLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> createStorageLocation({
    required StorageLocationType type,
    required String? parentLocationId,
    required String name,
    String? code,
    required String? description,
    Map<String, dynamic>? addressDetails,
    Map<String, dynamic>? capacity,
    Map<String, dynamic>? contact,
    GodownScope? godownScope,
    String? outletId,
    String parentLocationType = 'GODOWN',
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    final allowed = type == StorageLocationType.rack
        ? canCreateRacks()
        : canCreateStorage();
    if (session == null || context?.businessId == null || !allowed) {
      storageError = 'You do not have permission to create storage locations.';
      notifyListeners();
      return false;
    }
    storageSaving = true;
    storageError = null;
    notifyListeners();
    try {
      await storageService.createLocation(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        type: type,
        parentLocationId: parentLocationId,
        parentLocationType: parentLocationType,
        name: name,
        code: code,
        description: description,
        addressDetails: addressDetails,
        capacity: capacity,
        contact: contact,
        godownScope: godownScope,
        outletId: outletId,
        actorUid: context.uid,
        token: session.idToken,
      );
      await loadStorageLocations();
      return true;
    } catch (e) {
      storageError = e is AppException
          ? e.message
          : 'Unable to create storage location.';
      return false;
    } finally {
      storageSaving = false;
      notifyListeners();
    }
  }

  Future<bool> createMultipleRacks({
    required String parentLocationType,
    required String parentLocationId,
    required int count,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null || context?.businessId == null || !canCreateRacks()) {
      storageError = 'You do not have permission to create Racks.';
      notifyListeners();
      return false;
    }
    storageSaving = true;
    storageError = null;
    notifyListeners();
    try {
      await storageService.createRacks(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        parentLocationType: parentLocationType,
        parentLocationId: parentLocationId,
        count: count,
        actorUid: context.uid,
        token: session.idToken,
      );
      await loadStorageLocations();
      return true;
    } catch (e) {
      storageError = e is AppException ? e.message : 'Unable to create Racks.';
      return false;
    } finally {
      storageSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateStorageLocation({
    required StorageLocationModel location,
    required String name,
    String? code,
    required String? description,
    Map<String, dynamic>? addressDetails,
    Map<String, dynamic>? capacity,
    Map<String, dynamic>? contact,
    GodownScope? godownScope,
    String? outletId,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    final allowed = location.type == StorageLocationType.rack
        ? canUpdateRacks()
        : canEditStorage();
    if (session == null || context?.businessId == null || !allowed) {
      storageError = 'You do not have permission to edit storage locations.';
      notifyListeners();
      return false;
    }
    storageSaving = true;
    storageError = null;
    notifyListeners();
    try {
      await storageService.updateLocation(
        current: location,
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        name: name,
        code: code,
        description: description,
        addressDetails: addressDetails,
        capacity: capacity,
        contact: contact,
        godownScope: godownScope,
        outletId: outletId,
        actorUid: context.uid,
        token: session.idToken,
      );
      await loadStorageLocations();
      return true;
    } catch (e) {
      storageError = e is AppException
          ? e.message
          : 'Unable to update storage location.';
      return false;
    } finally {
      storageSaving = false;
      notifyListeners();
    }
  }

  Future<bool> setStorageLocationActive(
    StorageLocationModel location,
    bool isActive,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    final allowed = location.type == StorageLocationType.rack
        ? canDeactivateRacks()
        : canDeleteStorage();
    if (session == null || context?.businessId == null || !allowed) {
      storageError = 'You do not have permission to change storage status.';
      notifyListeners();
      return false;
    }
    storageSaving = true;
    storageError = null;
    notifyListeners();
    try {
      await storageService.setLocationActive(
        location: location,
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        isActive: isActive,
        actorUid: context.uid,
        token: session.idToken,
      );
      await loadStorageLocations();
      return true;
    } catch (e) {
      storageError = e is AppException
          ? e.message
          : 'Unable to update storage location status.';
      return false;
    } finally {
      storageSaving = false;
      notifyListeners();
    }
  }

  Future<void> refreshDashboard() async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null || context == null) return;
    final owner = context.accountType == 'owner';
    final permissions = context.permissions;
    if (!owner && permissions.isEmpty) {
      dashboardSummary = null;
      dashboardError = null;
      dashboardLoading = false;
      notifyListeners();
      return;
    }
    dashboardLoading = true;
    dashboardError = null;
    notifyListeners();
    try {
      final loadedSummary = await dashboardRepository.load(
        context,
        session.idToken,
        includeSales:
            owner ||
            PermissionCatalog.allows('sales', permissions) ||
            PermissionCatalog.allows('billing', permissions),
        includePurchases:
            owner || PermissionCatalog.allows('purchase', permissions),
        includeProducts:
            owner ||
            PermissionCatalog.allows('products', permissions) ||
            PermissionCatalog.allows('inventory', permissions),
        includeCustomers:
            owner || PermissionCatalog.allows('customers', permissions),
      );
      if (!_workspaceMatches(context)) return;
      dashboardSummary = loadedSummary;
    } catch (e) {
      dashboardSummary = null;
      dashboardError = e is AppException
          ? e.message
          : 'Unable to load this outlet dashboard. Please retry.';
    } finally {
      dashboardLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBusinessTypes() async {
    final token = (await _getUsableSession())?.idToken;
    if (token == null) return;
    businessTypesLoading = true;
    businessTypesError = null;
    notifyListeners();
    try {
      businessTypes = await businessTypesRepository.getActiveBusinessTypes(
        token,
      );
    } catch (e) {
      businessTypesError = e is AppException
          ? e.message
          : 'Unable to load business types.';
    } finally {
      businessTypesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBusinessSubTypes() async {
    final token = (await _getUsableSession())?.idToken;
    final businessId = appContext?.businessId;
    final business = businesses.where((item) => item.businessId == businessId);
    if (token == null || business.isEmpty) return;
    businessSubTypesLoading = true;
    businessSubTypesError = null;
    businessSubTypes = [];
    notifyListeners();
    try {
      businessSubTypes = await businessSubTypesRepository
          .getActiveSubTypesByBusinessType(
            business.first.businessTypeId,
            token,
          );
    } catch (e) {
      businessSubTypesError = e is AppException
          ? e.message
          : 'Unable to load outlet types.';
    } finally {
      businessSubTypesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadEmployees() async {
    final session = await _getUsableSession();
    final ownerUid = user?.uid;
    if (session == null || ownerUid == null || user?.accountType != 'owner') {
      return;
    }
    employeesLoading = true;
    employeesError = null;
    notifyListeners();
    try {
      employees = await employeesRepository.getEmployeesByOwner(
        ownerUid,
        session.idToken,
      );
    } catch (e) {
      employeesError = e is AppException
          ? e.message
          : 'Unable to load employees.';
    } finally {
      employeesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadEmployeeMasters() async {
    final session = await _getUsableSession();
    if (session == null || user?.accountType != 'owner') return;
    employeeMastersLoading = true;
    employeeMastersError = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        businessesRepository.getBusinessesByOwnerUid(
          user!.uid,
          session.idToken,
        ),
        rolesRepository.getActiveRoles(session.idToken),
        permissionsRepository.getActivePermissions(session.idToken),
      ]);
      businesses = values[0] as List<BusinessModel>;
      activeRoles = values[1] as List<RoleModel>;
      final loadedPermissions = values[2] as List<PermissionModel>;
      final configuredIds = loadedPermissions
          .map((p) => PermissionIdMatcher.normalize(p.permissionId))
          .toSet();
      activePermissions = [
        ...loadedPermissions,
        for (final id in PermissionCatalog.staffSalaryPermissions)
          if (!configuredIds.contains(PermissionIdMatcher.normalize(id)))
            PermissionModel(
              permissionId: id,
              groupId: 'staff_salary',
              groupName: 'Staff Salary Khata',
              name: id.replaceAll('_', ' '),
              isActive: true,
              displayOrder: 800,
            ),
        for (final id in [
          ...PermissionCatalog.staffAttendancePermissions,
          ...PermissionCatalog.biometricAttendancePermissions,
          ...PermissionCatalog.staffKhataPermissions,
        ])
          if (!configuredIds.contains(PermissionIdMatcher.normalize(id)))
            PermissionModel(
              permissionId: id,
              groupId: 'staff_salary',
              groupName: 'Staff Attendance & Khata',
              name: id.replaceAll('_', ' '),
              isActive: true,
              displayOrder: 820,
            ),
      ];
    } catch (e) {
      employeeMastersError = e is AppException
          ? e.message
          : 'Unable to load employee setup data.';
    } finally {
      employeeMastersLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadEmployeeOutlets(List<String> businessIds) async {
    final session = await _getUsableSession();
    final ownerUid = user?.uid;
    if (session == null || ownerUid == null) return;
    final request = ++_employeeOutletRequest;
    employeeOutletsLoading = true;
    employeeOutletError = null;
    employeeOutlets = [];
    notifyListeners();
    try {
      final loaded = await employeesRepository.getOutletsForBusinesses(
        businessIds,
        ownerUid,
        session.idToken,
      );
      if (request == _employeeOutletRequest) employeeOutlets = loaded;
    } catch (e) {
      if (request == _employeeOutletRequest) {
        employeeOutletError = e is AppException
            ? e.message
            : 'Unable to load outlets.';
      }
    } finally {
      if (request == _employeeOutletRequest) employeeOutletsLoading = false;
    }
    notifyListeners();
  }

  Future<AuthSession?> _getUsableSession() async {
    try {
      return await auth.ensureValidSession();
    } on AppException catch (exception) {
      error = exception.message;
      return null;
    }
  }

  bool canManageSuppliers() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('suppliers', context.permissions));
  }

  bool canManagePurchases() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('purchase', context.permissions));
  }

  bool canCreatePurchases() {
    final context = appContext;
    return context != null &&
        context.businessId?.isNotEmpty == true &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('purchase.create', context.permissions));
  }

  bool canCreateSuppliers() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('supplier.create', context.permissions) ||
            PermissionCatalog.allows('suppliers.create', context.permissions));
  }

  bool canManageProducts() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('product.read', context.permissions) ||
            PermissionCatalog.allows('products', context.permissions));
  }

  bool canCreateProducts() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('product.create', context.permissions) ||
            PermissionCatalog.allows('products.create', context.permissions));
  }

  bool canCreateProductMasters() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows(
              'product_master.create',
              context.permissions,
            ));
  }

  bool canUpdateProducts() {
    final context = appContext;
    return context != null &&
        (context.accountType == 'owner' ||
            PermissionCatalog.allows('product.update', context.permissions) ||
            PermissionCatalog.allows('products.update', context.permissions));
  }

  String? placementBackfillNotice;
  bool _backfillRunning = false;
  Map<String, dynamic>? lastProductDuplicateDetails;

  String get productsScopeLabel =>
      'Products placed at ${currentOutlet?.outletName ?? 'this outlet'}; stock is for this outlet only';

  bool get canAddExistingProductsToOutlet =>
      appContext != null &&
      appContext!.businessId != null &&
      appContext!.outletId != null &&
      (canCreateProducts() || canUpdateProducts());

  /// One-time, evidence-only placement of products created before outlet
  /// placement existed. Never throws; unprovable products stay unassigned.
  Future<void> _runPlacementBackfill(AppContext context, String idToken) async {
    if (_backfillRunning ||
        context.accountType != 'owner' ||
        context.businessId == null) {
      return;
    }
    _backfillRunning = true;
    try {
      final report = await productRepository.backfillKnownOutletPlacements(
        tenantId: context.ownerUid,
        businessId: context.businessId!,
        actorUid: context.uid,
        token: idToken,
      );
      if (report == null) return;
      final names = {for (final o in outlets) o.outletId: o.outletName};
      if (kDebugMode) {
        for (final a in report.assignments) {
          debugPrint(
            '[placement] ${a.productName} -> ${names[a.outletId] ?? a.outletId} (${a.evidence.join(', ')})',
          );
        }
        for (final name in report.unassigned.values) {
          debugPrint('[placement] $name left unassigned (no outlet proof)');
        }
      }
      placementBackfillNotice = report.unassigned.isEmpty
          ? null
          : '${report.unassigned.length} existing product(s) are not assigned to this outlet structure.';
    } catch (e) {
      if (kDebugMode) debugPrint('[placement] backfill skipped: $e');
    } finally {
      _backfillRunning = false;
    }
  }

  Future<void> loadProducts() async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageProducts()) {
      productsError = 'Select a Business and ensure you have Product access.';
      notifyListeners();
      return;
    }
    await _runPlacementBackfill(context!, session.idToken);
    final outletId = context.outletId;
    if (outletId == null) {
      products = [];
      productStock = {};
      productsError = 'Select an Outlet to view its Products.';
      notifyListeners();
      return;
    }
    productsLoading = true;
    productsError = null;
    notifyListeners();
    try {
      // Only this outlet's placements and this outlet's stock are read.
      final loadedProducts = await productRepository.getOutletProducts(
        tenantId: context.ownerUid,
        businessId: context.businessId!,
        outletId: outletId,
        token: session.idToken,
        activeOnly: false,
      );
      final loadedVariants = await purchaseRepository.getProductsForBusiness(
        context.businessId!,
        session.idToken,
        tenantId: context.ownerUid,
        outletId: outletId,
      );
      final stock = !canViewStorage()
          ? <String, int>{}
          : await productRepository.getOutletProductStock(
              tenantId: context.ownerUid,
              businessId: context.businessId!,
              outletId: outletId,
              token: session.idToken,
            );
      if (!_workspaceMatches(context)) return;
      productStock = stock;
      products = loadedProducts;
      purchaseProducts = loadedVariants;
    } catch (e) {
      if (!_workspaceMatches(context)) return;
      productsError = e is AppException
          ? e.message
          : 'Unable to load Products.';
    } finally {
      productsLoading = false;
      notifyListeners();
    }
  }

  Future<StockTransactionAuditModel> addOpeningStock({
    required String productId,
    required String variantId,
    required int quantity,
    required String reason,
    int? unitCostPaise,
    String? unit,
    String? transactionId,
  }) async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      throw const AppException('Active outlet workspace session required.');
    }
    final result = await inventoryRepository.addOpeningStock(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      productId: productId,
      variantId: variantId,
      quantity: quantity,
      reason: reason,
      userId: user?.uid ?? context.uid,
      token: session.idToken,
      permissions: context.permissions,
      isOwner: context.accountType == 'owner',
      unitCostPaise: unitCostPaise,
      unit: unit,
      transactionId: transactionId,
    );
    await loadProducts();
    return result;
  }

  Future<StockTransactionAuditModel> requestOrApplyAdjustment({
    required String productId,
    required String variantId,
    required int quantity,
    required bool isIncrease,
    required String transactionType,
    required String reason,
    String? unit,
    int? unitCostPaise,
    String? transactionId,
  }) async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      throw const AppException('Active outlet workspace session required.');
    }
    final result = await inventoryRepository.requestOrApplyAdjustment(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      productId: productId,
      variantId: variantId,
      quantity: quantity,
      isIncrease: isIncrease,
      transactionType: transactionType,
      reason: reason,
      userId: user?.uid ?? context.uid,
      token: session.idToken,
      permissions: context.permissions,
      isOwner: context.accountType == 'owner',
      unit: unit,
      unitCostPaise: unitCostPaise,
      transactionId: transactionId,
    );
    await loadProducts();
    return result;
  }

  Future<StockTransactionAuditModel> approveAdjustment(
    String transactionId,
  ) async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      throw const AppException('Active outlet workspace session required.');
    }
    final result = await inventoryRepository.approveAdjustment(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      transactionId: transactionId,
      userId: user?.uid ?? context.uid,
      token: session.idToken,
      permissions: context.permissions,
      isOwner: context.accountType == 'owner',
    );
    await loadProducts();
    return result;
  }

  Future<StockTransactionAuditModel> rejectAdjustment(
    String transactionId, {
    String? rejectionReason,
  }) async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      throw const AppException('Active outlet workspace session required.');
    }
    final result = await inventoryRepository.rejectAdjustment(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      transactionId: transactionId,
      userId: user?.uid ?? context.uid,
      token: session.idToken,
      permissions: context.permissions,
      isOwner: context.accountType == 'owner',
      rejectionReason: rejectionReason,
    );
    await loadProducts();
    return result;
  }

  Future<List<StockTransactionAuditModel>> getStockHistory({
    String? variantId,
  }) async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      return const [];
    }
    return inventoryRepository.getStockHistory(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      token: session.idToken,
      variantId: variantId,
      permissions: context.permissions,
      isOwner: context.accountType == 'owner',
    );
  }

  Future<List<StockTransactionAuditModel>> getPendingAdjustments() async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      return const [];
    }
    return inventoryRepository.getPendingAdjustments(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      token: session.idToken,
      permissions: context.permissions,
      isOwner: context.accountType == 'owner',
    );
  }

  Future<bool> hasOpeningStockBeenInitialized(String variantId) async {
    final context = appContext;
    final session = await _getUsableSession();
    if (context == null ||
        session == null ||
        context.outletId == null ||
        context.businessId == null) {
      return false;
    }
    return inventoryRepository.hasOpeningStockBeenInitialized(
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      variantId: variantId,
      token: session.idToken,
    );
  }

  /// Offline-only eligibility check used by Barcode label actions.
  Future<bool> barcodeVariantWasReceived(ProductVariantModel variant) async {
    final context = appContext;
    // This feature is local-only. Use the active cached identity and never
    // refresh credentials (which could require a network request) here.
    final session = auth.currentSession;
    if (context == null || session == null || context.outletId == null) {
      return false;
    }
    return productRepository.variantHasReceivedInventory(
      token: session.idToken,
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      variantId: variant.variantId,
    );
  }

  Future<Set<String>> loadBarcodeReceivedVariantIds() async {
    final context = appContext;
    // Reuse the active cached token only; no auth refresh or Firestore read.
    final session = auth.currentSession;
    if (context == null || session == null || context.outletId == null) {
      return const {};
    }
    return productRepository.variantsWithReceivedInventory(
      token: session.idToken,
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
    );
  }

  Future<Map<String, ({int mrp, int sellingPrice})>>
  loadBarcodeReceivedVariantPricing() async {
    final context = appContext;
    final session = auth.currentSession;
    if (context == null || session == null || context.outletId == null) {
      return const {};
    }
    return productRepository.receivedVariantPricing(
      token: session.idToken,
      tenantId: context.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
    );
  }

  /// Business products that are not yet placed at the current outlet.
  Future<List<ProductModel>> loadProductsAvailableToAddToOutlet() async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !canManageProducts()) {
      return const [];
    }
    return productRepository.getProductsNotInOutlet(
      tenantId: context!.ownerUid,
      businessId: context.businessId!,
      outletId: context.outletId!,
      token: session.idToken,
    );
  }

  /// Places existing business products at the current outlet. Never creates or
  /// copies product/variant masters.
  Future<bool> addExistingProductsToCurrentOutlet(
    List<String> productIds,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !(canCreateProducts() || canUpdateProducts())) {
      productsError = 'You do not have permission to add Products to Outlets.';
      notifyListeners();
      return false;
    }
    productSaving = true;
    productsError = null;
    notifyListeners();
    try {
      await productRepository.assignProductsToOutlet(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        outletId: context.outletId!,
        productIds: productIds,
        token: session.idToken,
        actorUid: context.uid,
      );
      await loadProducts();
      return true;
    } catch (e) {
      productsError = e is AppException
          ? e.message
          : 'Unable to add Products to this Outlet.';
      return false;
    } finally {
      productSaving = false;
      notifyListeners();
    }
  }

  /// Removes an existing product placement from the current outlet by marking it
  /// inactive. The product and variant masters remain untouched in the catalogue.
  Future<bool> removeProductFromCurrentOutlet(String productId) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !canUpdateProducts()) {
      productsError = 'You do not have permission to modify outlet placements.';
      notifyListeners();
      return false;
    }
    productSaving = true;
    productsError = null;
    notifyListeners();
    try {
      final removed = await productRepository.removeProductFromOutlet(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        outletId: context.outletId!,
        productId: productId,
        token: session.idToken,
        actorUid: context.uid,
      );
      if (removed) {
        await loadProducts();
      }
      return removed;
    } catch (e) {
      productsError = e is AppException
          ? e.message
          : 'Unable to remove Product from this Outlet.';
      return false;
    } finally {
      productSaving = false;
      notifyListeners();
    }
  }

  /// Removes multiple product placements from the current outlet by marking them
  /// inactive. Product and variant masters remain untouched in the catalogue.
  Future<int> removeProductsFromCurrentOutlet(List<String> productIds) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !canUpdateProducts()) {
      productsError = 'You do not have permission to modify outlet placements.';
      notifyListeners();
      return 0;
    }
    final ids = productIds.toSet().where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return 0;
    productSaving = true;
    productsError = null;
    notifyListeners();
    try {
      var count = 0;
      for (final productId in ids) {
        final removed = await productRepository.removeProductFromOutlet(
          tenantId: context!.ownerUid,
          businessId: context.businessId!,
          outletId: context.outletId!,
          productId: productId,
          token: session.idToken,
          actorUid: context.uid,
        );
        if (removed) count++;
      }
      if (count > 0) {
        await loadProducts();
      }
      return count;
    } catch (e) {
      productsError = e is AppException
          ? e.message
          : 'Unable to remove Products from this Outlet.';
      return 0;
    } finally {
      productSaving = false;
      notifyListeners();
    }
  }

  Future<String> createProductAttributeOption(
    String attributeId,
    String name,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canCreateProductMasters()) {
      throw const AppException('Product master permission is required.');
    }
    return productRepository.createAttributeOption(
      tenantId: context!.ownerUid,
      businessId: context.businessId!,
      attributeId: attributeId,
      name: name,
      actorUid: user?.uid ?? context.ownerUid,
      token: session.idToken,
    );
  }

  Future<void> configureProductAttribute(
    String subcategoryId,
    Map<String, dynamic> definition,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canCreateProductMasters()) {
      throw const AppException('Product master permission is required.');
    }
    await productRepository.configureBusinessAttribute(
      tenantId: context!.ownerUid,
      businessId: context.businessId!,
      subcategoryId: subcategoryId,
      actorUid: user?.uid ?? context.ownerUid,
      token: session.idToken,
      definition: definition,
    );
  }

  Future<ResolvedProductTemplate> resolveProductTemplate(
    String subcategoryId,
  ) async {
    try {
      final session = await _getUsableSession();
      final context = appContext;
      if (session != null &&
          context?.businessId != null &&
          canManageProducts()) {
        return await productRepository.resolveTemplate(
          tenantId: context!.ownerUid,
          businessId: context.businessId!,
          subcategoryId: subcategoryId,
          token: session.idToken,
        );
      }
    } catch (_) {
      // Fallback for test double controllers or mock environments
    }

    final legacyAttrs = await loadProductTemplate(subcategoryId);
    final productAttrs = <ResolvedTemplateAttribute>[];
    final variantAttrs = <ResolvedTemplateAttribute>[];
    final techAttrs = <ResolvedTemplateAttribute>[];

    ConditionScope resolveScope(
      Map<String, dynamic> condMap,
      String targetId,
      String levelStr,
    ) {
      final scopeStr = (condMap['scope'] ?? condMap['conditionScope'])
          ?.toString()
          .toUpperCase();
      if (scopeStr == 'ANY_VARIANT' || scopeStr == 'ANYVARIANT') {
        return ConditionScope.anyVariant;
      }
      if (scopeStr == 'ALL_VARIANTS' || scopeStr == 'ALLVARIANTS') {
        return ConditionScope.allVariants;
      }
      if (scopeStr == 'VARIANT') return ConditionScope.variant;
      if (scopeStr == 'PRODUCT') return ConditionScope.product;

      if (levelStr != 'VARIANT') {
        if (targetId == 'colourType' || targetId == 'colorType') {
          return ConditionScope.anyVariant;
        }
      }
      return levelStr == 'VARIANT'
          ? ConditionScope.variant
          : ConditionScope.product;
    }

    for (final a in legacyAttrs) {
      final conditions = <ResolvedCondition>[];
      if (a.visibleWhen != null && a.visibleWhen!.isNotEmpty) {
        final targetId = a.visibleWhen!['attributeId'] as String?;
        final inList = a.visibleWhen!['in'] as List?;
        if (targetId != null && inList != null) {
          conditions.add(
            ResolvedCondition(
              targetAttributeId: targetId,
              operator: 'IN',
              expectedValues: inList,
              scope: resolveScope(a.visibleWhen!, targetId, a.level),
            ),
          );
        }
      }

      final resolvedAttr = ResolvedTemplateAttribute(
        attributeId: a.id,
        displayName: a.name,
        level: a.level == 'VARIANT'
            ? AttributeLevel.variant
            : AttributeLevel.product,
        dataType: a.dataType,
        required: a.required,
        defaultValue: a.defaultValue,
        options: a.options
            .map((o) => ResolvedAttributeOption(id: o, name: o))
            .toList(),
        allowMultiple: false,
        allowAddNewOption: a.allowAddNewOption,
        hint: a.hintText,
        exampleValue: a.exampleValue,
        technical: a.section == 'TECHNICAL',
        sortOrder: a.sortOrder,
        conditions: conditions,
        section: a.section,
        semanticRole: a.semanticRole,
        measurementDimension: a.measurementDimension,
        measurementUnitAttributeId: a.measurementUnitAttributeId,
        minimumExclusive: a.minimumExclusive,
        defaultRules: a.defaultRules,
        visibleWhen: a.visibleWhen,
        requiredWhen: a.requiredWhen,
      );

      if (resolvedAttr.level == AttributeLevel.variant) {
        variantAttrs.add(resolvedAttr);
      } else {
        productAttrs.add(resolvedAttr);
      }
      if (resolvedAttr.technical) {
        techAttrs.add(resolvedAttr);
      }
    }

    return ResolvedProductTemplate(
      categoryId: '',
      subcategoryId: subcategoryId,
      categoryName: '',
      subcategoryName: subcategoryId,
      readiness: legacyAttrs.isEmpty
          ? TemplateReadinessState.missingTemplate
          : TemplateReadinessState.ready,
      productAttributes: productAttrs,
      variantAttributes: variantAttrs,
      technicalAttributes: techAttrs,
      unitRules: const ResolvedUnitRule(),
    );
  }

  Future<List<ProductAttribute>> loadProductTemplate(
    String subcategoryId,
  ) async {
    final resolved = await resolveProductTemplate(subcategoryId);
    return resolved.attributes;
  }

  Future<List<CentralProductMaster>> searchCentralProductMaster(
    String query,
  ) async {
    final normalized = query.trim();
    if (normalized.length < 2) return const [];
    final context = appContext;
    final business = businesses
        .where((value) => value.businessId == context?.businessId)
        .firstOrNull;
    final outlet = currentOutlet;
    if (context == null ||
        business == null ||
        outlet == null ||
        outlet.businessId != business.businessId ||
        !outlet.isActive ||
        !canManageProducts()) {
      throw const AppException(
        'Select an active outlet and ensure you have Product access.',
      );
    }
    // BUS-001 stores display labels where canonical catalogue scope IDs belong.
    final scope = resolveCentralProductSearchScope(
      businessId: business.businessId,
      businessTypeId: business.businessTypeId,
      businessSubTypeId: outlet.outletTypeId,
    );
    return productRepository.searchCentralProductMaster(
      query: normalized,
      businessTypeId: scope.businessTypeId,
      businessSubTypeId: scope.businessSubTypeId,
    );
  }

  Future<void> loadProductMasters({String? categoryId}) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageProducts()) {
      productMastersError =
          'Select a Business and ensure you have Product access.';
      notifyListeners();
      return;
    }
    productMastersLoading = true;
    productMastersError = null;
    notifyListeners();
    try {
      final business = businesses
          .where((value) => value.businessId == context!.businessId)
          .firstOrNull;
      final outlet = currentOutlet;
      final scope =
          business != null &&
              outlet != null &&
              outlet.businessId == business.businessId
          ? resolveCentralProductSearchScope(
              businessId: business.businessId,
              businessTypeId: business.businessTypeId,
              businessSubTypeId: outlet.outletTypeId,
            )
          : (businessTypeId: 'HARDWARE', businessSubTypeId: 'PAINTS');
      const types = ['BRAND', 'UNIT', 'HSN'];
      final values = await Future.wait([
        for (final type in types)
          productRepository.getMasterValues(
            tenantId: context!.ownerUid,
            businessId: context.businessId!,
            masterType: type,
            token: session.idToken,
          ),
        productRepository.getEligibleCategories(
          tenantId: context!.ownerUid,
          businessId: context.businessId!,
          token: session.idToken,
          businessTypeId: scope.businessTypeId,
          businessSubTypeId: scope.businessSubTypeId,
        ),
        if (categoryId != null)
          productRepository.getEligibleSubcategories(
            tenantId: context.ownerUid,
            businessId: context.businessId!,
            categoryId: categoryId,
            token: session.idToken,
            businessTypeId: scope.businessTypeId,
            businessSubTypeId: scope.businessSubTypeId,
          ),
      ]);
      if (!_workspaceMatches(context)) return;
      productMasterValues['BRAND'] = values[0];
      productMasterValues['UNIT'] = values[1];
      productMasterValues['HSN'] = values[2];
      productMasterValues['CATEGORY'] = values[3];

      if (categoryId != null) {
        productMasterValues['SUBCATEGORY:$categoryId'] = values.last;
      }
      if ([
        'BRAND',
        'CATEGORY',
        'UNIT',
      ].any((type) => productMasterValues[type]!.isEmpty)) {
        productMastersError = 'Product catalogue is unavailable. Please sync or contact administrator.';
      }
    } catch (e) {
      productMastersError = e is AppException
          ? e.message
          : 'Unable to load Product classification data.';
    } finally {
      productMastersLoading = false;
      notifyListeners();
    }
  }

  Future<ProductMasterValue?> createProductMaster({
    required String masterType,
    required String name,
    String? categoryId,
    String? code,
    List<String> applicableAttributes = const [],
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canCreateProductMasters()) {
      productMastersError =
          'You do not have permission to create Product master values.';
      notifyListeners();
      return null;
    }
    try {
      final created = await productRepository.createMasterValue(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        masterType: masterType,
        name: name,
        actorUid: user?.uid ?? context.ownerUid,
        token: session.idToken,
        categoryId: categoryId,
        code: code,
        applicableAttributes: applicableAttributes,
      );
      final key = masterType.toUpperCase() == 'SUBCATEGORY'
          ? 'SUBCATEGORY:$categoryId'
          : masterType.toUpperCase();
      final current = List<ProductMasterValue>.of(
        productMasterValues[key] ?? const [],
      );
      if (!current.any((value) => value.id == created.id)) current.add(created);
      current.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      productMasterValues[key] = current;
      productMastersError = null;
      notifyListeners();
      return created;
    } catch (e) {
      productMastersError = e is AppException
          ? e.message
          : 'Unable to create the master value.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> createProduct({
    required String name,
    required String variantName,
    required String unitId,
    String? brand,
    String? category,
    String? subcategory,
    String? description,
    String? sku,
    String? barcode,
    String? hsnCode,
    int gstRateBps = 0,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canCreateProducts()) {
      productsError = 'You do not have permission to create Products.';
      notifyListeners();
      return false;
    }
    productSaving = true;
    productsError = null;
    notifyListeners();
    try {
      await productRepository.createProduct(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        name: name,
        variantName: variantName,
        unitId: unitId,
        brand: brand,
        category: category,
        subcategory: subcategory,
        description: description,
        sku: sku,
        barcode: barcode,
        hsnCode: hsnCode,
        gstRateBps: gstRateBps,
        actorUid: context.uid,
        token: session.idToken,
        outletId: context.outletId,
      );
      await loadProducts();
      return true;
    } catch (e) {
      productsError = e is AppException ? e.message : 'Unable to save Product.';
      return false;
    } finally {
      productSaving = false;
      notifyListeners();
    }
  }

  Future<bool> createStructuredProduct({
    required String name,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canCreateProducts()) {
      productsError = 'You do not have permission to create Products.';
      notifyListeners();
      return false;
    }
    productSaving = true;
    productsError = null;
    lastProductDuplicateDetails = null;
    notifyListeners();
    try {
      final business = businesses
          .where((value) => value.businessId == context!.businessId)
          .firstOrNull;
      final outlet = currentOutlet;
      final scope =
          business != null &&
              outlet != null &&
              outlet.businessId == business.businessId
          ? resolveCentralProductSearchScope(
              businessId: business.businessId,
              businessTypeId: business.businessTypeId,
              businessSubTypeId: outlet.outletTypeId,
            )
          : (businessTypeId: 'HARDWARE', businessSubTypeId: 'PAINTS');
      await productRepository.createStructuredProduct(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        productName: name,
        actorUid: user?.uid ?? context.ownerUid,
        token: session.idToken,
        productFields: productFields,
        variants: variants,
        outletId: context.outletId,
        businessTypeId: scope.businessTypeId,
        businessSubTypeId: scope.businessSubTypeId,
      );
      await loadProducts();
      return true;
    } catch (e) {
      lastProductDuplicateDetails = (e is AppException && e.details != null)
          ? e.details
          : null;
      productsError = e is AppException ? e.message : 'Unable to save Product.';
      return false;
    } finally {
      productSaving = false;
      notifyListeners();
    }
  }

  bool canDeleteProducts() {
    final c = appContext;
    return c != null &&
        (c.accountType == 'owner' ||
            PermissionCatalog.allows('product.delete', c.permissions));
  }

  Future<ReclassificationPlan?> computeReclassificationPlan({
    required String productId,
    required String newCategoryId,
    required String newSubcategoryId,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    final session = await _getUsableSession();
    final c = appContext;
    if (session == null || c == null || c.businessId == null) return null;
    return productRepository.computeReclassificationPlan(
      tenantId: c.ownerUid,
      businessId: c.businessId!,
      productId: productId,
      newCategoryId: newCategoryId,
      newSubcategoryId: newSubcategoryId,
      productFields: productFields,
      variants: variants,
      token: session.idToken,
    );
  }

  Future<bool> saveStructuredProductEdit({
    required String productId,
    required String name,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    final session = await _getUsableSession();
    final c = appContext;
    if (session == null || c?.businessId == null || !canUpdateProducts()) {
      return false;
    }
    try {
      await productRepository.updateStructuredProduct(
        tenantId: c!.ownerUid,
        businessId: c.businessId!,
        productId: productId,
        productName: name,
        actorUid: user?.uid ?? c.ownerUid,
        token: session.idToken,
        productFields: productFields,
        variants: variants,
      );
      await loadProducts();
      return true;
    } catch (e) {
      productsError = e is AppException ? e.message : 'Unable to save Product.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> setProductStatus(List<String> ids, String status) async {
    final session = await _getUsableSession();
    final c = appContext;
    if (session == null ||
        c?.businessId == null ||
        !(status == 'DELETED' ? canDeleteProducts() : canUpdateProducts())) {
      return false;
    }
    try {
      await productRepository.setProductStatus(
        tenantId: c!.ownerUid,
        businessId: c.businessId!,
        productIds: ids,
        status: status,
        actorUid: user?.uid ?? c.ownerUid,
        token: session.idToken,
      );
      if (status == 'ACTIVE' && c.outletId != null) {
        await productRepository.assignProductsToOutlet(
          tenantId: c.ownerUid,
          businessId: c.businessId!,
          outletId: c.outletId!,
          productIds: ids,
          token: session.idToken,
          actorUid: user?.uid ?? c.ownerUid,
        );
      }
      await loadProducts();
      return true;
    } catch (e) {
      productsError = e is AppException
          ? e.message
          : 'Unable to update status.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProductVariant({
    required String productId,
    required String variantId,
    required String name,
    required String variantName,
    required String unitId,
    String? brand,
    String? category,
    String? subcategory,
    String? description,
    String? sku,
    String? barcode,
    String? hsnCode,
    int gstRateBps = 0,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canUpdateProducts()) {
      productsError = 'You do not have permission to edit Products.';
      notifyListeners();
      return false;
    }
    productSaving = true;
    productsError = null;
    notifyListeners();
    try {
      await productRepository.updateProductVariant(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        productId: productId,
        variantId: variantId,
        name: name,
        variantName: variantName,
        unitId: unitId,
        brand: brand,
        category: category,
        subcategory: subcategory,
        description: description,
        sku: sku,
        barcode: barcode,
        hsnCode: hsnCode,
        gstRateBps: gstRateBps,
        actorUid: user?.uid ?? context.ownerUid,
        token: session.idToken,
      );
      await loadProducts();
      return true;
    } catch (e) {
      productsError = e is AppException
          ? e.message
          : 'Unable to update Product.';
      notifyListeners();
      return false;
    } finally {
      productSaving = false;
      notifyListeners();
    }
  }

  Future<void> loadSuppliers() async {
    AuthSession? session;
    try {
      session = await auth.ensureValidSession();
    } catch (e) {
      suppliersError = e is AppException ? e.message : 'Please sign in again.';
      notifyListeners();
      return;
    }
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageSuppliers()) {
      suppliersError = 'You do not have supplier access in this workspace.';
      notifyListeners();
      return;
    }
    suppliersLoading = true;
    suppliersError = null;
    notifyListeners();
    try {
      final loaded = await supplierRepository.getForBusiness(
        context!.ownerUid,
        context.businessId!,
        session.idToken,
        includeInactive: true,
      );
      final tenant = await supplierRepository.getTenantSuppliers(
        context.ownerUid,
        session.idToken,
      );
      if (!_workspaceMatches(context)) return;
      suppliers = loaded;
      tenantSuppliers = tenant;
    } catch (e) {
      suppliersError = e is AppException
          ? e.message
          : 'Unable to load suppliers.';
    } finally {
      suppliersLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createSupplier({
    required String name,
    required String mobile,
    required String contactPerson,
    required String email,
    required String whatsapp,
    required String gstin,
    required String pan,
    required String stateCode,
    required String supplierType,
    required String address,
    required int creditLimit,
    required int paymentTermsDays,
    required int openingBalance,
    required bool preferred,
  }) async {
    AuthSession? session;
    try {
      session = await auth.ensureValidSession();
    } catch (e) {
      error = e is AppException ? e.message : 'Please sign in again.';
      notifyListeners();
      return false;
    }
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageSuppliers() ||
        businesses
            .where(
              (b) =>
                  b.businessId == context?.businessId &&
                  b.ownerUid == context?.ownerUid &&
                  b.isActive,
            )
            .isEmpty) {
      error = 'You are not authorized to create suppliers.';
      notifyListeners();
      return false;
    }
    if (name.trim().length < 2 ||
        (mobile.trim().isNotEmpty &&
            AppValidators.indianPhone(mobile) != null) ||
        (email.trim().isNotEmpty && AppValidators.email(email) != null) ||
        creditLimit < 0 ||
        openingBalance < 0 ||
        paymentTermsDays < 0) {
      error = 'Check the supplier details and try again.';
      notifyListeners();
      return false;
    }
    if (gstin.trim().isNotEmpty && AppValidators.gstin(gstin) != null) {
      error = 'Enter a valid GSTIN or leave it blank.';
      notifyListeners();
      return false;
    }
    supplierSaving = true;
    error = '';
    notifyListeners();
    try {
      await supplierRepository.createSupplier(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        name: name,
        mobile: mobile.trim().isEmpty
            ? ''
            : AppValidators.normalizeIndianPhone(mobile),
        contactPerson: contactPerson,
        email: email,
        whatsapp: whatsapp.trim().isEmpty
            ? ''
            : AppValidators.normalizeIndianPhone(whatsapp),
        gstin: AppValidators.normalizeGstin(gstin),
        pan: pan,
        stateCode: stateCode,
        supplierType: supplierType,
        address: address,
        creditLimit: creditLimit,
        paymentTermsDays: paymentTermsDays,
        openingBalance: openingBalance,
        preferred: preferred,
        createdBy: context.uid,
        token: session.idToken,
      );
      await loadSuppliers();
      return true;
    } catch (e) {
      error = _supplierError(e);
      notifyListeners();
      return false;
    } finally {
      supplierSaving = false;
      notifyListeners();
    }
  }

  Future<SupplierBusinessModel?> getSupplierBusinessTerms(
    String supplierId,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageSuppliers()) {
      return null;
    }
    try {
      return await supplierRepository.getSupplierBusiness(
        context!.ownerUid,
        context.businessId!,
        supplierId,
        session.idToken,
      );
    } on AppException catch (exception) {
      error = exception.message;
      notifyListeners();
      return null;
    } catch (_) {
      error = 'Unable to load supplier business terms.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateSupplier({
    required String supplierId,
    required String name,
    required String mobile,
    required String contactPerson,
    required String email,
    required String whatsapp,
    required String gstin,
    required String pan,
    required String stateCode,
    required String supplierType,
    required String address,
    required int creditLimit,
    required int paymentTermsDays,
    required bool preferred,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageSuppliers() ||
        businesses
            .where(
              (business) =>
                  business.businessId == context?.businessId &&
                  business.ownerUid == context?.ownerUid &&
                  business.isActive,
            )
            .isEmpty) {
      error = 'You are not authorized to edit suppliers.';
      notifyListeners();
      return false;
    }
    if (name.trim().length < 2 ||
        (mobile.trim().isNotEmpty &&
            AppValidators.indianPhone(mobile) != null) ||
        (email.trim().isNotEmpty && AppValidators.email(email) != null) ||
        creditLimit < 0 ||
        paymentTermsDays < 0) {
      error = 'Check the supplier details and try again.';
      notifyListeners();
      return false;
    }
    if (gstin.trim().isNotEmpty && AppValidators.gstin(gstin) != null) {
      error = 'Enter a valid GSTIN or leave it blank.';
      notifyListeners();
      return false;
    }

    supplierSaving = true;
    error = '';
    notifyListeners();
    try {
      await supplierRepository.updateSupplier(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        supplierId: supplierId,
        name: name,
        mobile: mobile.trim().isEmpty
            ? ''
            : AppValidators.normalizeIndianPhone(mobile),
        contactPerson: contactPerson,
        email: email,
        whatsapp: whatsapp.trim().isEmpty
            ? ''
            : AppValidators.normalizeIndianPhone(whatsapp),
        gstin: AppValidators.normalizeGstin(gstin),
        pan: pan,
        stateCode: stateCode,
        supplierType: supplierType,
        address: address,
        creditLimit: creditLimit,
        paymentTermsDays: paymentTermsDays,
        preferred: preferred,
        updatedBy: context.uid,
        token: session.idToken,
      );
      await loadSuppliers();
      return true;
    } catch (e) {
      error = _supplierError(e);
      notifyListeners();
      return false;
    } finally {
      supplierSaving = false;
      notifyListeners();
    }
  }

  Future<bool> setSupplierActive(String supplierId, bool isActive) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageSuppliers()) {
      error = 'You are not authorized to update suppliers.';
      notifyListeners();
      return false;
    }
    supplierSaving = true;
    error = '';
    notifyListeners();
    try {
      await supplierRepository.updateSupplierStatus(
        tenantId: context!.ownerUid,
        supplierId: supplierId,
        isActive: isActive,
        updatedBy: context.uid,
        token: session.idToken,
      );
      await loadSuppliers();
      return true;
    } catch (e) {
      error = _supplierError(e);
      notifyListeners();
      return false;
    } finally {
      supplierSaving = false;
      notifyListeners();
    }
  }

  Future<bool> linkSupplier({
    required String supplierId,
    required int creditLimit,
    required int paymentTermsDays,
    required int openingBalance,
    bool preferred = false,
  }) async {
    AuthSession? session;
    try {
      session = await auth.ensureValidSession();
    } catch (e) {
      error = e is AppException ? e.message : 'Please sign in again.';
      notifyListeners();
      return false;
    }
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        !canManageSuppliers()) {
      return false;
    }
    supplierSaving = true;
    error = '';
    notifyListeners();
    try {
      await supplierRepository.linkExistingSupplier(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        supplierId: supplierId,
        creditLimit: creditLimit,
        paymentTermsDays: paymentTermsDays,
        openingBalance: openingBalance,
        preferred: preferred,
        userId: context.uid,
        token: session.idToken,
      );
      await loadSuppliers();
      return true;
    } catch (e) {
      error = _supplierError(e);
      notifyListeners();
      return false;
    } finally {
      supplierSaving = false;
      notifyListeners();
    }
  }

  Future<void> loadPurchases() async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !canManagePurchases()) {
      purchasesError = 'Select an outlet and ensure you have purchase access.';
      notifyListeners();
      return;
    }
    purchasesLoading = true;
    purchasesError = null;
    notifyListeners();
    try {
      final values = await Future.wait([
        purchaseRepository.getProductsForBusiness(
          context!.businessId!,
          session.idToken,
          tenantId: context.ownerUid,
          outletId: context.outletId!,
        ),
        purchaseRepository.getBills(
          tenantId: context.ownerUid,
          businessId: context.businessId!,
          outletId: context.outletId!,
          token: session.idToken,
        ),
        supplierRepository.getForBusiness(
          context.ownerUid,
          context.businessId!,
          session.idToken,
        ),
      ]);
      if (!_workspaceMatches(context)) return;
      purchaseProducts = values[0] as List<ProductVariantModel>;
      purchaseBills = values[1] as List<PurchaseBillModel>;
      suppliers = values[2] as List<SupplierModel>;
    } catch (e) {
      purchasesError = e is AppException
          ? e.message
          : 'Unable to load purchases.';
    } finally {
      purchasesLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createPurchaseDraft({
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime purchaseDate,
    required String placeOfSupplyStateCode,
    required int discountAmount,
    required int chargesAmount,
    required int roundOff,
    required List<PurchaseBillItemModel> items,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    final business = businesses.where(
      (item) => item.businessId == context?.businessId,
    );
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        business.isEmpty ||
        !canManagePurchases()) {
      error = 'You are not authorized to create purchases in this outlet.';
      notifyListeners();
      return false;
    }
    purchaseSaving = true;
    error = '';
    notifyListeners();
    try {
      await purchaseRepository.createDraft(
        tenantId: context!.ownerUid,
        businessId: context.businessId!,
        outletId: context.outletId!,
        supplierId: supplierId,
        supplierInvoiceNumber: supplierInvoiceNumber,
        invoiceDate: invoiceDate,
        purchaseDate: purchaseDate,
        purchaseType: 'DIRECT',
        placeOfSupplyStateCode: placeOfSupplyStateCode,
        businessStateCode: _stateCode(
          business.first.gstin,
          business.first.gstState,
        ),
        discountAmount: discountAmount,
        chargesAmount: chargesAmount,
        roundOff: roundOff,
        items: items,
        createdBy: context.uid,
        token: session.idToken,
      );
      await loadPurchases();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to create purchase draft.';
      notifyListeners();
      return false;
    } finally {
      purchaseSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updatePurchaseDraft({
    required PurchaseBillModel bill,
    required String supplierId,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime purchaseDate,
    required String placeOfSupplyStateCode,
    required int discountAmount,
    required int chargesAmount,
    required int roundOff,
    required List<PurchaseBillItemModel> items,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.outletId == null ||
        !canManagePurchases() ||
        bill.status != 'DRAFT') {
      error = 'Only an editable draft in the current outlet can be updated.';
      notifyListeners();
      return false;
    }
    purchaseSaving = true;
    error = '';
    notifyListeners();
    try {
      final business = businesses
          .where((b) => b.businessId == bill.businessId)
          .firstOrNull;
      if (business == null) {
        throw const AppException('Purchase business was not found.');
      }
      await purchaseRepository.updateDraft(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        outletId: bill.outletId,
        billId: bill.purchaseBillId,
        supplierId: supplierId,
        supplierInvoiceNumber: supplierInvoiceNumber,
        invoiceDate: invoiceDate,
        purchaseDate: purchaseDate,
        placeOfSupplyStateCode: placeOfSupplyStateCode,
        businessStateCode: _stateCode(business.gstin, business.gstState),
        discountAmount: discountAmount,
        chargesAmount: chargesAmount,
        roundOff: roundOff,
        items: items,
        updatedBy: context.uid,
        token: session.idToken,
      );
      await loadPurchases();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to update purchase draft.';
      notifyListeners();
      return false;
    } finally {
      purchaseSaving = false;
      notifyListeners();
    }
  }

  Future<bool> correctPurchaseMetadata({
    required PurchaseBillModel bill,
    required String reason,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime purchaseDate,
    required Map<String, Map<String, dynamic>> lineMetadata,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.outletId != bill.outletId ||
        !canManagePurchases()) {
      return false;
    }
    purchaseSaving = true;
    error = '';
    notifyListeners();
    try {
      await purchaseRepository.correctApprovedMetadata(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        outletId: bill.outletId,
        billId: bill.purchaseBillId,
        reason: reason,
        correctedByUid: context.uid,
        supplierInvoiceNumber: supplierInvoiceNumber,
        invoiceDate: invoiceDate,
        purchaseDate: purchaseDate,
        lineMetadata: lineMetadata,
        token: session.idToken,
      );
      await loadPurchases();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to correct purchase metadata.';
      notifyListeners();
      return false;
    } finally {
      purchaseSaving = false;
      notifyListeners();
    }
  }

  Future<Map<String, int>?> loadPurchasePaymentReleasePreview(
    PurchaseBillModel bill,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.outletId != bill.outletId ||
        !canManagePurchases()) {
      return null;
    }
    try {
      return await purchaseRepository.getPaymentReleasePreview(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        purchaseId: bill.purchaseBillId,
        supplierBusinessId: bill.supplierBusinessId,
        token: session.idToken,
      );
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to verify the purchase payment allocation.';
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, Map<String, dynamic>>>
  loadAdvancedPurchaseCorrectionContext(PurchaseBillModel bill) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.outletId != bill.outletId ||
        !canManagePurchases()) {
      return {
        for (final item in bill.items)
          item.goodsReceiptItemId: {
            'verified': false,
            'blockedReason':
                'Purchase access or outlet context is unavailable.',
            'receivedBaseQuantity': item.baseQuantity,
            'consumedBaseQuantity': 0,
            'availableBaseQuantity': 0,
            'stockQuantityOnHand': 0,
          },
      };
    }
    try {
      return await purchaseRepository.getAdvancedCorrectionContext(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        outletId: bill.outletId,
        bill: bill,
        token: session.idToken,
      );
    } catch (_) {
      return {
        for (final item in bill.items)
          item.goodsReceiptItemId: {
            'verified': false,
            'blockedReason':
                'Local batch movement history could not be verified.',
            'receivedBaseQuantity': item.baseQuantity,
            'consumedBaseQuantity': 0,
            'availableBaseQuantity': 0,
            'stockQuantityOnHand': 0,
          },
      };
    }
  }

  Future<List<PurchaseCorrectionModel>> loadPurchaseCorrections(
    PurchaseBillModel bill,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.outletId != bill.outletId ||
        !canManagePurchases()) {
      return const [];
    }
    try {
      return await purchaseRepository.getCorrections(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        outletId: bill.outletId,
        purchaseId: bill.purchaseBillId,
        token: session.idToken,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> loadPurchasePaymentHistory(
    PurchaseBillModel bill,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.outletId != bill.outletId ||
        !canManagePurchases()) {
      return const [];
    }
    try {
      return await purchaseRepository.getPaymentHistory(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        outletId: bill.outletId,
        purchaseId: bill.purchaseBillId,
        token: session.idToken,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<bool> approvePurchase(String billId) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null || context == null || !canManagePurchases()) {
      return false;
    }
    purchaseSaving = true;
    error = '';
    notifyListeners();
    try {
      await purchaseRepository.approveDirectBill(
        tenantId: context.ownerUid,
        billId: billId,
        userId: context.uid,
        token: session.idToken,
      );
      await loadPurchases();
      return true;
    } catch (e) {
      error = e is AppException ? e.message : 'Unable to approve purchase.';
      notifyListeners();
      return false;
    } finally {
      purchaseSaving = false;
      notifyListeners();
    }
  }

  Future<bool> recordSupplierPayment({
    required PurchaseBillModel bill,
    required int amount,
    required String paymentMode,
    required String reference,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null || context?.outletId == null || !canManagePurchases()) {
      return false;
    }
    purchaseSaving = true;
    error = '';
    notifyListeners();
    try {
      await purchaseRepository.recordPayment(
        tenantId: context!.ownerUid,
        businessId: bill.businessId,
        outletId: context.outletId!,
        supplierId: bill.supplierId,
        supplierBusinessId: bill.supplierBusinessId,
        purchaseBillId: bill.purchaseBillId,
        amount: amount,
        paymentMode: paymentMode,
        transactionReference: reference,
        userId: context.uid,
        token: session.idToken,
      );
      await loadPurchases();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to record supplier payment.';
      notifyListeners();
      return false;
    } finally {
      purchaseSaving = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> loadSupplierFinancialSnapshot(
    String supplierId,
  ) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !canManageSuppliers()) {
      return null;
    }
    try {
      final relation = await supplierRepository.getSupplierBusiness(
        context!.ownerUid,
        context.businessId!,
        supplierId,
        session.idToken,
      );
      return await supplierRepository.getSupplierFinancialSnapshot(
        tenantId: context.ownerUid,
        businessId: context.businessId!,
        outletId: context.outletId!,
        supplierBusinessId: relation.supplierBusinessId,
        token: session.idToken,
      );
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to load supplier advance details.';
      notifyListeners();
      return null;
    }
  }

  Future<bool> recordSupplierRefund({
    required String supplierId,
    required int amount,
    required DateTime refundDate,
    required String paymentMode,
    required String referenceNo,
    required String reason,
    required String notes,
    required String requestId,
  }) async {
    final session = await _getUsableSession();
    final context = appContext;
    if (session == null ||
        context?.businessId == null ||
        context?.outletId == null ||
        !canManageSuppliers()) {
      return false;
    }
    supplierSaving = true;
    error = '';
    notifyListeners();
    try {
      final relation = await supplierRepository.getSupplierBusiness(
        context!.ownerUid,
        context.businessId!,
        supplierId,
        session.idToken,
      );
      await supplierRepository.recordSupplierRefund(
        tenantId: context.ownerUid,
        businessId: context.businessId!,
        outletId: context.outletId!,
        supplierId: supplierId,
        supplierBusinessId: relation.supplierBusinessId,
        amount: amount,
        refundDate: refundDate,
        paymentMode: paymentMode,
        referenceNo: referenceNo,
        reason: reason,
        notes: notes,
        createdByUid: context.uid,
        requestId: requestId,
        token: session.idToken,
      );
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to record supplier refund.';
      notifyListeners();
      return false;
    } finally {
      supplierSaving = false;
      notifyListeners();
    }
  }

  String _stateCode(String? gstin, String? fallback) {
    final code = gstin?.trim();
    if (code != null && code.length >= 2) return code.substring(0, 2);
    return fallback?.trim() ?? '';
  }

  String _supplierError(Object error) {
    if (error is AppException &&
        (error.code == '403' ||
            error.code == 'permission-denied' ||
            error.message.toLowerCase().contains(
              'missing or insufficient permissions',
            ))) {
      final detail = error.message.trim();
      final status = error.code == '403'
          ? 'HTTP 403'
          : error.code ?? 'permission-denied';
      return 'Firestore rejected a supplier operation for Firebase project '
          '"${EnvironmentConfig.projectId}" '
          '($status): '
          '$detail. The catch-all rule you shared allows reads and writes, so '
          'verify it is Published for this project’s (default) database. If it '
          'is, check whether App Check enforcement is enabled; REST requests '
          'from this app may be missing an App Check token.';
    }
    return error is AppException ? error.message : 'Unable to save supplier.';
  }

  Future<bool> createEmployee({
    required String name,
    required String mobile,
    required String email,
    required String password,
    required String employeeCode,
    required List<String> businessIds,
    required List<String> outletIds,
    required List<String> roleIds,
    required List<String> permissionIds,
    required String status,
  }) async {
    final session = await _getUsableSession();
    final ownerUid = user?.uid;
    if (session == null || ownerUid == null || user?.accountType != 'owner') {
      return false;
    }
    error = '';
    final normalizedEmail = AppValidators.normalizeEmail(email);
    final phoneError = AppValidators.indianPhone(mobile);
    if (name.trim().replaceAll(RegExp(r'\s'), '').length < 2 ||
        phoneError != null ||
        AppValidators.email(email) != null ||
        password.length < 6 ||
        businessIds.isEmpty ||
        outletIds.isEmpty ||
        roleIds.isEmpty) {
      error = 'Check the required employee details and selections.';
      notifyListeners();
      return false;
    }
    if (employeeCode.contains('/') || employeeCode.trim().length > 40) {
      error =
          'Employee code must be 40 characters or fewer and cannot contain /. ';
      notifyListeners();
      return false;
    }
    final activePermissionIds = activePermissions
        .where((permission) => permission.isActive)
        .map((permission) => permission.permissionId)
        .toSet();
    if (activePermissionIds.isNotEmpty &&
        !permissionIds.every(
          (id) => activePermissionIds.any(
            (activeId) => PermissionIdMatcher.matches(id, activeId),
          ),
        )) {
      error = 'A selected permission is no longer available.';
      notifyListeners();
      return false;
    }
    employeeSaving = true;
    notifyListeners();
    try {
      await employeesRepository.validateNewEmployee(
        ownerUid: ownerUid,
        name: name,
        email: normalizedEmail,
        mobile: AppValidators.normalizeIndianPhone(mobile),
        employeeCode: employeeCode,
        businessIds: businessIds,
        outletIds: outletIds,
        roleIds: roleIds,
        permissionIds: permissionIds,
        token: session.idToken,
        activeRoles: activeRoles,
      );
      final identity = await auth.createEmployeeIdentity(
        normalizedEmail,
        password,
      );
      final normalizedMobile = AppValidators.normalizeIndianPhone(mobile);
      await users.createEmployeeProfile(
        uid: identity.uid,
        name: name.trim(),
        email: normalizedEmail,
        mobile: normalizedMobile,
        isActive: status == 'active',
        token: session.idToken,
      );
      await employeesRepository.createEmployee(
        uid: identity.uid,
        ownerUid: ownerUid,
        name: name,
        email: normalizedEmail,
        mobile: normalizedMobile,
        employeeCode: employeeCode,
        businessIds: businessIds,
        outletIds: outletIds,
        roleIds: roleIds,
        permissionIds: permissionIds,
        status: status,
        activeRoles: activeRoles,
        token: session.idToken,
      );
      await loadEmployees();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to create the employee. Please try again.';
      notifyListeners();
      return false;
    } finally {
      employeeSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateEmployee({
    required EmployeeModel employee,
    required String name,
    required String mobile,
    required String employeeCode,
    required List<String> businessIds,
    required List<String> outletIds,
    required List<String> roleIds,
    required List<String> permissionIds,
    required String status,
  }) async {
    final session = await _getUsableSession();
    final ownerUid = user?.uid;
    if (session == null ||
        ownerUid == null ||
        user?.accountType != 'owner' ||
        employee.ownerUid != ownerUid) {
      return false;
    }
    error = '';
    final phoneError = AppValidators.indianPhone(mobile);
    if (name.trim().replaceAll(RegExp(r'\s'), '').length < 2 ||
        phoneError != null ||
        businessIds.isEmpty ||
        outletIds.isEmpty ||
        roleIds.isEmpty ||
        !const {'active', 'inactive'}.contains(status)) {
      error = 'Check the required employee details and selections.';
      notifyListeners();
      return false;
    }
    final activePermissionIds = activePermissions
        .where((permission) => permission.isActive)
        .map((permission) => permission.permissionId)
        .toSet();
    if (activePermissionIds.isNotEmpty &&
        !permissionIds.every(
          (id) => activePermissionIds.any(
            (activeId) => PermissionIdMatcher.matches(id, activeId),
          ),
        )) {
      error = 'A selected permission is no longer available.';
      notifyListeners();
      return false;
    }
    employeeSaving = true;
    notifyListeners();
    try {
      final normalizedMobile = AppValidators.normalizeIndianPhone(mobile);
      await employeesRepository.validateNewEmployee(
        ownerUid: ownerUid,
        name: name,
        email: employee.email,
        mobile: normalizedMobile,
        employeeCode: employeeCode,
        businessIds: businessIds,
        outletIds: outletIds,
        roleIds: roleIds,
        permissionIds: permissionIds,
        token: session.idToken,
        activeRoles: activeRoles,
        excludeUid: employee.uid,
      );
      await users.updateEmployeeProfile(
        uid: employee.uid,
        email: employee.email,
        name: name.trim(),
        mobile: normalizedMobile,
        isActive: status == 'active',
        token: session.idToken,
      );
      final updated = await employeesRepository.updateEmployee(
        employee: employee,
        ownerUid: ownerUid,
        name: name,
        mobile: normalizedMobile,
        employeeCode: employeeCode,
        businessIds: businessIds,
        outletIds: outletIds,
        roleIds: roleIds,
        permissionIds: permissionIds,
        status: status,
        activeRoles: activeRoles,
        token: session.idToken,
      );
      employees = employees
          .map((item) => item.uid == updated.uid ? updated : item)
          .toList();
      notifyListeners();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to update the employee. Please try again.';
      notifyListeners();
      return false;
    } finally {
      employeeSaving = false;
      notifyListeners();
    }
  }

  Future<bool> setEmployeeActive(EmployeeModel employee, bool isActive) async {
    final session = await _getUsableSession();
    final ownerUid = user?.uid;
    if (session == null ||
        user?.accountType != 'owner' ||
        ownerUid == null ||
        employee.ownerUid != ownerUid) {
      error = 'Only the employee owner can change account status.';
      notifyListeners();
      return false;
    }
    employeeSaving = true;
    error = '';
    notifyListeners();
    try {
      await employeesRepository.updateEmployeeStatus(
        employee: employee,
        ownerUid: ownerUid,
        isActive: isActive,
        token: session.idToken,
      );
      await loadEmployees();
      return true;
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to update employee status.';
      notifyListeners();
      return false;
    } finally {
      employeeSaving = false;
      notifyListeners();
    }
  }

  Future<GSTVerificationResult> verifyGSTIN(String gstin) =>
      gstVerificationService.verifyGSTIN(AppValidators.normalizeGstin(gstin));

  Future<void> openCreateBusiness() async {
    if (user?.accountType != 'owner' || await _getUsableSession() == null) {
      return;
    }
    status = AppStatus.createBusiness;
    error = '';
    gstVerificationResult = null;
    notifyListeners();
    await loadBusinessTypes();
  }

  Future<void> openCreateOutlet() async {
    if (!canCreateOutlet() || appContext?.businessId == null) return;
    status = AppStatus.createOutlet;
    error = '';
    gstVerificationResult = null;
    notifyListeners();
    await loadBusinessSubTypes();
  }

  Future<void> createBusiness({
    required String businessName,
    required String businessTypeId,
    required String email,
    required String phone,
    required String address,
    String? gstin,
  }) async {
    final session = await _getUsableSession();
    if (session == null || user?.accountType != 'owner') return;
    error = '';
    if (AppValidators.businessName(businessName) != null ||
        AppValidators.email(email) != null ||
        AppValidators.indianPhone(phone) != null ||
        address.trim().isEmpty) {
      error = 'Check the required business details and try again.';
      notifyListeners();
      return;
    }
    final typeMatches = businessTypes.where(
      (type) => type.id == businessTypeId && type.isActive,
    );
    if (typeMatches.isEmpty) {
      error = 'Select an active business type.';
      notifyListeners();
      return;
    }
    if (gstin != null &&
        gstin.trim().isNotEmpty &&
        AppValidators.gstin(gstin) != null) {
      error = 'Enter a valid GSTIN or leave the field blank.';
      notifyListeners();
      return;
    }
    businessSaving = true;
    notifyListeners();
    try {
      final business = await businessesRepository.createBusiness(
        ownerUid: session.uid,
        businessName: businessName,
        normalizedBusinessName: AppValidators.normalizeBusinessName(
          businessName,
        ),
        businessType: typeMatches.first,
        email: AppValidators.normalizeEmail(email),
        phone: AppValidators.normalizeIndianPhone(phone),
        address: address,
        gstin: gstin == null || gstin.trim().isEmpty
            ? null
            : AppValidators.normalizeGstin(gstin),
        gstinVerified: false,
        token: session.idToken,
      );
      businesses = [...businesses, business];
      await selectBusiness(business.businessId);
    } catch (e) {
      error = e is AppException
          ? e.message
          : 'Unable to create the business. Please try again.';
      notifyListeners();
    } finally {
      businessSaving = false;
      notifyListeners();
    }
  }

  Future<void> createOutlet({
    required String outletName,
    required String outletTypeId,
    required String address,
    required String contactNumber,
    String? gstin,
  }) async {
    final session = await _getUsableSession();
    final businessId = appContext?.businessId;
    if (session == null || businessId == null || !canCreateOutlet()) {
      return;
    }
    error = '';
    final businessesForContext = businesses.where(
      (item) => item.businessId == businessId,
    );
    if (businessesForContext.isEmpty ||
        outletName.trim().isEmpty ||
        address.trim().isEmpty ||
        AppValidators.indianPhone(contactNumber) != null) {
      error = 'Check the required outlet details and try again.';
      notifyListeners();
      return;
    }
    final business = businessesForContext.first;
    final subTypes = businessSubTypes.where(
      (type) =>
          type.id == outletTypeId &&
          type.isActive &&
          type.businessTypeId == business.businessTypeId,
    );
    if (subTypes.isEmpty) {
      error = 'Select a valid outlet type for this business.';
      notifyListeners();
      return;
    }
    if (gstin != null &&
        gstin.trim().isNotEmpty &&
        AppValidators.gstin(gstin) != null) {
      error = 'Enter a valid GSTIN or leave the field blank.';
      notifyListeners();
      return;
    }
    outletSaving = true;
    notifyListeners();
    try {
      final outlet = await outletsRepository.createOutlet(
        businessId: businessId,
        ownerUid: appContext!.ownerUid,
        createdBy: session.uid,
        outletName: outletName,
        businessTypeId: business.businessTypeId,
        outletType: subTypes.first,
        address: address,
        contactNumber: AppValidators.normalizeIndianPhone(contactNumber),
        gstin: gstin == null || gstin.trim().isEmpty
            ? null
            : AppValidators.normalizeGstin(gstin),
        gstinVerified: false,
        token: session.idToken,
      );
      if (user?.accountType == 'owner') {
        outlets = [
          ...outlets.where((existing) => existing.outletId != outlet.outletId),
          outlet,
        ];
        await selectOutlet(outlet.outletId);
      } else {
        // Creating an Outlet does not grant an employee access to it.
        status = AppStatus.dashboard;
        notifyListeners();
      }
    } catch (e) {
      debugPrint(
        'Outlet create failed: tenantId=${appContext?.ownerUid}, '
        'businessId=$businessId, actorUid=${session.uid}, error=$e',
      );
      error = e is AppException
          ? e.message
          : 'Unable to create the outlet. Please try again.';
      notifyListeners();
    } finally {
      outletSaving = false;
      notifyListeners();
    }
  }

  void openBusinessSelector() {
    status = AppStatus.businessSelector;
    notifyListeners();
  }

  void cancelCreation() {
    error = '';
    gstVerificationResult = null;
    status = appContext?.businessId == null
        ? AppStatus.businessSelector
        : AppStatus.outletSelector;
    notifyListeners();
  }

  Future<void> openOutletSelector() async {
    final businessId = appContext?.businessId;
    final session = await _getUsableSession();
    if (businessId == null || session == null) return;
    status = AppStatus.loading;
    notifyListeners();
    try {
      outlets = user?.accountType == 'employee'
          ? await employeesRepository.getEmployeeOutlets(
              employee!,
              businessId,
              session.idToken,
            )
          : await outletsRepository.getOutletsByBusinessId(
              businessId,
              session.idToken,
              tenantId: appContext!.ownerUid,
            );
      status = AppStatus.outletSelector;
    } catch (e) {
      error = e is AppException ? e.message : 'Unable to load outlets.';
      status = AppStatus.denied;
    }
    notifyListeners();
  }

  Future<void> _deny(String message) async {
    error = message;
    status = AppStatus.denied;
    notifyListeners();
  }

  Future<bool> _saveContext({String? businessId, String? outletId}) async {
    try {
      await auth.saveContext(businessId: businessId, outletId: outletId);
      return true;
    } on AppException catch (exception) {
      error = exception.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> _clearSession() => auth.logout();

  Future<void> logout() async {
    offline?.logout();
    try {
      await _clearSession();
    } on AppException catch (exception) {
      error = exception.message;
      notifyListeners();
      return;
    }
    user = null;
    employee = null;
    role = null;
    appContext = null;
    businesses = [];
    outlets = [];
    businessTypes = [];
    businessSubTypes = [];
    dashboardSummary = null;
    dashboardError = null;
    error = '';
    status = AppStatus.login;
    notifyListeners();
  }
}

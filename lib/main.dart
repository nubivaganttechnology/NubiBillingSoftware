import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'core/network/api_client.dart';
import 'core/storage/token_storage.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/business_repository.dart';
import 'data/repositories/business_sub_type_repository.dart';
import 'data/repositories/business_type_repository.dart';
import 'data/repositories/dashboard_repository.dart';
import 'data/repositories/employee_repository.dart';
import 'data/repositories/outlet_repository.dart';
import 'data/repositories/permission_repository.dart';
import 'data/repositories/purchase_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/repositories/role_repository.dart';
import 'data/repositories/supplier_repository.dart';
import 'data/repositories/billing_repository.dart';
import 'data/repositories/customer_repository.dart';
import 'data/repositories/expense_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'data/repositories/storage_repository.dart';
import 'data/repositories/staff_salary_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/services/app_config_service.dart';
import 'data/services/firebase_auth_rest_service.dart';
import 'data/services/error_analytics_service.dart';
import 'data/services/firestore_rest_service.dart';
import 'data/services/offline_firestore_service.dart';
import 'data/local/local_database.dart';
import 'data/sync/sync_engine.dart';
import 'data/sync/connectivity_service.dart';
import 'data/services/gst_verification_service.dart';
import 'domain/services/storage_service.dart';
import 'l10n/app_localizations.dart';
import 'presentation/app_controller.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

String? detectHistoricalWindowsDatabaseLocation({
  String? workingDirectory,
  String? targetDirectory,
}) {
  if (kIsWeb) return null;
  try {
    final base = workingDirectory ?? Directory.current.path;
    final legacyDir = Directory(
      p.join(base, '.dart_tool', 'sqflite_common_ffi', 'databases'),
    );
    if (legacyDir.existsSync()) {
      final legacyDbs = legacyDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      if (legacyDbs.isNotEmpty) {
        final target = targetDirectory ?? '(target permanent directory)';
        final message =
            '[storage] NOTICE: Detected ${legacyDbs.length} database(s) in historical location (${legacyDir.path}). '
            'Existing databases are preserved and NOT automatically moved or deleted. '
            'To migrate historical data to permanent storage ($target), copy the database files while the app is closed.';
        debugPrint(message);
        return message;
      }
    }
  } catch (_) {
    // Non-intrusive warning check must never interrupt startup.
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiClient();
  final storage = TokenStorageService();
  final remote = FirestoreRestService(api);
  final auth = AuthRepository(FirebaseAuthRestService(api), storage);
  final connectivity = ConnectivityService();
  auth.networkAvailable = () => connectivity.available;
  final errorAnalytics = ErrorAnalyticsService(
    remote,
    sessionProvider: () async => (await auth.ensureValidSession())?.idToken,
  );
  ErrorAnalyticsService.instance = errorAnalytics;
  final sync = SyncEngine(
    remote,
    connectivity,
    sessionProvider: auth.ensureValidSession,
    errorAnalytics: errorAnalytics,
  );
  LocalDatabase localDatabase;
  if (kIsWeb) {
    localDatabase = LocalDatabase(factory: databaseFactoryFfiWeb);
  } else if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final dbDir = Directory(p.join(appSupportDir.path, 'databases'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }
      detectHistoricalWindowsDatabaseLocation(
        targetDirectory: dbDir.path,
      );
      localDatabase = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: dbDir.path,
      );
    } catch (e, stack) {
      debugPrint('[startup] CRITICAL: Failed to initialize SQLite storage directory: $e\n$stack');
      rethrow;
    }
  } else {
    localDatabase = LocalDatabase();
  }
  final firestore = OfflineFirestoreService(localDatabase, remote, sync);
  await sync.start();
  final businesses = BusinessRepository(firestore);
  final outlets = OutletRepository(firestore);
  final suppliers = SupplierRepository(firestore, firestore);
  final storageService = StorageService(
    StorageRepository(firestore, firestore),
  );
  final controller = AppController(
    AppConfigService(firestore),
    auth,
    UserRepository(firestore),
    businesses,
    DashboardRepository(firestore),
    outlets,
    EmployeeRepository(firestore, businesses, outlets, firestore),
    RoleRepository(firestore),
    PermissionRepository(firestore),
    suppliers,
    PurchaseRepository(firestore, suppliers, firestore),
    ProductRepository(firestore, firestore),
    BusinessTypeRepository(firestore),
    BusinessSubTypeRepository(firestore),
    UnconfiguredGSTVerificationService(),
    storageService,
    offline: firestore,
    sync: sync,
    billingRepository: BillingRepository(firestore),
    customerRepository: CustomerRepository(firestore),
    expenseRepository: ExpenseRepository(firestore),
    staffSalaryRepository: StaffSalaryRepository(firestore, firestore),
    settingsRepository: SettingsRepository(firestore),
  );
  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const ShreeBalajiApp(),
    ),
  );
}

class ShreeBalajiApp extends StatefulWidget {
  const ShreeBalajiApp({super.key});
  @override
  State<ShreeBalajiApp> createState() => _ShreeBalajiAppState();
}

class _ShreeBalajiAppState extends State<ShreeBalajiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<AppController>().start(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<AppController>().sync?.onResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final controller = c.watch<AppController>();
    return MaterialApp(
      title: 'NubiBill ERP',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: controller.currentLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer<AppController>(
        builder: (_, x, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: AppRouter(key: ValueKey(x.status), controller: x),
        ),
      ),
    );
  }
}

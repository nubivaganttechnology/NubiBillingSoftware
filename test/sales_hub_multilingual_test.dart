import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/data/models/sales_invoice_model.dart';
import 'package:testflutter/data/repositories/sales_repository.dart';
import 'package:testflutter/data/repositories/settings_repository.dart';
import 'package:testflutter/data/services/firestore_data_service.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/sales/sales_entry_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class FakeOfflineFirestoreService extends Fake implements OfflineFirestoreService {
  FakeOfflineFirestoreService({List<Map<String, dynamic>>? docs}) : _docs = docs;
  final List<Map<String, dynamic>>? _docs;

  @override
  Future<void> patchDocument(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    String? idToken,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> queryDocuments({
    required String collection,
    required List<FirestoreFilter> filters,
    String? orderBy,
    int? limit,
    bool descending = false,
    String? idToken,
  }) async {
    if (_docs != null) return _docs!;
    return [
      <String, dynamic>{
        'name': 'projects/test/databases/(default)/documents/invoices/INV-1001',
        'fields': FirestoreRestService.encodeFields({
          'invoiceNumber': 'INV-1001',
          'customerName': 'Rahul Sharma',
          'customerPhone': '9876543210',
          'grandTotalPaise': 150000, // ₹1,500.00
          'paidPaise': 100000, // ₹1,000.00
          'dueAmount': 50000, // ₹500.00
          'status': 'PENDING',
          'invoiceDate': '2026-10-20T10:00:00Z',
          'createdAt': '2026-10-20T10:00:00Z',
          'customerId': 'cust-1',
        }),
      },
      <String, dynamic>{
        'name': 'projects/test/databases/(default)/documents/invoices/INV-1002',
        'fields': FirestoreRestService.encodeFields({
          'invoiceNumber': 'INV-1002',
          'customerName': 'Priya Das',
          'customerPhone': '9830012345',
          'grandTotalPaise': 250000, // ₹2,500.00
          'paidPaise': 250000, // ₹2,500.00
          'dueAmount': 0, // ₹0.00
          'status': 'PAID',
          'invoiceDate': '2026-10-19T14:30:00Z',
          'createdAt': '2026-10-19T14:30:00Z',
          'customerId': 'cust-2',
        }),
      },
    ];
  }
}

class TestSalesController extends EntryController {
  TestSalesController({
    Locale? initialLocale,
    FakeOfflineFirestoreService? offlineService,
  })  : _locale = initialLocale ?? const Locale('en'),
        _fakeOffline = offlineService ?? FakeOfflineFirestoreService();

  Locale _locale;
  final FakeOfflineFirestoreService _fakeOffline;

  @override
  Locale get currentLocale => _locale;

  @override
  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
  }

  @override
  AppContext get appContext => const AppContext(
        uid: 'user-uid',
        accountType: 'owner',
        ownerUid: 'owner-uid',
        businessId: 'bus-1',
        permissions: ['*'],
      );

  @override
  String? get idToken => 'mock-token';

  @override
  OfflineFirestoreService? get offline => _fakeOffline;

  @override
  SettingsRepository? get settingsRepository => null;

  @override
  OutletModel get currentOutlet => const OutletModel(
        outletId: 'out-1',
        businessId: 'bus-1',
        ownerUid: 'owner-uid',
        tenantId: 'owner-uid',
        outletName: 'Central Outlet POS',
        outletTypeId: 'retail',
        outletTypeName: 'Retail Counter',
        isActive: true,
      );

  @override
  List<BusinessModel> get businesses => const [
        BusinessModel(
          businessId: 'bus-1',
          ownerUid: 'owner-uid',
          businessName: 'Nubi Corp Retail',
          normalizedBusinessName: 'nubi corp retail',
          businessTypeId: 'retail',
          businessTypeName: 'Retail Store',
          isActive: true,
          gstState: 'West Bengal',
          gstin: '19AAACN0000A1Z5',
        ),
      ];

  @override
  List<ProductModel> get products => [
        ProductModel(
          productId: 'prod-1',
          tenantId: 'owner-uid',
          businessId: 'bus-1',
          name: 'Sigmark WeatherShield Paint',
          brand: 'Sigmark',
          category: 'Paint',
          baseUnitId: 'ltr',
          status: 'ACTIVE',
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
          variants: [
            const ProductVariantModel(
              variantId: 'var-1',
              productId: 'prod-1',
              businessId: 'bus-1',
              name: '1 Litre White',
              baseUnitId: 'ltr',
              sellingPrice: 45000, // ₹450.00
              mrp: 50000,
              defaultGstRateBps: 1800,
              productName: 'Sigmark WeatherShield Paint',
            ),
          ],
        ),
      ];

  @override
  Future<List<ProductVariantModel>> loadSalesVariants() async => [
        const ProductVariantModel(
          variantId: 'var-1',
          productId: 'prod-1',
          businessId: 'bus-1',
          name: '1 Litre White',
          baseUnitId: 'ltr',
          sellingPrice: 45000,
          mrp: 50000,
          defaultGstRateBps: 1800,
          productName: 'Sigmark WeatherShield Paint',
        ),
      ];

  @override
  Future<List<Map<String, dynamic>>> loadSalesCustomers() async => [
        {'customerId': 'cust-1', 'name': 'Rahul Sharma', 'phone': '9876543210'},
        {'customerId': 'cust-2', 'name': 'Priya Das', 'phone': '9830012345'},
      ];

  @override
  Future<List<SalesBatchOption>> loadSalesBatches(
    String productId,
    String variantId,
  ) async => [
        const SalesBatchOption(
          batchId: 'batch-1',
          internalBatchNo: 'BAT-2026-001',
          supplierLotNo: 'LOT-99',
          expiryDate: '2027-12-31',
          storageType: 'OUTLET',
          storageLocationId: 'out-1',
          rackId: 'R1',
          availableBaseQuantity: 100,
          trusted: true,
        ),
      ];

  @override
  Future<String> postSalesInvoice({
    required String invoiceId,
    required DateTime invoiceDate,
    required String? customerId,
    required String? customerName,
    String? chargeToEmployeeId,
    required List<SalesInvoiceLine> lines,
  }) async => invoiceId;
}

Widget createSalesHubApp({
  required TestSalesController controller,
  required Locale locale,
}) {
  return MaterialApp(
    title: 'Sales Hub Test',
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: SalesManagementPage(
      controller: controller,
      onOpenModule: (_) {},
    ),
  );
}

void main() {
  group('Sales Hub Multilingual & Responsive Tests', () {
    testWidgets('Renders Sales Hub in English with 4 KPI cards and zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestSalesController(initialLocale: const Locale('en'));
      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Executive Header & Segmented control
      expect(find.text('Sales Management & Invoicing'), findsOneWidget);
      expect(find.text('Sales Invoices'), findsOneWidget);
      expect(find.text('New Sale'), findsOneWidget);

      // KPI Cards
      expect(find.text('Total Invoices'), findsOneWidget);
      expect(find.text('Total Billed'), findsOneWidget);
      expect(find.text('Total Collected'), findsOneWidget);
      expect(find.text('Outstanding Due'), findsOneWidget);

      // Calculated KPI card values
      expect(find.text('2'), findsOneWidget); // 2 invoices
      expect(find.text('₹4000.00'), findsOneWidget); // ₹4,000.00 Total Billed
      expect(find.text('₹3500.00'), findsOneWidget); // ₹3,500.00 Total Collected
      expect(find.text('₹500.00'), findsWidgets); // ₹500.00 Outstanding Due & In Invoice

      // Filter chips
      expect(find.text('All Bills'), findsOneWidget);
      expect(find.text('Paid'), findsWidgets);
      expect(find.text('Borrow / Pending'), findsOneWidget);
      expect(find.text('Refund / Return'), findsOneWidget);

      // Action buttons
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('View Detail'), findsWidgets);
      expect(find.text('Edit Bill'), findsWidgets);
      expect(find.text('Pay / Settle'), findsOneWidget);
      expect(find.text('UPI QR'), findsOneWidget);
      expect(find.text('Delete Bill'), findsWidgets);
    });

    testWidgets('Renders Sales Hub in Hindi (हिन्दी) accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestSalesController(initialLocale: const Locale('hi'));
      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('hi')),
      );
      await tester.pumpAndSettle();

      // Header in Hindi
      expect(find.text('बिक्री प्रबंधन व इनवॉइसिंग'), findsOneWidget);
      expect(find.text('बिक्री इनवॉइस'), findsOneWidget);
      expect(find.text('नई बिक्री'), findsWidgets);

      // KPI Cards in Hindi
      expect(find.text('कुल इनवॉइस'), findsOneWidget);
      expect(find.text('कुल बिल राशि'), findsOneWidget);
      expect(find.text('कुल प्राप्त'), findsOneWidget);
      expect(find.text('कुल बाकी (उधार)'), findsOneWidget);

      // Filter chips in Hindi
      expect(find.text('सभी बिल'), findsOneWidget);
      expect(find.text('भुगतान प्राप्त'), findsWidgets);
      expect(find.text('उधार / बाकी'), findsOneWidget);
      expect(find.text('रिफंड / वापसी'), findsOneWidget);
    });

    testWidgets('Renders Sales Hub in Bengali (বাংলা) accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestSalesController(initialLocale: const Locale('bn'));
      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('bn')),
      );
      await tester.pumpAndSettle();

      // Header in Bengali
      expect(find.text('বিক্রয় ব্যবস্থাপনা ও ইনভয়েসিং'), findsOneWidget);
      expect(find.text('বিক্রয় ইনভয়েস'), findsOneWidget);
      expect(find.text('নতুন বিক্রয়'), findsWidgets);

      // KPI Cards in Bengali
      expect(find.text('মোট ইনভয়েস'), findsOneWidget);
      expect(find.text('মোট বিলকৃত'), findsOneWidget);
      expect(find.text('মোট সংগৃহীত'), findsOneWidget);
      expect(find.text('মোট বাকি (বকেয়া)'), findsOneWidget);

      // Filter chips in Bengali
      expect(find.text('সকল বিল'), findsOneWidget);
      expect(find.text('পরিশোধিত'), findsWidgets);
      expect(find.text('বাকি / অপেক্ষমাণ'), findsOneWidget);
      expect(find.text('রিফান্ড / ফেরত'), findsOneWidget);
    });

    testWidgets('Toggles seamlessly to New Sale invoice entry page', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestSalesController(initialLocale: const Locale('en'));
      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tap 'New Sale' segment
      await tester.tap(find.text('New Sale').first);
      await tester.pumpAndSettle();

      // Verify SalesEntryPage is rendered
      expect(find.text('Customer & Invoice'), findsWidgets);
      expect(find.text('Sale Items'), findsOneWidget);
      expect(find.text('Add Product / Variant'), findsOneWidget);
      expect(find.text('Invoice Summary'), findsOneWidget);
      expect(find.text('Post & Save Sale'), findsOneWidget);

      // Tap back to 'Sales Invoices'
      await tester.tap(find.text('Sales Invoices'));
      await tester.pumpAndSettle();

      // Verify BillSearchPage is rendered again
      expect(find.text('Total Invoices'), findsOneWidget);
    });

    testWidgets('Renders with zero overflow on Tablet (820px) viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(820, 1180);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestSalesController(initialLocale: const Locale('en'));
      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sales Management & Invoicing'), findsOneWidget);
      expect(find.text('Total Invoices'), findsOneWidget);
    });

    testWidgets('Renders with zero overflow on Mobile (390px) viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestSalesController(initialLocale: const Locale('en'));
      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sales Management & Invoicing'), findsOneWidget);
    });

    testWidgets('Borrow / Pending timeline filters and customer repayment dates in English', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final overdueDate = now.subtract(const Duration(days: 4));
      final dueTodayDate = now;
      final upcomingDate = now.add(const Duration(days: 6));

      final docs = [
        <String, dynamic>{
          'name': 'projects/test/databases/(default)/documents/invoices/INV-OVERDUE',
          'fields': FirestoreRestService.encodeFields({
            'invoiceNumber': 'INV-OVERDUE',
            'customerName': 'Aman Verma',
            'customerPhone': '9876543211',
            'grandTotalPaise': 80000,
            'paidPaise': 30000,
            'dueAmount': 50000,
            'status': 'PENDING',
            'dueDate': overdueDate.toUtc().toIso8601String(),
            'invoiceDate': overdueDate.toUtc().toIso8601String(),
            'createdAt': overdueDate.toUtc().toIso8601String(),
            'customerId': 'cust-overdue',
          }),
        },
        <String, dynamic>{
          'name': 'projects/test/databases/(default)/documents/invoices/INV-TODAY',
          'fields': FirestoreRestService.encodeFields({
            'invoiceNumber': 'INV-TODAY',
            'customerName': 'Ramesh Kumar',
            'customerPhone': '9876543212',
            'grandTotalPaise': 120000,
            'paidPaise': 20000,
            'dueAmount': 100000,
            'status': 'PENDING',
            'dueDate': dueTodayDate.toUtc().toIso8601String(),
            'invoiceDate': dueTodayDate.toUtc().toIso8601String(),
            'createdAt': dueTodayDate.toUtc().toIso8601String(),
            'customerId': 'cust-today',
          }),
        },
        <String, dynamic>{
          'name': 'projects/test/databases/(default)/documents/invoices/INV-UPCOMING',
          'fields': FirestoreRestService.encodeFields({
            'invoiceNumber': 'INV-UPCOMING',
            'customerName': 'Suresh Patel',
            'customerPhone': '9876543213',
            'grandTotalPaise': 150000,
            'paidPaise': 50000,
            'dueAmount': 100000,
            'status': 'PENDING',
            'dueDate': upcomingDate.toUtc().toIso8601String(),
            'invoiceDate': now.toUtc().toIso8601String(),
            'createdAt': now.toUtc().toIso8601String(),
            'customerId': 'cust-upcoming',
          }),
        },
      ];

      final fakeOffline = FakeOfflineFirestoreService(docs: docs);
      final controller = TestSalesController(
        initialLocale: const Locale('en'),
        offlineService: fakeOffline,
      );

      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Tap 'Borrow / Pending' filter chip
      await tester.tap(find.text('Borrow / Pending'));
      await tester.pumpAndSettle();

      // Repayment Timeline bar is rendered
      expect(find.text('Repayment Timeline'), findsOneWidget);
      expect(find.text('All Pending'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Due Today'), findsOneWidget);
      expect(find.text('Upcoming Due'), findsOneWidget);

      // Customer repayment dates are displayed on cards
      expect(find.text('Repayment Date: ', skipOffstage: false), findsWidgets);
      expect(find.textContaining('overdue', skipOffstage: false), findsWidgets);
      expect(find.text('⏰ Due Today', skipOffstage: false), findsWidgets);
      expect(find.textContaining('days left', skipOffstage: false), findsWidgets);

      // Filter by 'Overdue'
      await tester.tap(find.text('Overdue'));
      await tester.pumpAndSettle();
      expect(find.text('INV-OVERDUE'), findsOneWidget);
      expect(find.text('INV-TODAY'), findsNothing);
      expect(find.text('INV-UPCOMING'), findsNothing);

      // Filter by 'Due Today'
      await tester.tap(find.text('Due Today'));
      await tester.pumpAndSettle();
      expect(find.text('INV-TODAY'), findsOneWidget);
      expect(find.text('INV-OVERDUE'), findsNothing);
      expect(find.text('INV-UPCOMING'), findsNothing);

      // Filter by 'Upcoming Due'
      await tester.tap(find.text('Upcoming Due'));
      await tester.pumpAndSettle();
      expect(find.text('INV-UPCOMING'), findsOneWidget);
      expect(find.text('INV-OVERDUE'), findsNothing);
      expect(find.text('INV-TODAY'), findsNothing);
    });

    testWidgets('Borrow / Pending timeline filters and customer repayment dates in Hindi (हिन्दी)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final docs = [
        <String, dynamic>{
          'name': 'projects/test/databases/(default)/documents/invoices/INV-HI-1',
          'fields': FirestoreRestService.encodeFields({
            'invoiceNumber': 'INV-HI-1',
            'customerName': 'राम लाल',
            'customerPhone': '9876543210',
            'grandTotalPaise': 90000,
            'paidPaise': 30000,
            'dueAmount': 60000,
            'status': 'PENDING',
            'dueDate': now.toUtc().toIso8601String(),
            'invoiceDate': now.toUtc().toIso8601String(),
            'createdAt': now.toUtc().toIso8601String(),
            'customerId': 'cust-hi-1',
          }),
        },
      ];

      final fakeOffline = FakeOfflineFirestoreService(docs: docs);
      final controller = TestSalesController(
        initialLocale: const Locale('hi'),
        offlineService: fakeOffline,
      );

      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('hi')),
      );
      await tester.pumpAndSettle();

      // Tap Hindi Borrow / Pending filter chip
      await tester.tap(find.text('उधार / बाकी'));
      await tester.pumpAndSettle();

      // Verify Hindi timeline labels
      expect(find.text('चुकता समयरेखा'), findsOneWidget);
      expect(find.text('सभी लंबित'), findsOneWidget);
      expect(find.text('अतिदेय'), findsOneWidget);
      expect(find.text('आज देय'), findsWidgets); // chip + badge
      expect(find.text('आगामी देय'), findsOneWidget);
      expect(find.text('चुकता तारीख: ', skipOffstage: false), findsOneWidget);
    });

    testWidgets('Borrow / Pending timeline filters and customer repayment dates in Bengali (বাংলা)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final docs = [
        <String, dynamic>{
          'name': 'projects/test/databases/(default)/documents/invoices/INV-BN-1',
          'fields': FirestoreRestService.encodeFields({
            'invoiceNumber': 'INV-BN-1',
            'customerName': 'সুবীর ঘোষ',
            'customerPhone': '9876543219',
            'grandTotalPaise': 110000,
            'paidPaise': 40000,
            'dueAmount': 70000,
            'status': 'PENDING',
            'dueDate': now.toUtc().toIso8601String(),
            'invoiceDate': now.toUtc().toIso8601String(),
            'createdAt': now.toUtc().toIso8601String(),
            'customerId': 'cust-bn-1',
          }),
        },
      ];

      final fakeOffline = FakeOfflineFirestoreService(docs: docs);
      final controller = TestSalesController(
        initialLocale: const Locale('bn'),
        offlineService: fakeOffline,
      );

      await tester.pumpWidget(
        createSalesHubApp(controller: controller, locale: const Locale('bn')),
      );
      await tester.pumpAndSettle();

      // Tap Bengali Borrow / Pending filter chip
      await tester.tap(find.text('বাকি / অপেক্ষমাণ'));
      await tester.pumpAndSettle();

      // Verify Bengali timeline labels
      expect(find.text('পরিশোধের সময়সীমা'), findsOneWidget);
      expect(find.text('সব বকেয়া'), findsOneWidget);
      expect(find.text('বকেয়া অতিক্রান্ত'), findsOneWidget);
      expect(find.text('আজ প্রদেয়'), findsWidgets); // chip + badge
      expect(find.text('আসন্ন বকেয়া'), findsOneWidget);
      expect(find.text('পরিশোধের তারিখ: ', skipOffstage: false), findsOneWidget);
    });
  });
}

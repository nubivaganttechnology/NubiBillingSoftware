import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/expense_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/repositories/expense_repository.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/expenses/expense_pages.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'package:testflutter/data/services/firestore_data_service.dart';

import 'product_entry_form_test.dart' show EntryController;

class MockTestExpenseRepository implements ExpenseRepository {
  MockTestExpenseRepository({List<ExpenseModel>? initialExpenses})
      : _expenses = List.of(initialExpenses ?? _defaultExpenses());

  @override
  FirestoreDataService get firestore => throw UnimplementedError();

  final List<ExpenseModel> _expenses;

  static List<ExpenseModel> _defaultExpenses() {
    final now = DateTime.now();
    return [
      ExpenseModel(
        expenseId: 'EXP-1001',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        outletId: 'out-1',
        title: 'Store Rent for October',
        category: 'Rent & Lease',
        amountPaise: 2500000, // ₹25,000.00
        expenseDate: now,
        paymentMode: 'BANK_TRANSFER',
        payeeName: 'Sharma Real Estate',
        referenceNumber: 'RENT-OCT-26',
        notes: 'Monthly showroom floor lease payment',
        status: 'ACTIVE',
        createdAt: now,
        createdBy: 'Admin User',
      ),
      ExpenseModel(
        expenseId: 'EXP-1002',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        outletId: 'out-1',
        title: 'Electricity Bill - September',
        category: 'Electricity & Utilities',
        amountPaise: 485000, // ₹4,850.00
        expenseDate: now,
        paymentMode: 'UPI',
        payeeName: 'State Electricity Board',
        referenceNumber: 'UPI-987654',
        notes: 'Power bill paid via GooglePay UPI',
        status: 'ACTIVE',
        createdAt: now,
        createdBy: 'Admin User',
      ),
      ExpenseModel(
        expenseId: 'EXP-1003',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        outletId: 'out-1',
        title: 'Staff Tea & Refreshments',
        category: 'Tea & Refreshments',
        amountPaise: 25000, // ₹250.00
        expenseDate: now,
        paymentMode: 'CASH',
        payeeName: 'Radhe Tea Stall',
        referenceNumber: 'PETTY-01',
        notes: 'Snacks & chai for store crew',
        status: 'ACTIVE',
        createdAt: now,
        createdBy: 'Cashier Staff',
      ),
      ExpenseModel(
        expenseId: 'EXP-1004',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        outletId: 'out-1',
        title: 'Packaging Boxes & Bubble Wrap',
        category: 'Packaging & Materials',
        amountPaise: 180000, // ₹1,800.00
        expenseDate: now.subtract(const Duration(days: 2)),
        paymentMode: 'CASH',
        payeeName: 'Metro Packaging',
        referenceNumber: 'PKG-55',
        notes: '100 pcs packing boxes',
        status: 'ACTIVE',
        createdAt: now.subtract(const Duration(days: 2)),
        createdBy: 'Warehouse Manager',
      ),
      ExpenseModel(
        expenseId: 'EXP-1005',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        outletId: 'out-1',
        title: 'Freight & Transport Charges',
        category: 'Freight & Delivery',
        amountPaise: 350000, // ₹3,500.00
        expenseDate: now.subtract(const Duration(days: 5)),
        paymentMode: 'CASH',
        payeeName: 'Fast Logistics',
        referenceNumber: 'LR-9901',
        notes: 'Inter-store transfer cartage',
        status: 'ACTIVE',
        createdAt: now.subtract(const Duration(days: 5)),
        createdBy: 'Logistics Head',
      ),
      ExpenseModel(
        expenseId: 'EXP-1006',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        outletId: 'out-1',
        title: 'Damaged Material Disposal',
        category: 'Miscellaneous',
        amountPaise: 50000, // ₹500.00
        expenseDate: now.subtract(const Duration(days: 10)),
        paymentMode: 'CASH',
        payeeName: 'City Waste',
        referenceNumber: 'MISC-09',
        notes: 'Cancelled voided voucher',
        status: 'VOID',
        createdAt: now.subtract(const Duration(days: 10)),
        createdBy: 'Admin User',
      ),
    ];
  }

  @override
  Future<List<ExpenseModel>> getExpenses({
    required String tenantId,
    required String businessId,
    String? outletId,
    DateTime? startDate,
    DateTime? endDate,
    String? category,
    String? paymentMode,
    required String token,
  }) async {
    return List.of(_expenses);
  }

  @override
  Future<ExpenseModel> createExpense({
    required String tenantId,
    required String businessId,
    String? outletId,
    required String title,
    required String category,
    required int amountPaise,
    required DateTime expenseDate,
    String paymentMode = 'CASH',
    String? payeeName,
    String? referenceNumber,
    String? notes,
    String? createdBy,
    required String token,
  }) async {
    final newExp = ExpenseModel(
      expenseId: 'EXP-${DateTime.now().millisecondsSinceEpoch}',
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      title: title,
      category: category,
      amountPaise: amountPaise,
      expenseDate: expenseDate,
      paymentMode: paymentMode,
      payeeName: payeeName,
      referenceNumber: referenceNumber,
      notes: notes,
      status: 'ACTIVE',
      createdAt: DateTime.now(),
      createdBy: createdBy,
    );
    _expenses.insert(0, newExp);
    return newExp;
  }

  @override
  Future<void> voidExpense({
    required String expenseId,
    required String token,
  }) async {
    final index = _expenses.indexWhere((e) => e.expenseId == expenseId);
    if (index != -1) {
      final old = _expenses[index];
      _expenses[index] = ExpenseModel(
        expenseId: old.expenseId,
        tenantId: old.tenantId,
        businessId: old.businessId,
        outletId: old.outletId,
        title: old.title,
        category: old.category,
        amountPaise: old.amountPaise,
        expenseDate: old.expenseDate,
        paymentMode: old.paymentMode,
        payeeName: old.payeeName,
        referenceNumber: old.referenceNumber,
        notes: old.notes,
        status: 'VOID',
        createdAt: old.createdAt,
        createdBy: old.createdBy,
      );
    }
  }
}

class TestExpenseController extends EntryController {
  TestExpenseController({
    Locale? initialLocale,
    List<ExpenseModel>? initialExpenses,
  })  : _locale = initialLocale ?? const Locale('en'),
        _repo = MockTestExpenseRepository(initialExpenses: initialExpenses);

  Locale _locale;
  final MockTestExpenseRepository _repo;

  @override
  Locale get currentLocale => _locale;

  @override
  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
  }

  @override
  ExpenseRepository get expenseRepository => _repo;

  @override
  AppContext get appContext => const AppContext(
        uid: 'user-1',
        accountType: 'owner',
        ownerUid: 'owner-1',
        businessId: 'bus-1',
        permissions: ['*'],
      );

  @override
  String? get idToken => 'mock-id-token';

  @override
  OutletModel get currentOutlet => const OutletModel(
        outletId: 'out-1',
        businessId: 'bus-1',
        ownerUid: 'owner-1',
        tenantId: 'owner-1',
        outletName: 'Central Paint Depot',
        outletTypeId: 'retail',
        outletTypeName: 'Retail Outlet',
        isActive: true,
      );
}

void main() {
  group('Expenses Dashboard Modern UI & Multi-Language Tests', () {
    testWidgets('Renders in English with modern KPI metrics, Table View & Actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Executive Header
      expect(find.text('Expenses & Outflows'), findsOneWidget);
      expect(find.text('Central Paint Depot'), findsOneWidget);
      expect(find.text('Record Expense'), findsWidgets);
      expect(find.text('Export CSV'), findsOneWidget);

      // KPI Metric Cards
      expect(find.text("Today's Expense"), findsOneWidget);
      expect(find.text("This Month's Total"), findsOneWidget);
      expect(find.text('Cash Outflow'), findsOneWidget);
      expect(find.text('Digital & Bank'), findsOneWidget);
      expect(find.text('Active Records'), findsOneWidget);

      // Table View Headers
      expect(find.text('Date & Time'), findsOneWidget);
      expect(find.text('Title / Description'), findsOneWidget);
      expect(find.text('Category'), findsWidgets);
      expect(find.text('Payee'), findsOneWidget);
      expect(find.text('Mode'), findsWidgets);
      expect(find.text('Amount'), findsOneWidget);

      // Verify Expense row item rendered
      expect(find.text('Store Rent for October'), findsOneWidget);
      expect(find.text('Sharma Real Estate'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders in Hindi (हिन्दी) with accurate terminology', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('hi'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('hi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Executive Header & Actions in Hindi
      expect(find.text('व्यय और बहिर्वाह'), findsOneWidget);
      expect(find.text('खर्च दर्ज करें'), findsWidgets);
      expect(find.text('CSV निर्यात करें'), findsOneWidget);

      // KPI Metrics in Hindi
      expect(find.text('आज का खर्च'), findsOneWidget);
      expect(find.text('इस महीने का कुल'), findsOneWidget);
      expect(find.text('नकद व्यय'), findsOneWidget);
      expect(find.text('डिजिटल व बैंक'), findsOneWidget);
      expect(find.text('सक्रिय रिकॉर्ड'), findsOneWidget);

      // Table Headers in Hindi
      expect(find.text('तारीख व समय'), findsOneWidget);
      expect(find.text('शीर्षक / विवरण'), findsOneWidget);
      expect(find.text('राशि'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders in Bengali (বাংলা) with accurate terminology', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('bn'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('bn'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Executive Header & Actions in Bengali
      expect(find.text('ব্যয় ও বহির্গমন'), findsOneWidget);
      expect(find.text('খরচ রেকর্ড করুন'), findsWidgets);
      expect(find.text('CSV এক্সপোর্ট করুন'), findsOneWidget);

      // KPI Metrics in Bengali
      expect(find.text('আজকের খরচ'), findsOneWidget);
      expect(find.text('এই মাসের মোট'), findsOneWidget);
      expect(find.text('নগদ ব্যয়'), findsOneWidget);
      expect(find.text('ডিজিটাল ও ব্যাংক'), findsOneWidget);
      expect(find.text('সক্রিয় রেকর্ড'), findsOneWidget);

      // Table Headers in Bengali
      expect(find.text('তারিখ ও সময়'), findsOneWidget);
      expect(find.text('শিরোনাম / বিবরণ'), findsOneWidget);
      expect(find.text('পরিমাণ'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('In-place Language Switcher updates controller locale seamlessly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.light,
            locale: controller.currentLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ExpenseManagementPage(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expenses & Outflows'), findsOneWidget);

      // Switch to Hindi
      await controller.setLocale(const Locale('hi'));
      await tester.pumpAndSettle();
      expect(find.text('व्यय और बहिर्वाह'), findsOneWidget);

      // Switch to Bengali
      await controller.setLocale(const Locale('bn'));
      await tester.pumpAndSettle();
      expect(find.text('ব্যয় ও বহির্গমন'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Search query filters expense list accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Store Rent for October'), findsOneWidget);
      expect(find.text('Electricity Bill - September'), findsOneWidget);

      // Type in search query "Electricity"
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Electricity');
      await tester.pumpAndSettle();

      expect(find.text('Electricity Bill - September'), findsOneWidget);
      expect(find.text('Store Rent for October'), findsNothing);

      // Clear search
      final clearButton = find.byIcon(Icons.clear_rounded);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('Store Rent for October'), findsOneWidget);
      expect(find.text('Electricity Bill - September'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('KPI card tap filters list and Card View toggle works', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Toggle to Card View
      final cardViewIcon = find.byIcon(Icons.grid_view_rounded);
      await tester.tap(cardViewIcon);
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsWidgets);

      // Tap Cash Outflow KPI card
      final cashCard = find.text('Cash Outflow');
      await tester.tap(cashCard);
      await tester.pumpAndSettle();

      // Only Cash expenses shown
      expect(find.text('Staff Tea & Refreshments'), findsOneWidget);
      expect(find.text('Store Rent for October'), findsNothing); // It was Bank Transfer

      expect(tester.takeException(), isNull);
    });

    testWidgets('Opens Voucher Details dialog with complete breakdown and info', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap info/details button on first expense
      final infoButton = find.byIcon(Icons.info_outline_rounded).first;
      await tester.tap(infoButton);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Expense Voucher Details'), findsOneWidget);
      expect(find.text('Store Rent for October'), findsWidgets);
      expect(find.text('Sharma Real Estate'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Opens Record Expense dialog with quick chips and saves successfully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestExpenseController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Record Expense button
      final recordButton = find.text('Record Expense').first;
      await tester.tap(recordButton);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('New Expense Voucher'), findsOneWidget);

      // Tap quick amount chip +₹500
      final chip500 = find.text('+₹500');
      await tester.tap(chip500);
      await tester.pumpAndSettle();

      // Tap suggestion chip "Shop Rent"
      final rentSuggestion = find.text('Shop Rent');
      await tester.tap(rentSuggestion);
      await tester.pumpAndSettle();

      // Verify preview banner appeared
      expect(find.textContaining('Outflow Preview: ₹500.00'), findsOneWidget);

      // Tap Save Expense
      final saveButton = find.text('Save Expense');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Dialog should be closed and new expense added
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Shop Rent'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders with zero overflow across Mobile (390px), Tablet (820px), Desktop (1440px)', (
      tester,
    ) async {
      final controller = TestExpenseController(initialLocale: const Locale('en'));

      for (final size in [
        const Size(390, 844), // Mobile iPhone
        const Size(820, 1180), // Tablet iPad Air
        const Size(1440, 900), // Desktop ERP
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ExpenseManagementPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Expenses & Outflows'), findsOneWidget);
        final err = tester.takeException();
        if (err is FlutterError) {
          debugPrint('FULL_ERROR:\n${err.toStringDeep()}');
        }
        expect(err, isNull);
      }
    });
  });
}

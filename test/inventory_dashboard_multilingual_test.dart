import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/inventory/inventory_dashboard_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class TestInventoryController extends EntryController {
  TestInventoryController({
    Locale? initialLocale,
    List<ProductModel>? initialProducts,
    Map<String, int>? initialStock,
  })  : _locale = initialLocale ?? const Locale('en'),
        _products = initialProducts ?? _defaultProducts(),
        _stock = initialStock ?? _defaultStock();

  Locale _locale;
  final List<ProductModel> _products;
  final Map<String, int> _stock;

  @override
  Locale get currentLocale => _locale;

  @override
  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
  }

  @override
  bool canManageProducts() => true;

  @override
  bool canViewStorage() => true;

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

  @override
  List<ProductModel> get products => _products;

  @override
  Map<String, int> get productStock => _stock;

  @override
  Future<void> loadProducts() async {
    notifyListeners();
  }

  static List<ProductModel> _defaultProducts() {
    return [
      ProductModel(
        productId: 'prod-1',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        name: 'Sigmark WeatherShield Exterior Emulsion 20L',
        brand: 'Sigmark',
        category: 'Emulsion',
        status: 'ACTIVE',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 10, 1),
        variants: const [
          ProductVariantModel(
            variantId: 'var-1',
            productId: 'prod-1',
            businessId: 'bus-1',
            name: '20 Litre Brilliant White',
            sku: 'SIG-WS-20L-WHT',
            barcode: '8901234567890',
            baseUnitId: 'ltr',
            commercialUnitName: '20L Bucket',
            sellingPrice: 780000, // ₹7,800.00
            purchaseRate: 550000, // ₹5,500.00
            mrp: 850000,
            reorderLevel: 10,
            defaultGstRateBps: 1800,
          ),
        ],
      ),
      ProductModel(
        productId: 'prod-2',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        name: 'Asian Paints Apex Ultima 4L',
        brand: 'Asian Paints',
        category: 'Exterior',
        status: 'ACTIVE',
        createdAt: DateTime(2026, 2, 1),
        updatedAt: DateTime(2026, 10, 15),
        variants: const [
          ProductVariantModel(
            variantId: 'var-2',
            productId: 'prod-2',
            businessId: 'bus-1',
            name: '4 Litre Super White',
            sku: 'AP-APX-4L',
            barcode: '8909876543210',
            baseUnitId: 'ltr',
            commercialUnitName: '4L Can',
            sellingPrice: 195000, // ₹1,950.00
            purchaseRate: 140000, // ₹1,400.00
            mrp: 220000,
            reorderLevel: 8,
            defaultGstRateBps: 1800,
          ),
        ],
      ),
      ProductModel(
        productId: 'prod-3',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        name: 'Berger Silk Glamor 1L',
        brand: 'Berger',
        category: 'Interior',
        status: 'ACTIVE',
        createdAt: DateTime(2026, 3, 1),
        updatedAt: DateTime(2026, 10, 18),
        variants: const [
          ProductVariantModel(
            variantId: 'var-3',
            productId: 'prod-3',
            businessId: 'bus-1',
            name: '1 Litre Silk Offwhite',
            sku: 'BR-SLK-1L',
            barcode: '8904561237890',
            baseUnitId: 'ltr',
            commercialUnitName: '1L Can',
            sellingPrice: 62000, // ₹620.00
            purchaseRate: 45000, // ₹450.00
            mrp: 70000,
            reorderLevel: 15,
            defaultGstRateBps: 1800,
          ),
        ],
      ),
    ];
  }

  static Map<String, int> _defaultStock() {
    return {
      'var-1': 45, // Healthy in stock (> 10)
      'var-2': 3, // Low stock (<= 8)
      'var-3': 0, // Out of stock (0)
    };
  }
}

void main() {
  group('Inventory Dashboard Modern UI & Multi-Language Tests', () {
    testWidgets('Renders in English with modern KPI metrics, Table View & Actions', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('en'));
      var openedProducts = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InventoryDashboardPage(
              controller: controller,
              onOpenProducts: () => openedProducts = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header Title & Subtitle in English
      expect(find.text('Inventory Intelligence & Operations'), findsOneWidget);
      expect(
        find.text('Real-time stock monitoring, valuations, reorder alerts & movement management'),
        findsOneWidget,
      );
      expect(find.text('Central Paint Depot'), findsOneWidget);

      // KPI Cards in English
      expect(find.text('Total Products / SKUs'), findsOneWidget);
      expect(find.text('Optimal Stock'), findsOneWidget);
      expect(find.text('Low Stock Alerts'), findsOneWidget);
      expect(find.text('Out of Stock'), findsWidgets);
      expect(find.text('Estimated Stock Value'), findsOneWidget);

      // Actions in Header
      expect(find.text('Import CSV'), findsOneWidget);
      expect(find.text('Export CSV'), findsOneWidget);
      expect(find.text('Add New Product'), findsOneWidget);

      // Search & Filters in English
      expect(find.text('All'), findsOneWidget);
      expect(find.text('In Stock'), findsOneWidget);
      expect(find.text('Low Stock'), findsWidgets);
      expect(find.text('Table View'), findsNothing); // Tooltip only

      // Table rows rendered
      expect(find.text('Sigmark WeatherShield Exterior Emulsion 20L'), findsOneWidget);
      expect(find.text('Asian Paints Apex Ultima 4L'), findsOneWidget);
      expect(find.text('Berger Silk Glamor 1L'), findsOneWidget);

      // SKUs rendered
      expect(find.text('SIG-WS-20L-WHT'), findsOneWidget);
      expect(find.text('AP-APX-4L'), findsOneWidget);
      expect(find.text('BR-SLK-1L'), findsOneWidget);

      // Status badges
      expect(find.text('Healthy'), findsOneWidget);
      expect(find.text('Low Stock'), findsWidgets);

      // Add New Product callback
      await tester.tap(find.text('Add New Product'));
      await tester.pumpAndSettle();
      expect(openedProducts, isTrue);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders in Hindi (हिन्दी) with complete accurate terminology', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('hi'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('hi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InventoryDashboardPage(
              controller: controller,
              onOpenProducts: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hindi Header
      expect(find.text('इन्वेंट्री इंटेलिजेंस और संचालन'), findsOneWidget);

      // Hindi KPI Titles
      expect(find.text('कुल उत्पाद / एसकेयू'), findsOneWidget);
      expect(find.text('पर्याप्त स्टॉक'), findsOneWidget);
      expect(find.text('कम स्टॉक चेतावनी'), findsOneWidget);
      expect(find.text('स्टॉक समाप्त'), findsWidgets); // KPI & Status badge
      expect(find.text('अनुमानित स्टॉक मूल्य'), findsOneWidget);

      // Hindi Header Actions
      expect(find.text('CSV आयात करें'), findsOneWidget);
      expect(find.text('CSV निर्यात करें'), findsOneWidget);
      expect(find.text('नया उत्पाद जोड़ें'), findsOneWidget);

      // Hindi Filters
      expect(find.text('सभी'), findsOneWidget);
      expect(find.text('स्टॉक में'), findsOneWidget);
      expect(find.text('कम स्टॉक'), findsWidgets);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders in Bengali (বাংলা) with complete accurate terminology', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('bn'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('bn'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InventoryDashboardPage(
              controller: controller,
              onOpenProducts: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bengali Header
      expect(find.text('ইনভেন্টরি ইন্টেলিজেন্স ও অপারেশনস'), findsOneWidget);

      // Bengali KPI Titles
      expect(find.text('মোট পণ্য / এসকেইউ'), findsOneWidget);
      expect(find.text('উপযুক্ত স্টক'), findsOneWidget);
      expect(find.text('কম স্টক সতর্কতা'), findsOneWidget);
      expect(find.text('স্টক শেষ'), findsWidgets);
      expect(find.text('আনুমানিক স্টক মূল্য'), findsOneWidget);

      // Bengali Header Actions
      expect(find.text('CSV আমদানি করুন'), findsOneWidget);
      expect(find.text('CSV রপ্তানি করুন'), findsOneWidget);
      expect(find.text('নতুন পণ্য যোগ করুন'), findsOneWidget);

      // Bengali Filters
      expect(find.text('সব'), findsOneWidget);
      expect(find.text('স্টকে আছে'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('In-place Language Switcher updates controller locale seamlessly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return MaterialApp(
              theme: AppTheme.light,
              locale: controller.currentLocale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: InventoryDashboardPage(
                  controller: controller,
                  onOpenProducts: () {},
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventory Intelligence & Operations'), findsOneWidget);

      // Open Language popup menu from the header
      final langButton = find.byIcon(Icons.translate_rounded);
      expect(langButton, findsOneWidget);
      await tester.tap(langButton);
      await tester.pumpAndSettle();

      // Tap Hindi option
      final hindiOption = find.text('हिंदी (Hindi)');
      expect(hindiOption, findsOneWidget);
      await tester.tap(hindiOption);
      await tester.pumpAndSettle();

      // Controller locale should be updated
      expect(controller.currentLocale.languageCode, equals('hi'));
      expect(find.text('इन्वेंट्री इंटेलिजेंस और संचालन'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Search query filters inventory table accurately', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InventoryDashboardPage(
              controller: controller,
              onOpenProducts: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sigmark WeatherShield Exterior Emulsion 20L'), findsOneWidget);
      expect(find.text('Asian Paints Apex Ultima 4L'), findsOneWidget);

      // Search for 'Apex'
      await tester.enterText(find.byType(TextField).first, 'Apex');
      await tester.pumpAndSettle();

      expect(find.text('Asian Paints Apex Ultima 4L'), findsOneWidget);
      expect(find.text('Sigmark WeatherShield Exterior Emulsion 20L'), findsNothing);

      // Clear search
      final clearButton = find.byIcon(Icons.clear_rounded);
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('Sigmark WeatherShield Exterior Emulsion 20L'), findsOneWidget);
      expect(find.text('Asian Paints Apex Ultima 4L'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('KPI card tap filters list by status and Card View toggle works', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InventoryDashboardPage(
              controller: controller,
              onOpenProducts: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Low Stock Alerts' KPI card
      await tester.tap(find.text('Low Stock Alerts'));
      await tester.pumpAndSettle();

      // Only Asian Paints is low stock (3 units <= 8 reorder level)
      expect(find.text('Asian Paints Apex Ultima 4L'), findsOneWidget);
      expect(find.text('Sigmark WeatherShield Exterior Emulsion 20L'), findsNothing);

      // Switch to Card View
      final cardViewIcon = find.byIcon(Icons.grid_view_rounded);
      expect(cardViewIcon, findsOneWidget);
      await tester.tap(cardViewIcon);
      await tester.pumpAndSettle();

      expect(find.text('Asian Paints Apex Ultima 4L'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Opens Product Details modal with complete technical specifications', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestInventoryController(initialLocale: const Locale('en'));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: InventoryDashboardPage(
              controller: controller,
              onOpenProducts: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap details button on the first item
      final detailsButton = find.byIcon(Icons.info_outline_rounded).first;
      await tester.tap(detailsButton);
      await tester.pumpAndSettle();

      // Dialog should be displayed
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Brand'), findsOneWidget);
      expect(find.text('Category'), findsWidgets);
      expect(find.text('Selling Price'), findsWidgets);
      expect(find.text('Purchase Rate'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders with zero overflow across Mobile (390px), Tablet (820px), Desktop (1440px)', (
      tester,
    ) async {
      final controller = TestInventoryController(initialLocale: const Locale('en'));

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
              body: InventoryDashboardPage(
                controller: controller,
                onOpenProducts: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Inventory Intelligence & Operations'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'Zero overflow at $size');
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}

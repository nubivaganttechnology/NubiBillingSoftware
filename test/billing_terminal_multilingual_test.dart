import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/invoice_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/data/repositories/billing_repository.dart';
import 'package:testflutter/data/repositories/product_repository.dart'
    show VariantBatchPriceOption;
import 'package:testflutter/domain/billing/billing_models.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/billing/billing_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class MockBillingRepository extends Fake implements BillingRepository {
  FinalizeBillRequest? lastFinalizeRequest;

  @override
  Future<FinalizeBillResult> finalize(
    FinalizeBillRequest request, {
    required String token,
  }) async {
    lastFinalizeRequest = request;
    return const FinalizeBillResult(
      invoiceId: 'inv-123',
      invoiceNumber: 'INV-000001',
      existing: false,
    );
  }
}

class TestBillingController extends EntryController {
  TestBillingController({
    Locale? initialLocale,
    List<ProductModel>? customProducts,
    Map<String, ({int mrp, int sellingPrice})>? initialReceivedPricing,
    Map<String, int>? customStock,
    List<BusinessModel>? customBusinesses,
    BillingRepository? mockBilling,
    Map<String, List<VariantBatchPriceOption>>? variantBatches,
  })  : _locale = initialLocale ?? const Locale('en'),
        _products = customProducts,
        _receivedPricing = initialReceivedPricing ?? const {},
        _stock = customStock,
        _businesses = customBusinesses,
        _billingRepository = mockBilling,
        _variantBatches = variantBatches ?? const {};

  Locale _locale;
  final List<ProductModel>? _products;
  final Map<String, ({int mrp, int sellingPrice})> _receivedPricing;
  final Map<String, int>? _stock;
  final List<BusinessModel>? _businesses;
  final BillingRepository? _billingRepository;
  final Map<String, List<VariantBatchPriceOption>> _variantBatches;

  @override
  BillingRepository? get billingRepository => _billingRepository;

  @override
  Future<List<VariantBatchPriceOption>> loadVariantBatches(
    String variantId,
  ) async =>
      _variantBatches[variantId] ?? const [];

  @override
  Future<Map<String, ({int mrp, int sellingPrice})>>
  loadBarcodeReceivedVariantPricing() async => _receivedPricing;

  @override
  Locale get currentLocale => _locale;

  @override
  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
  }

  @override
  AppContext get appContext => const AppContext(
        uid: 'cashier-uid',
        accountType: 'owner',
        ownerUid: 'owner-uid',
        businessId: 'bus-1',
        permissions: ['*'],
      );

  @override
  String? get idToken => 'mock-token';

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
  List<OutletModel> get outlets => [currentOutlet];

  @override
  List<BusinessModel> get businesses =>
      _businesses ??
      const [
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
  List<ProductModel> get products => _products ?? [
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
              mrp: 50000, // ₹500.00
              defaultGstRateBps: 1800, // 18%
              barcode: '890123456789',
              sku: 'SIG-WS-1L',
              productName: 'Sigmark WeatherShield Paint',
            ),
          ],
        ),
      ];

  @override
  Map<String, int> get productStock =>
      _stock ??
      {
        for (final p in products)
          for (final v in p.variants) v.variantId: 25000,
      };
}

Widget createBillingApp({
  required TestBillingController controller,
  required Locale locale,
}) {
  return MaterialApp(
    title: 'POS Billing Test',
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BillingPage(controller: controller),
    ),
  );
}

void main() {
  group('POS Billing Terminal Multilingual & UI Tests', () {
    testWidgets('Renders POS Billing Terminal in English with zero overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestBillingController(initialLocale: const Locale('en'));
      await tester.pumpWidget(
        createBillingApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // Check header
      expect(find.text('POS Billing Terminal'), findsOneWidget);
      expect(find.text('Central Outlet POS'), findsOneWidget);
      expect(find.text('GST'), findsOneWidget);
      expect(find.text('Non-GST'), findsOneWidget);

      // Check search / barcode dock
      expect(find.text('Scan barcode / Search product'), findsOneWidget);
      expect(find.text('Add to Cart'), findsOneWidget);

      // Check empty cart
      expect(find.text('Cart Items'), findsOneWidget);
      expect(find.text('No items in this bill.'), findsOneWidget);

      // Check customer dock
      expect(find.text('Walk-in Customer'), findsOneWidget);
      expect(find.text('Select Customer'), findsOneWidget);

      // Check summary & payment options
      expect(find.text('Bill Summary'), findsOneWidget);
      expect(find.text('Grand Total'), findsOneWidget);
      expect(find.text('Full Cash'), findsOneWidget);
      expect(find.text('Full UPI'), findsOneWidget);
      expect(find.text('Partial Cash & UPI'), findsOneWidget);
      expect(find.text('Borrow (Credit / Udhaar)'), findsOneWidget);
      expect(find.text('FINALIZE & SAVE BILL'), findsOneWidget);

      // Verify no exceptions or overflows
      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders POS Billing Terminal in Hindi (हिन्दी)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestBillingController(initialLocale: const Locale('hi'));
      await tester.pumpWidget(
        createBillingApp(controller: controller, locale: const Locale('hi')),
      );
      await tester.pumpAndSettle();

      // Check localized Hindi strings
      expect(find.text('पीओएस बिलिंग टर्मिनल'), findsOneWidget);
      expect(find.text('जीएसटी'), findsOneWidget);
      expect(find.text('गैर-जीएसटी'), findsOneWidget);
      expect(find.text('बारकोड स्कैन / उत्पाद खोजें'), findsOneWidget);
      expect(find.text('कार्ट में जोड़ें'), findsOneWidget);
      expect(find.text('कार्ट आइटम'), findsOneWidget);
      expect(find.text('इस बिल में कोई आइटम नहीं है।'), findsOneWidget);
      expect(find.text('वॉल्क-इन ग्राहक'), findsOneWidget);
      expect(find.text('ग्राहक चुनें'), findsOneWidget);
      expect(find.text('बिल सारांश'), findsOneWidget);
      expect(find.text('कुल योग'), findsOneWidget);
      expect(find.text('पूर्ण नकद'), findsOneWidget);
      expect(find.text('पूर्ण यूपीआई'), findsOneWidget);
      expect(find.text('आंशिक नकद व यूपीआई'), findsOneWidget);
      expect(find.text('उधार (बाकी)'), findsOneWidget);
      expect(find.text('बिल सेव और फाइनल करें'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Renders POS Billing Terminal in Bengali (বাংলা)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestBillingController(initialLocale: const Locale('bn'));
      await tester.pumpWidget(
        createBillingApp(controller: controller, locale: const Locale('bn')),
      );
      await tester.pumpAndSettle();

      // Check localized Bengali strings
      expect(find.text('পিওএস বিলিং টার্মিনাল'), findsOneWidget);
      expect(find.text('জিএসটি'), findsOneWidget);
      expect(find.text('নন-জিএসটি'), findsOneWidget);
      expect(find.text('বারকোড স্ক্যান / পণ্য খুঁজুন'), findsOneWidget);
      expect(find.text('কার্টে যোগ করুন'), findsOneWidget);
      expect(find.text('কার্ট আইটেম'), findsOneWidget);
      expect(find.text('এই বিলে কোনো পণ্য নেই।'), findsOneWidget);
      expect(find.text('খুচরা ক্রেতা'), findsOneWidget);
      expect(find.text('ক্রেতা নির্বাচন'), findsOneWidget);
      expect(find.text('বিল সারাংশ'), findsOneWidget);
      expect(find.text('সর্বমোট'), findsOneWidget);
      expect(find.text('সম্পূর্ণ নগদ'), findsOneWidget);
      expect(find.text('সম্পূর্ণ ইউপিআই'), findsOneWidget);
      expect(find.text('আংশিক নগদ ও ইউপিআই'), findsOneWidget);
      expect(find.text('বাকি (উধার)'), findsOneWidget);
      expect(find.text('বিল সংরক্ষণ ও নিশ্চিত করুন'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Responsive Layout: No overflow on mobile (390px) and tablet (800px)', (
      tester,
    ) async {
      final controller = TestBillingController(initialLocale: const Locale('en'));

      // 1. Mobile (390 x 844)
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        createBillingApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text('POS Billing Terminal'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. Tablet (800 x 1024)
      tester.view.physicalSize = const Size(800, 1024);
      await tester.pumpWidget(
        createBillingApp(controller: controller, locale: const Locale('en')),
      );
      await tester.pumpAndSettle();
      expect(find.text('POS Billing Terminal'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Resolves MRP and selling price from received batch pricing when variant price is 0',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final zeroPriceProducts = [
          ProductModel(
            productId: 'prod-zero',
            tenantId: 'owner-uid',
            businessId: 'bus-1',
            name: 'Purchased Item',
            brand: 'Sigmark',
            category: 'Paint',
            baseUnitId: 'ltr',
            status: 'ACTIVE',
            createdAt: DateTime(2025, 1, 1),
            updatedAt: DateTime(2025, 1, 1),
            variants: const [
              ProductVariantModel(
                variantId: 'var-zero',
                productId: 'prod-zero',
                businessId: 'bus-1',
                name: '1 Litre Zero',
                baseUnitId: 'ltr',
                sellingPrice: 0,
                mrp: 0,
                defaultGstRateBps: 1800,
                barcode: '890999999999',
                sku: 'ZERO-1L',
                productName: 'Purchased Item',
              ),
            ],
          ),
        ];

        final controller = TestBillingController(
          initialLocale: const Locale('en'),
          customProducts: zeroPriceProducts,
          initialReceivedPricing: {
            'var-zero': (mrp: 85000, sellingPrice: 72000), // ₹850.00 MRP, ₹720.00 Selling
          },
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // Scan barcode in the billing search box
        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, '890999999999');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Verify cart has the item with the resolved selling price (₹720.00), not ₹0.00
        expect(find.textContaining('720.00'), findsWidgets);
      },
    );

    testWidgets(
      'Blocks adding zero-price items and prompts cashier to enter selling price',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final zeroPriceProducts = [
          ProductModel(
            productId: 'prod-zero',
            tenantId: 'owner-uid',
            businessId: 'bus-1',
            name: 'Opening Stock Item Without Price',
            brand: 'Sigmark',
            category: 'Paint',
            baseUnitId: 'ltr',
            status: 'ACTIVE',
            createdAt: DateTime(2025, 1, 1),
            updatedAt: DateTime(2025, 1, 1),
            variants: const [
              ProductVariantModel(
                variantId: 'var-zero',
                productId: 'prod-zero',
                businessId: 'bus-1',
                name: '1 Litre Zero Price',
                baseUnitId: 'ltr',
                sellingPrice: 0,
                mrp: 0,
                defaultGstRateBps: 1800,
                barcode: '890000000001',
                sku: 'ZERO-PRICE-SKU',
                productName: 'Opening Stock Item Without Price',
              ),
            ],
          ),
        ];

        final controller = TestBillingController(
          initialLocale: const Locale('en'),
          customProducts: zeroPriceProducts,
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // 1. Scan barcode of zero price item
        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, '890000000001');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Should NOT add line to cart with 0.00
        expect(find.text('No items in this bill.'), findsOneWidget);
        // Should prompt cashier
        expect(
          find.textContaining('Please set selling price for'),
          findsOneWidget,
        );

        // 2. Attempt to click Add to Cart with 0 selling price
        final addToCartBtn = find.widgetWithIcon(FilledButton, Icons.add_shopping_cart);
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();

        // Still blocked from adding
        expect(find.text('No items in this bill.'), findsOneWidget);
        expect(
          find.text('Enter a selling price greater than ₹0.00 before adding to cart.'),
          findsOneWidget,
        );

        // 3. Enter selling price exceeding MRP
        final sellingPriceField =
            find.widgetWithText(TextField, 'Selling price (₹)');
        final mrpField = find.widgetWithText(TextField, 'MRP (₹)');

        await tester.enterText(mrpField, '400.00');
        await tester.enterText(sellingPriceField, '500.00');
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();

        expect(find.text('Selling price cannot exceed MRP.'), findsOneWidget);
        expect(find.text('No items in this bill.'), findsOneWidget);

        // 4. Enter valid selling price <= MRP
        await tester.enterText(sellingPriceField, '350.00');
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();

        // Product is successfully added to cart with price ₹350.00
        expect(find.text('No items in this bill.'), findsNothing);
        expect(find.textContaining('350.00'), findsWidgets);
      },
    );

    testWidgets(
      'Strictly blocks billing zero-stock products via search, barcode, and Add to Cart with strong message',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final stockProducts = [
          ProductModel(
            productId: 'prod-in-stock',
            tenantId: 'owner-uid',
            businessId: 'bus-1',
            name: 'In Stock Paint',
            brand: 'Sigmark',
            category: 'Paint',
            baseUnitId: 'ltr',
            status: 'ACTIVE',
            createdAt: DateTime(2025, 1, 1),
            updatedAt: DateTime(2025, 1, 1),
            variants: const [
              ProductVariantModel(
                variantId: 'var-in-stock',
                productId: 'prod-in-stock',
                businessId: 'bus-1',
                name: '1L Can',
                baseUnitId: 'ltr',
                sellingPrice: 30000,
                mrp: 35000,
                defaultGstRateBps: 1800,
                barcode: '890111111111',
                sku: 'STOCK-1L',
                productName: 'In Stock Paint',
                trackStock: true,
              ),
            ],
          ),
          ProductModel(
            productId: 'prod-out-of-stock',
            tenantId: 'owner-uid',
            businessId: 'bus-1',
            name: 'Zero Stock Paint',
            brand: 'Sigmark',
            category: 'Paint',
            baseUnitId: 'ltr',
            status: 'ACTIVE',
            createdAt: DateTime(2025, 1, 1),
            updatedAt: DateTime(2025, 1, 1),
            variants: const [
              ProductVariantModel(
                variantId: 'var-out-of-stock',
                productId: 'prod-out-of-stock',
                businessId: 'bus-1',
                name: '1L Dry',
                baseUnitId: 'ltr',
                sellingPrice: 40000,
                mrp: 45000,
                defaultGstRateBps: 1800,
                barcode: '890222222222',
                sku: 'ZERO-STOCK-1L',
                productName: 'Zero Stock Paint',
                trackStock: true,
              ),
            ],
          ),
        ];

        final controller = TestBillingController(
          initialLocale: const Locale('en'),
          customProducts: stockProducts,
          customStock: {
            'var-in-stock': 2000, // 2 units
            'var-out-of-stock': 0, // 0 units
          },
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // 1. Try scanning barcode of out-of-stock product
        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, '890222222222');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Must NOT add to bill
        expect(find.text('No items in this bill.'), findsOneWidget);
        // Must show strong popup modal
        expect(find.text('Out of Stock Alert'), findsOneWidget);
        await tester.tap(find.text('OK, Understood'));
        await tester.pumpAndSettle();

        // 2. Select out-of-stock item from autocomplete
        await tester.enterText(searchField, 'Zero Stock');
        await tester.pumpAndSettle();
        expect(find.byType(ListTile), findsWidgets);
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        // Verify product details card displays out of stock warning
        expect(find.textContaining('has 0 available inventory and cannot be billed.'), findsOneWidget);

        // Click Add to Cart button (which displays Out of stock)
        final addToCartBtn = find.widgetWithIcon(FilledButton, Icons.block);
        expect(addToCartBtn, findsOneWidget);
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();

        // Still blocked with popup!
        expect(find.text('No items in this bill.'), findsOneWidget);
        expect(find.text('Out of Stock Alert'), findsOneWidget);
        await tester.tap(find.text('OK, Understood'));
        await tester.pumpAndSettle();

        // 3. Test In-stock only filter chip
        final inStockChip = find.byType(FilterChip);
        expect(inStockChip, findsOneWidget);
        await tester.tap(inStockChip);
        await tester.pumpAndSettle();

        // Clear and search again
        await tester.enterText(searchField, 'Paint');
        await tester.pumpAndSettle();

        // In-stock item appears in dropdown
        expect(
          find.widgetWithText(ListTile, 'In Stock Paint • 1L Can'),
          findsWidgets,
        );
        // Out-of-stock item does NOT appear in dropdown options
        expect(
          find.widgetWithText(ListTile, 'Zero Stock Paint • 1L Dry'),
          findsNothing,
        );

        // 4. Test Insufficient stock guard when adding more than available
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        // Available is 2 units. Request 5 units.
        final qtyField = find.widgetWithText(TextField, 'Qty');
        await tester.enterText(qtyField, '5');
        final addInStockBtn = find.widgetWithIcon(FilledButton, Icons.add_shopping_cart);
        await tester.tap(addInStockBtn);
        await tester.pumpAndSettle();

        // Blocked with Insufficient Stock strong popup modal & message
        expect(find.text('No items in this bill.'), findsOneWidget);
        expect(find.text('Insufficient Stock Alert'), findsOneWidget);
        expect(
          find.textContaining('Quantity cannot be greater than stock quantity!'),
          findsOneWidget,
        );
        await tester.tap(find.text('OK, Understood'));
        await tester.pumpAndSettle();

        // 5. Add 2 units successfully
        await tester.enterText(qtyField, '2');
        await tester.tap(addInStockBtn);
        await tester.pumpAndSettle();

        // Added to cart!
        expect(find.text('No items in this bill.'), findsNothing);
        expect(find.text('2'), findsWidgets);

        // 6. Try to increment beyond available stock using '+' button
        final addQtyBtn = find.byTooltip('Increase quantity');
        await tester.tap(addQtyBtn);
        await tester.pumpAndSettle();

        // Blocked with popup!
        expect(find.text('Stock Limit Reached'), findsOneWidget);
        await tester.tap(find.text('OK, Understood'));
        await tester.pumpAndSettle();

        // Quantity remains 2
        expect(find.text('2'), findsWidgets);
      },
    );

    testWidgets(
      'User Scenario: Product has 8 units in stock, cashier attempts to bill 10 units -> Strong notification pops up and blocks billing',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final productWith8Stock = [
          ProductModel(
            productId: 'prod-8-stock',
            tenantId: 'owner-uid',
            businessId: 'bus-1',
            name: 'Asian Paints Apex 10L',
            brand: 'Asian Paints',
            category: 'Exterior Paint',
            baseUnitId: 'bucket',
            status: 'ACTIVE',
            createdAt: DateTime(2025, 1, 1),
            updatedAt: DateTime(2025, 1, 1),
            variants: const [
              ProductVariantModel(
                variantId: 'var-8-stock',
                productId: 'prod-8-stock',
                businessId: 'bus-1',
                name: '10L Bucket',
                baseUnitId: 'bucket',
                sellingPrice: 280000, // ₹2,800.00
                mrp: 320000, // ₹3,200.00
                defaultGstRateBps: 1800,
                barcode: '890888888888',
                sku: 'APEX-10L',
                productName: 'Asian Paints Apex 10L',
                trackStock: true,
              ),
            ],
          ),
        ];

        final controller = TestBillingController(
          initialLocale: const Locale('en'),
          customProducts: productWith8Stock,
          customStock: {
            'var-8-stock': 8000, // Exactly 8 units in stock
          },
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // 1. Select the product
        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, 'Asian Paints');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ListTile).first);
        await tester.pumpAndSettle();

        // Verify available stock is shown as 8
        expect(find.text('8'), findsWidgets);

        // 2. Cashier enters quantity 10 (which is greater than stock 8)
        final qtyField = find.widgetWithText(TextField, 'Qty');
        await tester.enterText(qtyField, '10');
        await tester.pumpAndSettle();

        // Real-time helper in the Qty field shows Max limit
        expect(find.text('Max: 8'), findsOneWidget);

        // 3. Cashier attempts to click "Add to cart"
        final addToCartBtn = find.widgetWithIcon(FilledButton, Icons.add_shopping_cart);
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();

        // 4. Strong notification popup MUST appear!
        expect(find.text('Insufficient Stock Alert'), findsOneWidget);
        expect(
          find.textContaining('Quantity cannot be greater than stock quantity!'),
          findsOneWidget,
        );
        expect(find.textContaining('Available in Stock:'), findsOneWidget);
        expect(find.text('8 units'), findsOneWidget);
        expect(find.textContaining('Requested Quantity:'), findsOneWidget);
        expect(find.text('10 units'), findsOneWidget);

        // Bill line must NOT be added
        expect(find.text('No items in this bill.'), findsOneWidget);

        // 5. Cashier can tap "Set Qty to 8" in the popup to automatically adjust
        final adjustBtn = find.text('Set Qty to 8');
        expect(adjustBtn, findsOneWidget);
        await tester.tap(adjustBtn);
        await tester.pumpAndSettle();

        // Quantity field is automatically updated to 8!
        expect(find.widgetWithText(TextField, '8'), findsWidgets);

        // 6. Now cashier clicks "Add to cart" with valid stock quantity 8
        await tester.tap(addToCartBtn);
        await tester.pumpAndSettle();

        // Bill line is successfully added!
        expect(find.text('No items in this bill.'), findsNothing);
        expect(find.text('Asian Paints Apex 10L • 10L Bucket'), findsWidgets);
        expect(find.text('8'), findsWidgets);
      },
    );

    testWidgets(
      'Successfully finalizes GST bill even when business gstState is null (no blocking error)',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mockBilling = MockBillingRepository();
        final controller = TestBillingController(
          mockBilling: mockBilling,
          customBusinesses: const [
            BusinessModel(
              businessId: 'bus-1',
              ownerUid: 'owner-uid',
              businessName: 'Suman Enterprises',
              normalizedBusinessName: 'suman enterprises',
              businessTypeId: 'retail',
              businessTypeName: 'Retail Store',
              isActive: true,
              gstState: null,
              gstin: null,
            ),
          ],
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // 1. Add item to cart
        final searchField = find.byType(TextField).first;
        await tester.enterText(searchField, '890123456789');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('No items in this bill.'), findsNothing);

        // 2. Click FINALIZE & SAVE BILL
        final finalizeBtn =
            find.widgetWithText(FilledButton, 'FINALIZE & SAVE BILL');
        expect(finalizeBtn, findsOneWidget);
        final btnWidget = tester.widget<FilledButton>(finalizeBtn);
        expect(btnWidget.onPressed, isNotNull);
        btnWidget.onPressed!();
        await tester.pumpAndSettle();

        // 3. Verify no "Complete GST setup before creating a GST bill." error
        expect(
          find.text('Complete GST setup before creating a GST bill.'),
          findsNothing,
        );

        // 4. Verify billingRepository.finalize was invoked successfully with GST tax mode
        expect(mockBilling.lastFinalizeRequest, isNotNull);
        expect(mockBilling.lastFinalizeRequest!.taxMode, BillingTaxMode.gst);
        expect(mockBilling.lastFinalizeRequest!.businessId, 'bus-1');
        expect(mockBilling.lastFinalizeRequest!.lines.length, 1);
      },
    );

    testWidgets(
      'Multi-Price Lot Handling: Scanning barcode for item with different purchase lot prices prompts Lot Selection dialog',
      (WidgetTester tester) async {
        final mockBilling = MockBillingRepository();
        final controller = TestBillingController(
          mockBilling: mockBilling,
          variantBatches: {
            'var-1': [
              const VariantBatchPriceOption(
                batchId: 'BATCH-001',
                internalBatchNo: 'PUR-000010',
                availableQty: 10,
                sellingPricePaise: 55000, // ₹550.00
                mrpPaise: 80000, // ₹800.00
                purchaseRatePaise: 30000, // ₹300.00
              ),
              const VariantBatchPriceOption(
                batchId: 'BATCH-002',
                internalBatchNo: 'PUR-000013',
                availableQty: 8,
                sellingPricePaise: 65000, // ₹650.00
                mrpPaise: 90000, // ₹900.00
                purchaseRatePaise: 43000, // ₹430.00
              ),
            ],
          },
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // Scan barcode
        final searchField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText?.contains('barcode') == true,
        );
        await tester.enterText(searchField, '890123456789');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Verify Lot Price Selection dialog appears!
        expect(find.text('Select Selling Price / Lot'), findsOneWidget);
        expect(find.text('₹550.00'), findsOneWidget);
        expect(find.text('₹650.00'), findsOneWidget);
        expect(find.text('10 in stock'), findsOneWidget);
        expect(find.text('8 in stock'), findsOneWidget);

        // Tap the second lot (₹650.00)
        await tester.tap(find.text('₹650.00'));
        await tester.pumpAndSettle();

        // Verify dialog dismissed and item added to cart with ₹650.00!
        expect(find.text('Select Selling Price / Lot'), findsNothing);
        expect(find.text('No items in this bill.'), findsNothing);
        expect(find.text('₹650.00'), findsWidgets);
      },
    );

    testWidgets(
      'Single Price Lot Handling: When all lots have same selling price, scanning barcode adds directly without dialog',
      (WidgetTester tester) async {
        final mockBilling = MockBillingRepository();
        final controller = TestBillingController(
          mockBilling: mockBilling,
          variantBatches: {
            'var-1': [
              const VariantBatchPriceOption(
                batchId: 'BATCH-001',
                internalBatchNo: 'PUR-000010',
                availableQty: 10,
                sellingPricePaise: 55000, // ₹550.00
                mrpPaise: 80000,
              ),
              const VariantBatchPriceOption(
                batchId: 'BATCH-002',
                internalBatchNo: 'PUR-000011',
                availableQty: 8,
                sellingPricePaise: 55000, // Same ₹550.00
                mrpPaise: 80000,
              ),
            ],
          },
        );

        await tester.pumpWidget(
          createBillingApp(controller: controller, locale: const Locale('en')),
        );
        await tester.pumpAndSettle();

        // Scan barcode
        final searchField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.hintText?.contains('barcode') == true,
        );
        await tester.enterText(searchField, '890123456789');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Verify NO dialog appeared and item directly added to cart
        expect(find.text('Select Selling Price / Lot'), findsNothing);
        expect(find.text('No items in this bill.'), findsNothing);
        expect(find.text('₹550.00'), findsWidgets);
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/customer_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/billing/billing_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class TestBillingController extends EntryController {
  TestBillingController({Locale? initialLocale})
      : _locale = initialLocale ?? const Locale('en');

  Locale _locale;

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
  Map<String, int> get productStock => {'var-1': 25000}; // 25 units
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
  });
}

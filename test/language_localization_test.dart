import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/domain/entities/dashboard_summary.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/dashboard/admin_dashboard_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'dashboard_overflow_regression_test.dart'
    show DashboardPopulatedController, MockSyncEngine;

void main() {
  group('Multi-Language Localization & Switcher Tests', () {
    test('AppLocalizations supports English, Hindi, and Bengali', () {
      expect(
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
        containsAll({'en', 'hi', 'bn'}),
      );
    });

    final testSummary = DashboardSummary(
      salesTotal: 450000.0,
      salesCount: 85,
      purchaseTotal: 320000.0,
      purchaseCount: 42,
      productCount: 140,
      customerCount: 65,
      salesDueTotal: 75000.0,
      salesDueCount: 12,
      purchaseDueTotal: 45000.0,
      activeProductCount: 140,
      inactiveProductCount: 8,
      outOfStockCount: 4,
      lowStockCount: 9,
      customerDueTotal: 75000.0,
      customersWithDueCount: 12,
      weeklySales: const [],
      recentSales: const [],
      topProducts: const [],
      lowStockProducts: const [
        LowStockProductSummary(
          variantId: 'v1',
          name: 'Sigmark High Gloss Enamel 4L',
          sku: 'SIG-HG-4L',
          unit: 'ltr',
          currentStock: 0,
          reorderLevel: 10,
          isOutOfStock: true,
        ),
      ],
    );

    testWidgets('Renders in English, switches to Hindi and Bengali seamlessly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockSync = MockSyncEngine();
      final controller = DashboardPopulatedController(
        mockSync: mockSync,
        mockSummary: testSummary,
      );
      addTearDown(mockSync.dispose);
      addTearDown(controller.dispose);

      // 1. Verify English default strings
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('en-app'),
          theme: AppTheme.light,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WORKSPACE'), findsOneWidget);
      expect(find.text('Total sales'), findsOneWidget);
      expect(find.text('Commercial Liquidity & Cashflow Velocity'), findsOneWidget);
      expect(find.text('Inventory Health & Stock Intelligence'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. Switch to Hindi (हिंदी)
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('hi-app'),
          theme: AppTheme.light,
          locale: const Locale('hi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('कार्यक्षेत्र'), findsOneWidget);
      expect(find.text('कुल बिक्री'), findsOneWidget);
      expect(find.text('व्यापारिक तरलता और नकदी प्रवाह'), findsOneWidget);
      expect(find.text('इन्वेंट्री स्वास्थ्य और स्टॉक विश्लेषण'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 3. Switch to Bengali (বাংলা)
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('bn-app'),
          theme: AppTheme.light,
          locale: const Locale('bn'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ওয়ার্কস্পেস'), findsOneWidget);
      expect(find.text('মোট বিক্রি'), findsOneWidget);
      expect(find.text('ব্যবসায়িক তারল্য ও নগদ প্রবাহ'), findsOneWidget);
      expect(find.text('ইনভেন্টরি স্বাস্থ্য ও স্টক অ্যানালিটিক্স'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Zero overflow across mobile (390px), tablet (820px), desktop (1440px) in all 3 languages', (
      tester,
    ) async {
      final mockSync = MockSyncEngine();
      final controller = DashboardPopulatedController(
        mockSync: mockSync,
        mockSummary: testSummary,
      );
      addTearDown(mockSync.dispose);
      addTearDown(controller.dispose);

      for (final locale in [
        const Locale('en'),
        const Locale('hi'),
        const Locale('bn'),
      ]) {
        for (final width in [390.0, 820.0, 1233.3, 1440.0]) {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('${locale.languageCode}-$width'),
              theme: AppTheme.light,
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AdminDashboardPage(controller: controller),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'Overflow occurred at $width in locale ${locale.languageCode}',
          );
        }
      }
    });
  });
}

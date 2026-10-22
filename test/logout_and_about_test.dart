import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/about/about_page.dart';
import 'package:testflutter/presentation/dashboard/admin_dashboard_page.dart';
import 'package:testflutter/presentation/widgets/logout_dialog.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'dashboard_navigation_test.dart' show NavigationController;

class TestLogoutController extends NavigationController {
  bool logoutCalled = false;
  String testBusinessName = 'Suman Enterprise';

  @override
  String get currentBusinessName => testBusinessName;

  @override
  BusinessModel? get currentBusiness => BusinessModel(
        businessId: 'biz-1',
        ownerUid: 'owner',
        businessName: testBusinessName,
        normalizedBusinessName: testBusinessName.toLowerCase(),
        businessTypeId: 'retail',
        businessTypeName: 'Retail',
        isActive: true,
      );

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

Widget createTestApp({required Widget child, Locale locale = const Locale('en')}) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  group('Logout Confirmation Dialog Tests', () {
    testWidgets('Cancel button dismisses dialog without calling logout', (tester) async {
      final controller = TestLogoutController();

      await tester.pumpWidget(
        createTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showLogoutConfirmationDialog(context, controller),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      expect(
        find.textContaining('Are you sure you want to log out of your account?'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Log out'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsNothing);
      expect(controller.logoutCalled, isFalse);
    });

    testWidgets('Confirm button calls logout on controller', (tester) async {
      final controller = TestLogoutController();

      await tester.pumpWidget(
        createTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showLogoutConfirmationDialog(context, controller),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsNothing);
      expect(controller.logoutCalled, isTrue);
    });

    testWidgets('Renders properly in Hindi (हिन्दी)', (tester) async {
      final controller = TestLogoutController();

      await tester.pumpWidget(
        createTestApp(
          locale: const Locale('hi'),
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showLogoutConfirmationDialog(context, controller),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('लॉग आउट करें?'), findsOneWidget);
      expect(find.text('रद्द करें'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'लॉग आउट'), findsOneWidget);
    });
  });

  group('About Page and Dialog Tests', () {
    testWidgets('About dialog displays company info, website link, and active business name',
        (tester) async {
      final controller = TestLogoutController();

      await tester.pumpWidget(
        createTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAboutNubiBillDialog(context, controller),
              child: const Text('Open About'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open About'));
      await tester.pumpAndSettle();

      expect(find.text('NubiBill Business ERP'), findsWidgets);
      expect(find.textContaining('v${EnvironmentConfig.appVersion}'), findsWidgets);
      expect(find.text('https://nubibill.com'), findsOneWidget);
      expect(find.textContaining('Suman Enterprise'), findsWidgets);
      expect(find.text('support@nubibill.com'), findsOneWidget);
      expect(find.text('Official Website'), findsOneWidget);
    });

    testWidgets('About page standalone view renders completely', (tester) async {
      final controller = TestLogoutController();

      await tester.pumpWidget(
        createTestApp(
          child: AboutPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('About NubiBill Business ERP'), findsOneWidget);
      expect(find.text('NubiBill Business ERP'), findsWidgets);
      expect(find.text('https://nubibill.com'), findsOneWidget);
      expect(find.text('Core Enterprise Capabilities'), findsOneWidget);
      expect(find.text('Multi-Outlet & Godown Warehousing'), findsOneWidget);
      expect(find.text('Offline-First SQLite Architecture'), findsOneWidget);
    });
  });

  group('Admin Dashboard Business Name and Version Bar Tests', () {
    testWidgets('Sidebar header shows business name and footer shows NubiBill Business ERP v<version>',
        (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TestLogoutController();
      controller.testBusinessName = 'Suman Enterprise';

      await tester.pumpWidget(
        createTestApp(
          child: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      // Sidebar header displays business name "Suman Enterprise"
      expect(find.text('Suman Enterprise'), findsWidgets);

      // Sidebar footer displays "NubiBill Business ERP v<version>"
      expect(
        find.text('NubiBill Business ERP v${EnvironmentConfig.appVersion}'),
        findsOneWidget,
      );

      // Tapping logout in sidebar prompts confirmation dialog
      final logoutBtn = find.byTooltip('Log out');
      expect(logoutBtn, findsOneWidget);
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.logoutCalled, isFalse);
    });
  });
}

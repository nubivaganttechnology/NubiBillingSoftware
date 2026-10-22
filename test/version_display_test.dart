import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/presentation/auth/login_page.dart';
import 'package:testflutter/presentation/dashboard/admin_dashboard_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'dashboard_navigation_test.dart' show NavigationController;

class _LoginTestController extends NavigationController {
  @override
  String get error => '';
}

void main() {
  testWidgets('AdminDashboardPage displays version number in sidebar and profile menu', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = NavigationController(showOverview: true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminDashboardPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Verify version text in sidebar
    expect(find.text('v${EnvironmentConfig.appVersion}'), findsOneWidget);

    // Open profile menu
    await tester.tap(find.byTooltip('Profile menu'));
    await tester.pumpAndSettle();

    // Verify version text in profile menu
    expect(find.text('Version ${EnvironmentConfig.appVersion}'), findsOneWidget);
  });

  testWidgets('LoginPage displays version number at bottom of login form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _LoginTestController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: LoginPage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version ${EnvironmentConfig.appVersion}'), findsOneWidget);
  });
}

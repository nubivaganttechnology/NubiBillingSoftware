import 'package:flutter/material.dart';

import '../presentation/app_controller.dart';
import '../presentation/auth/login_page.dart';
import '../presentation/dashboard/admin_dashboard_page.dart';
import '../presentation/maintenance/maintenance_page.dart';
import '../presentation/splash/splash_page.dart';
import '../presentation/workspace/workspace_pages.dart';

class AppRouter extends StatelessWidget {
  const AppRouter({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.status) {
      case AppStatus.loading:
        return const Scaffold(body: SplashPage());
      case AppStatus.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    controller.error.isEmpty
                        ? 'We could not connect to the service.'
                        : controller.error,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: controller.retry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      case AppStatus.maintenance:
        return Scaffold(body: MaintenancePage(controller: controller));
      case AppStatus.login:
        return Scaffold(body: LoginPage(controller: controller));
      case AppStatus.businessSelector:
        return BusinessSelectorPage(controller: controller);
      case AppStatus.createBusiness:
        return CreateBusinessPage(controller: controller);
      case AppStatus.outletSelector:
        return OutletSelectorPage(controller: controller);
      case AppStatus.createOutlet:
        return CreateOutletPage(controller: controller);
      case AppStatus.dashboard:
        return AdminDashboardPage(controller: controller);
      case AppStatus.denied:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_bad_outlined, size: 52),
                  const SizedBox(height: 12),
                  Text(controller.error, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: controller.logout,
                    child: const Text('Back to sign in'),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

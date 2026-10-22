import 'package:flutter/material.dart';

import '../app_controller.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext c) {
    final cfg = controller.appConfig;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cfg?.maintenanceImageUrl?.isNotEmpty == true)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    cfg!.maintenanceImageUrl!,
                    height: 180,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              const Icon(
                Icons.construction_rounded,
                size: 54,
                color: Color(0xFFC18B35),
              ),
              const SizedBox(height: 16),
              Text(
                cfg?.maintenanceTitle?.isNotEmpty == true
                    ? cfg!.maintenanceTitle!
                    : 'System Maintenance',
                style: Theme.of(c).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                cfg?.maintenanceMessage?.isNotEmpty == true
                    ? cfg!.maintenanceMessage!
                    : 'We are making a few improvements. Please check back shortly.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: controller.retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

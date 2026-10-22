import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app_controller.dart';

/// Shows a professional confirmation dialog before logging the user out.
Future<void> showLogoutConfirmationDialog(
  BuildContext context,
  AppController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.logout_rounded,
              color: Colors.red.shade700,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            l10n?.logoutConfirmTitle ?? 'Log out?',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Text(
        l10n?.logoutConfirmMessage ??
            'Are you sure you want to log out of your account? Any unsaved changes in progress may be lost.',
        style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n?.cancel ?? 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n?.logout ?? 'Log out'),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await controller.logout();
  }
}

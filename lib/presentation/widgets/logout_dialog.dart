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
      elevation: 16,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 10),
      contentPadding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
      actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFEE2E2), Color(0xFFFECACA)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF87171),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.white,
                  offset: Offset(0, -1),
                  blurRadius: 1,
                ),
                BoxShadow(
                  color: Color(0xFFEF4444),
                  offset: Offset(0, 2.5),
                  blurRadius: 0,
                ),
                BoxShadow(
                  color: Color(0x26EF4444),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.logout_rounded,
              color: Color(0xFFDC2626),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              l10n?.logoutConfirmTitle ?? 'Log out?',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
      content: Text(
        l10n?.logoutConfirmMessage ??
            'Are you sure you want to log out of your account? Any unsaved changes in progress may be lost.',
        style: const TextStyle(fontSize: 14, color: Color(0xFF475569), height: 1.4),
      ),
      actions: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF94A3B8),
                offset: Offset(0, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF475569),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n?.cancel ?? 'Cancel',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Color(0xFF991B1B),
                offset: Offset(0, 2.5),
                blurRadius: 0,
              ),
              BoxShadow(
                color: Color(0x33DC2626),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n?.logout ?? 'Log out',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await controller.logout();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/environment_config.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';

/// Opens the About NubiBill Business ERP dialog.
Future<void> showAboutNubiBillDialog(
  BuildContext context,
  AppController controller,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      elevation: 16,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: AboutPageContent(controller: controller, isDialog: true),
      ),
    ),
  );
}

/// Standalone About Page for NubiBill Business ERP.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('About NubiBill Business ERP'),
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AboutPageContent(controller: controller, isDialog: false),
          ),
        ),
      ),
    );
  }
}

class AboutPageContent extends StatelessWidget {
  const AboutPageContent({
    super.key,
    required this.controller,
    required this.isDialog,
  });

  final AppController controller;
  final bool isDialog;

  Future<void> _openUrl(BuildContext context, String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: urlString));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Link copied to clipboard: $urlString'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final businessName = controller.currentBusiness?.businessName ?? 'Suman Enterprise';
    final outletName = controller.currentOutlet?.outletName ?? 'Main Enterprise Hub';

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Header Hero Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A1120), Color(0xFF162338), Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border(
              bottom: BorderSide(color: Color(0x40C18B35), width: 2),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFBBF24), Color(0xFFD97706), Color(0xFF92400E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFDE68A).withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.4),
                          offset: const Offset(0, -1),
                          blurRadius: 1,
                        ),
                        const BoxShadow(
                          color: Color(0xFF78350F),
                          offset: Offset(0, 3.5),
                          blurRadius: 0,
                        ),
                        BoxShadow(
                          color: const Color(0xFFD97706).withValues(alpha: 0.5),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Color(0xFF0F172A),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // HIGHLIGHTED NubiBill Business ERP
                        const Text(
                          'NubiBill Business ERP',
                          style: TextStyle(
                            color: Color(0xFFFDE68A),
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                            shadows: [
                              Shadow(
                                color: Color(0x99F59E0B),
                                blurRadius: 12,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2E2211), Color(0xFF1A1308)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0xFF000000),
                                offset: Offset(0, 2),
                                blurRadius: 0,
                              ),
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 4,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Text(
                            'v${EnvironmentConfig.appVersion} • Enterprise Edition',
                            style: const TextStyle(
                              color: Color(0xFFFCD34D),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                l10n?.aboutAppDescription ??
                    'High-performance, offline-first enterprise management solution engineered for retail, wholesale, godown logistics, and commercial trade operations.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        // 2. Body Details
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 3D Business Context Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Colors.white, Color(0xFFF8FAFC)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(0, -1),
                        blurRadius: 1,
                      ),
                      BoxShadow(
                        color: Color(0xFFCBD5E1),
                        offset: Offset(0, 3),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 8,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xFF020617),
                              offset: Offset(0, 2),
                              blurRadius: 0,
                            ),
                            BoxShadow(
                              color: Color(0x1F000000),
                              blurRadius: 4,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.apartment_rounded,
                          size: 20,
                          color: Color(0xFFF0C36D),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              businessName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Active Outlet: $outletName',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFDCFCE7), Color(0xFFBBF7D0)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF86EFAC),
                            width: 1,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0xFF4ADE80),
                              offset: Offset(0, 2),
                              blurRadius: 0,
                            ),
                            BoxShadow(
                              color: Color(0x1416A34A),
                              blurRadius: 4,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 12,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Active',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Features Overview
                const Text(
                  'Core Enterprise Capabilities',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                _FeatureRow(
                  icon: Icons.offline_bolt_outlined,
                  color: Color(0xFF0284C7),
                  title: 'Offline-First SQLite Architecture',
                  subtitle: 'Continue billing and inventory ops seamlessly without internet connectivity.',
                ),
                _FeatureRow(
                  icon: Icons.receipt_long_outlined,
                  color: Color(0xFF16A34A),
                  title: 'Rapid GST Billing & Invoicing',
                  subtitle: 'Multi-rate GST, barcode scanning, shade/spec variations, and thermal receipts.',
                ),
                _FeatureRow(
                  icon: Icons.warehouse_outlined,
                  color: Color(0xFFD97706),
                  title: 'Multi-Outlet & Godown Warehousing',
                  subtitle: 'Inter-branch transfers, lot batch expiry, and live inventory reconciliations.',
                ),
                _FeatureRow(
                  icon: Icons.fingerprint_rounded,
                  color: Color(0xFF8B5CF6),
                  title: 'Biometric Face Attendance & Payroll',
                  subtitle: 'AI-assisted anti-spoofing facial recognition for staff shifts and wage payouts.',
                ),

                const SizedBox(height: 20),

                // Official Links & Company Info
                const Text(
                  'Company & Web Resources',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                _LinkTile(
                  icon: Icons.language,
                  title: l10n?.companyWebsite ?? 'Official Website',
                  value: 'https://nubibill.com',
                  onTap: () => _openUrl(context, 'https://nubibill.com'),
                ),
                _LinkTile(
                  icon: Icons.menu_book_outlined,
                  title: l10n?.documentation ?? 'Documentation & User Guide',
                  value: 'https://nubibill.com/docs',
                  onTap: () => _openUrl(context, 'https://nubibill.com/docs'),
                ),
                _LinkTile(
                  icon: Icons.headset_mic_outlined,
                  title: l10n?.technicalSupport ?? 'Technical Support',
                  value: 'support@nubibill.com',
                  onTap: () => _openUrl(context, 'mailto:support@nubibill.com'),
                ),
                _LinkTile(
                  icon: Icons.shield_outlined,
                  title: l10n?.privacyPolicy ?? 'Privacy Policy',
                  value: 'https://nubibill.com/privacy',
                  onTap: () => _openUrl(context, 'https://nubibill.com/privacy'),
                ),
                _LinkTile(
                  icon: Icons.gavel_outlined,
                  title: l10n?.termsOfService ?? 'Terms of Service',
                  value: 'https://nubibill.com/terms',
                  onTap: () => _openUrl(context, 'https://nubibill.com/terms'),
                ),

                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    '© 2026 Nubi Technologies Pvt. Ltd. All rights reserved.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 3. Bottom Action Bar (if dialog)
        if (isDialog)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(0, -1),
                        blurRadius: 1,
                      ),
                      BoxShadow(
                        color: Color(0xFF94A3B8),
                        offset: Offset(0, 2.5),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 4,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0F172A),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openUrl(context, 'https://nubibill.com'),
                    icon: const Icon(Icons.open_in_new, size: 16, color: Color(0xFF2563EB)),
                    label: const Text('Visit Website', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF334155),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xFF020617),
                        offset: Offset(0, 3),
                        blurRadius: 0,
                      ),
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 6,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (isDialog) {
      return content;
    }

    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: content,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Colors.white, Color(0xFFFBFDFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.white,
              offset: Offset(0, -1),
              blurRadius: 1,
            ),
            BoxShadow(
              color: Color(0xFFCBD5E1),
              offset: Offset(0, 2.5),
              blurRadius: 0,
            ),
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 6,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.18),
                    color.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    offset: const Offset(0, 2),
                    blurRadius: 0,
                  ),
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.white, Color(0xFFF9FAFB)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.white,
                    offset: Offset(0, -1),
                    blurRadius: 1,
                  ),
                  BoxShadow(
                    color: Color(0xFFCBD5E1),
                    offset: Offset(0, 3),
                    blurRadius: 0,
                  ),
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 6,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEEF2FF), Color(0xFFE0E7FF)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFC7D2FE),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFFA5B4FC),
                          offset: Offset(0, 1.5),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 18, color: const Color(0xFF3B82F6)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFCBD5E1),
                        width: 1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xFF94A3B8),
                          offset: Offset(0, 1.5),
                          blurRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_outward_rounded,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import '../../data/sync/sync_engine.dart';

import 'package:flutter/material.dart';

import '../../core/config/environment_config.dart';
import '../../core/permissions/permission_catalog.dart';
import '../../domain/entities/dashboard_summary.dart';
import '../employees/employee_pages.dart';
import '../procurement/supplier_pages.dart';
import '../procurement/purchase_pages.dart';
import '../procurement/supplier_ledger_dashboard_page.dart';
import '../billing/billing_page.dart';
import '../sales/sales_entry_page.dart';
import '../customers/customer_pages.dart';
import '../products/product_pages.dart';
import '../products/barcode_management_page.dart';
import '../inventory/inventory_dashboard_page.dart';
import '../storage/storage_pages.dart' as storage;
import '../reports/reports_page.dart';
import '../expenses/expense_pages.dart';
import '../staff_salary/staff_salary_page.dart';
import '../staff_salary/staff_attendance_page.dart';
import '../settings/settings_page.dart';
import '../app_controller.dart';
import '../about/about_page.dart';
import '../widgets/logout_dialog.dart';
import '../../l10n/app_localizations.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}
// sksuman13@gmail.com

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  String _selectedModule = 'dashboard';
  String? _barcodeProductId;
  String? _barcodeVariantId;
  int _attendanceInitialTab = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.refreshPendingAttendanceCount();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final wide = MediaQuery.sizeOf(context).width >= 1040;
    final isOwner = controller.appContext?.accountType == 'owner';
    final permissions = controller.appContext?.permissions ?? const <String>[];
    final modules = PermissionCatalog.visibleModules(permissions);
    if (isOwner) {
      if (modules.isEmpty) modules.addAll(PermissionCatalog.modules);
      if (!modules.any((item) => item.id == 'attendance')) {
        final attendanceMod = PermissionCatalog.modules
            .where((item) => item.id == 'attendance')
            .firstOrNull;
        if (attendanceMod != null) modules.add(attendanceMod);
      }
      if (!modules.any((item) => item.id == 'racks')) {
        modules.add(
          PermissionCatalog.modules.firstWhere((item) => item.id == 'racks'),
        );
      }
      if (!modules.any((item) => item.id == 'salary')) {
        modules.add(
          PermissionCatalog.modules.firstWhere((item) => item.id == 'salary'),
        );
      }
      if (!modules.any((item) => item.id == 'barcode')) {
        modules.add(
          PermissionCatalog.modules.firstWhere((item) => item.id == 'barcode'),
        );
      }
      if (!modules.any((item) => item.id == 'supplier_ledger')) {
        final ledgerMod = PermissionCatalog.modules
            .where((item) => item.id == 'supplier_ledger')
            .firstOrNull;
        if (ledgerMod != null) modules.add(ledgerMod);
      }
    } else {
      if (controller.canViewStaffAttendance() &&
          !modules.any((item) => item.id == 'attendance')) {
        final attendanceMod = PermissionCatalog.modules
            .where((item) => item.id == 'attendance')
            .firstOrNull;
        if (attendanceMod != null) {
          modules.add(attendanceMod);
        }
      }
      if (_canViewSalary(controller) &&
          !modules.any((item) => item.id == 'salary')) {
        final salaryModule = PermissionCatalog.modules
            .where((item) => item.id == 'salary')
            .firstOrNull;
        if (salaryModule != null) {
          modules.add(salaryModule);
        }
      }
      if ((isOwner ||
              PermissionCatalog.allows('suppliers', permissions) ||
              PermissionCatalog.allows('purchase', permissions)) &&
          !modules.any((item) => item.id == 'supplier_ledger')) {
        final ledgerMod = PermissionCatalog.modules
            .where((item) => item.id == 'supplier_ledger')
            .firstOrNull;
        if (ledgerMod != null) {
          modules.add(ledgerMod);
        }
      }
    }
    if (modules.isNotEmpty &&
        !modules.any((item) => item.id == _selectedModule)) {
      _selectedModule = modules.first.id;
    }
    final selected = modules.where((item) => item.id == _selectedModule);
    final activeModule = selected.isEmpty ? null : selected.first;

    return Scaffold(
      key: _scaffoldKey,
      drawer: wide
          ? null
          : Drawer(
              child: _Sidebar(
                controller: controller,
                modules: modules,
                selectedId: _selectedModule,
                onSelect: _selectModule,
              ),
            ),
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: 254,
              child: _Sidebar(
                controller: controller,
                modules: modules,
                selectedId: _selectedModule,
                onSelect: _selectModule,
              ),
            ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  controller: controller,
                  showMenu: !wide,
                  // Products are outlet-scoped, so they keep the Outlet selector.
                  businessLevelModule: _selectedModule == 'godowns',
                  onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
                  onOpenAttendance: () {
                    final target = modules.where((m) => m.id == 'attendance');
                    if (target.isNotEmpty) _selectModule(target.first);
                  },
                ),
                Expanded(
                  child: activeModule == null
                      ? const _NoPermissions()
                      : _ModuleBody(
                          controller: controller,
                          module: activeModule,
                          isOwner: isOwner,
                          attendanceInitialTab: _attendanceInitialTab,
                          onOpenModule: (id) {
                            if (id == 'attendance:approval') {
                              _attendanceInitialTab = 1;
                              final target = modules.where(
                                (item) => item.id == 'attendance',
                              );
                              if (target.isNotEmpty) _selectModule(target.first);
                              return;
                            }
                            final target = modules.where(
                              (item) => item.id == id,
                            );
                            if (target.isNotEmpty) _selectModule(target.first);
                          },
                          initialBarcodeProductId: _barcodeProductId,
                          initialBarcodeVariantId: _barcodeVariantId,
                          onOpenBarcode: (productId, variantId) {
                            setState(() {
                              _selectedModule = 'barcode';
                              _barcodeProductId = productId;
                              _barcodeVariantId = variantId;
                            });
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectModule(AdminModule module) {
    _scaffoldKey.currentState?.closeDrawer();
    if (module.id == 'businesses') {
      widget.controller.openBusinessSelector();
      return;
    }
    setState(() {
      _selectedModule = module.id;
      if (module.id != 'barcode') {
        _barcodeProductId = null;
        _barcodeVariantId = null;
      }
      if (module.id != 'attendance') {
        _attendanceInitialTab = 0;
      }
    });
  }
}

String _localizedModuleLabel(
  BuildContext context,
  String moduleId,
  String defaultLabel,
) {
  final l10n = AppLocalizations.of(context);
  if (l10n == null) return defaultLabel;
  return switch (moduleId) {
    'dashboard' => l10n.dashboard,
    'billing' => l10n.billing,
    'sales' => l10n.sales,
    'purchase' || 'purchases' => l10n.purchases,
    'products' => l10n.products,
    'godowns' => l10n.godowns,
    'racks' => l10n.racks,
    'barcode' => l10n.barcode,
    'customers' => l10n.customers,
    'suppliers' => l10n.suppliers,
    'supplier_ledger' => switch (AppLocalizations.of(context)?.localeName) {
      'bn' => 'সাপ্লায়ার লেজার (খাতা)',
      'hi' => 'सप्लायर लेजर (खाता)',
      _ => 'Supplier Ledger',
    },
    'expenses' => l10n.expenses,
    'employees' => l10n.staffRoles,
    'settings' => l10n.settings,
    'businesses' => l10n.businesses,
    _ => defaultLabel,
  };
}

String _safeBusinessName(AppController controller) {
  try {
    return controller.currentBusinessName;
  } catch (_) {
    return 'Suman Enterprise';
  }
}

bool _canViewSalary(AppController controller) {
  try {
    return controller.canViewStaffSalary();
  } catch (_) {
    return false;
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.modules,
    required this.selectedId,
    required this.onSelect,
  });
  final AppController controller;
  final List<AdminModule> modules;
  final String selectedId;
  final ValueChanged<AdminModule> onSelect;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF10263D),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A56), Color(0xFF10243A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    offset: Offset(0, 3),
                    blurRadius: 0,
                  ),
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFBBF24), Color(0xFFD97706), Color(0xFF92400E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFDE68A).withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.35),
                          offset: const Offset(0, -1),
                          blurRadius: 1,
                        ),
                        const BoxShadow(
                          color: Color(0xFF78350F),
                          offset: Offset(0, 2.5),
                          blurRadius: 0,
                        ),
                        BoxShadow(
                          color: const Color(0xFFD97706).withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: Color(0xFF0F172A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _safeBusinessName(controller),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          controller.currentOutlet?.outletName.toUpperCase() ??
                              'BUSINESS ERP',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF0C36D),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 9),
            child: Text(
              AppLocalizations.of(context)?.workspace ?? 'WORKSPACE',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: modules.length,
              itemBuilder: (context, index) {
                final module = modules[index];
                final active = module.id == selectedId;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Container(
                    decoration: active
                        ? BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF26476B), Color(0xFF19324C)],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFF0C36D).withValues(alpha: 0.4),
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66000000),
                                offset: Offset(0, 2),
                                blurRadius: 0,
                              ),
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          )
                        : null,
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Icon(
                          module.icon,
                          size: 20,
                          color: active
                              ? const Color(0xFFF0C36D)
                              : Colors.white70,
                        ),
                        title: Text(
                          _localizedModuleLabel(
                            context,
                            module.id,
                            module.id == 'salary'
                                ? (controller.appContext?.accountType == 'owner' ||
                                        controller.canManageStaffSalary()
                                    ? (AppLocalizations.of(context)?.staffSalaryKhata ?? 'Staff Salary')
                                    : (switch (AppLocalizations.of(context)?.localeName) {
                                        'bn' => 'আমার বেতন',
                                        'hi' => 'मेरा वेतन',
                                        _ => 'My Salary',
                                      }))
                                : module.id == 'attendance'
                                    ? (controller.appContext?.accountType == 'owner' ||
                                            controller.canManageStaffAttendance()
                                        ? (switch (AppLocalizations.of(context)?.localeName) {
                                            'bn' => 'স্টাফ উপস্থিতি',
                                            'hi' => 'कर्मचारी उपस्थिति',
                                            _ => 'Staff Attendance',
                                          })
                                        : (switch (AppLocalizations.of(context)?.localeName) {
                                            'bn' => 'আমার উপস্থিতি',
                                            'hi' => 'मेरी उपस्थिति',
                                            _ => 'My Attendance',
                                          }))
                                    : module.label,
                          ),
                          style: TextStyle(
                            color: active ? Colors.white : Colors.white70,
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                        trailing: module.id == 'attendance' &&
                                controller.pendingAttendanceCount > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEA580C),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      offset: Offset(0, 1.5),
                                      blurRadius: 0,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${controller.pendingAttendanceCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                        selected: active,
                        onTap: () => onSelect(module),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF183049), Color(0xFF102235)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  offset: Offset(0, 2.5),
                  blurRadius: 0,
                ),
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xFF0F172A),
                        offset: Offset(0, 2),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person_outline, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        controller.user?.name ?? 'Account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        controller.appContext?.accountType == 'owner'
                            ? 'Owner account'
                            : controller.role?.roleName ?? 'Employee account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2C1515), Color(0xFF1A0B0B)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xFF000000),
                        offset: Offset(0, 1.5),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: 'Log out',
                    onPressed: () => showLogoutConfirmationDialog(context, controller),
                    icon: const Icon(Icons.logout, color: Color(0xFFFCA5A5), size: 16),
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: InkWell(
              onTap: () => showAboutNubiBillDialog(context, controller),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF22364E), Color(0xFF152435)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFF0C36D).withValues(alpha: 0.5),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xFF08121B),
                      offset: Offset(0, 2),
                      blurRadius: 0,
                    ),
                    BoxShadow(
                      color: Color(0x33D97706),
                      blurRadius: 6,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: Color(0xFFFBBF24),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'NubiBill Business ERP v${EnvironmentConfig.appVersion}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                          shadows: [
                            Shadow(
                              color: Color(0x80F59E0B),
                              blurRadius: 6,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.showMenu,
    required this.businessLevelModule,
    required this.onOpenMenu,
    this.onOpenAttendance,
  });
  final AppController controller;
  final bool showMenu, businessLevelModule;
  final VoidCallback onOpenMenu;
  final VoidCallback? onOpenAttendance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 980;
    final showExtraIcons = screenWidth >= 1180;
    final businessId = controller.appContext?.businessId;
    final outletId = controller.appContext?.outletId;
    final businessPicker = _WorkspaceDropdown<String>(
      label: 'Business',
      value: businessId,
      items: controller.businesses
          .map(
            (business) => DropdownMenuItem(
              value: business.businessId,
              child: Text(
                business.businessName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null && id != businessId) {
          controller.selectBusiness(
            id,
            businessLevelContext: businessLevelModule,
          );
        }
      },
    );
    final outletPicker = _OutletContextControl(
      controller: controller,
      outletId: outletId,
    );

    return SafeArea(
      bottom: false,
      child: Material(
        color: Colors.white,
        child: Column(
          children: [
            SizedBox(
              height: 66,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (showMenu)
                      IconButton(
                        tooltip: 'Open navigation',
                        onPressed: onOpenMenu,
                        icon: const Icon(Icons.menu),
                      ),
                    if (compact)
                      Expanded(
                        child: Text(
                          _safeBusinessName(controller),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      )
                    else ...[
                      businessPicker,
                      const SizedBox(width: 8),
                      if (!businessLevelModule) outletPicker,
                      const Spacer(),
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: screenWidth < 1200 ? 180 : 240,
                          ),
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              enableInteractiveSelection: true,
                              decoration: const InputDecoration(
                                hintText: 'Search workspace',
                                prefixIcon: Icon(Icons.search, size: 19),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                              onSubmitted: (_) => _showNotice(
                                context,
                                'Workspace-wide search is not connected yet.',
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (controller.sync != null)
                      Tooltip(
                        message: () {
                          final err = controller.sync!.error;
                          if (err == null) return 'Synchronize local changes';
                          if (SyncEngine.isQuotaFailure(err)) {
                            return 'Firestore is rate limiting or has reached a quota. Sync will retry after the cooldown; check Firebase project quotas if it continues. Local billing and saved data remain available.';
                          }
                          return err;
                        }(),
                        child: compact
                            ? IconButton(
                                onPressed:
                                    controller.sync!.state == SyncState.syncing
                                    ? null
                                    : controller.sync!.retry,
                                icon: Icon(
                                  controller.sync!.state == SyncState.offline
                                      ? Icons.cloud_off
                                      : (controller.sync!.state ==
                                                    SyncState.error &&
                                                SyncEngine.isQuotaFailure(
                                                  controller.sync!.error,
                                                )
                                            ? Icons.cloud_queue_rounded
                                            : Icons.sync),
                                  size: 20,
                                ),
                              )
                            : TextButton.icon(
                                onPressed:
                                    controller.sync!.state == SyncState.syncing
                                    ? null
                                    : controller.sync!.retry,
                                icon: Icon(
                                  controller.sync!.state == SyncState.offline
                                      ? Icons.cloud_off
                                      : (controller.sync!.state ==
                                                    SyncState.error &&
                                                SyncEngine.isQuotaFailure(
                                                  controller.sync!.error,
                                                )
                                            ? Icons.cloud_queue_rounded
                                            : Icons.sync),
                                  size: 18,
                                ),
                                label: Text(switch (controller.sync!.state) {
                                  SyncState.synced =>
                                    l10n?.syncStatusSynced ?? 'Synced',
                                  SyncState.syncing =>
                                    l10n?.syncStatusSyncing ?? 'Syncing',
                                  SyncState.offline =>
                                    l10n?.syncStatusOffline ?? 'Offline',
                                  SyncState.pending =>
                                    '${l10n?.syncStatusPending ?? "Pending"} (${controller.sync!.pendingCount})',
                                  SyncState.error =>
                                    SyncEngine.isQuotaFailure(
                                          controller.sync!.error,
                                        )
                                        ? 'Cloud paused'
                                        : (l10n?.syncStatusError ??
                                              'Sync error'),
                                }),
                              ),
                      ),
                    if (controller.sync != null)
                      PopupMenuButton<String>(
                        tooltip: 'Synchronization options',
                        enabled: controller.sync!.state != SyncState.syncing,
                        onSelected: (_) async {
                          await controller.sync!.sync(refreshCatalogue: true);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'catalogue',
                            child: Text('Refresh SYSTEM catalogue'),
                          ),
                        ],
                      ),
                    if (showExtraIcons) ...[
                      IconButton(
                        tooltip: 'Notifications',
                        onPressed: () =>
                            _showNotice(context, 'You are all caught up.'),
                        icon: const Icon(Icons.notifications_none_rounded),
                      ),
                      IconButton(
                        tooltip: 'Help',
                        onPressed: () => _showNotice(
                          context,
                          'Contact your NubiBill administrator for help.',
                        ),
                        icon: const Icon(Icons.help_outline_rounded),
                      ),
                    ],
                    if (screenWidth >= 1280) ...[
                      _TopBarLanguageSelector(controller: controller),
                      const SizedBox(width: 4),
                    ],
                    PopupMenuButton<String>(
                      tooltip: 'Profile menu',
                      onSelected: (value) {
                        if (value == 'attendance') {
                          onOpenAttendance?.call();
                        }
                        if (value == 'business') {
                          controller.openBusinessSelector();
                        }
                        if (value == 'outlet' && !businessLevelModule) {
                          controller.openOutletSelector();
                        }
                        if (value == 'language') {
                          _showLanguagePickerDialog(context, controller);
                        }
                        if (value == 'about') {
                          showAboutNubiBillDialog(context, controller);
                        }
                        if (value == 'logout') {
                          showLogoutConfirmationDialog(context, controller);
                        }
                      },
                      itemBuilder: (ctx) {
                        final l10n = AppLocalizations.of(ctx);
                        return [
                          PopupMenuItem(
                            enabled: false,
                            child: Text(controller.user?.email ?? ''),
                          ),
                          if (!businessLevelModule &&
                              (controller.appContext?.accountType == 'owner' ||
                                  controller.businesses.length > 1))
                            PopupMenuItem(
                              value: 'business',
                              child: Text(
                                l10n?.switchBusiness ?? 'Switch business',
                              ),
                            ),
                          if (!businessLevelModule &&
                              (controller.appContext?.accountType == 'owner' ||
                                  controller.outlets.length > 1))
                            PopupMenuItem(
                              value: 'outlet',
                              child: Text(
                                l10n?.switchOutlet ?? 'Switch outlet',
                              ),
                            ),
                          if (controller.canViewStaffAttendance())
                            PopupMenuItem(
                              value: 'attendance',
                              child: Row(
                                children: [
                                  const Icon(Icons.fact_check_outlined, size: 18, color: Color(0xFF0D9488)),
                                  const SizedBox(width: 8),
                                  Text(
                                    controller.appContext?.accountType == 'owner' ||
                                            controller.canManageStaffAttendance()
                                        ? (switch (l10n?.localeName) {
                                            'bn' => 'স্টাফ উপস্থিতি',
                                            'hi' => 'कर्मचारी उपस्थिति',
                                            _ => 'Staff Attendance',
                                          })
                                        : (switch (l10n?.localeName) {
                                            'bn' => 'আমার উপস্থিতি',
                                            'hi' => 'मेरी उपस्थिति',
                                            _ => 'My Attendance',
                                          }),
                                  ),
                                ],
                              ),
                            ),
                          PopupMenuItem(
                            value: 'language',
                            child: Row(
                              children: [
                                const Icon(Icons.translate_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  l10n?.language ?? 'Language / भाषा / ভাষা',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'about',
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  l10n?.aboutAppTitle ?? 'About NubiBill ERP',
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'logout',
                            child: Text(l10n?.logout ?? 'Log out'),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'about',
                            child: Text(
                              'NubiBill Business ERP v${EnvironmentConfig.appVersion}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                        ];
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Text(_initial(controller.user?.name)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: businessPicker),
                        if (!businessLevelModule) ...[
                          const SizedBox(width: 10),
                          Expanded(child: outletPicker),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 40,
                      child: TextField(
                        enableInteractiveSelection: true,
                        decoration: const InputDecoration(
                          hintText: 'Search workspace',
                          prefixIcon: Icon(Icons.search, size: 19),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                        onSubmitted: (_) => _showNotice(
                          context,
                          'Workspace-wide search is not connected yet.',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _initial(String? name) =>
      name == null || name.isEmpty ? 'U' : name.characters.first.toUpperCase();
}

Future<void> _showLanguagePickerDialog(
  BuildContext context,
  AppController controller,
) {
  final currentCode = controller.currentLocale.languageCode;
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final l10n = AppLocalizations.of(dialogCtx);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10263D).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.translate_rounded,
                color: Color(0xFF10263D),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n?.language ?? 'Language / भाषा / ভাষা',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLanguageDialogTile(
              dialogCtx,
              controller,
              locale: const Locale('en'),
              nativeName: 'English',
              subLabel: 'Default / International',
              isSelected: currentCode == 'en',
            ),
            const Divider(height: 1, indent: 12, endIndent: 12),
            _buildLanguageDialogTile(
              dialogCtx,
              controller,
              locale: const Locale('hi'),
              nativeName: 'हिंदी',
              subLabel: 'Hindi • भारत की आधिकारिक भाषा',
              isSelected: currentCode == 'hi',
            ),
            const Divider(height: 1, indent: 12, endIndent: 12),
            _buildLanguageDialogTile(
              dialogCtx,
              controller,
              locale: const Locale('bn'),
              nativeName: 'বাংলা',
              subLabel: 'Bengali • পশ্চিমবঙ্গ ও আঞ্চলিক ভাষা',
              isSelected: currentCode == 'bn',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Widget _buildLanguageDialogTile(
  BuildContext context,
  AppController controller, {
  required Locale locale,
  required String nativeName,
  required String subLabel,
  required bool isSelected,
}) {
  return ListTile(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    selected: isSelected,
    selectedTileColor: const Color(0xFF10263D).withValues(alpha: 0.06),
    leading: Icon(
      isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
      color: isSelected ? const Color(0xFF10263D) : Colors.black38,
    ),
    title: Text(
      nativeName,
      style: TextStyle(
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? const Color(0xFF10263D) : Colors.black87,
        fontSize: 15,
      ),
    ),
    subtitle: Text(
      subLabel,
      style: const TextStyle(fontSize: 11, color: Colors.black54),
    ),
    onTap: () {
      controller.setLocale(locale);
      Navigator.of(context).pop();
    },
  );
}

class _TopBarLanguageSelector extends StatelessWidget {
  const _TopBarLanguageSelector({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final currentCode = controller.currentLocale.languageCode;
    final currentLabel = switch (currentCode) {
      'hi' => 'हिंदी',
      'bn' => 'বাংলা',
      _ => 'English',
    };

    return PopupMenuButton<Locale>(
      tooltip: 'Language / भाषा / ভাষা',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.translate_rounded,
                size: 15,
                color: Color(0xFF1E293B),
              ),
              const SizedBox(width: 5),
              Text(
                currentLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
      onSelected: (locale) => controller.setLocale(locale),
      itemBuilder: (_) => [
        _buildLanguagePopupItem(
          const Locale('en'),
          'English',
          'English',
          currentCode == 'en',
          isDark: false,
        ),
        _buildLanguagePopupItem(
          const Locale('hi'),
          'हिंदी',
          'Hindi',
          currentCode == 'hi',
          isDark: false,
        ),
        _buildLanguagePopupItem(
          const Locale('bn'),
          'বাংলা',
          'Bengali',
          currentCode == 'bn',
          isDark: false,
        ),
      ],
    );
  }
}

PopupMenuItem<Locale> _buildLanguagePopupItem(
  Locale locale,
  String nativeName,
  String englishName,
  bool isSelected, {
  required bool isDark,
}) {
  return PopupMenuItem<Locale>(
    value: locale,
    child: Row(
      children: [
        Icon(
          isSelected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked,
          size: 16,
          color: isSelected
              ? (isDark ? const Color(0xFFF0C36D) : const Color(0xFF2563EB))
              : (isDark ? Colors.white38 : Colors.black38),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nativeName,
              style: TextStyle(
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF2563EB))
                    : (isDark ? Colors.white70 : Colors.black87),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 13,
              ),
            ),
            Text(
              englishName,
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black45,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _WorkspaceDropdown<T> extends StatelessWidget {
  const _WorkspaceDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: MediaQuery.sizeOf(context).width < 980
        ? double.infinity
        : MediaQuery.sizeOf(context).width < 1200
        ? 150
        : 220,
    child: DropdownButtonFormField<T>(
      initialValue: items.any((item) => item.value == value) ? value : null,
      items: items,
      onChanged: items.length > 1 ? onChanged : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}

class _OutletContextControl extends StatelessWidget {
  const _OutletContextControl({
    required this.controller,
    required this.outletId,
  });

  final AppController controller;
  final String? outletId;

  @override
  Widget build(BuildContext context) {
    final canCreate = controller.canCreateOutlet();
    if (controller.outlets.isEmpty) {
      if (canCreate) {
        return OutlinedButton.icon(
          onPressed: controller.openCreateOutlet,
          icon: const Icon(Icons.add_business_outlined, size: 18),
          label: const Text('Add Outlet'),
        );
      }
      return const Align(
        alignment: Alignment.centerLeft,
        child: Text('No Outlet Available'),
      );
    }
    final picker = _WorkspaceDropdown<String>(
      label: 'Outlet',
      value: outletId,
      items: controller.outlets
          .map(
            (outlet) => DropdownMenuItem(
              value: outlet.outletId,
              child: Text(outlet.outletName, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (id) {
        if (id != null) controller.selectOutlet(id);
      },
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (MediaQuery.sizeOf(context).width < 980)
          Expanded(child: picker)
        else
          picker,
        if (canCreate)
          IconButton(
            tooltip: 'Add Outlet',
            onPressed: controller.openCreateOutlet,
            icon: const Icon(Icons.add_business_outlined),
          ),
      ],
    );
  }
}

class _ModuleBody extends StatelessWidget {
  const _ModuleBody({
    required this.controller,
    required this.module,
    required this.isOwner,
    required this.onOpenModule,
    this.attendanceInitialTab = 0,
    required this.initialBarcodeProductId,
    required this.initialBarcodeVariantId,
    required this.onOpenBarcode,
  });
  final AppController controller;
  final AdminModule module;
  final bool isOwner;
  final ValueChanged<String> onOpenModule;
  final int attendanceInitialTab;
  final String? initialBarcodeProductId;
  final String? initialBarcodeVariantId;
  final void Function(String productId, String variantId) onOpenBarcode;

  @override
  Widget build(BuildContext context) {
    if (module.id == 'dashboard') {
      return _DashboardOverview(
        controller: controller,
        isOwner: isOwner,
        onOpenModule: onOpenModule,
      );
    }
    if (module.id == 'staff') {
      return EmployeeManagementPage(controller: controller);
    }
    if (module.id == 'suppliers') {
      return SupplierManagementPage(controller: controller);
    }
    if (module.id == 'supplier_ledger') {
      return SupplierLedgerDashboardPage(controller: controller);
    }
    if (module.id == 'purchase') {
      return PurchaseManagementPage(controller: controller);
    }
    if (module.id == 'billing') {
      return BillingPage(
        controller: controller,
        onBillSaved: () => onOpenModule('sales'),
      );
    }
    if (module.id == 'sales') {
      return SalesManagementPage(
        controller: controller,
        onOpenModule: onOpenModule,
        initialShowHistory: false,
      );
    }
    if (module.id == 'customers') {
      return CustomerManagementPage(controller: controller);
    }
    if (module.id == 'products') {
      return ProductManagementPage(
        key: ValueKey(controller.appContext?.businessId),
        controller: controller,
        onOpenBarcodeModule: onOpenBarcode,
      );
    }
    if (module.id == 'barcode') {
      final businessName =
          controller.businesses
              .where(
                (business) =>
                    business.businessId == controller.appContext?.businessId,
              )
              .firstOrNull
              ?.businessName ??
          '';
      return BarcodeManagementPage(
        key: ValueKey('barcode-module-${controller.appContext?.businessId}'),
        products: controller.products,
        businessName: businessName,
        loadReceivedVariantIds: controller.loadBarcodeReceivedVariantIds,
        loadReceivedVariantPricing:
            controller.loadBarcodeReceivedVariantPricing,
        loadVariantBatches: controller.loadVariantBatches,
        availableQuantities: controller.productStock,
        initialProductId: initialBarcodeProductId,
        initialVariantId: initialBarcodeVariantId,
      );
    }
    if (module.id == 'inventory') {
      return InventoryDashboardPage(
        key: ValueKey(controller.appContext?.businessId),
        controller: controller,
        onOpenProducts: () => onOpenModule('products'),
      );
    }
    if (module.id == 'godowns') {
      return storage.StorageManagementPage(
        key: ValueKey(controller.appContext?.businessId),
        controller: controller,
      );
    }
    if (module.id == 'racks') {
      return storage.OutletRackManagementPage(
        key: ValueKey(controller.currentOutlet?.outletId),
        controller: controller,
      );
    }
    if (module.id == 'reports') {
      return ReportsPage(
        key: ValueKey(
          controller.currentOutlet?.outletId ??
              controller.appContext?.businessId,
        ),
        controller: controller,
      );
    }
    if (module.id == 'expenses') {
      return ExpenseManagementPage(
        key: ValueKey(controller.appContext?.businessId),
        controller: controller,
      );
    }
    if (module.id == 'attendance') {
      return StaffAttendancePage(
        key: ValueKey(
          '${controller.appContext?.businessId}-${controller.appContext?.outletId}-$attendanceInitialTab',
        ),
        controller: controller,
        initialTab: attendanceInitialTab,
      );
    }
    if (module.id == 'salary') {
      return StaffSalaryPage(
        key: ValueKey(
          '${controller.appContext?.businessId}-${controller.appContext?.employeeId}',
        ),
        controller: controller,
      );
    }
    if (module.id == 'settings') {
      return SettingsPage(
        key: ValueKey(controller.appContext?.businessId),
        controller: controller,
      );
    }
    return _ModulePlaceholder(module: module);
  }
}

class _DashboardOverview extends StatelessWidget {
  const _DashboardOverview({
    required this.controller,
    required this.isOwner,
    required this.onOpenModule,
  });
  final AppController controller;
  final bool isOwner;
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    if (controller.currentOutlet == null) {
      final hasOutlets = controller.outlets.isNotEmpty;
      final canCreateOutlet = controller.canCreateOutlet();
      return Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasOutlets
                      ? Icons.store_outlined
                      : Icons.store_mall_directory_outlined,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  hasOutlets ? 'Select an Outlet' : 'No Outlet Available',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  hasOutlets
                      ? 'Choose an Outlet to load its dashboard.'
                      : 'This Business has no active Outlets yet.',
                  textAlign: TextAlign.center,
                ),
                if (hasOutlets || canCreateOutlet) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: hasOutlets
                        ? controller.openOutletSelector
                        : controller.openCreateOutlet,
                    icon: Icon(
                      hasOutlets
                          ? Icons.store_outlined
                          : Icons.add_business_outlined,
                    ),
                    label: Text(hasOutlets ? 'Select Outlet' : 'Add Outlet'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final permissions = controller.appContext?.permissions ?? const <String>[];
    final canSales =
        isOwner ||
        PermissionCatalog.allows('sales', permissions) ||
        PermissionCatalog.allows('billing', permissions);
    final canPurchases =
        isOwner || PermissionCatalog.allows('purchase', permissions);
    final canProducts =
        isOwner ||
        PermissionCatalog.allows('products', permissions) ||
        PermissionCatalog.allows('inventory', permissions);
    final canCustomers =
        isOwner || PermissionCatalog.allows('customers', permissions);
    final summary = controller.dashboardSummary;
    final maxWidth = MediaQuery.sizeOf(context).width;
    final columns = maxWidth > 1180
        ? 4
        : maxWidth > 720
        ? 2
        : 1;
    final l10n = AppLocalizations.of(context);
    final metrics = <_MetricData>[
      if (canSales)
        _MetricData(
          l10n?.totalSales ?? 'Total sales',
          summary?.salesTotal,
          summary?.salesCount,
          Icons.trending_up_rounded,
          const Color(0xFF168A65),
          money: true,
          moduleId: isOwner || PermissionCatalog.allows('sales', permissions)
              ? 'sales'
              : 'billing',
          subBadges: [
            if ((summary?.borrowedAmount ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${l10n?.borrowed ?? 'Borrowed'}: ${_compactCurrency(summary!.borrowedAmount)}',
                color: const Color(0xFFE11D48),
                isAlert: true,
                icon: Icons.account_balance_wallet_outlined,
              ),
            if ((summary?.salesTotal ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${l10n?.collected ?? 'Collected'}: ${_compactCurrency(((summary!.salesTotal) - (summary.salesDueTotal)).clamp(0, double.infinity))}',
                color: const Color(0xFF16A34A),
              ),
          ],
        ),
      if (canPurchases)
        _MetricData(
          l10n?.totalPurchases ?? 'Total purchases',
          summary?.purchaseTotal,
          summary?.purchaseCount,
          Icons.shopping_bag_outlined,
          const Color(0xFF4D6CD3),
          money: true,
          moduleId: 'purchase',
          subBadges: [
            if ((summary?.purchaseDueTotal ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${l10n?.payable ?? 'Payable'}: ${_compactCurrency(summary!.purchaseDueTotal)}',
                color: const Color(0xFFD97706),
                isAlert: true,
              ),
            if ((summary?.purchaseTotal ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${l10n?.allSettled ?? 'Settled'}: ${_compactCurrency(((summary!.purchaseTotal) - (summary.purchaseDueTotal)).clamp(0, double.infinity))}',
                color: const Color(0xFF2563EB),
              ),
          ],
        ),
      if (canProducts)
        _MetricData(
          l10n?.products ?? 'Products',
          summary?.productCount.toDouble(),
          null,
          Icons.inventory_2_outlined,
          const Color(0xFFCA8B2B),
          moduleId: isOwner || PermissionCatalog.allows('products', permissions)
              ? 'products'
              : 'inventory',
          subBadges: [
            _MetricSubBadge(
              label:
                  '${summary?.activeProductCount ?? summary?.productCount ?? 0} ${l10n?.active ?? 'Active'}',
              color: const Color(0xFF16A34A),
            ),
            if ((summary?.inactiveProductCount ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${summary!.inactiveProductCount} ${l10n?.inactive ?? 'Inactive'}',
                color: const Color(0xFF64748B),
              ),
            if ((summary?.outOfStockCount ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${summary!.outOfStockCount} ${l10n?.outOfStock ?? 'Out of Stock'}',
                color: const Color(0xFFDC2626),
                isAlert: true,
              ),
            if ((summary?.lowStockCount ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${summary!.lowStockCount} ${l10n?.lowStock ?? 'Low Stock'}',
                color: const Color(0xFFD97706),
                isAlert: true,
              ),
          ],
        ),
      if (canCustomers)
        _MetricData(
          l10n?.customers ?? 'Customers',
          summary?.customerCount.toDouble(),
          null,
          Icons.people_outline,
          const Color(0xFF8B62BE),
          moduleId: 'customers',
          subBadges: [
            if ((summary?.customerDueTotal ?? 0) > 0)
              _MetricSubBadge(
                label:
                    '${summary!.customersWithDueCount} ${l10n?.withDues ?? 'with dues'} (${_compactCurrency(summary.customerDueTotal)})',
                color: const Color(0xFFE11D48),
                isAlert: true,
              )
            else
              _MetricSubBadge(
                label: l10n?.allSettled ?? 'All settled',
                color: const Color(0xFF16A34A),
              ),
          ],
        ),
      if (isOwner || controller.canViewStaffAttendance())
        _MetricData(
          isOwner || controller.canManageStaffAttendance()
              ? (switch (l10n?.localeName) {
                  'bn' => 'স্টাফ উপস্থিতি',
                  'hi' => 'कर्मचारी उपस्थिति',
                  _ => 'Staff Attendance',
                })
              : (switch (l10n?.localeName) {
                  'bn' => 'আমার উপস্থিতি',
                  'hi' => 'मेरी उपस्थिति',
                  _ => 'My Attendance',
                }),
          null,
          null,
          Icons.fact_check_outlined,
          const Color(0xFF0D9488),
          moduleId: 'attendance',
          subBadges: [
            if (controller.pendingAttendanceCount > 0 &&
                (isOwner || controller.canApproveStaffAttendance()))
              _MetricSubBadge(
                label:
                    '${controller.pendingAttendanceCount} Pending Review',
                color: const Color(0xFFEA580C),
                isAlert: true,
              )
            else
              _MetricSubBadge(
                label: isOwner || controller.canManageStaffAttendance()
                    ? 'Shift Register & Biometrics'
                    : 'Clock In / Out & History',
                color: const Color(0xFF0D9488),
              ),
          ],
        ),
    ];

    return ListView(
      padding: EdgeInsets.all(maxWidth < 600 ? 14 : 24),
      children: [
        _ExecutiveHeroBanner(
          controller: controller,
          onOpenModule: onOpenModule,
          canSales: canSales,
          canPurchases: canPurchases,
          canProducts: canProducts,
        ),
        const SizedBox(height: 18),
        if (isOwner || controller.canViewStaffAttendance()) ...[
          if (controller.pendingAttendanceCount > 0) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD97706).withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.pending_actions_rounded,
                      color: Color(0xFFB45309),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${controller.pendingAttendanceCount} Attendance Record(s) Pending Review',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF78350F),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Review and authorize employee shifts to accurately calculate payable work units for payroll.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB45309),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => onOpenModule('attendance:approval'),
                    icon: const Icon(Icons.verified_user_rounded, size: 18),
                    label: const Text('Review & Approve'),
                  ),
                ],
              ),
            ),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => onOpenModule('attendance'),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  controller.pendingAttendanceCount > 0
                      ? 'Attendance & Approvals ( Pending)'
                      : (isOwner || controller.canManageStaffAttendance()
                          ? 'Staff Attendance & Approvals'
                          : (switch (l10n?.localeName) {
                              'bn' => 'আমার উপস্থিতি বিবরণ',
                              'hi' => 'मेरी উपस्থিতি विवरण',
                              _ => 'My Attendance Details',
                            })),
                ),
              ),
              if (_canViewSalary(controller))
                OutlinedButton.icon(
                  onPressed: () => onOpenModule('salary'),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(
                    isOwner || controller.canManageStaffSalary()
                        ? (l10n?.staffSalaryKhata ?? 'Staff Salary Khata')
                        : (switch (l10n?.localeName) {
                            'bn' => '\u0986\u09ae\u09be\u09b0 \u09ac\u09c7\u09a4\u09a8 \u0993 \u09b8\u09cd\u09b2\u09bf\u09aa',
                            'hi' => '\u092e\u0947\u0930\u093e \u0935\u0947\u0924\u0928 \u0914\u0930 \u092a\u0930\u094d\u091a\u0940',
                            _ => 'My Salary & Slips',
                          }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
        ] else if (_canViewSalary(controller)) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => onOpenModule('salary'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(
                isOwner || controller.canManageStaffSalary()
                    ? (l10n?.staffSalaryKhata ?? 'Staff Salary Khata')
                    : (switch (l10n?.localeName) {
                        'bn' => '\u0986\u09ae\u09be\u09b0 \u09ac\u09c7\u09a4\u09a8 \u0993 \u09b8\u09cd\u09b2\u09bf\u09aa',
                        'hi' => '\u092e\u0947\u0930\u093e \u0935\u0947\u0924\u0928 \u0914\u0930 \u092a\u0930\u094d\u091a\u0940',
                        _ => 'My Salary & Slips',
                      }),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (controller.dashboardError != null) ...[
          _DashboardError(
            message: controller.dashboardError!,
            onRetry: controller.refreshDashboard,
          ),
          const SizedBox(height: 18),
        ],
        if (metrics.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              mainAxisExtent: maxWidth > 1180
                  ? 228
                  : maxWidth > 720
                  ? 210
                  : 200,
            ),
            itemBuilder: (context, index) => _MetricCard(
              metric: metrics[index],
              loading: controller.dashboardLoading,
              onTap: () => onOpenModule(metrics[index].moduleId),
            ),
          ),
        if (metrics.isEmpty &&
            !controller.dashboardLoading &&
            controller.dashboardError == null)
          const _EmptyPermissionCard(),
        if (canSales &&
            canPurchases &&
            ((summary?.salesTotal ?? 0) > 0 ||
                (summary?.purchaseTotal ?? 0) > 0)) ...[
          const SizedBox(height: 16),
          _CashflowVelocityBar(summary: summary),
        ],
        if (canProducts) ...[
          const SizedBox(height: 16),
          _InventoryHealthCard(
            summary: summary,
            loading: controller.dashboardLoading,
            onOpenModule: onOpenModule,
          ),
        ],
        const SizedBox(height: 16),
        if (canSales)
          LayoutBuilder(
            builder: (context, constraints) {
              final chart = _SalesChartCard(
                summary: summary,
                loading: controller.dashboardLoading,
              );
              final products = _TopProductsCard(
                summary: summary,
                loading: controller.dashboardLoading,
              );
              if (constraints.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: chart),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: products),
                  ],
                );
              }
              return Column(
                children: [chart, const SizedBox(height: 16), products],
              );
            },
          ),
        if (canSales) ...[
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final recentSales = _RecentSalesCard(
                summary: summary,
                loading: controller.dashboardLoading,
                onOpenModule: onOpenModule,
              );
              final quickActions = _ExecutiveQuickActions(
                onOpenModule: onOpenModule,
                canSales: canSales,
                canPurchases: canPurchases,
                canProducts: canProducts,
              );
              if (constraints.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: recentSales),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: quickActions),
                  ],
                );
              }
              return Column(
                children: [
                  recentSales,
                  const SizedBox(height: 16),
                  quickActions,
                ],
              );
            },
          ),
        ],
        if (!isOwner && permissions.isEmpty) const _EmptyPermissionCard(),
      ],
    );
  }
}

class _ExecutiveHeroBanner extends StatelessWidget {
  const _ExecutiveHeroBanner({
    required this.controller,
    required this.onOpenModule,
    required this.canSales,
    required this.canPurchases,
    required this.canProducts,
  });

  final AppController controller;
  final ValueChanged<String> onOpenModule;
  final bool canSales;
  final bool canPurchases;
  final bool canProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentOutlet = controller.currentOutlet;
    final user = controller.user;
    final l10n = AppLocalizations.of(context);
    final isOwner = controller.appContext?.accountType == 'owner';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 14,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Dashboard',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF0EA5E9)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          'LIVE ERP',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF38BDF8),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Welcome back, ${user?.name ?? 'there'}. Here is your workspace overview.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (currentOutlet != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF10B981),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              currentOutlet.outletName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: controller.dashboardLoading
                        ? null
                        : controller.refreshDashboard,
                    icon: controller.dashboardLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: const Text(
                      'Refresh',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (canSales)
                  _HeroQuickDockPill(
                    icon: Icons.point_of_sale_rounded,
                    label: 'POS Billing',
                    color: const Color(0xFF10B981),
                    onTap: () => onOpenModule('billing'),
                  ),
                if (canSales) const SizedBox(width: 8),
                if (canProducts)
                  _HeroQuickDockPill(
                    icon: Icons.inventory_2_rounded,
                    label: 'Products',
                    color: const Color(0xFFF59E0B),
                    onTap: () => onOpenModule('products'),
                  ),
                if (canProducts) const SizedBox(width: 8),
                if (canPurchases)
                  _HeroQuickDockPill(
                    icon: Icons.local_shipping_rounded,
                    label: 'Vendor Bills',
                    color: const Color(0xFF6366F1),
                    onTap: () => onOpenModule('purchase'),
                  ),
                if (canPurchases) const SizedBox(width: 8),
                if (canPurchases)
                  _HeroQuickDockPill(
                    icon: Icons.menu_book_rounded,
                    label: switch (l10n?.localeName) {
                      'bn' => 'সাপ্লায়ার লেজার',
                      'hi' => 'सप्लायर लेजर',
                      _ => 'Supplier Ledger',
                    },
                    color: const Color(0xFF4338CA),
                    onTap: () => onOpenModule('supplier_ledger'),
                  ),
                if (canPurchases) const SizedBox(width: 8),
                _HeroQuickDockPill(
                  icon: Icons.qr_code_2_rounded,
                  label: 'Print Barcode',
                  color: const Color(0xFFA855F7),
                  onTap: () => onOpenModule('barcode'),
                ),
                if (controller.canViewStaffAttendance()) ...[
                  const SizedBox(width: 8),
                  _HeroQuickDockPill(
                    icon: Icons.fact_check_rounded,
                    label: isOwner || controller.canManageStaffAttendance()
                        ? (switch (l10n?.localeName) {
                            'bn' => 'উপস্থিতি',
                            'hi' => 'उपस्थिति',
                            _ => 'Attendance',
                          })
                        : (switch (l10n?.localeName) {
                            'bn' => 'আমার উপস্থিতি',
                            'hi' => 'मेरी उपस्थिति',
                            _ => 'My Attendance',
                          }),
                    color: const Color(0xFF10B981),
                    onTap: () => onOpenModule('attendance'),
                  ),
                ],
                if (_canViewSalary(controller)) ...[
                  const SizedBox(width: 8),
                  _HeroQuickDockPill(
                    icon: Icons.account_balance_wallet_rounded,
                    label: isOwner || controller.canManageStaffSalary()
                        ? (l10n?.staffSalaryKhata ?? 'Staff Salary')
                        : (switch (l10n?.localeName) {
                            'bn' => '\u0986\u09ae\u09be\u09b0 \u09ac\u09c7\u09a4\u09a8',
                            'hi' => '\u092e\u0947\u0930\u093e \u0935\u0947\u0924\u0928',
                            _ => 'My Salary',
                          }),
                    color: const Color(0xFF0EA5E9),
                    onTap: () => onOpenModule('salary'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroQuickDockPill extends StatelessWidget {
  const _HeroQuickDockPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricData {
  const _MetricData(
    this.label,
    this.value,
    this.count,
    this.icon,
    this.color, {
    required this.moduleId,
    this.money = false,
    this.subBadges = const [],
  });
  final String label;
  final String moduleId;
  final num? value, count;
  final IconData icon;
  final Color color;
  final bool money;
  final List<_MetricSubBadge> subBadges;
}

class _MetricSubBadge {
  const _MetricSubBadge({
    required this.label,
    required this.color,
    this.isAlert = false,
    this.icon,
  });
  final String label;
  final Color color;
  final bool isAlert;
  final IconData? icon;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.loading,
    required this.onTap,
  });
  final _MetricData metric;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // Top Accent Line
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 4,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      metric.color,
                      metric.color.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              metric.color.withValues(alpha: 0.20),
                              metric.color.withValues(alpha: 0.08),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: metric.color.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(metric.icon, size: 19, color: metric.color),
                      ),
                      const Spacer(),
                      if (metric.count != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: metric.color.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: metric.color.withValues(alpha: 0.20),
                            ),
                          ),
                          child: Text(
                            '${metric.count!.toInt()} records',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: metric.color,
                            ),
                          ),
                        )
                      else
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 13,
                          color: Colors.black26,
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    metric.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (loading)
                    const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      metric.value == null
                          ? '—'
                          : metric.money
                          ? _currency(metric.value!)
                          : metric.value!.toInt().toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  if (!loading && metric.subBadges.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ClipRect(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final badge in metric.subBadges)
                            Container(
                              constraints: const BoxConstraints(maxWidth: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: badge.color.withValues(
                                  alpha: badge.isAlert ? 0.12 : 0.08,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: badge.color.withValues(
                                    alpha: badge.isAlert ? 0.35 : 0.20,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (badge.icon != null) ...[
                                    Icon(
                                      badge.icon,
                                      size: 10,
                                      color: badge.color,
                                    ),
                                    const SizedBox(width: 3),
                                  ],
                                  Flexible(
                                    child: Text(
                                      badge.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: badge.isAlert
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: badge.color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashflowVelocityBar extends StatelessWidget {
  const _CashflowVelocityBar({required this.summary});
  final DashboardSummary? summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sales = summary?.salesTotal ?? 0.0;
    final purchases = summary?.purchaseTotal ?? 0.0;
    final borrowed = summary?.borrowedAmount ?? 0.0;
    final purchaseDue = summary?.purchaseDueTotal ?? 0.0;
    final realizedSales = (sales - borrowed).clamp(0.0, double.infinity);
    final netFlow = sales - purchases;
    final isSurplus = netFlow >= 0;
    final totalVol = sales + purchases;
    final salesRatio = totalVol > 0
        ? (sales / totalVol).clamp(0.08, 0.92)
        : 0.5;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final isHeaderCompact = headerConstraints.maxWidth < 460;
              final titleWidget = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 18,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      l10n?.liquidityVelocityTitle ??
                          'Commercial Liquidity & Cashflow Velocity',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );

              final netBadge = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isSurplus
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSurplus
                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                        : const Color(0xFFEF4444).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSurplus
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 13,
                      color: isSurplus
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${isSurplus ? '+' : ''}${_currency(netFlow)} ${l10n?.net ?? 'Net'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSurplus
                            ? const Color(0xFF065F46)
                            : const Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
              );

              if (isHeaderCompact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [titleWidget, const SizedBox(height: 8), netBadge],
                );
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: titleWidget),
                  const SizedBox(width: 8),
                  netBadge,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (salesRatio * 100).toInt(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: ((1.0 - salesRatio) * 100).toInt(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, legendConstraints) {
              final maxLegendWidth = legendConstraints.maxWidth;
              Widget buildLegendItem({
                required Color color,
                required String label,
                bool isAlert = false,
              }) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLegendWidth),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isAlert
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isAlert ? color : const Color(0xFF334155),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 6,
                children: [
                  buildLegendItem(
                    color: const Color(0xFF10B981),
                    label:
                        '${l10n?.realizedCash ?? 'Realized Cash'}: ${_currency(realizedSales)}',
                  ),
                  if (borrowed > 0)
                    buildLegendItem(
                      color: const Color(0xFFE11D48),
                      label:
                          '${l10n?.borrowedUdhaar ?? 'Borrowed (Udhaar)'}: ${_currency(borrowed)}',
                      isAlert: true,
                    ),
                  if (purchaseDue > 0)
                    buildLegendItem(
                      color: const Color(0xFFD97706),
                      label:
                          '${l10n?.vendorPayables ?? 'Vendor Payables'}: ${_currency(purchaseDue)}',
                      isAlert: true,
                    ),
                  buildLegendItem(
                    color: const Color(0xFF6366F1),
                    label:
                        '${l10n?.purchases ?? 'Purchases'}: ${_currency(purchases)}',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InventoryHealthCard extends StatelessWidget {
  const _InventoryHealthCard({
    required this.summary,
    required this.loading,
    required this.onOpenModule,
  });

  final DashboardSummary? summary;
  final bool loading;
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final total = summary?.productCount ?? 0;
    final active = summary?.activeProductCount ?? total;
    final inactive = summary?.inactiveProductCount ?? 0;
    final outOfStock = summary?.outOfStockCount ?? 0;
    final lowStock = summary?.lowStockCount ?? 0;
    final lowStockItems = summary?.lowStockProducts ?? const [];

    final hasCriticalIssues = outOfStock > 0 || lowStock > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFF59E0B).withValues(alpha: 0.25),
                            const Color(0xFFD97706).withValues(alpha: 0.10),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        size: 20,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                l10n?.inventoryHealthTitle ??
                                    'Inventory Health & Stock Intelligence',
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: hasCriticalIssues
                                      ? const Color(0xFFFEE2E2)
                                      : const Color(0xFFD1FAE5),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: hasCriticalIssues
                                        ? const Color(0xFFEF4444)
                                              .withValues(alpha: 0.4)
                                        : const Color(0xFF10B981)
                                              .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  hasCriticalIssues
                                      ? '$outOfStock ${l10n?.outOfStock ?? 'zero-stock'} • $lowStock ${l10n?.lowStock ?? 'low'}'
                                      : (l10n?.optimalHealth ??
                                            'Optimal Health'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: hasCriticalIssues
                                        ? const Color(0xFFB91C1C)
                                        : const Color(0xFF047857),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n?.inventorySubtitle ?? 'Real-time store catalog distribution and replenishment alerts',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => onOpenModule('products'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                label: Text(l10n?.manageCatalog ?? 'Manage Catalog'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4 Status Pillars in responsive Grid / Wrap
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;
              final tileWidth = isWide
                  ? (constraints.maxWidth - 36) / 4
                  : (constraints.maxWidth - 12) / 2;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _InventoryPillarTile(
                    width: tileWidth,
                    label: l10n?.activeInStore ?? 'Active in Store',
                    count: active,
                    color: const Color(0xFF16A34A),
                    icon: Icons.check_circle_outline_rounded,
                    subtext: l10n?.catalogActiveItems ?? 'Catalog active items',
                  ),
                  _InventoryPillarTile(
                    width: tileWidth,
                    label: l10n?.inactiveHidden ?? 'Inactive / Hidden',
                    count: inactive,
                    color: const Color(0xFF64748B),
                    icon: Icons.pause_circle_outline_rounded,
                    subtext: l10n?.draftOrArchived ?? 'Draft or archived',
                  ),
                  _InventoryPillarTile(
                    width: tileWidth,
                    label: l10n?.outOfStock ?? 'Out of Stock',
                    count: outOfStock,
                    color: const Color(0xFFDC2626),
                    icon: Icons.cancel_outlined,
                    subtext: l10n?.zeroUnitsRemaining ?? '0 units remaining',
                    isAlert: outOfStock > 0,
                  ),
                  _InventoryPillarTile(
                    width: tileWidth,
                    label: l10n?.lowStockAlerts ?? 'Low Stock Alerts',
                    count: lowStock,
                    color: const Color(0xFFD97706),
                    icon: Icons.warning_amber_rounded,
                    subtext: l10n?.belowReorderLevel ?? 'Below reorder level',
                    isAlert: lowStock > 0,
                  ),
                ],
              );
            },
          ),

          // Low Stock / Out of Stock Actionable Ledger
          if (lowStockItems.isNotEmpty) ...[
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, actionConstraints) {
                final isNarrow = actionConstraints.maxWidth < 560;
                final headerText = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.notification_important_rounded,
                      size: 16,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${l10n?.actionNeededReorder ?? 'Action Needed: Reorder List'} (${lowStockItems.length} ${l10n?.records ?? 'items'})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                );

                final actionBtn = TextButton.icon(
                  onPressed: () => onOpenModule('purchase'),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 14),
                  label: Text(
                    l10n?.inwardNewPurchase ?? 'Inward / New Purchase',
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: isNarrow ? EdgeInsets.zero : null,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headerText,
                      const SizedBox(height: 2),
                      actionBtn,
                    ],
                  );
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: headerText),
                    const SizedBox(width: 8),
                    actionBtn,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: lowStockItems.length.clamp(0, 6),
                  separatorBuilder: (context, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFEDF2F7),
                  ),
                  itemBuilder: (context, index) {
                    final item = lowStockItems[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: LayoutBuilder(
                        builder: (context, rowConstraints) {
                          final isItemCompact = rowConstraints.maxWidth < 460;
                          final statusBadge = Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: item.isOutOfStock
                                  ? const Color(0xFFFEE2E2)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              item.isOutOfStock ? 'OUT OF STOCK' : 'LOW STOCK',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: item.isOutOfStock
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFFB45309),
                                letterSpacing: 0.3,
                              ),
                            ),
                          );

                          final stockInfo = Column(
                            crossAxisAlignment: isItemCompact
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${item.currentStock} ${item.unit.isNotEmpty ? item.unit : 'units'}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: item.isOutOfStock
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFD97706),
                                ),
                              ),
                              Text(
                                'Reorder: ${item.reorderLevel}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          );

                          final inwardBtn = FilledButton.tonal(
                            onPressed: () => onOpenModule('purchase'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              l10n?.inward ?? 'Inward',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                          );

                          if (isItemCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    statusBadge,
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E293B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.sku.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'SKU: ${item.sku}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [stockInfo, inwardBtn],
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              statusBadge,
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (item.sku.isNotEmpty)
                                      Text(
                                        'SKU: ${item.sku}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF64748B),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              stockInfo,
                              const SizedBox(width: 12),
                              inwardBtn,
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    size: 16,
                    color: Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.allStockSufficient ?? 'All inventory products are sufficiently stocked above reorder thresholds.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InventoryPillarTile extends StatelessWidget {
  const _InventoryPillarTile({
    required this.width,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.subtext,
    this.isAlert = false,
  });

  final double width;
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final String subtext;
  final bool isAlert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAlert
            ? color.withValues(alpha: 0.05)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAlert
              ? color.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isAlert ? color : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SalesChartCard extends StatelessWidget {
  const _SalesChartCard({required this.summary, required this.loading});
  final DashboardSummary? summary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final values = summary?.weeklySales ?? const <SalesDaySummary>[];
    final totalWeekly = values.fold<double>(
      0.0,
      (acc, day) => acc + day.amount,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales overview',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Daily sales for the last 7 days',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                if (totalWeekly > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_graph_rounded,
                          size: 14,
                          color: Color(0xFF0284C7),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '7-Day: ${_compactCurrency(totalWeekly)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 172,
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : values.isEmpty || values.every((day) => day.amount == 0)
                  ? const _InlineEmpty(
                      message: 'No sales recorded for this period.',
                    )
                  : CustomPaint(
                      painter: _FancySalesChartPainter(
                        values.map((day) => day.amount).toList(),
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).dividerColor,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
            if (values.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final day in values)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: day.date.day == DateTime.now().day
                            ? Theme.of(context).colorScheme.primary
                                  .withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _weekday(day.date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: day.date.day == DateTime.now().day
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: day.date.day == DateTime.now().day
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FancySalesChartPainter extends CustomPainter {
  _FancySalesChartPainter(this.values, this.primaryColor, this.gridColor);
  final List<double> values;
  final Color primaryColor, gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    const right = 8.0;
    const top = 16.0;
    const bottom = 8.0;
    final width = size.width - left - right;
    final height = size.height - top - bottom;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;

    for (var row = 0; row < 4; row++) {
      final y = top + height * row / 3;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
    }

    final maxValue = values.fold<double>(0, math.max);
    if (maxValue <= 0) return;
    final count = values.length;
    final slot = width / count;
    final barWidth = math.min(32.0, slot * 0.48);

    final trackPaint = Paint()..color = primaryColor.withValues(alpha: 0.05);

    for (var i = 0; i < count; i++) {
      final barHeight = height * (values[i] / maxValue);
      final x = left + slot * i + (slot - barWidth) / 2;
      final y = top + height - barHeight;

      // Draw background slot track
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barWidth, height),
          const Radius.circular(6),
        ),
        trackPaint,
      );

      if (values[i] > 0) {
        final isPeak = values[i] == maxValue;
        final barRect = Rect.fromLTWH(x, y, barWidth, barHeight);

        final barPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isPeak
                ? [const Color(0xFF06B6D4), const Color(0xFF0284C7)]
                : [primaryColor, primaryColor.withValues(alpha: 0.70)],
          ).createShader(barRect);

        canvas.drawRRect(
          RRect.fromRectAndRadius(barRect, const Radius.circular(6)),
          barPaint,
        );

        if (isPeak) {
          // Glow dot at peak
          final dotPaint = Paint()..color = const Color(0xFF38BDF8);
          canvas.drawCircle(Offset(x + barWidth / 2, y + 4), 2.5, dotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FancySalesChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.gridColor != gridColor;
}

class _TopProductsCard extends StatefulWidget {
  const _TopProductsCard({required this.summary, required this.loading});
  final DashboardSummary? summary;
  final bool loading;

  @override
  State<_TopProductsCard> createState() => _TopProductsCardState();
}

class _TopProductsCardState extends State<_TopProductsCard> {
  bool _sortByRevenue = true;
  bool _showLeastSelling = false;
  int _itemCount = 10;

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final theme = Theme.of(context);

    List<TopProductSummary> sourceList;
    if (_showLeastSelling) {
      sourceList = summary?.bottomProducts ?? const [];
      if (_sortByRevenue) {
        sourceList = List.of(sourceList)
          ..sort((a, b) => a.revenue.compareTo(b.revenue));
      } else {
        sourceList = List.of(sourceList)
          ..sort((a, b) => a.quantity.compareTo(b.quantity));
      }
    } else {
      if (_sortByRevenue) {
        sourceList = summary?.topProductsByRevenue.isNotEmpty == true
            ? summary!.topProductsByRevenue
            : (summary?.topProducts ?? const []);
      } else {
        sourceList = summary?.topProducts ?? const [];
      }
    }

    final displayedProducts = sourceList.take(_itemCount).toList();

    final double maxVal = displayedProducts.fold<double>(
      0.0,
      (max, p) => math.max(max, _sortByRevenue ? p.revenue : p.quantity),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _showLeastSelling
                            ? 'Least selling products'
                            : 'Top selling products',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _showLeastSelling
                              ? const Color(0xFFB45309)
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _showLeastSelling
                            ? 'Slow-moving items & dead stock'
                            : 'Ranked by ${_sortByRevenue ? 'income / revenue' : 'quantity sold'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment<int>(value: 5, label: Text('5')),
                    ButtonSegment<int>(value: 10, label: Text('10')),
                  ],
                  selected: {_itemCount},
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) {
                    setState(() => _itemCount = selection.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('🏆 Top Selling'),
                    selected: !_showLeastSelling,
                    onSelected: (selected) {
                      if (selected) setState(() => _showLeastSelling = false);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('📉 Least Selling'),
                    selected: _showLeastSelling,
                    selectedColor: const Color(0xFFFEF3C7),
                    labelStyle: TextStyle(
                      color: _showLeastSelling ? const Color(0xFF92400E) : null,
                      fontWeight: _showLeastSelling ? FontWeight.w600 : null,
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _showLeastSelling = true);
                    },
                  ),
                  const SizedBox(width: 14),
                  Container(height: 18, width: 1, color: Colors.grey.shade300),
                  const SizedBox(width: 14),
                  ChoiceChip(
                    label: const Text('₹ By Revenue'),
                    selected: _sortByRevenue,
                    onSelected: (selected) {
                      if (selected) setState(() => _sortByRevenue = true);
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('📦 By Quantity'),
                    selected: !_sortByRevenue,
                    onSelected: (selected) {
                      if (selected) setState(() => _sortByRevenue = false);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (displayedProducts.isEmpty)
              const _InlineEmpty(message: 'Product sales will appear here.')
            else
              Column(
                children: [
                  for (var index = 0; index < displayedProducts.length; index++)
                    _buildProductBarRow(
                      context: context,
                      index: index,
                      product: displayedProducts[index],
                      maxVal: maxVal > 0 ? maxVal : 1.0,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductBarRow({
    required BuildContext context,
    required int index,
    required TopProductSummary product,
    required double maxVal,
  }) {
    final rank = index + 1;
    final currentVal = _sortByRevenue ? product.revenue : product.quantity;
    final progress = (currentVal / maxVal).clamp(0.02, 1.0);

    Color rankBg;
    Color rankText;
    String rankBadgeText = '$rank';
    if (_showLeastSelling) {
      rankBg = const Color(0xFFFEE2E2);
      rankText = const Color(0xFF991B1B);
    } else if (rank == 1) {
      rankBg = const Color(0xFFFEF3C7);
      rankText = const Color(0xFFB45309);
      rankBadgeText = '🥇';
    } else if (rank == 2) {
      rankBg = const Color(0xFFE2E8F0);
      rankText = const Color(0xFF475569);
      rankBadgeText = '🥈';
    } else if (rank == 3) {
      rankBg = const Color(0xFFFFEDD5);
      rankText = const Color(0xFFC2410C);
      rankBadgeText = '🥉';
    } else {
      rankBg = const Color(0xFFF1F5F9);
      rankText = const Color(0xFF64748B);
    }

    Color barStart;
    Color barEnd;
    if (_showLeastSelling) {
      barStart = const Color(0xFFF87171);
      barEnd = const Color(0xFFEF4444);
    } else if (_sortByRevenue) {
      barStart = const Color(0xFF0D9488);
      barEnd = const Color(0xFF10B981);
    } else {
      barStart = const Color(0xFF3B82F6);
      barEnd = const Color(0xFF6366F1);
    }

    final qtyLabel = product.unit.isNotEmpty
        ? '${product.quantity.toStringAsFixed(product.quantity % 1 == 0 ? 0 : 2)} ${product.unit}'
        : '${product.quantity.toStringAsFixed(product.quantity % 1 == 0 ? 0 : 2)} sold';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rankBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: rankText.withValues(alpha: 0.20)),
                ),
                child: Text(
                  rankBadgeText,
                  style: TextStyle(
                    fontSize: rank <= 3 && !_showLeastSelling ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    color: rankText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    if (product.sku.isNotEmpty && product.sku != '—') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          product.sku,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _sortByRevenue ? _currency(product.revenue) : qtyLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _showLeastSelling
                          ? const Color(0xFFB45309)
                          : (_sortByRevenue
                                ? const Color(0xFF0F766E)
                                : const Color(0xFF1D4ED8)),
                    ),
                  ),
                  Text(
                    _sortByRevenue ? qtyLabel : _currency(product.revenue),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                height: 7,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 7,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [barStart, barEnd]),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentSalesCard extends StatelessWidget {
  const _RecentSalesCard({
    required this.summary,
    required this.loading,
    required this.onOpenModule,
  });
  final DashboardSummary? summary;
  final bool loading;
  final ValueChanged<String> onOpenModule;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recent sales',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Latest billed invoices & live status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => onOpenModule('sales'),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (summary?.recentSales.isNotEmpty != true)
              const _InlineEmpty(
                message: 'Invoices for this outlet will show here.',
              )
            else
              for (final sale in summary!.recentSales) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E)
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF0F766E)
                                .withValues(alpha: 0.20),
                          ),
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          size: 19,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    sale.invoiceNumber,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _buildStatusPill(sale.paymentStatus),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _dateLabel(sale.createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _currency(sale.amount),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                if (sale != summary!.recentSales.last)
                  Divider(
                    height: 1,
                    color: Theme.of(context).dividerColor
                        .withValues(alpha: 0.20),
                  ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    final s = status.trim().toLowerCase();
    Color bg;
    Color text;
    if (s.contains('paid')) {
      bg = const Color(0xFFD1FAE5);
      text = const Color(0xFF065F46);
    } else if (s.contains('pending') || s.contains('partial')) {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFF92400E);
    } else {
      bg = const Color(0xFFF1F5F9);
      text = const Color(0xFF475569);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ExecutiveQuickActions extends StatelessWidget {
  const _ExecutiveQuickActions({
    required this.onOpenModule,
    required this.canSales,
    required this.canPurchases,
    required this.canProducts,
  });

  final ValueChanged<String> onOpenModule;
  final bool canSales;
  final bool canPurchases;
  final bool canProducts;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1.5,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ERP Operations',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Frequently used operational workflows',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            _ActionTile(
              icon: Icons.point_of_sale_rounded,
              color: const Color(0xFF10B981),
              title: 'POS Counter',
              subtitle: 'Express retail billing & cash desk',
              onTap: () => onOpenModule(canSales ? 'billing' : 'sales'),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.inventory_2_rounded,
              color: const Color(0xFFCA8B2B),
              title: 'Stock Master',
              subtitle: 'Manage products, barcodes & prices',
              onTap: () => onOpenModule('products'),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.local_shipping_rounded,
              color: const Color(0xFF4D6CD3),
              title: 'Vendor Inward',
              subtitle: 'Receive purchase bills & stock batches',
              onTap: () => onOpenModule('purchase'),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.menu_book_rounded,
              color: const Color(0xFF4338CA),
              title: 'Supplier Ledger',
              subtitle: 'Statement, balance tracking & due settlement',
              onTap: () => onOpenModule('supplier_ledger'),
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.qr_code_2_rounded,
              color: const Color(0xFF8B62BE),
              title: 'Barcode Studio',
              subtitle: 'Design & print custom sticker labels',
              onTap: () => onOpenModule('barcode'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
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
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 90,
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Colors.black54),
      ),
    ),
  );
}

class _EmptyPermissionCard extends StatelessWidget {
  const _EmptyPermissionCard();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'No dashboard summaries are available for the assigned permissions. Use the allowed modules from the navigation menu.',
      ),
    ),
  );
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({required this.module});
  final AdminModule module;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  module.icon,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  module.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'This module is not connected yet. Your current business and outlet context is ready for it.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _NoPermissions extends StatelessWidget {
  const _NoPermissions();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'No active permissions are assigned to this account. Contact your owner to review your access.',
      ),
    ),
  );
}

String _currency(num amount) {
  final isNegative = amount < 0;
  final absVal = amount.abs();
  final parts = absVal.toStringAsFixed(2).split('.');
  final whole = parts[0];
  final dec = parts[1];
  final reg = RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))');
  final formatted = whole.replaceAllMapped(reg, (m) => '${m[1]},');
  return '${isNegative ? '-' : ''}₹$formatted.$dec';
}

String _compactCurrency(num amount) {
  final isNeg = amount < 0;
  final a = amount.abs();
  String res;
  if (a >= 10000000) {
    res = '${(a / 10000000).toStringAsFixed(1)}Cr';
  } else if (a >= 100000) {
    res = '${(a / 100000).toStringAsFixed(1)}L';
  } else if (a >= 1000) {
    res = '${(a / 1000).toStringAsFixed(1)}k';
  } else {
    res = a.toInt().toString();
  }
  return '${isNeg ? '-' : ''}₹$res';
}

String _weekday(DateTime date) =>
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][date.weekday - 1];

String _dateLabel(DateTime? date) {
  if (date == null) return 'Date unavailable';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

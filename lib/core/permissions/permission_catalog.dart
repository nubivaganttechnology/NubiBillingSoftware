import 'package:flutter/material.dart';

import 'permission_id_matcher.dart';

class AdminModule {
  const AdminModule(this.id, this.label, this.icon, this.permission);
  final String id, label, permission;
  final IconData icon;
}

class PermissionCatalog {
  PermissionCatalog._();

  static const staffSalaryPermissions = <String>[
    'SALARY_VIEW',
    'SALARY_MANAGE',
    'SALARY_APPROVE',
    'SALARY_PAY',
    'SALARY_REPORT',
  ];

  static const staffAttendancePermissions = <String>[
    'ATTENDANCE_VIEW',
    'ATTENDANCE_MANAGE',
    'ATTENDANCE_APPROVE',
  ];

  static const biometricAttendancePermissions = <String>[
    'BIOMETRIC_ENROLL',
    'BIOMETRIC_REVOKE',
  ];

  static const staffKhataPermissions = <String>['STAFF_KHATA_CHARGE'];

  static const modules = <AdminModule>[
    AdminModule(
      'dashboard',
      'Dashboard',
      Icons.dashboard_outlined,
      'dashboard',
    ),
    AdminModule(
      'billing',
      'Billing (POS)',
      Icons.point_of_sale_outlined,
      'billing',
    ),
    AdminModule('sales', 'Sales', Icons.receipt_long_outlined, 'sales'),
    AdminModule(
      'purchase',
      'Purchase',
      Icons.shopping_cart_outlined,
      'purchase',
    ),
    AdminModule(
      'inventory',
      'Inventory',
      Icons.inventory_2_outlined,
      'inventory',
    ),
    AdminModule('barcode', 'Barcode', Icons.qr_code_2_outlined, 'barcode'),
    AdminModule('racks', 'Racks', Icons.view_list_outlined, 'rack.read'),
    AdminModule('products', 'Products', Icons.widgets_outlined, 'products'),
    AdminModule('customers', 'Customers', Icons.people_outline, 'customers'),
    AdminModule(
      'suppliers',
      'Suppliers',
      Icons.local_shipping_outlined,
      'suppliers',
    ),
    AdminModule('expenses', 'Expenses', Icons.payments_outlined, 'expenses'),
    AdminModule(
      'attendance',
      'Staff Attendance',
      Icons.fact_check_outlined,
      'attendance',
    ),
    AdminModule('reports', 'Reports', Icons.bar_chart_outlined, 'reports'),
    AdminModule(
      'businesses',
      'Businesses & Outlets',
      Icons.store_mall_directory_outlined,
      'businesses',
    ),
    AdminModule('staff', 'Users & Staff', Icons.badge_outlined, 'staff'),
    AdminModule('settings', 'Settings', Icons.settings_outlined, 'settings'),
    AdminModule('godowns', 'Godowns', Icons.warehouse_outlined, 'godown.read'),
  ];

  static bool allows(String module, List<String> permissions) {
    final moduleKey = PermissionIdMatcher.normalize(module);
    for (final permission in permissions) {
      final key = PermissionIdMatcher.normalize(permission);
      if (key == '*' || key == 'all' || key == moduleKey) return true;
      if (key.startsWith('$moduleKey.') || key.startsWith('${moduleKey}_')) {
        return true;
      }
      if (key == 'view_$moduleKey' || key == 'manage_$moduleKey') return true;
    }
    return false;
  }

  static List<AdminModule> visibleModules(List<String> permissions) {
    final visible = modules
        .where(
          (module) =>
              allows(module.permission, permissions) ||
              (module.id == 'barcode' &&
                  (allows('products', permissions) ||
                      allows('product.read', permissions))) ||
              (module.id == 'godowns' && allows('godown.view', permissions)),
        )
        .toList();
    if (permissions.isNotEmpty &&
        !visible.any((module) => module.id == 'dashboard')) {
      visible.insert(
        0,
        modules.firstWhere((module) => module.id == 'dashboard'),
      );
    }
    return visible;
  }
}

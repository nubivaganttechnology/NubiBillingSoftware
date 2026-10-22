import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/user_model.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/domain/entities/dashboard_summary.dart';
import 'package:testflutter/presentation/dashboard/admin_dashboard_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'dashboard_navigation_test.dart' show NavigationController;

class MockSyncEngine extends ChangeNotifier implements SyncEngine {
  MockSyncEngine({
    this.state = SyncState.synced,
    this.pendingCount = 0,
    this.error,
  });

  @override
  SyncState state;

  @override
  int pendingCount;

  @override
  String? error;

  @override
  final StreamController<void> changes = StreamController<void>.broadcast();

  @override
  Future<void> retry() async {}

  @override
  Future<void> sync({
    bool? pull,
    bool? push,
    bool refreshCatalogue = false,
    bool catalogueOnly = false,
  }) async {}

  @override
  void dispose() {
    changes.close();
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class DashboardTestController extends NavigationController {
  DashboardTestController({this.mockSync}) : super(showOverview: true);

  final MockSyncEngine? mockSync;

  @override
  SyncEngine? get sync => mockSync;

  @override
  AppContext get appContext => const AppContext(
        uid: 'test-owner',
        accountType: 'owner',
        ownerUid: 'test-owner',
        businessId: 'biz-1',
        outletId: 'out-1',
        permissions: ['*'],
      );

  @override
  UserModel? get user => const UserModel(
        uid: 'test-owner',
        name: 'John Doe',
        email: 'john@example.com',
        accountType: 'owner',
        isActive: true,
        phone: '+919876543210',
      );

  @override
  List<BusinessModel> get businesses => const [
        BusinessModel(
          businessId: 'biz-1',
          businessName: 'Apex Industrial Supplies & Paints',
          normalizedBusinessName: 'apex industrial supplies & paints',
          ownerUid: 'test-owner',
          businessTypeId: 'retail',
          businessTypeName: 'Retail',
          isActive: true,
        ),
        BusinessModel(
          businessId: 'biz-2',
          businessName: 'Apex Wholesale Distribution',
          normalizedBusinessName: 'apex wholesale distribution',
          ownerUid: 'test-owner',
          businessTypeId: 'wholesale',
          businessTypeName: 'Wholesale',
          isActive: true,
        ),
      ];

  @override
  List<OutletModel> get outlets => const [
        OutletModel(
          outletId: 'out-1',
          businessId: 'biz-1',
          ownerUid: 'test-owner',
          tenantId: 'test-owner',
          outletName: 'Central Warehouse Outlet',
          outletTypeId: 'warehouse',
          outletTypeName: 'Warehouse',
          isActive: true,
        ),
        OutletModel(
          outletId: 'out-2',
          businessId: 'biz-1',
          ownerUid: 'test-owner',
          tenantId: 'test-owner',
          outletName: 'North City Branch',
          outletTypeId: 'shop',
          outletTypeName: 'Shop',
          isActive: true,
        ),
      ];

  @override
  OutletModel? get currentOutlet => outlets.first;

  @override
  bool canCreateOutlet() => true;
}

void main() {
  group('AdminDashboardPage TopBar Overflow Regression Tests', () {
    testWidgets(
      'reproduces and resolves exact 41px RenderFlex overflow at 1233.3px width',
      (tester) async {
        // Exact Windows viewport where 41px overflow occurred
        tester.view.physicalSize = const Size(1233.3, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockSync = MockSyncEngine(state: SyncState.synced);
        final controller = DashboardTestController(mockSync: mockSync);
        addTearDown(mockSync.dispose);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AdminDashboardPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // Core header elements must be present
        expect(find.text('Business'), findsOneWidget);
        expect(find.text('Outlet'), findsOneWidget);
        expect(find.text('Search workspace'), findsOneWidget);
        expect(find.text('Synced'), findsOneWidget);
        expect(find.byTooltip('Synchronization options'), findsOneWidget);
        expect(find.byTooltip('Notifications'), findsOneWidget);
        expect(find.byTooltip('Help'), findsOneWidget);
        expect(find.byTooltip('Profile menu'), findsOneWidget);
      },
    );

    testWidgets(
      'prevents overflow when sync state is pending with wide count at 1233.3px',
      (tester) async {
        tester.view.physicalSize = const Size(1233.3, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockSync = MockSyncEngine(
          state: SyncState.pending,
          pendingCount: 99,
        );
        final controller = DashboardTestController(mockSync: mockSync);
        addTearDown(mockSync.dispose);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AdminDashboardPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Pending (99)'), findsOneWidget);
      },
    );

    testWidgets(
      'prevents overflow across all responsive width breakpoints',
      (tester) async {
        final widthsToTest = [
          1440.0, // Large desktop (wide=true, available=1186)
          1233.3, // Common scaled desktop (wide=true, available=979.3)
          1200.0, // Desktop (wide=true, available=946)
          1040.0, // Sidebar transition threshold (wide=true, available=786)
          1039.0, // Sidebar in drawer (wide=false, available=1039)
          800.0,  // Medium viewport (wide=false, available=800)
          600.0,  // Compact viewport (wide=false, available=600)
          360.0,  // Mobile compact viewport (wide=false, available=360)
        ];

        for (final width in widthsToTest) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;

          final mockSync = MockSyncEngine(state: SyncState.synced);
          final controller = DashboardTestController(mockSync: mockSync);

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: AdminDashboardPage(controller: controller),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'RenderFlex overflow occurred at width $width',
          );
          expect(find.text('Search workspace'), findsOneWidget);

          mockSync.dispose();
          controller.dispose();
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );

    testWidgets(
      'handles null sync engine gracefully without layout issues',
      (tester) async {
        tester.view.physicalSize = const Size(1233.3, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = DashboardTestController(mockSync: null);
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: AdminDashboardPage(controller: controller),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Search workspace'), findsOneWidget);
        expect(find.text('Synced'), findsNothing);
      },
    );
  });

  group('AdminDashboardPage Comprehensive Metrics & Inventory Health Tests', () {
    final mockPopulatedSummary = DashboardSummary(
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
      weeklySales: [
        SalesDaySummary(date: DateTime.now().subtract(const Duration(days: 6)), amount: 50000),
        SalesDaySummary(date: DateTime.now().subtract(const Duration(days: 5)), amount: 65000),
        SalesDaySummary(date: DateTime.now().subtract(const Duration(days: 4)), amount: 48000),
        SalesDaySummary(date: DateTime.now().subtract(const Duration(days: 3)), amount: 72000),
        SalesDaySummary(date: DateTime.now().subtract(const Duration(days: 2)), amount: 80000),
        SalesDaySummary(date: DateTime.now().subtract(const Duration(days: 1)), amount: 60000),
        SalesDaySummary(date: DateTime.now(), amount: 75000),
      ],
      recentSales: [
        RecentSaleSummary(
          invoiceNumber: 'INV-2026-001',
          amount: 2500.0,
          paymentStatus: 'PAID',
          createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        ),
        RecentSaleSummary(
          invoiceNumber: 'INV-2026-002',
          amount: 4800.0,
          paymentStatus: 'PENDING',
          createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      ],
      topProducts: const [
        TopProductSummary(name: 'Asian Paints Apex Ultima 20L', quantity: 45, revenue: 135000),
        TopProductSummary(name: 'Berger Silk Glamor 10L', quantity: 38, revenue: 95000),
      ],
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
        LowStockProductSummary(
          variantId: 'v2',
          name: 'Nippon Paint Weatherbond 20L',
          sku: 'NIP-WB-20L',
          unit: 'bucket',
          currentStock: 0,
          reorderLevel: 5,
          isOutOfStock: true,
        ),
        LowStockProductSummary(
          variantId: 'v3',
          name: 'Dulux Velvet Touch 1L',
          sku: 'DLX-VT-1L',
          unit: 'can',
          currentStock: 2,
          reorderLevel: 8,
          isOutOfStock: false,
        ),
      ],
    );

    testWidgets(
      'renders borrowed amount and inventory health cards accurately without overflow across all viewports',
      (tester) async {
        final widthsToTest = [
          1440.0, // Desktop wide
          1233.3, // Windows standard scaling
          1040.0, // Sidebar transition
          800.0,  // Tablet
          600.0,  // Phablet
          360.0,  // Compact mobile
        ];

        for (final width in widthsToTest) {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1.0;

          final mockSync = MockSyncEngine(state: SyncState.synced);
          final controller = DashboardPopulatedController(
            mockSync: mockSync,
            mockSummary: mockPopulatedSummary,
          );

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(width),
              theme: AppTheme.light,
              home: AdminDashboardPage(controller: controller),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: 'RenderFlex overflow occurred at width $width with populated summary',
          );

          // Verify borrowed amount badge in Total sales
          expect(find.text('Borrowed: ₹75.0k'), findsOneWidget);

          // Verify inventory health section
          final invTitle = find.text('Inventory Health & Stock Intelligence');
          if (invTitle.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              invTitle,
              200,
              scrollable: find.byType(Scrollable).last,
            );
          }
          expect(find.text('Inventory Health & Stock Intelligence'), findsOneWidget);
          expect(find.text('Active in Store'), findsOneWidget);
          expect(find.text('Out of Stock'), findsOneWidget);
          expect(find.text('Low Stock Alerts'), findsOneWidget);

          // Verify actionable reorder list
          final sampleProduct = find.text('Sigmark High Gloss Enamel 4L');
          if (sampleProduct.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              sampleProduct,
              200,
              scrollable: find.byType(Scrollable).last,
            );
          }
          expect(find.text('Action Needed: Reorder List (3 items)'), findsOneWidget);
          expect(find.text('Sigmark High Gloss Enamel 4L'), findsOneWidget);
          expect(find.text('Inward / New Purchase'), findsOneWidget);

          mockSync.dispose();
          controller.dispose();
        }

        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  });
}

class DashboardPopulatedController extends DashboardTestController {
  DashboardPopulatedController({
    super.mockSync,
    required this.mockSummary,
  });

  final DashboardSummary mockSummary;

  @override
  DashboardSummary? get dashboardSummary => mockSummary;
}

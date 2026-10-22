import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/data/models/purchase_bill_model.dart';
import 'package:testflutter/data/models/storage_location_model.dart';
import 'package:testflutter/data/models/supplier_model.dart';
import 'package:testflutter/data/models/sales_invoice_model.dart';
import 'package:testflutter/data/repositories/sales_repository.dart';
import 'package:testflutter/data/models/role_model.dart';
import 'package:testflutter/data/models/user_model.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/domain/entities/dashboard_summary.dart';
import 'package:testflutter/presentation/dashboard/admin_dashboard_page.dart';
import 'package:testflutter/presentation/procurement/purchase_pages.dart';
import 'package:testflutter/presentation/procurement/purchase_entry_page.dart';
import 'package:testflutter/presentation/products/product_pages.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class NavigationController extends EntryController {
  NavigationController({this.showOverview = false});
  final bool showOverview;
  @override
  AppContext get appContext => const AppContext(
    uid: 'owner',
    accountType: 'owner',
    ownerUid: 'owner',
    businessId: 'business',
    permissions: ['*'],
  );
  @override
  UserModel? get user => null;
  @override
  RoleModel? get role => null;
  @override
  List<BusinessModel> get businesses => const [];
  @override
  List<OutletModel> get outlets => [?currentOutlet];
  @override
  OutletModel? get currentOutlet => showOverview
      ? const OutletModel(
          outletId: 'outlet',
          businessId: 'business',
          ownerUid: 'owner',
          tenantId: 'owner',
          outletName: 'Test outlet',
          outletTypeId: 'shop',
          outletTypeName: 'Shop',
          isActive: true,
        )
      : null;
  @override
  DashboardSummary? get dashboardSummary => null;
  @override
  bool get dashboardLoading => false;
  @override
  String? get dashboardError => null;
  @override
  bool canCreateOutlet() => showOverview;
  @override
  bool canManagePurchases() => true;
  @override
  bool canCreatePurchases() => true;
  @override
  bool canCreateSuppliers() => false;
  @override
  List<ProductVariantModel> get purchaseProducts => const [];
  @override
  Map<String, int> get productStock => const {};
  @override
  List<SupplierModel> get suppliers => const [];
  @override
  List<StorageLocationModel> get storageLocations => const [];
  @override
  String get error => '';
  @override
  String? get productsError => null;
  @override
  Future<void> loadStorageLocations() async {}
  @override
  Future<List<ProductVariantModel>> loadSalesVariants() async => const [];
  @override
  Future<List<Map<String, dynamic>>> loadSalesCustomers() async => const [];
  @override
  Future<List<SalesBatchOption>> loadSalesBatches(
    String productId,
    String variantId,
  ) async => const [];
  @override
  Future<String> postSalesInvoice({
    required String invoiceId,
    required DateTime invoiceDate,
    required String? customerId,
    required String? customerName,
    String? chargeToEmployeeId,
    required List<SalesInvoiceLine> lines,
  }) async => invoiceId;
  @override
  List<PurchaseBillModel> get purchaseBills => const [];
  @override
  bool get purchasesLoading => false;
  @override
  bool get purchaseSaving => false;
  @override
  String? get purchasesError => null;
  @override
  Future<void> loadPurchases() async {}
  @override
  Future<void> refreshDashboard() async {}
  @override
  Future<void> refreshPendingAttendanceCount() async {}
  @override
  int get pendingAttendanceCount => 0;
}

class TwoOutletController extends NavigationController {
  TwoOutletController() : super(showOverview: true);
  final selected = <String>[];
  OutletModel _outlet(String id, String name) => OutletModel(
    outletId: id,
    businessId: 'business',
    ownerUid: 'owner',
    tenantId: 'owner',
    outletName: name,
    outletTypeId: 'shop',
    outletTypeName: 'Shop',
    isActive: true,
  );
  @override
  AppContext get appContext => const AppContext(
    uid: 'owner',
    accountType: 'owner',
    ownerUid: 'owner',
    businessId: 'business',
    outletId: 'o1',
    permissions: ['*'],
  );
  @override
  List<OutletModel> get outlets => [
    _outlet('o1', 'Kolkata Hardware Shop'),
    _outlet('o2', 'Howrah Paint Store'),
  ];
  @override
  OutletModel? get currentOutlet => outlets.first;
  @override
  Future<void> selectOutlet(String outletId) async => selected.add(outletId);
}

class PurchaseStorageController extends TwoOutletController {
  @override
  List<StorageLocationModel> get storageLocations => [
    _storageLocation(
      id: 'godown-a',
      name: 'Godown A',
      type: StorageLocationType.godown,
    ),
    _storageLocation(
      id: 'godown-b',
      name: 'Godown B',
      type: StorageLocationType.godown,
    ),
    _storageLocation(
      id: 'rack-outlet',
      name: 'Outlet Rack',
      type: StorageLocationType.rack,
      parentId: 'o1',
      parentType: 'OUTLET',
    ),
    _storageLocation(
      id: 'rack-a',
      name: 'Godown A Rack',
      type: StorageLocationType.rack,
      parentId: 'godown-a',
      parentType: 'GODOWN',
    ),
    _storageLocation(
      id: 'rack-b',
      name: 'Godown B Rack',
      type: StorageLocationType.rack,
      parentId: 'godown-b',
      parentType: 'GODOWN',
    ),
  ];
}

StorageLocationModel _storageLocation({
  required String id,
  required String name,
  required StorageLocationType type,
  String? parentId,
  String? parentType,
}) => StorageLocationModel(
  storageLocationId: id,
  tenantId: 'owner',
  businessId: 'business',
  name: name,
  code: id,
  type: type,
  status: StorageLocationStatus.active,
  createdBy: 'owner',
  updatedBy: 'owner',
  createdAt: null,
  updatedAt: null,
  version: 1,
  parentLocationId: parentId,
  parentLocationType: parentType,
);

void main() {
  testWidgets('Barcode opens as a separate dashboard sidebar module', (
    tester,
  ) async {
    final controller = NavigationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminDashboardPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    if (find.widgetWithText(ListTile, 'Barcode').evaluate().isEmpty) {
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(ListTile, 'Barcode'));
    await tester.pumpAndSettle();

    expect(find.text('Barcode'), findsOneWidget);
    expect(find.text('Barcode Printing'), findsAtLeastNWidgets(1));
    expect(find.text('Barcode Lookup'), findsOneWidget);
  });

  testWidgets(
    'Sales opens the manual batch allocation entry in the dashboard shell',
    (tester) async {
      tester.view.physicalSize = const Size(1680, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = NavigationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Sales'));
      await tester.pumpAndSettle();
      expect(find.text('New Sale'), findsWidgets);
      expect(find.text('Customer and invoice'), findsOneWidget);
      expect(find.text('Sale items'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Sales'), findsOneWidget);
    },
  );

  testWidgets(
    'Purchase form stays in dashboard shell and Back and Cancel return to list',
    (tester) async {
      tester.view.physicalSize = const Size(1680, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TwoOutletController();
      addTearDown(controller.dispose);
      final selectedOutlet = controller.currentOutlet?.outletId;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Purchase'));
      await tester.pumpAndSettle();
      expect(find.text('Purchases'), findsOneWidget);
      expect(find.text('Search workspace'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);

      await tester.tap(find.text('New Purchase'));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseEntryPage), findsOneWidget);
      expect(find.text('Search workspace'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
      expect(find.text('Purchase'), findsOneWidget);
      for (final header in [
        '#',
        'Product',
        'Variant / Specification',
        'HSN',
        'Barcode',
        'Internal Batch No',
        'Supplier Lot',
        'Mfg Date',
        'Expiry Date',
        'Qty',
        'Unit',
        'Purchase Price',
        'GST %',
        'Taxable',
        'MRP',
        'Selling Price',
        'Receiving',
        'Store At',
        'Location',
        'Rack',
        'Total',
        'Delete',
      ]) {
        expect(
          find.descendant(
            of: find.byType(PurchaseEntryPage),
            matching: find.text(header),
          ),
          findsAtLeastNWidgets(1),
          reason: 'Missing $header header',
        );
      }
      expect(find.text('Preview'), findsWidgets);
      expect(find.text('Save Draft'), findsWidgets);
      expect(find.text('Review & Post'), findsWidgets);
      await tester.tap(find.text('Preview').first);
      await tester.pumpAndSettle();
      expect(find.text('Purchase Preview'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Back to Edit'), findsOneWidget);
      await tester.tap(find.text('Back to Edit'));
      await tester.pumpAndSettle();
      final purchaseGrid = find.byKey(
        const ValueKey('purchase-items-horizontal-scroll'),
      );
      final horizontalScrollables = find.descendant(
        of: purchaseGrid,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      expect(horizontalScrollables, findsWidgets);
      final horizontalScrollable = horizontalScrollables.first;
      final gridPosition = tester
          .state<ScrollableState>(horizontalScrollable)
          .position;
      expect(gridPosition.maxScrollExtent, greaterThan(0));
      await tester.drag(purchaseGrid, const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(gridPosition.pixels, greaterThan(0));
      gridPosition.jumpTo(gridPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(gridPosition.pixels, gridPosition.maxScrollExtent);
      expect(find.text('Selling Price'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      gridPosition.jumpTo(0);
      await tester.pumpAndSettle();
      expect(controller.currentOutlet?.outletId, selectedOutlet);
      tester.view.physicalSize = const Size(1100, 900);
      await tester.pumpAndSettle();
      expect(find.text('Search workspace'), findsOneWidget);
      expect(find.text('Business'), findsOneWidget);
      expect(find.text('Internal Batch No'), findsOneWidget);
      expect(gridPosition.maxScrollExtent, greaterThan(0));
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1680, 900);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back to Purchases'));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseEntryPage), findsNothing);
      expect(find.text('Purchases'), findsOneWidget);
      expect(controller.currentOutlet?.outletId, selectedOutlet);

      await tester.tap(find.text('New Purchase'));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseEntryPage), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseEntryPage), findsNothing);
      expect(find.text('Purchases'), findsOneWidget);
      expect(controller.currentOutlet?.outletId, selectedOutlet);
    },
  );

  testWidgets('Products keeps a visible Outlet selector that switches outlet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TwoOutletController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: AdminDashboardPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Products'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductManagementPage), findsOneWidget);
    expect(find.text('Outlet'), findsWidgets);
    expect(find.text('Kolkata Hardware Shop'), findsWidgets);
    await tester.tap(find.text('Kolkata Hardware Shop').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Howrah Paint Store').last);
    await tester.pumpAndSettle();
    expect(controller.selected, ['o2']);
  });

  testWidgets(
    'Purchase storage destination filters optional racks by location',
    (tester) async {
      tester.view.physicalSize = const Size(1680, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PurchaseStorageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Purchase'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Purchase'));
      await tester.pumpAndSettle();

      final grid = find.byKey(
        const ValueKey('purchase-items-horizontal-scroll'),
      );
      final scrollables = find.descendant(
        of: grid,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.right,
        ),
      );
      tester.state<ScrollableState>(scrollables.first).position.jumpTo(2300);
      await tester.pumpAndSettle();

      // The first row defaults to direct outlet storage with its rack left empty.
      expect(find.text('Outlet'), findsWidgets);
      expect(find.text('No Rack'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('purchase-rack-1')));
      await tester.pumpAndSettle();
      expect(find.text('Outlet Rack'), findsOneWidget);
      expect(find.text('Godown A Rack'), findsNothing);
      await tester.tap(find.text('Outlet Rack').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('purchase-store-at-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Godown').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-location-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Godown A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-rack-2')));
      await tester.pumpAndSettle();
      expect(find.text('Godown A Rack'), findsOneWidget);
      expect(find.text('Godown B Rack'), findsNothing);
      await tester.tap(find.text('Godown A Rack').last);
      await tester.pumpAndSettle();
      expect(find.text('Godown A Rack'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('purchase-store-at-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Godown').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-location-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Godown B').last);
      await tester.pumpAndSettle();
      expect(find.text('No Rack'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('purchase-store-at-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Godown').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-location-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Godown B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-rack-4')));
      await tester.pumpAndSettle();
      expect(find.text('Godown B Rack'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('purchase-rack-4')),
          matching: find.text('Godown A Rack'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Products row action allows Remove from this outlet with confirmation',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TwoOutletController();
      controller.products.add(
        ProductModel(
          productId: 'p1',
          tenantId: 'owner',
          businessId: 'business',
          name: 'ASIAN PAINTS DAMP PROOF SUPERFLEX',
          brand: 'Asian Paints',
          category: 'Waterproofing',
          status: 'ACTIVE',
          variants: const [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Products'));
      await tester.pumpAndSettle();
      expect(find.text('ASIAN PAINTS DAMP PROOF SUPERFLEX'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('product-actions-p1')));
      await tester.pumpAndSettle();

      // Row action menu in outlet scope has NO global Deactivate or Delete
      expect(find.text('Deactivate'), findsNothing);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Remove from this outlet'), findsOneWidget);

      await tester.tap(find.text('Remove from this outlet'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from this outlet?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('confirm-remove-from-outlet')),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Select all in table: toolbar has Remove from this outlet, NOT global Delete or Deactivate
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('bulk-remove-from-outlet')),
        findsOneWidget,
      );
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Deactivate'), findsNothing);
    },
  );

  for (final width in [800.0, 1440.0]) {
    testWidgets('Dashboard cards open Products and Purchase at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
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
      if (width == 1440) {
        tester.view.physicalSize = const Size(800, 900);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();
      }
      final productCard = find.descendant(
        of: find.byType(Card),
        matching: find.text('Products'),
      );
      await tester.tap(productCard);
      await tester.pumpAndSettle();
      expect(find.byType(ProductManagementPage), findsOneWidget);
      if (width < 1040) {
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(ListTile, 'Dashboard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Total purchases'));
      await tester.pumpAndSettle();
      expect(find.byType(PurchaseManagementPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Products and Purchase navigation accepts clicks at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = NavigationController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AdminDashboardPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> select(String label) async {
        if (width < 1040) {
          await tester.tap(find.byTooltip('Open navigation'));
          await tester.pumpAndSettle();
        }
        final tile = find.widgetWithText(ListTile, label);
        if (tile.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            tile,
            label == 'Dashboard' || label == 'Purchase' ? -200 : 200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await select('Products');
      expect(find.byType(ProductManagementPage), findsOneWidget);
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      expect(find.text('Save Product'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await select('Purchase');
      expect(find.byType(PurchaseManagementPage), findsOneWidget);
      await select('Dashboard');
      expect(find.text('No Outlet Available').last, findsOneWidget);
    });
  }
}

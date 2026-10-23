import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/data/models/stock_transaction_audit_model.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/l10n/app_localizations.dart';
import 'package:testflutter/presentation/inventory/inventory_dashboard_page.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class RegressionInventoryController extends EntryController {
  RegressionInventoryController({
    List<ProductModel>? products,
    Map<String, int>? initialStock,
    Map<String, bool>? initialInitialized,
  })  : _products = products ?? _testProducts(),
        _stock = initialStock ?? {'var-zero': 0},
        _openingStockInitialized = initialInitialized != null
            ? Map.from(initialInitialized)
            : {'var-zero': true};

  final List<ProductModel> _products;
  final Map<String, int> _stock;
  final Map<String, bool> _openingStockInitialized;
  final List<StockTransactionAuditModel> _history = [];
  int adjustmentCallCount = 0;
  int openingStockCallCount = 0;

  @override
  Locale get currentLocale => const Locale('en');

  @override
  bool canManageProducts() => true;

  @override
  bool canCreatePurchases() => true;

  @override
  bool canManagePurchases() => true;

  @override
  bool canViewStorage() => true;

  @override
  bool canViewInventory() => true;

  @override
  bool canAddOpeningStock() => true;

  @override
  bool canAdjustStock() => true;

  @override
  bool canApproveAdjustment() => true;

  @override
  AppContext get appContext => const AppContext(
        uid: 'user-1',
        accountType: 'owner',
        ownerUid: 'owner-1',
        businessId: 'bus-1',
        permissions: ['*'],
      );

  @override
  String? get idToken => 'mock-id-token';

  @override
  OutletModel get currentOutlet => const OutletModel(
        outletId: 'out-1',
        businessId: 'bus-1',
        ownerUid: 'owner-1',
        tenantId: 'owner-1',
        outletName: 'Central Paint Depot',
        outletTypeId: 'retail',
        outletTypeName: 'Retail Outlet',
        isActive: true,
      );

  @override
  List<ProductModel> get products => _products;

  @override
  Map<String, int> get productStock => _stock;

  @override
  Future<void> loadProducts() async {
    notifyListeners();
  }

  @override
  Future<bool> hasOpeningStockBeenInitialized(String variantId) async {
    return _openingStockInitialized[variantId] ?? false;
  }

  @override
  Future<StockTransactionAuditModel> addOpeningStock({
    required String productId,
    required String variantId,
    required int quantity,
    required String reason,
    int? unitCostPaise,
    String? unit,
    String? transactionId,
    int? sellingPricePaise,
    int? mrpPaise,
  }) async {
    openingStockCallCount++;
    _openingStockInitialized[variantId] = true;
    final prev = _stock[variantId] ?? 0;
    final next = prev + quantity;
    _stock[variantId] = next;

    final audit = StockTransactionAuditModel(
      transactionId: transactionId ?? 'TX_OP_$openingStockCallCount',
      businessId: 'bus-1',
      outletId: 'out-1',
      productId: productId,
      variantId: variantId,
      transactionType: StockTransactionAuditModel.typeOpeningStock,
      sourceDocumentId: 'OP_REF',
      previousQuantity: prev,
      changedQuantity: quantity,
      newQuantity: next,
      unit: unit ?? 'pcs',
      reason: reason,
      performedBy: 'user-1',
      approvedBy: 'user-1',
      approvalStatus: StockTransactionAuditModel.statusPosted,
      createdAt: DateTime.now().toUtc(),
      syncStatus: StockTransactionAuditModel.statusPendingSync,
    );
    _history.add(audit);
    return audit;
  }

  @override
  Future<StockTransactionAuditModel> requestOrApplyAdjustment({
    required String productId,
    required String variantId,
    required int quantity,
    required bool isIncrease,
    required String transactionType,
    required String reason,
    String? unit,
    int? unitCostPaise,
    String? transactionId,
    String? sourceDocumentId,
  }) async {
    adjustmentCallCount++;
    // Simulate short network latency to test rapid double clicking
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final prev = _stock[variantId] ?? 0;
    final next = isIncrease ? prev + quantity : prev - quantity;
    _stock[variantId] = next;

    final audit = StockTransactionAuditModel(
      transactionId: transactionId ?? 'TX_ADJ_$adjustmentCallCount',
      businessId: 'bus-1',
      outletId: 'out-1',
      productId: productId,
      variantId: variantId,
      transactionType: transactionType,
      sourceDocumentId: sourceDocumentId ?? 'ADJ_REF',
      previousQuantity: prev,
      changedQuantity: quantity,
      newQuantity: next,
      unit: unit ?? 'pcs',
      reason: reason,
      performedBy: 'user-1',
      approvedBy: 'user-1',
      approvalStatus: StockTransactionAuditModel.statusPosted,
      createdAt: DateTime.now().toUtc(),
      syncStatus: StockTransactionAuditModel.statusPendingSync,
    );
    _history.add(audit);
    return audit;
  }

  @override
  Future<List<StockTransactionAuditModel>> getStockHistory({
    String? variantId,
  }) async {
    if (variantId != null) {
      return _history.where((e) => e.variantId == variantId).toList();
    }
    return List.from(_history);
  }

  static List<ProductModel> _testProducts() {
    return [
      ProductModel(
        productId: 'prod-zero',
        tenantId: 'owner-1',
        businessId: 'bus-1',
        name: 'Zero Stock Test Product',
        brand: 'TestBrand',
        category: 'TestCategory',
        status: 'ACTIVE',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        variants: const [
          ProductVariantModel(
            variantId: 'var-zero',
            productId: 'prod-zero',
            businessId: 'bus-1',
            name: 'Standard Unit',
            sku: 'TEST-SKU-001',
            baseUnitId: 'pcs',
            commercialUnitName: 'Piece',
            sellingPrice: 10000,
            purchaseRate: 7000,
            mrp: 12000,
            reorderLevel: 5,
            defaultGstRateBps: 1800,
          ),
        ],
      ),
    ];
  }
}

Widget _buildTestApp(RegressionInventoryController controller) {
  return MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: InventoryDashboardPage(
        controller: controller,
        onOpenProducts: () {},
      ),
    ),
  );
}

void main() {
  group('Inventory Dashboard Stock Dialog Lifecycle & Regression Tests', () {
    testWidgets(
      'Scenario: Product starts with stock 0, updates by +2, closes cleanly without controller disposal exceptions, reflects stock 2',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = RegressionInventoryController();
        await tester.pumpWidget(_buildTestApp(controller));
        await tester.pumpAndSettle();

        // 1. Verify product starts with stock 0 and "Out of Stock"
        expect(find.text('Zero Stock Test Product'), findsOneWidget);
        expect(find.text('Out of Stock'), findsWidgets);

        // 2. Tap stock action button to open action hub
        final actionButton = find.byIcon(Icons.tune_rounded).first;
        await tester.tap(actionButton);
        await tester.pumpAndSettle();

        // 3. Select 'Stock Adjustment'
        expect(find.text('Stock Adjustment'), findsOneWidget);
        await tester.tap(find.text('Stock Adjustment'));
        await tester.pumpAndSettle();

        // 4. Fill in +2 and Reason
        expect(find.text('Current Available Stock:'), findsOneWidget);
        final qtyField = find.widgetWithText(TextField, 'Quantity (Piece)');
        await tester.enterText(qtyField, '2');
        await tester.pumpAndSettle();

        final reasonField = find.widgetWithText(TextField, 'Reason for Adjustment *');
        await tester.enterText(reasonField, 'Audited found stock +2');
        await tester.pumpAndSettle();

        // 5. Submit Adjustment
        final submitButton = find.widgetWithText(FilledButton, 'Submit Adjustment');
        await tester.tap(submitButton);

        // Advance through async network simulation and route pop transition
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // 6. VERIFICATION:
        // No exceptions thrown (specifically no "A TextEditingController was used after being disposed" or GlobalKey errors)
        expect(tester.takeException(), isNull);

        // Stock in controller must be exactly 2000 milli-units (+2 units)
        expect(controller.productStock['var-zero'], 2000);
        expect(controller.adjustmentCallCount, 1);

        // Dashboard must reflect updated stock '2' and success snackbar
        expect(find.text('Stock adjustment applied successfully.'), findsOneWidget);
        expect(find.text('2'), findsWidgets);

        // Check history contains exactly 1 corresponding transaction
        final history = await controller.getStockHistory(variantId: 'var-zero');
        expect(history.length, 1);
        expect(history.first.changedQuantity, 2000);
        expect(history.first.newQuantity, 2000);
      },
    );

    testWidgets(
      'Scenario: Rapid double submission prevention - only one transaction created for rapid clicks',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = RegressionInventoryController();
        await tester.pumpWidget(_buildTestApp(controller));
        await tester.pumpAndSettle();

        // Open stock action hub
        await tester.tap(find.byIcon(Icons.tune_rounded).first);
        await tester.pumpAndSettle();

        // Open stock adjustment dialog
        await tester.tap(find.text('Stock Adjustment'));
        await tester.pumpAndSettle();

        // Enter quantity and reason
        await tester.enterText(find.widgetWithText(TextField, 'Quantity (Piece)'), '5');
        await tester.enterText(find.widgetWithText(TextField, 'Reason for Adjustment *'), 'Rapid click test');
        await tester.pumpAndSettle();

        final submitButton = find.widgetWithText(FilledButton, 'Submit Adjustment');

        // Tap submit twice rapidly in the same frame sequence
        await tester.tap(submitButton);
        await tester.tap(submitButton, warnIfMissed: false);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Adjustment call count must be EXACTLY 1 (second click ignored because _saving was true)
        expect(controller.adjustmentCallCount, 1);
        expect(controller.productStock['var-zero'], 5000);
      },
    );

    testWidgets(
      'Scenario: Opening stock entry workflow completes cleanly and refreshes dashboard',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = RegressionInventoryController(
          initialInitialized: {'var-zero': false},
        );
        await tester.pumpWidget(_buildTestApp(controller));
        await tester.pumpAndSettle();

        // Open action hub
        await tester.tap(find.byIcon(Icons.tune_rounded).first);
        await tester.pumpAndSettle();

        // Select Add Opening Stock
        await tester.tap(find.text('Add Opening Stock'));
        await tester.pumpAndSettle();

        expect(find.text('Register Opening Stock'), findsOneWidget);

        // Enter quantity and required unit purchase cost
        await tester.enterText(find.widgetWithText(TextField, 'Opening Quantity (Piece)'), '10');
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Unit Purchase Cost (₹) *'), '50.00');
        await tester.pumpAndSettle();

        // Confirm
        await tester.tap(find.widgetWithText(FilledButton, 'Confirm Opening Stock'));
        await tester.pumpAndSettle();

        // Secondary confirmation modal
        expect(find.text('Confirm Opening Stock Registration'), findsOneWidget);
        await tester.tap(find.text('Confirm & Post'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(controller.openingStockCallCount, 1);
        expect(controller.productStock['var-zero'], 10000);
        expect(find.text('Opening stock recorded successfully.'), findsOneWidget);
        expect(find.text('10'), findsWidgets);
      },
    );

    testWidgets(
      'Scenario: Repeated dialog opening and cancelling causes zero duplicate GlobalKey or disposal errors',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final controller = RegressionInventoryController();
        await tester.pumpWidget(_buildTestApp(controller));
        await tester.pumpAndSettle();

        // Open and cancel 3 times consecutively
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byIcon(Icons.tune_rounded).first);
          await tester.pumpAndSettle();

          await tester.tap(find.text('Stock Adjustment'));
          await tester.pumpAndSettle();

          expect(find.text('Stock Adjustment'), findsOneWidget);

          // Tap Cancel
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
        }

        // Screen remains responsive
        expect(find.text('Zero Stock Test Product'), findsOneWidget);
      },
    );
  });
}

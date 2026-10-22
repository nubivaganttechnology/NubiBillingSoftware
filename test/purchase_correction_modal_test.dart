import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/purchase_bill_model.dart';
import 'package:testflutter/data/models/supplier_model.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/presentation/procurement/purchase_pages.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'product_entry_form_test.dart' show EntryController;

class CorrectPurchaseController extends EntryController {
  CorrectPurchaseController(this.bills, {this.batchVerified = true});

  final List<PurchaseBillModel> bills;
  final bool batchVerified;
  int correctionCalls = 0;
  Map<String, dynamic>? lastCorrection;
  int allocatedAmount = 0;
  int unallocatedAdvance = 0;

  @override
  AppContext get appContext => const AppContext(
    uid: 'owner',
    accountType: 'owner',
    ownerUid: 'owner',
    businessId: 'business',
    outletId: 'outlet',
    permissions: ['*'],
  );

  @override
  bool canManagePurchases() => true;

  @override
  bool canCreatePurchases() => false;

  @override
  List<SupplierModel> get suppliers => const [];

  @override
  List<PurchaseBillModel> get purchaseBills => bills;

  @override
  bool get purchasesLoading => false;

  @override
  bool get purchaseSaving => false;

  @override
  String? get purchasesError => null;

  @override
  Future<void> loadPurchases() async {}

  @override
  Future<bool> correctPurchaseMetadata({
    required PurchaseBillModel bill,
    required String reason,
    required String supplierInvoiceNumber,
    required DateTime invoiceDate,
    required DateTime purchaseDate,
    required Map<String, Map<String, dynamic>> lineMetadata,
  }) async {
    correctionCalls++;
    lastCorrection = {
      'bill': bill,
      'reason': reason,
      'supplierInvoiceNumber': supplierInvoiceNumber,
      'invoiceDate': invoiceDate,
      'purchaseDate': purchaseDate,
      'lineMetadata': lineMetadata,
    };
    return true;
  }

  @override
  Future<Map<String, int>?> loadPurchasePaymentReleasePreview(
    PurchaseBillModel bill,
  ) async => {
    'allocatedAmount': allocatedAmount,
    'unallocatedAdvance': unallocatedAdvance,
  };

  @override
  Future<Map<String, Map<String, dynamic>>>
  loadAdvancedPurchaseCorrectionContext(PurchaseBillModel bill) async => {
    for (final item in bill.items)
      item.goodsReceiptItemId: {
        'verified': batchVerified,
        if (!batchVerified)
          'blockedReason':
              'This batch lacks complete verified movement-ledger coverage.',
        'receivedBaseQuantity': item.baseQuantity,
        'consumedBaseQuantity': 0,
        'availableBaseQuantity': item.baseQuantity,
        'stockQuantityOnHand': item.baseQuantity,
      },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'multi-item correction accordion, advanced fields, top reset, and fixed footer',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CorrectPurchaseController([_bill(itemCount: 10)]);
      addTearDown(controller.dispose);
      await _pumpPage(tester, controller);

      await _openCorrection(tester);
      expect(find.text('Invoice Details'), findsOneWidget);
      expect(find.text('Supplier Invoice No.'), findsOneWidget);
      expect(find.text('Original: INV-ORIGINAL'), findsOneWidget);
      expect(find.text('Original: LOT-1'), findsOneWidget);
      expect(find.text('Original: 2026-09-01'), findsOneWidget);
      expect(find.text('Original: 2028-04-01'), findsOneWidget);
      var expansionIcons = tester.widgetList<ExpandIcon>(
        find.byType(ExpandIcon),
      );
      expect(expansionIcons.first.isExpanded, isTrue);
      expect(expansionIcons.skip(1).first.isExpanded, isFalse);

      await tester.ensureVisible(find.text('Product 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Product 2'));
      await tester.pumpAndSettle();
      expansionIcons = tester.widgetList<ExpandIcon>(find.byType(ExpandIcon));
      expect(expansionIcons.first.isExpanded, isFalse);
      expect(expansionIcons.skip(1).first.isExpanded, isTrue);
      expect(find.text('Original: LOT-2'), findsOneWidget);

      final dialogScroll = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(SingleChildScrollView),
      );
      final scrollable = dialogScroll.first;
      await tester.drag(scrollable, const Offset(0, -1400));
      await tester.pumpAndSettle();
      final firstScrollController = tester
          .widget<SingleChildScrollView>(scrollable)
          .controller!;
      expect(firstScrollController.position.pixels, greaterThan(0));

      // The actions stay available even when the content is scrolled.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save Correction'), findsOneWidget);
      final textFields = tester.widgetList<TextField>(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
      );
      final labels = textFields
          .map((field) => field.decoration?.labelText ?? '')
          .toList();
      expect(labels, contains('Supplier Invoice No.'));
      for (final editable in [
        'Quantity',
        'Purchase Rate (₹)',
        'GST %',
        'MRP (₹)',
        'Selling Price (₹)',
      ]) {
        expect(labels, contains(editable));
      }
      for (final locked in [
        'Supplier',
        'Storage Location',
        'Rack',
        'Product',
        'Variant',
        'Barcode',
        'Internal Batch No.',
      ]) {
        expect(labels, isNot(contains(locked)));
      }

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await _openCorrection(tester);
      expect(find.text('Supplier Invoice No.'), findsOneWidget);
      final reopenedController = tester
          .widget<SingleChildScrollView>(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.byType(SingleChildScrollView),
                )
                .first,
          )
          .controller!;
      expect(reopenedController.position.pixels, 0);
    },
  );

  testWidgets(
    'single-item correction keeps blank dates optional and all date pickers available',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CorrectPurchaseController([
        _bill(itemCount: 1, blankItemDates: true),
      ]);
      addTearDown(controller.dispose);
      await _pumpPage(tester, controller);
      await _openCorrection(tester);

      final mfgField = _fieldFor('Manufacturing Date (YYYY-MM-DD)');
      final expiryField = _fieldFor('Expiry Date (YYYY-MM-DD)');
      expect(tester.widget<TextField>(mfgField).controller!.text, isEmpty);
      expect(tester.widget<TextField>(expiryField).controller!.text, isEmpty);
      expect(find.text('Original: —'), findsNWidgets(2));

      for (final label in [
        'Invoice Date (YYYY-MM-DD)',
        'Purchase Date (YYYY-MM-DD)',
        'Manufacturing Date (YYYY-MM-DD)',
        'Expiry Date (YYYY-MM-DD)',
      ]) {
        final picker = find.byTooltip('Choose $label');
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
      }

      expect(tester.widget<TextField>(mfgField).controller!.text, isEmpty);
      expect(tester.widget<TextField>(expiryField).controller!.text, isEmpty);

      for (final label in [
        'Invoice Date (YYYY-MM-DD)',
        'Purchase Date (YYYY-MM-DD)',
        'Manufacturing Date (YYYY-MM-DD)',
        'Expiry Date (YYYY-MM-DD)',
      ]) {
        final picker = find.byTooltip('Choose $label');
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('15').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK').last);
        await tester.pumpAndSettle();
        final value = tester
            .widget<TextField>(_fieldFor(label))
            .controller!
            .text;
        expect(value, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      }
    },
  );

  testWidgets('unverified batch quantity is visibly disabled with reason', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CorrectPurchaseController([
      _bill(itemCount: 1),
    ], batchVerified: false);
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller);
    await _openCorrection(tester);
    final quantity = tester.widget<TextField>(_fieldFor('Quantity'));
    expect(quantity.enabled, isFalse);
    expect(
      find.textContaining('lacks complete verified movement-ledger coverage'),
      findsOneWidget,
    );
  });

  testWidgets(
    'strict date validation and required reason guard existing save path',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CorrectPurchaseController([
        _bill(itemCount: 1, blankItemDates: true),
      ]);
      addTearDown(controller.dispose);
      await _pumpPage(tester, controller);
      await _openCorrection(tester);

      await tester.enterText(
        _fieldFor('Invoice Date (YYYY-MM-DD)'),
        '2026-02-31',
      );
      await tester.tap(find.text('Save Correction'));
      await tester.pumpAndSettle();
      expect(controller.correctionCalls, 0);
      expect(
        find.text('Enter a correction reason and valid dates as YYYY-MM-DD.'),
        findsOneWidget,
      );

      await _openCorrection(tester);
      await tester.enterText(
        _fieldFor('Invoice Date (YYYY-MM-DD)'),
        '2026-10-15',
      );
      await tester.enterText(
        _fieldFor('Reason for correction'),
        'Correct date',
      );
      await tester.tap(find.text('Save Correction'));
      await tester.pumpAndSettle();
      expect(controller.correctionCalls, 1);
      expect(controller.lastCorrection?['reason'], 'Correct date');
      expect(controller.lastCorrection?['invoiceDate'], DateTime(2026, 10, 15));
      expect(controller.lastCorrection?['purchaseDate'], DateTime(2026, 10, 1));
      final metadata =
          controller.lastCorrection?['lineMetadata']
              as Map<String, Map<String, dynamic>>;
      expect(metadata['LINE-1']?['manufacturingDate'], isNull);
      expect(metadata['LINE-1']?['expiryDate'], isNull);
    },
  );

  testWidgets('empty correction reason blocks save', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CorrectPurchaseController([_bill(itemCount: 1)]);
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller);
    await _openCorrection(tester);

    await tester.tap(find.text('Save Correction'));
    await tester.pumpAndSettle();
    expect(controller.correctionCalls, 0);
    expect(
      find.text('Enter a correction reason and valid dates as YYYY-MM-DD.'),
      findsOneWidget,
    );
  });

  testWidgets('downward correction confirms excess supplier advance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller =
        CorrectPurchaseController([_bill(itemCount: 1, paidAmount: 10000)])
          ..allocatedAmount = 10000
          ..unallocatedAdvance = 2500;
    addTearDown(controller.dispose);
    await _pumpPage(tester, controller);
    await _openCorrection(tester);
    await tester.enterText(_fieldFor('Purchase Rate (₹)'), '80.00');
    await tester.enterText(
      _fieldFor('Reason for correction'),
      'Rate correction',
    );
    await tester.tap(find.text('Save Correction'));
    await tester.pumpAndSettle();

    expect(
      find.text('Excess payment will become Supplier Advance'),
      findsOneWidget,
    );
    expect(find.text('Current purchase total: ₹100.00'), findsOneWidget);
    expect(find.text('Corrected purchase total: ₹80.00'), findsOneWidget);
    expect(find.text('Amount currently applied: ₹100.00'), findsOneWidget);
    expect(find.text('Excess amount: ₹20.00'), findsOneWidget);
    expect(
      find.text('Supplier advance after correction: ₹45.00'),
      findsOneWidget,
    );
    expect(find.textContaining('No cash refund is recorded.'), findsOneWidget);
    await tester.tap(find.text('Apply Correction'));
    await tester.pumpAndSettle();
    expect(controller.correctionCalls, 1);
  });
}

Finder _fieldFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

Future<void> _pumpPage(
  WidgetTester tester,
  CorrectPurchaseController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: PurchaseManagementPage(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openCorrection(WidgetTester tester) async {
  final target = find.byTooltip('Purchase actions').first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Correct Purchase').last);
  await tester.pumpAndSettle();
}

PurchaseBillModel _bill({
  required int itemCount,
  bool blankItemDates = false,
  int paidAmount = 0,
}) {
  final invoiceDate = DateTime(2026, 10, 1);
  return PurchaseBillModel(
    purchaseBillId: 'PURCHASE-1',
    tenantId: 'owner',
    businessId: 'business',
    outletId: 'outlet',
    supplierId: 'supplier',
    supplierBusinessId: 'supplier-business',
    supplierInvoiceNumber: 'INV-ORIGINAL',
    supplierName: 'Test Supplier',
    purchaseNumber: 'PUR-0001',
    status: 'APPROVED',
    purchaseType: 'DIRECT',
    taxType: 'INTRA_STATE',
    invoiceDate: invoiceDate,
    purchaseDate: invoiceDate,
    entryDate: invoiceDate,
    subtotal: 10000,
    discountAmount: 0,
    taxableAmount: 10000,
    cgstAmount: 0,
    sgstAmount: 0,
    igstAmount: 0,
    chargesAmount: 0,
    roundOff: 0,
    grandTotal: 10000,
    paidAmount: paidAmount,
    outstandingAmount: 10000 - paidAmount,
    paymentStatus: paidAmount == 0 ? 'UNPAID' : 'PARTIAL',
    version: 1,
    items: [
      for (var index = 1; index <= itemCount; index++)
        PurchaseBillItemModel(
          goodsReceiptItemId: 'LINE-$index',
          productId: 'PRODUCT-$index',
          variantId: 'VARIANT-$index',
          productName: 'Product $index',
          variantName: 'Variant $index',
          unitId: 'UNIT',
          conversionFactor: 1000,
          quantity: 1000,
          rate: 10000,
          gstRateBps: 0,
          taxableAmount: 10000,
          taxAmount: 0,
          mrp: 12000,
          sellingPrice: 11000,
          barcodeSnapshot: '70000000000$index',
          internalBatchNo: 'BAT-00000$index',
          supplierLotNo: 'LOT-$index',
          manufacturingDate: blankItemDates ? null : DateTime(2026, 9, index),
          expiryDate: blankItemDates ? null : DateTime(2028, 4, index),
        ),
    ],
  );
}

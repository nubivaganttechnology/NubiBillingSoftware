import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/utils/stock_quantity_formatter.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/presentation/products/barcode_printing_page.dart';

ProductVariantModel _variant(
  String id, {
  String? barcode,
  int mrp = 85000,
  int sellingPrice = 80000,
  String status = 'ACTIVE',
}) => ProductVariantModel(
  variantId: id,
  businessId: 'BUS-1',
  productId: 'PROD-1',
  name: 'Variant $id',
  baseUnitId: 'UNIT',
  defaultGstRateBps: 1800,
  barcode: barcode ?? id,
  status: status,
  mrp: mrp,
  sellingPrice: sellingPrice,
);

ProductModel _product(
  String id,
  String name,
  List<ProductVariantModel> variants, {
  String status = 'ACTIVE',
}) => ProductModel(
  productId: id,
  tenantId: 'TENANT-1',
  businessId: 'BUS-1',
  name: name,
  status: status,
  createdAt: null,
  updatedAt: null,
  brand: 'Brand $name',
  category: 'Paint',
  variants: variants,
);

Widget _harness({
  required List<ProductModel> products,
  required Set<String> received,
  Map<String, ({int mrp, int sellingPrice})>? pricing,
  Map<String, int> quantities = const {},
}) => MaterialApp(
  home: Scaffold(
    body: BarcodePrintingPage(
      products: products,
      businessName: 'Suman Enterprises',
      loadReceivedVariantIds: () async => received,
      loadReceivedVariantPricing: pricing != null ? () async => pricing : null,
      availableQuantities: quantities,
    ),
  ),
);

void main() {
  test('formats stock balances like the ERP Products table', () {
    expect(formatStockQuantity(76063), '76.063');
    expect(formatStockQuantity(22020), '22.02');
    expect(formatStockQuantity(10000), '10');
  });

  testWidgets(
    'eligible variants load into table; zero or null stock is ineligible and blocked',
    (tester) async {
      final product = _product('PROD-1', 'Decoprime Premium', [
        _variant('VAR-1', barcode: '1'),
        _variant('VAR-2', barcode: '700000000002'),
        _variant('VAR-3', barcode: '700000000003'),
      ]);
      await tester.pumpWidget(
        _harness(
          products: [product],
          received: {'VAR-1', 'VAR-2', 'VAR-3'},
          quantities: {'VAR-1': 76063, 'VAR-2': 0, 'VAR-3': 22020},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Barcode Printing'), findsOneWidget);
      expect(find.text('Decoprime Premium'), findsWidgets);
      // VAR-1 and VAR-3 have stock > 0, so they are ready to print
      expect(find.text('Ready to print'), findsNWidgets(2));
      expect(find.text('76.063'), findsOneWidget);
      expect(find.text('22.02'), findsOneWidget);
      // VAR-2 has zero stock, so by default it is hidden
      expect(find.text('700000000002'), findsNothing);

      // When "Show ineligible" is turned on, VAR-2 appears with No stock available and disabled checkbox
      await tester.tap(find.text('Show ineligible'));
      await tester.pumpAndSettle();
      expect(find.text('700000000002'), findsOneWidget);
      expect(find.text('No stock available'), findsOneWidget);
      final checkbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('select-VAR-2')),
      );
      expect(checkbox.onChanged, isNull);
    },
  );

  testWidgets(
    'inactive product or variant is ineligible and blocked from barcode printing',
    (tester) async {
      final activeProduct = _product('PROD-1', 'Active Paint', [
        _variant('VAR-ACTIVE', barcode: '101', status: 'ACTIVE'),
        _variant('VAR-INACTIVE', barcode: '102', status: 'INACTIVE'),
      ]);
      final inactiveProduct = _product(
        'PROD-2',
        'Discontinued Paint',
        [_variant('VAR-DISC', barcode: '103', status: 'ACTIVE')],
        status: 'INACTIVE',
      );

      await tester.pumpWidget(
        _harness(
          products: [activeProduct, inactiveProduct],
          received: {'VAR-ACTIVE', 'VAR-INACTIVE', 'VAR-DISC'},
          quantities: {
            'VAR-ACTIVE': 15000,
            'VAR-INACTIVE': 15000,
            'VAR-DISC': 15000,
          },
        ),
      );
      await tester.pumpAndSettle();

      // Only the active variant of the active product is visible by default
      expect(find.text('Active Paint'), findsWidgets);
      expect(find.text('Discontinued Paint'), findsNothing);
      expect(find.text('Variant VAR-ACTIVE'), findsOneWidget);
      expect(find.text('Variant VAR-INACTIVE'), findsNothing);
      expect(find.text('Ready to print'), findsOneWidget);

      // Show ineligible rows to inspect inactive items
      await tester.tap(find.text('Show ineligible'));
      await tester.pumpAndSettle();

      expect(find.text('Product is inactive'), findsOneWidget);
      expect(find.text('Variant is inactive'), findsOneWidget);

      final inactiveProductCheckbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('select-VAR-DISC')),
      );
      expect(inactiveProductCheckbox.onChanged, isNull);

      final inactiveVariantCheckbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('select-VAR-INACTIVE')),
      );
      expect(inactiveVariantCheckbox.onChanged, isNull);
    },
  );

  testWidgets(
    'never received rows stay hidden by default and are disabled when shown',
    (tester) async {
      final product = _product('PROD-1', 'Decoprime Premium', [
        _variant('VAR-RECEIVED', barcode: '101'),
        _variant('VAR-NEW', barcode: '102'),
      ]);
      await tester.pumpWidget(
        _harness(
          products: [product],
          received: {'VAR-RECEIVED'},
          quantities: {'VAR-RECEIVED': 10000, 'VAR-NEW': 10000},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Variant VAR-RECEIVED'), findsOneWidget);
      expect(find.text('Variant VAR-NEW'), findsNothing);
      await tester.tap(find.text('Show ineligible'));
      await tester.pumpAndSettle();
      expect(find.text('Not received'), findsOneWidget);
      final checkbox = tester.widget<Checkbox>(
        find.byKey(const ValueKey('select-VAR-NEW')),
      );
      expect(checkbox.onChanged, isNull);
    },
  );

  testWidgets(
    'search filters locally and global copies apply to selected rows',
    (tester) async {
      final first = _product('PROD-1', 'Decoprime Premium', [
        _variant('VAR-1', barcode: '700000000001'),
        _variant('VAR-2', barcode: '700000000002'),
      ]);
      final second = _product('PROD-2', 'Fairy Dust', [
        _variant('VAR-3', barcode: '700000000003'),
      ]);
      await tester.pumpWidget(
        _harness(
          products: [first, second],
          received: {'VAR-1', 'VAR-2', 'VAR-3'},
          quantities: {
            'VAR-1': 20000,
            'VAR-2': 20000,
            'VAR-3': 20000,
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Decoprime');
      await tester.pumpAndSettle();
      expect(find.text('Decoprime Premium'), findsWidgets);
      expect(find.text('Fairy Dust'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('select-VAR-1')));
      await tester.tap(find.byKey(const ValueKey('select-VAR-2')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('copies-VAR-1')),
          matching: find.byType(EditableText),
        ),
        '5',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('copies-VAR-2')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '1',
      );
      await tester.enterText(find.byType(TextField).at(1), '4');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('copies-VAR-1')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '4',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('copies-VAR-2')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '4',
      );
      expect(find.text('2 selected'), findsWidgets);
    },
  );

  testWidgets(
    'per-row copies are independent and enabled zero price is blocked',
    (tester) async {
      final product = _product('PROD-1', 'Decoprime Premium', [
        _variant('VAR-1', barcode: '1', mrp: 0),
        _variant('VAR-2', barcode: '2'),
      ]);
      await tester.pumpWidget(
        _harness(
          products: [product],
          received: {'VAR-1', 'VAR-2'},
          quantities: {'VAR-1': 10000, 'VAR-2': 10000},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Incomplete · MRP unavailable'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('select-VAR-1')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview Selected'));
      await tester.pumpAndSettle();
      expect(find.textContaining('MRP unavailable'), findsWidgets);
      expect(find.textContaining('Label preview'), findsNothing);
    },
  );

  testWidgets(
    'resolves MRP and selling price from received batch pricing when variant price is 0',
    (tester) async {
      final product = _product('PROD-1', 'Sigmark HMRM', [
        _variant('VAR-SIG', barcode: '700000000003', mrp: 0, sellingPrice: 0),
      ]);
      await tester.pumpWidget(
        _harness(
          products: [product],
          received: {'VAR-SIG'},
          pricing: {'VAR-SIG': (mrp: 81200, sellingPrice: 74900)},
          quantities: {'VAR-SIG': 21000},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready to print'), findsOneWidget);
      expect(find.text('INR 812.00'), findsOneWidget);
      expect(find.text('INR 749.00'), findsOneWidget);
      expect(find.text('Incomplete · MRP unavailable'), findsNothing);

      // Verify row is selectable and preview shows the resolved MRP
      await tester.tap(find.byKey(const ValueKey('select-VAR-SIG')));
      await tester.pumpAndSettle();
      expect(find.text('Preview unavailable · MRP unavailable'), findsNothing);
      expect(find.textContaining('MRP INR 812.00'), findsWidgets);
    },
  );
}

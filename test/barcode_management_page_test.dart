import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/core/permissions/permission_catalog.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/presentation/products/barcode_management_page.dart';

void main() {
  test('Barcode is visible to product readers as a separate module', () {
    final modules = PermissionCatalog.visibleModules(['product.read']);
    expect(modules.any((module) => module.id == 'barcode'), isTrue);
  });

  testWidgets('lookup resolves legacy barcode from local variants', (
    tester,
  ) async {
    final variant = ProductVariantModel(
      variantId: 'VAR-1',
      businessId: 'BUS-1',
      productId: 'PROD-1',
      name: '20 Litre Bucket',
      baseUnitId: 'UNIT',
      defaultGstRateBps: 1800,
      barcode: '1',
      mrp: 85000,
      sellingPrice: 80000,
    );
    final product = ProductModel(
      productId: 'PROD-1',
      tenantId: 'TENANT-1',
      businessId: 'BUS-1',
      name: 'Decoprime Premium',
      status: 'ACTIVE',
      createdAt: null,
      updatedAt: null,
      variants: [variant],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeManagementPage(
            products: [product],
            businessName: 'Suman Enterprises',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Barcode Lookup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1');
    await tester.pumpAndSettle();

    expect(find.text('Decoprime Premium'), findsOneWidget);
    expect(find.textContaining('Barcode 1'), findsOneWidget);
  });

  testWidgets('separate module exposes printing and lookup tabs', (
    tester,
  ) async {
    final product = ProductModel(
      productId: 'PROD-1',
      tenantId: 'TENANT-1',
      businessId: 'BUS-1',
      name: 'Local Product',
      status: 'ACTIVE',
      createdAt: null,
      updatedAt: null,
      variants: [
        ProductVariantModel(
          variantId: 'VAR-1',
          businessId: 'BUS-1',
          productId: 'PROD-1',
          name: '12 Litre',
          baseUnitId: 'UNIT',
          defaultGstRateBps: 1800,
          barcode: '1',
          mrp: 10000,
          sellingPrice: 9000,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeManagementPage(
            products: [product],
            businessName: 'Suman Enterprises',
            loadReceivedVariantIds: () async => {'VAR-1'},
            availableQuantities: const {'VAR-1': 1000},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barcode Printing'), findsWidgets);
    expect(find.text('Barcode Lookup'), findsOneWidget);
    expect(find.text('Local Product'), findsOneWidget);
  });
}

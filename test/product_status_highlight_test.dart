import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/domain/entities/app_context.dart';
import 'package:testflutter/presentation/products/product_pages.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'dashboard_navigation_test.dart' show NavigationController;

class _StatusTestController extends NavigationController {
  _StatusTestController(this.testProducts) : super(showOverview: true);

  final List<ProductModel> testProducts;

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
  List<ProductModel> get products => testProducts;

  @override
  OutletModel? get currentOutlet => const OutletModel(
    outletId: 'outlet',
    businessId: 'business',
    ownerUid: 'owner',
    tenantId: 'owner',
    outletName: 'Main Outlet',
    outletTypeId: 'shop',
    outletTypeName: 'Shop',
    isActive: true,
  );

  @override
  bool canViewProducts() => true;
  @override
  bool canCreateProducts() => true;
  @override
  bool canUpdateProducts() => true;
  @override
  bool canDeleteProducts() => true;
}

void main() {
  testWidgets(
    'Active products are highlighted green and inactive products are highlighted red',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final activeProduct = ProductModel(
        productId: 'P-ACTIVE',
        tenantId: 'owner',
        businessId: 'business',
        name: 'Active Paint Can',
        status: 'ACTIVE',
        createdAt: now,
        updatedAt: now,
        variants: [
          const ProductVariantModel(
            variantId: 'V-ACTIVE',
            businessId: 'business',
            name: '1L Can',
            baseUnitId: 'u1',
            defaultGstRateBps: 1800,
            status: 'ACTIVE',
          ),
        ],
      );

      final inactiveProduct = ProductModel(
        productId: 'P-INACTIVE',
        tenantId: 'owner',
        businessId: 'business',
        name: 'Inactive Paint Can',
        status: 'INACTIVE',
        createdAt: now,
        updatedAt: now,
        variants: [
          const ProductVariantModel(
            variantId: 'V-INACTIVE',
            businessId: 'business',
            name: '500ml Can',
            baseUnitId: 'u1',
            defaultGstRateBps: 1800,
            status: 'INACTIVE',
          ),
        ],
      );

      final controller = _StatusTestController([activeProduct, inactiveProduct]);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ProductManagementPage(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the "Active" status text
      final activeTextFinder = find.text('Active');
      expect(activeTextFinder, findsAtLeastNWidgets(1));

      // Find the "Inactive" status text
      final inactiveTextFinder = find.text('Inactive');
      expect(inactiveTextFinder, findsAtLeastNWidgets(1));

      // Verify the decoration color of the active badge container
      final containers = tester.widgetList<Container>(find.byType(Container));
      final greenContainer = containers.firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == Colors.green.shade100,
      );
      expect(greenContainer, isNotNull);

      // Verify the decoration color of the inactive badge container
      final redContainer = containers.firstWhere(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == Colors.red.shade100,
      );
      expect(redContainer, isNotNull);

      // Verify active text style color inside the green badge
      final activeBadgeText = find.descendant(
        of: find.byWidget(greenContainer),
        matching: find.text('Active'),
      );
      expect(activeBadgeText, findsOneWidget);
      expect(
        tester.widget<Text>(activeBadgeText).style?.color,
        equals(Colors.green.shade900),
      );

      // Verify inactive text style color inside the red badge
      final inactiveBadgeText = find.descendant(
        of: find.byWidget(redContainer),
        matching: find.text('Inactive'),
      );
      expect(inactiveBadgeText, findsOneWidget);
      expect(
        tester.widget<Text>(inactiveBadgeText).style?.color,
        equals(Colors.red.shade900),
      );

      // Expand both products to reveal variant tables
      final expandButtons = find.byIcon(Icons.expand_more);
      expect(expandButtons, findsNWidgets(2));
      for (final btn in expandButtons.evaluate().toList()) {
        await tester.tap(find.byWidget(btn.widget));
      }
      await tester.pumpAndSettle();

      // Verify variant status badges also have green and red highlight
      final allContainers = tester.widgetList<Container>(find.byType(Container));
      final greenVariantContainers = allContainers.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == Colors.green.shade100,
      );
      expect(greenVariantContainers.length, greaterThanOrEqualTo(2));

      final redVariantContainers = allContainers.where(
        (c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == Colors.red.shade100,
      );
      expect(redVariantContainers.length, greaterThanOrEqualTo(2));
    },
  );
}

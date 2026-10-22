import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:testflutter/theme/app_theme.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/models/product_attribute.dart';
import 'package:testflutter/data/models/central_product_master.dart';
import 'package:testflutter/data/models/product_master_value.dart';
import 'package:testflutter/data/models/product_model.dart';
import 'package:testflutter/data/models/business_model.dart';
import 'package:testflutter/data/models/employee_model.dart';
import 'package:testflutter/data/models/outlet_model.dart';
import 'package:testflutter/data/models/product_variant_model.dart';
import 'package:testflutter/data/models/reclassification_plan.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/presentation/app_controller.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

class EntryController extends ChangeNotifier implements AppController {
  @override
  Locale get currentLocale => const Locale('en');
  @override
  Future<void> setLocale(Locale locale) async {}
  @override
  OutletModel? get currentOutlet => null;
  @override
  BusinessModel? get currentBusiness => null;
  @override
  String get currentBusinessName => 'Suman Enterprise';
  @override
  int get pendingAttendanceCount => 0;
  @override
  bool canViewStaffAttendance() => false;
  @override
  bool canViewStaffSalary() => false;
  @override
  bool canChargeStaffKhata() => false;
  @override
  Future<List<EmployeeModel>> loadStaffKhataEmployees() async => const [];
  @override
  Map<String, int> get productStock => const {};
  @override
  String get productsScopeLabel => 'Products placed at this outlet';
  @override
  bool get canAddExistingProductsToOutlet => false;
  @override
  String? get placementBackfillNotice => null;
  @override
  final products = <ProductModel>[];
  @override
  final productMasterValues = <String, List<ProductMasterValue>>{
    'BRAND': [
      const ProductMasterValue(id: 'BR', name: 'Berger', status: 'ACTIVE'),
    ],
    'CATEGORY': [
      const ProductMasterValue(id: 'CA', name: 'Accessories', status: 'ACTIVE'),
    ],
    'SUBCATEGORY:CA': [
      const ProductMasterValue(
        id: 'SU',
        name: 'Brush',
        status: 'ACTIVE',
        categoryId: 'CA',
      ),
    ],
    'UNIT': [
      const ProductMasterValue(
        id: 'SYS_UNIT_PIECE',
        name: 'Piece',
        status: 'ACTIVE',
      ),
      const ProductMasterValue(
        id: 'SYS_UNIT_INCH',
        name: 'inch',
        status: 'ACTIVE',
        measurementDimension: 'LENGTH',
      ),
      const ProductMasterValue(
        id: 'MM',
        name: 'mm',
        status: 'ACTIVE',
        measurementDimension: 'LENGTH',
      ),
      const ProductMasterValue(
        id: 'CM',
        name: 'cm',
        status: 'ACTIVE',
        measurementDimension: 'LENGTH',
      ),
    ],
  };
  final templates = <String, List<ProductAttribute>>{};
  final pendingTemplateResolutions =
      <String, Completer<ResolvedProductTemplate>>{};
  final templateResolutionErrors = <String, Object>{};
  final unitContracts = <String, ResolvedUnitRule>{};
  final centralProductResults = <CentralProductMaster>[];
  final centralProductQueries = <String>[];
  Object? centralProductSearchError;
  int productMasterLoadCount = 0;
  Map<String, dynamic>? savedFields;
  List<Map<String, dynamic>>? savedVariants;
  @override
  bool get productsLoading => false;
  @override
  bool get productSaving => false;
  @override
  String? get productsError => null;
  @override
  String? get productMastersError => null;
  @override
  SyncEngine? get sync => null;
  @override
  bool canManageProducts() => true;
  @override
  bool canCreateProducts() => true;
  @override
  bool canCreateProductMasters() => false;
  @override
  Future<void> loadProducts() async {}
  @override
  Future<void> loadProductMasters({String? categoryId}) async {
    productMasterLoadCount++;
  }

  @override
  Future<List<CentralProductMaster>> searchCentralProductMaster(
    String query,
  ) async {
    centralProductQueries.add(query);
    if (centralProductSearchError != null) throw centralProductSearchError!;
    return centralProductResults;
  }

  @override
  Future<List<ProductAttribute>> loadProductTemplate(
    String subcategoryId,
  ) async =>
      templates[subcategoryId] ??
      const [
        ProductAttribute(
          id: 'brushType',
          name: 'Brush Type',
          dataType: 'SELECT',
          options: ['Flat'],
          defaultValue: 'Flat',
        ),
        ProductAttribute(
          id: 'brushSize',
          name: 'Brush Size',
          dataType: 'NUMBER',
          level: 'VARIANT',
          required: true,
          measurementUnitAttributeId: 'brushSizeUnit',
          measurementDimension: 'LENGTH',
          exampleValue: 2,
        ),
        ProductAttribute(
          id: 'brushSizeUnit',
          name: 'Size unit',
          dataType: 'SELECT',
          level: 'VARIANT',
          options: ['inch', 'mm', 'cm', 'Piece'],
          defaultValue: 'inch',
        ),
        ProductAttribute(id: 'hsnCode', name: 'HSN Code'),
      ];
  @override
  Future<ResolvedProductTemplate> resolveProductTemplate(
    String subcategoryId,
  ) async {
    final pending = pendingTemplateResolutions[subcategoryId];
    if (pending != null) return pending.future;
    final error = templateResolutionErrors[subcategoryId];
    if (error != null) throw error;
    final legacyAttrs = await loadProductTemplate(subcategoryId);
    return ResolvedProductTemplate(
      categoryId: 'CA',
      subcategoryId: subcategoryId,
      categoryName: 'Accessories',
      subcategoryName: 'Brush',
      readiness: legacyAttrs.isEmpty
          ? TemplateReadinessState.missingTemplate
          : TemplateReadinessState.ready,
      productAttributes: legacyAttrs
          .where((a) => a.level != 'VARIANT')
          .map(
            (a) => ResolvedTemplateAttribute(
              attributeId: a.id,
              displayName: a.name,
              level: AttributeLevel.product,
              dataType: a.dataType,
              required: a.required,
              defaultValue: a.defaultValue,
              options: a.options
                  .map((o) => ResolvedAttributeOption(id: o, name: o))
                  .toList(),
              allowAddNewOption: a.allowAddNewOption,
              hint: a.hintText,
              exampleValue: a.exampleValue,
              technical: a.section == 'TECHNICAL',
              sortOrder: a.sortOrder,
              section: a.section,
              semanticRole: a.semanticRole,
              measurementDimension: a.measurementDimension,
              measurementUnitAttributeId: a.measurementUnitAttributeId,
              minimumExclusive: a.minimumExclusive,
              defaultRules: a.defaultRules,
              visibleWhen: a.visibleWhen,
              requiredWhen: a.requiredWhen,
            ),
          )
          .toList(),
      variantAttributes: legacyAttrs
          .where((a) => a.level == 'VARIANT')
          .map(
            (a) => ResolvedTemplateAttribute(
              attributeId: a.id,
              displayName: a.name,
              level: AttributeLevel.variant,
              dataType: a.dataType,
              required: a.required,
              defaultValue: a.defaultValue,
              options: a.options
                  .map((o) => ResolvedAttributeOption(id: o, name: o))
                  .toList(),
              allowAddNewOption: a.allowAddNewOption,
              hint: a.hintText,
              exampleValue: a.exampleValue,
              technical: a.section == 'TECHNICAL',
              sortOrder: a.sortOrder,
              section: a.section,
              semanticRole: a.semanticRole,
              measurementDimension: a.measurementDimension,
              measurementUnitAttributeId: a.measurementUnitAttributeId,
              minimumExclusive: a.minimumExclusive,
              defaultRules: a.defaultRules,
              visibleWhen: a.visibleWhen,
              requiredWhen: a.requiredWhen,
            ),
          )
          .toList(),
      technicalAttributes: const [],
      unitRules:
          unitContracts[subcategoryId] ??
          ResolvedUnitRule(
            allowedPackUnits:
                legacyAttrs.where((a) => a.id == 'unit').firstOrNull?.options ??
                const ['Piece'],
            defaultPackUnit:
                legacyAttrs
                        .where((a) => a.id == 'unit')
                        .firstOrNull
                        ?.defaultValue
                    as String? ??
                'Piece',
            allowedSellingUnits:
                legacyAttrs
                    .where((a) => a.id == 'soldAs')
                    .firstOrNull
                    ?.options ??
                legacyAttrs.where((a) => a.id == 'unit').firstOrNull?.options ??
                const ['Piece'],
            defaultSellingUnit:
                legacyAttrs
                        .where((a) => a.id == 'soldAs')
                        .firstOrNull
                        ?.defaultValue
                    as String? ??
                legacyAttrs
                        .where((a) => a.id == 'unit')
                        .firstOrNull
                        ?.defaultValue
                    as String? ??
                'Piece',
            unitAliases: {
              for (final u
                  in productMasterValues['UNIT'] ?? <ProductMasterValue>[])
                u.id.toLowerCase(): u.name,
            },
          ),
    );
  }

  @override
  Future<bool> createStructuredProduct({
    required String name,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    savedFields = productFields;
    savedVariants = variants;
    return true;
  }

  @override
  bool canUpdateProducts() => true;
  @override
  bool canDeleteProducts() => false;
  @override
  bool canViewStorage() => false;
  @override
  Future<ReclassificationPlan?> computeReclassificationPlan({
    required String productId,
    required String newCategoryId,
    required String newSubcategoryId,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    return ReclassificationPlan(
      classificationChanged: false,
      newCategoryId: newCategoryId,
      newSubcategoryId: newSubcategoryId,
      preservedVariantIds: variants
          .map((v) => v['variantId'] as String?)
          .whereType<String>()
          .toList(),
      updatedVariantIds: [],
      newVariantCount: 0,
      retiredVariantIds: [],
    );
  }

  @override
  Future<bool> saveStructuredProductEdit({
    required String productId,
    required String name,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    savedFields = productFields;
    savedVariants = variants;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TableController extends EntryController {
  @override
  bool canViewStorage() => true;
  @override
  Map<String, int> get productStock => {'V2': 1000, 'V4': 2000, 'V5': 0};
}

class RefreshingMasterController extends EntryController {
  @override
  Future<void> loadProductMasters({String? categoryId}) async {
    if (categoryId == null) return;
    productMasterValues['BRAND'] = const [
      ProductMasterValue(id: 'NEW', name: 'New brand', status: 'ACTIVE'),
    ];
  }

  @override
  bool canCreateProductMasters() => true;

  @override
  Future<ProductMasterValue?> createProductMaster({
    required String masterType,
    required String name,
    String? categoryId,
    String? code,
    List<String> applicableAttributes = const [],
  }) async => ProductMasterValue(id: 'CREATED', name: name, status: 'ACTIVE');
}

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

const _interiorDampnessSubcategoryId =
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_INTERIOR_DAMPNESS_TREATMENT';

const _dampProofTemplate = [
  ProductAttribute(
    id: 'usage',
    name: 'Usage',
    dataType: 'SELECT',
    options: ['Interior'],
    defaultValue: 'Interior',
  ),
  ProductAttribute(
    id: 'surface',
    name: 'Surface',
    dataType: 'SELECT',
    options: ['Concrete'],
    defaultValue: 'Concrete',
  ),
  ProductAttribute(
    id: 'brushSize',
    name: 'Brush Size',
    dataType: 'NUMBER',
    level: 'VARIANT',
    required: true,
    measurementUnitAttributeId: 'brushSizeUnit',
    measurementDimension: 'LENGTH',
    exampleValue: 2,
  ),
  ProductAttribute(
    id: 'brushSizeUnit',
    name: 'Size unit',
    dataType: 'SELECT',
    level: 'VARIANT',
    options: ['inch', 'mm', 'cm', 'Piece'],
    defaultValue: 'inch',
  ),
];

CentralProductMaster _centralProduct({
  required String id,
  required String name,
  required String categoryId,
  required String categoryName,
  required String subcategoryId,
  required String subcategoryName,
}) => CentralProductMaster(
  masterProductId: id,
  productName: name,
  normalizedProductName: name.toLowerCase(),
  businessTypeId: 'BT-HARDWARE',
  businessTypeName: 'Hardware',
  businessSubTypeId: 'BST-PAINTS',
  businessSubTypeName: 'Paints',
  brandId: 'SYS_BRAND_ASIAN_PAINTS',
  brandName: 'Asian Paints',
  categoryId: categoryId,
  categoryName: categoryName,
  subcategoryId: subcategoryId,
  subcategoryName: subcategoryName,
  searchTokens: name.toLowerCase().split(' '),
  isActive: true,
  status: 'ACTIVE',
  scopeType: 'SYSTEM',
);

Finder _dropdownField(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownMenu<String> &&
      widget.label is Text &&
      (widget.label as Text).data?.replaceAll(' *', '') == label,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy BUS-001 central autocomplete uses its canonical catalogue scope',
    () {
      expect(
        resolveCentralProductSearchScope(
          businessId: 'BUS-001',
          businessTypeId: 'Hardware',
          businessSubTypeId: 'Hardware Outlet',
        ),
        (businessTypeId: 'BT-HARDWARE', businessSubTypeId: 'BST-PAINTS'),
      );
      expect(
        resolveCentralProductSearchScope(
          businessId: 'OTHER',
          businessTypeId: 'BT-HARDWARE',
          businessSubTypeId: 'BST-CONSTRUCTION-HARDWARE',
        ),
        (
          businessTypeId: 'BT-HARDWARE',
          businessSubTypeId: 'BST-CONSTRUCTION-HARDWARE',
        ),
      );
    },
  );
  testWidgets(
    'catalogue refresh clears picker text without rebuilding during layout',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RefreshingMasterController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Brand / Company'), 'draft search');
      await tester.enterText(field('Category'), 'Accessories');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accessories').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(field('Brand / Company')).controller!.text,
        '',
      );
      expect(
        tester.widget<TextField>(field('Category')).controller!.text,
        'Accessories',
      );
      await tester.enterText(field('Brand / Company'), 'new search');
      await tester.enterText(field('Category'), 'other category');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Category')).controller!.text,
        'other category',
      );
      expect(
        tester.widget<TextField>(field('Brand / Company')).controller!.text,
        'new search',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adding a master selects its name without rebuilding during layout',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = RefreshingMasterController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add Brand / Company'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Brand / Company name'), 'Created brand');
      await tester.tap(find.text('Save & Select'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(field('Brand / Company')).controller!.text,
        'Created brand',
      );
    },
  );
  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets(
      'product table stock and variant details remain readable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = TableController();
        addTearDown(controller.dispose);
        controller.products.add(
          ProductModel(
            productId: 'P',
            tenantId: 'T',
            businessId: 'B',
            name: 'Professional Paint Brush',
            productCode: 'PRD-0004',
            status: 'ACTIVE',
            createdAt: null,
            updatedAt: null,
            brandId: 'BR',
            categoryId: 'CA',
            syncStatus: 'PENDING_CREATE',
            variants: [
              for (final size in [2, 4, 5])
                ProductVariantModel(
                  variantId: 'V$size',
                  businessId: 'B',
                  name: '$size inch',
                  sku: 'SKU-$size',
                  baseUnitId: 'SYS_UNIT_PIECE',
                  defaultGstRateBps: 0,
                ),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ProductManagementPage(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Pending'), findsOneWidget);
        if (width == 768) expect(find.text('Berger'), findsNothing);
        expect(find.text(width < 700 ? 'Stock 3' : '3'), findsWidgets);
        if (width == 768) {
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(-220, 0),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byIcon(Icons.expand_more).last);
        await tester.pumpAndSettle();
        expect(find.text('2 inch'), findsOneWidget);
        expect(find.textContaining('SYS_UNIT_PIECE'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Product KPIs remain business-wide when search and status hide table rows',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TableController();
      addTearDown(controller.dispose);
      for (final entry in {
        'Professional Paint Brush': 3,
        'Sharlimar_paint_001': 1,
      }.entries) {
        controller.products.add(
          ProductModel(
            productId: entry.key,
            tenantId: 'T',
            businessId: 'B',
            name: entry.key,
            status: 'ACTIVE',
            createdAt: null,
            updatedAt: null,
            syncStatus: entry.value == 3 ? 'PENDING_CREATE' : 'SYNCED',
            variants: [
              for (var i = 0; i < entry.value; i++)
                ProductVariantModel(
                  variantId: '${entry.key}-$i',
                  businessId: 'B',
                  name: '$i',
                  baseUnitId: 'SYS_UNIT_PIECE',
                  defaultGstRateBps: 0,
                ),
            ],
          ),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      void expectKpis() {
        for (final entry in {
          'Products': '2',
          'Variants': '4',
          'Active': '2',
        }.entries) {
          final card = find
              .ancestor(of: find.text(entry.key), matching: find.byType(Card))
              .first;
          expect(
            find.descendant(of: card, matching: find.text(entry.value)),
            findsOneWidget,
          );
        }
      }

      expectKpis();
      await tester.enterText(
        find.byType(TextField).first,
        'no matching products',
      );
      await tester.pumpAndSettle();
      expect(find.text('No Products match your search.'), findsOneWidget);
      expectKpis();
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Status',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inactive').last);
      await tester.pumpAndSettle();
      expect(find.text('No Products match your search.'), findsOneWidget);
      expectKpis();
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    // Use fonts from the installed Flutter SDK for legible preview artifacts.
    var folder = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 9; i++) {
      final fonts = Directory(
        '${folder.path}/bin/cache/artifacts/material_fonts',
      );
      if (await fonts.exists()) {
        for (final entry in {
          'Roboto': 'Roboto-Regular.ttf',
          'MaterialIcons': 'MaterialIcons-Regular.otf',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  await File('${fonts.path}/${entry.value}').readAsBytes(),
                ),
              ),
            );
          await loader.load();
        }
        break;
      }
      folder = folder.parent;
    }
  });
  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets(
      'premium product layout has no overflow at $width and separates unit choices',
      (tester) async {
        tester.view.physicalSize = Size(width, width >= 1200 ? 1900 : 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = EntryController();
        addTearDown(controller.dispose);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light.copyWith(
                textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Roboto'),
              ),
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => showQuickProductDialog(ctx, controller),
                      child: const Text('Open form'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();
        Future<void> pick(String label, String name) async {
          await tester.ensureVisible(field(label));
          await tester.enterText(field(label), name);
          await tester.pumpAndSettle();
          await tester.tap(find.text(name).last);
          await tester.pumpAndSettle();
        }

        await tester.enterText(
          field('Product Name *'),
          'Professional Paint Brush',
        );
        await pick('Brand / Company', 'Berger');
        await pick('Category', 'Accessories');
        await pick('Subcategory', 'Brush');
        final brand = tester.getTopLeft(field('Brand / Company'));
        final category = tester.getTopLeft(field('Category'));
        if (width >= 768) {
          expect((brand.dy - category.dy).abs(), lessThan(1));
          expect(category.dx, greaterThan(brand.dx));
        } else {
          expect(category.dy, greaterThan(brand.dy));
        }
        expect(
          tester.getSize(field('Product Name *')).height,
          greaterThanOrEqualTo(56),
        );
        if (field('Brush Size *').evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            field('Brush Size *'),
            300,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
        }
        await tester.ensureVisible(field('Brush Size *'));
        await tester.enterText(field('Brush Size *'), '2');
        final sizeDropdown = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == 'Size unit',
        );
        final options = tester
            .widget<DropdownButton<String>>(
              find.descendant(
                of: sizeDropdown,
                matching: find.byType(DropdownButton<String>),
              ),
            )
            .items!
            .map((v) => v.value)
            .toList();
        expect(options, ['inch', 'mm', 'cm']);
        expect(options, isNot(contains('Piece')));
        await pick('Sold As *', 'Piece');
        if (find.text('No product image').evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            find.text('No product image'),
            300,
            scrollable: find
                .descendant(
                  of: find.byType(ListView).last,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
        }
        expect(find.text('No product image'), findsOneWidget);
        if (width >= 1200 || width == 390) {
          if (width >= 1200) {
            await tester.drag(
              find.byType(ListView).last,
              const Offset(0, 10000),
            );
          } else {
            await tester.drag(find.byType(ListView).last, const Offset(0, 600));
            await tester.pumpAndSettle();
            if (field('Brush Size *').evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                field('Brush Size *'),
                -200,
                scrollable: find
                    .descendant(
                      of: find.byType(ListView).last,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
            }
            if (find.text('Variant 1').evaluate().isEmpty) {
              await tester.scrollUntilVisible(
                find.text('Variant 1'),
                -150,
                scrollable: find
                    .descendant(
                      of: find.byType(ListView).last,
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
            }
            await Scrollable.ensureVisible(
              tester.element(find.text('Variant 1')),
              alignment: 0.05,
            );
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/nubibill-product-${width >= 1200 ? 'desktop' : 'mobile'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Save Product'));
        await tester.pumpAndSettle();
        expect(
          controller.savedVariants!.single['commercialUnitId'],
          'SYS_UNIT_PIECE',
        );
        expect(
          (controller.savedVariants!.single['attributeValues']
              as Map)['brushSizeUnit'],
          'inch',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Edit opens the same dynamic form and preserves untouched variants and clears inapplicable attributes',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = EntryController();
      addTearDown(c.dispose);
      c.products.add(
        ProductModel(
          productId: 'P',
          tenantId: 'T',
          businessId: 'B',
          name: 'Brush',
          status: 'ACTIVE',
          createdAt: null,
          updatedAt: null,
          brandId: 'BR',
          categoryId: 'CA',
          subcategoryId: 'SU',
          hsnCode: '960340',
          productImage: 'https://example.com/brush.png',
          attributeValues: const {'brushType': 'Flat', 'hidden': 'preserve'},
          variants: [
            for (final size in [1, 4])
              ProductVariantModel(
                variantId: 'V$size',
                businessId: 'B',
                name: 'Brush $size',
                baseUnitId: 'SYS_UNIT_PIECE',
                commercialUnitId: 'SYS_UNIT_PIECE',
                defaultGstRateBps: 1800,
                sku: 'SKU-$size',
                attributeValues: {
                  'brushSize': size,
                  'brushSizeUnit': 'inch',
                  'hiddenVariant': 'keep-$size',
                },
              ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Product / Manage Variants'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Product'), findsOneWidget);
      expect(find.text('Configure for this Business'), findsNothing);
      expect(field('HSN Code'), findsNothing);
      expect(
        tester.widget<TextField>(field('HSN / SAC')).controller!.text,
        '960340',
      );
      expect(field('Brush Size *'), findsNWidgets(2));
      expect(
        tester.widget<TextField>(field('Brush Size *').last).controller!.text,
        '4',
      );
      await tester.enterText(field('Brush Size *').first, '2');
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      expect(c.savedFields!['imageUrl'], 'https://example.com/brush.png');
      expect(
        (c.savedFields!['attributeValues'] as Map).containsKey('hidden'),
        isFalse,
      );
      expect(c.savedVariants!.map((v) => v['variantId']), ['V1', 'V4']);
      expect(
        (c.savedVariants!.first['attributeValues'] as Map)['brushSize'],
        2,
      );
      expect((c.savedVariants!.last['attributeValues'] as Map)['brushSize'], 4);
      expect(
        (c.savedVariants!.last['attributeValues'] as Map)['hiddenVariant'],
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'shop entry pairs measurements and saves selling units independently with one HSN',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      Future<void> pick(String label, String name) async {
        await tester.enterText(field(label), name);
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await tester.enterText(field('Product Name *'), 'Professional Brush');
      await pick('Brand / Company', 'Berger');
      await pick('Category', 'Accessories');
      await pick('Subcategory', 'Brush');
      expect(find.text('Configure for this Business'), findsNothing);
      expect(find.text('Add Business Attribute'), findsNothing);
      expect(field('HSN / SAC'), findsOneWidget);
      expect(field('HSN Code'), findsNothing);
      await tester.enterText(field('HSN / SAC'), '960340');
      await tester.enterText(field('Brush Size *'), '2');
      expect(field('Selling price'), findsNothing);
      expect(field('Purchase rate'), findsNothing);
      expect(field('MRP'), findsNothing);
      expect(field('Variant GST (%)'), findsNothing);
      expect(find.text('Selling Mode'), findsNothing);
      await pick('Sold As *', 'Piece');
      expect(find.text('Contains *'), findsNothing);
      expect(find.text('SYS_UNIT_PIECE'), findsNothing);
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      final variant = controller.savedVariants!.single;
      expect(variant.containsKey('sellingPrice'), isFalse);
      expect(variant.containsKey('purchaseRate'), isFalse);
      expect(variant.containsKey('mrp'), isFalse);
      expect(variant['defaultGstRateBps'], isNull);
      expect(variant['attributeValues'], {
        'brushSize': 2,
        'brushSizeUnit': 'inch',
      });
      expect(variant['baseUnitId'], 'SYS_UNIT_PIECE');
      expect(variant['commercialUnitId'], 'SYS_UNIT_PIECE');
      expect(variant['baseQuantityPerCommercialUnit'], 1);
      expect(
        (controller.savedFields!['attributeValues'] as Map).containsKey(
          'hsnCode',
        ),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'central product selection fills identity and saves only its master reference',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController()
        ..centralProductResults.add(
          const CentralProductMaster(
            masterProductId: 'MASTER-APEX',
            productName: 'Apex Ultima',
            normalizedProductName: 'apex ultima',
            businessTypeId: 'BT-HARDWARE',
            businessTypeName: 'Hardware',
            businessSubTypeId: 'BST-PAINTS',
            businessSubTypeName: 'Paints',
            brandId: 'BR',
            brandName: 'Berger',
            categoryId: 'CA',
            categoryName: 'Accessories',
            subcategoryId: 'SU',
            subcategoryName: 'Brush',
            searchTokens: ['apex', 'ultima'],
            isActive: true,
            status: 'ACTIVE',
            scopeType: 'SYSTEM',
            packSizes: ['1 L', '4 L'],
            imageUrl: 'https://example.com/central.png',
          ),
        );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();
      final productMasterLoadCount = controller.productMasterLoadCount;

      await tester.enterText(field('Product Name *'), 'Apex Ul');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(controller.centralProductQueries, ['Apex Ul']);
      await tester.tap(find.text('Apex Ultima').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field('Product Name *')).controller!.text,
        'Apex Ultima',
      );
      expect(
        tester.widget<TextField>(field('Brand / Company')).controller!.text,
        'Berger',
      );
      expect(
        tester.widget<TextField>(field('Category')).controller!.text,
        'Accessories',
      );
      expect(
        tester.widget<TextField>(field('Subcategory')).controller!.text,
        'Brush',
      );
      expect(controller.productMasterLoadCount, productMasterLoadCount);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownMenu<String> &&
              widget.label is Text &&
              (widget.label as Text).data == 'Brush Type',
        ),
        findsOneWidget,
      );
      expect(field('Selling price'), findsNothing);
      expect(field('Purchase rate'), findsNothing);
      expect(field('MRP'), findsNothing);
      expect(field('Stock'), findsNothing);

      await tester.enterText(field('Brush Size *'), '2');
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();
      expect(controller.savedFields!['masterProductId'], 'MASTER-APEX');
      expect(controller.savedFields!['brandId'], 'BR');
      expect(controller.savedFields!['categoryId'], 'CA');
      expect(controller.savedFields!['subcategoryId'], 'SU');
      for (final key in [
        'sku',
        'barcode',
        'supplier',
        'purchasePrice',
        'sellingPrice',
        'mrp',
        'openingStock',
        'currentStock',
        'minimumStock',
      ]) {
        expect(controller.savedFields!.containsKey(key), isFalse, reason: key);
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Damp Proof Superflex renders its canonical template and reaches save',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController()
        ..centralProductResults.add(
          _centralProduct(
            id: 'MASTER-DAMP-PROOF-SUPERFLEX',
            name: 'ASIAN PAINTS DAMP PROOF SUPERFLEX',
            categoryId: 'SYS_CATEGORY_WATERPROOFING',
            categoryName: 'Waterproofing',
            subcategoryId: _interiorDampnessSubcategoryId,
            subcategoryName: 'Interior Dampness Treatment',
          ),
        )
        ..templates[_interiorDampnessSubcategoryId] = _dampProofTemplate;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();

      await tester.enterText(
        field('Product Name *'),
        'ASIAN PAINTS DAMP PROOF SUPERFLEX',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(controller.centralProductQueries, [
        'ASIAN PAINTS DAMP PROOF SUPERFLEX',
      ]);
      await tester.tap(find.text('ASIAN PAINTS DAMP PROOF SUPERFLEX').last);
      await tester.pumpAndSettle();

      expect(_dropdownField('Usage'), findsOneWidget);
      expect(_dropdownField('Surface'), findsOneWidget);
      expect(field('Brush Size *'), findsOneWidget);
      expect(
        find.text('Product template unavailable for this subcategory.'),
        findsNothing,
      );
      await tester.enterText(field('Brush Size *'), '2');
      await tester.ensureVisible(field('Sold As *'));
      await tester.enterText(field('Sold As *'), 'Piece');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Piece').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Product'));
      await tester.pumpAndSettle();

      expect(
        controller.savedFields!['subcategoryId'],
        _interiorDampnessSubcategoryId,
      );
      expect(controller.savedFields!['attributeValues'], {
        'usage': 'Interior',
        'surface': 'Concrete',
      });
      expect(
        (controller.savedVariants!.single['attributeValues'] as Map)
            .containsKey('brushSize'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching from Sandpaper to Damp Proof clears old fields and warning',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController()
        ..centralProductResults.addAll([
          _centralProduct(
            id: 'MASTER-SANDPAPER',
            name: 'Sandpaper Product',
            categoryId: 'TOOLS',
            categoryName: 'Painting Tools & Accessories',
            subcategoryId: 'SAND',
            subcategoryName: 'Sandpaper & Abrasives',
          ),
          _centralProduct(
            id: 'MASTER-DAMP-PROOF-SUPERFLEX',
            name: 'ASIAN PAINTS DAMP PROOF SUPERFLEX',
            categoryId: 'SYS_CATEGORY_WATERPROOFING',
            categoryName: 'Waterproofing',
            subcategoryId: _interiorDampnessSubcategoryId,
            subcategoryName: 'Interior Dampness Treatment',
          ),
        ])
        ..templates['SAND'] = const [
          ProductAttribute(
            id: 'grit',
            name: 'Grit',
            dataType: 'SELECT',
            level: 'VARIANT',
            options: ['P80', 'P120'],
            defaultValue: 'P80',
          ),
        ]
        ..templates[_interiorDampnessSubcategoryId] = _dampProofTemplate;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();

      Future<void> selectCentral(String name) async {
        await tester.enterText(field('Product Name *'), name);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await selectCentral('Sandpaper Product');
      expect(_dropdownField('Grit'), findsOneWidget);
      await selectCentral('ASIAN PAINTS DAMP PROOF SUPERFLEX');
      expect(_dropdownField('Grit'), findsNothing);
      expect(_dropdownField('Usage'), findsOneWidget);
      expect(_dropdownField('Surface'), findsOneWidget);
      expect(
        find.text('Product template unavailable for this subcategory.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a stale template failure cannot replace the newer selected product template',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final staleResolution = Completer<ResolvedProductTemplate>();
      final controller = EntryController()
        ..centralProductResults.addAll([
          _centralProduct(
            id: 'MASTER-SANDPAPER',
            name: 'Sandpaper Product',
            categoryId: 'TOOLS',
            categoryName: 'Painting Tools & Accessories',
            subcategoryId: 'SAND',
            subcategoryName: 'Sandpaper & Abrasives',
          ),
          _centralProduct(
            id: 'MASTER-DAMP-PROOF-SUPERFLEX',
            name: 'ASIAN PAINTS DAMP PROOF SUPERFLEX',
            categoryId: 'SYS_CATEGORY_WATERPROOFING',
            categoryName: 'Waterproofing',
            subcategoryId: _interiorDampnessSubcategoryId,
            subcategoryName: 'Interior Dampness Treatment',
          ),
        ])
        ..pendingTemplateResolutions['SAND'] = staleResolution
        ..templates[_interiorDampnessSubcategoryId] = _dampProofTemplate;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Product Name *'), 'Sandpaper Product');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sandpaper Product').last);
      await tester.pump();

      await tester.enterText(
        field('Product Name *'),
        'ASIAN PAINTS DAMP PROOF SUPERFLEX',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.tap(find.text('ASIAN PAINTS DAMP PROOF SUPERFLEX').last);
      await tester.pumpAndSettle();
      staleResolution.completeError(StateError('stale Sandpaper failure'));
      await tester.pumpAndSettle();

      expect(_dropdownField('Usage'), findsOneWidget);
      expect(_dropdownField('Surface'), findsOneWidget);
      expect(_dropdownField('Grit'), findsNothing);
      expect(find.text('Bad state: stale Sandpaper failure'), findsNothing);
      expect(
        find.text('Product template unavailable for this subcategory.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing template blocks save and a later successful retry clears its error',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController()
        ..centralProductResults.addAll([
          _centralProduct(
            id: 'MASTER-NO-TEMPLATE',
            name: 'Missing Template Product',
            categoryId: 'TOOLS',
            categoryName: 'Painting Tools & Accessories',
            subcategoryId: 'NO-TEMPLATE',
            subcategoryName: 'Missing Template',
          ),
          _centralProduct(
            id: 'MASTER-SANDPAPER',
            name: 'Sandpaper Product',
            categoryId: 'TOOLS',
            categoryName: 'Painting Tools & Accessories',
            subcategoryId: 'SAND',
            subcategoryName: 'Sandpaper & Abrasives',
          ),
        ])
        ..templates['NO-TEMPLATE'] = []
        ..templates['SAND'] = const [
          ProductAttribute(
            id: 'grit',
            name: 'Grit',
            dataType: 'SELECT',
            level: 'VARIANT',
            options: ['P80', 'P120'],
            defaultValue: 'P80',
          ),
        ]
        ..templateResolutionErrors['SAND'] = StateError(
          'temporary template resolution failure',
        );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();

      Future<void> selectCentral(String name) async {
        await tester.enterText(field('Product Name *'), name);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await selectCentral('Missing Template Product');
      expect(
        find.text('Product template unavailable for this subcategory.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save Product'),
            )
            .onPressed,
        isNull,
      );
      expect(controller.savedFields, isNull);

      await selectCentral('Sandpaper Product');
      expect(
        find.text('Bad state: temporary template resolution failure'),
        findsOneWidget,
      );
      controller.templateResolutionErrors.remove('SAND');
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('Bad state: temporary template resolution failure'),
        findsNothing,
      );
      expect(
        find.text('Product template unavailable for this subcategory.'),
        findsNothing,
      );
      expect(_dropdownField('Grit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching central products reloads only the selected subcategory template',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EntryController()
        ..centralProductResults.addAll([
          const CentralProductMaster(
            masterProductId: 'MASTER-SAND',
            productName: 'Sandpaper Product',
            normalizedProductName: 'sandpaper product',
            businessTypeId: 'BT-HARDWARE',
            businessTypeName: 'Hardware',
            businessSubTypeId: 'BST-PAINTS',
            businessSubTypeName: 'Paints',
            brandId: 'BR',
            brandName: 'Berger',
            categoryId: 'TOOLS',
            categoryName: 'Painting Tools & Accessories',
            subcategoryId: 'SAND',
            subcategoryName: 'Sandpaper & Abrasives',
            searchTokens: ['sandpaper'],
            isActive: true,
            status: 'ACTIVE',
            scopeType: 'SYSTEM',
          ),
          const CentralProductMaster(
            masterProductId: 'MASTER-APEX-CREATEX',
            productName: 'Apex Createx',
            normalizedProductName: 'apex createx',
            businessTypeId: 'BT-HARDWARE',
            businessTypeName: 'Hardware',
            businessSubTypeId: 'BST-PAINTS',
            businessSubTypeName: 'Paints',
            brandId: 'BR',
            brandName: 'Berger',
            categoryId: 'TEXTURES',
            categoryName: 'Textures & Special Effects',
            subcategoryId: 'EXTERIOR-TEXTURES',
            subcategoryName: 'Exterior Textures',
            searchTokens: ['apex', 'createx'],
            isActive: true,
            status: 'ACTIVE',
            scopeType: 'SYSTEM',
          ),
        ])
        ..templates['SAND'] = const [
          ProductAttribute(
            id: 'grit',
            name: 'Grit',
            dataType: 'SELECT',
            level: 'VARIANT',
            options: ['P80', 'P120'],
            defaultValue: 'P80',
          ),
          ProductAttribute(
            id: 'packUnit',
            name: 'Pack Unit',
            dataType: 'SELECT',
            level: 'VARIANT',
            options: ['Sheet', 'Pack'],
            defaultValue: 'Sheet',
          ),
          ProductAttribute(
            id: 'soldAs',
            name: 'Sold As',
            dataType: 'SELECT',
            level: 'VARIANT',
            options: ['Sheet', 'Pack'],
            defaultValue: 'Sheet',
          ),
        ]
        ..templates['EXTERIOR-TEXTURES'] = const [
          ProductAttribute(
            id: 'textureType',
            name: 'Texture Type',
            dataType: 'SELECT',
            level: 'PRODUCT',
            options: ['Fine', 'Coarse'],
            defaultValue: 'Fine',
          ),
        ];
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();

      Future<void> selectCentral(String query, String product) async {
        await tester.enterText(field('Product Name *'), query);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        await tester.tap(find.text(product).last);
        await tester.pumpAndSettle();
      }

      bool hasDropdown(String label) => find
          .byWidgetPredicate(
            (widget) =>
                widget is DropdownMenu<String> &&
                widget.label is Text &&
                (widget.label as Text).data?.replaceAll(' *', '') == label,
          )
          .evaluate()
          .isNotEmpty;

      await selectCentral('Sandpaper Product', 'Sandpaper Product');
      expect(field('Category'), findsOneWidget);
      expect(field('Subcategory'), findsOneWidget);
      expect(hasDropdown('Grit'), isTrue);
      expect(find.text('Sheet'), findsNWidgets(2));

      await selectCentral('Apex Createx', 'Apex Createx');
      expect(find.text('Textures & Special Effects'), findsOneWidget);
      expect(find.text('Exterior Textures'), findsOneWidget);
      expect(hasDropdown('Grit'), isFalse);
      expect(hasDropdown('Texture Type'), isTrue);
      expect(find.text('Sheet'), findsNothing);

      await selectCentral('Sandpaper Product', 'Sandpaper Product');
      expect(hasDropdown('Grit'), isTrue);
      expect(find.text('Sheet'), findsNWidgets(2));
      await selectCentral('Apex Createx', 'Apex Createx');
      expect(hasDropdown('Grit'), isFalse);
      expect(hasDropdown('Texture Type'), isTrue);
      expect(find.text('Sheet'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('central no-match keeps the custom product flow available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EntryController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductManagementPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Product Name *'), 'Custom brush');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Add "Custom brush" as custom product'), findsOneWidget);
    await tester.tap(find.text('Add "Custom brush" as custom product'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Product Name *')).controller!.text,
      'Custom brush',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('Loctite central matches are shown instead of custom fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EntryController()
      ..centralProductResults.addAll([
        for (final (id, category) in [
          ('LOCTITE-WOOD', 'Adhesives & Tiling'),
          ('LOCTITE-ABRASIVE', 'Painting Tools & Accessories'),
        ])
          CentralProductMaster(
            masterProductId: id,
            productName: 'Loctite Rapid',
            normalizedProductName: 'loctite rapid',
            businessTypeId: 'BT-HARDWARE',
            businessTypeName: 'Hardware',
            businessSubTypeId: 'BST-PAINTS',
            businessSubTypeName: 'Paints',
            brandId: 'SYS_BRAND_ASIAN_PAINTS',
            brandName: 'Asian Paints',
            categoryId: category,
            categoryName: category,
            subcategoryId: 'SUBCATEGORY-$id',
            subcategoryName: 'Woodworking & Multi-Surface Adhesives',
            searchTokens: const ['loctite', 'rapid'],
            isActive: true,
            status: 'ACTIVE',
            scopeType: 'SYSTEM',
          ),
      ]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductManagementPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Product Name *'), 'Loctite Rapid');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(controller.centralProductQueries, ['Loctite Rapid']);
    expect(find.widgetWithText(ListTile, 'Loctite Rapid'), findsNWidgets(2));
    expect(find.text('Add "Loctite Rapid" as custom product'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('central search errors remain distinct from no-match state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = EntryController()
      ..centralProductSearchError = StateError('offline');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductManagementPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();

    await tester.enterText(field('Product Name *'), 'Offline brush');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Unable to search products'), findsOneWidget);
    expect(find.text('No matching product found'), findsNothing);
    expect(find.text('Add "Offline brush" as custom product'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('template switch replaces defaults and removes obsolete values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = EntryController();
    addTearDown(c.dispose);
    c.productMasterValues['SUBCATEGORY:CA'] = [
      const ProductMasterValue(
        id: 'IN',
        name: 'Indoor',
        categoryId: 'CA',
        status: 'ACTIVE',
      ),
      const ProductMasterValue(
        id: 'OUT',
        name: 'Outdoor',
        categoryId: 'CA',
        status: 'ACTIVE',
      ),
    ];
    for (final id in ['IN', 'OUT']) {
      c.templates[id] = [
        ProductAttribute(
          id: 'usage',
          name: 'Usage',
          dataType: 'SELECT',
          defaultValue: id == 'IN' ? 'Interior' : 'Exterior',
          options: const ['Interior', 'Exterior'],
        ),
        if (id == 'IN') const ProductAttribute(id: 'old', name: 'Old detail'),
      ];
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProductManagementPage(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();
    Future<void> pick(String label, String name) async {
      await tester.ensureVisible(field(label));
      await tester.enterText(field(label), name);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await tester.enterText(field('Product Name *'), 'Template test');
    await pick('Brand / Company', 'Berger');
    await pick('Category', 'Accessories');
    await pick('Subcategory', 'Indoor');
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is DropdownMenu<String> &&
                  w.label is Text &&
                  (w.label as Text).data == 'Usage',
            ),
          )
          .initialSelection,
      'Interior',
    );
    await tester.enterText(field('Old detail'), 'obsolete');
    await pick('Subcategory', 'Outdoor');
    expect(
      tester
          .widget<DropdownMenu<String>>(
            find.byWidgetPredicate(
              (w) =>
                  w is DropdownMenu<String> &&
                  w.label is Text &&
                  (w.label as Text).data == 'Usage',
            ),
          )
          .initialSelection,
      'Exterior',
    );
    expect(field('Old detail'), findsNothing);
    await pick('Sold As *', 'Piece');
    await tester.tap(find.text('Save Product'));
    await tester.pumpAndSettle();
    expect(c.savedFields!['attributeValues'], {'usage': 'Exterior'});
    expect(tester.takeException(), isNull);
  });
}

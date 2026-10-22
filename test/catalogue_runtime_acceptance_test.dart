import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/data/catalogue/central_product_master_contract.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/models/central_product_master.dart';
import 'package:testflutter/data/models/product_attribute.dart';
import 'package:testflutter/data/models/resolved_product_template.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';
import 'package:testflutter/presentation/products/product_pages.dart';

import 'offline_sync_test.dart' show FakeRemote, TestConnectivity;
import 'product_entry_form_test.dart' show EntryController, field;

const _expectedProducts = 1305;
const _expectedCategories = 22;
const _expectedSubcategories = 99;
const _acceptanceTenant = '__catalogue_runtime_acceptance__';
const _acceptanceBusiness = '__catalogue_runtime_acceptance__';

String _token(String uid) {
  final claims = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': uid,
            'aud': EnvironmentConfig.projectId,
            'exp':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'header.$claims.signature';
}

Map<String, dynamic> _payload(Map<String, Object?> row) =>
    FirestoreRestService.decodeFields(
      jsonDecode(row['payloadJson'] as String) as Map<String, dynamic>,
    );

class _SubcategoryResult {
  _SubcategoryResult(this.id, this.name, this.representative);

  final String id;
  final String name;
  final CentralProductMaster representative;
  final List<String> failureClasses = [];
  final List<String> reasons = [];
  int resolverTemplateRowCount = 0;
  int activeTemplateRowCount = 0;
  int canonicalTemplateRowCount = 0;
  int productFieldCount = 0;
  int variantFieldCount = 0;
  ResolvedProductTemplate? resolved;
  String? staleValueSentinel;

  bool get passed => failureClasses.isEmpty;

  void fail(String failureClass, String reason) {
    if (!failureClasses.contains(failureClass)) {
      failureClasses.add(failureClass);
    }
    reasons.add(reason);
  }

  Map<String, dynamic> toJson() => {
    'subcategoryId': id,
    'subcategoryName': name,
    'representativeProduct': {
      'masterProductId': representative.masterProductId,
      'productName': representative.productName,
      'brandId': representative.brandId,
      'brandName': representative.brandName,
      'categoryId': representative.categoryId,
      'categoryName': representative.categoryName,
      'subcategoryId': representative.subcategoryId,
      'subcategoryName': representative.subcategoryName,
    },
    'status': passed ? 'PASS' : 'FAIL',
    'failureClass': failureClasses.isEmpty ? null : failureClasses.first,
    'failureClasses': failureClasses,
    'failureReasons': reasons,
    'resolverTemplateRowCount': resolverTemplateRowCount,
    'activeTemplateRowCount': activeTemplateRowCount,
    'canonicalTemplateRowCount': canonicalTemplateRowCount,
    'productLevelFieldCount': productFieldCount,
    'variantLevelFieldCount': variantFieldCount,
    'productLevelFields': [
      for (final attribute in resolved?.productAttributes ?? const [])
        {'id': attribute.attributeId, 'name': attribute.displayName},
    ],
    'variantLevelFields': [
      for (final attribute in resolved?.variantAttributes ?? const [])
        {'id': attribute.attributeId, 'name': attribute.displayName},
    ],
  };
}

class _SQLiteEntryController extends EntryController {
  _SQLiteEntryController(this.searchResults, this.resolvedTemplates);

  final Map<String, List<CentralProductMaster>> searchResults;
  final Map<String, ResolvedProductTemplate> resolvedTemplates;
  ResolvedProductTemplate? lastResolved;

  @override
  Future<List<CentralProductMaster>> searchCentralProductMaster(String query) =>
      Future.value(
        searchResults[_normalize(query)] ?? const <CentralProductMaster>[],
      );

  @override
  Future<ResolvedProductTemplate> resolveProductTemplate(String subcategoryId) {
    final resolved = resolvedTemplates[subcategoryId];
    if (resolved == null) {
      throw StateError('No SQLite resolver result for $subcategoryId.');
    }
    lastResolved = resolved;
    return Future.value(resolved);
  }

  @override
  Future<List<ProductAttribute>> loadProductTemplate(String subcategoryId) =>
      Future.value(
        resolvedTemplates[subcategoryId]?.attributes ??
            const <ProductAttribute>[],
      );
}

String _normalize(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

Finder _visibleAttributeField(ResolvedTemplateAttribute attribute) =>
    find.byWidgetPredicate((widget) {
      if (widget is! TextFormField || widget.key is! ValueKey) return false;
      final key = (widget.key as ValueKey).value.toString();
      final namespace = attribute.level == AttributeLevel.product
          ? '-product-'
          : '-sku-';
      return key.contains(namespace) &&
          key.endsWith('-${attribute.attributeId}');
    });

bool _hasRenderedDynamicAttribute(ResolvedProductTemplate resolved) {
  for (final attribute in resolved.allAttributes) {
    final textField = find.byWidgetPredicate(
      (widget) =>
          widget is InputDecorator &&
          widget.decoration.labelText?.replaceAll(' *', '').trim() ==
              attribute.displayName.trim(),
    );
    final textLabel = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data ?? '').replaceAll(' *', '').trim() ==
              attribute.displayName.trim(),
    );
    final dropdown = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownMenu<String> &&
          widget.label is Text &&
          ((widget.label as Text).data ?? '').replaceAll(' *', '').trim() ==
              attribute.displayName.trim(),
    );
    final toggle = find.widgetWithText(SwitchListTile, attribute.displayName);
    if (textField.evaluate().isNotEmpty ||
        textLabel.evaluate().isNotEmpty ||
        dropdown.evaluate().isNotEmpty ||
        toggle.evaluate().isNotEmpty) {
      return true;
    }
  }
  return false;
}

Future<String?> _enterDynamicSentinel(
  WidgetTester tester,
  ResolvedProductTemplate resolved,
  int sequence,
) async {
  for (final attribute in resolved.allAttributes) {
    if (attribute.attributeId == 'hsnCode' ||
        {'BOOLEAN', 'SELECT', 'MULTI_SELECT'}.contains(attribute.dataType)) {
      continue;
    }
    final finder = _visibleAttributeField(attribute);
    if (finder.evaluate().isEmpty) continue;
    final sentinel = 'runtime-stale-check-$sequence';
    await tester.ensureVisible(finder.first);
    await tester.enterText(finder.first, sentinel);
    await tester.pumpAndSettle();
    final entered = find.byWidgetPredicate(
      (widget) => widget is EditableText && widget.controller.text == sentinel,
    );
    if (entered.evaluate().isNotEmpty) return sentinel;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'punctuated product autocomplete uses its SQLite normalized name',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'catalogue-search-normalization-',
      );
      final database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: dir.path,
      );
      final rawDatabase = await database.open(
        EnvironmentConfig.projectId,
        'SEARCH_TEST',
      );
      final source = LocalDataSource(rawDatabase);
      final remote = FakeRemote()..offline = true;
      final sync = SyncEngine(
        remote,
        TestConnectivity()..available = false,
        sessionProvider: () async => null,
      );
      final service = OfflineFirestoreService(database, remote, sync);
      await service.activate('SEARCH_TEST');
      sync.detach();
      final repository = ProductRepository(service, service);
      addTearDown(() async {
        service.logout();
        sync.dispose();
        await database.close();
        await dir.delete(recursive: true);
      });

      await source.upsertCentralProductMasters([
        {
          'name': '${CentralProductMasterContract.collection}/CPM-PUNCTUATION',
          'fields': FirestoreRestService.encodeFields({
            'masterProductId': 'CPM-PUNCTUATION',
            'productName': 'HomeShield Wonder-Flex',
            'normalizedProductName': 'homeshield wonder flex',
            'businessTypeId': 'BT-HARDWARE',
            'businessTypeName': 'Hardware',
            'businessSubTypeId': 'BST-PAINTS',
            'businessSubTypeName': 'Paints',
            'brandId': 'SYS_BRAND_TEST',
            'brandName': 'Test Brand',
            'categoryId': 'SYS_CATEGORY_TEST',
            'categoryName': 'Test Category',
            'subcategoryId': 'SYS_SUBCATEGORY_TEST',
            'subcategoryName': 'Test Subcategory',
            'searchTokens': ['homeshield', 'wonder', 'flex'],
            'scopeType': 'SYSTEM',
            'status': 'ACTIVE',
            'isActive': true,
          }),
        },
      ]);

      final matches = await repository.searchCentralProductMaster(
        query: 'HomeShield Wonder-Flex',
        businessTypeId: 'BT-HARDWARE',
        businessSubTypeId: 'BST-PAINTS',
      );
      expect(matches.map((product) => product.masterProductId), [
        'CPM-PUNCTUATION',
      ]);
      expect(remote.reads, 0);
      expect(remote.queries, 0);
      expect(remote.commits, 0);
    },
  );

  final dbPath = Platform.environment['CATALOGUE_RUNTIME_DB_PATH'];
  final runtimeConfigured =
      dbPath != null &&
      dbPath.isNotEmpty &&
      EnvironmentConfig.projectId.isNotEmpty;

  testWidgets(
    'Product Add accepts every referenced canonical SYSTEM subcategory from SQLite',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<T> runDb<T>(Future<T> Function() action) async {
        final result = await tester.runAsync(() async => (await action(),));
        if (result == null) {
          throw StateError('SQLite operation did not complete.');
        }
        return result.$1;
      }

      final absoluteDbPath = path.normalize(path.absolute(dbPath!));
      final databaseFile = File(absoluteDbPath);
      expect(await runDb(databaseFile.exists), isTrue, reason: absoluteDbPath);

      final projectId = EnvironmentConfig.projectId;
      final fileName = path.basename(absoluteDbPath);
      final prefix = 'nubibill-${Uri.encodeComponent('$projectId-')}';
      expect(
        fileName.startsWith(prefix) && fileName.endsWith('.db'),
        isTrue,
        reason: 'The cache path must belong to FIREBASE_PROJECT_ID.',
      );
      final uid = fileName.substring(prefix.length, fileName.length - 3);
      expect(uid, isNotEmpty);

      final schemaVersion = await runDb(() async {
        final probe = await databaseFactoryFfi.openDatabase(
          absoluteDbPath,
          options: OpenDatabaseOptions(readOnly: true),
        );
        final version = await probe.getVersion();
        await probe.close();
        return version;
      });
      expect(
        schemaVersion,
        LocalDatabase.schemaVersion,
        reason: 'Refusing to open a cache that would require schema migration.',
      );

      final database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: path.dirname(absoluteDbPath),
      );
      final rawDatabase = await runDb(() async {
        final opened = await database.open(projectId, uid);
        await opened.execute('PRAGMA query_only=ON');
        return opened;
      });
      expect(
        (await runDb(() => rawDatabase.rawQuery('PRAGMA query_only')))
            .single
            .values
            .single,
        1,
      );

      final source = LocalDataSource(rawDatabase);
      final outboxBefore = await runDb(
        () => rawDatabase.query('sync_outbox', orderBy: 'id ASC'),
      );
      final remote = FakeRemote()..offline = true;
      final sync = SyncEngine(
        remote,
        TestConnectivity()..available = false,
        sessionProvider: () async => throw StateError(
          'Runtime acceptance must not start a sync session.',
        ),
      );
      final service = OfflineFirestoreService(database, remote, sync);
      await tester.runAsync(() async {
        await service.activate(uid);
      });
      sync.detach();
      final token = _token(uid);
      final repository = ProductRepository(service, service);
      final searchResultsByQuery = <String, List<CentralProductMaster>>{};
      final resolvedTemplates = <String, ResolvedProductTemplate>{};
      final controller = _SQLiteEntryController(
        searchResultsByQuery,
        resolvedTemplates,
      );
      addTearDown(controller.dispose);
      addTearDown(() async {
        service.logout();
        sync.dispose();
        await database.close();
      });

      final masterRows = await runDb(
        () => rawDatabase.query(
          'local_central_product_master',
          where: 'source_collection=? AND scope_type=? AND status=? AND is_active=1',
          whereArgs: [
            CentralProductMasterContract.collection,
            'SYSTEM',
            'ACTIVE',
          ],
          orderBy: 'master_product_id ASC',
        ),
      );
      final products = [
        for (final row in masterRows)
          CentralProductMaster.fromData(
            row['master_product_id'] as String,
            FirestoreRestService.decodeFields(
              jsonDecode(row['payload_json'] as String) as Map<String, dynamic>,
            ),
          ),
      ];
      for (final product in products) {
        CentralProductMasterContract.validateProduct(product);
      }
      final grouped = <String, List<CentralProductMaster>>{};
      for (final product in products) {
        grouped.putIfAbsent(product.subcategoryId, () => []).add(product);
      }
      final referencedCategoryIds = products
          .map((product) => product.categoryId)
          .toSet();

      final results = <String, _SubcategoryResult>{};
      final orderedSubcategoryIds = grouped.keys.toList()..sort();

      for (final subcategoryId in orderedSubcategoryIds) {
        final representatives = grouped[subcategoryId]!
          ..sort((a, b) => a.masterProductId.compareTo(b.masterProductId));
        final representative = representatives.first;
        final result = _SubcategoryResult(
          subcategoryId,
          representative.subcategoryName,
          representative,
        );
        results[subcategoryId] = result;

        if ([
          representative.brandId,
          representative.brandName,
          representative.categoryId,
          representative.categoryName,
          representative.subcategoryId,
          representative.subcategoryName,
        ].any((value) => value.trim().isEmpty)) {
          result.fail(
            'MISSING_CATEGORY',
            'The representative verified product is missing classification IDs or names.',
          );
        }

        final localBrand = await runDb(
          () => source.row('brands', representative.brandId),
        );
        if (localBrand == null ||
            localBrand['status'] != 'ACTIVE' ||
            localBrand['isDeleted'] != 0 ||
            _payload(localBrand)['brandId'] != representative.brandId ||
            _payload(localBrand)['name'] != representative.brandName) {
          result.fail(
            'MISSING_BRAND',
            'The exact local brand row is missing, inactive, deleted, or has a mismatched name.',
          );
        }

        final localCategory = await runDb(
          () => source.row('product_categories', representative.categoryId),
        );
        if (localCategory == null ||
            localCategory['scopeType'] != 'SYSTEM' ||
            localCategory['status'] != 'ACTIVE' ||
            localCategory['isDeleted'] != 0 ||
            _payload(localCategory)['categoryId'] !=
                representative.categoryId ||
            _payload(localCategory)['name'] != representative.categoryName) {
          result.fail(
            'MISSING_CATEGORY',
            'The exact canonical category row is missing, inactive, deleted, or mismatched.',
          );
        }

        final localSubcategory = await runDb(
          () => source.row('product_subcategories', subcategoryId),
        );
        if (localSubcategory == null) {
          result.fail(
            'MISSING_SUBCATEGORY',
            'No exact-ID local canonical subcategory row exists.',
          );
        } else if (localSubcategory['scopeType'] != 'SYSTEM' ||
            localSubcategory['status'] != 'ACTIVE' ||
            localSubcategory['isDeleted'] != 0 ||
            _payload(localSubcategory)['subcategoryId'] != subcategoryId ||
            _payload(localSubcategory)['categoryId'] !=
                representative.categoryId ||
            _payload(localSubcategory)['name'] !=
                representative.subcategoryName) {
          result.fail(
            'INACTIVE_CANONICAL_SUBCATEGORY',
            'The exact-ID canonical subcategory is not ACTIVE or its IDs/names do not match.',
          );
        }

        final allCanonicalTemplates = await runDb(
          () => source.query('subcategory_attribute_templates', [
            FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
            FirestoreFilter('subcategoryId', 'EQUAL', subcategoryId),
          ]),
        );
        final activeCanonicalTemplates = allCanonicalTemplates.where((doc) {
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          return fields['subcategoryId'] == subcategoryId &&
              fields['scopeType'] == 'SYSTEM' &&
              fields['status'] == 'ACTIVE';
        }).toList();
        result.canonicalTemplateRowCount = allCanonicalTemplates.length;
        result.activeTemplateRowCount = activeCanonicalTemplates.length;

        if (allCanonicalTemplates.isEmpty) {
          result.fail(
            'MISSING_CANONICAL_TEMPLATE',
            'No SYSTEM template row exists for this exact canonical subcategory ID.',
          );
        }
        if (activeCanonicalTemplates.isEmpty) {
          result.fail(
            'NO_ACTIVE_CANONICAL_TEMPLATE',
            'No ACTIVE SYSTEM template row exists for this exact canonical subcategory ID.',
          );
        }

        final searchResults = await runDb(
          () => repository.searchCentralProductMaster(
            query: representative.productName,
            businessTypeId: representative.businessTypeId,
            businessSubTypeId: representative.businessSubTypeId,
          ),
        );
        searchResultsByQuery[_normalize(representative.productName)] =
            searchResults;
        final selectedProduct = searchResults
            .where(
              (candidate) =>
                  candidate.masterProductId == representative.masterProductId,
            )
            .firstOrNull;
        if (selectedProduct == null ||
            selectedProduct.brandId != representative.brandId ||
            selectedProduct.categoryId != representative.categoryId ||
            selectedProduct.subcategoryId != subcategoryId ||
            selectedProduct.brandName != representative.brandName ||
            selectedProduct.categoryName != representative.categoryName ||
            selectedProduct.subcategoryName != representative.subcategoryName) {
          result.fail(
            'RESOLVER_EMPTY',
            'SQLite Product Add autocomplete did not return the representative with its exact IDs and names.',
          );
        }

        final resolved = await runDb(
          () => repository.resolveTemplate(
            tenantId: _acceptanceTenant,
            businessId: _acceptanceBusiness,
            subcategoryId: subcategoryId,
            token: token,
          ),
        );
        resolvedTemplates[subcategoryId] = resolved;
        result.resolved = resolved;
        result.resolverTemplateRowCount = resolved.attributes.length;
        result.productFieldCount = resolved.productAttributes.length;
        result.variantFieldCount = resolved.variantAttributes.length;

        if (resolved.subcategoryId != subcategoryId ||
            resolved.categoryId != representative.categoryId ||
            resolved.categoryName != representative.categoryName ||
            resolved.subcategoryName != representative.subcategoryName) {
          result.fail(
            'RESOLVER_EMPTY',
            'ProductTemplateResolver returned IDs or names that do not match the exact canonical selection.',
          );
        }
        if (resolved.attributes.isEmpty ||
            resolved.readiness != TemplateReadinessState.ready) {
          result.fail(
            'RESOLVER_EMPTY',
            'ProductTemplateResolver returned no ready dynamic fields.',
          );
        }

        final declaresVariantAttributes = activeCanonicalTemplates.any((doc) {
          final fields = FirestoreRestService.decodeFields(doc['fields']);
          return fields['attributeLevel']?.toString().toUpperCase() ==
              'VARIANT';
        });
        if (declaresVariantAttributes && resolved.variantAttributes.isEmpty) {
          result.fail(
            'RESOLVER_EMPTY',
            'Canonical ACTIVE template rows declare variant fields, but the resolver returned none.',
          );
        }

        if (activeCanonicalTemplates.isEmpty) {
          final activeSubcategories = await runDb(
            () => source.query('product_subcategories', [
              const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
              const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
              FirestoreFilter('categoryId', 'EQUAL', representative.categoryId),
            ]),
          );
          final legacyCandidates = activeSubcategories.where((doc) {
            final fields = FirestoreRestService.decodeFields(doc['fields']);
            return doc['name'].toString().split('/').last != subcategoryId &&
                fields['name'] == representative.subcategoryName;
          });
          for (final legacy in legacyCandidates) {
            final legacyId = legacy['name'].toString().split('/').last;
            final legacyTemplates = await runDb(
              () => source.query('subcategory_attribute_templates', [
                const FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
                const FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
                FirestoreFilter('subcategoryId', 'EQUAL', legacyId),
              ]),
            );
            if (legacyTemplates.isNotEmpty) {
              result.fail(
                'LEGACY_ONLY_TEMPLATE_DEPENDENCY',
                'Active templates exist under same-name legacy subcategory $legacyId, not the canonical ID.',
              );
            }
          }
        }
      }

      final duplicateMasterIds = await runDb(
        () => rawDatabase.rawQuery(
          '''
        SELECT master_product_id
        FROM local_central_product_master
        WHERE source_collection=? AND scope_type='SYSTEM'
          AND status='ACTIVE' AND is_active=1
        GROUP BY master_product_id HAVING COUNT(*) > 1
        ''',
          [CentralProductMasterContract.collection],
        ),
      );
      for (final duplicate in duplicateMasterIds) {
        final duplicateId = duplicate['master_product_id'];
        final product = products
            .where((candidate) => candidate.masterProductId == duplicateId)
            .firstOrNull;
        if (product != null) {
          results[product.subcategoryId]?.fail(
            'DUPLICATE_MASTER_PRODUCT',
            'masterProductId ${product.masterProductId} occurs more than once in the verified SYSTEM cache.',
          );
        }
      }

      final duplicateNames = await runDb(
        () => rawDatabase.rawQuery(
          '''
        SELECT subcategory_id, brand_name, normalized_product_name
        FROM local_central_product_master
        WHERE source_collection=? AND scope_type='SYSTEM'
          AND status='ACTIVE' AND is_active=1
        GROUP BY lower(trim(brand_name)), lower(trim(normalized_product_name))
        HAVING COUNT(*) > 1
        ''',
          [CentralProductMasterContract.collection],
        ),
      );
      for (final duplicate in duplicateNames) {
        final id = duplicate['subcategory_id'] as String?;
        results[id]?.fail(
          'DUPLICATE_BRAND_NORMALIZED_NAME',
          'Brand "${duplicate['brand_name']}" and normalized product name "${duplicate['normalized_product_name']}" are duplicated.',
        );
      }

      final report = <String, dynamic>{
        'productsChecked': products.length,
        'categoriesReferenced': referencedCategoryIds.length,
        'subcategoriesChecked': results.length,
        'passCount': 0,
        'failCount': 0,
        'failedSubcategoryIds': <String>[],
        'failedSubcategoryNames': <String>[],
        'subcategories': <Map<String, dynamic>>[],
      };
      final checks = orderedSubcategoryIds
          .map((id) => results[id]!)
          .toList(growable: false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProductManagementPage(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Product'));
      await tester.pumpAndSettle();

      Future<bool> selectRepresentative(_SubcategoryResult result) async {
        final product = result.representative;
        await tester.ensureVisible(field('Product Name *'));
        await tester.enterText(field('Product Name *'), product.productName);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();

        final suggestion = find.byWidgetPredicate((widget) {
          if (widget is! ListTile || widget.title is! Text) return false;
          final title = (widget.title as Text).data;
          final subtitle = widget.subtitle is Text
              ? (widget.subtitle as Text).data ?? ''
              : '';
          return title == product.productName &&
              subtitle.startsWith('${product.brandName}  ·  ');
        });
        if (suggestion.evaluate().isEmpty) {
          result.fail(
            'RESOLVER_EMPTY',
            'The SQLite-backed Product Add autocomplete did not render the representative product.',
          );
          return false;
        }
        await tester.tap(suggestion.first);
        await tester.pumpAndSettle();
        return true;
      }

      String? pendingStaleValue;
      _SubcategoryResult? previousResult;
      var staleTransitionsChecked = 0;
      for (var index = 0; index < checks.length; index++) {
        final result = checks[index];
        if (!await selectRepresentative(result)) {
          if (pendingStaleValue != null) {
            previousResult?.fail(
              'STALE_DYNAMIC_STATE',
              'A different-subcategory transition was not completed, so stale-value clearing could not be verified.',
            );
          }
          previousResult = result;
          pendingStaleValue = null;
          continue;
        }

        if (pendingStaleValue != null) {
          final staleField = find.byWidgetPredicate(
            (widget) =>
                widget is EditableText &&
                widget.controller.text == pendingStaleValue,
          );
          if (staleField.evaluate().isNotEmpty) {
            result.fail(
              'STALE_DYNAMIC_STATE',
              'Dynamic value from ${previousResult?.id} remained after selecting ${result.id}.',
            );
          }
          staleTransitionsChecked++;
        } else if (previousResult != null) {
          previousResult.fail(
            'STALE_DYNAMIC_STATE',
            'No dynamic text field could be populated to verify clearing on the next subcategory switch.',
          );
        }

        final resolved = controller.lastResolved;
        if (resolved == null ||
            resolved.subcategoryId != result.id ||
            resolved.attributes.isEmpty) {
          result.fail(
            'RESOLVER_EMPTY',
            'The Product Add form did not load a non-empty template for the selected canonical subcategory.',
          );
          pendingStaleValue = null;
          previousResult = result;
          continue;
        }

        if (find
            .text('Product template unavailable for this subcategory.')
            .evaluate()
            .isNotEmpty) {
          result.fail(
            'RESOLVER_EMPTY',
            'The Product Add form displayed the template-unavailable banner.',
          );
        }
        if (!_hasRenderedDynamicAttribute(resolved)) {
          result.fail(
            'RESOLVER_EMPTY',
            'No dynamic field from the resolved product/variant template was rendered.',
          );
        }

        pendingStaleValue = await _enterDynamicSentinel(
          tester,
          resolved,
          index,
        );
        if (pendingStaleValue == null) {
          result.fail(
            'STALE_DYNAMIC_STATE',
            'No editable dynamic product- or variant-level field was available for the stale-value switch check.',
          );
        }
        previousResult = result;
      }

      if (checks.length > 1 &&
          previousResult != null &&
          pendingStaleValue != null) {
        final firstResult = checks.first;
        if (await selectRepresentative(firstResult)) {
          final staleField = find.byWidgetPredicate(
            (widget) =>
                widget is EditableText &&
                widget.controller.text == pendingStaleValue,
          );
          if (staleField.evaluate().isNotEmpty) {
            firstResult.fail(
              'STALE_DYNAMIC_STATE',
              'Dynamic value from ${previousResult.id} remained after switching back to ${firstResult.id}.',
            );
          }
          staleTransitionsChecked++;
        } else {
          previousResult.fail(
            'STALE_DYNAMIC_STATE',
            'Could not complete the final switch from ${previousResult.id} to ${firstResult.id}.',
          );
        }
      } else if (previousResult != null && checks.length > 1) {
        previousResult.fail(
          'STALE_DYNAMIC_STATE',
          'The final dynamic text value was unavailable for the closing switch check.',
        );
      }

      final passed = checks.where((result) => result.passed).length;
      final failed = checks.length - passed;
      report['passCount'] = passed;
      report['failCount'] = failed;
      report['failedSubcategoryIds'] = checks
          .where((result) => !result.passed)
          .map((result) => result.id)
          .toList();
      report['failedSubcategoryNames'] = checks
          .where((result) => !result.passed)
          .map((result) => result.name)
          .toList();
      report['dynamicStateTransitionsChecked'] = staleTransitionsChecked;
      report['legacyOnlyTemplateDependencies'] = checks
          .where(
            (result) => result.failureClasses.contains(
              'LEGACY_ONLY_TEMPLATE_DEPENDENCY',
            ),
          )
          .length;
      report['resolverEmptyCases'] = checks
          .where((result) => result.failureClasses.contains('RESOLVER_EMPTY'))
          .length;
      report['subcategories'] = checks
          .map((result) => result.toJson())
          .toList();

      final outboxAfter = await runDb(
        () => rawDatabase.query('sync_outbox', orderBy: 'id ASC'),
      );
      report['firestoreReadRequests'] = remote.reads + remote.queries;
      report['firestoreWriteRequests'] = remote.commits;
      report['syncOutboxBefore'] = outboxBefore.length;
      report['syncOutboxAfter'] = outboxAfter.length;
      stdout.writeln(
        'Catalogue runtime acceptance: ${report['passCount']} PASS, '
        '${report['failCount']} FAIL across ${report['subcategoriesChecked']} '
        'subcategories and ${report['productsChecked']} products.',
      );
      stdout.writeln('CATALOGUE_RUNTIME_ACCEPTANCE_JSON:${jsonEncode(report)}');

      expect(products, hasLength(_expectedProducts));
      expect(referencedCategoryIds, hasLength(_expectedCategories));
      expect(checks, hasLength(_expectedSubcategories));
      expect(report['passCount'], _expectedSubcategories);
      expect(
        report['failCount'],
        0,
        reason: jsonEncode(report['subcategories']),
      );
      expect(report['dynamicStateTransitionsChecked'], _expectedSubcategories);
      expect(
        remote.queries,
        0,
        reason: 'Product search/resolution must be local.',
      );
      expect(
        remote.reads,
        0,
        reason: 'Product search/resolution must be local.',
      );
      expect(
        remote.commits,
        0,
        reason: 'The acceptance test must not write remotely.',
      );
      expect(
        outboxAfter,
        outboxBefore,
        reason: 'sync_outbox must remain unchanged.',
      );
    },
    skip: !runtimeConfigured,
  );
}

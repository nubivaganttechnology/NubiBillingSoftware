import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:testflutter/core/config/environment_config.dart';
import 'package:testflutter/data/catalogue/system_catalogue_snapshot.dart';
import 'package:testflutter/data/local/local_data_source.dart';
import 'package:testflutter/data/local/local_database.dart';
import 'package:testflutter/data/repositories/product_repository.dart';
import 'package:testflutter/data/services/firestore_rest_service.dart';
import 'package:testflutter/data/services/offline_firestore_service.dart';
import 'package:testflutter/data/sync/connectivity_service.dart';
import 'package:testflutter/data/sync/sync_engine.dart';

import 'support/phase10e_release.dart' show release4Documents;

const _tenantId = 'test-tenant-product-edit';
const _businessId = 'test-business-product-edit';
const _uid = 'test-user-product-edit';
const _productId = 'test-product-prd-0009';
const _variantId = 'test-variant-prd-0009-1';
const _categoryId = 'BUS_CATEGORY_EDIT_FIXTURE';
const _subcategoryId = 'BUS_SUBCATEGORY_EDIT_FIXTURE';

String _token() =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': _uid, 'aud': EnvironmentConfig.projectId})))}.signature';

/// Any unexpected network access fails the test. Catalogue and product reads
/// are served from the isolated local SQLite database.
class _ForbiddenRemote implements FirestoreRestService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected remote call: ${invocation.memberName}');
}

class _OfflineConnectivity implements ConnectivityService {
  @override
  bool available = false;
  @override
  Stream<bool> get onConnectivityChanged => const Stream<bool>.empty();
  @override
  Future<bool> checkInternet() async => false;
  @override
  Future<void> dispose() async {}
  @override
  Future<void> start(void Function(bool) onChange) async {}
}

class _UnscheduledSync extends SyncEngine {
  _UnscheduledSync(FirestoreRestService remote)
    : super(
        remote,
        _OfflineConnectivity(),
        sessionProvider: () async => null,
      );

  @override
  void schedule({bool pull = false, String reason = 'OUTBOX'}) {}
}

Map<String, dynamic> _document(
  String collection,
  String id,
  Map<String, dynamic> fields,
) => {
  'name': '$collection/$id',
  'updateTime': 'fixture-$id-v1',
  'fields': FirestoreRestService.encodeFields(fields),
};

Future<void> _seed(
  LocalDataSource source,
  String collection,
  String id,
  Map<String, dynamic> fields,
) => source.upsertRemote(collection, [_document(collection, id, fields)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'deterministic Product Edit regression persists packSize 12, warranty 2 Years and mixingRatio 2:1 offline and after reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'product-edit-regression-',
      );
      final remote = _ForbiddenRemote();
      final database = LocalDatabase(
        factory: databaseFactoryFfi,
        directory: directory.path,
      );
      final sync = _UnscheduledSync(remote);
      final service = OfflineFirestoreService(database, remote, sync);
      var databaseClosed = false;
      try {
        await service.activate(_uid);
        var source = LocalDataSource(
          await database.open(EnvironmentConfig.projectId, _uid),
        );
        await SystemCatalogueSnapshot.import(
          source: source,
          documents: release4Documents(),
          readTimes: const {},
          allowUnapprovedIsolatedForTests: true,
        );
        const unitRules = <String, dynamic>{
          'allowedPackUnits': ['Litre'],
          'defaultPackUnit': 'Litre',
          'allowedBaseUnits': ['Litre'],
          'defaultBaseUnit': 'Litre',
          'allowedSellingUnits': ['Litre'],
          'defaultSellingUnit': 'Litre',
          'conversionAllowed': false,
        };
        await _seed(source, 'brands', 'BUS_BRAND_EDIT_FIXTURE', {
          'brandId': 'BUS_BRAND_EDIT_FIXTURE',
          'name': 'Fixture Brand',
          'scopeType': 'BUSINESS',
          'tenantId': _tenantId,
          'businessId': _businessId,
          'status': 'ACTIVE',
        });
        await _seed(source, 'product_categories', _categoryId, {
          'categoryId': _categoryId,
          'name': 'Fixture Waterproofing',
          'scopeType': 'BUSINESS',
          'tenantId': _tenantId,
          'businessId': _businessId,
          'status': 'ACTIVE',
        });
        await _seed(source, 'product_subcategories', _subcategoryId, {
          'subcategoryId': _subcategoryId,
          'categoryId': _categoryId,
          'name': 'Fixture Interior Coating',
          'scopeType': 'BUSINESS',
          'tenantId': _tenantId,
          'businessId': _businessId,
          'templateSelectable': true,
          'templateStatus': 'READY',
          'unitRules': unitRules,
          'status': 'ACTIVE',
        });
        const attributes = <String, Map<String, dynamic>>{
          'usage': {
            'name': 'Usage', 'dataType': 'SELECT', 'attributeLevel': 'PRODUCT',
            'options': ['Interior', 'Exterior'],
          },
          'mixingRatio': {
            'name': 'Mixing Ratio', 'dataType': 'TEXT', 'attributeLevel': 'PRODUCT',
          },
          'warranty': {
            'name': 'Warranty', 'dataType': 'TEXT', 'attributeLevel': 'PRODUCT',
          },
          'packSize': {
            'name': 'Pack Size', 'dataType': 'NUMBER', 'attributeLevel': 'VARIANT',
          },
          'unit': {
            'name': 'Pack Unit', 'dataType': 'SELECT', 'attributeLevel': 'VARIANT',
            'options': ['Litre'],
          },
        };
        for (final entry in attributes.entries) {
          await _seed(
            source,
            'subcategory_attribute_templates',
            'EDIT_${entry.key}',
            {
              'templateId': 'EDIT_${entry.key}',
              'subcategoryId': _subcategoryId,
              'attributeId': entry.key,
              'attributeLevel': entry.value['attributeLevel'],
              'scopeType': 'BUSINESS',
              'tenantId': _tenantId,
              'businessId': _businessId,
              'status': 'ACTIVE',
            },
          );
        }
        var repository = ProductRepository(
          service,
          service,
          allowUnapprovedIsolatedCatalogueForTests: true,
        );

        final originalProductFields = <String, dynamic>{
          'productId': _productId,
          'productCode': 'PRD-0009',
          'productName': 'Waterproof Coating Test Product',
          'name': 'Waterproof Coating Test Product',
          'tenantId': _tenantId,
          'businessId': _businessId,
          'scopeType': 'BUSINESS',
          'brandId': 'BUS_BRAND_EDIT_FIXTURE',
          'brand': 'Fixture Brand',
          'categoryId': _categoryId,
          'categoryName': 'Waterproofing',
          'subcategoryId': _subcategoryId,
          'subcategory': 'Interior Dampness Treatment',
          'attributeValues': {
            'usage': 'Interior',
            'mixingRatio': '1:1',
            'warranty': '1 Year',
          },
          'description': 'Preserve this description',
          'productImage': '',
          'imageUrl': '',
          'hsnCode': '320910',
          'defaultGstRateBps': 1800,
          'status': 'ACTIVE',
          'version': 1,
          'createdAt': DateTime.utc(2026, 1, 1),
          'updatedAt': DateTime.utc(2026, 1, 1),
        };
        final originalVariantFields = <String, dynamic>{
          'variantId': _variantId,
          'productId': _productId,
          'productCode': 'PRD-0009',
          'tenantId': _tenantId,
          'businessId': _businessId,
          'scopeType': 'BUSINESS',
          'sku': 'PRD-0009-01',
          'barcode': 'TEST-BARCODE-0009',
          'status': 'ACTIVE',
          'packSize': 5,
          'packUnitId': 'SYS_UNIT_LITRE',
          'unitId': 'SYS_UNIT_LITRE',
          'baseUnitId': 'SYS_UNIT_LITRE',
          'commercialUnitId': 'SYS_UNIT_LITRE',
          'commercialUnitName': 'Litre',
          'baseQuantityPerCommercialUnit': 1,
          'attributeValues': {'packSize': 5, 'unit': 'Litre'},
          'version': 1,
          'createdAt': DateTime.utc(2026, 1, 1),
          'updatedAt': DateTime.utc(2026, 1, 1),
        };
        await _seed(source, 'products', _productId, originalProductFields);
        await _seed(
          source,
          'product_variants',
          _variantId,
          originalVariantFields,
        );

        final beforeProduct = FirestoreRestService.decodeFields(
          jsonDecode((await source.row('products', _productId))!['payloadJson'] as String),
        );
        final beforeVariant = FirestoreRestService.decodeFields(
          jsonDecode((await source.row('product_variants', _variantId))!['payloadJson'] as String),
        );

        await repository.updateStructuredProduct(
          tenantId: _tenantId,
          businessId: _businessId,
          productId: _productId,
          productName: 'Waterproof Coating Test Product',
          actorUid: _uid,
          token: _token(),
          productFields: {
            ...originalProductFields,
            'attributeValues': {
              ...(originalProductFields['attributeValues'] as Map<String, dynamic>),
              'warranty': '2 Years',
              'mixingRatio': '2:1',
            },
          },
          variants: [
            {
              ...originalVariantFields,
              'packSize': 12,
              'attributeValues': {'packSize': 12, 'unit': 'Litre'},
            },
          ],
        );

        final editedProduct = FirestoreRestService.decodeFields(
          jsonDecode((await source.row('products', _productId))!['payloadJson'] as String),
        );
        final editedVariant = FirestoreRestService.decodeFields(
          jsonDecode((await source.row('product_variants', _variantId))!['payloadJson'] as String),
        );
        expect(editedProduct['attributeValues']['warranty'], '2 Years');
        expect(editedProduct['attributeValues']['mixingRatio'], '2:1');
        expect(editedProduct['attributeValues']['usage'], 'Interior');
        expect(editedProduct['description'], beforeProduct['description']);
        expect(editedProduct['productImage'], beforeProduct['productImage']);
        expect(editedVariant['variantId'], _variantId);
        expect(editedVariant['packSize'], 12);
        expect(editedVariant['attributeValues']['packSize'], 12);
        expect(editedVariant['barcode'], beforeVariant['barcode']);
        expect(editedVariant['sku'], beforeVariant['sku']);

        final pendingOutbox = await source.db.query(
          'sync_outbox',
          orderBy: 'entityType,documentId',
        );
        expect(pendingOutbox.map((row) => row['entityType']).toSet(), containsAll({
          'products',
          'product_variants',
          'product_unique_keys',
        }));
        final pendingOutboxIds = pendingOutbox
            .map((row) => row['id'])
            .toSet();

        // Reopen the same disposable account database while still offline.
        await database.close();
        databaseClosed = true;
        final reopenedDatabase = LocalDatabase(
          factory: databaseFactoryFfi,
          directory: directory.path,
        );
        final reopenedSync = _UnscheduledSync(remote);
        final reopenedService = OfflineFirestoreService(
          reopenedDatabase,
          remote,
          reopenedSync,
        );
        try {
          await reopenedService.activate(_uid);
          source = LocalDataSource(
            await reopenedDatabase.open(EnvironmentConfig.projectId, _uid),
          );
          repository = ProductRepository(
            reopenedService,
            reopenedService,
            allowUnapprovedIsolatedCatalogueForTests: true,
          );
          final products = await repository.getProducts(
            tenantId: _tenantId,
            businessId: _businessId,
            token: _token(),
          );
          final reopenedProduct = products.singleWhere(
            (product) => product.productCode == 'PRD-0009',
          );
          expect(reopenedProduct.attributeValues['warranty'], '2 Years');
          expect(reopenedProduct.attributeValues['mixingRatio'], '2:1');
          expect(reopenedProduct.variants.single.packSize.toString(), '12');
          expect(reopenedProduct.description, beforeProduct['description']);
          expect(
            (await source.db.query('sync_outbox')).map((row) => row['id']).toSet(),
            pendingOutboxIds,
          );
        } finally {
          reopenedSync.dispose();
          await reopenedDatabase.close();
        }
      } finally {
        sync.dispose();
        if (!databaseClosed) await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/product_attribute.dart';
import '../models/product_validation_result.dart';
import '../models/reclassification_plan.dart';
import '../models/resolved_product_template.dart';
import '../services/product_template_resolver.dart';
import '../services/catalogue_selection_resolver.dart';
import '../services/product_validator.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../models/outlet_product_model.dart';
import '../models/product_model.dart';
import '../models/quantity_discount_slab.dart';
import '../models/product_master_value.dart';
import '../models/central_product_master.dart';
import '../models/product_variant_model.dart';
import '../catalogue/catalogue_fingerprint.dart';
import '../catalogue/catalogue_contract.dart';
import '../catalogue/catalogue_readiness.dart';
import '../catalogue/system_catalogue_metadata.dart';
import '../services/firestore_data_service.dart';
import '../services/firestore_rest_service.dart';
import '../services/firestore_transaction_service.dart';
import '../services/offline_firestore_service.dart';
import '../services/historical_catalogue_resolver.dart';
import '../services/outlet_placement_backfill.dart';

class VariantBatchPriceOption {
  const VariantBatchPriceOption({
    required this.batchId,
    required this.internalBatchNo,
    required this.availableQty,
    required this.sellingPricePaise,
    required this.mrpPaise,
    this.purchaseRatePaise = 0,
    this.purchaseId,
    this.supplierLotNo,
    this.expiryDate,
  });

  final String batchId;
  final String internalBatchNo;
  final int availableQty;
  final int sellingPricePaise;
  final int mrpPaise;
  final int purchaseRatePaise;
  final String? purchaseId;
  final String? supplierLotNo;
  final DateTime? expiryDate;
}

class ProductRepository {
  ProductRepository(
    this.firestore,
    this.transactions, {
    @visibleForTesting this.allowUnapprovedIsolatedCatalogueForTests = false,
  }) : assert(!allowUnapprovedIsolatedCatalogueForTests || kDebugMode);
  final FirestoreDataService firestore;
  final FirestoreTransactionService transactions;

  Future<void> updateVariantPricing({
    required String tenantId,
    required String businessId,
    required String productId,
    required String variantId,
    required int sellingPrice,
    required int mrp,
    required int gstRateBps,
    required String actorUid,
    required String token,
    bool makeDefaultForProduct = false,
  }) async {
    final fields = <String, dynamic>{
      'sellingPrice': sellingPrice,
      'mrp': mrp,
      'defaultGstRateBps': gstRateBps,
      'updatedBy': actorUid,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await firestore.patchDocument(
      FirebaseConstants.productVariants,
      variantId,
      fields,
      idToken: token,
    );
    if (makeDefaultForProduct) {
      await firestore.patchDocument(FirebaseConstants.products, productId, {
        'sellingPrice': sellingPrice,
        'mrp': mrp,
        'updatedBy': actorUid,
      }, idToken: token);
    }
  }

  /// Test-only approval policy switch. Full compiler, manifest, fingerprint,
  /// profile and template validation still runs; production callers must leave
  /// this false and isolated fixture approval flags remain unchanged.
  @visibleForTesting
  final bool allowUnapprovedIsolatedCatalogueForTests;

  /// Receipt history is read directly from the active account's SQLite cache.
  /// Draft purchase batches are excluded by their receipt status and quantity.
  Future<bool> variantHasReceivedInventory({
    required String token,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String variantId,
  }) async {
    final received = await variantsWithReceivedInventory(
      token: token,
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
    );
    return received.contains(variantId);
  }

  Future<Set<String>> variantsWithReceivedInventory({
    required String token,
    required String tenantId,
    required String businessId,
    required String outletId,
  }) async {
    final source = firestore;
    if (source is! OfflineFirestoreService) return const {};
    final local = await source.localDataSourceForToken(token);
    final rows = await local.db.query(
      'local_inventory_batches',
      columns: ['payloadJson'],
      where: 'isDeleted=0 AND tenantId=? AND businessId=? AND outletId=?',
      whereArgs: [tenantId, businessId, outletId],
    );
    final receivedVariants = <String>{};
    for (final row in rows) {
      final payload = jsonDecode(row['payloadJson'] as String);
      if (payload is! Map) continue;
      final data = FirestoreRestService.decodeFields(
        Map<String, dynamic>.from(payload),
      );
      final quantity = (data['receivedQty'] as num?)?.toDouble() ?? 0;
      final status = (data['status'] as String? ?? '').toUpperCase();
      final variantId = data['variantId'];
      if (variantId is String &&
          variantId.isNotEmpty &&
          data['isDeleted'] != true &&
          data['isDeleted'] != 1 &&
          quantity > 0 &&
          !const {'PENDING_RECEIPT', 'DELETED', 'VOID'}.contains(status)) {
        receivedVariants.add(variantId);
      }
    }
    return receivedVariants;
  }

  Future<Map<String, ({int mrp, int sellingPrice})>> receivedVariantPricing({
    required String token,
    required String tenantId,
    required String businessId,
    required String outletId,
  }) async {
    final source = firestore;
    if (source is! OfflineFirestoreService) return const {};
    final local = await source.localDataSourceForToken(token);
    final rows = await local.db.query(
      'local_inventory_batches',
      columns: ['payloadJson'],
      where: 'isDeleted=0 AND tenantId=? AND businessId=? AND outletId=?',
      whereArgs: [tenantId, businessId, outletId],
    );
    final pricing = <String, ({int mrp, int sellingPrice})>{};
    for (final row in rows) {
      final payload = jsonDecode(row['payloadJson'] as String);
      if (payload is! Map) continue;
      final data = FirestoreRestService.decodeFields(
        Map<String, dynamic>.from(payload),
      );
      final quantity = (data['receivedQty'] as num?)?.toDouble() ?? 0;
      final status = (data['status'] as String? ?? '').toUpperCase();
      final variantId = data['variantId'];
      if (variantId is! String ||
          variantId.isEmpty ||
          data['isDeleted'] == true ||
          data['isDeleted'] == 1 ||
          quantity <= 0 ||
          const {'PENDING_RECEIPT', 'DELETED', 'VOID'}.contains(status)) {
        continue;
      }
      final mrp = (data['mrp'] as num?)?.toInt() ?? 0;
      final sellingPrice = (data['sellingPrice'] as num?)?.toInt() ?? 0;
      final availableQty = (data['availableQty'] as num?)?.toDouble() ?? 0;

      final existing = pricing[variantId];
      if (existing == null) {
        if (mrp > 0 || sellingPrice > 0) {
          pricing[variantId] = (mrp: mrp, sellingPrice: sellingPrice);
        }
      } else if (availableQty > 0 && (mrp > 0 || sellingPrice > 0)) {
        pricing[variantId] = (mrp: mrp, sellingPrice: sellingPrice);
      }
    }
    return pricing;
  }

  Future<List<VariantBatchPriceOption>> loadVariantBatches({
    required String token,
    required String tenantId,
    required String businessId,
    required String outletId,
    required String variantId,
  }) async {
    final source = firestore;
    if (source is! OfflineFirestoreService) {
      final docs = await firestore.queryDocuments(
        collection: FirebaseConstants.inventoryBatches,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
          FirestoreFilter('outletId', 'EQUAL', outletId),
          FirestoreFilter('variantId', 'EQUAL', variantId),
        ],
        idToken: token,
      );
      final list = <VariantBatchPriceOption>[];
      for (final doc in docs) {
        final data = FirestoreRestService.decodeFields(doc['fields']);
        final status = (data['status'] as String? ?? '').toUpperCase();
        if (data['isDeleted'] == true ||
            const {'PENDING_RECEIPT', 'DELETED', 'VOID'}.contains(status)) {
          continue;
        }
        final availableQty = (data['availableQty'] as num?)?.toInt() ?? 0;
        if (availableQty <= 0) continue;
        list.add(
          VariantBatchPriceOption(
            batchId: data['batchId']?.toString() ??
                doc['name']?.toString().split('/').last ??
                '',
            internalBatchNo: data['internalBatchNo']?.toString() ??
                data['batchId']?.toString() ??
                '',
            availableQty: availableQty,
            sellingPricePaise: (data['sellingPrice'] as num?)?.toInt() ?? 0,
            mrpPaise: (data['mrp'] as num?)?.toInt() ?? 0,
            purchaseRatePaise: (data['purchaseRate'] as num?)?.toInt() ?? 0,
            purchaseId: data['purchaseId']?.toString(),
            supplierLotNo: data['supplierLotNo']?.toString(),
            expiryDate: data['expiryDate'] is DateTime
                ? data['expiryDate'] as DateTime
                : DateTime.tryParse(data['expiryDate']?.toString() ?? ''),
          ),
        );
      }
      return list;
    }

    final local = await source.localDataSourceForToken(token);
    final rows = await local.db.query(
      'local_inventory_batches',
      columns: ['payloadJson'],
      where:
          'isDeleted=0 AND tenantId=? AND businessId=? AND outletId=? AND variantId=?',
      whereArgs: [tenantId, businessId, outletId, variantId],
    );
    final list = <VariantBatchPriceOption>[];
    for (final row in rows) {
      final payload = jsonDecode(row['payloadJson'] as String);
      if (payload is! Map) continue;
      final data = FirestoreRestService.decodeFields(
        Map<String, dynamic>.from(payload),
      );
      final status = (data['status'] as String? ?? '').toUpperCase();
      if (data['isDeleted'] == true ||
          data['isDeleted'] == 1 ||
          const {'PENDING_RECEIPT', 'DELETED', 'VOID'}.contains(status)) {
        continue;
      }
      final availableQty = (data['availableQty'] as num?)?.toInt() ?? 0;
      if (availableQty <= 0) continue;

      list.add(
        VariantBatchPriceOption(
          batchId: data['batchId']?.toString() ?? '',
          internalBatchNo: data['internalBatchNo']?.toString() ??
              data['batchId']?.toString() ??
              '',
          availableQty: availableQty,
          sellingPricePaise: (data['sellingPrice'] as num?)?.toInt() ?? 0,
          mrpPaise: (data['mrp'] as num?)?.toInt() ?? 0,
          purchaseRatePaise: (data['purchaseRate'] as num?)?.toInt() ?? 0,
          purchaseId: data['purchaseId']?.toString(),
          supplierLotNo: data['supplierLotNo']?.toString(),
          expiryDate: data['expiryDate'] is DateTime
              ? data['expiryDate'] as DateTime
              : DateTime.tryParse(data['expiryDate']?.toString() ?? ''),
        ),
      );
    }
    return list;
  }


  static const _internalBarcodeStart = 700000000001;

  int _nextInternalBarcodeNumber(Iterable<Map<String, dynamic>> documents) {
    var next = _internalBarcodeStart;
    for (final document in documents) {
      final fields = FirestoreRestService.decodeFields(document['fields']);
      final raw = fields['barcode'];
      if (raw is! String || !RegExp(r'^\d{12}$').hasMatch(raw)) continue;
      final number = int.tryParse(raw);
      if (number != null && number >= next) next = number + 1;
    }
    if (next > 999999999999) {
      throw const AppException('The internal barcode range is exhausted.');
    }
    return next;
  }

  String _formatInternalBarcode(int number) {
    if (number < _internalBarcodeStart || number > 999999999999) {
      throw const AppException('The internal barcode range is exhausted.');
    }
    return number.toString().padLeft(12, '0');
  }

  Future<List<CentralProductMaster>> searchCentralProductMaster({
    required String query,
    required String businessTypeId,
    required String businessSubTypeId,
  }) async {
    final source = firestore;
    if (source is! OfflineFirestoreService) {
      throw const AppException(
        'Product autocomplete requires the local product catalogue.',
        code: 'local-catalogue-unavailable',
      );
    }
    return source.searchCentralProductMaster(
      query: query,
      businessTypeId: businessTypeId,
      businessSubTypeId: businessSubTypeId,
    );
  }

  Future<HistoricalCatalogueResolution> resolveHistoricalProductMetadata({
    required ProductModel product,
    required String token,
    CatalogueResolutionContext context =
        CatalogueResolutionContext.readExisting,
  }) async {
    if (context == CatalogueResolutionContext.createCanonical) {
      throw ArgumentError(
        'Historical metadata must never be used for canonical Product creation.',
      );
    }
    final source = firestore;
    if (source is! OfflineFirestoreService) {
      return HistoricalCatalogueResolution(
        status: CatalogueResolutionStatus.archiveNotFound,
        context: context,
        fingerprint: product.catalogueFingerprint,
        productFields: product.toData(),
      );
    }
    final local = await source.localDataSourceForToken(token);
    return HistoricalCatalogueResolver(local.db)
        .resolveProduct(product.toData(), context: context);
  }

  Future<List<ProductMasterValue>> getEligibleCategories({
    required String tenantId,
    required String businessId,
    required String token,
    String businessTypeId = 'HARDWARE',
    String businessSubTypeId = 'PAINTS',
  }) async {
    final selectionResolver = CatalogueSelectionResolver(firestore);
    return selectionResolver.getEligibleCategories(
      tenantId: tenantId,
      businessId: businessId,
      token: token,
      businessTypeId: businessTypeId,
      businessSubTypeId: businessSubTypeId,
    );
  }

  Future<List<ProductMasterValue>> getEligibleSubcategories({
    required String tenantId,
    required String businessId,
    required String categoryId,
    required String token,
    String businessTypeId = 'HARDWARE',
    String businessSubTypeId = 'PAINTS',
  }) async {
    final selectionResolver = CatalogueSelectionResolver(firestore);
    return selectionResolver.getEligibleSubcategories(
      tenantId: tenantId,
      businessId: businessId,
      categoryId: categoryId,
      token: token,
      businessTypeId: businessTypeId,
      businessSubTypeId: businessSubTypeId,
    );
  }

  Future<List<ProductMasterValue>> getMasterValues({
    required String tenantId,
    required String businessId,
    required String masterType,
    required String token,
    String? categoryId,
    bool includeInactive = false,
  }) async {
    final type = masterType.toUpperCase();
    final collection = _masterCollection(type);
    final filters = <FirestoreFilter>[
      FirestoreFilter('tenantId', 'EQUAL', tenantId),
      FirestoreFilter('businessId', 'EQUAL', businessId),
    ];
    if (!includeInactive) {
      filters.add(FirestoreFilter('status', 'EQUAL', 'ACTIVE'));
    }
    if (type == 'SUBCATEGORY' && categoryId != null) {
      filters.add(FirestoreFilter('categoryId', 'EQUAL', categoryId));
    }
    if (_isOptionType(type)) {
      filters.add(FirestoreFilter('type', 'EQUAL', type));
    }
    final docs = await firestore.queryDocuments(
      collection: collection,
      filters: filters,
      idToken: token,
    );
    final systemDocs = await firestore.queryDocuments(
      collection: collection,
      filters: [
        FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM'),
        FirestoreFilter('status', 'EQUAL', 'ACTIVE'),
        if (type == 'SUBCATEGORY' && categoryId != null)
          FirestoreFilter('categoryId', 'EQUAL', categoryId),
        if (_isOptionType(type)) FirestoreFilter('type', 'EQUAL', type),
      ],
      idToken: token,
    );
    final merged = <String, ProductMasterValue>{};
    for (final doc in systemDocs) {
      final d = FirestoreRestService.decodeFields(doc['fields']);
      final id =
          d[_masterIdField(type)] as String? ??
          (doc['name'] as String).split('/').last;
      merged[id] = ProductMasterValue(
        id: id,
        name: _masterName(type, d),
        status: 'ACTIVE',
        scopeType: 'SYSTEM',
        categoryId: d['categoryId'] as String?,
        measurementDimension:
            (d['measurementDimension'] ?? d['dimension']) as String?,
      );
    }
    final businessValues = [
      for (final doc in docs)
        () {
          final id = (doc['name'] as String? ?? '').split('/').last;
          final data = FirestoreRestService.decodeFields(doc['fields']);
          final name = _masterName(type, data);
          return ProductMasterValue(
            id: data[_masterIdField(type)] as String? ?? id,
            name: name,
            code:
                data['code'] as String? ??
                data['shadeCode'] as String? ??
                data['hsnCode'] as String?,
            status: data['status'] as String? ?? 'ACTIVE',
            categoryId: data['categoryId'] as String?,
            type: data['type'] as String?,
            measurementDimension:
                (data['measurementDimension'] ?? data['dimension']) as String?,
            applicableAttributes: _stringList(data['applicableAttributes']),
          );
        }(),
    ];
    for (final v in businessValues) {
      merged[v.id] = v;
    }
    // Keep business records intact; prefer the canonical SYSTEM choice when
    // the same display name exists in both scopes.
    final choices = <String, ProductMasterValue>{};
    for (final value in merged.values) {
      final key = value.name
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      final previous = choices[key];
      final isCanonicalSystemSubcategory =
          type == 'SUBCATEGORY' &&
          value.scopeType == 'SYSTEM' &&
          value.id.startsWith('SYS_SUBCATEGORY_SYS_CATEGORY_');
      final previousIsCanonicalSystemSubcategory =
          previous != null &&
          type == 'SUBCATEGORY' &&
          previous.scopeType == 'SYSTEM' &&
          previous.id.startsWith('SYS_SUBCATEGORY_SYS_CATEGORY_');
      if (previous == null ||
          (value.scopeType == 'SYSTEM' && previous.scopeType != 'SYSTEM') ||
          (isCanonicalSystemSubcategory &&
              !previousIsCanonicalSystemSubcategory)) {
        choices[key] = value;
      }
    }
    return choices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<ResolvedProductTemplate> resolveTemplate({
    required String tenantId,
    required String businessId,
    required String subcategoryId,
    required String token,
  }) async {
    final resolver = ProductTemplateResolver(firestore);
    return resolver.resolveTemplate(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: subcategoryId,
      token: token,
    );
  }

  Future<List<ProductAttribute>> loadTemplate({
    required String tenantId,
    required String businessId,
    required String subcategoryId,
    required String token,
  }) async {
    final resolved = await resolveTemplate(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: subcategoryId,
      token: token,
    );
    return resolved.attributes;
  }

  Future<String> createAttributeOption({
    required String tenantId,
    required String businessId,
    required String attributeId,
    required String name,
    required String actorUid,
    required String token,
  }) async {
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw const AppException('Enter an option name.');
    for (final scope in ['SYSTEM', 'BUSINESS']) {
      final options = await firestore.queryDocuments(
        collection: FirebaseConstants.productAttributeOptions,
        filters: [
          FirestoreFilter('attributeId', 'EQUAL', attributeId),
          FirestoreFilter('scopeType', 'EQUAL', scope),
          if (scope == 'BUSINESS') ...[
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
          ],
        ],
        idToken: token,
      );
      for (final option in options) {
        final data = FirestoreRestService.decodeFields(option['fields']);
        final existingName = (data['name'] as String? ?? '').trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        if (existingName.toLowerCase() == clean.toLowerCase()) {
          if (data['status'] != 'ACTIVE') {
            throw const AppException(
              'This option already exists but is inactive. Activate it in master data.',
            );
          }
          return existingName;
        }
      }
    }
    final id = _masterDocumentId(
      '${tenantId}_${businessId}_OPTION',
      clean.toLowerCase(),
      attributeId,
    );
    await transactions.runAtomicOperation((tx) async {
      final existing = await tx.get(
        FirebaseConstants.productAttributeOptions,
        id,
      );
      if (existing.exists) return;
      final now = DateTime.now().toUtc();
      tx.create(FirebaseConstants.productAttributeOptions, id, {
        'optionId': id,
        'attributeId': attributeId,
        'name': clean,
        'normalizedName': clean.toLowerCase(),
        'scopeType': 'BUSINESS',
        'tenantId': tenantId,
        'businessId': businessId,
        'status': 'ACTIVE',
        'createdBy': actorUid,
        'createdAt': now,
        'updatedBy': actorUid,
        'updatedAt': now,
      });
    }, idToken: token);
    return clean;
  }

  Future<void> configureBusinessAttribute({
    required String tenantId,
    required String businessId,
    required String subcategoryId,
    required String actorUid,
    required String token,
    required Map<String, dynamic> definition,
  }) async {
    final name = (definition['name'] as String? ?? '').trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (name.isEmpty ||
        !{
          'TEXT',
          'NUMBER',
          'SELECT',
          'MULTI_SELECT',
          'BOOLEAN',
        }.contains(definition['dataType']) ||
        !{'PRODUCT', 'VARIANT'}.contains(definition['attributeLevel'])) {
      throw const AppException('Check attribute name, type and level.');
    }
    final id =
        definition['attributeId'] as String? ??
        _masterDocumentId(
          '${tenantId}_${businessId}_ATTRIBUTE',
          name.toLowerCase(),
          null,
        );
    final templateId = _masterDocumentId(
      '${tenantId}_${businessId}_TEMPLATE',
      id,
      subcategoryId,
    );
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((tx) async {
      final attribute = await tx.get(FirebaseConstants.productAttributes, id);
      final template = await tx.get(
        FirebaseConstants.subcategoryAttributeTemplates,
        templateId,
      );
      final systemAttribute = attribute.fields['scopeType'] == 'SYSTEM';
      if (attribute.exists &&
          !systemAttribute &&
          (attribute.fields['tenantId'] != tenantId ||
              attribute.fields['businessId'] != businessId)) {
        throw const AppException('System attributes are read-only.');
      }
      final audit = {
        'scopeType': 'BUSINESS',
        'tenantId': tenantId,
        'businessId': businessId,
        'updatedBy': actorUid,
        'updatedAt': now,
      };
      final fields = {
        ...audit,
        'attributeId': id,
        'name': name,
        'code': id,
        'normalizedName': name.toLowerCase(),
        'dataType': definition['dataType'],
        'allowMultiple': definition['dataType'] == 'MULTI_SELECT',
        'allowAddNewOption': true,
        'options': definition['options'] ?? [],
        'status': 'ACTIVE',
      };
      if (systemAttribute) {
        // Store only the business template override; central definition is immutable.
      } else if (attribute.exists) {
        tx.update(
          FirebaseConstants.productAttributes,
          id,
          fields,
          updateTime: attribute.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.productAttributes, id, {
          ...fields,
          'createdBy': actorUid,
          'createdAt': now,
        });
      }
      final config = {
        ...audit,
        'templateId': templateId,
        'subcategoryId': subcategoryId,
        'attributeId': id,
        'attributeLevel': definition['attributeLevel'],
        'required': definition['required'] == true,
        'defaultValue': definition['defaultValue'],
        'sortOrder': definition['sortOrder'] ?? 100,
        'status': 'ACTIVE',
      };
      if (template.exists) {
        tx.update(
          FirebaseConstants.subcategoryAttributeTemplates,
          templateId,
          config,
          updateTime: template.updateTime,
        );
      } else {
        tx.create(FirebaseConstants.subcategoryAttributeTemplates, templateId, {
          ...config,
          'createdBy': actorUid,
          'createdAt': now,
        });
      }
    }, idToken: token);
  }

  Future<ProductMasterValue> createMasterValue({
    required String tenantId,
    required String businessId,
    required String masterType,
    required String name,
    required String actorUid,
    required String token,
    String? categoryId,
    String? code,
    List<String> applicableAttributes = const [],
  }) async {
    final type = masterType.toUpperCase();
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (tenantId.isEmpty || businessId.isEmpty || cleanName.isEmpty) {
      throw const AppException('Enter a valid master value.');
    }
    if (type == 'SUBCATEGORY' && (categoryId == null || categoryId.isEmpty)) {
      throw const AppException(
        'Select a Category before adding a Subcategory.',
      );
    }
    final normalized = cleanName.toLowerCase();
    final available = await getMasterValues(
      tenantId: tenantId,
      businessId: businessId,
      masterType: type,
      token: token,
      categoryId: categoryId,
    );
    if (available.any((v) => v.name.trim().toLowerCase() == normalized)) {
      throw const AppException(
        'This value already exists. Select it from the list.',
      );
    }
    final generatedId = _masterDocumentId(
      '${tenantId}_${businessId}_$type',
      normalized,
      categoryId,
    );
    final brandSlug = cleanName
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final readableBrand = brandSlug.isEmpty ? 'BRAND' : brandSlug;
    final id = type == 'BRAND'
        ? 'PM_BRAND_${readableBrand.substring(0, readableBrand.length > 64 ? 64 : readableBrand.length)}_${generatedId.substring(3)}'
        : generatedId;
    final keyField = _masterIdField(type);
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((tx) async {
      final existing = await tx.get(_masterCollection(type), id);
      if (existing.exists) {
        throw const AppException(
          'This value already exists. Select it from the list.',
        );
      }
      tx.create(_masterCollection(type), id, {
        keyField: id,
        'scopeType': 'BUSINESS',
        'tenantId': tenantId,
        'businessId': businessId,
        'name': cleanName,
        'normalizedName': normalized,
        'status': 'ACTIVE',
        if (type == 'SUBCATEGORY') 'categoryId': categoryId,
        if (type == 'CATEGORY') 'applicableAttributes': applicableAttributes,
        if (_isOptionType(type)) 'type': type,
        if (code?.trim().isNotEmpty == true) 'code': code!.trim(),
        'createdBy': actorUid,
        'createdAt': now,
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': 1,
      });
    }, idToken: token);
    return ProductMasterValue(
      id: id,
      name: cleanName,
      status: 'ACTIVE',
      code: code?.trim(),
      categoryId: categoryId,
      type: type,
      applicableAttributes: applicableAttributes,
    );
  }

  String _masterCollection(String type) => switch (type) {
    'BRAND' => FirebaseConstants.brands,
    'CATEGORY' => FirebaseConstants.productCategories,
    'SUBCATEGORY' => FirebaseConstants.productSubcategories,
    'SHADE' => FirebaseConstants.shades,
    'PACK_SIZE' => FirebaseConstants.packSizes,
    'UNIT' => FirebaseConstants.units,
    'HSN' => FirebaseConstants.hsnCodes,
    _ => FirebaseConstants.productClassificationOptions,
  };

  String _masterName(String type, Map<String, dynamic> data) {
    final specificField = switch (type) {
      'BRAND' => 'brandName',
      'CATEGORY' => 'categoryName',
      'SUBCATEGORY' => 'subcategoryName',
      'SHADE' => 'shadeName',
      'PACK_SIZE' => 'packSize',
      'UNIT' => 'unitName',
      'HSN' => 'hsnCode',
      _ => 'optionName',
    };
    return data['name'] as String? ??
        data['label'] as String? ??
        data[specificField] as String? ??
        '';
  }

  String _masterIdField(String type) => switch (type) {
    'BRAND' => 'brandId',
    'CATEGORY' => 'categoryId',
    'SUBCATEGORY' => 'subcategoryId',
    'SHADE' => 'shadeId',
    'PACK_SIZE' => 'packSizeId',
    'UNIT' => 'unitId',
    'HSN' => 'hsnCodeId',
    _ => 'optionId',
  };

  bool _isOptionType(String type) => const {
    'USAGE',
    'SURFACE',
    'SEGMENT',
    'FINISH',
    'COLOUR_FAMILY',
    'BASE_TYPE',
    'DILUTION_TYPE',
    'NUMBER_OF_COATS',
  }.contains(type);

  static String masterDocumentId(
    String type,
    String normalized,
    String? parentId,
  ) {
    final source = '${type}_${parentId ?? ''}_$normalized';
    var hashA = 0x811c9dc5;
    var hashB = 0x9e3779b9;
    for (final unit in source.codeUnits) {
      hashA = ((hashA ^ unit) * 0x01000193) & 0xffffffff;
      hashB = ((hashB ^ (unit + 0x9e37)) * 0x85ebca6b) & 0xffffffff;
    }
    return 'PM_${type}_${hashA.toRadixString(16)}${hashB.toRadixString(16)}';
  }

  static String productUniquenessId({
    required String tenantId,
    required String businessId,
    required String normalizedName,
    String? brandId,
  }) =>
      masterDocumentId(
        '${tenantId}_${businessId}_PRODUCT',
        normalizedName,
        brandId,
      );

  String _masterDocumentId(String type, String normalized, String? parentId) =>
      masterDocumentId(type, normalized, parentId);


  // The business-wide Product Management dataset is shared by the table and
  // its KPIs. SQLite tombstones are already excluded by LocalDataSource.query;
  // payload soft deletion must also be checked (a pending UPDATE is not a
  // SQLite tombstone). Synchronization state does not affect membership.
  bool _validProductRecord(
    Map<String, dynamic> data,
    String tenantId,
    String businessId,
  ) =>
      data['tenantId'] == tenantId &&
      data['businessId'] == businessId &&
      (data['status'] as String? ?? 'ACTIVE').trim().toUpperCase() !=
          'DELETED' &&
      data['isDeleted'] != true &&
      data['isDeleted'] != 1;

  Future<List<ProductModel>> getProducts({
    required String tenantId,
    required String businessId,
    required String token,
  }) async {
    final results = await Future.wait([
      firestore.queryDocuments(
        collection: FirebaseConstants.products,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
        ],
        idToken: token,
      ),
      firestore.queryDocuments(
        collection: FirebaseConstants.productVariants,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
        ],
        idToken: token,
      ),
    ]);
    final families = <String, ProductModel>{};
    final productData = <String, Map<String, dynamic>>{};
    for (final doc in results[0]) {
      final id = (doc['name'] as String? ?? '').split('/').last;
      final data = FirestoreRestService.decodeFields(doc['fields']);
      if (!_validProductRecord(data, tenantId, businessId) ||
          (data['productName'] as String? ?? data['name'] as String? ?? '')
              .trim()
              .isEmpty) {
        continue;
      }
      final productId = data['productId'] as String? ?? id;
      productData[productId] = data;
      families[productId] = ProductModel(
        attributeValues: {
          if (data['usageIds'] != null) 'usage': data['usageIds'],
          if (data['surfaceIds'] != null) 'surface': data['surfaceIds'],
          for (final k in ['segment', 'numberOfCoats', 'dilutionType'])
            if (data['${k}Id'] != null || data[k] != null)
              k: data['${k}Id'] ?? data[k],
          ...Map<String, dynamic>.from(data['attributeValues'] as Map? ?? {})
            ..remove('hsnCode'),
        },
        productId: productId,
        tenantId: data['tenantId'] as String? ?? tenantId,
        businessId: data['businessId'] as String? ?? businessId,
        name: data['productName'] as String? ?? data['name'] as String? ?? '',
        status: data['status'] as String? ?? 'ACTIVE',
        brand: data['brand'] as String?,
        brandId: data['brandId'] as String?,
        category:
            data['categoryName'] as String? ?? data['category'] as String?,
        categoryId: data['categoryId'] as String?,
        subcategory: data['subcategory'] as String?,
        subcategoryId: data['subcategoryId'] as String?,
        description: data['description'] as String?,
        baseUnitId: data['baseUnitId'] as String?,
        hsnCode: (data['hsnCode'] as String?)?.trim().isNotEmpty == true
            ? data['hsnCode'] as String
            : (data['attributeValues'] as Map?)?['hsnCode'] as String?,
        defaultGstRateBps: (data['defaultGstRateBps'] as num?)?.toInt() ?? 0,
        createdAt: data['createdAt'] as DateTime?,
        updatedAt: data['updatedAt'] as DateTime?,
        productCode: data['productCode'] as String?,
        usageIds: _stringList(data['usageIds']),
        surfaceIds: _stringList(data['surfaceIds']),
        segmentId: data['segmentId'] as String?,
        finishId: data['finishId'] as String?,
        hsnCodeId: data['hsnCodeId'] as String?,
        numberOfCoats: (data['numberOfCoats'] as num?)?.toInt(),
        dilutionTypeId: data['dilutionTypeId'] as String?,
        productImage: ProductModel.parseProductImage(data),
        catalogueFingerprint: data['catalogueFingerprint'] as String?,
        quantitySlabs: (data['quantitySlabs'] as List?)
            ?.whereType<Map>()
            .map((e) => QuantityDiscountSlab.fromData(Map<String, dynamic>.from(e)))
            .toList() ??
            const [],
        syncStatus: doc['localSyncStatus'] as String? ?? 'SYNCED',
      );
    }
    final variants = <String, List<ProductVariantModel>>{};
    final parentsWithStoredVariants = <String>{};
    final seenVariantIds = <String>{};
    for (final doc in results[1]) {
      final id = (doc['name'] as String? ?? '').split('/').last;
      final data = FirestoreRestService.decodeFields(doc['fields']);
      // Even deleted explicit variants prevent inventing a legacy default.
      if (data['productId'] is String) {
        parentsWithStoredVariants.add(data['productId'] as String);
      }
      if (!_validProductRecord(data, tenantId, businessId)) continue;
      final parent = families[data['productId']];
      if (parent == null) continue; // Orphan, deleted or outside this business.
      final variantId = data['variantId'] as String? ?? id;
      if (!seenVariantIds.add(variantId)) continue;
      final model = ProductVariantModel.fromData(id, {
        ...data,
        if (parent.hsnCode != null) 'hsnCode': parent.hsnCode,
        if (data['defaultGstRate'] == null && data['defaultGstRateBps'] == null)
          'defaultGstRateBps': parent.defaultGstRateBps,
      });
      final parentId = parent.productId;
      variants.putIfAbsent(parentId, () => []).add(model);
    }
    // Older catalog records may store the sellable product directly in
    // `products` without a separate `product_variants` document. Keep those
    // records selectable in Purchase and visible in Product Management.
    for (final entry in families.entries) {
      if (variants[entry.key]?.isNotEmpty == true ||
          parentsWithStoredVariants.contains(entry.key)) {
        continue;
      }
      final data = productData[entry.key]!;
      // Only legacy product records with selling-unit metadata represent a
      // sellable variant themselves. A modern master without variants is zero.
      final unit = data['baseUnitId'] ?? data['unitId'];
      final legacySellable =
          data['productId'] == null || data['variantId'] == entry.key;
      if (!legacySellable || unit is! String || unit.trim().isEmpty) continue;
      variants[entry.key] = [
        ProductVariantModel.fromData(entry.key, {
          ...data,
          'productId': entry.key,
          'productName': entry.value.name,
          'variantName': data['variantName'] ?? 'Default',
        }),
      ];
    }
    final historicalResolutions = <String, HistoricalCatalogueResolution>{};
    final offlineFirestore = firestore;
    if (offlineFirestore is OfflineFirestoreService) {
      final local = await offlineFirestore.localDataSourceForToken(token);
      final resolver = HistoricalCatalogueResolver(local.db);
      for (final entry in families.entries) {
        historicalResolutions[entry.key] = await resolver.resolveProduct(
          entry.value.toData(),
          context: CatalogueResolutionContext.readExisting,
        );
      }
    }
    return [
      for (final entry in families.entries)
        ProductModel(
          attributeValues: entry.value.attributeValues,
          productId: entry.value.productId,
          tenantId: entry.value.tenantId,
          businessId: entry.value.businessId,
          name: entry.value.name,
          status: entry.value.status,
          brand: entry.value.brand,
          brandId: entry.value.brandId,
          category: entry.value.category,
          categoryId: entry.value.categoryId,
          subcategory: entry.value.subcategory,
          subcategoryId: entry.value.subcategoryId,
          description: entry.value.description,
          baseUnitId: entry.value.baseUnitId,
          hsnCode: entry.value.hsnCode,
          defaultGstRateBps: entry.value.defaultGstRateBps,
          createdAt: entry.value.createdAt,
          updatedAt: entry.value.updatedAt,
          variants: variants[entry.key] ?? const [],
          quantitySlabs: entry.value.quantitySlabs,
          productCode: entry.value.productCode,
          usageIds: entry.value.usageIds,
          surfaceIds: entry.value.surfaceIds,
          segmentId: entry.value.segmentId,
          finishId: entry.value.finishId,
          hsnCodeId: entry.value.hsnCodeId,
          numberOfCoats: entry.value.numberOfCoats,
          dilutionTypeId: entry.value.dilutionTypeId,
          productImage: entry.value.productImage,
          catalogueFingerprint: entry.value.catalogueFingerprint,
          historicalCatalogueResolution: historicalResolutions[entry.key],
          syncStatus: entry.value.syncStatus,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Placement records for one outlet (or every outlet of the business when
  /// [outletId] is null). Reads SQLite only when backed by [OfflineFirestoreService].
  Future<List<OutletProductModel>> getOutletPlacements({
    required String tenantId,
    required String businessId,
    required String token,
    String? outletId,
    bool activeOnly = true,
  }) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.outletProducts,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (outletId != null) FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    final placements = <String, OutletProductModel>{};
    for (final doc in docs) {
      final id = (doc['name'] as String? ?? '').split('/').last;
      final data = FirestoreRestService.decodeFields(doc['fields']);
      if (data['tenantId'] != tenantId ||
          data['businessId'] != businessId ||
          (outletId != null && data['outletId'] != outletId) ||
          data['isDeleted'] == true) {
        continue;
      }
      final placement = OutletProductModel.fromData(id, data);
      if (placement.productId.isEmpty ||
          placement.outletId.isEmpty ||
          activeOnly && !placement.isActive) {
        continue;
      }
      placements[id] = placement;
    }
    return placements.values.toList();
  }

  /// Outlet view: products with an ACTIVE placement at [outletId] (or all
  /// placed products when [activeOnly] is false).
  Future<List<ProductModel>> getOutletProducts({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
    bool activeOnly = true,
  }) async {
    if (outletId.trim().isEmpty) {
      throw const AppException('Select an Outlet to view its Products.');
    }
    final placements = <String, OutletProductModel>{};
    for (final p in await getOutletPlacements(
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
      token: token,
      activeOnly: activeOnly,
    )) {
      final existing = placements[p.productId];
      if (existing == null || (!existing.isActive && p.isActive)) {
        placements[p.productId] = p;
      }
    }
    if (placements.isEmpty) return const [];
    final masters = await getProducts(
      tenantId: tenantId,
      businessId: businessId,
      token: token,
    );
    final receivedPricing = await receivedVariantPricing(
      token: token,
      tenantId: tenantId,
      businessId: businessId,
      outletId: outletId,
    );
    return [
      for (final product in masters)
        if (placements[product.productId] case final placement?)
          (() {
            final effectiveStatus =
                !placement.isActive ? 'INACTIVE' : product.status;
            final baseVariants = placement.variantIds == null
                ? product.variants
                : product.variants
                    .where((v) => placement.variantIds!.contains(v.variantId))
                    .toList();
            final effectiveVariants = [
              for (final v in baseVariants)
                (() {
                  final pricing = receivedPricing[v.variantId];
                  if (pricing != null && (v.sellingPrice <= 0 || v.mrp <= 0)) {
                    return v.copyWith(
                      sellingPrice: v.sellingPrice > 0
                          ? v.sellingPrice
                          : pricing.sellingPrice,
                      mrp: v.mrp > 0 ? v.mrp : pricing.mrp,
                    );
                  }
                  return v;
                })(),
            ];
            final effectiveProduct = product.withVariants(effectiveVariants);
            return effectiveStatus != product.status
                ? effectiveProduct.copyWith(status: effectiveStatus)
                : effectiveProduct;
          })(),
    ];
  }

  static String placementBackfillMarker(String tenantId, String businessId) =>
      'outlet_products_backfill_v1:$tenantId:$businessId';

  /// Runs the evidence-only placement migration once per business, after the
  /// local copy of every evidence collection has completed its first sync.
  /// Returns null when it is not applicable yet or already done.
  Future<OutletPlacementBackfillReport?> backfillKnownOutletPlacements({
    required String tenantId,
    required String businessId,
    required String actorUid,
    required String token,
  }) async {
    final source = firestore;
    if (source is! OfflineFirestoreService) return null;
    final marker = placementBackfillMarker(tenantId, businessId);
    if (await source.isMigrationDone(marker)) return null;
    if (!await source.hasCompletedInitialSync(
      tenantId,
      businessId,
      OutletPlacementBackfill.requiredCollections,
    )) {
      return null;
    }
    final report = await OutletPlacementBackfill(firestore, transactions).run(
      tenantId: tenantId,
      businessId: businessId,
      actorUid: actorUid,
      token: token,
    );
    await source.markMigrationDone(marker);
    return report;
  }

  /// Business products with no ACTIVE placement at [outletId]; candidates for
  /// "Add existing business product to this outlet".
  Future<List<ProductModel>> getProductsNotInOutlet({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
  }) async {
    final placed = {
      for (final p in await getOutletPlacements(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        token: token,
      ))
        p.productId,
    };
    final masters = await getProducts(
      tenantId: tenantId,
      businessId: businessId,
      token: token,
    );
    return [
      for (final product in masters)
        if (product.isActive && !placed.contains(product.productId)) product,
    ];
  }

  /// Creates only outlet placements for existing business products. Product and
  /// variant masters are read (to validate) but never written.
  Future<int> assignProductsToOutlet({
    required String tenantId,
    required String businessId,
    required String outletId,
    required List<String> productIds,
    required String token,
    String? actorUid,
  }) async {
    final ids = productIds.toSet().where((id) => id.trim().isNotEmpty).toList();
    if (tenantId.isEmpty || businessId.isEmpty || outletId.isEmpty) {
      throw const AppException('Select an Outlet first.');
    }
    if (ids.isEmpty) return 0;
    return transactions.runAtomicOperation<int>((tx) async {
      final outlet = await tx.get(FirebaseConstants.outlets, outletId);
      if (!outlet.exists ||
          outlet.fields['businessId'] != businessId ||
          (outlet.fields['tenantId'] ?? outlet.fields['ownerUid']) !=
              tenantId) {
        throw const AppException(
          'That Outlet does not belong to this Business.',
        );
      }
      final now = DateTime.now().toUtc();
      var changed = 0;
      for (final productId in ids) {
        final product = await tx.get(FirebaseConstants.products, productId);
        if (!product.exists ||
            !_validProductRecord(product.fields, tenantId, businessId)) {
          throw const AppException(
            'A selected Product is not available in this Business.',
          );
        }
        final placementId = OutletProductModel.documentId(
          tenantId: tenantId,
          businessId: businessId,
          outletId: outletId,
          productId: productId,
        );
        final placement = await tx.get(
          FirebaseConstants.outletProducts,
          placementId,
        );
        if (!placement.exists) {
          tx.create(
            FirebaseConstants.outletProducts,
            placementId,
            OutletProductModel.newPlacementData(
              tenantId: tenantId,
              businessId: businessId,
              outletId: outletId,
              productId: productId,
              now: now,
              source: OutletProductModel.sourceManualAssignment,
              createdBy: actorUid,
            ),
          );
          changed++;
        } else if (!OutletProductModel.fromData(
          placementId,
          placement.fields,
        ).isActive) {
          tx.update(FirebaseConstants.outletProducts, placementId, {
            'status': OutletProductModel.statusActive,
            'isActive': true,
            'updatedAt': now,
          }, updateTime: placement.updateTime);
          changed++;
        }
      }
      return changed;
    }, idToken: token);
  }

  /// Safely deactivates an outlet placement without deleting product or variant masters.
  Future<bool> removeProductFromOutlet({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String productId,
    required String token,
    String? actorUid,
  }) async {
    if (tenantId.isEmpty ||
        businessId.isEmpty ||
        outletId.isEmpty ||
        productId.isEmpty) {
      throw const AppException('Select an Outlet and Product first.');
    }
    return transactions.runAtomicOperation<bool>((tx) async {
      final placementId = OutletProductModel.documentId(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        productId: productId,
      );
      final placement = await tx.get(
        FirebaseConstants.outletProducts,
        placementId,
      );
      if (!placement.exists) return false;
      final current = OutletProductModel.fromData(
        placementId,
        placement.fields,
      );
      if (!current.isActive) return false;
      final now = DateTime.now().toUtc();
      tx.update(FirebaseConstants.outletProducts, placementId, {
        'status': OutletProductModel.statusInactive,
        'isActive': false,
        'updatedAt': now,
        'updatedBy': ?actorUid,
      }, updateTime: placement.updateTime);
      return true;
    }, idToken: token);
  }

  Future<void> createProduct({
    required String tenantId,
    required String businessId,
    required String name,
    required String variantName,
    required String unitId,
    required String actorUid,
    required String token,
    String? outletId,
    String? brand,
    String? category,
    String? subcategory,
    String? description,
    String? sku,
    String? barcode,
    String? hsnCode,
    int gstRateBps = 0,
  }) async {
    final catalogueFingerprint = await _requireInstalledCatalogueFingerprint(
      token,
    );
    final productName = name.trim();
    final nameOfVariant = variantName.trim().isEmpty
        ? 'Default'
        : variantName.trim();
    final source = firestore;
    if (source is OfflineWritePrerequisites) {
      await (source as OfflineWritePrerequisites).ensureProductScopeReady(
        tenantId,
        businessId,
      );
    }
    if (tenantId.isEmpty ||
        businessId.isEmpty ||
        productName.length < 2 ||
        unitId.trim().isEmpty ||
        gstRateBps < 0 ||
        gstRateBps > 2800) {
      throw const AppException(
        'Check the required Product and Variant details.',
      );
    }
    final variants = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    for (final doc in variants) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      if ((data['tenantId'] as String? ?? tenantId) != tenantId) continue;
      if (sku?.trim().isNotEmpty == true &&
          (data['sku'] as String? ?? '').trim().toLowerCase() ==
              sku!.trim().toLowerCase()) {
        throw const AppException(
          'This SKU already exists. Select the existing Product/Variant.',
        );
      }
      if (barcode?.trim().isNotEmpty == true &&
          (data['barcode'] as String? ?? '').trim() == barcode!.trim()) {
        throw const AppException(
          'This barcode already exists. Select the existing Product/Variant.',
        );
      }
    }
    final products = await firestore.queryDocuments(
      collection: FirebaseConstants.products,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    final normalizedName = productName.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedBrand = (brand ?? '').trim().toLowerCase();
    for (final doc in products) {
      final data = FirestoreRestService.decodeFields(doc['fields']);
      if (!_validProductRecord(data, tenantId, businessId)) continue;
      final existingName =
          (data['productName'] as String? ?? data['name'] as String? ?? '')
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      final existingBrand = (data['brand'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (existingName == normalizedName && existingBrand == normalizedBrand) {
        throw const AppException(
          'A Product with this name and brand already exists. Review it and add a Variant there instead.',
        );
      }
    }
    final productId = IdGenerator.create('PROD');
    final variantId = IdGenerator.create('VAR');
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((tx) async {
      final resolvedBarcode =
          _optional(barcode) ??
          _formatInternalBarcode(
            await _reserveSequenceRange(
              tx,
              tenantId: tenantId,
              businessId: businessId,
              type: 'INTERNAL_BARCODE',
              count: 1,
              initialNumber: _nextInternalBarcodeNumber(variants),
              now: now,
            ),
          );
      tx.create(FirebaseConstants.products, productId, {
        'productId': productId,
        'tenantId': tenantId,
        'businessId': businessId,
        'productName': productName,
        'name': productName,
        'brand': _optional(brand),
        'categoryName': _optional(category),
        'subcategory': _optional(subcategory),
        'description': _optional(description),
        'baseUnitId': unitId.trim(),
        'hsnCode': _optional(hsnCode),
        'defaultGstRateBps': gstRateBps,
        'catalogueFingerprint': catalogueFingerprint,
        'status': 'ACTIVE',
        'createdBy': actorUid,
        'createdAt': now,
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': 1,
      });
      tx.create(FirebaseConstants.productVariants, variantId, {
        'variantId': variantId,
        'tenantId': tenantId,
        'businessId': businessId,
        'productId': productId,
        'productName': productName,
        'variantName': nameOfVariant,
        'name': '$productName Â· $nameOfVariant',
        'baseUnitId': unitId.trim(),
        'unitId': unitId.trim(),
        'sku': _optional(sku),
        'barcode': resolvedBarcode,
        'hsnCode': _optional(hsnCode),
        'defaultGstRateBps': gstRateBps,
        'defaultGstRate': gstRateBps,
        'status': 'ACTIVE',
        'createdBy': actorUid,
        'createdAt': now,
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': 1,
      });
      _createPlacement(
        tx,
        tenantId,
        businessId,
        outletId,
        productId,
        now,
        actorUid,
      );
    }, idToken: token);
  }

  /// Places a newly created product at the creating outlet only.
  void _createPlacement(
    FirestoreTransactionContext tx,
    String tenantId,
    String businessId,
    String? outletId,
    String productId,
    DateTime now, [
    String? actorUid,
  ]) {
    if (outletId == null || outletId.trim().isEmpty) return;
    tx.create(
      FirebaseConstants.outletProducts,
      OutletProductModel.documentId(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        productId: productId,
      ),
      OutletProductModel.newPlacementData(
        tenantId: tenantId,
        businessId: businessId,
        outletId: outletId,
        productId: productId,
        now: now,
        source: OutletProductModel.sourceNewProduct,
        createdBy: actorUid,
      ),
    );
  }

  void _validateCommercialFields(Map<String, dynamic> input) {
    final gst = input['defaultGstRateBps'];
    if (gst != null && (gst is! int || gst < 0 || gst > 2800)) {
      throw const AppException('GST must be between 0 and 28%.');
    }
    for (final key in ['sellingPrice', 'purchaseRate', 'mrp']) {
      final value = input[key];
      if (value != null && (value is! int || value < 0)) {
        throw const AppException('Enter valid non-negative prices.');
      }
    }
  }

  Map<String, dynamic> _canonicalProductFields(Map<String, dynamic> input) {
    final fields = Map<String, dynamic>.from(input);
    final attributes = Map<String, dynamic>.from(
      fields['attributeValues'] as Map? ?? {},
    );
    final canonical = (fields['hsnCode'] as String?)?.trim();
    // Explicit empty HSN is removal; only omitted canonical fields use legacy data.
    fields['hsnCode'] = canonical ?? attributes['hsnCode'];
    attributes.remove('hsnCode');
    fields['attributeValues'] = attributes;
    final hsn = fields['hsnCode'] as String?;
    if (hsn != null && hsn.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(hsn)) {
      throw const AppException('HSN / SAC must contain 4 to 8 digits.');
    }
    final gst = fields['defaultGstRateBps'];
    if (gst != null && (gst is! int || gst < 0 || gst > 2800)) {
      throw const AppException('GST must be between 0 and 28%.');
    }
    final parsedImage = ProductModel.parseProductImage(fields);
    if (fields.containsKey('productImage') || fields.containsKey('imageUrl')) {
      final img = parsedImage ?? '';
      fields['productImage'] = img;
      fields['imageUrl'] = img;
    }
    return fields;
  }

  Future<void> _validateBarcodes(
    String tenantId,
    String businessId,
    List<Map<String, dynamic>> variants,
    String token,
  ) async {
    final codes = <String, String?>{};
    for (final v in variants) {
      final barcode = (v['barcode'] as String?)?.trim();
      if (barcode == null || barcode.isEmpty) continue;
      if (codes.containsKey(barcode)) {
        throw const AppException('Each variant needs a different barcode.');
      }
      codes[barcode] = v['variantId'] as String?;
    }
    if (codes.isEmpty) return;
    for (final collection in [
      FirebaseConstants.products,
      FirebaseConstants.productVariants,
    ]) {
      final docs = await firestore.queryDocuments(
        collection: collection,
        filters: [
          FirestoreFilter('tenantId', 'EQUAL', tenantId),
          FirestoreFilter('businessId', 'EQUAL', businessId),
        ],
        idToken: token,
      );
      for (final doc in docs) {
        final data = FirestoreRestService.decodeFields(doc['fields']);
        final barcode = (data['barcode'] as String?)?.trim();
        final id = (doc['name'] as String).split('/').last;
        if (codes.containsKey(barcode) && codes[barcode] != id) {
          throw const AppException(
            'This barcode already belongs to another variant.',
          );
        }
      }
    }
  }

  static void _pruneAttributeValues(
    Map values,
    List<ProductAttribute> template,
    String level, [
    Map? fallback,
  ]) {
    final visible = template
        .where(
          (a) =>
              a.level == level &&
              a.id != 'hsnCode' &&
              a.isVisible(values, fallback),
        )
        .map((a) => a.id)
        .toSet();
    values.removeWhere((key, _) => !visible.contains(key));
  }

  Future<void> createStructuredProduct({
    required String tenantId,
    required String businessId,
    required String productName,
    required String actorUid,
    required String token,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
    String? outletId,
    String businessTypeId = 'HARDWARE',
    String businessSubTypeId = 'PAINTS',
  }) async {
    final catalogueFingerprint = await _requireInstalledCatalogueFingerprint(
      token,
    );
    final source = firestore;
    if (source is OfflineWritePrerequisites) {
      await (source as OfflineWritePrerequisites).ensureProductScopeReady(
        tenantId,
        businessId,
      );
    }

    final validator = ProductValidator(firestore);
    final validationResult = await validator.validateProduct(
      tenantId: tenantId,
      businessId: businessId,
      productName: productName,
      productFields: productFields,
      variants: variants,
      token: token,
      businessTypeId: businessTypeId,
      businessSubTypeId: businessSubTypeId,
      isNew: true,
    );

    if (!validationResult.isValid) {
      throw ProductValidationException(validationResult);
    }
    productFields = _canonicalProductFields(productFields)
      ..removeWhere(
        (k, v) => !{
          'brandId',
          'brand',
          'masterProductId',
          'categoryId',
          'categoryName',
          'subcategoryId',
          'subcategory',
          'attributeValues',
          'productImage',
          'imageUrl',
          'hsnCode',
          'defaultGstRateBps',
          'description',
          'quantitySlabs',
        }.contains(k),
      );
    variants = [
      for (final v in variants)
        (Map<String, dynamic>.from(v)
            ..['attributeValues'] = (Map<String, dynamic>.from(
              v['attributeValues'] as Map? ?? {},
            )..remove('hsnCode')))
          ..removeWhere(
            (k, v) => !{
              'attributeValues',
              'displayName',
              'packSize',
              'packUnitId',
              'commercialUnitId',
              'commercialUnitName',
              'baseQuantityPerCommercialUnit',
              'baseUnitId',
              'unitId',
              'barcode',
              'status',
              'sellingPrice',
              'purchaseRate',
              'mrp',
              'defaultGstRateBps',
              'quantitySlabs',
            }.contains(k),
          ),
    ];
    await _validateBarcodes(tenantId, businessId, variants, token);
    final name = productName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (tenantId.isEmpty ||
        businessId.isEmpty ||
        name.length < 2 ||
        variants.isEmpty) {
      throw const AppException(
        'Enter a Product name and at least one sellable Variant.',
      );
    }
    for (final field in ['brandId', 'categoryId', 'subcategoryId']) {
      if ((productFields[field] as String? ?? '').isEmpty) {
        throw const AppException('Select Brand, Category and Subcategory.');
      }
    }
    final template = await loadTemplate(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: productFields['subcategoryId'] as String,
      token: token,
    );
    if (template.any((a) => a.id == 'hsnCode' && a.required) &&
        (productFields['hsnCode'] as String? ?? '').isEmpty) {
      throw const AppException('HSN / SAC is required.');
    }
    void validate(Map<String, dynamic> values, String level, [Map? fallback]) {
      if (values['colourMode'] == null) {
        final ct = values['colourType'] ?? fallback?['colourType'];
        if (ct == 'Ready Colour') {
          values['colourMode'] = 'Multiple Ready Colours';
        } else if (ct == 'Tintable Base') {
          values['colourMode'] = 'Tintable Base';
        } else if (ct == 'Not Applicable' || ct == 'Clear / Transparent') {
          values['colourMode'] = ct;
        } else if (fallback?['colourMode'] != null) {
          values['colourMode'] = fallback!['colourMode'];
        }
      }
      if (values['colourType'] == null) {
        final cm = values['colourMode'] ?? fallback?['colourMode'];
        if (cm == 'Multiple Ready Colours') {
          values['colourType'] = 'Ready Colour';
        } else if (cm == 'Tintable Base') {
          values['colourType'] = 'Tintable Base';
        } else if (cm == 'Not Applicable' || cm == 'Clear / Transparent') {
          values['colourType'] = cm;
        } else if (fallback?['colourType'] != null) {
          values['colourType'] = fallback!['colourType'];
        }
      }
      _pruneAttributeValues(values, template, level, fallback);
      for (final a in template.where(
        (a) =>
            a.level == level &&
            a.id != 'hsnCode' &&
            a.isVisible(values, fallback),
      )) {
        final v = values[a.id];
        if (a.isRequired(values, fallback) &&
            (v == null ||
                v is String && v.trim().isEmpty ||
                v is List && v.isEmpty)) {
          throw AppException('${a.name} is required.');
        }
        if (v != null && a.dataType == 'BOOLEAN' && v is! bool) {
          throw AppException('${a.name} must be true or false.');
        }
        if (v != null && a.dataType == 'SELECT' && !a.options.contains(v)) {
          throw AppException('Select an available ${a.name}.');
        }
        if (v != null &&
            a.dataType == 'MULTI_SELECT' &&
            (v is! List || v.any((o) => !a.options.contains(o)))) {
          throw AppException('Select available ${a.name} options.');
        }
        if (a.minimumExclusive != null &&
            v is num &&
            v <= a.minimumExclusive!) {
          throw AppException('${a.name} must be greater than zero.');
        }
        if (v != null && a.dataType == 'NUMBER' && (v is! num || !v.isFinite)) {
          throw AppException('${a.name} must be numeric.');
        }
      }
    }

    final productValues = Map<String, dynamic>.from(
      productFields['attributeValues'] as Map? ?? {},
    );
    validate(productValues, 'PRODUCT');
    productFields['attributeValues'] = productValues;
    final masters = await Future.wait([
      for (final type in ['BRAND', 'CATEGORY', 'SUBCATEGORY'])
        getMasterValues(
          tenantId: tenantId,
          businessId: businessId,
          masterType: type,
          token: token,
          categoryId: type == 'SUBCATEGORY'
              ? productFields['categoryId'] as String
              : null,
        ),
    ]);
    for (var i = 0; i < masters.length; i++) {
      final field = ['brandId', 'categoryId', 'subcategoryId'][i];
      if (!masters[i].any((v) => v.id == productFields[field])) {
        throw const AppException(
          'Selected classification is unavailable in this Business.',
        );
      }
    }
    final units = await getMasterValues(
      tenantId: tenantId,
      businessId: businessId,
      masterType: 'UNIT',
      token: token,
    );
    final keys = <String>{};
    for (final variant in variants) {
      final values = Map<String, dynamic>.from(
        variant['attributeValues'] as Map? ?? {},
      );
      if (values['soldAs'] == null) {
        final soldAsAttr = template
            .where((a) => a.level == 'VARIANT' && a.id == 'soldAs')
            .firstOrNull;
        if (soldAsAttr != null) {
          values['soldAs'] =
              soldAsAttr.defaultValue ??
              variant['commercialUnitName'] ??
              variant['commercialUnitId'] ??
              values['unit'];
        }
      }
      validate(values, 'VARIANT', productValues);
      variant['attributeValues'] = values;
      _validateCommercialFields(variant);
      if (!units.any((u) => u.id == variant['baseUnitId']) ||
          !units.any((u) => u.id == variant['commercialUnitId'])) {
        throw const AppException('Select valid base and commercial units.');
      }
      final factor = variant['baseQuantityPerCommercialUnit'];
      if (factor is! num ||
          !factor.isFinite ||
          factor <= 0 ||
          (variant['baseUnitId'] as String? ?? '').isEmpty) {
        throw const AppException(
          'Each SKU needs a positive conversion and base unit.',
        );
      }
      final sorted = values.keys.toList()..sort();
      final key = jsonEncode({
        for (final k in sorted)
          k: values[k] is List
              ? ((values[k] as List)
                    .map((v) => v.toString().trim().toLowerCase())
                    .toList()
                  ..sort())
              : values[k] is String
              ? (values[k] as String)
                    .trim()
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .toLowerCase()
              : values[k],
        'commercialUnitId': variant['commercialUnitId'],
        'baseUnitId': variant['baseUnitId'],
      });
      if (!keys.add(key)) {
        throw const AppException('Duplicate SKU combination.');
      }
    }

    final existingProducts = await firestore.queryDocuments(
      collection: FirebaseConstants.products,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    final normalizedName = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final brandId = productFields['brandId'] as String?;
    for (final document in existingProducts) {
      final data = FirestoreRestService.decodeFields(document['fields']);
      if (!_validProductRecord(data, tenantId, businessId)) continue;
      final existingName =
          (data['productName'] as String? ?? data['name'] as String? ?? '')
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      final oldBrand = (data['brand'] as String? ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final newBrand = (productFields['brand'] as String? ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (existingName == normalizedName &&
          (data['brandId'] == brandId ||
              (data['brandId'] == null && oldBrand == newBrand))) {
        final existingProdId = (data['productId'] as String? ??
            (document['name'] as String? ?? '').split('/').last);
        final existingDisplayName =
            (data['productName'] as String? ?? data['name'] as String? ?? name)
                .trim();
        final existingBrandName =
            (data['brand'] as String? ?? productFields['brand'] as String? ?? '')
                .trim();

        var hasActivePlacementAtOutlet = false;
        if (outletId != null && outletId.isNotEmpty) {
          final placementDocs = await firestore.queryDocuments(
            collection: FirebaseConstants.outletProducts,
            filters: [
              FirestoreFilter('tenantId', 'EQUAL', tenantId),
              FirestoreFilter('businessId', 'EQUAL', businessId),
              FirestoreFilter('outletId', 'EQUAL', outletId),
              FirestoreFilter('productId', 'EQUAL', existingProdId),
            ],
            idToken: token,
          );
          for (final pDoc in placementDocs) {
            final pData = FirestoreRestService.decodeFields(pDoc['fields']);
            if (pData['isDeleted'] != true &&
                pData['isActive'] == true &&
                (pData['status'] as String? ?? '').toUpperCase() == 'ACTIVE') {
              hasActivePlacementAtOutlet = true;
              break;
            }
          }
        }

        if (outletId != null && !hasActivePlacementAtOutlet) {
          throw AppException(
            'A Product with this name and Brand already exists in this Business. Add the existing Product to this Outlet instead.',
            code: 'product-exists-in-business',
            details: {
              'productId': existingProdId,
              'productName': existingDisplayName,
              'brand': existingBrandName,
            },
          );
        } else {
          throw AppException(
            'A Product with this name and Brand already exists. Add another Variant to the existing Product.',
            code: 'product-exists-in-outlet',
            details: {
              'productId': existingProdId,
              'productName': existingDisplayName,
              'brand': existingBrandName,
            },
          );
        }
      }
    }
    final existingVariants = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    // Codes already issued in this business (any status) must never be reused,
    // even when the local sequence counter is stale.
    int highestIssued(Iterable<Map<String, dynamic>> docs, String field) {
      var highest = 0;
      for (final d in docs) {
        final code = FirestoreRestService.decodeFields(d['fields'])[field];
        final n = code is String
            ? int.tryParse(RegExp(r'-(\d+)$').firstMatch(code)?.group(1) ?? '')
            : null;
        if (n != null && n > highest) highest = n;
      }
      return highest;
    }

    final productCodeStart = highestIssued(existingProducts, 'productCode') + 1;
    final variantCodeStart = highestIssued(existingVariants, 'variantCode') + 1;
    final productId = IdGenerator.create('PROD');
    final variantIds = [
      for (var i = 0; i < variants.length; i++) IdGenerator.create('VAR'),
    ];
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((tx) async {
      final uniquenessId = _masterDocumentId(
        '${tenantId}_${businessId}_PRODUCT',
        normalizedName,
        brandId,
      );
      final unique = await tx.get('product_unique_keys', uniquenessId);
      var isOrphanedUniqueKey = false;
      if (unique.exists) {
        final existingReferencedId = unique.fields['productId'] as String?;
        if (existingReferencedId == null || existingReferencedId.trim().isEmpty) {
          isOrphanedUniqueKey = true;
        } else {
          final referencedProduct =
              await tx.get(FirebaseConstants.products, existingReferencedId);
          if (!referencedProduct.exists ||
              !_validProductRecord(
                referencedProduct.fields,
                tenantId,
                businessId,
              )) {
            isOrphanedUniqueKey = true;
          }
        }
        if (!isOrphanedUniqueKey) {
          throw const AppException(
            'A Product with this name and Brand already exists.',
          );
        }
      }
      final oldProductSequence = await tx.get(
        FirebaseConstants.documentSequences,
        '${tenantId}_${businessId}_PRODUCT',
      );
      final oldVariantSequence = await tx.get(
        FirebaseConstants.documentSequences,
        '${tenantId}_${businessId}_PRODUCT_VARIANT',
      );
      if (!oldProductSequence.exists &&
              existingProducts.any(
                (d) =>
                    FirestoreRestService.decodeFields(
                      d['fields'],
                    )['productCode'] !=
                    null,
              ) ||
          !oldVariantSequence.exists &&
              existingVariants.any(
                (d) =>
                    FirestoreRestService.decodeFields(
                      d['fields'],
                    )['variantCode'] !=
                    null,
              )) {
        throw const AppException(
          'An administrator must initialize the existing catalogue code sequences before adding Products.',
        );
      }
      final productSequence = await _reserveSequenceRange(
        tx,
        tenantId: tenantId,
        businessId: businessId,
        type: 'PRODUCT',
        count: 1,
        initialNumber: productCodeStart,
        now: now,
      );
      final variantSequence = await _reserveSequenceRange(
        tx,
        tenantId: tenantId,
        businessId: businessId,
        type: 'PRODUCT_VARIANT',
        count: variants.length,
        initialNumber: variantCodeStart,
        now: now,
      );
      final missingBarcodeCount = variants
          .where((variant) => _optional(variant['barcode'] as String?) == null)
          .length;
      final barcodeSequence = missingBarcodeCount == 0
          ? 0
          : await _reserveSequenceRange(
              tx,
              tenantId: tenantId,
              businessId: businessId,
              type: 'INTERNAL_BARCODE',
              count: missingBarcodeCount,
              initialNumber: _nextInternalBarcodeNumber(existingVariants),
              now: now,
            );
      final productCode = 'PRD-${productSequence.toString().padLeft(4, '0')}';
      if (isOrphanedUniqueKey) {
        tx.update('product_unique_keys', uniquenessId, {
          'tenantId': tenantId,
          'businessId': businessId,
          'productId': productId,
          'updatedAt': now,
        }, updateTime: unique.updateTime);
      } else {
        tx.create('product_unique_keys', uniquenessId, {
          'tenantId': tenantId,
          'businessId': businessId,
          'productId': productId,
          'createdAt': now,
        });
      }
      tx.create(FirebaseConstants.products, productId, {
        'productId': productId,
        'productCode': productCode,
        'tenantId': tenantId,
        'businessId': businessId,
        'productName': name,
        'name': name,
        ...productFields,
        'catalogueFingerprint': catalogueFingerprint,
        'status': 'ACTIVE',
        'createdBy': actorUid,
        'createdAt': now,
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': 1,
      });
      var nextBarcode = barcodeSequence;
      for (var index = 0; index < variants.length; index++) {
        final variant = variants[index];
        final barcode =
            _optional(variant['barcode'] as String?) ??
            _formatInternalBarcode(nextBarcode++);
        final variantName = (variant['displayName'] as String? ?? '').trim();
        final variantCode =
            'SKU-${(variantSequence + index).toString().padLeft(4, '0')}';
        tx.create(FirebaseConstants.productVariants, variantIds[index], {
          'variantId': variantIds[index],
          'variantCode': variantCode,
          'sku': variantCode,
          'tenantId': tenantId,
          'businessId': businessId,
          'productId': productId,
          'productName': name,
          'variantName': variantName.isEmpty ? 'Default' : variantName,
          'name': '$name Â· ${variantName.isEmpty ? 'Default' : variantName}',
          ...variant,
          'barcode': barcode,
          'hsnCode': productFields['hsnCode'],
          'gstOverride': variant['defaultGstRateBps'] != null,
          'defaultGstRateBps':
              variant['defaultGstRateBps'] ??
              productFields['defaultGstRateBps'] ??
              0,
          'status': variant['status'] ?? 'ACTIVE',
          'createdBy': actorUid,
          'createdAt': now,
          'updatedBy': actorUid,
          'updatedAt': now,
          'version': 1,
        });
      }
      _createPlacement(
        tx,
        tenantId,
        businessId,
        outletId,
        productId,
        now,
        actorUid,
      );
    }, idToken: token);
  }

  Future<String> _requireInstalledCatalogueFingerprint(String token) async {
    final snapshot = <String, List<Map<String, dynamic>>>{};
    for (final collection in SystemCatalogueMetadata.collections) {
      snapshot[collection] = await firestore.queryDocuments(
        collection: collection,
        filters: const [FirestoreFilter('scopeType', 'EQUAL', 'SYSTEM')],
        idToken: token,
      );
    }
    final readiness = CatalogueReadiness.validateInstalled(
      snapshot,
      allowUnapprovedIsolatedForTests:
          allowUnapprovedIsolatedCatalogueForTests,
    );
    if (!readiness.isReady) {
      throw AppException(
        'The local SYSTEM catalogue is not ready for Product operations: ${readiness.errors.join(' ')}',
        code: 'catalogue-readiness',
      );
    }
    final releases =
        CatalogueContract.decode(snapshot)['product_catalogue_releases']!
            .where((fields) => CatalogueContract.active(fields))
            .toList();
    if (releases.length != 1) {
      throw const AppException(
        'The installed SYSTEM catalogue has no exact version fingerprint. Product creation is unavailable until catalogue provenance is available.',
        code: 'catalogue-provenance-missing',
      );
    }
    final release = releases.single;
    final version = CatalogueContract.version(release);
    final isSupportedVersion =
        version == CatalogueContract.legacyReleaseVersion || version == 4;
    if (release['installed'] != true ||
        !isSupportedVersion ||
        release['schemaRevision'] != CatalogueContract.schemaRevision ||
        release['compilerRevision'] !=
            CatalogueContract.compilerRevision ||
        !CatalogueFingerprint.isValid(
          release['catalogueFingerprint'],
        )) {
      throw const AppException(
        'The installed SYSTEM catalogue has no exact version fingerprint. Product creation is unavailable until catalogue provenance is available.',
        code: 'catalogue-provenance-missing',
      );
    }
    return release['catalogueFingerprint'] as String;
  }

  Future<int> _reserveSequenceRange(
    FirestoreTransactionContext tx, {
    required String tenantId,
    required String businessId,
    required String type,
    required int count,
    required int initialNumber,
    required DateTime now,
  }) async {
    final id = '${tenantId}_${businessId}_$type';
    final sequence = await tx.get(FirebaseConstants.documentSequences, id);
    final storedNext = sequence.exists
        ? (sequence.fields['nextNumber'] as num?)?.toInt() ?? initialNumber
        : initialNumber;
    final next = storedNext > initialNumber ? storedNext : initialNumber;
    final fields = {
      'tenantId': tenantId,
      'businessId': businessId,
      'sequenceType': type,
      'prefix': switch (type) {
        'PRODUCT' => 'PRD',
        'PRODUCT_VARIANT' => 'SKU',
        'INTERNAL_BARCODE' => '',
        _ => '',
      },
      'padding': type == 'INTERNAL_BARCODE' ? 12 : 4,
      'nextNumber': next + count,
      'updatedAt': now,
      if (!sequence.exists) 'createdAt': now,
    };
    if (sequence.exists) {
      tx.update(
        FirebaseConstants.documentSequences,
        id,
        fields,
        updateTime: sequence.updateTime,
      );
    } else {
      tx.create(FirebaseConstants.documentSequences, id, fields);
    }
    return next;
  }

  Future<ReclassificationPlan> computeReclassificationPlan({
    required String tenantId,
    required String businessId,
    required String productId,
    required String newCategoryId,
    required String newSubcategoryId,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
    required String token,
  }) async {
    final productDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.products,
      filters: [
        FirestoreFilter('productId', 'EQUAL', productId),
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );

    if (productDocs.isEmpty) {
      return ReclassificationPlan(
        classificationChanged: false,
        newCategoryId: newCategoryId,
        newSubcategoryId: newSubcategoryId,
        blockingIssues: ['Original Product not found.'],
      );
    }

    final originalProd = FirestoreRestService.decodeFields(
      productDocs.first['fields'],
    );
    final origCat = originalProd['categoryId'] as String?;
    final origSubcat = originalProd['subcategoryId'] as String?;
    final classificationChanged =
        origCat != newCategoryId || origSubcat != newSubcategoryId;

    final existingVariantDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [
        FirestoreFilter('productId', 'EQUAL', productId),
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );

    final originalVariantIds = existingVariantDocs
        .map((d) => FirestoreRestService.decodeFields(d['fields']))
        .where((d) => d['status'] != 'DELETED' && d['isDeleted'] != true)
        .map((d) => (d['variantId'] ?? d['id']) as String)
        .toList();

    final incomingVariantIds = variants
        .map((v) => v['variantId'] as String?)
        .whereType<String>()
        .toSet();

    final preservedIds = originalVariantIds
        .where((id) => incomingVariantIds.contains(id))
        .toList();
    final retiredIds = originalVariantIds
        .where((id) => !incomingVariantIds.contains(id))
        .toList();
    final newCount = variants
        .where((v) => v['variantId'] == null || v['_new'] == true)
        .length;

    final oldTemplate =
        classificationChanged && origSubcat != null && origSubcat.isNotEmpty
        ? await loadTemplate(
            tenantId: tenantId,
            businessId: businessId,
            subcategoryId: origSubcat,
            token: token,
          )
        : <ProductAttribute>[];

    final newTemplate = await loadTemplate(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: newSubcategoryId,
      token: token,
    );

    final newProdAttrIds = newTemplate
        .where((a) => a.level == 'PRODUCT')
        .map((a) => a.id)
        .toSet();
    final newVarAttrIds = newTemplate
        .where((a) => a.level == 'VARIANT')
        .map((a) => a.id)
        .toSet();

    final droppedProdAttrIds = oldTemplate
        .where((a) => a.level == 'PRODUCT' && !newProdAttrIds.contains(a.id))
        .map((a) => a.id)
        .toList();

    final droppedVarAttrIds = oldTemplate
        .where((a) => a.level == 'VARIANT' && !newVarAttrIds.contains(a.id))
        .map((a) => a.id)
        .toList();

    return ReclassificationPlan(
      classificationChanged: classificationChanged,
      originalCategoryId: origCat,
      originalSubcategoryId: origSubcat,
      newCategoryId: newCategoryId,
      newSubcategoryId: newSubcategoryId,
      preservedVariantIds: preservedIds,
      updatedVariantIds: preservedIds,
      newVariantCount: newCount,
      retiredVariantIds: retiredIds,
      removedProductAttributeIds: droppedProdAttrIds,
      removedVariantAttributeIds: droppedVarAttrIds,
      blockingIssues: [],
      warnings: [],
    );
  }

  Future<void> updateStructuredProduct({
    required String tenantId,
    required String businessId,
    required String productId,
    required String productName,
    required String actorUid,
    required String token,
    required Map<String, dynamic> productFields,
    required List<Map<String, dynamic>> variants,
  }) async {
    await _requireInstalledCatalogueFingerprint(token);
    final validator = ProductValidator(firestore);
    final validationResult = await validator.validateProduct(
      tenantId: tenantId,
      businessId: businessId,
      productName: productName,
      productFields: productFields,
      variants: variants,
      token: token,
      isNew: false,
      currentProductId: productId,
    );

    if (!validationResult.isValid) {
      throw ProductValidationException(validationResult);
    }

    productFields = _canonicalProductFields(productFields);
    if (productName.trim().length < 2 || variants.isEmpty) {
      throw const AppException('Enter a product name and keep its variants.');
    }
    final hasNew = variants.any((v) => v['variantId'] == null);
    if (hasNew && firestore is OfflineWritePrerequisites) {
      await (firestore as OfflineWritePrerequisites).ensureProductScopeReady(
        tenantId,
        businessId,
      );
    }
    await _validateBarcodes(tenantId, businessId, variants, token);
    variants = [
      for (final v in variants)
        {
          ...v,
          'variantId': v['variantId'] ?? IdGenerator.create('VAR'),
          '_new': v['variantId'] == null,
        },
    ];
    final template = await loadTemplate(
      tenantId: tenantId,
      businessId: businessId,
      subcategoryId: productFields['subcategoryId'] as String? ?? '',
      token: token,
    );
    for (final type in ['BRAND', 'CATEGORY', 'SUBCATEGORY']) {
      final values = await getMasterValues(
        tenantId: tenantId,
        businessId: businessId,
        masterType: type,
        token: token,
        categoryId: type == 'SUBCATEGORY'
            ? productFields['categoryId'] as String?
            : null,
      );
      final key = {
        'BRAND': 'brandId',
        'CATEGORY': 'categoryId',
        'SUBCATEGORY': 'subcategoryId',
      }[type]!;
      if (!values.any((v) => v.id == productFields[key])) {
        throw const AppException(
          'Select a valid Brand, Category and Subcategory.',
        );
      }
    }
    final units = await getMasterValues(
      tenantId: tenantId,
      businessId: businessId,
      masterType: 'UNIT',
      token: token,
    );
    if (template.any((a) => a.id == 'hsnCode' && a.required) &&
        (productFields['hsnCode'] as String? ?? '').isEmpty) {
      throw const AppException('HSN / SAC is required.');
    }
    void validate(Map values, String level, [Map? fallback]) {
      _pruneAttributeValues(values, template, level, fallback);
      for (final a in template.where(
        (a) =>
            a.level == level &&
            a.id != 'hsnCode' &&
            a.isVisible(values, fallback),
      )) {
        final v = values[a.id];
        if (a.isRequired(values, fallback) &&
            (v == null ||
                v is String && v.trim().isEmpty ||
                v is List && v.isEmpty)) {
          throw AppException('${a.name} is required.');
        }
        if (v == null) continue;
        if (a.minimumExclusive != null &&
            v is num &&
            v <= a.minimumExclusive!) {
          throw AppException('${a.name} must be greater than zero.');
        }
        if (a.dataType == 'NUMBER' && (v is! num || !v.isFinite) ||
            a.dataType == 'BOOLEAN' && v is! bool ||
            a.dataType == 'MULTI_SELECT' &&
                (v is! List || v.any((o) => !a.options.contains(o))) ||
            a.dataType == 'SELECT' && !a.options.contains(v)) {
          throw AppException('Check ${a.name}.');
        }
      }
    }

    for (final input in [productFields, ...variants]) {
      if (input['status'] != null &&
          !{'ACTIVE', 'INACTIVE'}.contains(input['status'])) {
        throw const AppException(
          'Use the authorized delete action to archive products.',
        );
      }
    }
    final productValues = Map<String, dynamic>.from(
      productFields['attributeValues'] as Map? ?? {},
    );
    validate(productValues, 'PRODUCT');
    productFields['attributeValues'] = productValues;
    final ids = <String>{};
    for (final v in variants) {
      if (!ids.add(v['variantId'] as String)) {
        throw const AppException('Duplicate variant.');
      }
      final values = Map<String, dynamic>.from(
        v['attributeValues'] as Map? ?? {},
      );
      if (values['soldAs'] == null) {
        final soldAsAttr = template
            .where((a) => a.level == 'VARIANT' && a.id == 'soldAs')
            .firstOrNull;
        if (soldAsAttr != null) {
          values['soldAs'] =
              soldAsAttr.defaultValue ??
              v['commercialUnitName'] ??
              v['commercialUnitId'] ??
              values['unit'];
        }
      }
      validate(values, 'VARIANT', productValues);
      v['attributeValues'] = values;
      final conversion = v['baseQuantityPerCommercialUnit'];
      if (conversion is! num ||
          !conversion.isFinite ||
          conversion <= 0 ||
          !units.any((u) => u.id == v['baseUnitId']) ||
          !units.any((u) => u.id == v['commercialUnitId'])) {
        throw const AppException(
          'Select valid units and a positive conversion.',
        );
      }
    }
    for (final type in ['BRAND', 'CATEGORY', 'SUBCATEGORY']) {
      final field = {
        'BRAND': 'brandId',
        'CATEGORY': 'categoryId',
        'SUBCATEGORY': 'subcategoryId',
      }[type]!;
      final masters = await getMasterValues(
        tenantId: tenantId,
        businessId: businessId,
        masterType: type,
        token: token,
        categoryId: type == 'SUBCATEGORY'
            ? productFields['categoryId'] as String?
            : null,
      );
      if (!masters.any((v) => v.id == productFields[field])) {
        throw const AppException('Select available product classifications.');
      }
    }
    for (final input in [productFields, ...variants]) {
      final gst = input['defaultGstRateBps'];
      if (gst != null && (gst is! int || gst < 0 || gst > 2800)) {
        throw const AppException('GST must be between 0 and 28%.');
      }
      for (final key in ['sellingPrice', 'purchaseRate', 'mrp']) {
        final value = input[key];
        if (value != null && (value is! int || value < 0)) {
          throw const AppException('Enter valid prices.');
        }
      }
    }
    final checkSkus = hasNew || variants.any((v) => v.containsKey('sku'));
    final existingWithSku = checkSkus
        ? await firestore.queryDocuments(
            collection: FirebaseConstants.productVariants,
            filters: [
              FirestoreFilter('tenantId', 'EQUAL', tenantId),
              FirestoreFilter('businessId', 'EQUAL', businessId),
            ],
            idToken: token,
          )
        : <Map<String, dynamic>>[];
    final existingVariantDocs = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [
        FirestoreFilter('productId', 'EQUAL', productId),
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((tx) async {
      final product = await tx.get(FirebaseConstants.products, productId);
      if (!product.exists ||
          product.fields['tenantId'] != tenantId ||
          product.fields['businessId'] != businessId) {
        throw const AppException('Product is unavailable in this Business.');
      }
      final uniqueId = _masterDocumentId(
        '${tenantId}_${businessId}_PRODUCT',
        productName.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
        productFields['brandId'] as String,
      );
      final unique = await tx.get('product_unique_keys', uniqueId);
      var isOrphanedUnique = false;
      if (unique.exists && unique.fields['productId'] != productId) {
        final existingReferencedId = unique.fields['productId'] as String?;
        if (existingReferencedId == null || existingReferencedId.trim().isEmpty) {
          isOrphanedUnique = true;
        } else {
          final referencedProduct =
              await tx.get(FirebaseConstants.products, existingReferencedId);
          if (!referencedProduct.exists ||
              !_validProductRecord(
                referencedProduct.fields,
                tenantId,
                businessId,
              )) {
            isOrphanedUnique = true;
          }
        }
        if (!isOrphanedUnique) {
          throw const AppException(
            'A product with this name and Brand already exists.',
          );
        }
      }
      if (unique.exists && isOrphanedUnique) {
        tx.update('product_unique_keys', uniqueId, {
          'tenantId': tenantId,
          'businessId': businessId,
          'productId': productId,
          'updatedAt': now,
        }, updateTime: unique.updateTime);
      } else if (!unique.exists) {
        tx.create('product_unique_keys', uniqueId, {
          'tenantId': tenantId,
          'businessId': businessId,
          'productId': productId,
          'createdAt': now,
        });
      }
      final patch = Map<String, dynamic>.from(productFields)
        ..removeWhere(
          (k, _) => !{
            'brandId',
            'brand',
            'categoryId',
            'categoryName',
            'subcategoryId',
            'subcategory',
            'attributeValues',
            'productImage',
            'imageUrl',
            'description',
          'quantitySlabs',
            'hsnCode',
            'defaultGstRateBps',
            'status',
          }.contains(k),
        );
      patch.addAll({
        'productName': productName.trim(),
        'name': productName.trim(),
        'updatedAt': now,
        'updatedBy': actorUid,
        'version': ((product.fields['version'] as num?)?.toInt() ?? 0) + 1,
      });
      tx.update(
        FirebaseConstants.products,
        productId,
        patch,
        updateTime: product.updateTime,
      );
      final newCount = variants.where((v) => v['_new'] == true).length;
      if (newCount > 0) {
        final sequence = await tx.get(
          FirebaseConstants.documentSequences,
          '${tenantId}_${businessId}_PRODUCT_VARIANT',
        );
        if (!sequence.exists &&
            existingWithSku.any(
              (doc) =>
                  FirestoreRestService.decodeFields(doc['fields'])['sku'] !=
                  null,
            )) {
          throw const AppException(
            'An administrator must initialize the existing SKU sequence before adding variants.',
          );
        }
      }
      var nextSku = newCount == 0
          ? 0
          : await _reserveSequenceRange(
              tx,
              tenantId: tenantId,
              businessId: businessId,
              type: 'PRODUCT_VARIANT',
              count: newCount,
              initialNumber: 1,
              now: now,
            );
      final missingBarcodeCount = variants
          .where(
            (input) =>
                input['_new'] == true &&
                _optional(input['barcode'] as String?) == null,
          )
          .length;
      var nextBarcode = missingBarcodeCount == 0
          ? 0
          : await _reserveSequenceRange(
              tx,
              tenantId: tenantId,
              businessId: businessId,
              type: 'INTERNAL_BARCODE',
              count: missingBarcodeCount,
              initialNumber: _nextInternalBarcodeNumber(existingWithSku),
              now: now,
            );
      // Compare effective SKUs, including omitted values on preserved rows.
      // Generated codes must also be checked against the existing active scope.
      final activeSkus = <String>{};
      for (final doc in existingWithSku) {
        final data = FirestoreRestService.decodeFields(doc['fields']);
        if (data['productId'] != productId && data['status'] == 'ACTIVE') {
          final sku = (data['sku'] as String?)?.trim().toLowerCase();
          if (sku != null && sku.isNotEmpty) {
            activeSkus.add(sku);
          }
        }
      }
      void validateSku(String? sku, String status) {
        if (!checkSkus || status != 'ACTIVE') {
          return;
        }
        final normalized = sku?.trim().toLowerCase();
        if (normalized != null &&
            normalized.isNotEmpty &&
            !activeSkus.add(normalized)) {
          throw const AppException('Each active variant needs a unique SKU.');
        }
      }

      for (final input in variants) {
        final id = input['variantId'] as String;
        if (input['_new'] == true) {
          final barcode =
              _optional(input['barcode'] as String?) ??
              _formatInternalBarcode(nextBarcode++);
          final code = 'SKU-${(nextSku++).toString().padLeft(4, '0')}';
          validateSku(
            code,
            productFields['status'] == 'INACTIVE'
                ? 'INACTIVE'
                : input['status'] as String? ?? 'ACTIVE',
          );
          final fields = Map<String, dynamic>.from(input)
            ..removeWhere(
              (k, _) => !{
                'attributeValues',
                'packSize',
                'packUnitId',
                'commercialUnitId',
                'commercialUnitName',
                'baseQuantityPerCommercialUnit',
                'baseUnitId',
                'unitId',
                'barcode',
                'status',
                'sellingPrice',
                'purchaseRate',
                'mrp',
                'defaultGstRateBps',
              'quantitySlabs',
              }.contains(k),
            );
          tx.create(FirebaseConstants.productVariants, id, {
            ...fields,
            'variantId': id,
            'barcode': barcode,
            'productId': productId,
            'tenantId': tenantId,
            'businessId': businessId,
            'sku': code,
            'variantCode': code,
            'productName': productName.trim(),
            'variantName': input['displayName'] ?? 'Default',
            'hsnCode': productFields['hsnCode'],
            'gstOverride': input['defaultGstRateBps'] != null,
            'defaultGstRateBps':
                input['defaultGstRateBps'] ??
                productFields['defaultGstRateBps'] ??
                0,
            'status': productFields['status'] == 'INACTIVE'
                ? 'INACTIVE'
                : input['status'] ?? 'ACTIVE',
            'createdAt': now,
            'updatedAt': now,
            'createdBy': actorUid,
            'updatedBy': actorUid,
            'version': 1,
          });
          continue;
        }
        // Old single-document products retain their original identity.
        final legacy = id == productId;
        final record = legacy
            ? product
            : await tx.get(FirebaseConstants.productVariants, id);
        if (!record.exists ||
            record.fields['tenantId'] != tenantId ||
            record.fields['businessId'] != businessId ||
            !legacy && record.fields['productId'] != productId) {
          throw const AppException('Variant is unavailable in this Business.');
        }
        if (input.containsKey('sku') &&
            (input['sku'] is! String ||
                (input['sku'] as String).trim().isEmpty)) {
          throw const AppException('Enter a non-empty SKU.');
        }
        validateSku(
          input.containsKey('sku')
              ? input['sku'] as String
              : record.fields['sku'] as String?,
          productFields['status'] == 'INACTIVE'
              ? 'INACTIVE'
              : input['status'] as String? ??
                    record.fields['status'] as String? ??
                    'ACTIVE',
        );
        final fields = Map<String, dynamic>.from(input)
          ..removeWhere(
            (k, _) => !{
              'attributeValues',
              'packSize',
              'packUnitId',
              'commercialUnitId',
              'commercialUnitName',
              'baseQuantityPerCommercialUnit',
              'baseUnitId',
              'unitId',
              'barcode',
              'sku',
              'status',
              'sellingPrice',
              'purchaseRate',
              'mrp',
              'defaultGstRateBps',
              'quantitySlabs',
            }.contains(k),
          );
        if (fields.containsKey('sku')) {
          fields['sku'] = (fields['sku'] as String).trim();
        }
        fields['gstOverride'] = input['defaultGstRateBps'] != null;
        fields['defaultGstRateBps'] =
            input['defaultGstRateBps'] ??
            productFields['defaultGstRateBps'] ??
            0;
        fields['defaultGstRate'] = fields['defaultGstRateBps'];
        if (productFields['status'] == 'INACTIVE') {
          fields['status'] = 'INACTIVE';
          fields['statusBeforeProductDeactivation'] =
              record.fields['statusBeforeProductDeactivation'] ??
              record.fields['status'] ??
              'ACTIVE';
        }
        if (legacy) {
          fields['attributeValues'] = {
            ...?productFields['attributeValues'] as Map?,
            ...?input['attributeValues'] as Map?,
          };
        }
        fields.addAll({
          'hsnCode': productFields['hsnCode'],
          'productName': productName.trim(),
          'updatedAt': now,
          'updatedBy': actorUid,
        });
        tx.update(
          legacy
              ? FirebaseConstants.products
              : FirebaseConstants.productVariants,
          id,
          fields,
          updateTime: record.updateTime,
        );
      }

      // Reconcile and soft-retire removed variants
      final incomingVariantIds = variants
          .map((v) => v['variantId'] as String?)
          .whereType<String>()
          .toSet();

      for (final doc in existingVariantDocs) {
        final docData = FirestoreRestService.decodeFields(doc['fields']);
        final vId =
            (docData['variantId'] ??
                    doc['id'] ??
                    (doc['name'] as String?)?.split('/').last)
                as String?;
        final vStatus = docData['status'] as String?;
        if (vId != null &&
            vStatus != 'DELETED' &&
            !incomingVariantIds.contains(vId)) {
          final record = await tx.get(FirebaseConstants.productVariants, vId);
          if (record.exists) {
            tx.update(FirebaseConstants.productVariants, vId, {
              'status': 'DELETED',
              'isDeleted': true,
              'updatedAt': now,
              'updatedBy': actorUid,
            }, updateTime: record.updateTime);
          }
        }
      }
    }, idToken: token);
  }

  /// Normal outlet view: only stock_balances of [outletId]; never aggregates
  /// other outlets.
  Future<Map<String, int>> getOutletProductStock({
    required String tenantId,
    required String businessId,
    required String outletId,
    required String token,
  }) {
    if (outletId.trim().isEmpty) {
      throw const AppException('Select an Outlet to view its stock.');
    }
    return _sumStock(tenantId, businessId, outletId, token);
  }

  Future<Map<String, int>> _sumStock(
    String tenantId,
    String businessId,
    String? outletId,
    String token,
  ) async {
    final docs = await firestore.queryDocuments(
      collection: FirebaseConstants.stockBalances,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
        if (outletId != null) FirestoreFilter('outletId', 'EQUAL', outletId),
      ],
      idToken: token,
    );
    final result = <String, int>{};
    for (final doc in docs) {
      final fields = FirestoreRestService.decodeFields(doc['fields']);
      if (outletId != null && fields['outletId'] != outletId) continue;
      final id = fields['variantId'] as String?;
      if (id != null) {
        final rawQty = (fields['quantityOnHand'] as num?)?.toInt() ?? 0;
        var qty = rawQty;
        final remainder = rawQty % 1000;
        if (remainder != 0) {
          final unitsSold = 1000 - remainder;
          if (unitsSold > 0 && unitsSold < 100) {
            qty = rawQty - (unitsSold * 999);
            final docId = doc['name']?.toString().split('/').last;
            if (docId != null) {
              _healStockFraction(
                tenantId: tenantId,
                businessId: businessId,
                outletId: outletId,
                variantId: id,
                docId: docId,
                correctedQty: qty,
                unitsSold: unitsSold,
                token: token,
              );
            }
          }
        }
        result[id] = (result[id] ?? 0) + qty;
      }
    }
    return result;
  }

  Future<void> _healStockFraction({
    required String tenantId,
    required String businessId,
    required String? outletId,
    required String? variantId,
    required String docId,
    required int correctedQty,
    required int unitsSold,
    required String token,
  }) async {
    try {
      await firestore.patchDocument(
        FirebaseConstants.stockBalances,
        docId,
        {'quantityOnHand': correctedQty},
        idToken: token,
      );
      if (variantId != null && outletId != null) {
        final batchDocs = await firestore.queryDocuments(
          collection: FirebaseConstants.inventoryBatches,
          filters: [
            FirestoreFilter('tenantId', 'EQUAL', tenantId),
            FirestoreFilter('businessId', 'EQUAL', businessId),
            FirestoreFilter('outletId', 'EQUAL', outletId),
            FirestoreFilter('variantId', 'EQUAL', variantId),
          ],
          idToken: token,
        );
        for (final bDoc in batchDocs) {
          final bFields = FirestoreRestService.decodeFields(bDoc['fields']);
          final bQty = (bFields['availableQty'] as num?)?.toInt() ?? 0;
          final bId = bDoc['name']?.toString().split('/').last;
          if (bId != null && bQty >= unitsSold * 1000) {
            final newBQty = bQty - (unitsSold * 1000);
            await firestore.patchDocument(
              FirebaseConstants.inventoryBatches,
              bId,
              {
                'availableQty': newBQty,
                'status': newBQty == 0 ? 'DEPLETED' : 'AVAILABLE',
              },
              idToken: token,
            );
            break;
          }
        }
      }
      if (firestore is OfflineFirestoreService) {
        final local = (firestore as OfflineFirestoreService).localDataSource;
        if (local != null && variantId != null) {
          await local.db.rawUpdate(
            "UPDATE local_stock_balances SET quantityOnHand=? WHERE variantId=?",
            [correctedQty, variantId],
          );
        }
      }
    } catch (_) {}
  }

  Future<void> setProductStatus({
    required String tenantId,
    required String businessId,
    required List<String> productIds,
    required String status,
    required String actorUid,
    required String token,
  }) async {
    if (!{'ACTIVE', 'INACTIVE', 'DELETED'}.contains(status)) {
      throw const AppException('Invalid product status.');
    }
    final variants = await firestore.queryDocuments(
      collection: FirebaseConstants.productVariants,
      filters: [
        FirestoreFilter('tenantId', 'EQUAL', tenantId),
        FirestoreFilter('businessId', 'EQUAL', businessId),
      ],
      idToken: token,
    );
    await transactions.runAtomicOperation((tx) async {
      for (final doc in variants) {
        final data = FirestoreRestService.decodeFields(doc['fields']);
        if (!productIds.contains(data['productId'])) continue;
        final variantId = (doc['name'] as String).split('/').last;
        final variant = await tx.get(
          FirebaseConstants.productVariants,
          variantId,
        );
        if (!variant.exists ||
            variant.fields['tenantId'] != tenantId ||
            variant.fields['businessId'] != businessId) {
          throw const AppException('Variant scope changed.');
        }
        tx.update(FirebaseConstants.productVariants, variantId, {
          'status': status == 'ACTIVE'
              ? variant.fields['statusBeforeProductDeactivation'] ??
                    variant.fields['status'] ??
                    'ACTIVE'
              : 'INACTIVE',
          if (status != 'ACTIVE' &&
              variant.fields['statusBeforeProductDeactivation'] == null)
            'statusBeforeProductDeactivation':
                variant.fields['status'] ?? 'ACTIVE',
          if (status == 'ACTIVE') 'statusBeforeProductDeactivation': null,
          'updatedAt': DateTime.now().toUtc(),
          'updatedBy': actorUid,
        }, updateTime: variant.updateTime);
      }
      for (final id in productIds.toSet()) {
        final record = await tx.get(FirebaseConstants.products, id);
        if (!record.exists ||
            record.fields['tenantId'] != tenantId ||
            record.fields['businessId'] != businessId) {
          throw const AppException('Product is unavailable in this Business.');
        }
        tx.update(FirebaseConstants.products, id, {
          'status': status,
          'isDeleted': status == 'DELETED',
          'updatedAt': DateTime.now().toUtc(),
          'updatedBy': actorUid,
        }, updateTime: record.updateTime);
      }
    }, idToken: token);
  }

  Future<void> updateProductVariant({
    required String tenantId,
    required String businessId,
    required String productId,
    required String variantId,
    required String name,
    required String variantName,
    required String unitId,
    required String actorUid,
    required String token,
    String? brand,
    String? category,
    String? subcategory,
    String? description,
    String? sku,
    String? barcode,
    String? hsnCode,
    required int gstRateBps,
  }) async {
    await _requireInstalledCatalogueFingerprint(token);
    if (name.trim().length < 2 ||
        unitId.trim().isEmpty ||
        gstRateBps < 0 ||
        gstRateBps > 2800) {
      throw const AppException(
        'Check the required Product and Variant details.',
      );
    }
    final now = DateTime.now().toUtc();
    await transactions.runAtomicOperation((tx) async {
      final product = await tx.get(FirebaseConstants.products, productId);
      final variant = await tx.get(
        FirebaseConstants.productVariants,
        variantId,
      );
      if (!product.exists ||
          !variant.exists ||
          product.fields['tenantId'] != tenantId ||
          product.fields['businessId'] != businessId ||
          variant.fields['tenantId'] != tenantId ||
          variant.fields['businessId'] != businessId ||
          variant.fields['productId'] != productId) {
        throw const AppException(
          'Product or Variant is no longer available in this Business.',
        );
      }
      final productFields = {
        'productName': name.trim(),
        'name': name.trim(),
        'brand': _optional(brand),
        'categoryName': _optional(category),
        'subcategory': _optional(subcategory),
        'description': _optional(description),
        'baseUnitId': unitId.trim(),
        'hsnCode': _optional(hsnCode),
        'defaultGstRateBps': gstRateBps,
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': ((product.fields['version'] as num?)?.toInt() ?? 1) + 1,
      };
      final variantFields = {
        'productName': name.trim(),
        'variantName': variantName.trim().isEmpty
            ? 'Default'
            : variantName.trim(),
        'name':
            '${name.trim()} Â· ${variantName.trim().isEmpty ? 'Default' : variantName.trim()}',
        'baseUnitId': unitId.trim(),
        'unitId': unitId.trim(),
        'sku': _optional(sku),
        'barcode': _optional(barcode),
        'hsnCode': _optional(hsnCode),
        'defaultGstRateBps': gstRateBps,
        'defaultGstRate': gstRateBps,
        'updatedBy': actorUid,
        'updatedAt': now,
        'version': ((variant.fields['version'] as num?)?.toInt() ?? 1) + 1,
      };
      tx.update(
        FirebaseConstants.products,
        productId,
        productFields,
        updateTime: product.updateTime,
      );
      tx.update(
        FirebaseConstants.productVariants,
        variantId,
        variantFields,
        updateTime: variant.updateTime,
      );
    }, idToken: token);
  }

  String? _optional(String? value) =>
      value?.trim().isEmpty == true ? null : value?.trim();

  List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().toList(growable: false)
      : const [];
}

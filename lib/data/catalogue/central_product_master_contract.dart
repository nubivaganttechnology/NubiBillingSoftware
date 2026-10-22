import '../../core/errors/app_exception.dart';
import '../models/central_product_master.dart';

class CentralProductMasterContract {
  CentralProductMasterContract._();

  static const collection = 'central_product_master_verified';
  static const previousCollection = 'central_product_master';
  static const expectedDocumentCount = 1305;
  static const verifiedBootstrapVersion = 'verified-central-master-v1';

  static void validateSnapshot(List<Map<String, dynamic>> documents) {
    if (documents.length != expectedDocumentCount) {
      throw AppException(
        'Verified central product bootstrap returned ${documents.length} '
        'documents; expected $expectedDocumentCount. Existing local cache retained.',
        code: 'central-product-count',
      );
    }

    final masterProductIds = <String>{};
    final brandNameProductNames = <String>{};
    for (final document in documents) {
      final documentName = document['name'];
      if (documentName is! String ||
          documentName.split('/').length < 2 ||
          documentName.split('/')[documentName.split('/').length - 2] !=
              collection) {
        throw const AppException(
          'Verified central product bootstrap returned a document from an unexpected collection.',
          code: 'central-product-source',
        );
      }
      final product = CentralProductMaster.fromFirestoreRest(document);
      validateProduct(product);
      if (!masterProductIds.add(product.masterProductId)) {
        throw AppException(
          'Verified central product masterProductId is duplicated: ${product.masterProductId}.',
          code: 'central-product-duplicate-id',
        );
      }
      final nameKey = [
        product.brandName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
        product.normalizedProductName.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        ),
      ].join('\u0000');
      if (!brandNameProductNames.add(nameKey)) {
        throw AppException(
          'Verified central product brand and normalized product name are duplicated: '
          '${product.brandName} / ${product.normalizedProductName}.',
          code: 'central-product-duplicate-name',
        );
      }
    }
  }

  static void validateProduct(CentralProductMaster product) {
    if (product.scopeType != 'SYSTEM' ||
        product.status.toUpperCase() != 'ACTIVE' ||
        !product.isActive ||
        product.businessTypeId != 'BT-HARDWARE' ||
        product.businessSubTypeId != 'BST-PAINTS') {
      throw AppException(
        'Verified central product ${product.masterProductId} has an unexpected scope or status.',
        code: 'central-product-scope',
      );
    }
  }
}

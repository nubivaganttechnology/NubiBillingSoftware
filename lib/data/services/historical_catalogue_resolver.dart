import 'package:sqflite_common/sqlite_api.dart';

import '../catalogue/catalogue_fingerprint.dart';
import '../local/catalogue_archive_store.dart';

/// Callers must select a context explicitly; CREATE_CANONICAL is intentionally
/// not implemented by the archive resolver.
enum CatalogueResolutionContext { createCanonical, readExisting, historical }

enum CatalogueResolutionStatus { exact, provenanceMissing, archiveNotFound }

class HistoricalCatalogueResolution {
  const HistoricalCatalogueResolution({
    required this.status,
    required this.context,
    this.fingerprint,
    this.productFields,
    this.collections = const {},
  });

  final CatalogueResolutionStatus status;
  final CatalogueResolutionContext context;
  final String? fingerprint;
  final Map<String, dynamic>? productFields;
  final Map<String, List<Map<String, dynamic>>> collections;
  bool get provenanceMissing =>
      status == CatalogueResolutionStatus.provenanceMissing;
}

/// Reads one complete retained snapshot namespace and never consults current
/// catalogue tables, display names, or Product timestamps.
class HistoricalCatalogueResolver {
  HistoricalCatalogueResolver(this.db, {CatalogueArchiveStore? archive})
    : archive = archive ?? CatalogueArchiveStore();

  final DatabaseExecutor db;
  final CatalogueArchiveStore archive;

  Future<HistoricalCatalogueResolution> resolveProduct(
    Map<String, dynamic> product, {
    required CatalogueResolutionContext context,
  }) async {
    if (context == CatalogueResolutionContext.createCanonical) {
      throw ArgumentError('Historical resolver cannot serve CREATE_CANONICAL.');
    }
    final fingerprint = product['catalogueFingerprint'];
    if (!CatalogueFingerprint.isValid(fingerprint)) {
      return HistoricalCatalogueResolution(
        status: CatalogueResolutionStatus.provenanceMissing,
        context: context,
        productFields: Map.of(product),
      );
    }
    final releaseMarkers = await archive.getCollection(
      db,
      fingerprint: fingerprint as String,
      collection: 'product_catalogue_releases',
    );
    if (releaseMarkers.isEmpty) {
      // A valid token without the matching archived marker is unknown, not a
      // reason to fall back to the current installed release.
      return HistoricalCatalogueResolution(
        status: CatalogueResolutionStatus.archiveNotFound,
        context: context,
        fingerprint: fingerprint,
        productFields: Map.of(product),
      );
    }
    final collections = <String, List<Map<String, dynamic>>>{};
    for (final collection in CatalogueArchiveStore.collections) {
      collections[collection] = await archive.getCollection(
        db,
        fingerprint: fingerprint,
        collection: collection,
      );
    }
    final subcategoryId = product['subcategoryId'];
    if (subcategoryId is String && subcategoryId.isNotEmpty) {
      collections['subcategory_attribute_templates'] =
          collections['subcategory_attribute_templates']!
              .where((row) =>
                  row['fields']['subcategoryId'] == subcategoryId ||
                  row['documentId'] == subcategoryId)
              .toList(growable: false);
    }
    return HistoricalCatalogueResolution(
      status: CatalogueResolutionStatus.exact,
      context: context,
      fingerprint: fingerprint,
      productFields: Map.of(product),
      collections: collections,
    );
  }

  Future<HistoricalCatalogueResolution> resolveDocument({
    required String? fingerprint,
    required String collection,
    required String documentId,
    required CatalogueResolutionContext context,
  }) async {
    if (context == CatalogueResolutionContext.createCanonical) {
      throw ArgumentError('Historical resolver cannot serve CREATE_CANONICAL.');
    }
    if (!CatalogueFingerprint.isValid(fingerprint)) {
      return HistoricalCatalogueResolution(
        status: CatalogueResolutionStatus.provenanceMissing,
        context: context,
      );
    }
    final document = await archive.getDocument(
      db,
      fingerprint: fingerprint!,
      collection: collection,
      documentId: documentId,
    );
    if (document == null) {
      return HistoricalCatalogueResolution(
        status: CatalogueResolutionStatus.archiveNotFound,
        context: context,
        fingerprint: fingerprint,
      );
    }
    return HistoricalCatalogueResolution(
      status: CatalogueResolutionStatus.exact,
      context: context,
      fingerprint: fingerprint,
      collections: {
        collection: [document],
      },
    );
  }

}

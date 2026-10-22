import '../../core/errors/app_exception.dart';
import '../local/local_data_source.dart';
import 'catalogue_contract.dart';
import 'catalogue_fingerprint.dart';
import 'system_catalogue_metadata.dart';
import '../services/firestore_value_codec.dart';

enum CatalogueReadinessState {
  notInitialized,
  syncing,
  validating,
  ready,
  offlineValidCache,
  invalidCache,
  recoveryRequired,
  failed,
}

class CatalogueReadinessReport {
  const CatalogueReadinessReport({
    required this.state,
    required this.errors,
    required this.releaseVersion,
    required this.fingerprint,
  });

  final CatalogueReadinessState state;
  final List<String> errors;
  final int? releaseVersion;
  final String? fingerprint;

  bool get isReady => state == CatalogueReadinessState.ready;
}

class CatalogueReadiness {
  CatalogueReadiness._();

  static CatalogueReadinessReport validate(
    Map<String, List<Map<String, dynamic>>> documents, {
    bool allowUnapprovedIsolatedForTests = false,
  }) {
    final errors = <String>[];
    if (!CatalogueContract.requiredCollections.every(documents.containsKey)) {
      errors.add('Incomplete SYSTEM catalogue snapshot.');
    }
    for (final col in CatalogueContract.requiredCollections) {
      if ((documents[col] ?? const []).isEmpty) {
        errors.add('Required catalogue collection $col is missing or empty.');
      }
    }

    if (errors.isNotEmpty) {
      return _failed(errors);
    }

    try {
      final compiled = SystemCatalogueMetadata.compile(documents);
      final raw = CatalogueContract.decode(compiled);

      for (final col in [
        'product_categories',
        'product_subcategories',
        'product_attributes',
        'subcategory_attribute_templates',
        'units',
      ]) {
        if (!(raw[col]?.any(CatalogueContract.active) ?? false)) {
          errors.add('Required active catalogue records are missing in $col.');
        }
      }

      CatalogueContract.validate(raw);

      final releases = raw['product_catalogue_releases']!
          .where((row) => CatalogueContract.active(row))
          .where((row) => row['published'] != false)
          .toList();
      if (releases.length != 1) {
        errors.add('Exactly one published catalogue release is required.');
      }

      final release = releases.length == 1 ? releases.single : null;
      final releaseVersion = release == null
          ? null
          : CatalogueContract.version(release);
      final fingerprint = release == null
          ? null
          : SystemCatalogueMetadata.fingerprint(
              compiled['product_catalogue_releases']!,
            );
      if (release != null && releaseVersion == null) {
        errors.add('Published catalogue release has no valid version.');
      }
      if (release != null &&
          (releaseVersion ?? 0) >= 4 &&
          !allowUnapprovedIsolatedForTests) {
        if (release['isolatedOnly'] == true ||
            release['approvedForLiveExecution'] != true ||
            release['productionMigrationApproved'] != true ||
            release['firestorePublicationApproved'] != true) {
          errors.add(
            'Catalogue release is isolated or lacks required production approvals.',
          );
        }
      }

      final subcategory = raw['product_subcategories']!.where(
        (row) =>
            row['subcategoryId'] ==
                'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS' &&
            CatalogueContract.active(row),
      );
      // The compiler validates a profile when its subcategory is present.
      // Do not require a specific business category to exist in every release.
      if (subcategory.length > 1) {
        errors.add('DIY_KITS subcategory metadata is ambiguous.');
      } else if (subcategory.isNotEmpty) {
        // DIY_KITS has an unresolved owner decision. Let the compiler reject
        // missing or unsupported metadata; do not encode the unapproved v4
        // review candidate (EXPLICIT_METADATA/selectable) as a production
        // requirement here.
        final templates = raw['subcategory_attribute_templates']!
            .where(
              (row) =>
                  row['subcategoryId'] ==
                      'SYS_SUBCATEGORY_SYS_CATEGORY_DIY_AEROSOLS_DIY_KITS' &&
                  CatalogueContract.active(row),
            )
            .toList();
        if (templates.isEmpty) {
          errors.add('Required DIY_KITS template metadata is missing.');
        }
      }

      if (errors.isNotEmpty) {
        return CatalogueReadinessReport(
          state: CatalogueReadinessState.failed,
          errors: List.unmodifiable(errors),
          releaseVersion: releaseVersion,
          fingerprint: fingerprint,
        );
      }
      return CatalogueReadinessReport(
        state: CatalogueReadinessState.ready,
        errors: const [],
        releaseVersion: releaseVersion,
        fingerprint: fingerprint,
      );
    } on AppException catch (error) {
      return _failed([error.message]);
    }
  }

  /// Verifies an installed local snapshot against the exact install manifest.
  /// Inactive rows outside the manifest are retained as history; active rows
  /// outside it are an unexpected mixed-release state and block use.
  static CatalogueReadinessReport validateInstalled(
    Map<String, List<Map<String, dynamic>>> documents, {
    bool allowUnapprovedIsolatedForTests = false,
  }) {
    final structural = validate(
      documents,
      allowUnapprovedIsolatedForTests: allowUnapprovedIsolatedForTests,
    );
    if (!structural.isReady) return structural;

    try {
      final compiled = SystemCatalogueMetadata.compile(documents);
      final raw = CatalogueContract.decode(compiled);
      final releases = raw['product_catalogue_releases']!
          .where(CatalogueContract.active)
          .where((row) => row['published'] != false)
          .toList();
      if (releases.length != 1) {
        return _failed(['Exactly one installed release marker is required.']);
      }
      final release = releases.single;
      if (release['installed'] != true) {
        return _failed(['Installed catalogue marker is missing.']);
      }
      if (release['schemaRevision'] != CatalogueContract.schemaRevision ||
          release['compilerRevision'] != CatalogueContract.compilerRevision) {
        return _failed(['Installed catalogue compiler/schema is unsupported.']);
      }
      final fingerprint = release['catalogueFingerprint'];
      if (!CatalogueFingerprint.isValid(fingerprint)) {
        return _failed([
          'Installed catalogue fingerprint is missing or invalid.',
        ]);
      }

      final manifestValue = release['installedDocumentManifest'];
      Map<String, List<String>> manifest;
      if (manifestValue == null) {
        // Compatibility for older installs: exact equality is still required
        // across all provided local SYSTEM collections.
        manifest = {
          for (final entry in documents.entries)
            entry.key: entry.value.map(_documentId).toList()..sort(),
        };
      } else {
        if (manifestValue is! Map) {
          return _failed(['Installed catalogue document manifest is invalid.']);
        }
        manifest = {};
        for (final collection in SystemCatalogueMetadata.collections) {
          final ids = manifestValue[collection];
          if (ids is! List || ids.any((id) => id is! String)) {
            return _failed([
              'Installed catalogue manifest is incomplete for $collection.',
            ]);
          }
          manifest[collection] = ids.cast<String>();
        }
      }

      final selected = <String, List<Map<String, dynamic>>>{};
      final errors = <String>[];
      for (final collection in SystemCatalogueMetadata.collections) {
        final source = documents[collection] ?? const [];
        final byId = {for (final doc in source) _documentId(doc): doc};
        final ids = manifest[collection] ?? const <String>[];
        if (ids.toSet().length != ids.length) {
          errors.add(
            'Installed catalogue manifest has duplicate $collection IDs.',
          );
          continue;
        }
        final missing = ids.where((id) => !byId.containsKey(id)).toList();
        if (missing.isNotEmpty) {
          errors.add('Installed catalogue is incomplete in $collection.');
        }
        selected[collection] = [
          for (final id in ids)
            if (byId[id] != null) byId[id]!,
        ];
        final manifestIds = ids.toSet();
        for (final doc in source) {
          // SYSTEM brands are independently synchronized masters in the
          // current release contract (the published v4 manifest omits them).
          if (collection == 'brands' &&
              !manifestIds.contains(_documentId(doc))) {
            continue;
          }
          final fields = FirestoreValueCodec.decodeFields(doc['fields']);
          if (!manifestIds.contains(_documentId(doc)) &&
              CatalogueContract.active(fields)) {
            errors.add(
              'Unexpected active SYSTEM record outside installed release: $collection/${_documentId(doc)}.',
            );
          }
        }
      }
      if (errors.isNotEmpty) return _failed(errors);
      final recomputed = CatalogueFingerprint.calculate(selected);
      if (recomputed != fingerprint) {
        return _failed([
          'Installed catalogue fingerprint mismatch (stored and recomputed values differ).',
        ]);
      }
      final contentFingerprint = CatalogueContract.fingerprint({
        for (final entry in selected.entries)
          if (entry.key != 'brands') entry.key: entry.value,
      });
      if (release['contentFingerprint'] != contentFingerprint) {
        return _failed(['Installed release content fingerprint mismatch.']);
      }
      return structural;
    } on AppException catch (error) {
      return _failed([error.message]);
    } on FormatException catch (error) {
      return _failed([
        'Installed catalogue fingerprint input is invalid: ${error.message}',
      ]);
    }
  }

  static String _documentId(Map<String, dynamic> document) {
    final name = document['name'];
    if (name is String && name.contains('/')) return name.split('/').last;
    final id = document['documentId'];
    if (id is String) return id;
    throw const FormatException('Catalogue document ID is missing.');
  }

  static CatalogueReadinessReport _failed(List<String> errors) =>
      CatalogueReadinessReport(
        state: CatalogueReadinessState.failed,
        errors: List.unmodifiable(errors),
        releaseVersion: null,
        fingerprint: null,
      );

  /// Checks whether catalogue synchronization is required for the active workspace,
  /// and if so, verifies full deep installed catalogue readiness from SQLite.
  /// Returns null if catalogue functionality is legitimately disabled for this workspace.
  static Future<CatalogueReadinessReport?> checkInstalledReadiness(
    LocalDataSource source, {
    bool allowUnapprovedIsolatedForTests = false,
  }) async {
    final hasActiveCatalogueQueries = (await source.db.query(
      'sync_queries',
      where:
          "active=1 AND collectionName IN ('product_catalogue_releases','product_categories')",
      limit: 1,
    )).isNotEmpty;
    if (!hasActiveCatalogueQueries) {
      return null;
    }

    final installedReleases = await source.db.query(
      LocalDataSource.table('product_catalogue_releases'),
      where: "scopeType='SYSTEM' AND isDeleted=0",
      limit: 2,
    );
    if (installedReleases.isEmpty) {
      return null;
    }

    final documents = <String, List<Map<String, dynamic>>>{};
    for (final collection in SystemCatalogueMetadata.collections) {
      final rows = await source.db.query(
        LocalDataSource.table(collection),
        where: "scopeType='SYSTEM' AND isDeleted=0",
        orderBy: 'remoteId',
      );
      documents[collection] = [
        for (final row in rows) LocalDataSource.document(row, collection),
      ];
    }

    return validateInstalled(
      documents,
      allowUnapprovedIsolatedForTests: allowUnapprovedIsolatedForTests,
    );
  }
}

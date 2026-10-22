import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../services/firestore_rest_service.dart';

/// Canonical query identities without classification alias rewriting. Reconcile
/// is explicit maintenance for isolated proof/future review, never an on-open
/// production cleanup. Registration deduplicates only equivalent query specs.
class SyncQueryRegistry {
  /// Phase 8 protected identities, not migration approvals or alias mappings.
  static const protectedLegacyIds = <String>{
    'PM_CATEGORY_93d0611d84196d62',
    'PM_SUBCATEGORY_ce0bf39843417fca',
    'PM_UNIT_3871fc5bdee74d78',
    'SYS_CATEGORY_ACCESSORIES',
    'SYS_CATEGORY_EXTERIOR_WALL_PAINTS',
    'SYS_CATEGORY_FLOOR_COATINGS',
    'SYS_CATEGORY_INDUSTRIAL_COATINGS',
    'SYS_CATEGORY_INTERIOR_WALL_PAINTS',
    'SYS_CATEGORY_METAL_PAINTS',
    'SYS_CATEGORY_PRIMERS_PUTTY',
    'SYS_CATEGORY_WALLPAPERS',
    'SYS_CATEGORY_WALL_TEXTURES',
    'SYS_CATEGORY_WOOD_COATINGS',
    'SYS_SUBCATEGORY_INTERIOR_WALL_COATINGS_CEILING_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_BRUSH',
    'SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_ROLLER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_ACCESSORIES_SANDPAPER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_ECONOMY_EXTERIOR_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_EXTERIOR_EMULSION',
    'SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_PREMIUM_EXTERIOR_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_EXTERIOR_WALL_PAINTS_WEATHER_RESISTANT_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_CONCRETE_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_EPOXY_FLOORING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_FLOOR_COATINGS_FLOOR_PAINT',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_ANTI_CORROSION_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_EPOXY_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_HEAT_RESISTANT_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INDUSTRIAL_COATINGS_PROTECTIVE_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_DISTEMPER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_ECONOMY_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_EMULSION_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_LUXURY_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_INTERIOR_WALL_PAINTS_PREMIUM_PAINTS',
    'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ANTI_CORROSION_PAINT',
    'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_DECORATIVE_METAL_PAINT',
    'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_ENAMEL_PAINT',
    'SYS_SUBCATEGORY_SYS_CATEGORY_METAL_PAINTS_PROTECTIVE_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_EXTERIOR_WALL_PRIMER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_INTERIOR_WALL_PRIMER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WALL_PUTTY',
    'SYS_SUBCATEGORY_SYS_CATEGORY_PRIMERS_PUTTY_WOOD_PRIMER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_DESIGNER_WALLPAPER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_NON_WOVEN_WALLPAPER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_PAPER_WALLPAPER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALLPAPERS_VINYL_WALLPAPER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_3D_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_CONCRETE_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_DESIGNER_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_MARBLE_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_METALLIC_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STONE_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_STUCCO_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WALL_TEXTURES_VELVET_TEXTURE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_BATHROOM_WATERPROOFING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_CRACK_REPAIR',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_DAMP_PROOFING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_TERRACE_WATERPROOFING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WATERPROOFING_WALL_WATERPROOFING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_MELAMINE',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_PU_COATING',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_POLISH',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_SEALER',
    'SYS_SUBCATEGORY_SYS_CATEGORY_WOOD_COATINGS_WOOD_STAIN',
    'SYS_SUBCATEGORY_WATERPROOFING_BASEMENT',
  };

  static dynamic canonical(dynamic value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  static Map<String, dynamic> normalize(Map<String, dynamic> spec) {
    final normalized = Map<String, dynamic>.from(canonical(spec) as Map);
    if (normalized['filters'] is List) {
      final filters = <String, dynamic>{
        for (final f in normalized['filters'] as List) jsonEncode(f): f,
      };
      final keys = filters.keys.toList()..sort();
      normalized['filters'] = [for (final key in keys) filters[key]];
    }
    return normalized;
  }

  static String key(String collection, Map<String, dynamic> spec) =>
      '$collection:${jsonEncode(normalize(spec))}';

  static Set<String> legacyReferences(dynamic value) {
    final found = <String>{};
    void visit(dynamic v) {
      if (v is String && protectedLegacyIds.contains(v)) found.add(v);
      if (v is Map) {
        for (final e in v.entries) {
          visit(e.key);
          visit(e.value);
        }
      }
      if (v is List) {
        for (final e in v) {
          visit(e);
        }
      }
    }

    visit(value);
    return found;
  }

  static Future<List<Map<String, dynamic>>> auditLegacy(
    DatabaseExecutor db,
  ) async => [
    for (final row in await db.query('sync_queries'))
      if (legacyReferences(jsonDecode(row['queryJson'] as String)).isNotEmpty)
        {
          'queryKey': row['queryKey'],
          'active': row['active'],
          'legacyIds': legacyReferences(
            jsonDecode(row['queryJson'] as String),
          ).toList()..sort(),
          'disposition': 'BLOCK_MIGRATION; retain specification pending explicit Phase 8 review',
        },
  ];

  static Future<bool> upsert(
    DatabaseExecutor db,
    String collection,
    Map<String, dynamic> spec, {
    bool active = true,
  }) async {
    final normalized = normalize(spec), identity = key(collection, spec);
    if (legacyReferences(normalized).isNotEmpty) {
      throw const AppException(
        'Protected legacy query reference requires review; no alias rewrite performed.',
        code: 'legacy-query-reference',
      );
    }
    final equivalent = <Map<String, Object?>>[];
    for (final row in await db.query(
      'sync_queries',
      where: 'collectionName=?',
      whereArgs: [collection],
    )) {
      final old =
          jsonDecode(row['queryJson'] as String) as Map<String, dynamic>;
      if (key(collection, old) == identity) equivalent.add(row);
    }
    // Keep the oldest durable cursor when equivalent registrations disagree.
    // Re-reading is safe; selecting the newest cursor could lose unapplied data.
    equivalent.sort(
      (a, b) => (a['cursor'] as String? ?? '').compareTo(
        b['cursor'] as String? ?? '',
      ),
    );
    final chosen = equivalent.isEmpty ? null : equivalent.first;
    final initialized = chosen?['lastSyncedAt'] != null;
    final data = <String, Object?>{
      ...?chosen,
      'queryKey': identity,
      'collectionName': collection,
      'queryJson': jsonEncode(normalized),
      'active': active || equivalent.any((r) => r['active'] == 1) ? 1 : 0,
    };
    for (final row in equivalent) {
      if (row['queryKey'] != identity) {
        await db.delete(
          'sync_queries',
          where: 'queryKey=?',
          whereArgs: [row['queryKey']],
        );
      }
    }
    await db.insert(
      'sync_queries',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return initialized;
  }

  /// Explicit isolated maintenance: dedupe exact equivalents and deactivate
  /// narrower obsolete SYSTEM queries covered by an initialized broad query.
  /// Protected legacy specs are retained byte-for-byte and reported as blockers.
  static Future<void> reconcile(
    DatabaseExecutor db,
    Set<String> catalogueCollections,
  ) async {
    final rows = await db.query('sync_queries');
    for (final row in rows) {
      final spec =
          jsonDecode(row['queryJson'] as String) as Map<String, dynamic>;
      if (legacyReferences(spec).isNotEmpty) continue;
      await upsert(
        db,
        row['collectionName'] as String,
        spec,
        active: row['active'] == 1,
      );
    }
    for (final collection in catalogueCollections) {
      final current = await db.query(
        'sync_queries',
        where: 'collectionName=?',
        whereArgs: [collection],
      );
      bool broad(Map<String, dynamic> spec) {
        final filters = spec['filters'];
        return spec['id'] == null &&
            filters is List &&
            filters.length == 1 &&
            filters.single['field'] == 'scopeType' &&
            filters.single['operation'] == 'EQUAL' &&
            FirestoreRestService.decodeValue(filters.single['value']) ==
                'SYSTEM';
      }

      if (!current.any(
        (r) =>
            r['lastSyncedAt'] != null &&
            broad(jsonDecode(r['queryJson'] as String) as Map<String, dynamic>),
      )) {
        continue;
      }
      for (final row in current) {
        final spec =
            jsonDecode(row['queryJson'] as String) as Map<String, dynamic>;
        final filters = spec['filters'];
        if (legacyReferences(spec).isEmpty &&
            !broad(spec) &&
            filters is List &&
            filters.any(
              (f) =>
                  f['field'] == 'scopeType' &&
                  f['operation'] == 'EQUAL' &&
                  FirestoreRestService.decodeValue(f['value']) == 'SYSTEM',
            )) {
          await db.update(
            'sync_queries',
            {'active': 0},
            where: 'queryKey=?',
            whereArgs: [row['queryKey']],
          );
        }
      }
    }
  }
}

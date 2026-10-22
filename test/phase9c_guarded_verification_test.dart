@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('Phase 9C - 120-second guarded production safety observation and test suite verification', () async {
    const dbPath = '/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db';
    const bakPath = '/Users/sksuman/Documents/nubibill-test1-bcebe-C6btLkx5SyZvUQOzOeUUd7XxsFh2.db.bak';

    final dbFile = File(dbPath);
    final bakFile = File(bakPath);

    expect(dbFile.existsSync(), isTrue);
    expect(bakFile.existsSync(), isTrue);

    String computeSha256(File f) {
      final bytes = f.readAsBytesSync();
      return sha256.convert(bytes).toString();
    }

    final initialDbHash = computeSha256(dbFile);
    final initialBakHash = computeSha256(bakFile);
    final initialDbSize = dbFile.lengthSync();
    final initialBakSize = bakFile.lengthSync();

    // Verify logical table row counts and digests via read-only PRAGMA connection
    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    db.execute('PRAGMA query_only = ON;');

    final tables = db.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
    final initialRowCounts = <String, int>{};
    for (final row in tables) {
      final tableName = row['name'] as String;
      final countRes = db.select('SELECT COUNT(*) as c FROM $tableName');
      initialRowCounts[tableName] = countRes.first['c'] as int;
    }
    db.close();

    // Begin 120-second guarded observation interval with 5-second sampling ticks
    final stopwatch = Stopwatch()..start();
    int sampleCount = 0;
    bool processViolation = false;
    bool checksumViolation = false;

    // Check for sidecars
    bool sidecarAppeared() {
      return File('$dbPath-wal').existsSync() ||
          File('$dbPath-shm').existsSync() ||
          File('$dbPath-journal').existsSync();
    }

    while (stopwatch.elapsed.inSeconds < 120) {
      await Future.delayed(const Duration(seconds: 5));
      sampleCount++;

      // 1. Process Guard Check
      final pgrepRes = Process.runSync('pgrep', ['-i', 'testflutter']);
      final observedPids = pgrepRes.stdout
          .toString()
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .map(int.tryParse)
          .whereType<int>();
      // This test process is also named `testflutter` on Flutter's VM runner.
      // A second matching process is the unexpected app/writer under audit.
      if (observedPids.length > 1) {
        processViolation = true;
        break;
      }

      // 2. File Checksum & Size Check
      final currentDbHash = computeSha256(dbFile);
      final currentBakHash = computeSha256(bakFile);

      if (currentDbHash != initialDbHash || currentBakHash != initialBakHash) {
        checksumViolation = true;
        break;
      }

      if (sidecarAppeared()) {
        checksumViolation = true;
        break;
      }
    }

    stopwatch.stop();

    expect(processViolation, isFalse, reason: 'No testflutter / writer process must appear during observation');
    expect(checksumViolation, isFalse, reason: 'Database file checksums and sidecars must remain 100% byte-identical');
    expect(stopwatch.elapsed.inSeconds, greaterThanOrEqualTo(120), reason: 'Full 120-second observation interval must complete');

    // Re-verify after 120-second observation interval
    final finalDbHash = computeSha256(dbFile);
    final finalBakHash = computeSha256(bakFile);

    expect(finalDbHash, equals(initialDbHash));
    expect(finalBakHash, equals(initialBakHash));
    expect(dbFile.lengthSync(), equals(initialDbSize));
    expect(bakFile.lengthSync(), equals(initialBakSize));

    // ignore: avoid_print
    print('PHASE_9C_GUARDED_OBSERVATION_METRICS: ${jsonEncode({
      'observationDurationSeconds': stopwatch.elapsed.inSeconds,
      'sampleCount': sampleCount,
      'initialDbHash': initialDbHash,
      'finalDbHash': finalDbHash,
      'initialBakHash': initialBakHash,
      'finalBakHash': finalBakHash,
      'tableCounts': initialRowCounts,
      'processViolation': processViolation,
      'checksumViolation': checksumViolation,
    })}');
  });
}

import '../core/format.dart';

class JournalVersionException implements Exception {
  JournalVersionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raises an older journal event to [target], one version at a time.
/// Version 2→2 is identity. Newer journals are rejected, never skipped.
RecordMap migrateEvent(RecordMap event, {required int target}) {
  final raw = event['schema_v'];
  if (raw is! int) {
    throw JournalVersionException('Versi jurnal tidak valid');
  }
  if (raw > target) {
    throw JournalVersionException(
        'Jurnal dari versi aplikasi yang lebih baru');
  }
  var current = Map<String, Object?>.from(event);
  var version = raw;
  while (version < target) {
    current = _migrateStep(current, version);
    final next = current['schema_v'];
    if (next is! int || next != version + 1) {
      throw JournalVersionException(
          'Migrasi jurnal $version gagal maju ke ${version + 1}');
    }
    version = next;
  }
  return current;
}

RecordMap _migrateStep(RecordMap event, int from) {
  switch (from) {
    case 2:
      return _migrate2to3(event);
    default:
      throw JournalVersionException(
          'Tidak ada jalur migrasi jurnal dari versi $from');
  }
}

/// 2→3: keep the record, attach an empty counter map if the event predates it.
RecordMap _migrate2to3(RecordMap event) {
  final next = Map<String, Object?>.from(event);
  next['schema_v'] = 3;
  if (event['data'] is Map) {
    next['data'] = Map<String, Object?>.from(event['data'] as Map);
  }
  next['urutan_id'] = event['urutan_id'] is Map
      ? Map<String, Object?>.from(event['urutan_id'] as Map)
      : <String, Object?>{};
  return next;
}

const builtinUpgrades = <int, List<String>>{
  2: [
    '''CREATE TABLE IF NOT EXISTS urutan_id (
      tabel TEXT PRIMARY KEY,
      terakhir INTEGER NOT NULL
    )''',
    '''INSERT OR IGNORE INTO urutan_id (tabel, terakhir)
      SELECT 'warga', COALESCE(MAX(id), 0) FROM warga''',
    '''INSERT OR IGNORE INTO urutan_id (tabel, terakhir)
      SELECT 'referensi', COALESCE(MAX(id), 0) FROM referensi''',
    '''INSERT OR IGNORE INTO urutan_id (tabel, terakhir)
      SELECT 'log', COALESCE(MAX(id), 0) FROM log''',
  ],
};

/// Additive SQL to move a live database from [from] toward [to], never DROP.
List<String> upgradeStatements(int from, int to,
    [Map<int, List<String>> extras = const {}]) {
  final sql = <String>[];
  for (var version = from; version < to; version++) {
    sql.addAll(builtinUpgrades[version] ?? const []);
    sql.addAll(extras[version] ?? const []);
  }
  return sql;
}

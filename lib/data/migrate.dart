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
    throw JournalVersionException('Jurnal dari versi aplikasi yang lebih baru');
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
    case 3:
      return _migrate3to4(event);
    case 4:
      return _migrate4to5(event);
    case 5:
      return _migrate5to6(event);
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

/// 3→4: keep the record, attach kode_wilayah=null. Never guess from desa.
RecordMap _migrate3to4(RecordMap event) {
  final next = Map<String, Object?>.from(event);
  next['schema_v'] = 4;
  final data = event['data'];
  if (data is! Map) return next;
  final copy = Map<String, Object?>.from(data);
  final table = event['tabel'];
  if (table == 'warga') {
    copy.putIfAbsent('kode_wilayah', () => null);
  } else if (table == 'referensi') {
    if (copy['records'] is List) {
      copy['records'] = [
        for (final raw in copy['records'] as List)
          raw is Map
              ? {
                  ...Map<String, Object?>.from(raw),
                  if (!raw.containsKey('kode_wilayah')) 'kode_wilayah': null,
                }
              : raw
      ];
    } else {
      copy.putIfAbsent('kode_wilayah', () => null);
    }
  }
  next['data'] = copy;
  return next;
}

/// 4→5: drop sumber_input from warga payloads. The live column is left in
/// place on existing databases (upgrades stay additive). Verified: the v4
/// definition was `sumber_input TEXT NOT NULL DEFAULT 'LAPANGAN'`, so inserts
/// that omit the column keep working and no builtinUpgrades[4] is needed.
RecordMap _migrate4to5(RecordMap event) {
  final next = Map<String, Object?>.from(event);
  next['schema_v'] = 5;
  final data = event['data'];
  if (data is! Map) return next;
  final copy = Map<String, Object?>.from(data);
  if (event['tabel'] == 'warga') {
    copy.remove('sumber_input');
  }
  next['data'] = copy;
  return next;
}

/// 5→6: card colour is optional TEXT and never scored.
RecordMap _migrate5to6(RecordMap event) {
  final next = Map<String, Object?>.from(event);
  next['schema_v'] = 6;
  final data = event['data'];
  if (data is! Map) return next;
  final copy = Map<String, Object?>.from(data);
  if (event['tabel'] == 'warga') {
    copy.putIfAbsent('warna', () => null);
  }
  next['data'] = copy;
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
  3: [
    'ALTER TABLE warga ADD COLUMN kode_wilayah TEXT',
    'ALTER TABLE referensi ADD COLUMN kode_wilayah TEXT',
    'CREATE INDEX IF NOT EXISTS idx_warga_kode ON warga(kode_wilayah)',
    '''CREATE TABLE IF NOT EXISTS lokasi (
      kode          TEXT PRIMARY KEY,
      nama_desa     TEXT NOT NULL,
      nama_kec      TEXT,
      nama_kab      TEXT,
      nama_prov     TEXT,
      kode_kec      TEXT,
      nik_prefix    TEXT,
      sumber_versi  TEXT,
      manual        INTEGER NOT NULL DEFAULT 0,
      dicatat_pada  TEXT NOT NULL
    )''',
    '''INSERT OR IGNORE INTO urutan_id (tabel, terakhir)
      SELECT 'lokasi', 0''',
  ],
  5: [
    'ALTER TABLE warga ADD COLUMN warna TEXT',
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

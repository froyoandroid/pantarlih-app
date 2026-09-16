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

/// 2→3: payload shape unchanged. A later additive column stays NULL.
RecordMap _migrate2to3(RecordMap event) {
  final next = Map<String, Object?>.from(event);
  next['schema_v'] = 3;
  if (event['data'] is Map) {
    next['data'] = Map<String, Object?>.from(event['data'] as Map);
  }
  return next;
}

/// Additive SQL to move a live database from [from] toward [to], never DROP.
List<String> upgradeStatements(int from, int to,
    [Map<int, List<String>> extras = const {}]) {
  final sql = <String>[];
  for (var version = from; version < to; version++) {
    sql.addAll(extras[version] ?? const []);
  }
  return sql;
}

import 'package:sqflite/sqflite.dart';

/// Next sparse key at the end of one RT. Gaps of 999 stay available for inserts.
Future<int> urutAkhir(DatabaseExecutor db, int rw, int rt) async {
  final rows = await db.rawQuery(
      'SELECT COALESCE(MAX(urut_sort), 0) AS m FROM warga '
      'WHERE rw = ? AND rt = ?',
      [rw, rt]);
  return (rows.first['m'] as int) + 1000;
}

/// Midpoint between two existing keys. Either side may be null (list edge).
/// Returns null when the gap is exhausted so the caller can renumber.
int? urutAntara(int? sebelum, int? sesudah) {
  if (sebelum == null && sesudah == null) return 1000;
  if (sebelum == null) return sesudah! - 1000 > 0 ? sesudah - 1000 : null;
  if (sesudah == null) return sebelum + 1000;
  if (sesudah - sebelum < 2) return null;
  return sebelum + ((sesudah - sebelum) ~/ 2);
}

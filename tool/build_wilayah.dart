import 'dart:convert';
import 'dart:io';

import 'package:tiliksuara/core/nama.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Counts from the source README table (Kepmendagri 2025), used as a
/// build-time gate. A mismatch means the dump and the documented pack
/// drifted, so this script must fail rather than emit a half-built asset.
const expectedCounts = {1: 38, 2: 514, 3: 7285, 4: 83762};

const kepmendagri = 'Kepmendagri No. 300.2.2-2430 Tahun 2025';
const sourceSha = 'd68e8d5516f969d1905d0b2940f20034becb0db7';
const builtAt = '2026-09-16T00:00:00.000+07:00';

class WilayahRow {
  WilayahRow(this.kode, this.nama);
  final String kode;
  final String nama;
  int get level {
    switch (kode.length) {
      case 2:
        return 1;
      case 5:
        return 2;
      case 8:
        return 3;
      case 13:
        return 4;
      default:
        throw FormatException('Panjang kode tidak dikenal: $kode');
    }
  }

  String? get induk {
    final index = kode.lastIndexOf('.');
    return index < 0 ? null : kode.substring(0, index);
  }

  String get kodePolos => kode.replaceAll('.', '');
}

List<WilayahRow> parseWilayahInserts(String sql) {
  final withoutBlock = sql.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final pair = RegExp(r"\('((?:[^']|'')*)','((?:[^']|'')*)'\)");
  final rows = <WilayahRow>[];
  for (final line in withoutBlock.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('--')) continue;
    for (final match in pair.allMatches(trimmed)) {
      rows.add(WilayahRow(match.group(1)!.replaceAll("''", "'"),
          match.group(2)!.replaceAll("''", "'")));
    }
  }
  return rows;
}

Directory repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'pubspec.yaml tidak ditemukan dari ${Directory.current.path}');
    }
    dir = parent;
  }
}

String? parseProv(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--prov=')) {
      final value = arg.substring('--prov='.length).trim();
      if (!RegExp(r'^\d{2}$').hasMatch(value)) {
        throw ArgumentError('Nilai --prov harus dua digit, contoh --prov=33');
      }
      return value;
    }
  }
  return null;
}

void verify(List<WilayahRow> rows, {required bool fullPack}) {
  final seen = <String>{};
  for (final row in rows) {
    if (!seen.add(row.kode)) {
      throw StateError('Kode duplikat: ${row.kode}');
    }
  }
  final missing = <String>[];
  for (final row in rows) {
    final parent = row.induk;
    if (parent != null && !seen.contains(parent)) {
      missing.add('${row.kode} induk $parent');
    }
  }
  if (missing.isNotEmpty) {
    throw StateError(
        'Induk hilang (${missing.length}): ${missing.take(8).join(', ')}');
  }
  if (!fullPack) return;
  final byLevel = <int, int>{1: 0, 2: 0, 3: 0, 4: 0};
  for (final row in rows) {
    byLevel[row.level] = (byLevel[row.level] ?? 0) + 1;
  }
  for (final entry in expectedCounts.entries) {
    if (byLevel[entry.key] != entry.value) {
      throw StateError(
          'Jumlah level ${entry.key} = ${byLevel[entry.key]}, diharapkan ${entry.value}');
    }
  }
}

Future<void> writePack(
    {required List<WilayahRow> rows,
    required File dbFile,
    required File metaFile,
    required bool fullPack}) async {
  verify(rows, fullPack: fullPack);
  rows.sort((a, b) => a.kode.compareTo(b.kode));
  final byLevel = <int, int>{1: 0, 2: 0, 3: 0, 4: 0};
  for (final row in rows) {
    byLevel[row.level] = (byLevel[row.level] ?? 0) + 1;
  }
  final tmp = File('${dbFile.path}.tmp');
  if (await tmp.exists()) await tmp.delete();
  if (await dbFile.exists()) await dbFile.delete();
  final db = await openDatabase(tmp.path);
  try {
    await db.execute('PRAGMA journal_mode = OFF');
    await db.execute('PRAGMA synchronous = OFF');
    await db.execute('''
CREATE TABLE wilayah (
  kode        TEXT PRIMARY KEY,
  nama        TEXT NOT NULL,
  level       INTEGER NOT NULL,
  induk       TEXT,
  nama_norm   TEXT NOT NULL,
  kode_polos  TEXT NOT NULL
)''');
    await db.execute('''
CREATE TABLE wilayah_meta (
  kunci TEXT PRIMARY KEY,
  nilai TEXT
)''');
    const chunk = 800;
    for (var i = 0; i < rows.length; i += chunk) {
      final end = i + chunk < rows.length ? i + chunk : rows.length;
      final batch = db.batch();
      for (final row in rows.sublist(i, end)) {
        batch.insert('wilayah', {
          'kode': row.kode,
          'nama': row.nama,
          'level': row.level,
          'induk': row.induk,
          'nama_norm': normalisasiNama(row.nama),
          'kode_polos': row.kodePolos,
        });
      }
      await batch.commit(noResult: true);
    }
    await db.execute('CREATE INDEX idx_wil_induk ON wilayah(induk, nama)');
    await db.execute('CREATE INDEX idx_wil_norm ON wilayah(nama_norm)');
    await db.execute('CREATE INDEX idx_wil_level ON wilayah(level, nama)');
    final meta = <String, String>{
      'kepmendagri': kepmendagri,
      'sha_sumber': sourceSha,
      'dibuat_pada': builtAt,
      'jumlah_total': '${rows.length}',
      'jumlah_prov': '${byLevel[1]}',
      'jumlah_kab': '${byLevel[2]}',
      'jumlah_kec': '${byLevel[3]}',
      'jumlah_desa': '${byLevel[4]}',
      if (!fullPack) 'filter_prov': rows.first.kode.substring(0, 2),
    };
    final metaBatch = db.batch();
    for (final entry in meta.entries) {
      metaBatch
          .insert('wilayah_meta', {'kunci': entry.key, 'nilai': entry.value});
    }
    await metaBatch.commit(noResult: true);
    await db.execute('VACUUM');
  } catch (e) {
    await db.close();
    if (await tmp.exists()) await tmp.delete();
    rethrow;
  }
  await db.close();
  await tmp.rename(dbFile.path);
  final json = const JsonEncoder.withIndent('  ').convert({
    ...{
      'kepmendagri': kepmendagri,
      'sha_sumber': sourceSha,
      'dibuat_pada': builtAt,
      'jumlah_total': rows.length,
      'jumlah_prov': byLevel[1],
      'jumlah_kab': byLevel[2],
      'jumlah_kec': byLevel[3],
      'jumlah_desa': byLevel[4],
    },
    if (!fullPack) 'filter_prov': rows.first.kode.substring(0, 2),
  });
  await metaFile.writeAsString('$json\n');
}

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final root = repoRoot();
  final sqlFile = File('${root.path}/third_party/wilayah/wilayah.sql');
  if (!await sqlFile.exists()) {
    stderr.writeln('Berkas sumber tidak ada: ${sqlFile.path}');
    exit(1);
  }
  final prov = parseProv(args);
  var rows = parseWilayahInserts(await sqlFile.readAsString());
  if (rows.isEmpty) {
    stderr.writeln('Tidak ada baris INSERT yang terbaca.');
    exit(1);
  }
  if (prov != null) {
    rows = [
      for (final row in rows)
        if (row.kode == prov || row.kode.startsWith('$prov.')) row
    ];
    if (rows.isEmpty) {
      stderr.writeln('Tidak ada baris untuk --prov=$prov');
      exit(1);
    }
  }
  final assets = Directory('${root.path}/assets');
  await assets.create(recursive: true);
  final dbFile = File('${assets.path}/wilayah.db');
  final metaFile = File('${assets.path}/wilayah.meta.json');
  try {
    await writePack(
        rows: rows, dbFile: dbFile, metaFile: metaFile, fullPack: prov == null);
  } catch (e) {
    stderr.writeln('Build wilayah gagal: $e');
    if (await dbFile.exists()) await dbFile.delete();
    if (await metaFile.exists()) await metaFile.delete();
    exit(1);
  }
  stdout.writeln(
      'OK ${rows.length} baris → ${dbFile.path} (${await dbFile.length()} byte)');
}

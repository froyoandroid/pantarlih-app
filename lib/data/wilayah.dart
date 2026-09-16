import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/nama.dart';

class Wilayah {
  const Wilayah({
    required this.kode,
    required this.nama,
    required this.level,
    this.induk,
    required this.namaNorm,
    required this.kodePolos,
  });
  final String kode;
  final String nama;
  final int level;
  final String? induk;
  final String namaNorm;
  final String kodePolos;

  factory Wilayah.fromRow(Map<String, Object?> row) => Wilayah(
        kode: row['kode'] as String,
        nama: row['nama'] as String,
        level: row['level'] as int,
        induk: row['induk'] as String?,
        namaNorm: row['nama_norm'] as String,
        kodePolos: row['kode_polos'] as String,
      );
}

class Lokasi {
  const Lokasi({
    required this.kode,
    required this.namaDesa,
    this.namaKec,
    this.namaKab,
    this.namaProv,
    this.kodeKec,
    this.nikPrefix,
    this.sumberVersi,
    this.manual = false,
    required this.dicatatPada,
  });
  final String kode;
  final String namaDesa;
  final String? namaKec;
  final String? namaKab;
  final String? namaProv;
  final String? kodeKec;
  final String? nikPrefix;
  final String? sumberVersi;
  final bool manual;
  final String dicatatPada;

  factory Lokasi.fromRow(Map<String, Object?> row) => Lokasi(
        kode: '${row['kode']}',
        namaDesa: '${row['nama_desa']}',
        namaKec: row['nama_kec'] as String?,
        namaKab: row['nama_kab'] as String?,
        namaProv: row['nama_prov'] as String?,
        kodeKec: row['kode_kec'] as String?,
        nikPrefix: row['nik_prefix'] as String?,
        sumberVersi: row['sumber_versi'] as String?,
        manual: (row['manual'] as int? ?? 0) == 1,
        dicatatPada: '${row['dicatat_pada'] ?? ''}',
      );

  Map<String, Object?> toRow() => {
        'kode': kode,
        'nama_desa': namaDesa,
        'nama_kec': namaKec,
        'nama_kab': namaKab,
        'kode_kec': kodeKec,
        'nama_prov': namaProv,
        'nik_prefix': nikPrefix,
        'sumber_versi': sumberVersi,
        'manual': manual ? 1 : 0,
        'dicatat_pada': dicatatPada,
      };
}

String kodeLokasiManual(String namaDesa) {
  final slug = namaDesa
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'MANUAL:${slug.isEmpty ? 'tanpa_nama' : slug}';
}

/// Read-only Kemendagri pack. Never journaled, never part of rebuild().
class WilayahRepo {
  WilayahRepo._(this._db, this.path, [this.alasanGagal]);
  final Database? _db;
  final String? path;

  /// Why the pack failed to open, shown in the UI when unavailable.
  final String? alasanGagal;
  bool get available => _db != null;

  factory WilayahRepo.unavailable([String? alasan]) =>
      WilayahRepo._(null, null, alasan);

  static Future<WilayahRepo> open({
    Directory? supportDir,
    File? assetFile,
    Map<String, String>? bundledMeta,
    AssetBundle? bundle,
    DatabaseFactory? factory,
  }) async {
    try {
      final meta = bundledMeta ?? await _metaFromBundle(bundle);
      final sha = meta['sha_sumber'] ?? 'unknown';
      final short = sha.length >= 12 ? sha.substring(0, 12) : sha;
      final support = supportDir ?? await getApplicationSupportDirectory();
      final dest = File('${support.path}/wilayah_$short.db');
      if (!await dest.exists()) {
        await dest.parent.create(recursive: true);
        if (assetFile != null) {
          if (!await assetFile.exists()) {
            throw StateError('Aset wilayah tidak ditemukan');
          }
          await assetFile.copy(dest.path);
        } else {
          final data = await (bundle ?? rootBundle).load('assets/wilayah.db');
          await dest.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true);
        }
      }
      final opener = factory ?? databaseFactory;
      final db = await opener.openDatabase(dest.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: true));
      return WilayahRepo._(db, dest.path);
    } catch (e, st) {
      debugPrint('WilayahRepo gagal dibuka: $e\n$st');
      return WilayahRepo.unavailable('$e');
    }
  }

  static Future<Map<String, String>> _metaFromBundle(
      AssetBundle? bundle) async {
    try {
      final raw =
          await (bundle ?? rootBundle).loadString('assets/wilayah.meta.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {'sha_sumber': 'unknown'};
      return {for (final e in decoded.entries) '${e.key}': '${e.value}'};
    } catch (_) {
      return {'sha_sumber': 'unknown'};
    }
  }

  Future<List<Wilayah>> anak(String? indukKode) async {
    final db = _db;
    if (db == null) return [];
    final rows = indukKode == null
        ? await db.query('wilayah', where: 'level = 1', orderBy: 'nama')
        : await db.query('wilayah',
            where: 'induk = ?', whereArgs: [indukKode], orderBy: 'nama');
    return rows.map(Wilayah.fromRow).toList();
  }

  Future<List<Wilayah>> cari(String query, {int? level, String? dalam}) async {
    final db = _db;
    if (db == null) return [];
    final norm = normalisasiNama(query);
    if (norm.length < 3) return [];
    final where = <String>['nama_norm LIKE ?'];
    final args = <Object?>['%${norm.replaceAll(RegExp(r'[%_]'), '')}%'];
    if (level != null) {
      where.add('level = ?');
      args.add(level);
    }
    if (dalam != null && dalam.isNotEmpty) {
      where.add('(kode = ? OR kode LIKE ?)');
      args.add(dalam);
      args.add('$dalam.%');
    }
    final rows = await db.query('wilayah',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'nama',
        limit: 50);
    return rows.map(Wilayah.fromRow).toList();
  }

  Future<Wilayah?> byKode(String kode) async {
    final db = _db;
    if (db == null) return null;
    final rows =
        await db.query('wilayah', where: 'kode = ?', whereArgs: [kode]);
    return rows.isEmpty ? null : Wilayah.fromRow(rows.first);
  }

  /// Province, kabupaten, kecamatan chain of a kode. Depth is capped and
  /// visited codes tracked so a corrupt pack (self- or cyclic induk) cannot
  /// spin the UI forever.
  Future<List<Wilayah>> leluhur(String kode) async {
    final chain = <Wilayah>[];
    final seen = <String>{kode};
    var current = await byKode(kode);
    while (current != null && current.induk != null && chain.length < 4) {
      final parentKode = current.induk!;
      if (seen.contains(parentKode)) break;
      final parent = await byKode(parentKode);
      if (parent == null) break;
      seen.add(parentKode);
      chain.insert(0, parent);
      current = parent;
    }
    return chain;
  }

  Future<Map<String, String>> meta() async {
    final db = _db;
    if (db == null) return {};
    final rows = await db.query('wilayah_meta');
    return {
      for (final row in rows)
        row['kunci'] as String: row['nilai'] as String? ?? ''
    };
  }

  Future<String> jalur(String kode) async {
    final self = await byKode(kode);
    return [
      ...await leluhur(kode),
      if (self != null) self,
    ].map((w) => w.nama).join(' · ');
  }

  Future<void> close() async {
    try {
      await _db?.close();
    } catch (_) {/* already closed */}
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/format.dart';
import '../core/nama.dart';
import 'migrate.dart';
import 'order.dart';
import 'schema.dart';

class AppException implements Exception {
  AppException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RecoveryReport {
  int processed = 0;
  int applied = 0;
  int failed = 0;
  String? failurePath;
  String? previousDatabase;
  @override
  String toString() =>
      '$processed baris diproses · $applied diterapkan · $failed gagal';
}

/// One serialized writer. Journal is appended first, then SQLite commits.
class AppStore extends ChangeNotifier {
  AppStore(this.root,
      {DatabaseFactory? factory,
      this.schemaV = schemaVersion,
      this.upgrades = const {}})
      : factory = factory ?? databaseFactory;
  final Directory root;
  final DatabaseFactory factory;
  final int schemaV;
  final Map<int, List<String>> upgrades;
  late Database db;
  Future<void> _tail = Future<void>.value();
  bool _recoveryRequired = false;
  RecoveryReport? startupRecovery;
  String get dbPath => '${root.path}/pantarlih.db';

  Future<T> exclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> open() async {
    for (final path in [
      'journal',
      'import/raw',
      'import/parsed',
      'import/ready',
      'snapshot',
      'export/auto',
      'export/manual',
      'recovered'
    ]) {
      await Directory('${root.path}/$path').create(recursive: true);
    }
    try {
      await _snapshotBeforeUpgrade(dbPath);
      db = await _openDatabase(dbPath);
      final check = await db.rawQuery('PRAGMA quick_check');
      if (check.any((row) => row.values.first != 'ok')) {
        throw AppException('Pemeriksaan integritas database gagal');
      }
      startupRecovery = await _replay(db);
      await trimStoredText();
    } catch (e) {
      throw AppException(
          'Database tidak dapat dibuka. Berkas aman di ${root.path}. '
          'Gunakan pemulihan dari jurnal. Detail: $e');
    }
  }

  Future<int?> _userVersion(String path) async {
    final file = File(path);
    if (!await file.exists() || await file.length() < 64) return null;
    final bytes = await file.openRead(60, 64).first;
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  Future<void> _snapshotBeforeUpgrade(String path) async {
    final current = await _userVersion(path);
    if (current == null || current >= schemaV) return;
    final stamp = fileStamp();
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File('$path$suffix');
      if (!await source.exists()) continue;
      await source.copy('${root.path}/snapshot/pre_migrasi_$stamp.db$suffix');
    }
  }

  Future<void> _applySchema(Database db, int version) async {
    for (final sql in schemaStatements) {
      await db.execute(sql);
    }
    for (final sql
        in upgradeStatements(schemaBaseVersion, version, upgrades)) {
      await db.execute(sql);
    }
  }

  Future<Database> _openDatabase(String path) => factory.openDatabase(path,
      options: OpenDatabaseOptions(
          version: schemaV,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
            await db.rawQuery('PRAGMA journal_mode = WAL');
          },
          onCreate: (db, version) => _applySchema(db, version),
          onUpgrade: (db, oldVersion, newVersion) async {
            for (final sql
                in upgradeStatements(oldVersion, newVersion, upgrades)) {
              await db.execute(sql);
            }
          }));

  Future<Map<String, String>> settings() async {
    final rows = await db.query('setelan');
    return {
      'rt_aktif': '3',
      'rw_aktif': '3',
      'desa_default': 'KALITORONG',
      'schema_v': '$schemaV',
      for (final row in rows)
        row['kunci'] as String: row['nilai'] as String? ?? ''
    };
  }

  Future<void> setSession(int rt, int rw) async {
    await _commit(
        'UPDATE',
        'setelan',
        (txn, ts) async => {
              'records': [
                {'kunci': 'rt_aktif', 'nilai': '$rt'},
                {'kunci': 'rw_aktif', 'nilai': '$rw'},
                {'kunci': 'desa_default', 'nilai': 'KALITORONG'},
                {'kunci': 'schema_v', 'nilai': '$schemaV'},
              ]
            });
  }

  Future<bool> _hasUrutanId(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='urutan_id'");
    return rows.isNotEmpty;
  }

  Future<int> _maxId(DatabaseExecutor txn, String table) async {
    final rows = await txn
        .rawQuery('SELECT COALESCE(MAX(id), 0) AS id FROM $table');
    return intValue(rows.first['id']);
  }

  Future<int> _nextId(DatabaseExecutor txn, String table) async {
    if (!await _hasUrutanId(txn)) {
      return await _maxId(txn, table) + 1;
    }
    final rows = await txn
        .query('urutan_id', where: 'tabel = ?', whereArgs: [table]);
    final last = rows.isEmpty ? 0 : intValue(rows.first['terakhir']);
    final seen = await _maxId(txn, table);
    final next = (last > seen ? last : seen) + 1;
    await txn.insert(
        'urutan_id',
        {'tabel': table, 'terakhir': next},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return next;
  }

  Future<RecordMap> _idCounters(DatabaseExecutor txn) async {
    if (!await _hasUrutanId(txn)) return {};
    final rows = await txn.query('urutan_id');
    return {
      for (final row in rows) row['tabel'] as String: row['terakhir'],
    };
  }

  Future<void> _applyCounters(DatabaseExecutor txn, Object? raw) async {
    if (raw is! Map || !await _hasUrutanId(txn)) return;
    for (final entry in raw.entries) {
      await txn.insert(
          'urutan_id',
          {'tabel': '${entry.key}', 'terakhir': intValue(entry.value)},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  RecordMap _full(Iterable<String> columns, RecordMap source) => {
        for (final column in columns) column: source[column],
      };

  Future<RecordMap> _commit(String op, String table,
          Future<RecordMap> Function(Transaction txn, String ts) prepare,
          {List<RecordMap> Function(RecordMap payload)? extras}) =>
      exclusive(() async {
        if (_recoveryRequired) {
          throw AppException(
              'Pulihkan database dari jurnal sebelum melanjutkan.');
        }
        var journalWritten = false;
        try {
          final result = await db.transaction((txn) async {
            final ts = timestamp();
            final payload = await prepare(txn, ts);
            final events = <RecordMap>[
              if (extras != null) ...extras(payload),
              {
                'schema_v': schemaV,
                'ts': ts,
                'op': op,
                'tabel': table,
                'row_id': payload['id'] ?? payload['row_id'],
                'data': payload,
              }
            ];
            for (final event in events) {
              event['schema_v'] = schemaV;
              event['ts'] = event['ts'] ?? ts;
              event['event_id'] = await _nextId(txn, 'log');
            }
            final counters = await _idCounters(txn);
            for (final event in events) {
              event['urutan_id'] = counters;
              await _appendJournal(event);
              journalWritten = true;
              await _applyEvent(txn, event);
            }
            return payload;
          });
          notifyListeners();
          return result;
        } catch (e) {
          if (journalWritten) {
            _recoveryRequired = true;
            throw AppException(
                'Jurnal sudah tersimpan, tetapi database gagal diperbarui. '
                'Jangan input ulang, bangun ulang dari jurnal. Detail: $e');
          }
          rethrow;
        }
      });

  Future<void> _appendJournal(RecordMap event) async {
    final date = event['ts'].toString().substring(0, 10);
    final file = File('${root.path}/journal/$date.jsonl');
    final handle = await file.open(mode: FileMode.append);
    try {
      final length = await handle.length();
      if (length > 0) {
        final reader = await file.open();
        try {
          await reader.setPosition(length - 1);
          if (await reader.readByte() != 10) await handle.writeByte(10);
        } finally {
          await reader.close();
        }
      }
      await handle.writeString('${jsonEncode(event)}\n');
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<void> _applyEvent(DatabaseExecutor txn, RecordMap event) async {
    late RecordMap migrated;
    try {
      migrated = migrateEvent(event, target: schemaV);
    } catch (e) {
      throw AppException('$e');
    }
    event = migrated;
    if (event['schema_v'] != schemaV) {
      throw AppException('Versi jurnal tidak didukung');
    }
    final data = Map<String, Object?>.from(event['data'] as Map);
    final table = event['tabel'];
    final op = event['op'];
    if (table == 'referensi' && op == 'IMPORT') {
      for (final raw in data['records'] as List) {
        await txn.insert('referensi', Map<String, Object?>.from(raw as Map));
      }
    } else if (table == 'referensi' && op == 'DELETE') {
      await txn.delete('referensi');
    } else if (table == 'warga') {
      if (op == 'INSERT') {
        await txn.insert('warga', _full(wargaColumns, data));
      } else if (op == 'UPDATE') {
        final record = _full(wargaColumns, data);
        final count = await txn.update('warga', record,
            where: 'id = ?', whereArgs: [record['id']]);
        if (count != 1) {
          throw AppException('Baris warga ${record['id']} tidak ditemukan');
        }
      } else if (op == 'DELETE') {
        await txn.delete('warga', where: 'id = ?', whereArgs: [data['id']]);
      } else if (op == 'REORDER' || op == 'RENUMBER') {
        await _applyUrutMap(txn, data['peta'] as Map);
      } else {
        throw AppException('Operasi warga tidak dikenal: $op');
      }
    } else if (table == 'setelan' && op == 'UPDATE') {
      for (final raw in data['records'] as List) {
        await txn.insert('setelan', Map<String, Object?>.from(raw as Map),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } else if (!(table == 'export' && op == 'EXPORT')) {
      throw AppException('Operasi jurnal tidak dikenal: $table/$op');
    }
    await _applyCounters(txn, event['urutan_id']);
    await txn.insert('log', {
      'id': event['event_id'],
      'ts': event['ts'],
      'op': op,
      'tabel': table,
      'row_id': event['row_id'],
      'payload': jsonEncode(data),
      'schema_v': event['schema_v'],
    });
  }

  Future<void> _applyUrutMap(DatabaseExecutor txn, Map peta) async {
    final entries = peta.entries.toList();
    for (final entry in entries) {
      await txn.update(
          'warga',
          {'urut_sort': -1000000 - intValue(entry.key)},
          where: 'id = ?',
          whereArgs: [intValue(entry.key)]);
    }
    for (final entry in entries) {
      final next = Map<String, Object?>.from(entry.value as Map);
      await txn.update('warga', {'urut_sort': next['baru']},
          where: 'id = ?', whereArgs: [intValue(entry.key)]);
    }
  }

  Future<List<RecordMap>> _wargaRt(
      DatabaseExecutor txn, int rw, int rt) async {
    final rows = await txn.query('warga',
        where: 'rw = ? AND rt = ?',
        whereArgs: [rw, rt],
        orderBy: 'urut_sort ASC, id ASC');
    return rows.map((r) => Map<String, Object?>.from(r)).toList();
  }

  RecordMap _petaRenumber(List<RecordMap> rows, {int start = 1000}) {
    final peta = <String, RecordMap>{};
    for (var i = 0; i < rows.length; i++) {
      final id = rows[i]['id'] as int;
      final lama = rows[i]['urut_sort'] as int;
      final baru = start + i * 1000;
      if (lama != baru) {
        peta['$id'] = {'lama': lama, 'baru': baru};
      }
    }
    return peta;
  }

  List<RecordMap> _virtualRenumber(List<RecordMap> rows, {int start = 1000}) =>
      [
        for (var i = 0; i < rows.length; i++)
          {...rows[i], 'urut_sort': start + i * 1000}
      ];

  void _queueRenumber(List<RecordMap> extras, int rw, int rt, String ts,
      Map peta) {
    extras.add({
      'op': 'RENUMBER',
      'tabel': 'warga',
      'row_id': null,
      'data': {'rw': rw, 'rt': rt, 'peta': peta, 'diubah_pada': ts},
    });
  }

  int? _urutDari(List<RecordMap> rows, int? afterId) {
    if (afterId == null) {
      return urutAntara(
          rows.isEmpty ? null : rows.last['urut_sort'] as int, null);
    }
    final index = rows.indexWhere((r) => r['id'] == afterId);
    if (index < 0) return null;
    final sebelum = rows[index]['urut_sort'] as int;
    final sesudah =
        index + 1 < rows.length ? rows[index + 1]['urut_sort'] as int : null;
    return urutAntara(sebelum, sesudah);
  }

  Future<int> _urutSisip(Transaction txn, int rw, int rt, int? afterId,
      List<RecordMap> extras, String ts) async {
    final rows = await _wargaRt(txn, rw, rt);
    if (afterId != null && rows.every((r) => r['id'] != afterId)) {
      throw AppException('Baris sisip tidak ditemukan');
    }
    final value = _urutDari(rows, afterId);
    if (value != null) return value;
    final peta = _petaRenumber(rows);
    _queueRenumber(extras, rw, rt, ts, peta);
    return _urutDari(_virtualRenumber(rows), afterId)!;
  }

  void _validateWarga(RecordMap fields) {
    if ('${fields['nama'] ?? ''}'.trim().isEmpty) {
      throw AppException('Nama wajib diisi');
    }
    if (intValue(fields['rt']) <= 0 || intValue(fields['rw']) <= 0) {
      throw AppException('RT dan RW wajib berupa bilangan positif');
    }
  }

  RecordMap _wargaRecord(RecordMap fields, int id, int urut, String ts,
      String dibuat) {
    final nik = nullableText('${fields['nik'] ?? ''}');
    return {
      'id': id,
      'urut_sort': urut,
      'grup_id': null,
      'nik': nik,
      'nama': fields['nama'].toString().trim(),
      'nama_norm': normalisasiNama(fields['nama'].toString()),
      'jenis_kelamin': fields['jenis_kelamin'],
      'tempat_lahir': nullableText('${fields['tempat_lahir'] ?? ''}'),
      'tgl_lahir': fields['tgl_lahir'],
      'desa': nullableText('${fields['desa'] ?? ''}'),
      'rt': intValue(fields['rt']),
      'rw': intValue(fields['rw']),
      'keterangan': nullableText('${fields['keterangan'] ?? ''}'),
      'sumber_input': fields['sumber_input'] ?? 'LAPANGAN',
      'dibuat_pada': dibuat,
      'diubah_pada': ts,
    };
  }

  bool _needsTrim(Object? value, {bool required = false}) {
    if (value == null) return false;
    final raw = '$value';
    if (required) return raw != raw.trim();
    return raw != (nullableText(raw) ?? '');
  }

  /// One-time cleanup of padded text already on disk. Each dirty row is a
  /// normal journaled UPDATE so replay stays the source of truth.
  Future<int> trimStoredText() async {
    final rows = await db.query('warga');
    var cleaned = 0;
    for (final row in rows) {
      final dirty = _needsTrim(row['nik']) ||
          _needsTrim(row['nama'], required: true) ||
          _needsTrim(row['tempat_lahir']) ||
          _needsTrim(row['desa']) ||
          _needsTrim(row['keterangan']);
      if (!dirty) continue;
      await saveWarga({
        'nik': row['nik'],
        'nama': row['nama'],
        'jenis_kelamin': row['jenis_kelamin'],
        'tempat_lahir': row['tempat_lahir'],
        'tgl_lahir': row['tgl_lahir'],
        'desa': row['desa'],
        'rt': row['rt'],
        'rw': row['rw'],
        'keterangan': row['keterangan'],
        'sumber_input': row['sumber_input'],
      }, id: row['id'] as int);
      cleaned++;
    }
    return cleaned;
  }

  Future<RecordMap> saveWarga(RecordMap fields, {int? id, int? afterId}) async {
    _validateWarga(fields);
    final extras = <RecordMap>[];
    return _commit(id == null ? 'INSERT' : 'UPDATE', 'warga', (txn, ts) async {
      if (id == null) {
        final next = await _nextId(txn, 'warga');
        final urut = await _urutSisip(
            txn, intValue(fields['rw']), intValue(fields['rt']), afterId, extras, ts);
        return _wargaRecord(fields, next, urut, ts, ts);
      }
      final before =
          (await txn.query('warga', where: 'id = ?', whereArgs: [id])).first;
      var urut = before['urut_sort'] as int;
      if (intValue(fields['rt']) != intValue(before['rt']) ||
          intValue(fields['rw']) != intValue(before['rw'])) {
        urut = await urutAkhir(
            txn, intValue(fields['rw']), intValue(fields['rt']));
      }
      return _wargaRecord(
          fields, id, urut, ts, before['dibuat_pada'] as String);
    }, extras: (_) => extras);
  }

  Future<void> deleteWarga(int id) async {
    await _commit('DELETE', 'warga', (txn, ts) async {
      final rows = await txn.query('warga', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        throw AppException('Baris warga $id tidak ditemukan');
      }
      return _full(wargaColumns, rows.first);
    });
  }

  int? _urutTetangga(List<RecordMap> others, int? beforeId, int? afterId) {
    final sebelum = beforeId == null
        ? null
        : others.firstWhere((r) => r['id'] == beforeId)['urut_sort'] as int;
    final sesudah = afterId == null
        ? null
        : others.firstWhere((r) => r['id'] == afterId)['urut_sort'] as int;
    return urutAntara(sebelum, sesudah);
  }

  Future<void> reorderWarga(int id, int? beforeId, int? afterId) async {
    final extras = <RecordMap>[];
    await _commit('REORDER', 'warga', (txn, ts) async {
      final row =
          (await txn.query('warga', where: 'id = ?', whereArgs: [id])).first;
      final rw = row['rw'] as int;
      final rt = row['rt'] as int;
      final others =
          (await _wargaRt(txn, rw, rt)).where((r) => r['id'] != id).toList();
      var next = _urutTetangga(others, beforeId, afterId);
      if (next == null) {
        final start = beforeId == null ? 2000 : 1000;
        final full = await _wargaRt(txn, rw, rt);
        _queueRenumber(extras, rw, rt, ts, _petaRenumber(full, start: start));
        final virtual = _virtualRenumber(full, start: start)
            .where((r) => r['id'] != id)
            .toList();
        next = _urutTetangga(virtual, beforeId, afterId);
        if (next == null) {
          throw AppException('Urutan tidak dapat dihitung ulang');
        }
      }
      return {
        'id': id,
        'peta': {
          '$id': {'lama': row['urut_sort'], 'baru': next}
        },
        'rw': rw,
        'rt': rt,
      };
    }, extras: (_) => extras);
  }

  Future<void> importRows(List<RecordMap> ready, String filename) async {
    await _commit('IMPORT', 'referensi', (txn, ts) async {
      final records = <RecordMap>[];
      for (final row in ready) {
        records.add(_full(referensiColumns, {
          ...row,
          'id': await _nextId(txn, 'referensi'),
          'diimpor_pada': ts,
        }));
      }
      return {
        'nama_file': filename,
        'jumlah': records.length,
        'records': records,
      };
    });
  }

  Future<void> clearReferensi() async {
    await _commit('DELETE', 'referensi', (txn, ts) async {
      final rows = await txn.query('referensi');
      return {
        'jumlah': rows.length,
        'records': rows.map((r) => _full(referensiColumns, r)).toList(),
      };
    });
  }

  Future<void> recordExport(
      List<RecordMap> files, int rw, List<int> rts) async {
    await _commit('EXPORT', 'export',
        (txn, ts) async => {
              'files': files,
              'rw': rw,
              'rt': rts,
              'jumlah': files.fold<int>(
                  0, (n, f) => n + intValue(f['jumlah_baris'])),
            });
  }

  Future<List<RecordMap>> duplicates(String nik, {int? exceptId}) {
    if (nik.isEmpty) return Future.value([]);
    return db.query('warga',
        where: 'nik = ?${exceptId == null ? '' : ' AND id <> ?'}',
        whereArgs: [nik, if (exceptId != null) exceptId],
        orderBy: 'dibuat_pada ASC, id ASC');
  }

  Future<RecordMap?> warga(int id) async {
    final result = await db.query('warga', where: 'id = ?', whereArgs: [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<List<RecordMap>> allWarga() =>
      db.query('warga', orderBy: 'dibuat_pada DESC, id DESC');

  Future<List<RecordMap>> wargaRt(int rw, int rt) => db.query('warga',
      where: 'rw = ? AND rt = ?',
      whereArgs: [rw, rt],
      orderBy: 'urut_sort ASC, id ASC');

  Future<List<RecordMap>> allReferensi(int rw) =>
      db.query('referensi', where: 'rw = ?', whereArgs: [rw], orderBy: 'id');

  Future<int> referensiCount() async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM referensi');
    return rows.first['n'] as int;
  }

  Future<List<RecordMap>> history() =>
      db.query('warga', orderBy: 'dibuat_pada DESC, id DESC', limit: 20);

  Future<List<RecordMap>> duplicateRows() => db.rawQuery('''
    SELECT w.* FROM warga w
    JOIN v_duplikat_nik d ON w.nik = d.nik
    ORDER BY w.nik, w.urut_sort, w.id''');

  Future<List<RecordMap>> tanpaNik({int? rw, int? rt}) => db.query('warga',
      where: [
        "(nik IS NULL OR nik = '')",
        if (rw != null) 'rw = ?',
        if (rt != null) 'rt = ?',
      ].join(' AND '),
      whereArgs: [if (rw != null) rw, if (rt != null) rt],
      orderBy: 'rw, rt, urut_sort, id');

  Future<RecordMap> counts(int rt, int rw) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS jumlah,
        COALESCE(SUM(CASE WHEN nik IS NULL OR nik = '' THEN 1 ELSE 0 END), 0) AS tanpa_nik
      FROM warga WHERE rt = ? AND rw = ?''', [rt, rw]);
    return rows.first;
  }

  Future<List<RecordMap>> countsByRt(int rw) => db.rawQuery('''
    SELECT rt, COUNT(*) AS jumlah,
      COALESCE(SUM(CASE WHEN nik IS NULL OR nik = '' THEN 1 ELSE 0 END), 0) AS tanpa_nik
    FROM warga WHERE rw = ? GROUP BY rt ORDER BY rt''', [rw]);

  Future<List<int>> rtList(int rw) async {
    final rows = await db.rawQuery(
        'SELECT rt FROM warga WHERE rw=? UNION SELECT rt FROM referensi WHERE rw=? ORDER BY rt',
        [rw, rw]);
    return rows.map((r) => r['rt'] as int).toList();
  }

  Future<List<RecordMap>> exportWarga(int rt, int rw) => db.query('warga',
      where: 'rw = ? AND rt = ?',
      whereArgs: [rw, rt],
      orderBy: 'urut_sort ASC, id ASC');

  Future<int> posisi(int id, int rw, int rt) async {
    final rows = await wargaRt(rw, rt);
    return rows.indexWhere((r) => r['id'] == id) + 1;
  }

  Future<File> snapshot() => exclusive(() async {
        if (_recoveryRequired) {
          throw AppException('Pulihkan database sebelum membuat snapshot.');
        }
        final result = await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        if (result.isNotEmpty && result.first['busy'] != 0) {
          throw AppException('Database masih sibuk. Coba snapshot lagi.');
        }
        final copy = await File(dbPath)
            .copy('${root.path}/snapshot/db_${fileStamp()}.db');
        final files = await snapshots();
        for (final old in files.skip(20)) {
          await old.delete();
        }
        return copy;
      });

  Future<List<File>> snapshots() async {
    final files = await Directory('${root.path}/snapshot')
        .list()
        .where((e) => e is File && RegExp(r'/db_\d+\.db$').hasMatch(e.path))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<RecoveryReport> _replay(Database target) async {
    final report = RecoveryReport();
    final errors = <String>[];
    final knownRows = await target.query('log', columns: ['id']);
    final known = knownRows.map((r) => r['id']).toSet();
    final files = await Directory('${root.path}/journal')
        .list()
        .where((e) => e is File && e.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final file in files) {
      var number = 0;
      await for (final line in file
          .openRead()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
        number++;
        if (line.trim().isEmpty) continue;
        report.processed++;
        try {
          var event = Map<String, Object?>.from(jsonDecode(line) as Map);
          if (event['event_id'] is! int) {
            throw AppException('ID jurnal tidak valid');
          }
          try {
            event = migrateEvent(event, target: schemaV);
          } catch (e) {
            throw AppException('$e');
          }
          if (known.contains(event['event_id'])) continue;
          await target.transaction((txn) => _applyEvent(txn, event));
          known.add(event['event_id']);
          report.applied++;
        } catch (e) {
          report.failed++;
          errors.add('${file.path}:$number: $e');
        }
      }
    }
    if (errors.isNotEmpty) {
      report.failurePath = '${root.path}/recovered/gagal_${fileStamp()}.log';
      await File(report.failurePath!)
          .writeAsString('${errors.join('\n')}\n', flush: true);
    }
    return report;
  }

  Future<RecoveryReport> rebuild() => exclusive(() async {
        final stamp = fileStamp();
        final candidatePath = '${root.path}/recovered/rebuild_$stamp.db';
        final candidate = await _openDatabase(candidatePath);
        RecoveryReport report;
        try {
          report = await _replay(candidate);
          await candidate.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        } finally {
          await candidate.close();
        }
        try {
          await db.close();
        } catch (_) {/* Startup may have failed to open DB. */}
        final backup = '${root.path}/recovered/db_rusak_$stamp.db';
        if (await File(dbPath).exists()) await File(dbPath).rename(backup);
        for (final suffix in ['-wal', '-shm']) {
          final sidecar = File('$dbPath$suffix');
          if (await sidecar.exists()) await sidecar.rename('$backup$suffix');
        }
        await File(candidatePath).rename(dbPath);
        db = await _openDatabase(dbPath);
        report.previousDatabase = backup;
        _recoveryRequired = false;
        notifyListeners();
        return report;
      });

  Future<void> close() async {
    await _tail;
    try {
      await db.close();
    } catch (_) {/* Already closed after a swap or a second close. */}
  }
}

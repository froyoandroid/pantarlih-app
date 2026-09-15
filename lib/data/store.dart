import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../core/format.dart';
import '../core/nama.dart';
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

/// One serialized writer; every user action is one SQLite transaction and one
/// flushed, full-payload JSONL event. SQLite is a rebuildable materialized cache.
class AppStore extends ChangeNotifier {
  AppStore(this.root, {DatabaseFactory? factory})
      : factory = factory ?? databaseFactory;
  final Directory root;
  final DatabaseFactory factory;
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
      db = await _openDatabase(dbPath);
      final check = await db.rawQuery('PRAGMA quick_check');
      if (check.any((row) => row.values.first != 'ok')) {
        throw AppException('Pemeriksaan integritas database gagal');
      }
      startupRecovery = await _replay(db);
    } catch (e) {
      throw AppException(
          'Database tidak dapat dibuka. Berkas aman di ${root.path}. '
          'Gunakan pemulihan dari jurnal. Detail: $e');
    }
  }

  Future<Database> _openDatabase(String path) => factory.openDatabase(path,
      options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
            await db.rawQuery('PRAGMA journal_mode = WAL');
          },
          onCreate: (db, _) async {
            for (final sql in schemaStatements) {
              await db.execute(sql);
            }
          }));

  Future<Map<String, String>> settings() async {
    final rows = await db.query('setelan');
    return {
      'rt_aktif': '1',
      'rw_aktif': '3',
      'desa_default': 'KALITORONG',
      'schema_v': '1',
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
                {'kunci': 'schema_v', 'nilai': '1'},
              ]
            });
  }

  Future<int> _nextId(DatabaseExecutor txn, String table) async {
    final rows =
        await txn.rawQuery('SELECT COALESCE(MAX(id), 0) + 1 AS id FROM $table');
    return rows.first['id'] as int;
  }

  Future<RecordMap> _commit(String op, String table,
          Future<RecordMap> Function(Transaction txn, String ts) prepare) =>
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
            final event = <String, Object?>{
              'schema_v': schemaVersion,
              'event_id': await _nextId(txn, 'log'),
              'ts': ts,
              'op': op,
              'tabel': table,
              'row_id': payload['id'] ??
                  (payload['after'] as Map?)?['id'] ??
                  payload['id_lama'],
              'data': payload,
            };
            await _appendJournal(event);
            journalWritten = true;
            await _applyEvent(txn, event);
            return payload;
          });
          notifyListeners();
          return result;
        } catch (e) {
          if (journalWritten) {
            _recoveryRequired = true;
            throw AppException(
                'Jurnal sudah tersimpan, tetapi database gagal diperbarui. '
                'Jangan input ulang; bangun ulang dari jurnal. Detail: $e');
          }
          rethrow;
        }
      });

  Future<void> _appendJournal(RecordMap event) async {
    final date = event['ts'].toString().substring(0, 10);
    final file = File('${root.path}/journal/$date.jsonl');
    final handle = await file.open(mode: FileMode.append);
    try {
      // A killed process may have left an unterminated JSON fragment. Never
      // concatenate a new event onto it; recovery reports that fragment.
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
    if (event['schema_v'] != schemaVersion) {
      throw AppException('Versi jurnal tidak didukung');
    }
    final data = Map<String, Object?>.from(event['data'] as Map);
    final table = event['tabel'];
    final op = event['op'];
    if (table == 'warga_lama' && op == 'IMPORT') {
      for (final raw in data['records'] as List) {
        await txn.insert('warga_lama', Map<String, Object?>.from(raw as Map));
      }
    } else if (table == 'survei') {
      final record = data['after'] is Map
          ? Map<String, Object?>.from(data['after'] as Map)
          : data;
      if (op == 'INSERT') {
        await txn.insert('survei', record);
      } else if (['UPDATE', 'UNLINK', 'RELINK'].contains(op)) {
        final count = await txn.update('survei', record,
            where: 'id = ?', whereArgs: [record['id']]);
        if (count != 1) {
          throw AppException('Baris survei ${record['id']} tidak ditemukan');
        }
      } else if (op == 'DELETE') {
        await txn.delete('survei', where: 'id = ?', whereArgs: [data['id']]);
      } else {
        throw AppException('Operasi survei tidak dikenal: $op');
      }
    } else if (table == 'tanda_lama' && op == 'MARK') {
      await txn.insert('tanda_lama', data,
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else if (table == 'setelan' && op == 'UPDATE') {
      for (final raw in data['records'] as List) {
        await txn.insert('setelan', Map<String, Object?>.from(raw as Map),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    } else if (!(table == 'export' && op == 'EXPORT')) {
      throw AppException('Operasi jurnal tidak dikenal: $table/$op');
    }
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

  Future<void> importRows(
      List<RecordMap> ready, String filename, int confirmedRt) async {
    await _commit('IMPORT', 'warga_lama', (txn, ts) async {
      var id = await _nextId(txn, 'warga_lama');
      final existing =
          await txn.query('warga_lama', columns: ['rt', 'urut_asli']);
      final keys = existing.map((r) => '${r['rt']}:${r['urut_asli']}').toSet();
      final records = <RecordMap>[];
      for (final row in ready) {
        final key = '${row['rt']}:${row['urut_asli']}';
        if (!keys.add(key)) {
          throw AppException('Impor ditolak: RT ${row['rt']}, nomor '
              '${row['urut_asli']} sudah ada atau berulang di file. Data lama tidak diubah.');
        }
        records.add({...row, 'id': id++, 'diimpor_pada': ts});
      }
      return {
        'nama_file': filename,
        'rt_konfirmasi': confirmedRt,
        'jumlah': records.length,
        'jumlah_perlu_review':
            records.where((r) => r['perlu_review'] == 1).length,
        'records': records
      };
    });
  }

  Future<List<RecordMap>> duplicates(String nik, {int? exceptId}) =>
      db.query('survei',
          where: 'nik = ?${exceptId == null ? '' : ' AND id <> ?'}',
          whereArgs: [nik, if (exceptId != null) exceptId],
          orderBy: 'dibuat_pada ASC, id ASC');

  Future<void> _checkLink(
      DatabaseExecutor txn, int? oldId, int? surveyId) async {
    if (oldId == null) return;
    final linked = await txn.query('survei',
        where: 'id_lama = ?${surveyId == null ? '' : ' AND id <> ?'}',
        whereArgs: [oldId, if (surveyId != null) surveyId]);
    if (linked.isNotEmpty) {
      throw AppException(
          'Data lama ini sudah ditautkan ke ${linked.first['nama']}. '
          'Buka baris tersebut melalui riwayat untuk memperbaikinya.');
    }
  }

  Future<RecordMap> saveSurvey(RecordMap fields, {int? id, int? oldId}) async {
    if (!RegExp(r'^\d{16}$').hasMatch('${fields['nik'] ?? ''}')) {
      throw AppException('NIK harus 16 digit angka');
    }
    if ('${fields['nama'] ?? ''}'.trim().isEmpty) {
      throw AppException('Nama wajib diisi');
    }
    if (intValue(fields['rt_baru']) <= 0 || intValue(fields['rw_baru']) <= 0) {
      throw AppException('RT dan RW wajib berupa bilangan positif');
    }
    return _commit(id == null ? 'INSERT' : 'UPDATE', 'survei', (txn, ts) async {
      await _checkLink(txn, oldId, id);
      final before = id == null
          ? null
          : (await txn.query('survei', where: 'id = ?', whereArgs: [id])).first;
      final old = oldId == null
          ? null
          : (await txn.query('warga_lama', where: 'id = ?', whereArgs: [oldId]))
              .first;
      final record = <String, Object?>{
        'id': id ?? await _nextId(txn, 'survei'),
        'id_lama': oldId,
        'grup_id': null,
        'nik': fields['nik'],
        'nama': fields['nama'].toString().trim(),
        'nama_norm': normalisasiNama(fields['nama'].toString()),
        'jenis_kelamin': fields['jenis_kelamin'],
        'tempat_lahir': fields['tempat_lahir'],
        'tgl_lahir': fields['tgl_lahir'],
        'desa': fields['desa'],
        'rt_lama': old?['rt'],
        'rw_lama': old?['rw'],
        'rt_baru': fields['rt_baru'],
        'rw_baru': fields['rw_baru'],
        'keterangan': nullableText('${fields['keterangan'] ?? ''}'),
        'sumber_input': fields['sumber_input'],
        'dibuat_pada': before?['dibuat_pada'] ?? ts,
        'diubah_pada': ts,
      };
      if (before == null) return record;
      return {'before': before, 'after': record};
    });
  }

  Future<void> relink(int surveyId, int? oldId) async {
    await _commit(oldId == null ? 'UNLINK' : 'RELINK', 'survei',
        (txn, ts) async {
      await _checkLink(txn, oldId, surveyId);
      final before =
          (await txn.query('survei', where: 'id = ?', whereArgs: [surveyId]))
              .first;
      final old = oldId == null
          ? null
          : (await txn.query('warga_lama', where: 'id = ?', whereArgs: [oldId]))
              .first;
      final after = {
        ...before,
        'id_lama': oldId,
        'rt_lama': old?['rt'],
        'rw_lama': old?['rw'],
        'diubah_pada': ts
      };
      return {'before': before, 'after': after};
    });
  }

  Future<void> mark(int oldId, bool grey) async {
    await _commit(
        'MARK',
        'tanda_lama',
        (txn, ts) async => {
              'id_lama': oldId,
              'abu_abu': grey ? 1 : 0,
              'ditandai_pada': ts,
            });
  }

  Future<void> recordExport(
      List<RecordMap> files, int rw, List<int> rts) async {
    await _commit('EXPORT', 'export',
        (txn, ts) async => {'files': files, 'rw': rw, 'rt': rts});
  }

  Future<List<RecordMap>> allLegacy(int rw) => db.rawQuery('''
    SELECT w.*, s.id AS survey_id, s.rt_baru, s.rw_baru,
      COALESCE(t.abu_abu, 0) AS abu_abu
    FROM warga_lama w LEFT JOIN survei s ON s.id_lama = w.id
    LEFT JOIN tanda_lama t ON t.id_lama = w.id
    WHERE w.rw = ? ORDER BY w.rt, w.urut_sort, w.id''', [rw]);

  Future<RecordMap?> survey(int id) async {
    final result = await db.query('survei', where: 'id = ?', whereArgs: [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<RecordMap?> legacy(int id) async {
    final result =
        await db.query('warga_lama', where: 'id = ?', whereArgs: [id]);
    return result.isEmpty ? null : result.first;
  }

  Future<List<RecordMap>> history() =>
      db.query('survei', orderBy: 'dibuat_pada DESC, id DESC', limit: 20);
  Future<List<RecordMap>> conflicts() =>
      db.query('v_konflik_rt', orderBy: 'rt_lama, dibuat_pada');
  Future<List<RecordMap>> duplicateRows() =>
      db.rawQuery('''SELECT s.* FROM survei s
    JOIN v_duplikat_nik d ON s.nik = d.nik ORDER BY s.nik, s.dibuat_pada''');
  Future<List<RecordMap>> remaining(int rt, int rw) => db.rawQuery('''
    SELECT w.*, COALESCE(t.abu_abu,0) AS abu_abu, s.id AS survey_id, s.rt_baru, s.rw_baru
    FROM warga_lama w LEFT JOIN tanda_lama t ON t.id_lama = w.id
    LEFT JOIN survei s ON s.id_lama = w.id
    WHERE w.rt = ? AND w.rw = ? AND (s.id IS NULL OR s.rt_baru <> w.rt OR s.rw_baru <> w.rw)
    ORDER BY w.urut_sort, w.id''', [rt, rw]);

  Future<RecordMap> progress(int rt, int rw) async {
    final r = await db.rawQuery('''SELECT COUNT(*) AS total,
      COALESCE(SUM(CASE WHEN EXISTS(SELECT 1 FROM survei s WHERE s.id_lama=w.id) THEN 1 ELSE 0 END),0) AS surveyed,
      COALESCE(SUM(CASE WHEN NOT EXISTS(SELECT 1 FROM survei s WHERE s.id_lama=w.id)
        AND COALESCE(t.abu_abu,0)=0 THEN 1 ELSE 0 END),0) AS remaining,
      COALESCE(SUM(CASE WHEN NOT EXISTS(SELECT 1 FROM survei s WHERE s.id_lama=w.id)
        AND COALESCE(t.abu_abu,0)=1 THEN 1 ELSE 0 END),0) AS grey
      FROM warga_lama w LEFT JOIN tanda_lama t ON t.id_lama=w.id WHERE w.rt=? AND w.rw=?''',
        [rt, rw]);
    final inputs = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM survei WHERE rt_baru=? AND rw_baru=?',
        [rt, rw]);
    return {...r.first, 'inputs': inputs.first['n']};
  }

  Future<List<int>> rtList(int rw) async {
    final rows = await db.rawQuery(
        'SELECT rt FROM warga_lama WHERE rw=? UNION SELECT rt_baru AS rt FROM survei WHERE rw_baru=? ORDER BY rt',
        [rw, rw]);
    return rows.map((r) => r['rt'] as int).toList();
  }

  Future<List<RecordMap>> pending({required int rw, int? rt}) => db.rawQuery('''
    SELECT w.* FROM warga_lama w WHERE w.rw=? ${rt == null ? '' : 'AND w.rt=?'}
    AND NOT EXISTS(SELECT 1 FROM survei s WHERE s.id_lama=w.id) ORDER BY w.rt, w.urut_sort, w.id''',
      [rw, if (rt != null) rt]);
  Future<List<RecordMap>> exportSurveys(int rt, int rw) => db.query('survei',
      where: 'rt_baru=? AND rw_baru=?',
      whereArgs: [rt, rw],
      orderBy: 'dibuat_pada ASC, id ASC');

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
        // Only rotate our own concrete snapshot files; journal is never rotated.
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
          final event = Map<String, Object?>.from(jsonDecode(line) as Map);
          if (event['event_id'] is! int || event['schema_v'] != schemaVersion) {
            throw AppException('ID atau versi jurnal tidak valid');
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
        // Build a candidate first, preserving the old DB if replay/file IO fails.
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
    await db.close();
  }
}

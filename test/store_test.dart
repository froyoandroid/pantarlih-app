import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/core/format.dart';
import 'package:pantarlih_kalitorong/data/spreadsheets.dart';
import 'package:pantarlih_kalitorong/data/store.dart';
import 'package:pantarlih_kalitorong/ui/common.dart';
import 'package:pantarlih_kalitorong/ui/survey_form.dart';

WorkbookSource fixture() {
  final book = Excel.createExcel();
  final sheet = book['RT 03'];
  sheet.appendRow([
    'NO',
    'NAMA PEMILIH',
    'NIK',
    'Jenis Kelamin',
    'TEMPAT LAHIR',
    'TANGGAL LAHIR',
    'DUSUN',
    'RT',
    'RW',
    'KET'
  ].map(TextCellValue.new).toList());
  for (final row in [
    [
      '70',
      'MUHAMAD HASAN',
      '332707**********',
      'LAKI-LAKI',
      'PEMALANG',
      '19-09-1968',
      'KALITORONG',
      '3',
      '3',
      ''
    ],
    [
      '71',
      'SITI SALIMAH',
      '332707**********',
      'PEREMPUAN',
      'PEMALANG',
      '11/09/1973',
      'KALITORONG',
      '3',
      '3',
      ''
    ],
    [
      '72',
      'MUHAMAD NAZWA BAIHAKY',
      '332707**********',
      'LAKI-LAKI',
      'PEMALANG',
      '19-09-2007',
      'KALITORONG',
      '3',
      '3',
      ''
    ],
  ]) {
    sheet.appendRow(row.map(TextCellValue.new).toList());
  }
  return WorkbookSource('fixture.xlsx', Uint8List.fromList(book.encode()!));
}

WorkbookSource dirtyFixture() {
  final book = Excel.createExcel();
  final sheet = book['RT 03'];
  sheet.appendRow([
    'NO',
    'NAMA PEMILIH',
    'NIK',
    'Jenis Kelamin',
    'TEMPAT LAHIR',
    'TANGGAL LAHIR',
    'DUSUN',
    'RT',
    'RW',
    'KET'
  ].map(TextCellValue.new).toList());
  for (final row in [
    [
      '70',
      'MUHAMAD HASAN',
      '332707**********',
      'LAKI-LAKI',
      'PEMALANG',
      '19-09-1968',
      'KALITORONG',
      '3',
      '3',
      ''
    ],
    ['', '', 'sel rusak', '', '', '', '', '', '', ''],
    [
      '',
      'SITI SALIMAH',
      '332707**********',
      'PEREMPUAN',
      'PEMALANG',
      '11/09/1973',
      'KALITORONG',
      '3',
      '3',
      ''
    ],
    ['bukan-angka', '', '', '', '', '', '', '3', '3', ''],
    [
      '72',
      'MUHAMAD NAZWA BAIHAKY',
      '332707**********',
      'LAKI-LAKI',
      'PEMALANG',
      '19-09-2007',
      'KALITORONG',
      '3',
      '3',
      ''
    ],
  ]) {
    sheet.appendRow(row.map(TextCellValue.new).toList());
  }
  return WorkbookSource('dirty.xlsx', Uint8List.fromList(book.encode()!));
}

RecordMap fields(
        {String name = 'MUHAMAD HASAN',
        String? nik = '3327071909680001',
        int rt = 3,
        String? note}) =>
    {
      'nama': name,
      'nik': nik,
      'jenis_kelamin': 'L',
      'tempat_lahir': 'PEMALANG',
      'tgl_lahir': '1968-09-19',
      'desa': 'KALITORONG',
      'rt': rt,
      'rw': 3,
      'keterangan': note,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late AppStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pantarlih-test-');
    store = AppStore(root, factory: databaseFactoryFfi);
    await store.open();
    final source = fixture();
    await store.importRows(
        source
            .prepare('RT 03', source.suggestedMapping('RT 03'), 2, 3, 3)
            .records,
        source.name);
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test('duplicate listing respects the requested rw and rt scope', () async {
    final shared = '3327071909680001';
    await store.saveWarga(fields(nik: shared));
    await store.db.insert('warga', {
      'urut_sort': 2000,
      'nik': shared,
      'nama': 'TETANGGA',
      'nama_norm': 'tetangga',
      'jenis_kelamin': 'L',
      'rt': 5,
      'rw': 4,
      'dibuat_pada': timestamp(),
      'diubah_pada': timestamp(),
    });
    expect(await store.duplicateRows(), hasLength(2));
    expect(await store.duplicateRows(rw: 3, rt: 3), hasLength(1));
    expect((await store.duplicateRows(rw: 3, rt: 3)).single['rt'], 3);
  });

  test('trim cleanup runs once per install and is marked in setelan', () async {
    final marker = await store.db
        .query('setelan', where: 'kunci = ?', whereArgs: ['trim_v1_selesai']);
    expect(marker.single['nilai'], '1');
  });

  test('rtList counts warga RTs only, rtListReferensi includes references',
      () async {
    await store.db.insert('referensi', {
      'nama': 'REFERENSI KOSONG',
      'nama_norm': 'referensi kosong',
      'rt': 7,
      'rw': 3,
      'diimpor_pada': timestamp(),
    });
    expect(await store.rtList(3), isEmpty);
    expect(await store.rtListReferensi(3), containsAll([3, 7]));
    await store.saveWarga(fields());
    expect(await store.rtList(3), [3]);
  });

  test('backfill assigns kode in one journal event', () async {
    final a = await store.saveWarga(fields());
    final b = await store.saveWarga(fields(name: 'KEDUA'));
    final n = await store.backfillKodeWilayah('33.27.07.2001');
    expect(n, 2);
    expect((await store.warga(a['id'] as int))!['kode_wilayah'],
        '33.27.07.2001');
    expect((await store.warga(b['id'] as int))!['kode_wilayah'],
        '33.27.07.2001');
    final events = await store.db.query('log', where: "op='BACKFILL'");
    expect(events, hasLength(1));
    final payload = jsonDecode(events.single['payload'] as String) as Map;
    expect(payload['ids'], containsAll([a['id'], b['id']]));
  });

  test('reference import is optional, dirty, and repeatable', () async {
    final rows = await store.allReferensi(3);
    expect(rows, hasLength(3));
    expect(rows[1]['tgl_lahir'], '1973-09-11');
    expect(rows.first['nik_lama'], '332707**********');
    expect(rows.first.containsKey('urut_sort'), isFalse);
    final source = fixture();
    await store.importRows(
        source
            .prepare('RT 03', source.suggestedMapping('RT 03'), 2, 3, 3)
            .records,
        source.name);
    expect(await store.allReferensi(3), hasLength(6));
    await store.clearReferensi();
    expect(await store.referensiCount(), 0);
  });

  test('app works without reference rows', () async {
    await store.clearReferensi();
    final saved = await store.saveWarga(fields());
    expect(saved['urut_sort'], 1000);
    expect(saved.containsKey('id_lama'), isFalse);
    expect(await store.wargaRt(3, 3), hasLength(1));
  });

  test('empty NIK and short NIK save, duplicates warn but stay', () async {
    final empty = await store.saveWarga(fields(nik: null));
    expect(empty['nik'], isNull);
    final short = await store.saveWarga(fields(name: 'PENDATANG', nik: '123'));
    expect(short['nik'], '123');
    await store.saveWarga(fields(name: 'SALINAN'));
    await store.saveWarga(fields(name: 'SALINAN DUA'));
    expect(await store.duplicateRows(), hasLength(2));
    final note = await store.saveWarga(fields(name: 'CATATAN', note: '   '));
    expect(note['keterangan'], isNull);
  });

  test('saving or reordering a warga deleted elsewhere fails readably',
      () async {
    final pertama = await store.saveWarga(fields());
    final kedua = await store.saveWarga(fields(name: 'KEDUA'));
    final id = pertama['id'] as int;
    await store.deleteWarga(id);
    await expectLater(
        store.saveWarga(fields(), id: id),
        throwsA(isA<AppException>()
            .having((e) => e.message, 'message', contains('sudah dihapus'))));
    await expectLater(store.reorderWarga(kedua['id'] as int, id, null),
        throwsA(isA<AppException>()));
  });

  test('padded NIK is stored trimmed and collides with the same digits',
      () async {
    final padded = await store.saveWarga(fields(nik: ' 3327071909680001 '));
    expect(padded['nik'], '3327071909680001');
    await store.saveWarga(fields(name: 'KEMBARAN', nik: '3327071909680001'));
    expect(await store.duplicateRows(), hasLength(2));
    final spaceNote = await store.saveWarga(fields(name: 'KOSONG', note: ' '));
    expect(spaceNote['keterangan'], isNull);
    await store.db.insert('warga', {
      'urut_sort': 9000,
      'nik': ' 3327074109730002 ',
      'nama': ' SITI SALIMAH ',
      'nama_norm': 'siti salimah',
      'jenis_kelamin': 'P',
      'rt': 3,
      'rw': 3,
      'dibuat_pada': timestamp(),
      'diubah_pada': timestamp(),
    });
    expect(await store.trimStoredText(), 1);
    expect((await store.warga(4))!['nik'], '3327074109730002');
    final updates =
        await store.db.query('log', where: "tabel='warga' AND op='UPDATE'");
    expect(updates, isNotEmpty);
  });

  testWidgets('new form shows SIMPAN & LANJUT', (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: SurveyForm(session: Session(store))));
    expect(find.text('SIMPAN & LANJUT'), findsOneWidget);
    expect(find.textContaining('orang ke-1'), findsOneWidget);
  });

  test('five chained inserts keep rising urut_sort in input order', () async {
    RecordMap? previous;
    for (final name in ['SATU', 'DUA', 'TIGA', 'EMPAT', 'LIMA']) {
      previous = await store.saveWarga(fields(name: name, nik: null),
          afterId: previous?['id'] as int?);
    }
    final rows = await store.wargaRt(3, 3);
    expect(
        rows.map((r) => r['nama']), ['SATU', 'DUA', 'TIGA', 'EMPAT', 'LIMA']);
    final sorts = rows.map((r) => r['urut_sort'] as int).toList();
    expect(sorts, sorts.toList()..sort());
    expect(sorts.toSet(), hasLength(5));
  });

  test('insert between rows uses sparse keys and export follows that order',
      () async {
    final first = await store.saveWarga(fields());
    final third = await store.saveWarga(fields(name: 'ORANG TIGA'));
    final middle = await store.saveWarga(fields(name: 'ORANG DUA'),
        afterId: first['id'] as int);
    expect(first['urut_sort'], 1000);
    expect(third['urut_sort'], 2000);
    expect(middle['urut_sort'], 1500);
    final ordered = await store.wargaRt(3, 3);
    expect(ordered.map((r) => r['nama']),
        ['MUHAMAD HASAN', 'ORANG DUA', 'ORANG TIGA']);
    await store.reorderWarga(third['id'] as int, null, first['id'] as int);
    expect((await store.wargaRt(3, 3)).first['nama'], 'ORANG TIGA');
    final files = await ExportService(store).generate(rw: 3, rt: 3);
    expect(files.any((f) => f.path.contains('PENDING')), isFalse);
    expect(files.any((f) => f.path.contains('KONFLIK')), isFalse);
    expect(files.any((f) => f.path.contains('TANPA_NIK')), isTrue);
    expect(files.any((f) => f.path.contains('DUPLIKAT_NAMA')), isTrue);
    final dps = files.firstWhere((f) {
      final n = f.path.split(Platform.pathSeparator).last;
      return n.startsWith('DPS_') &&
          n.contains('RT03') &&
          !n.contains('GABUNGAN');
    });
    final book = Excel.decodeBytes(await dps.readAsBytes());
    expect(book.tables.containsKey('INFO'), isTrue);
    final data = book.tables.entries.firstWhere((e) => e.key != 'INFO').value;
    final rows = data.rows;
    expect(cellText(rows[0][0]), 'NO');
    expect(cellText(rows[1][1]), 'ORANG TIGA');
    expect(cellText(rows[1][0]), '1');
    expect(cellText(rows[2][1]), 'MUHAMAD HASAN');
  });

  test('insert before a row uses the gap before that row', () async {
    final first = await store.saveWarga(fields());
    final second = await store.saveWarga(fields(name: 'KEDUA'));
    await store.saveWarga(fields(name: 'DEPAN', nik: null),
        beforeId: first['id'] as int);
    expect((await store.wargaRt(3, 3)).map((r) => r['nama']),
        ['DEPAN', 'MUHAMAD HASAN', 'KEDUA']);
    await store.saveWarga(fields(name: 'TENGAH', nik: null),
        beforeId: second['id'] as int);
    expect((await store.wargaRt(3, 3)).map((r) => r['nama']),
        ['DEPAN', 'MUHAMAD HASAN', 'TENGAH', 'KEDUA']);
  });

  test('card warna persists on save', () async {
    final saved = await store.saveWarga(fields(name: 'WARNA', nik: null));
    await store.saveWarga(
        {...fields(name: 'WARNA', nik: null), 'warna': 'kuning'},
        id: saved['id'] as int);
    expect((await store.warga(saved['id'] as int))!['warna'], 'kuning');
  });

  test('renumber runs when the gap is exhausted', () async {
    final a = await store.saveWarga(fields());
    await store.saveWarga(fields(name: 'B'));
    var after = a['id'] as int;
    for (var i = 0; i < 12; i++) {
      final inserted =
          await store.saveWarga(fields(name: 'SISIP $i'), afterId: after);
      after = inserted['id'] as int;
    }
    final rows = await store.wargaRt(3, 3);
    expect(rows, hasLength(14));
    final sorts = rows.map((r) => r['urut_sort'] as int).toList();
    expect(sorts.toSet().length, sorts.length);
    final log =
        await store.db.query('log', where: 'op=?', whereArgs: ['RENUMBER']);
    expect(log, isNotEmpty);
  });

  test('journal full replay keeps urut_sort, damaged lines continue', () async {
    await store.setSession(3, 3);
    final a = await store.saveWarga(fields());
    await store.saveWarga(fields(name: 'KEDUA'));
    await store.saveWarga(fields(name: 'TENGAH', note: 'changed'),
        afterId: a['id'] as int);
    await store.deleteWarga(a['id'] as int);
    const tables = ['referensi', 'warga', 'setelan', 'log'];
    final before = {for (final t in tables) t: await store.db.query(t)};
    final journal =
        (await Directory('${root.path}/journal').list().cast<File>().toList())
            .single;
    await journal.writeAsString('{truncated',
        mode: FileMode.append, flush: true);
    final report = await store.rebuild();
    expect(report.failed, 1);
    expect(File(report.previousDatabase!).existsSync(), isTrue);
    for (final t in tables) {
      expect(await store.db.query(t), before[t], reason: t);
    }
  });

  test('journal failure notice can be opened then dismissed', () async {
    await store.saveWarga(fields());
    final journal =
        (await Directory('${root.path}/journal').list().cast<File>().toList())
            .single;
    await journal.writeAsString('{truncated',
        mode: FileMode.append, flush: true);
    await store.close();
    await store.open();
    expect(store.startupRecovery!.failed, 1);
    expect(store.startupRecovery!.showNotice, isTrue);
    expect(store.startupRecovery!.failurePath, isNotNull);
    expect(await store.journalReportText(), contains('truncated'));
    await store.dismissJournalReport();
    expect(store.startupRecovery!.showNotice, isFalse);
    expect(
        Directory('${root.path}/recovered')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('gagal_')),
        isEmpty);
    await store.close();
    await store.open();
    expect(store.startupRecovery!.failed, 1);
    expect(store.startupRecovery!.showNotice, isFalse);
    expect(store.startupRecovery!.failurePath, isNull);
  });

  test('missing database is recreated automatically from journal', () async {
    await store.saveWarga(fields());
    final before = await store.db.query('warga');
    await store.close();
    await File(store.dbPath).rename('${root.path}/removed-for-test.db');
    await store.open();
    expect(await store.db.query('warga'), before);
    expect(await store.allReferensi(3), hasLength(3));
  });

  test('journal failure leaves database unchanged', () async {
    final journalDir = Directory('${root.path}/journal');
    await journalDir.rename('${root.path}/journal-before-test');
    await File('${root.path}/journal').writeAsString('not a directory');
    await expectLater(
        store.saveWarga(fields()), throwsA(isA<FileSystemException>()));
    expect(await store.history(), isEmpty);
  });

  test('twelve RT changes keep ten auto-export folders for the left RT',
      () async {
    await store.saveWarga(fields());
    await store
        .saveWarga(fields(name: 'ORANG RT4', rt: 4, nik: '3327071909680099'));
    await store.setSession(3, 3);
    final session = Session(store);
    await session.load();
    for (var i = 0; i < 12; i++) {
      await session.change(session.rt == 3 ? 4 : 3, 3);
    }
    final folders = Directory('${root.path}/export/auto')
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    expect(folders, hasLength(10));
    final names = folders.first
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .toList();
    expect(names.where((n) => n.contains('RT04')), hasLength(1));
    expect(names.where((n) => n.contains('RT03')), isEmpty);
    expect(names.where((n) => n.contains('DUPLIKAT')), isEmpty);
    expect(names.where((n) => n.contains('TANPA_NIK')), isEmpty);
  });

  test('session changes create snapshot and automatic exports', () async {
    await store.setSession(3, 3);
    final session = Session(store);
    await session.load();
    expect(session.rt, 3);
    await session.change(4, 3);
    expect(await store.snapshots(), hasLength(1));
    expect(await Directory('${root.path}/export/auto').list().toList(),
        isNotEmpty);
    for (var i = 0; i < 21; i++) {
      await store.snapshot();
    }
    expect(await store.snapshots(), hasLength(20));
    expect((await store.settings())['rt_aktif'], '4');
  });

  test('journal payload is the full warga row, not a delta', () async {
    final saved = await store.saveWarga(fields(note: 'bebas'));
    final log =
        await store.db.query('log', where: "tabel='warga' AND op='INSERT'");
    final payload = jsonDecode(log.first['payload'] as String) as Map;
    expect(payload['id'], saved['id']);
    expect(payload.containsKey('grup_id'), isTrue);
    expect(payload['grup_id'], isNull);
    expect(payload['keterangan'], 'bebas');
    expect(payload.containsKey('id_lama'), isFalse);
  });

  test('changing RT keeps a custom village name', () async {
    await store.setDesa('KALITORONG DUSUN 2');
    await store.setSession(4, 3);
    final values = await store.settings();
    expect(values['desa_default'], 'KALITORONG DUSUN 2');
    expect(values['rt_aktif'], '4');
  });

  test('adding RT keeps previous RT in the workspace', () async {
    await store.setSession(3, 3);
    final session = Session(store);
    await session.load();
    expect(session.workspace, contains(const RtRw(3, 3)));
    await session.addRtRw(4, 3);
    await session.addRtRw(5, 3);
    await session.addRtRw(1, 4);
    expect(session.rt, 1);
    expect(session.rw, 4);
    expect(session.workspace, [
      const RtRw(3, 3),
      const RtRw(3, 4),
      const RtRw(3, 5),
      const RtRw(4, 1),
    ]);
    expect((await store.settings())['ruang_kerja'], '3.3,3.4,3.5,4.1');
    await session.focusRt(const RtRw(3, 4));
    expect(session.rt, 4);
    expect(session.rw, 3);
    expect(session.workspace, hasLength(4));
  });

  test('same-RT name duplicates without NIK appear in duplicateNameRows',
      () async {
    await store.saveWarga(fields(name: 'MUHAMMAD HASSAN', nik: null));
    await store.saveWarga(fields(name: 'MUHAMAD HASAN', nik: null));
    final rows = await store.duplicateNameRows();
    expect(rows.map((r) => r['nama']),
        containsAll(['MUHAMMAD HASSAN', 'MUHAMAD HASAN']));
  });

  test('deleted ids are not reused and rebuild keeps the same ids', () async {
    final first = await store.saveWarga(fields());
    await store.deleteWarga(first['id'] as int);
    final second = await store.saveWarga(fields(name: 'PENGGANTI'));
    expect(second['id'] as int, greaterThan(first['id'] as int));
    final before = await store.db.query('warga');
    final report = await store.rebuild();
    expect(report.failed, 0);
    expect(await store.db.query('warga'), before);
    expect((await store.warga(second['id'] as int))!['nama'], 'PENGGANTI');
  });

  test('snapshot rotation trims the oldest db copies', () async {
    final dir = Directory('${root.path}/snapshot');
    for (var i = 1; i <= 24; i++) {
      File('${dir.path}/db_20260901${i.toString().padLeft(6, '0')}.db')
          .writeAsStringSync('x$i');
    }
    await store.snapshot();
    final sisa = await store.snapshots();
    expect(sisa, hasLength(20));
    expect(await File('${dir.path}/db_20260901000001.db').exists(), isFalse);
    expect(await File('${dir.path}/db_20260901000005.db').exists(), isFalse);
    expect(await File('${dir.path}/db_20260901000006.db').exists(), isTrue);
  });

  test('pre-migration snapshots rotate with their own cap plus sidecars',
      () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-premig-');
    final dir = Directory('${isolated.path}/snapshot')..createSync();
    for (var i = 1; i <= 8; i++) {
      final nama =
          'pre_migrasi_20260901${i.toString().padLeft(6, '0')}.db';
      File('${dir.path}/$nama').writeAsStringSync('p$i');
      File('${dir.path}/$nama-wal').writeAsStringSync('w$i');
    }
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 2);
    await older.open();
    await older.saveWarga(fields());
    await older.close();
    final newer =
        AppStore(isolated, factory: databaseFactoryFfi, schemaV: 3, upgrades: {
      2: ['ALTER TABLE warga ADD COLUMN kolom_baru TEXT']
    });
    await newer.open();
    try {
      final sisa = Directory('${isolated.path}/snapshot')
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split('/').last)
          .toList();
      final utama = sisa.where((n) => n.endsWith('.db')).toList();
      // The fresh copy counts inside the cap of 5.
      expect(utama, hasLength(5));
      expect(
          utama.any((n) => n.startsWith('pre_migrasi_20260901000001')), isFalse);
      expect(
          utama.any((n) => n.startsWith('pre_migrasi_20260901000004')), isFalse);
      expect(
          utama.any((n) => n.startsWith('pre_migrasi_20260901000005')), isTrue);
      // Sidecars of trimmed stamps are gone too.
      expect(
          await File(
                  '${dir.path}/pre_migrasi_20260901000001.db-wal')
              .exists(),
          isFalse);
      expect(
          await File(
                  '${dir.path}/pre_migrasi_20260901000005.db-wal')
              .exists(),
          isTrue);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('opening a v2 database on v3 keeps every row and snapshots first',
      () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-v2-open-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 2);
    await older.open();
    final saved = await older.saveWarga(fields());
    final before = await older.db.query('warga');
    await older.close();
    final newer =
        AppStore(isolated, factory: databaseFactoryFfi, schemaV: 3, upgrades: {
      2: ['ALTER TABLE warga ADD COLUMN kolom_baru TEXT']
    });
    await newer.open();
    try {
      final after = await newer.db.query('warga');
      expect(after, hasLength(before.length));
      expect(after.first['id'], saved['id']);
      expect(after.first['nama'], saved['nama']);
      expect(after.first['kolom_baru'], isNull);
      expect(
          Directory('${isolated.path}/snapshot')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('pre_migrasi_')),
          isNotEmpty);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('rebuild from v2 journal onto v3 keeps rows with the new column null',
      () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-v2-rebuild-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 2);
    await older.open();
    await older.saveWarga(fields());
    await older.saveWarga(fields(name: 'ORANG DUA'));
    final before = await older.db.query('warga');
    await older.close();
    final newer =
        AppStore(isolated, factory: databaseFactoryFfi, schemaV: 3, upgrades: {
      2: ['ALTER TABLE warga ADD COLUMN kolom_baru TEXT']
    });
    await newer.open();
    try {
      final report = await newer.rebuild();
      expect(report.failed, 0);
      final after = await newer.db.query('warga');
      expect(after, hasLength(before.length));
      expect(after.map((r) => r['nama']), before.map((r) => r['nama']));
      expect(after.every((r) => r['kolom_baru'] == null), isTrue);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('semicolon CSV with BOM matches the equivalent xlsx fixture', () async {
    final xlsx = fixture();
    const csvText =
        '\uFEFFNO;NAMA PEMILIH;NIK;Jenis Kelamin;TEMPAT LAHIR;TANGGAL LAHIR;DUSUN;RT;RW;KET\r\n'
        '70;MUHAMAD HASAN;332707**********;LAKI-LAKI;PEMALANG;19-09-1968;KALITORONG;3;3;\r\n'
        '71;SITI SALIMAH;332707**********;PEREMPUAN;PEMALANG;11/09/1973;KALITORONG;3;3;\r\n'
        '72;MUHAMAD NAZWA BAIHAKY;332707**********;LAKI-LAKI;PEMALANG;19-09-2007;KALITORONG;3;3;\r\n';
    final csv =
        CsvSource('fixture.csv', Uint8List.fromList(utf8.encode(csvText)));
    final fromXlsx =
        xlsx.prepare('RT 03', xlsx.suggestedMapping('RT 03'), 2, 3, 3);
    final fromCsv = csv.prepare(
        csv.sheets.first, csv.suggestedMapping(csv.sheets.first), 2, 3, 3);
    expect(fromCsv.records.map((r) => r['nama']),
        fromXlsx.records.map((r) => r['nama']));
    expect(fromCsv.records.map((r) => r['tgl_lahir']),
        fromXlsx.records.map((r) => r['tgl_lahir']));
    expect(fromCsv.records.map((r) => r['nik_lama']),
        fromXlsx.records.map((r) => r['nik_lama']));
    expect(fromCsv.skipped, isEmpty);
  });

  test('dirty workbook imports good rows and writes dilewati.jsonl', () async {
    final source = dirtyFixture();
    final prep =
        source.prepare('RT 03', source.suggestedMapping('RT 03'), 2, 3, 3);
    expect(prep.records, hasLength(3));
    expect(prep.skipped, hasLength(2));
    await source.archiveAndImport(
        store, 'RT 03', prep.records, source.suggestedMapping('RT 03'), 2, 3,
        skipped: prep.skipped);
    expect(await store.allReferensi(3), hasLength(6));
    final skippedFiles = Directory('${root.path}/import/ready')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('dilewati.jsonl'));
    expect(skippedFiles, isNotEmpty);
    final lines = await skippedFiles.first.readAsLines();
    expect(lines.where((l) => l.trim().isNotEmpty), hasLength(2));
  });

  test('actual provided workbook imports all 504 reference rows', () async {
    final input = File('data-exel/DPS_RW03_Kalitorong_Gabungan.xlsx');
    if (!await input.exists()) {
      markTestSkipped('Private workbook is not distributed with the source.');
      return;
    }
    final source =
        WorkbookSource(input.uri.pathSegments.last, await input.readAsBytes());
    expect(source.sheets, ['REKAP', 'RT 03', 'RT 04', 'RT 05']);
    final actualRoot =
        await Directory.systemTemp.createTemp('pantarlih-workbook-test-');
    final actual = AppStore(actualRoot, factory: databaseFactoryFfi);
    try {
      await actual.open();
      for (final entry in {'RT 03': 189, 'RT 04': 123, 'RT 05': 192}.entries) {
        final rt = int.parse(entry.key.split(' ').last);
        final ready = source.prepare(
            entry.key, source.suggestedMapping(entry.key), 2, rt, 3);
        expect(ready.records, hasLength(entry.value));
        await source.archiveAndImport(actual, entry.key, ready.records,
            source.suggestedMapping(entry.key), 2, rt,
            skipped: ready.skipped);
      }
      expect(await actual.allReferensi(3), hasLength(504));
      final before = await actual.db.query('referensi');
      final report = await actual.rebuild();
      expect(report.failed, 0);
      expect(await actual.db.query('referensi'), before);
    } finally {
      await actual.close();
      await actualRoot.delete(recursive: true);
    }
  });

  test(
      'opening a v3 database on v4 keeps rows, null kode_wilayah, empty lokasi',
      () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-v3-open-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 3);
    await older.open();
    for (var i = 0; i < 50; i++) {
      await older.saveWarga(fields(name: 'ORANG $i', nik: null, rt: 3));
    }
    await older.close();
    final newer = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 4);
    await newer.open();
    try {
      final after = await newer.db.query('warga');
      expect(after, hasLength(50));
      expect(after.every((r) => r['kode_wilayah'] == null), isTrue);
      expect(await newer.db.query('lokasi'), isEmpty);
      expect(
          Directory('${isolated.path}/snapshot')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('pre_migrasi_')),
          isNotEmpty);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('v2 journal replayed on v4 keeps names and null kode_wilayah', () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-v2-to-v4-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 2);
    await older.open();
    await older.saveWarga(fields());
    await older.saveWarga(fields(name: 'ORANG DUA'));
    await older.close();
    final newer = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 4);
    await newer.open();
    try {
      final report = await newer.rebuild();
      expect(report.failed, 0);
      final after = await newer.db.query('warga', orderBy: 'id');
      expect(after.map((r) => r['nama']), ['MUHAMAD HASAN', 'ORANG DUA']);
      expect(after.every((r) => r['kode_wilayah'] == null), isTrue);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('opening a v4 database on v5 keeps rows and leaves sumber_input unused',
      () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-v4-open-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 4);
    await older.open();
    await older.db.execute(
        "ALTER TABLE warga ADD COLUMN sumber_input TEXT NOT NULL DEFAULT 'LAPANGAN'");
    final saved = await older.saveWarga(fields());
    await older.close();
    final newer = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 5);
    await newer.open();
    try {
      final after = await newer.db.query('warga');
      expect(after, hasLength(1));
      expect(after.first['id'], saved['id']);
      expect(after.first['nama'], saved['nama']);
      expect(after.first['sumber_input'], 'LAPANGAN');
      expect(
          Directory('${isolated.path}/snapshot')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('pre_migrasi_')),
          isNotEmpty);
      final report = await newer.rebuild();
      expect(report.failed, 0);
      final rebuilt = await newer.db.query('warga', orderBy: 'id');
      expect(rebuilt.first['nama'], saved['nama']);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('opening a v5 database on v6 adds warna and keeps rows', () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-v5-open-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 5);
    await older.open();
    final saved = await older.saveWarga(fields());
    await older.close();
    final newer = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 6);
    await newer.open();
    try {
      final after = await newer.db.query('warga');
      expect(after, hasLength(1));
      expect(after.first['id'], saved['id']);
      expect(after.first['nama'], saved['nama']);
      expect(after.first['warna'], isNull);
    } finally {
      await newer.close();
      await isolated.delete(recursive: true);
    }
  });

  test('saving lokasi writes one journal event and survives rebuild', () async {
    await store.setLokasi({
      'kode': '33.27.07.2016',
      'nama_desa': 'Kalitorong',
      'nama_kec': 'Randudongkal',
      'nama_kab': 'Kabupaten Pemalang',
      'nama_prov': 'Jawa Tengah',
      'kode_kec': '33.27.07',
      'nik_prefix': '332707',
      'sumber_versi': 'Kepmendagri No. 300.2.2-2430 Tahun 2025',
      'manual': 0,
    });
    final journalFiles = Directory('${root.path}/journal')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'));
    var lokasiEvents = 0;
    var wilayahEvents = 0;
    for (final file in journalFiles) {
      for (final line in file.readAsLinesSync()) {
        if (line.trim().isEmpty) continue;
        final event = jsonDecode(line) as Map;
        if (event['tabel'] == 'lokasi') lokasiEvents++;
        if (event['tabel'] == 'wilayah') wilayahEvents++;
      }
    }
    expect(lokasiEvents, 1);
    expect(wilayahEvents, 0);
    final before = await store.db.query('lokasi');
    final report = await store.rebuild();
    expect(report.failed, 0);
    expect(await store.db.query('lokasi'), before);
    expect((await store.settings())['kode_wilayah_aktif'], '33.27.07.2016');
  });

  test('backfill writes one journal event and rebuild matches', () async {
    for (var i = 0; i < 10; i++) {
      await store.saveWarga(fields(name: 'LAMA $i', nik: null));
    }
    await store.setLokasi({
      'kode': '33.27.07.2016',
      'nama_desa': 'Kalitorong',
      'manual': 0,
    });
    final beforeLog = (await store.db.query('log')).length;
    expect(await store.backfillKodeWilayah('33.27.07.2016'), 10);
    expect((await store.db.query('log')).length, beforeLog + 1);
    expect(
        (await store.db.query('warga', where: "nama LIKE 'LAMA %'"))
            .every((r) => r['kode_wilayah'] == '33.27.07.2016'),
        isTrue);
    final before = await store.db.query('warga', orderBy: 'id');
    final report = await store.rebuild();
    expect(report.failed, 0);
    expect(await store.db.query('warga', orderBy: 'id'), before);
  });

  test('export has INFO sheet and ten-column header on row 1', () async {
    await store.saveWarga(fields());
    await store.setLokasi({
      'kode': 'MANUAL:kalitorong',
      'nama_desa': 'Kalitorong',
      'nama_prov': 'Jawa Tengah',
      'manual': 1,
    });
    final files = await ExportService(store).generate(rw: 3, rt: 3);
    final dps = files.firstWhere((f) {
      final n = f.path.split(Platform.pathSeparator).last;
      return n.startsWith('DPS_') && n.contains('TANPALOKASI');
    });
    final book = Excel.decodeBytes(await dps.readAsBytes());
    expect(book.tables.length, 2);
    expect(book.tables.containsKey('INFO'), isTrue);
    final data = book.tables.entries.firstWhere((e) => e.key != 'INFO').value;
    expect(cellText(data.rows[0][0]), 'NO');
    expect(data.rows[0].length, 10);
    final info = book.tables['INFO']!;
    final kodeRow =
        info.rows.firstWhere((r) => cellText(r[0]) == 'Kode wilayah');
    expect(cellText(kodeRow[1]), '(manual)');
  });

  test('empty database without lokasi still saves one person', () async {
    final isolated =
        await Directory.systemTemp.createTemp('pantarlih-empty-lokasi-');
    final fresh = AppStore(isolated, factory: databaseFactoryFfi);
    await fresh.open();
    try {
      final saved = await fresh.saveWarga(fields());
      expect(saved['nama'], 'MUHAMAD HASAN');
      expect(saved['kode_wilayah'], isNull);
      expect(await fresh.db.query('lokasi'), isEmpty);
    } finally {
      await fresh.close();
      await isolated.delete(recursive: true);
    }
  });
}

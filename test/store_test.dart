import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/core/format.dart';
import 'package:pantarlih_kalitorong/data/spreadsheets.dart';
import 'package:pantarlih_kalitorong/data/store.dart';
import 'package:pantarlih_kalitorong/ui/common.dart';

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
      'sumber_input': 'LAPANGAN',
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
      'sumber_input': 'LAPANGAN',
      'dibuat_pada': timestamp(),
      'diubah_pada': timestamp(),
    });
    expect(await store.trimStoredText(), 1);
    expect((await store.warga(4))!['nik'], '3327074109730002');
    final updates =
        await store.db.query('log', where: "tabel='warga' AND op='UPDATE'");
    expect(updates, isNotEmpty);
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
    final dps = files.firstWhere((f) => f.path.contains('DPS_RT3'));
    final book = Excel.decodeBytes(await dps.readAsBytes());
    final rows = book.tables.values.first.rows;
    expect(cellText(rows[0][0]), 'NO');
    expect(cellText(rows[1][1]), 'ORANG TIGA');
    expect(cellText(rows[1][0]), '1');
    expect(cellText(rows[2][1]), 'MUHAMAD HASAN');
  });

  test('renumber runs when the gap is exhausted', () async {
    final a = await store.saveWarga(fields());
    await store.saveWarga(fields(name: 'B'));
    var after = a['id'] as int;
    for (var i = 0; i < 12; i++) {
      final inserted = await store.saveWarga(fields(name: 'SISIP $i'),
          afterId: after);
      after = inserted['id'] as int;
    }
    final rows = await store.wargaRt(3, 3);
    expect(rows, hasLength(14));
    final sorts = rows.map((r) => r['urut_sort'] as int).toList();
    expect(sorts.toSet().length, sorts.length);
    final log = await store.db.query('log', where: 'op=?', whereArgs: ['RENUMBER']);
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
    await store.saveWarga(fields(name: 'ORANG RT4', rt: 4, nik: '3327071909680099'));
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
    expect(names.where((n) => n.contains('DPS_RT4')), hasLength(1));
    expect(names.where((n) => n.contains('DPS_RT3')), isEmpty);
    expect(names.where((n) => n.contains('DUPLIKAT')), isEmpty);
    expect(names.where((n) => n.contains('TANPA_NIK')), isEmpty);
  });

  test('session changes create snapshot and automatic exports', () async {
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
    final log = await store.db
        .query('log', where: "tabel='warga' AND op='INSERT'");
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

  test('opening a v2 database on v3 keeps every row and snapshots first',
      () async {
    final isolated = await Directory.systemTemp.createTemp('pantarlih-v2-open-');
    final older = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 2);
    await older.open();
    final saved = await older.saveWarga(fields());
    final before = await older.db.query('warga');
    await older.close();
    final newer = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 3, upgrades: {
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
    final newer = AppStore(isolated, factory: databaseFactoryFfi, schemaV: 3, upgrades: {
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
    const csvText = '\uFEFFNO;NAMA PEMILIH;NIK;Jenis Kelamin;TEMPAT LAHIR;TANGGAL LAHIR;DUSUN;RT;RW;KET\r\n'
        '70;MUHAMAD HASAN;332707**********;LAKI-LAKI;PEMALANG;19-09-1968;KALITORONG;3;3;\r\n'
        '71;SITI SALIMAH;332707**********;PEREMPUAN;PEMALANG;11/09/1973;KALITORONG;3;3;\r\n'
        '72;MUHAMAD NAZWA BAIHAKY;332707**********;LAKI-LAKI;PEMALANG;19-09-2007;KALITORONG;3;3;\r\n';
    final csv = CsvSource('fixture.csv', Uint8List.fromList(utf8.encode(csvText)));
    final fromXlsx =
        xlsx.prepare('RT 03', xlsx.suggestedMapping('RT 03'), 2, 3, 3);
    final fromCsv =
        csv.prepare(csv.sheets.first, csv.suggestedMapping(csv.sheets.first), 2, 3, 3);
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
    await source.archiveAndImport(store, 'RT 03', prep.records,
        source.suggestedMapping('RT 03'), 2, 3,
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
}

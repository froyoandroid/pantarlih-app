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

RecordMap fields(
        {String name = 'MUHAMAD HASAN',
        String nik = '3327071909680001',
        int rt = 3,
        String? note}) =>
    {
      'nama': name,
      'nik': nik,
      'jenis_kelamin': 'L',
      'tempat_lahir': 'PEMALANG',
      'tgl_lahir': '1968-09-19',
      'desa': 'KALITORONG',
      'rt_baru': rt,
      'rw_baru': 3,
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
        source.prepare('RT 03', source.suggestedMapping('RT 03'), 2, 3, 3),
        source.name,
        3);
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  test(
      'immutable import, masked NIK, day-first parsing and duplicate rejection',
      () async {
    final rows = await store.allLegacy(3);
    expect(rows, hasLength(3));
    expect(rows[1]['tgl_lahir'], '1973-09-11');
    expect(rows.first['nik_lama'], '332707**********');
    expect(rows.first['urut_sort'], 70000);
    await expectLater(
        store.db.update('warga_lama', {'nama': 'Changed'}, where: 'id=1'),
        throwsA(isA<DatabaseException>()));
    final source = fixture();
    await expectLater(
        store.importRows(
            source.prepare('RT 03', source.suggestedMapping('RT 03'), 2, 3, 3),
            source.name,
            3),
        throwsA(isA<AppException>()));
    expect(await store.allLegacy(3), hasLength(3));
    final otherRt = source
        .prepare('RT 03', source.suggestedMapping('RT 03'), 2, 3, 3)
        .map((r) => {...r, 'rt': 4})
        .toList();
    await store.importRows(otherRt, source.name, 4);
    expect(await store.allLegacy(3), hasLength(6));
  });
  test('surveys, duplicate allowance, grey count, conflicts, unlink and relink',
      () async {
    await expectLater(store.saveSurvey(fields(nik: ''), oldId: 1),
        throwsA(isA<AppException>()));
    await store.saveSurvey(fields(nik: '123'), oldId: 1);
    await store.mark(2, true);
    expect((await store.progress(3, 3))['remaining'], 1);
    await store.saveSurvey(fields(rt: 4, note: '  bebas  '), oldId: 2);
    expect(await store.conflicts(), hasLength(1));
    expect((await store.conflicts()).first['keterangan'], '  bebas  ');
    expect((await store.remaining(3, 3)).first['survey_id'], 2);
    await expectLater(
        store.saveSurvey(fields(), oldId: 1), throwsA(isA<AppException>()));
    await store.saveSurvey(fields(name: 'WARGA BARU', note: '   '));
    expect(await store.duplicateRows(), hasLength(2));
    expect((await store.survey(3))!['keterangan'], isNull);
    await store.relink(1, null);
    expect((await store.survey(1))!['rt_lama'], isNull);
    expect((await store.progress(3, 3))['remaining'], 2);
    await store.relink(1, 3);
    expect((await store.survey(1))!['id_lama'], 3);
    final log =
        await store.db.query('log', where: 'op=?', whereArgs: ['RELINK']);
    final payload = jsonDecode(log.first['payload'] as String) as Map;
    expect(payload['before'], hasLength(18));
    expect(payload['after'], hasLength(18));
  });
  test('journal full replay, damaged lines continue, old database retained',
      () async {
    await store.setSession(3, 3);
    await store.saveSurvey(fields(), oldId: 1);
    await store.saveSurvey(fields(name: 'CORRECTED', note: 'changed'),
        id: 1, oldId: 1);
    await store.mark(2, true);
    await store.relink(1, null);
    await store.relink(1, 3);
    const tables = ['warga_lama', 'survei', 'tanda_lama', 'setelan', 'log'];
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
    await store.mark(
        2, false); // append after unterminated fragment stays replayable
    final again = await store.rebuild();
    expect(again.failed, 1);
    expect((await store.db.query('tanda_lama')).first['abu_abu'], 0);
  });
  test('missing database is recreated automatically from journal', () async {
    await store.saveSurvey(fields(), oldId: 1);
    final before = await store.db.query('survei');
    await store.close();
    await File(store.dbPath).rename('${root.path}/removed-for-test.db');
    await store.open();
    expect(await store.db.query('survei'), before);
    expect(await store.allLegacy(3), hasLength(3));
  });
  test('journal failure leaves database unchanged', () async {
    final journalDir = Directory('${root.path}/journal');
    await journalDir.rename('${root.path}/journal-before-test');
    await File('${root.path}/journal').writeAsString('not a directory');
    await expectLater(store.saveSurvey(fields(), oldId: 1),
        throwsA(isA<FileSystemException>()));
    expect(await store.history(), isEmpty);
  });
  test(
      'exports use new RT, time order, text NIK, blank notes and pending at bottom',
      () async {
    await store.saveSurvey(fields(rt: 4), oldId: 1);
    await store.saveSurvey(fields(name: 'WARGA BARU'));
    final files = await ExportService(store).generate(rw: 3, combined: true);
    expect(files, hasLength(4));
    final combined = Excel.decodeBytes(await files.first.readAsBytes());
    expect(combined.tables.keys.toSet(), {'RT 3', 'RT 4'});
    final rows = combined['RT 3'].rows;
    expect(rows.first.map(cellText).toList(), dpsHeaders);
    expect(cellText(rows[1][1]), 'WARGA BARU');
    expect(rows[1][2]!.value, isA<TextCellValue>());
    expect(rows[1][9]?.value, isNull);
    expect(cellText(rows[2][1]), 'SITI SALIMAH');
    expect(rows[2][2]?.value, isNull);
    expect(cellText(rows[2][5]), '11-09-1973');
    expect(cellText(combined['RT 4'].rows[1][0]), '1');
    final duplicateFile = files.firstWhere((f) => f.path.contains('DUPLIKAT'));
    final duplicateBook = Excel.decodeBytes(await duplicateFile.readAsBytes());
    expect(duplicateBook.tables.values.single.rows, hasLength(3));
  });
  test(
      'session changes create snapshot and automatic exports; keep 20 snapshots',
      () async {
    final session = Session(store);
    await session.load();
    await session.change(3, 3);
    expect(await store.snapshots(), hasLength(1));
    expect(await Directory('${root.path}/export/auto').list().toList(),
        isNotEmpty);
    for (var i = 0; i < 21; i++) {
      await store.snapshot();
    }
    expect(await store.snapshots(), hasLength(20));
    expect((await store.settings())['rt_aktif'], '3');
  });
  test('actual provided workbook imports all 504 rows across three RT sheets',
      () async {
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
        expect(ready, hasLength(entry.value));
        await source.archiveAndImport(actual, entry.key, ready,
            source.suggestedMapping(entry.key), 2, rt);
      }
      expect(await actual.allLegacy(3), hasLength(504));
      final before = await actual.db.query('warga_lama');
      final report = await actual.rebuild();
      expect(report.failed, 0);
      expect(await actual.db.query('warga_lama'), before);
    } finally {
      await actual.close();
      await actualRoot.delete(recursive: true);
    }
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/data/wilayah.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('built pack has Kalitorong neighbor structure and matching meta counts',
      () async {
    final source = File('${Directory.current.path}/assets/wilayah.db');
    expect(await source.exists(), isTrue);
    final tmp = await Directory.systemTemp.createTemp('wilayah-pack-');
    final copy = File('${tmp.path}/wilayah.db');
    await source.copy(copy.path);
    final db = await databaseFactoryFfi.openDatabase(copy.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      final row = (await db.query('wilayah',
              where: 'kode = ?', whereArgs: ['33.27.07.2001']))
          .single;
      expect(row['induk'], '33.27.07');
      expect(row['level'], 4);
      expect(row['kode_polos'], '3327072001');
      final kalitorong = (await db.query('wilayah',
              where: 'kode = ?', whereArgs: ['33.27.07.2016']))
          .single;
      expect(kalitorong['nama'], 'Kalitorong');
      final metaFile =
          jsonDecode(await File('assets/wilayah.meta.json').readAsString())
              as Map;
      final counts = await db
          .rawQuery('SELECT level, COUNT(*) AS n FROM wilayah GROUP BY level');
      final byLevel = {
        for (final r in counts) r['level'] as int: r['n'] as int
      };
      expect(byLevel[1], metaFile['jumlah_prov']);
      expect(byLevel[2], metaFile['jumlah_kab']);
      expect(byLevel[3], metaFile['jumlah_kec']);
      expect(byLevel[4], metaFile['jumlah_desa']);
      expect(byLevel[1], 38);
    } finally {
      await db.close();
      await tmp.delete(recursive: true);
    }
  });

  test('WilayahRepo lists provinces and finds Pemalang', () async {
    final support = await Directory.systemTemp.createTemp('wilayah-repo-');
    final repo = await WilayahRepo.open(
        supportDir: support,
        assetFile: File('${Directory.current.path}/assets/wilayah.db'),
        bundledMeta: {'sha_sumber': 'd68e8d5516f969d1905d0b2940f20034becb0db7'},
        factory: databaseFactoryFfi);
    try {
      expect(repo.available, isTrue);
      final prov = await repo.anak(null);
      expect(prov, hasLength(38));
      final hits = await repo.cari('pemalang', level: 2);
      expect(hits.map((w) => w.kode), contains('33.27'));
    } finally {
      await repo.close();
      await support.delete(recursive: true);
    }
  });

  test('missing wilayah asset leaves the repo unavailable', () async {
    final support = await Directory.systemTemp.createTemp('wilayah-missing-');
    final repo = await WilayahRepo.open(
        supportDir: support,
        assetFile: File('${support.path}/tidak-ada.db'),
        bundledMeta: {'sha_sumber': 'missingasset00'},
        factory: databaseFactoryFfi);
    try {
      expect(repo.available, isFalse);
      expect(await repo.anak(null), isEmpty);
      expect(await repo.cari('pemalang', level: 2), isEmpty);
      expect(await repo.byKode('33.27'), isNull);
      expect(await repo.meta(), isEmpty);
    } finally {
      await repo.close();
      await support.delete(recursive: true);
    }
  });
}

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/data/exchange.dart';
import 'package:pantarlih_kalitorong/data/storage.dart';
import 'package:pantarlih_kalitorong/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('folder name suffixes the wilayah kode to split look-alike desas', () {
    expect(namaFolderDesa('Sido Mulyo'), namaFolderDesa('Sidomulyo'));
    expect(namaFolderDesa('Sido Mulyo', kodeWilayah: '33.27.07.2001'),
        'PantarlihSidomulyo_3327072001');
    expect(namaFolderDesa('Sidomulyo', kodeWilayah: '33.27.07.2002'),
        isNot(namaFolderDesa('Sidomulyo', kodeWilayah: '33.27.07.2001')));
    expect(namaFolderDesa('Sido Mulyo', kodeWilayah: 'MANUAL:sido mulyo'),
        'PantarlihSidomulyo_MANUALsidomulyo');
    expect(namaFolderDesa('', kodeWilayah: ''), 'Pantarlih');
  });

  test('data root is a private data folder that needs no permission', () async {
    final base = await Directory.systemTemp.createTemp('pantarlih-akar-');
    addTearDown(() => base.delete(recursive: true));
    final root = await akarData(base: base);
    expect(root.path, '${base.path}/data');
    expect(await root.exists(), isTrue);
    final store = AppStore(root, factory: databaseFactoryFfi);
    await store.open();
    expect(await File('${root.path}/pantarlih.db').exists(), isTrue);
    // Exports never land in the private root any more.
    expect(await Directory('${root.path}/export').exists(), isFalse);
    await store.close();
  });

  test('public parent prefers Documents then Dokumen then creates Documents',
      () async {
    final root = await Directory.systemTemp.createTemp('pantarlih-induk-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory('${root.path}/Documents');
    final dokumen = Directory('${root.path}/Dokumen');
    await dokumen.create();
    expect(
        (await pilihAtauBuatInduk(documents: documents, dokumen: dokumen)).path,
        dokumen.path);
    await documents.create();
    expect(
        (await pilihAtauBuatInduk(documents: documents, dokumen: dokumen)).path,
        documents.path);
  });

  test('missing Documents and Dokumen creates Documents', () async {
    final root = await Directory.systemTemp.createTemp('pantarlih-buat-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory('${root.path}/Documents');
    final dokumen = Directory('${root.path}/Dokumen');
    final chosen =
        await pilihAtauBuatInduk(documents: documents, dokumen: dokumen);
    expect(chosen.path, documents.path);
    expect(await documents.exists(), isTrue);
  });

  test('intro flag is absent until marked', () async {
    final dir = await Directory.systemTemp.createTemp('pantarlih-intro-');
    addTearDown(() => dir.delete(recursive: true));
    expect(await introSudahDilewati(base: dir), isFalse);
    await tandaiIntroSelesai(base: dir);
    expect(await introSudahDilewati(base: dir), isTrue);
  });

  test('existing pantarlih.db counts as intro already done', () async {
    final dir = await Directory.systemTemp.createTemp('pantarlih-intro-db-');
    addTearDown(() => dir.delete(recursive: true));
    expect(await introSudahDilewati(base: dir), isFalse);
    await File('${dir.path}/pantarlih.db').writeAsString('x', flush: true);
    expect(await introSudahDilewati(base: dir), isTrue);
  });

  test('exchange folder holds only ekspor, cadangan and impor', () async {
    final induk = await Directory.systemTemp.createTemp('pantarlih-tukar-');
    addTearDown(() => induk.delete(recursive: true));
    final folder = await bukaFolderPertukaran(
        desa: 'Kalitorong',
        kodeWilayah: '33.27.07.2016',
        minta: false,
        induk: induk);
    expect(folder!.root.path, '${induk.path}/PantarlihKalitorong_3327072016');
    final names = folder.root
        .listSync()
        .map((e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .toList()
      ..sort();
    expect(names, ['cadangan', 'ekspor', 'impor']);
    expect(await folder.eksporOtomatis.exists(), isTrue);
    expect(folder.label, endsWith('/PantarlihKalitorong_3327072016'));
  });

  test('cadangan bundle carries the snapshot database and every journal file',
      () async {
    final base = await Directory.systemTemp.createTemp('pantarlih-cad-');
    addTearDown(() => base.delete(recursive: true));
    final store =
        AppStore(await akarData(base: base), factory: databaseFactoryFfi);
    await store.open(); // first open journals the trim marker
    await File('${store.root.path}/journal/2026-01-01.jsonl')
        .writeAsString('{"event_id":0}\n', flush: true);
    final snap = await store.snapshot();
    final tujuan = Directory('${base.path}/cadangan');
    final zip = await tulisCadangan(store, snap, tujuan);
    expect(zip.path, startsWith('${tujuan.path}/cadangan_'));
    final arsip = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final names = arsip.files.map((f) => f.name).toList()..sort();
    expect(names, contains('pantarlih.db'));
    expect(names, contains('journal/2026-01-01.jsonl'));
    expect(names.where((n) => n.startsWith('journal/')).length,
        greaterThanOrEqualTo(2));
    expect(arsip.findFile('pantarlih.db')!.size, await snap.length());
    await store.close();
  });

  test('cadangan rotation keeps the newest ten bundles', () async {
    final base = await Directory.systemTemp.createTemp('pantarlih-rot-');
    addTearDown(() => base.delete(recursive: true));
    final store =
        AppStore(await akarData(base: base), factory: databaseFactoryFfi);
    await store.open();
    final snap = await store.snapshot();
    final tujuan = Directory('${base.path}/cadangan');
    for (var i = 0; i < 12; i++) {
      await File('${tujuan.path}/cadangan_2000010100000$i.zip'
              .replaceFirst('$i.zip', '${i.toString().padLeft(2, '0')}.zip'))
          .create(recursive: true);
    }
    await tulisCadangan(store, snap, tujuan);
    final left = tujuan.listSync().whereType<File>().length;
    expect(left, 10);
    await store.close();
  });
}

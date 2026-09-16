import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/data/storage.dart';
import 'package:pantarlih_kalitorong/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('denied permission still opens on the internal directory', () async {
    final internal = await Directory.systemTemp.createTemp('pantarlih-int-');
    addTearDown(() => internal.delete(recursive: true));
    final resolved = await resolveDataRoot(
      publicAccess: false,
      internalBase: internal,
    );
    expect(resolved.usingPublic, isFalse);
    expect(resolved.root.path, startsWith(internal.path));
    final store = AppStore(resolved.root, factory: databaseFactoryFfi);
    await store.open();
    expect(store.root.path, resolved.root.path);
    await store.close();
  });

  test('public parent prefers Documents then Dokumen then creates Documents',
      () async {
    final root = await Directory.systemTemp.createTemp('pantarlih-induk-');
    addTearDown(() => root.delete(recursive: true));
    final documents = Directory('${root.path}/Documents');
    final dokumen = Directory('${root.path}/Dokumen');
    await dokumen.create();
    expect((await pilihAtauBuatInduk(documents: documents, dokumen: dokumen)).path,
        dokumen.path);
    await documents.create();
    expect((await pilihAtauBuatInduk(documents: documents, dokumen: dokumen)).path,
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

  test('existing PantarlihKalitorong folder is reused before desa is known',
      () async {
    final parent = await Directory.systemTemp.createTemp('pantarlih-scan-');
    addTearDown(() => parent.delete(recursive: true));
    final lama = Directory('${parent.path}/PantarlihKalitorong');
    await lama.create();
    await File('${lama.path}/pantarlih.db').writeAsString('x', flush: true);
    final chosen = await pilihFolderApp(parent);
    expect(chosen.path, lama.path);
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

  test('relocating internal data keeps every journal file', () async {
    final from = await Directory.systemTemp.createTemp('pantarlih-from-');
    final to = await Directory.systemTemp.createTemp('pantarlih-to-');
    addTearDown(() async {
      await from.delete(recursive: true);
      await to.delete(recursive: true);
    });
    await Directory('${from.path}/journal').create(recursive: true);
    await File('${from.path}/journal/2026-09-15.jsonl')
        .writeAsString('{"event_id":1,"op":"INSERT"}\n', flush: true);
    await File('${from.path}/journal/2026-09-16.jsonl')
        .writeAsString('{"event_id":2,"op":"UPDATE"}\n', flush: true);
    await relocateDataRoot(from, to);
    expect(await File('${to.path}/journal/2026-09-15.jsonl').readAsString(),
        '{"event_id":1,"op":"INSERT"}\n');
    expect(await File('${to.path}/journal/2026-09-16.jsonl').readAsString(),
        '{"event_id":2,"op":"UPDATE"}\n');
  });
}

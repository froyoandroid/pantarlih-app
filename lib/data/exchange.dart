import 'dart:io';

import 'package:archive/archive.dart';

import '../core/format.dart';
import 'storage.dart';
import 'store.dart';

/// Public `Documents/Pantarlih<Desa>_<kode>`. This folder is the only thing
/// the app touches outside its private storage, and it holds exactly three
/// things: Excel exports, backup bundles, and files the user drops in for
/// import. The database never lives here.
class ExchangeFolder {
  ExchangeFolder(this.root);
  final Directory root;
  Directory get ekspor => Directory('${root.path}/ekspor');
  Directory get eksporOtomatis => Directory('${root.path}/ekspor/otomatis');
  Directory get cadangan => Directory('${root.path}/cadangan');
  Directory get impor => Directory('${root.path}/impor');

  /// Short label for the UI: parent folder name plus the desa folder.
  String get label => '${basenameDir(root.parent)}/${basenameDir(root)}';

  Future<void> siapkan() async {
    for (final dir in [ekspor, eksporOtomatis, cadangan, impor]) {
      await dir.create(recursive: true);
    }
  }
}

/// Resolves the exchange folder for [desa]. With [minta] false this never
/// prompts and returns null when the permission is missing, so automatic
/// backups silently wait until the user has exported once. With [minta]
/// true the permission dialog appears, which is what export and import do.
/// [induk] overrides the public parent (tests and desktop).
Future<ExchangeFolder?> bukaFolderPertukaran({
  required String desa,
  String? kodeWilayah,
  required bool minta,
  Directory? induk,
}) async {
  Directory parent;
  if (induk != null) {
    parent = induk;
  } else {
    final boleh =
        minta ? await requestPublicAccess() : await publicAccessGranted();
    if (!boleh) {
      if (!minta) return null;
      throw const StorageAccessException(
          'Izin akses berkas ditolak. Ekspor dan impor memerlukan folder Documents.');
    }
    parent = await indukPublik();
  }
  final folder = ExchangeFolder(Directory(
      '${parent.path}/${namaFolderDesa(desa, kodeWilayah: kodeWilayah)}'));
  await folder.siapkan();
  return folder;
}

/// Bundles one snapshot database plus every journal file into
/// `cadangan_<stamp>.zip`. The journal makes the bundle self-sufficient:
/// restoring it replays every event after the snapshot, so the bundle is
/// always as fresh as the newest journal line, not just the snapshot.
Future<File> tulisCadangan(AppStore store, File snapshot, Directory tujuan,
    {int keep = 10}) async {
  await tujuan.create(recursive: true);
  final arsip = Archive();
  final db = await snapshot.readAsBytes();
  arsip.addFile(ArchiveFile('pantarlih.db', db.length, db));
  final journal = Directory('${store.root.path}/journal');
  if (await journal.exists()) {
    final files = await journal
        .list()
        .where((e) => e is File && e.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final bytes = await f.readAsBytes();
      arsip.addFile(ArchiveFile(
          'journal/${f.uri.pathSegments.last}', bytes.length, bytes));
    }
  }
  final bytes = ZipEncoder().encode(arsip);
  if (bytes == null) throw AppException('Gagal membuat berkas cadangan.');
  final out = File('${tujuan.path}/cadangan_${fileStamp()}.zip');
  await out.writeAsBytes(bytes, flush: true);
  await _rotasiCadangan(tujuan, keep);
  return out;
}

Future<void> _rotasiCadangan(Directory dir, int keep) async {
  final all = await dir
      .list()
      .where((e) => e is File && RegExp(r'/cadangan_.+\.zip$').hasMatch(e.path))
      .cast<File>()
      .toList();
  all.sort((a, b) => b.path.compareTo(a.path));
  for (final old in all.skip(keep)) {
    await old.delete();
  }
}

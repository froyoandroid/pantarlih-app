import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _channelPenyimpanan = MethodChannel('id.kalitorong.pantarlih/storage');
const _berkasAktif = 'pantarlih.aktif';
const _penandaPindah = 'PINDAH_SELESAI';

class StorageAccessException implements Exception {
  const StorageAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ResolvedStorage {
  ResolvedStorage(this.root, {required this.usingPublic});
  final Directory root;
  final bool usingPublic;
}

String namaFolderDesa(String desa, {String? kodeWilayah}) {
  final huruf = desa.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  final dasar = huruf.isEmpty
      ? 'Pantarlih'
      : 'Pantarlih${huruf[0].toUpperCase()}${huruf.substring(1).toLowerCase()}';
  // Suffix the wilayah kode so names that normalize identically (Sido Mulyo
  // and Sidomulyo) land in separate folders instead of merging datasets.
  final polos =
      (kodeWilayah ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  return polos.isEmpty ? dasar : '${dasar}_$polos';
}

String basenameDir(Directory dir) {
  final parts = dir.uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? '' : parts.last;
}

Future<File> _introFlag({Directory? base}) async {
  final dir = base ?? await getApplicationDocumentsDirectory();
  return File('${dir.path}/intro_selesai');
}

Future<Permission> _izinPenyimpanan() async {
  final sdk = await _channelPenyimpanan.invokeMethod<int>('sdkVersion') ?? 30;
  return sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
}

Future<bool> publicAccessGranted() async {
  if (!Platform.isAndroid) return true;
  try {
    return await (await _izinPenyimpanan()).isGranted;
  } catch (_) {
    return false;
  }
}

bool adaBerkasSesi(Directory root) {
  try {
    return File('${root.path}/intro_selesai').existsSync() ||
        File('${root.path}/pantarlih.db').existsSync();
  } catch (_) {
    return false;
  }
}

Future<Directory> pilihAtauBuatInduk({
  required Directory documents,
  required Directory dokumen,
}) async {
  if (await documents.exists()) return documents;
  if (await dokumen.exists()) return dokumen;
  try {
    await documents.create(recursive: true);
    if (await documents.exists()) return documents;
  } catch (_) {}
  try {
    await dokumen.create(recursive: true);
    if (await dokumen.exists()) return dokumen;
  } catch (_) {}
  throw const StorageAccessException(
      'Folder Documents dan Dokumen tidak dapat dibuat. Periksa izin penyimpanan.');
}

Future<Directory?> cariFolderData(Directory parent) async {
  if (!await parent.exists()) return null;
  Directory? terbaik;
  DateTime? terbaru;
  await for (final entity in parent.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final nama = basenameDir(entity);
    if (!nama.startsWith('Pantarlih')) continue;
    // Staging and kept-aside folders from a relocation are never the active
    // data: an unfinished .partial must be ignored in favour of the origin.
    if (nama.endsWith('.partial') || nama.endsWith('.lama')) continue;
    if (!adaBerkasSesi(entity)) continue;
    final db = File('${entity.path}/pantarlih.db');
    final diubah = await db.exists()
        ? await db.lastModified()
        : DateTime.fromMillisecondsSinceEpoch(0);
    if (terbaik == null || diubah.isAfter(terbaru!)) {
      terbaik = entity;
      terbaru = diubah;
    }
  }
  return terbaik;
}

Future<void> tulisFolderAktif(Directory parent, String nama) async {
  await parent.create(recursive: true);
  await File('${parent.path}/$_berkasAktif').writeAsString(nama, flush: true);
}

Future<String?> bacaFolderAktif(Directory parent) async {
  try {
    final file = File('${parent.path}/$_berkasAktif');
    if (!await file.exists()) return null;
    final nama = (await file.readAsString()).trim();
    return nama.startsWith('Pantarlih') ? nama : null;
  } catch (_) {
    return null;
  }
}

/// Single source of truth for which Pantarlih* folder holds the data:
/// pantarlih.aktif marker first, then the freshest folder scan, then a new
/// folder for the desa. Every reader must go through this, never scan alone.
Future<Directory> resolveFolderAktif(Directory parent, {String? desa}) async {
  final ingin = namaFolderDesa(desa ?? '');
  final aktif = await bacaFolderAktif(parent);
  if (aktif != null) return Directory('${parent.path}/$aktif');
  final existing = await cariFolderData(parent);
  if (existing != null) return existing;
  return Directory('${parent.path}/$ingin');
}

Future<bool> introSudahDilewati({Directory? base}) async {
  if (base != null) return adaBerkasSesi(base);
  try {
    if (await (await _introFlag()).exists()) return true;
  } catch (_) {}
  try {
    final granted = await publicAccessGranted();
    if (granted) {
      final induk = Platform.isAndroid
          ? await indukPublik(buatJikaTidakAda: false)
          : await getApplicationDocumentsDirectory();
      if (induk != null &&
          await induk.exists() &&
          adaBerkasSesi(await resolveFolderAktif(induk))) {
        return true;
      }
    }
    final internal = await getApplicationDocumentsDirectory();
    return adaBerkasSesi(await resolveFolderAktif(internal));
  } catch (_) {
    return false;
  }
}

Future<void> tandaiIntroSelesai({Directory? base, Directory? dataRoot}) async {
  if (base != null) {
    await File('${base.path}/intro_selesai').writeAsString('1', flush: true);
    return;
  }
  await (await _introFlag()).writeAsString('1', flush: true);
  if (dataRoot != null) {
    await File('${dataRoot.path}/intro_selesai')
        .writeAsString('1', flush: true);
    await tulisFolderAktif(dataRoot.parent, basenameDir(dataRoot));
  }
}

Future<bool> requestPublicAccess() async {
  if (!Platform.isAndroid) return true;
  final permission = await _izinPenyimpanan();
  if (!await permission.isGranted) await permission.request();
  return permission.isGranted;
}

Future<Directory?> indukPublik({bool buatJikaTidakAda = true}) async {
  final path = await _channelPenyimpanan.invokeMethod<String>('documentsPath');
  final documents = Directory(path ?? '/storage/emulated/0/Documents');
  final dokumen = Directory('${documents.parent.path}/Dokumen');
  if (!buatJikaTidakAda) {
    if (await documents.exists()) return documents;
    if (await dokumen.exists()) return dokumen;
    return null;
  }
  return pilihAtauBuatInduk(documents: documents, dokumen: dokumen);
}

/// Public Documents/Dokumen when allowed, otherwise the app-private folder.
Future<ResolvedStorage> resolveDataRoot({
  bool? publicAccess,
  Directory? publicRoot,
  Directory? internalBase,
  String? desa,
}) async {
  final allowed = publicAccess ?? await requestPublicAccess();
  if (allowed) {
    if (publicRoot != null) {
      await publicRoot.create(recursive: true);
      return ResolvedStorage(publicRoot, usingPublic: true);
    }
    final parent = Platform.isAndroid
        ? await indukPublik()
        : await getApplicationDocumentsDirectory();
    if (parent == null) {
      throw const StorageAccessException(
          'Folder Documents dan Dokumen tidak dapat dibuka. Periksa izin penyimpanan.');
    }
    final dir = await resolveFolderAktif(parent, desa: desa);
    await dir.create(recursive: true);
    await tulisFolderAktif(parent, basenameDir(dir));
    return ResolvedStorage(dir, usingPublic: true);
  }
  final base = internalBase ?? await getApplicationDocumentsDirectory();
  final dir = await resolveFolderAktif(base, desa: desa);
  await dir.create(recursive: true);
  await tulisFolderAktif(base, basenameDir(dir));
  return ResolvedStorage(dir, usingPublic: false);
}

/// Move the data folder without ever risking the origin copy.
///
/// Protocol: copy into `<target>.partial`, verify every origin file arrived
/// byte-for-byte in length, write a PINDAH_SELESAI marker naming the origin,
/// only then swap the staging folder into place. The origin folder is kept,
/// renamed to `<origin>.lama`, so a crash at any earlier point still leaves
/// a complete dataset behind. Startup ignores `.partial` folders entirely
/// (see cariFolderData), which is the recovery path for a torn move.
Future<void> relocateDataRoot(Directory from, Directory to) async {
  if (from.absolute.path == to.absolute.path) return;
  final namaAsal = basenameDir(from);
  final partial = Directory('${to.parent.path}/${basenameDir(to)}.partial');
  if (await partial.exists()) await partial.delete(recursive: true);
  await partial.create(recursive: true);
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(from.path.length);
    if (entity is Directory) {
      await Directory('${partial.path}$relative').create(recursive: true);
    } else if (entity is File) {
      final dest = File('${partial.path}$relative');
      await dest.parent.create(recursive: true);
      await entity.copy(dest.path);
    }
  }
  final staged = <String>{};
  await for (final entity
      in partial.list(recursive: true, followLinks: false)) {
    if (entity is File) staged.add(entity.path.substring(partial.path.length));
  }
  const gagal = StorageAccessException(
      'Penyalinan data ke folder baru tidak lengkap. Data lama tetap utuh di folder semula.');
  var jumlah = 0;
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(from.path.length);
    final dest = File('${partial.path}$relative');
    if (!staged.contains(relative) ||
        await dest.length() != await entity.length()) {
      throw gagal;
    }
    jumlah++;
  }
  if (staged.length != jumlah) throw gagal;
  await File('${partial.path}/$_penandaPindah')
      .writeAsString(namaAsal, flush: true);
  if (await to.exists()) {
    // Target already exists (resolveDataRoot pre-creates it, or an older
    // desa folder is being reused): merge staging in, jsonl files append
    // so no journalled record from either side is lost.
    await for (final entity
        in partial.list(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(partial.path.length);
      if (entity is Directory) {
        await Directory('${to.path}$relative').create(recursive: true);
      } else if (entity is File) {
        // The marker stays in staging only, never lands in the target.
        if (relative == '/$_penandaPindah') continue;
        final dest = File('${to.path}$relative');
        if (await dest.exists() && relative.endsWith('.jsonl')) {
          var extra = await entity.readAsString();
          if (extra.isEmpty) continue;
          if (!extra.endsWith('\n')) extra = '$extra\n';
          await dest.writeAsString(extra, mode: FileMode.append, flush: true);
        } else if (!await dest.exists()) {
          await entity.rename(dest.path);
        }
      }
    }
    await partial.delete(recursive: true);
  } else {
    await partial.rename(to.path);
  }
  final lama = Directory('${from.parent.path}/$namaAsal.lama');
  if (await lama.exists()) await lama.delete(recursive: true);
  try {
    await from.rename(lama.path);
  } catch (_) {
    // Cross-device renames can fail; leaving the origin untouched is safe.
  }
}

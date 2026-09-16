import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _channelPenyimpanan = MethodChannel('id.kalitorong.pantarlih/storage');
const _berkasAktif = 'pantarlih.aktif';

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

String namaFolderDesa(String desa) {
  final huruf = desa.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  if (huruf.isEmpty) return 'Pantarlih';
  return 'Pantarlih${huruf[0].toUpperCase()}${huruf.substring(1).toLowerCase()}';
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
    if (!basenameDir(entity).startsWith('Pantarlih')) continue;
    if (!adaBerkasSesi(entity)) continue;
    final db = File('${entity.path}/pantarlih.db');
    final diubah =
        await db.exists() ? await db.lastModified() : DateTime.fromMillisecondsSinceEpoch(0);
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

Future<Directory> pilihFolderApp(Directory parent, {String? desa}) async {
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
      if (induk != null && await cariFolderData(induk) != null) return true;
    }
    final internal = await getApplicationDocumentsDirectory();
    return await cariFolderData(internal) != null;
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
    await File('${dataRoot.path}/intro_selesai').writeAsString('1', flush: true);
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
  final path =
      await _channelPenyimpanan.invokeMethod<String>('documentsPath');
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
    final dir = await pilihFolderApp(parent, desa: desa);
    await dir.create(recursive: true);
    await tulisFolderAktif(parent, basenameDir(dir));
    return ResolvedStorage(dir, usingPublic: true);
  }
  final base = internalBase ?? await getApplicationDocumentsDirectory();
  final dir = await pilihFolderApp(base, desa: desa);
  await dir.create(recursive: true);
  await tulisFolderAktif(base, basenameDir(dir));
  return ResolvedStorage(dir, usingPublic: false);
}

Future<void> relocateDataRoot(Directory from, Directory to) async {
  if (from.absolute.path == to.absolute.path) return;
  await to.create(recursive: true);
  await for (final entity in from.list(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(from.path.length);
    final destPath = '${to.path}$relative';
    if (entity is Directory) {
      await Directory(destPath).create(recursive: true);
    } else if (entity is File) {
      final dest = File(destPath);
      await dest.parent.create(recursive: true);
      if (await dest.exists() && destPath.endsWith('.jsonl')) {
        var extra = await entity.readAsString();
        if (extra.isEmpty) continue;
        if (!extra.endsWith('\n')) extra = '$extra\n';
        await dest.writeAsString(extra, mode: FileMode.append, flush: true);
      } else if (!await dest.exists()) {
        await entity.copy(destPath);
      }
    }
  }
}

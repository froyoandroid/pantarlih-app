import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _channelPenyimpanan = MethodChannel('id.tiliksuara.app/storage');

class StorageAccessException implements Exception {
  const StorageAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Public folder name for a desa: `Pantarlih<Desa>_<kode>`. Only the
/// exchange folder (ekspor, cadangan, impor) carries this name now, the
/// database itself never moves when the desa is renamed.
String namaFolderDesa(String desa, {String? kodeWilayah}) {
  final huruf = desa.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  final dasar = huruf.isEmpty
      ? 'Pantarlih'
      : 'Pantarlih${huruf[0].toUpperCase()}${huruf.substring(1).toLowerCase()}';
  // Suffix the wilayah kode so names that normalize identically (Sido Mulyo
  // and Sidomulyo) land in separate folders instead of merging exports.
  final polos =
      (kodeWilayah ?? '').trim().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
  return polos.isEmpty ? dasar : '${dasar}_$polos';
}

String basenameDir(Directory dir) {
  final parts = dir.uri.pathSegments.where((s) => s.isNotEmpty).toList();
  return parts.isEmpty ? '' : parts.last;
}

/// App-private data root. Holds the database, journal, snapshots, import
/// archive and recovery files. Needs no permission and never moves. It does
/// not survive uninstall, which is why every snapshot is also bundled into
/// the public cadangan folder (see exchange.dart).
Future<Directory> akarData({Directory? base}) async {
  final induk = base ?? await getApplicationSupportDirectory();
  final dir = Directory('${induk.path}/data');
  await dir.create(recursive: true);
  return dir;
}

bool adaBerkasSesi(Directory root) {
  try {
    return File('${root.path}/intro_selesai').existsSync() ||
        File('${root.path}/pantarlih.db').existsSync();
  } catch (_) {
    return false;
  }
}

Future<bool> introSudahDilewati({Directory? base}) async {
  try {
    return adaBerkasSesi(base ?? await akarData());
  } catch (_) {
    return false;
  }
}

Future<void> tandaiIntroSelesai({Directory? base}) async {
  final root = base ?? await akarData();
  await File('${root.path}/intro_selesai').writeAsString('1', flush: true);
}

Future<Permission> _izinPenyimpanan() async {
  final sdk = await _channelPenyimpanan.invokeMethod<int>('sdkVersion') ?? 30;
  return sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
}

/// True when the public Documents folder is already writable. Never prompts,
/// so automatic paths (RT switch) can check without interrupting the user.
Future<bool> publicAccessGranted() async {
  if (!Platform.isAndroid) return true;
  try {
    return await (await _izinPenyimpanan()).isGranted;
  } catch (_) {
    return false;
  }
}

/// Prompts for the storage permission. Only export and import call this,
/// the app itself runs entirely without it.
Future<bool> requestPublicAccess() async {
  if (!Platform.isAndroid) return true;
  final permission = await _izinPenyimpanan();
  if (!await permission.isGranted) await permission.request();
  return permission.isGranted;
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

/// Public Documents (or Dokumen on localized ROMs). Android only, other
/// platforms use the app documents directory so tests and desktop work.
Future<Directory> indukPublik() async {
  if (!Platform.isAndroid) return getApplicationDocumentsDirectory();
  final path = await _channelPenyimpanan.invokeMethod<String>('documentsPath');
  final documents = Directory(path ?? '/storage/emulated/0/Documents');
  final dokumen = Directory('${documents.parent.path}/Dokumen');
  return pilihAtauBuatInduk(documents: documents, dokumen: dokumen);
}

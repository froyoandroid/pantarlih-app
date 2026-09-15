import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class StorageAccessException implements Exception {
  const StorageAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Directory> publicDataDirectory() async {
  if (!Platform.isAndroid) {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/PantarlihKalitorong');
  }
  const channel = MethodChannel('id.kalitorong.pantarlih/storage');
  final sdk = await channel.invokeMethod<int>('sdkVersion') ?? 30;
  final permission =
      sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
  if (!await permission.isGranted) await permission.request();
  if (!await permission.isGranted) {
    throw const StorageAccessException(
        'Izinkan akses berkas agar jurnal dan cadangan dapat disimpan di Documents/PantarlihKalitorong. '
        'Berkas tetap dapat diambil lewat USB meskipun aplikasi dihapus.');
  }
  final path = await channel.invokeMethod<String>('documentsPath');
  if (path == null) {
    throw const StorageAccessException('Folder Documents tidak tersedia.');
  }
  final root = Directory('$path/PantarlihKalitorong');
  await root.create(recursive: true);
  return root;
}

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

class ResolvedStorage {
  ResolvedStorage(this.root, {required this.usingPublic});
  final Directory root;
  final bool usingPublic;
}

Future<bool> requestPublicAccess() async {
  if (!Platform.isAndroid) return true;
  const channel = MethodChannel('id.kalitorong.pantarlih/storage');
  final sdk = await channel.invokeMethod<int>('sdkVersion') ?? 30;
  final permission =
      sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
  if (!await permission.isGranted) await permission.request();
  return permission.isGranted;
}

Future<Directory?> _androidDocuments() async {
  const channel = MethodChannel('id.kalitorong.pantarlih/storage');
  final path = await channel.invokeMethod<String>('documentsPath');
  if (path == null) return null;
  return Directory('$path/PantarlihKalitorong');
}

/// Public Documents when allowed, otherwise the app-private documents folder.
Future<ResolvedStorage> resolveDataRoot({
  bool? publicAccess,
  Directory? publicRoot,
  Directory? internalBase,
}) async {
  final allowed = publicAccess ?? await requestPublicAccess();
  if (allowed) {
    final dir = publicRoot ??
        (Platform.isAndroid
            ? await _androidDocuments()
            : Directory(
                '${(await getApplicationDocumentsDirectory()).path}/PantarlihKalitorong'));
    if (dir != null) {
      await dir.create(recursive: true);
      return ResolvedStorage(dir, usingPublic: true);
    }
  }
  final base = internalBase ?? await getApplicationDocumentsDirectory();
  final dir = Directory('${base.path}/PantarlihKalitorong');
  await dir.create(recursive: true);
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

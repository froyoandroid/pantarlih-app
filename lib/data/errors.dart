import 'storage.dart';
import 'store.dart';

/// Only application-authored messages may be shown to the person using the
/// app. Platform, database and filesystem errors can contain private data.
String pesanKesalahan(Object error) {
  if (error is AppException) return error.message;
  if (error is StorageAccessException) return error.message;
  return 'Terjadi kesalahan. Coba lagi.';
}

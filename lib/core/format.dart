import 'package:flutter/services.dart';

class TanggalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length > 8 ? digits.substring(0, 8) : digits;
    final buffer = StringBuffer();
    for (var i = 0; i < clipped.length; i++) {
      if (i == 2 || i == 4) buffer.write('-');
      buffer.write(clipped[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

String timestamp([DateTime? value]) {
  // All persisted timestamps use the mandated WIB offset, independent of device settings.
  final d = (value ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
  return '${d.toIso8601String().replaceAll('Z', '')}+07:00';
}

String tanggalTampil(Object? iso) {
  if (iso == null || iso.toString().isEmpty) return '';
  final date = DateTime.tryParse(iso.toString());
  if (date == null) return iso.toString();
  return '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}';
}

String waktuTampil(Object? raw) {
  final d = DateTime.tryParse(raw?.toString() ?? '')
      ?.toUtc()
      .add(const Duration(hours: 7));
  if (d == null) return '';
  return '${tanggalTampil(d.toIso8601String())} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} WIB';
}

String? nullableText(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
int intValue(Object? value, [int fallback = 0]) =>
    int.tryParse('$value') ?? fallback;
String jkTampil(Object? value) => value == 'L'
    ? 'LAKI-LAKI'
    : value == 'P'
        ? 'PEREMPUAN'
        : '—';
String fileStamp() => timestamp().replaceAll(RegExp(r'[^0-9]'), '');

typedef RecordMap = Map<String, Object?>;

import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

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

String tanggalPanjang() {
  final d = DateTime.now().toUtc().add(const Duration(hours: 7));
  initializeDateFormatting('id');
  return DateFormat('d MMMM y', 'id').format(d);
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

/// SQLite text values from older app versions can be the literal string
/// 'null'. Current writers never produce it (every write goes through
/// nullableText), so this is a display-side guard for legacy rows: null and
/// 'null' both become the empty string, everything else is trimmed.
String teks(Object? v) {
  if (v == null) return '';
  final t = '$v'.trim();
  return t == 'null' ? '' : t;
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

class RtRw implements Comparable<RtRw> {
  const RtRw(this.rw, this.rt);
  final int rw;
  final int rt;

  static List<RtRw> decode(String raw) {
    final out = <RtRw>[];
    for (final part in raw.split(',')) {
      final token = part.trim();
      if (token.isEmpty) continue;
      final bits = token.split('.');
      if (bits.length != 2) continue;
      final nextRw = int.tryParse(bits[0]);
      final nextRt = int.tryParse(bits[1]);
      if (nextRw == null || nextRt == null || nextRw <= 0 || nextRt <= 0) {
        continue;
      }
      final item = RtRw(nextRw, nextRt);
      if (!out.contains(item)) out.add(item);
    }
    out.sort();
    return out;
  }

  static String encode(List<RtRw> items) {
    final copy = [...items]..sort();
    return copy.map((e) => '${e.rw}.${e.rt}').join(',');
  }

  String get label =>
      'RT ${rt.toString().padLeft(2, '0')} / RW ${rw.toString().padLeft(2, '0')}';

  @override
  int compareTo(RtRw other) {
    final byRw = rw.compareTo(other.rw);
    return byRw != 0 ? byRw : rt.compareTo(other.rt);
  }

  @override
  bool operator ==(Object other) =>
      other is RtRw && other.rw == rw && other.rt == rt;

  @override
  int get hashCode => Object.hash(rw, rt);
}

/// Workspace-wide warga totals for the Beranda RT / RW card. Only pairs in
/// [workspace] count, so rows typed outside the workspace never inflate it.
class RingkasanWarga {
  const RingkasanWarga(
      {required this.rt, required this.jumlah, required this.tanpaNik});
  final int rt;
  final int jumlah;
  final int tanpaNik;
}

RingkasanWarga ringkasWarga(List<RecordMap> counts, List<RtRw> workspace) {
  var jumlah = 0, tanpaNik = 0;
  for (final row in counts) {
    final pair = RtRw(intValue(row['rw']), intValue(row['rt']));
    if (!workspace.contains(pair)) continue;
    jumlah += intValue(row['jumlah']);
    tanpaNik += intValue(row['tanpa_nik']);
  }
  return RingkasanWarga(
      rt: workspace.length, jumlah: jumlah, tanpaNik: tanpaNik);
}

String ukuranTampil(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Indonesian labels for warga columns, used when listing what changed.
const _labelKolom = <String, String>{
  'nik': 'NIK',
  'nama': 'nama',
  'jenis_kelamin': 'jenis kelamin',
  'tempat_lahir': 'tempat lahir',
  'tgl_lahir': 'tanggal lahir',
  'desa': 'desa',
  'kode_wilayah': 'kode wilayah',
  'rt': 'RT',
  'rw': 'RW',
  'keterangan': 'keterangan',
  'warna': 'warna',
};

String namaKolomTampil(String kolom) => _labelKolom[kolom] ?? kolom;

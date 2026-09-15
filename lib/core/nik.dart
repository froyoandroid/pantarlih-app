List<String> periksaNik(
    String nik, DateTime? tgl, String? jk, String? prefixLama) {
  final warnings = <String>[];
  if (!RegExp(r'^\d{16}$').hasMatch(nik)) return ['NIK harus 16 digit angka'];
  if (prefixLama != null &&
      prefixLama.length == 6 &&
      !nik.startsWith(prefixLama)) {
    warnings.add('Prefix wilayah beda dari data lama ($prefixLama)');
  }
  if (tgl != null && jk != null) {
    var day = int.parse(nik.substring(6, 8));
    final month = int.parse(nik.substring(8, 10));
    final year = int.parse(nik.substring(10, 12));
    final female = day > 40;
    if (female) day -= 40;
    if (day != tgl.day || month != tgl.month || year != tgl.year % 100) {
      warnings.add('Tanggal lahir di NIK tidak cocok');
    }
    if (female != (jk == 'P')) warnings.add('Jenis kelamin di NIK tidak cocok');
  }
  return warnings;
}

String? parseTanggal(String raw) {
  final match =
      RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(raw.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  try {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  } catch (_) {
    return null;
  }
}

String? prefixNik(String? nik) {
  if (nik == null) return null;
  final match = RegExp(r'^\d+').firstMatch(nik);
  return match?.group(0);
}

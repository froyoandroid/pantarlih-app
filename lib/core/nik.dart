/// Empty is clean. Length and date/JK mismatches are warnings and never block save.
///
/// [prefixWilayah] is the 6-digit kecamatan code of the *current* work
/// location. The first six NIK digits are the kecamatan of issuance, not
/// present domicile, so a mismatch is a yellow warning and never a gate.
List<String> periksaNik(String nik, DateTime? tgl, String? jk,
    {String? prefixWilayah}) {
  if (nik.isEmpty) return [];
  if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
    return ['NIK bukan 16 digit angka'];
  }
  final warnings = <String>[];
  if (tgl != null) {
    var day = int.parse(nik.substring(6, 8));
    final month = int.parse(nik.substring(8, 10));
    final year = int.parse(nik.substring(10, 12));
    final perempuan = day > 40;
    if (perempuan) day -= 40;
    if (day != tgl.day || month != tgl.month || year != tgl.year % 100) {
      warnings.add('Tanggal lahir di NIK tidak cocok');
    }
    if (jk != null && perempuan != (jk == 'P')) {
      warnings.add('Jenis kelamin di NIK tidak cocok');
    }
  }
  if (prefixWilayah != null &&
      prefixWilayah.length == 6 &&
      nik.substring(0, 6) != prefixWilayah) {
    warnings.add(
        'Enam digit awal NIK (${nik.substring(0, 6)}) berbeda dari kecamatan lokasi ($prefixWilayah), wajar bila warga pendatang atau NIK diterbitkan di kecamatan lain');
  }
  return warnings;
}

/// Day-first date to ISO. Accepts DD-MM-YYYY with -, / or . separators and
/// the bare 8-digit form DDMMYYYY that people type on a numeric keyboard.
String? parseTanggal(String raw) {
  final bersih = raw.trim();
  final match =
      RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$').firstMatch(bersih) ??
          RegExp(r'^(\d{2})(\d{2})(\d{4})$').firstMatch(bersih);
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

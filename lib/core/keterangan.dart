/// Common DPS note codes. The column stays free text: unknown values are
/// kept as-is under the "Lainnya" chip and never scored.
///
/// Extra codes live in setelan as newline-separated "KODE=Arti" lines -
/// one string so the setelan journal op stays untouched and no migration is
/// needed. Newline, not ';': UI strings must never contain a semicolon and
/// the scanner cannot tell a separator from copy. The four official codes
/// are the built-in floor and can never be removed.
const keteranganKode = <String, String>{
  'TMS': 'Tidak Memenuhi Syarat',
  'PD': 'Pindah Domisili',
  'B': 'Baru',
  'MD': 'Meninggal Dunia',
};

const keteranganNormal = 'normal';
const keteranganLainnya = 'lainnya';
const kunciKeteranganKustom = 'keterangan_kustom';

/// Parses the stored "KODE=Arti" lines. Built-in codes win over
/// any custom entry with the same code, and malformed pairs are dropped.
Map<String, String> parseKeteranganKustom(String? nilai) {
  final hasil = <String, String>{};
  for (final pasangan in (nilai ?? '').split('\n')) {
    final i = pasangan.indexOf('=');
    if (i <= 0) continue;
    final kode = pasangan.substring(0, i).trim().toUpperCase();
    final arti = pasangan.substring(i + 1).trim();
    if (kode.isEmpty || arti.isEmpty || keteranganKode.containsKey(kode)) {
      continue;
    }
    hasil[kode] = arti;
  }
  return hasil;
}

String tulisKeteranganKustom(Map<String, String> peta) => [
      for (final e in peta.entries) '${e.key}=${e.value}',
    ].join('\n');

/// Built-in codes first (their declaration order), customs after.
Map<String, String> gabungKeterangan(String? nilaiKustom) =>
    {...keteranganKode, ...parseKeteranganKustom(nilaiKustom)};

String? kodeKeterangan(String? raw, [Map<String, String>? kustom]) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return null;
  final upper = trimmed.toUpperCase();
  final peta = {...keteranganKode, if (kustom != null) ...kustom};
  return peta.containsKey(upper) ? upper : null;
}

String chipKeterangan(String? raw, [Map<String, String>? kustom]) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return keteranganNormal;
  return kodeKeterangan(trimmed, kustom) ?? keteranganLainnya;
}

String nilaiKeterangan(String? chip, String lain) {
  if (chip == null || chip == keteranganNormal) return '';
  if (chip == keteranganLainnya) return lain;
  return chip;
}

String? keteranganArti(String? chip, [Map<String, String>? kustom]) {
  if (chip == null) return null;
  return {...keteranganKode, if (kustom != null) ...kustom}[chip];
}

String keteranganTampil(Object? raw, [Map<String, String>? kustom]) {
  final trimmed = '${raw ?? ''}'.trim();
  if (trimmed.isEmpty) return '';
  return kodeKeterangan(trimmed, kustom) ?? trimmed;
}

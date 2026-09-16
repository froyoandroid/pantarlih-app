/// Common DPS note codes. The column stays free text: unknown values are
/// kept as-is under the "Lainnya" chip and never scored.
const keteranganKode = <String, String>{
  'PD': 'pindah domisili',
  'TMS': 'tidak memenuhi syarat',
  'B': 'baru',
  'MD': 'meninggal dunia',
};

const keteranganNormal = 'normal';
const keteranganLainnya = 'lainnya';

String? kodeKeterangan(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return null;
  final upper = trimmed.toUpperCase();
  return keteranganKode.containsKey(upper) ? upper : null;
}

String chipKeterangan(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return keteranganNormal;
  return kodeKeterangan(trimmed) ?? keteranganLainnya;
}

String nilaiKeterangan(String? chip, String lain) {
  if (chip == null || chip == keteranganNormal) return '';
  if (chip == keteranganLainnya) return lain;
  return chip;
}

String? keteranganArti(String? chip) =>
    chip == null ? null : keteranganKode[chip];

String keteranganTampil(Object? raw) {
  final trimmed = '${raw ?? ''}'.trim();
  if (trimmed.isEmpty) return '';
  return kodeKeterangan(trimmed) ?? trimmed;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pantarlih_kalitorong/core/nama.dart';
import 'package:pantarlih_kalitorong/core/nik.dart';
import 'package:pantarlih_kalitorong/core/format.dart';

void main() {
  test('Indonesian normalization follows ordered transformations', () {
    const cases = {
      'MUHAMAD HASAN': 'muhamad hasan',
      'MUHAMMAD HASSAN': 'muhamad hasan',
      'SITI SALIMAH': 'siti salimah',
      'SITY SALLIMAH': 'siti salimah',
      'H. ABDUL ROHMAN': 'abdul rohman',
      'ABDURROHMAN': 'abdurohman',
      'KHOLIL': 'holil',
      'CHOLIL': 'holil',
      'KH. KHOLIL': 'holil',
      'MUHAMAD NAZWA BAIHAKY': 'muhamad nazwa baihaki',
      ' KH.  SOEKARNO123 ': 'sukarno',
      'DZAKIR TSANI SYARIF': 'zakir sani sarip',
    };
    for (final c in cases.entries) {
      expect(normalisasiNama(c.key), c.value, reason: c.key);
    }
  });
  test('matching any token and spelling variants', () {
    expect(skorNama('hasan', 'MUHAMAD HASAN'), 100);
    expect(skorNama('SITY', 'SITI SALIMAH'), 100);
    expect(skorNama('MUHAMMAD', 'MUHAMAD HASAN'), 100);
    expect(skorNama('', 'HASAN'), 0);
    expect(levenshtein('kitten', 'sitting'), 3);
    expect(skorNama('emi', 'EMI'), 100);
  });
  test('strict day-first date parsing and leap years', () {
    for (final d in ['11/09/1973', '11-09-1973', '11.09.1973']) {
      expect(parseTanggal(d), '1973-09-11');
    }
    expect(parseTanggal('29/02/2024'), '2024-02-29');
    for (final bad in [
      '29/02/2023',
      '31/04/2000',
      '12/31/2000',
      '00/01/2000',
      'not a date'
    ]) {
      expect(parseTanggal(bad), isNull);
    }
    expect(tanggalTampil('1973-09-11'), '11-09-1973');
  });
  test('NIK warnings do not infer eligibility', () {
    expect(periksaNik('3327075109730002', DateTime(1973, 9, 11), 'P', '332707'),
        isEmpty);
    expect(periksaNik('3327071109730002', DateTime(1973, 9, 11), 'P', '332707'),
        contains('Jenis kelamin di NIK tidak cocok'));
    expect(periksaNik('123', null, null, null), ['NIK bukan 16 digit angka']);
    expect(periksaNik('1234565109730002', DateTime(1973, 9, 11), 'P', '332707'),
        hasLength(1));
    expect(prefixNik('332707**********'), '332707');
    expect(prefixNik('***123'), isNull);
  });
  test('notes preserve nonblank bytes and timestamps use explicit WIB', () {
    expect(nullableText('  '), isNull);
    expect(nullableText('  bebas apa adanya  '), '  bebas apa adanya  ');
    expect(timestamp(DateTime.utc(2026, 9, 15, 2, 14, 22)),
        '2026-09-15T09:14:22.000+07:00');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pantarlih_kalitorong/core/format.dart';
import 'package:pantarlih_kalitorong/core/keterangan.dart';
import 'package:pantarlih_kalitorong/core/nama.dart';
import 'package:pantarlih_kalitorong/core/nik.dart';
import 'package:pantarlih_kalitorong/data/migrate.dart';
import 'package:pantarlih_kalitorong/data/order.dart';

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
  test('date formatter inserts dashes and still parses to ISO', () {
    final formatted = TanggalInputFormatter().formatEditUpdate(
        TextEditingValue.empty, const TextEditingValue(text: '19091968'));
    expect(formatted.text, '19-09-1968');
    expect(parseTanggal(formatted.text), '1968-09-19');
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
  test('NIK warnings never block and do not infer eligibility', () {
    expect(periksaNik('', null, null), isEmpty);
    expect(periksaNik('3327075109730002', DateTime(1973, 9, 11), 'P'), isEmpty);
    expect(periksaNik('3327071109730002', DateTime(1973, 9, 11), 'P'),
        contains('Jenis kelamin di NIK tidak cocok'));
    expect(periksaNik('123', null, null), ['NIK bukan 16 digit angka']);
    expect(periksaNik('1234565109730002', DateTime(1973, 9, 11), 'P'), isEmpty);
    expect(
        periksaNik('3327075109730002', DateTime(1973, 9, 11), 'P',
            prefixWilayah: '332707'),
        isEmpty);
    expect(
        periksaNik('3327995109730002', DateTime(1973, 9, 11), 'P',
            prefixWilayah: '332707'),
        contains(
            'Enam digit awal NIK (332799) berbeda dari kecamatan lokasi (332707), wajar bila warga pendatang atau NIK diterbitkan di kecamatan lain'));
    expect(
        periksaNik('3327075109730002', DateTime(1973, 9, 11), 'P',
            prefixWilayah: null),
        isEmpty);
  });
  test('journal migrateEvent keeps v2 as identity and rejects a newer file',
      () {
    final event = {
      'schema_v': 2,
      'op': 'INSERT',
      'tabel': 'warga',
      'data': {'id': 1, 'nama': 'SITI'}
    };
    expect(migrateEvent(event, target: 2), event);
    final raised = migrateEvent(event, target: 3);
    expect(raised['schema_v'], 3);
    expect((raised['data'] as Map)['nama'], 'SITI');
    final raised4 = migrateEvent(event, target: 4);
    expect(raised4['schema_v'], 4);
    expect((raised4['data'] as Map)['nama'], 'SITI');
    expect((raised4['data'] as Map)['kode_wilayah'], isNull);
    final raised5from2 = migrateEvent(event, target: 5);
    expect(raised5from2['schema_v'], 5);
    expect((raised5from2['data'] as Map)['kode_wilayah'], isNull);
    final withSource = {
      'schema_v': 4,
      'op': 'INSERT',
      'tabel': 'warga',
      'data': {'id': 1, 'nama': 'SITI', 'sumber_input': 'KERTAS'}
    };
    final raised5 = migrateEvent(withSource, target: 5);
    expect(raised5['schema_v'], 5);
    expect((raised5['data'] as Map)['nama'], 'SITI');
    expect((raised5['data'] as Map).containsKey('sumber_input'), isFalse);
    final raised6 = migrateEvent(withSource, target: 6);
    expect(raised6['schema_v'], 6);
    expect((raised6['data'] as Map)['warna'], isNull);
    expect(
        () => migrateEvent({'schema_v': 6, 'data': {}}, target: 5),
        throwsA(isA<JournalVersionException>().having((e) => e.message,
            'message', contains('lebih baru'))));
    expect(
        () => migrateEvent({'schema_v': 7, 'data': {}}, target: 6),
        throwsA(isA<JournalVersionException>().having((e) => e.message,
            'message', contains('lebih baru'))));
  });

  test('onReorder index correction keeps the same beforeId and afterId', () {
    const ids = [10, 20, 30];
    expect(reorderNeighbors(ids, 0, 3), (beforeId: 30, afterId: null));
    expect(reorderNeighbors(ids, 2, 0), (beforeId: null, afterId: 10));
    expect(reorderNeighbors(ids, 0, 2), (beforeId: 20, afterId: 30));
    expect(reorderNeighbors(ids, 1, 0), (beforeId: null, afterId: 10));
    expect(reorderNeighbors(ids, 1, 3), (beforeId: 30, afterId: null));
  });

  test('sparse insert keys leave room then report a exhausted gap', () {
    expect(urutAntara(null, null), 1000);
    expect(urutAntara(1000, null), 2000);
    expect(urutAntara(1000, 2000), 1500);
    expect(urutAntara(1000, 1001), isNull);
    expect(urutAntara(null, 1000), isNull);
    expect(urutAntara(null, 2000), 1000);
  });
  test('keterangan chips keep codes and leave other text free', () {
    expect(kodeKeterangan('PD'), 'PD');
    expect(kodeKeterangan(' tms '), 'TMS');
    expect(kodeKeterangan('b'), 'B');
    expect(kodeKeterangan('md'), 'MD');
    expect(kodeKeterangan('pindah'), isNull);
    expect(chipKeterangan(''), keteranganNormal);
    expect(chipKeterangan('PD'), 'PD');
    expect(chipKeterangan('catatan sendiri'), keteranganLainnya);
    expect(nilaiKeterangan(null, 'abaikan'), '');
    expect(nilaiKeterangan(keteranganNormal, 'abaikan'), '');
    expect(nilaiKeterangan('PD', 'abaikan'), 'PD');
    expect(keteranganArti('PD'), 'pindah domisili');
    expect(keteranganArti(keteranganNormal), isNull);
    expect(nilaiKeterangan(keteranganLainnya, '  bebas  '), '  bebas  ');
    expect(keteranganTampil('TMS'), 'TMS');
    expect(keteranganTampil('catatan sendiri'), 'catatan sendiri');
    expect(keteranganTampil(''), '');
  });
  test('notes preserve nonblank bytes and timestamps use explicit WIB', () {
    expect(nullableText('  '), isNull);
    expect(nullableText('  bebas apa adanya  '), 'bebas apa adanya');
    expect(nullableText(' 3327071909680001 '), '3327071909680001');
    expect(timestamp(DateTime.utc(2026, 9, 15, 2, 14, 22)),
        '2026-09-15T09:14:22.000+07:00');
  });
}

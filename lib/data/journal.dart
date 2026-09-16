import 'dart:convert';
import 'dart:io';

import '../core/format.dart';

/// One journal file: a WIB calendar day.
class HariJurnal {
  const HariJurnal(
      {required this.file, required this.tanggal, required this.jumlah});
  final File file;
  final String tanggal;
  final int jumlah;
}

/// One journal line, decoded. [rusak] is set when the line could not be
/// read, so damaged lines are visible in the browser instead of vanishing.
class EventJurnal {
  const EventJurnal(
      {required this.id,
      required this.ts,
      required this.op,
      required this.tabel,
      required this.data,
      required this.baris,
      this.rowId,
      this.rusak});
  final int id;
  final String ts;
  final String op;
  final String tabel;
  final RecordMap data;
  final int baris;
  final Object? rowId;
  final String? rusak;

  bool get warga => tabel == 'warga';
  bool get versiWarga => warga && (op == 'INSERT' || op == 'UPDATE');
  bool get hapusWarga => warga && op == 'DELETE';

  static EventJurnal? decode(String line, int baris) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    try {
      final raw = jsonDecode(trimmed);
      if (raw is! Map) throw const FormatException('bukan objek');
      final data = raw['data'];
      return EventJurnal(
          id: intValue(raw['event_id']),
          ts: '${raw['ts'] ?? ''}',
          op: '${raw['op'] ?? ''}',
          tabel: '${raw['tabel'] ?? ''}',
          rowId: raw['row_id'],
          data: data is Map ? Map<String, Object?>.from(data) : {},
          baris: baris);
    } catch (_) {
      return EventJurnal(
          id: 0,
          ts: '',
          op: '',
          tabel: '',
          data: const {},
          baris: baris,
          rusak:
              trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed);
    }
  }
}

/// Read-only access to the journal folder for the in-app browser. Writing
/// stays in AppStore, this class never touches the database.
class JournalReader {
  JournalReader(this.root);
  final Directory root;
  Directory get dir => Directory('${root.path}/journal');

  Future<List<File>> _files() async {
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.jsonl'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Stream<String> _lines(File file) => file
      .openRead()
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  /// Newest day first.
  Future<List<HariJurnal>> hari() async {
    final out = <HariJurnal>[];
    for (final file in await _files()) {
      var n = 0;
      await for (final line in _lines(file)) {
        if (line.trim().isNotEmpty) n++;
      }
      final nama = file.uri.pathSegments.last;
      out.add(HariJurnal(
          file: file,
          tanggal: nama.endsWith('.jsonl')
              ? nama.substring(0, nama.length - 6)
              : nama,
          jumlah: n));
    }
    return out;
  }

  /// Events of one day, newest first. Damaged lines are included.
  Future<List<EventJurnal>> baca(File file) async {
    final out = <EventJurnal>[];
    var n = 0;
    await for (final line in _lines(file)) {
      n++;
      final event = EventJurnal.decode(line, n);
      if (event != null) out.add(event);
    }
    out.sort((a, b) => b.id.compareTo(a.id));
    return out;
  }

  /// Every INSERT, UPDATE and DELETE of one warga across all days, newest
  /// first. A substring filter keeps the scan cheap.
  Future<List<EventJurnal>> riwayatWarga(int wargaId) async {
    final out = <EventJurnal>[];
    final penanda = '"row_id":$wargaId,';
    for (final file in await _files()) {
      var n = 0;
      await for (final line in _lines(file)) {
        n++;
        if (!line.contains(penanda) || !line.contains('"tabel":"warga"')) {
          continue;
        }
        final event = EventJurnal.decode(line, n);
        if (event == null || event.rusak != null || !event.warga) continue;
        if (intValue(event.rowId) != wargaId) continue;
        if (event.versiWarga || event.hapusWarga) out.add(event);
      }
    }
    out.sort((a, b) => b.id.compareTo(a.id));
    return out;
  }

  /// The warga version recorded just before [event], or null for the first.
  Future<EventJurnal?> versiSebelum(EventJurnal event) async {
    final id = intValue(event.rowId ?? event.data['id']);
    if (id <= 0) return null;
    for (final e in await riwayatWarga(id)) {
      if (e.id < event.id && e.versiWarga) return e;
    }
    return null;
  }
}

const _labelSetelan = <String, String>{
  'rt_aktif': 'RT aktif',
  'rw_aktif': 'RW aktif',
  'ruang_kerja': 'wilayah kerja',
  'desa_default': 'nama pada formulir',
  'kode_wilayah_aktif': 'kode wilayah aktif',
  'jurnal_checkpoint': 'checkpoint jurnal',
  'trim_v1_selesai': 'pembersihan teks',
  'laporan_jurnal_diabaikan': 'laporan jurnal diabaikan',
};

/// One Indonesian line per event for the journal browser.
String ringkasanEvent(EventJurnal e) {
  if (e.rusak != null) return 'Baris ${e.baris} tidak terbaca';
  final d = e.data;
  String nama() => '${d['nama'] ?? 'warga ${e.rowId ?? ''}'}'.trim();
  switch ((e.tabel, e.op)) {
    case ('warga', 'INSERT'):
      return 'Tambah warga ${nama()}';
    case ('warga', 'UPDATE'):
      return 'Ubah warga ${nama()}';
    case ('warga', 'DELETE'):
      return 'Hapus warga ${nama()}';
    case ('warga', 'REORDER'):
      return 'Geser urutan warga di RT ${d['rt'] ?? ''}';
    case ('warga', 'RENUMBER'):
      return 'Nomor ulang urutan RT ${d['rt'] ?? ''}';
    case ('warga', 'BACKFILL'):
      final ids = d['ids'];
      return 'Tetapkan kode wilayah ${ids is List ? ids.length : ''} warga';
    case ('referensi', 'IMPORT'):
      return 'Impor referensi ${d['jumlah'] ?? ''} baris dari ${d['nama_file'] ?? ''}';
    case ('referensi', 'DELETE'):
      return 'Hapus semua referensi (${d['jumlah'] ?? 0} baris)';
    case ('lokasi', _):
      return 'Simpan lokasi ${d['nama_desa'] ?? ''}';
    case ('setelan', _):
      final records = d['records'];
      final kunci = records is List
          ? records
              .whereType<Map>()
              .map((r) => _labelSetelan['${r['kunci']}'] ?? '${r['kunci']}')
              .toList()
          : <String>[];
      if (kunci.contains('RT aktif') || kunci.contains('RW aktif')) {
        final peta = {
          for (final r in (records as List).whereType<Map>())
            '${r['kunci']}': '${r['nilai']}'
        };
        final rt = intValue(peta['rt_aktif']);
        final rw = intValue(peta['rw_aktif']);
        if (rt <= 0 && rw <= 0) return 'Lepas semua RT dari wilayah kerja';
        return 'Pindah ke ${RtRw(rw, rt).label}';
      }
      return 'Ubah setelan: ${kunci.join(', ')}';
    case ('export', _):
      final files = d['files'];
      return 'Ekspor ${files is List ? files.length : ''} berkas Excel RW ${d['rw'] ?? ''}';
    case ('snapshot', 'RESTORE'):
      return 'Pulihkan snapshot ${d['berkas'] ?? ''}';
    case ('storage', _):
      return 'Pindah folder data';
    default:
      return '${e.op} ${e.tabel}';
  }
}

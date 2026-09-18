import 'package:flutter/material.dart';

import '../core/format.dart';
import '../data/journal.dart';
import '../data/store.dart';
import 'common.dart';
import 'survey_form.dart';

/// The journal is the source of truth, so it must be readable by the person
/// who owns it: days, then events, then one event with what it changed and
/// a way back to that version.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.session});
  final Session session;
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  List<HariJurnal>? hari;
  RecoveryReport? hasil;
  bool busy = false;

  JournalReader get reader => JournalReader(widget.session.store.root);

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final loaded = await reader.hari();
    if (mounted) setState(() => hari = loaded);
  }

  Future<void> _periksa() async {
    setState(() {
      busy = true;
      hasil = null;
    });
    try {
      final report = await widget.session.store.periksaJurnal();
      if (mounted) setState(() => hasil = report);
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = hari?.fold<int>(0, (n, h) => n + h.jumlah) ?? 0;
    return AppPage(
        session: widget.session,
        title: 'Jurnal',
        subtitle: hari == null ? null : '${hari!.length} hari · $total catatan',
        actions: [
          TextButton(
              onPressed: busy ? null : _periksa, child: const Text('Periksa'))
        ],
        child: hari == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  const Notice(
                      'Setiap perubahan data dicatat otomatis di jurnal dan tidak pernah dihapus. Ketuk tanggal untuk melihat riwayat harian. Anda dapat mengembalikan data ke versi sebelumnya atau membatalkan penghapusan warga. Tombol Periksa memastikan keutuhan catatan jurnal untuk pemulihan tanpa mengubah data aktif.',
                      icon: Icons.menu_book_outlined),
                  if (busy) const LinearProgressIndicator(),
                  if (hasil != null)
                    Notice(
                        hasil!.failed == 0
                            ? 'Jurnal utuh. ${hasil!}'
                            : 'Jurnal bermasalah. ${hasil!}\n\n${hasil!.details.take(20).join('\n')}${hasil!.details.length > 20 ? '\ndan ${hasil!.details.length - 20} baris lainnya' : ''}',
                        warning: hasil!.failed > 0),
                  if (hari!.isEmpty)
                    const EmptyState('Jurnal Masih Kosong',
                        'Catatan perubahan data akan muncul di sini setelah Anda menyimpan warga.'),
                  for (final h in hari!)
                    Card(
                        child: ListTile(
                            leading: const Icon(Icons.today_outlined),
                            title: Text(tanggalTampil(h.tanggal),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text('${h.jumlah} catatan'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: busy
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => JournalDayScreen(
                                            session: widget.session,
                                            hari: h))))),
                ])));
  }
}

IconData _ikonEvent(EventJurnal e) {
  if (e.rusak != null) return Icons.report_problem_outlined;
  switch ((e.tabel, e.op)) {
    case ('warga', 'INSERT'):
      return Icons.person_add_alt_1_outlined;
    case ('warga', 'UPDATE'):
      return Icons.edit_outlined;
    case ('warga', 'DELETE'):
      return Icons.person_remove_outlined;
    case ('warga', _):
      return Icons.swap_vert;
    case ('referensi', _):
      return Icons.file_upload_outlined;
    case ('lokasi', _):
      return Icons.place_outlined;
    case ('export', _):
      return Icons.table_view_outlined;
    case ('snapshot', _):
      return Icons.restore;
    default:
      return Icons.tune;
  }
}

class JournalDayScreen extends StatefulWidget {
  const JournalDayScreen(
      {super.key, required this.session, required this.hari});
  final Session session;
  final HariJurnal hari;
  @override
  State<JournalDayScreen> createState() => _JournalDayScreenState();
}

class _JournalDayScreenState extends State<JournalDayScreen> {
  List<EventJurnal>? events;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final loaded =
        await JournalReader(widget.session.store.root).baca(widget.hari.file);
    if (mounted) setState(() => events = loaded);
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: tanggalTampil(widget.hari.tanggal),
      subtitle:
          events == null ? null : '${events!.length} catatan, terbaru di atas',
      child: events == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                for (final e in events!)
                  Card(
                      color: e.rusak != null ? const Color(0xFFF8E4E4) : null,
                      child: ListTile(
                          leading: Icon(_ikonEvent(e), color: forest),
                          title: Text(ringkasanEvent(e),
                              style: TextStyle(
                                  fontWeight: e.warga
                                      ? FontWeight.w700
                                      : FontWeight.normal)),
                          subtitle: Text(e.rusak != null
                              ? e.rusak!
                              : '${waktuTampil(e.ts)} · catatan ke-${e.id}'),
                          trailing: e.warga && e.rusak == null
                              ? const Icon(Icons.chevron_right)
                              : null,
                          onTap: e.warga && e.rusak == null
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => JournalEventScreen(
                                          session: widget.session,
                                          event: e))).then((_) => load())
                              : null)),
              ])));
}

/// One warga event: the full record as written, what changed against the
/// previous version, and the way back.
class JournalEventScreen extends StatefulWidget {
  const JournalEventScreen(
      {super.key, required this.session, required this.event});
  final Session session;
  final EventJurnal event;
  @override
  State<JournalEventScreen> createState() => _JournalEventScreenState();
}

class _JournalEventScreenState extends State<JournalEventScreen> {
  EventJurnal? sebelum;
  RecordMap? sekarang;
  bool loaded = false, busy = false;

  static const _kolom = [
    'nama',
    'nik',
    'jenis_kelamin',
    'tempat_lahir',
    'tgl_lahir',
    'desa',
    'kode_wilayah',
    'rt',
    'rw',
    'keterangan',
    'warna',
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final reader = JournalReader(widget.session.store.root);
    final prev = await reader.versiSebelum(widget.event);
    final id = intValue(widget.event.rowId ?? widget.event.data['id']);
    final kini = id > 0 ? await widget.session.store.warga(id) : null;
    if (mounted) {
      setState(() {
        sebelum = prev;
        sekarang = kini;
        loaded = true;
      });
    }
  }

  String _nilai(RecordMap? r, String k) {
    if (r == null) return '';
    final v = r[k];
    if (v == null) return '';
    if (k == 'tgl_lahir') return tanggalTampil(v);
    if (k == 'jenis_kelamin') return jkTampil(v);
    return '$v';
  }

  Future<void> _kembalikan() async {
    final e = widget.event;
    final judul = e.hapusWarga ? 'Batalkan hapus?' : 'Kembalikan versi ini?';
    final isi = e.hapusWarga
        ? '${e.data['nama']} dimasukkan lagi ke daftar dengan data seperti saat dihapus, di urutan paling akhir RT-nya. Tercatat sebagai penambahan baru di jurnal.'
        : sekarang == null
            ? '${e.data['nama']} sudah tidak ada di daftar. Versi ini dimasukkan lagi di urutan paling akhir RT-nya.'
            : 'Data ${e.data['nama']} sekarang ditimpa dengan versi ini. Versi sekarang tetap tersimpan di jurnal.';
    if (!await confirm(context, judul, isi,
        action: e.hapusWarga ? 'Batalkan Hapus' : 'Kembalikan')) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.session.store.kembalikanWarga(e.data);
      if (!mounted) return;
      final namaWarga = e.data['nama'] ?? 'warga';
      feedback(
          context,
          e.hapusWarga
              ? 'Data $namaWarga berhasil dikembalikan ke daftar'
              : 'Versi data $namaWarga berhasil dikembalikan');
      await load();
    } catch (err) {
      if (mounted) feedback(context, err, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final berubah = <String>{
      if (sebelum != null && e.op == 'UPDATE')
        for (final k in _kolom)
          if (_nilai(sebelum!.data, k) != _nilai(e.data, k)) k
    };
    return AppPage(
        session: widget.session,
        title: ringkasanEvent(e),
        subtitle: '${waktuTampil(e.ts)} · catatan ke-${e.id}',
        child: !loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(20), children: [
                if (e.hapusWarga)
                  Notice(
                      sekarang == null
                          ? 'Warga ini dihapus dan tidak ada di daftar sekarang. Data di bawah adalah keadaan terakhir sebelum dihapus.'
                          : 'Warga ini pernah dihapus, tetapi sekarang sudah kembali ada di daftar.',
                      warning: sekarang == null)
                else if (sekarang == null)
                  const Notice('Warga ini sudah tidak ada di daftar sekarang.',
                      warning: true)
                else if (e.op == 'UPDATE' && berubah.isEmpty && sebelum != null)
                  const Notice('Tidak ada kolom yang berubah pada catatan ini.')
                else if (e.op == 'UPDATE' && berubah.isNotEmpty)
                  Notice(
                      'Berubah dari versi sebelumnya: ${berubah.map(namaKolomTampil).join(', ')}.'),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  e.hapusWarga
                                      ? 'Data saat dihapus'
                                      : 'Data pada catatan ini',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: forest)),
                              const SizedBox(height: 8),
                              for (final k in _kolom)
                                _Baris(
                                    label: namaKolomTampil(k),
                                    nilai: _nilai(e.data, k),
                                    sebelum: berubah.contains(k)
                                        ? _nilai(sebelum!.data, k)
                                        : null),
                            ]))),
                if (sekarang != null && e.op != 'DELETE')
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Data sekarang di daftar',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: forest)),
                                const SizedBox(height: 8),
                                for (final k in _kolom)
                                  if (_nilai(sekarang, k) != _nilai(e.data, k))
                                    _Baris(
                                        label: namaKolomTampil(k),
                                        nilai: _nilai(sekarang, k)),
                                if (_kolom.every((k) =>
                                    _nilai(sekarang, k) == _nilai(e.data, k)))
                                  const Text('Sama dengan catatan ini.',
                                      style: TextStyle(color: Colors.black54)),
                              ]))),
                if (busy) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                if (sekarang != null)
                  OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => SurveyForm(
                                      session: widget.session,
                                      warga: sekarang!))).then((_) => load()),
                      icon: const Icon(Icons.person_search),
                      label: const Text('Buka Warga Sekarang')),
                const SizedBox(height: 8),
                if (e.hapusWarga && sekarang == null)
                  FilledButton.icon(
                      onPressed: busy ? null : _kembalikan,
                      icon: const Icon(Icons.undo),
                      label: const Text('Batalkan Hapus'))
                else if (e.versiWarga &&
                    (sekarang == null ||
                        _kolom.any(
                            (k) => _nilai(sekarang, k) != _nilai(e.data, k))))
                  FilledButton.icon(
                      onPressed: busy ? null : _kembalikan,
                      icon: const Icon(Icons.history),
                      label: const Text('Kembalikan Versi Ini')),
              ]));
  }
}

class _Baris extends StatelessWidget {
  const _Baris({required this.label, required this.nilai, this.sebelum});
  final String label, nilai;
  final String? sebelum;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nilai.isEmpty ? '—' : nilai,
              style: TextStyle(
                  fontWeight:
                      sebelum != null ? FontWeight.w700 : FontWeight.normal)),
          if (sebelum != null)
            Text('sebelumnya: ${sebelum!.isEmpty ? '—' : sebelum}',
                style: const TextStyle(
                    fontSize: 12,
                    color: amber,
                    decoration: TextDecoration.lineThrough)),
        ])),
      ]));
}

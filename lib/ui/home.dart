import 'package:flutter/material.dart';
import '../core/format.dart';
import 'admin_screen.dart';
import 'common.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'lokasi_screen.dart';
import 'rt_list_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RecordMap> counts = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    counts = await widget.session.store.countsByRtRw();
    if (mounted) setState(() {});
  }

  Future<void> _focus(RtRw pair) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.session.focusRt(pair);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addRtRw() async {
    final chosen = await showDialog<(int, int)>(
        context: context,
        builder: (_) => _TambahRtRwDialog(
            rwAwal: widget.session.rw > 0 ? widget.session.rw : null));
    if (chosen == null) return;
    setState(() => busy = true);
    try {
      await widget.session.addRtRw(chosen.$1, chosen.$2);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _lepas(RtRw pair) async {
    if (!await confirm(context, 'Lepas dari wilayah kerja?',
        '${pair.label} dilepas dari wilayah kerja. Data yang sudah diketik tetap ada.',
        action: 'LEPAS')) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.session.removeRtRw(pair);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _bukaLaporanJurnal() async {
    final text = await widget.session.store.journalReportText();
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Laporan jurnal rusak'),
                content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                        child: SelectableText(text,
                            style:
                                const TextStyle(fontSize: 12, height: 1.4)))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Tutup')),
                ]));
  }

  Future<void> _hapusLaporanJurnal() async {
    if (!await confirm(context, 'Hapus pemberitahuan ini?',
        'Laporan di layar dihilangkan. Baris jurnal yang rusak tetap di folder journal dan tidak ikut dihapus.',
        action: 'HAPUS', dangerous: true)) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.session.store.dismissJournalReport();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  RecordMap? _countFor(RtRw pair) {
    for (final row in counts) {
      if (intValue(row['rt']) == pair.rt && intValue(row['rw']) == pair.rw) {
        return row;
      }
    }
    return null;
  }

  /// Pairs holding typed warga but outside the workspace. Without this the
  /// rows are invisible in every screen yet still exist and still export.
  List<RtRw> get _luarWilayah => [
        for (final row in counts)
          if (!widget.session.workspace.any((p) =>
              p.rw == intValue(row['rw']) && p.rt == intValue(row['rt'])))
            RtRw(intValue(row['rw']), intValue(row['rt']))
      ]..sort();

  Future<void> _tambahkanLuar(RtRw pair) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.session.addRtRw(pair.rt, pair.rw);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String get _lokasiSub {
    final loc = widget.session.lokasi;
    if (loc == null) return 'Pilih desa, lalu nama pada formulir';
    final kec = loc.namaKec?.trim() ?? '';
    if (kec.isEmpty) return loc.kode;
    return '$kec · ${loc.kode}';
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Beranda',
      subtitle: tanggalPanjang(),
      child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Card(
                child: ListTile(
                    minVerticalPadding: 12,
                    onTap: busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    LokasiScreen(session: widget.session))),
                    leading: CircleAvatar(
                        backgroundColor: forest.withValues(alpha: .1),
                        child: const Icon(Icons.place_outlined, color: forest)),
                    title: Text(
                        widget.session.village.isEmpty
                            ? 'Lokasi kerja'
                            : widget.session.village,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_lokasiSub),
                    trailing: const Icon(Icons.chevron_right))),
            const SizedBox(height: 8),
            _kartuRtRw(),
            if (busy) const LinearProgressIndicator(),
            if (widget.session.peringatanCadangan != null)
              Notice(widget.session.peringatanCadangan!,
                  warning: true, icon: Icons.folder_off_outlined),
            if ((widget.session.store.startupRecovery?.showNotice ?? false))
              Notice(
                  'Ada ${widget.session.store.startupRecovery!.failed} baris jurnal yang gagal dibaca. Buka laporan di aplikasi, atau hapus pemberitahuan ini.',
                  warning: true,
                  actions: Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: busy ? null : _bukaLaporanJurnal,
                        child: const Text('BUKA LAPORAN')),
                    TextButton(
                        onPressed: busy ? null : _hapusLaporanJurnal,
                        child: const Text('HAPUS')),
                  ])),
            const SizedBox(height: 8),
            _action(
                Icons.list_alt,
                'Daftar RT',
                'Urutan, sisip, geser, dan hapus',
                () => _open(RtListScreen(session: widget.session))),
            _action(
                Icons.person_search,
                'Ketik data',
                'Cari saran lalu isi satu orang',
                () => _open(SearchScreen(session: widget.session))),
            _action(
                Icons.history,
                'Riwayat',
                '20 input terakhir dan koreksi cepat',
                () => _open(HistoryScreen(session: widget.session))),
            _action(
                Icons.file_upload_outlined,
                'Impor referensi',
                'Bantuan pengetikan dari workbook lama',
                () => _open(ImportScreen(session: widget.session))),
            _action(
                Icons.admin_panel_settings_outlined,
                'Ekspor & pemulihan',
                'Spreadsheet, jurnal, dan snapshot',
                () => _open(AdminScreen(session: widget.session))),
            const SizedBox(height: 20),
            const Notice(
                'Mode offline. Tidak ada jaringan keluar, foto KK, penilaian umur, atau keputusan kelayakan di aplikasi ini.',
                icon: Icons.shield_outlined),
          ])));

  /// One card for the whole workspace: every RT / RW is a tile that carries
  /// its own warga count, so picking the active RT and reading the numbers
  /// happen in the same place.
  Widget _kartuRtRw() {
    final s = widget.session;
    final ringkas = ringkasWarga(counts, s.workspace);
    return Card(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(
                    child: s.workspace.isEmpty
                        ? const SizedBox.shrink()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text('${ringkas.jumlah} warga',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: forest)),
                                Text(
                                    '${ringkas.rt} RT · ${ringkas.tanpaNik} tanpa NIK',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700)),
                              ])),
                TextButton.icon(
                    onPressed: busy ? null : _addRtRw,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambahkan RT / RW',
                        style: TextStyle(fontWeight: FontWeight.normal))),
              ]),
              if (s.workspace.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: Text(
                        'Belum ada RT. Tambahkan RT di bawah RW desa ini. Boleh lebih dari satu RW.',
                        style: TextStyle(color: Colors.black54)))
              else ...[
                const SizedBox(height: 10),
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: LayoutBuilder(builder: (context, box) {
                      const gap = 10.0;
                      final kolom = box.maxWidth >= 520 ? 3 : 2;
                      final lebar = (box.maxWidth - gap * (kolom - 1)) / kolom;
                      return Wrap(spacing: gap, runSpacing: gap, children: [
                        for (final pair
                            in s.workspaceByRw.values.expand((list) => list))
                          SizedBox(
                              width: lebar,
                              child: _RtTile(
                                  pair: pair,
                                  jumlah: intValue(_countFor(pair)?['jumlah']),
                                  tanpaNik:
                                      intValue(_countFor(pair)?['tanpa_nik']),
                                  aktif: s.rt == pair.rt && s.rw == pair.rw,
                                  onTap: busy ? null : () => _focus(pair),
                                  onLepas: busy ? null : () => _lepas(pair))),
                      ]);
                    })),
                if (s.rt > 0 && s.rw > 0) ...[
                  const SizedBox(height: 12),
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                          'Ketik data memakai ${s.label}. Ketuk kartu lain untuk pindah RT, ketuk ikon silang pada kartu aktif untuk melepas dari wilayah kerja.',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12))),
                ],
              ],
              if (_luarWilayah.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Di luar wilayah kerja',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text(
                        'Data tersimpan tetapi tidak tampil di daftar. Ketuk untuk menambahkan ke wilayah kerja.',
                        style: TextStyle(color: Colors.black54))),
                for (final pair in _luarWilayah)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                          '${pair.label} · ${intValue(_countFor(pair)?['jumlah'])} warga · ${intValue(_countFor(pair)?['tanpa_nik'])} tanpa NIK'),
                      trailing: const Icon(Icons.add_circle_outline, size: 20),
                      onTap: busy ? null : () => _tambahkanLuar(pair)),
              ],
            ])));
  }

  Widget _action(
          IconData icon, String title, String detail, VoidCallback onTap) =>
      Card(
          child: ListTile(
              minVerticalPadding: 10,
              leading: CircleAvatar(
                  backgroundColor: forest.withValues(alpha: .1),
                  child: Icon(icon, color: forest)),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(detail),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap));

  void _open(Widget page) {
    if (busy) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page))
        .then((_) => _load());
  }
}

/// Workspace tile: full RT / RW label, warga count as the hero number, NIK gap
/// underneath. The active tile is filled forest and carries the release icon.
class _RtTile extends StatelessWidget {
  const _RtTile(
      {required this.pair,
      required this.jumlah,
      required this.tanpaNik,
      required this.aktif,
      this.onTap,
      this.onLepas});
  final RtRw pair;
  final int jumlah;
  final int tanpaNik;
  final bool aktif;
  final VoidCallback? onTap;
  final VoidCallback? onLepas;

  @override
  Widget build(BuildContext context) {
    final fg = aktif ? Colors.white : forest;
    final muted = aktif ? Colors.white70 : Colors.grey.shade700;
    final nikWarna = aktif
        ? Colors.white70
        : tanpaNik > 0
            ? amber
            : Colors.grey.shade700;
    return Material(
        color: aktif ? forest : canvas,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: aktif ? forest : const Color(0xFFE2E5DD))),
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(pair.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: fg))),
                        SizedBox(
                            width: 28,
                            height: 28,
                            child: aktif
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    tooltip: 'Lepas dari wilayah kerja',
                                    onPressed: onLepas,
                                    icon: Icon(Icons.close, color: fg))
                                : null),
                      ]),
                      const SizedBox(height: 4),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('$jumlah',
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                    color: fg)),
                            const SizedBox(width: 6),
                            Text('warga',
                                style: TextStyle(fontSize: 13, color: muted)),
                          ]),
                      const SizedBox(height: 4),
                      Text('$tanpaNik tanpa NIK',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: tanpaNik > 0 && !aktif
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: nikWarna)),
                    ]))));
  }
}

class _TambahRtRwDialog extends StatefulWidget {
  const _TambahRtRwDialog({this.rwAwal});
  final int? rwAwal;
  @override
  State<_TambahRtRwDialog> createState() => _TambahRtRwDialogState();
}

class _TambahRtRwDialogState extends State<_TambahRtRwDialog> {
  late final TextEditingController rw = TextEditingController(
      text: widget.rwAwal == null ? '' : '${widget.rwAwal}');
  final rt = TextEditingController();

  @override
  void dispose() {
    rw.dispose();
    rt.dispose();
    super.dispose();
  }

  void _simpan() {
    final nextRt = intValue(rt.text);
    final nextRw = intValue(rw.text);
    if (nextRt > 0 && nextRw > 0) {
      Navigator.pop(context, (nextRt, nextRw));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Tambah RT / RW'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'RT berada di bawah RW, RW berada di bawah desa. Boleh menambah RW lain di desa yang sama.'),
            const SizedBox(height: 12),
            TextField(
                controller: rw,
                autofocus: widget.rwAwal == null,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'RW')),
            const SizedBox(height: 12),
            TextField(
                controller: rt,
                autofocus: widget.rwAwal != null,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'RT')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(onPressed: _simpan, child: const Text('TAMBAHKAN')),
          ]);
}

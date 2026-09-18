import 'package:flutter/material.dart';
import '../core/format.dart';
import 'admin_screen.dart';
import 'common.dart';
import 'history_screen.dart';
import 'journal_screen.dart';
import 'lokasi_screen.dart';
import 'referensi_screen.dart';
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
  List<RecordMap> sumberReferensi = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    counts = await widget.session.store.countsByRtRw();
    sumberReferensi = await widget.session.store.sumberReferensi();
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
        action: 'Lepas')) {
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
                title: const Text('Laporan Jurnal Rusak'),
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
        action: 'Hapus', dangerous: true)) {
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

  /// Detail line for the Impor referensi tile: the file actually feeding the
  /// typing suggestions, not a generic description.
  String get _detailReferensi {
    if (sumberReferensi.isEmpty) return 'Belum ada berkas referensi';
    final utama = teks(sumberReferensi.first['sumber_file']);
    final nama = utama.isEmpty ? 'Berkas tanpa nama' : utama;
    final lain = sumberReferensi.length - 1;
    return lain == 0 ? nama : '$nama +$lain berkas lain';
  }

  String get _lokasiSub {
    final loc = widget.session.lokasi;
    if (loc == null) return 'Pilih desa, lalu nama pada formulir';
    final kec = loc.namaKec?.trim() ?? '';
    if (kec.isEmpty) return loc.kode;
    return '$kec · ${loc.kode}';
  }

  @override
  Widget build(BuildContext context) {
    final adaRt = widget.session.rt > 0 && widget.session.rw > 0;
    return AppPage(
        session: widget.session,
        title: 'Beranda',
        subtitle: tanggalPanjang(),
        showVersion: true,
        // The two daily actions live in a sticky bar, so they are under the
        // thumb no matter how long the workspace card grows.
        bottom: Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: busy || !adaRt
                      ? null
                      : () => _open(RtListScreen(session: widget.session)),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Daftar Warga'))),
          const SizedBox(width: 12),
          Expanded(
              child: FilledButton.icon(
                  onPressed: busy || !adaRt
                      ? null
                      : () => _open(SearchScreen(session: widget.session)),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Tambah Warga'))),
        ]),
        child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                children: [
                  Card(
                      child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          onTap: busy
                              ? null
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => LokasiScreen(
                                          session: widget.session))),
                          leading:
                              const Icon(Icons.place_outlined, color: forest),
                          title: Text(
                              widget.session.village.isEmpty
                                  ? 'Lokasi kerja'
                                  : widget.session.village,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          subtitle: Text(_lokasiSub,
                              style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, size: 20))),
                  const SizedBox(height: 4),
                  _kartuRtRw(),
                  if (busy) const LinearProgressIndicator(),
                  if (widget.session.peringatanCadangan != null)
                    Notice(widget.session.peringatanCadangan!,
                        warning: true, icon: Icons.folder_off_outlined),
                  if ((widget.session.store.startupRecovery?.showNotice ??
                      false))
                    Notice(
                        'Ada ${widget.session.store.startupRecovery!.failed} baris jurnal yang gagal dibaca. Buka laporan di aplikasi, atau hapus pemberitahuan ini.',
                        warning: true,
                        actions: Wrap(spacing: 8, children: [
                          TextButton(
                              onPressed: busy ? null : _bukaLaporanJurnal,
                              child: const Text('Buka Laporan')),
                          TextButton(
                              onPressed: busy ? null : _hapusLaporanJurnal,
                              child: const Text('Hapus')),
                        ])),
                  const SizedBox(height: 10),
                  _gridAksi([
                    (
                      Icons.history,
                      'Riwayat',
                      '20 input terakhir',
                      () => _open(HistoryScreen(session: widget.session))
                    ),
                    (
                      Icons.menu_book_outlined,
                      'Jurnal',
                      'Semua catatan, kembalikan versi',
                      () => _open(JournalScreen(session: widget.session))
                    ),
                    (
                      Icons.folder_open_outlined,
                      'Referensi',
                      _detailReferensi,
                      () => _open(ReferensiScreen(session: widget.session))
                    ),
                    (
                      Icons.admin_panel_settings_outlined,
                      'Ekspor & Pemulihan',
                      'Excel, snapshot, cadangan',
                      () => _open(AdminScreen(session: widget.session))
                    ),
                  ]),
                ])));
  }

  /// Two tiles per row, both stretched to the taller one so the grid reads
  /// as a grid and not as four cards of different heights.
  Widget _gridAksi(List<(IconData, String, String, VoidCallback)> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final pasangan = items.sublist(i, (i + 2).clamp(0, items.length));
      rows.add(Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
          child: IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                for (var j = 0; j < pasangan.length; j++) ...[
                  if (j > 0) const SizedBox(width: 10),
                  Expanded(
                      child: _TileAksi(
                          icon: pasangan[j].$1,
                          title: pasangan[j].$2,
                          detail: pasangan[j].$3,
                          onTap: busy ? null : pasangan[j].$4)),
                ],
                if (pasangan.length == 1) ...[
                  const SizedBox(width: 10),
                  const Expanded(child: SizedBox.shrink()),
                ],
              ]))));
    }
    return Column(children: rows);
  }

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
                                Text('${ringkas.jumlah} Warga',
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
                        'Belum ada RT di wilayah kerja. Tekan Tambahkan RT / RW untuk mulai mendata.',
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
                                  tms: intValue(_countFor(pair)?['tms']),
                                  pd: intValue(_countFor(pair)?['pd']),
                                  b: intValue(_countFor(pair)?['b']),
                                  md: intValue(_countFor(pair)?['md']),
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
                          'Input data warga menggunakan ${s.label}. Ketuk kartu untuk berpindah RT, atau ketuk ikon silang pada kartu aktif untuk melepas dari wilayah kerja.',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12))),
                ],
              ],
              if (_luarWilayah.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Di Luar Wilayah Kerja',
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
                          '${pair.label} · ${intValue(_countFor(pair)?['jumlah'])} Warga · ${intValue(_countFor(pair)?['tanpa_nik'])} tanpa NIK'),
                      trailing: const Icon(Icons.add_circle_outline, size: 20),
                      onTap: busy ? null : () => _tambahkanLuar(pair)),
              ],
            ])));
  }

  void _open(Widget page) {
    if (busy) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page))
        .then((_) => _load());
  }
}

/// Compact secondary action: icon, title, one short line. These fit in a
/// compact grid under the workspace card without pushing the daily actions
/// away from the thumb.
class _TileAksi extends StatelessWidget {
  const _TileAksi(
      {required this.icon,
      required this.title,
      required this.detail,
      this.onTap});
  final IconData icon;
  final String title, detail;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E5DD))),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: forest, size: 22),
                    const SizedBox(height: 8),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade700)),
                  ]))));
}

/// Workspace tile: full RT / RW label, warga count as the hero number, NIK gap
/// underneath. The active tile is filled forest and carries the release icon.
class _RtTile extends StatelessWidget {
  const _RtTile(
      {required this.pair,
      required this.jumlah,
      required this.tanpaNik,
      required this.tms,
      required this.pd,
      required this.b,
      required this.md,
      required this.aktif,
      this.onTap,
      this.onLepas});
  final RtRw pair;
  final int jumlah;
  final int tanpaNik;
  final int tms, pd, b, md;
  final bool aktif;
  final VoidCallback? onTap;
  final VoidCallback? onLepas;

  Widget? _statusBar() {
    final statuses = [
      ('TMS', tms),
      ('PD', pd),
      ('MD', md),
      ('B', b),
    ].where((status) => status.$2 > 0).toList();
    if (statuses.isEmpty) return null;
    final color = aktif ? Colors.white : forest;
    return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(7)),
        child: Text(
            statuses.map((status) => '${status.$1} ${status.$2}').join(' · '),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)));
  }

  @override
  Widget build(BuildContext context) {
    final fg = aktif ? Colors.white : forest;
    final muted = aktif ? Colors.white70 : Colors.grey.shade700;
    final nikWarna = aktif
        ? Colors.white70
        : tanpaNik > 0
            ? amber
            : Colors.grey.shade700;
    final statusBar = _statusBar();
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
                            Text('Warga',
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
                      if (statusBar != null) statusBar,
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
                'Tambahkan RT dan RW sesuai wilayah kerja penugasan Anda. Anda dapat menambahkan lebih dari satu RT.'),
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
            FilledButton(onPressed: _simpan, child: const Text('Tambahkan')),
          ]);
}

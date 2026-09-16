import 'package:flutter/material.dart';
import '../core/format.dart';
import '../data/storage.dart';
import 'admin_screen.dart';
import 'common.dart';
import 'history_screen.dart';
import 'import_screen.dart';
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
      storageBanner: true,
      child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 6),
                child: Text(tanggalPanjang(),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600))),
            Card(
                child: ListTile(
                    minVerticalPadding: 12,
                    leading: CircleAvatar(
                        backgroundColor: forest.withValues(alpha: .1),
                        child: const Icon(Icons.place_outlined, color: forest)),
                    title: Text(
                        widget.session.village.isEmpty
                            ? 'Lokasi kerja'
                            : widget.session.village,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_lokasiSub))),
            Padding(
                padding: const EdgeInsets.only(left: 10, top: 4, bottom: 8),
                child: Text(
                    'Folder data: ${basenameDir(widget.session.store.root)}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade700))),
            const SizedBox(height: 8),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                  onPressed: busy ? null : _addRtRw,
                                  child: const Text('Tambahkan RT / RW',
                                      style: TextStyle(
                                          fontWeight: FontWeight.normal)))),
                          if (widget.session.workspace.isEmpty)
                            const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: Text(
                                    'Belum ada RT. Tambahkan RT di bawah RW desa ini. Boleh lebih dari satu RW.',
                                    style: TextStyle(color: Colors.black54)))
                          else ...[
                            for (final rw
                                in widget.session.workspaceByRw.keys) ...[
                              if (rw !=
                                  widget.session.workspaceByRw.keys.first)
                                const SizedBox(height: 12),
                              Text('RW ${rw.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final pair
                                    in widget.session.workspaceByRw[rw]!)
                                  ChoiceChip(
                                      label: Row(mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('RT ${pair.rt.toString().padLeft(2, '0')}'),
                                            if (widget.session.rt == pair.rt &&
                                                widget.session.rw == pair.rw) ...[
                                              const SizedBox(width: 4),
                                              GestureDetector(
                                                  onTap: busy
                                                      ? null
                                                      : () => _lepas(pair),
                                                  child: const Icon(
                                                      Icons.close,
                                                      size: 14)),
                                            ],
                                          ]),
                                      selected:
                                          widget.session.rt == pair.rt &&
                                              widget.session.rw == pair.rw,
                                      onSelected: busy
                                          ? null
                                          : (_) => _focus(pair)),
                              ]),
                            ],
                            if (widget.session.rt > 0 &&
                                widget.session.rw > 0) ...[
                              const SizedBox(height: 12),
                              Text(
                                  'Ketik data memakai ${widget.session.label}. Ketuk ikon silang pada chip aktif untuk melepas dari wilayah kerja.',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12)),
                            ],
                          ],
                        ]))),
            if (busy) const LinearProgressIndicator(),
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
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Jumlah warga per RT',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          if (widget.session.workspace.isEmpty)
                            const Text('Belum ada RT di wilayah kerja.',
                                style: TextStyle(color: Colors.black54))
                          else
                            for (final rw
                                in widget.session.workspaceByRw.keys) ...[
                              Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, bottom: 2),
                                  child: Text(
                                      'RW ${rw.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black54))),
                              for (final pair
                                  in widget.session.workspaceByRw[rw]!)
                                Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(
                                        'RT ${pair.rt.toString().padLeft(2, '0')} · ${_countFor(pair)?['jumlah'] ?? 0} warga · ${_countFor(pair)?['tanpa_nik'] ?? 0} tanpa NIK')),
                            ],
                          if (_luarWilayah.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text('Di luar wilayah kerja',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            const Text(
                                'Data tersimpan tetapi tidak tampil di daftar. Ketuk untuk menambahkan ke wilayah kerja.',
                                style: TextStyle(color: Colors.black54)),
                            for (final pair in _luarWilayah)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: Text(
                                      '${pair.label} · ${_countFor(pair)?['jumlah'] ?? 0} warga · ${_countFor(pair)?['tanpa_nik'] ?? 0} tanpa NIK'),
                                  trailing: const Icon(Icons.add_circle_outline,
                                      size: 20),
                                  onTap:
                                      busy ? null : () => _tambahkanLuar(pair)),
                          ],
                        ]))),
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

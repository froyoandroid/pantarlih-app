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
  List<int> rts = [];
  List<RecordMap> counts = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    rts = await widget.session.store.rtList(widget.session.rw);
    counts = await widget.session.store.countsByRt(widget.session.rw);
    if (mounted) setState(() {});
  }

  Future<void> _change(int value, [int? newRw]) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.session.change(value, newRw ?? widget.session.rw);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseSession() async {
    final rt = TextEditingController(text: '${widget.session.rt}');
    final rw = TextEditingController(text: '${widget.session.rw}');
    final chosen = await showDialog<(int, int)>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Wilayah kerja aktif'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: rt,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'RT')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: rw,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'RW')),
                  const SizedBox(height: 12),
                  const Text(
                      'Mengganti wilayah membuat snapshot dan ekspor otomatis lokal terlebih dahulu.'),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () {
                        if (intValue(rt.text) > 0 && intValue(rw.text) > 0) {
                          Navigator.pop(
                              ctx, (intValue(rt.text), intValue(rw.text)));
                        }
                      },
                      child: const Text('AKTIFKAN'))
                ]));
    if (chosen != null) await _change(chosen.$1, chosen.$2);
  }

  Future<void> editVillage() async {
    final desa = TextEditingController(text: widget.session.village);
    final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Nama desa atau dusun'),
                content: TextField(
                    controller: desa,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                        labelText: 'Desa',
                        hintText: 'nama desa atau dusun')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, desa.text),
                      child: const Text('SIMPAN'))
                ]));
    desa.dispose();
    if (chosen == null) return;
    setState(() => busy = true);
    try {
      await widget.session.setVillage(chosen);
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  RecordMap? _countFor(int rt) {
    for (final row in counts) {
      if (intValue(row['rt']) == rt) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Beranda',
      actions: [
        IconButton(
            onPressed: () => _open(AdminScreen(session: widget.session)),
            icon: const Icon(Icons.settings_outlined))
      ],
      child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('RT aktif',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                TextButton(
                                    onPressed: busy ? null : chooseSession,
                                    child: const Text('Ganti RT / RW'))
                              ]),
                          const SizedBox(height: 10),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final rt in {
                              ...rts,
                              widget.session.rt,
                            })
                              ChoiceChip(
                                  label: Text(
                                      'RT ${rt.toString().padLeft(2, '0')}'),
                                  selected: widget.session.rt == rt,
                                  onSelected: (_) => _change(rt))
                          ]),
                          const SizedBox(height: 10),
                          Text(
                              'RW ${widget.session.rw.toString().padLeft(2, '0')} · ${widget.session.village}',
                              style: const TextStyle(color: Colors.black54)),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => _open(LokasiScreen(
                                          session: widget.session)),
                                  child: const Text('Ganti lokasi'))),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                  onPressed: busy ? null : editVillage,
                                  child: const Text('Ganti nama desa'))),
                        ]))),
            if (busy) const LinearProgressIndicator(),
            if ((widget.session.store.startupRecovery?.failed ?? 0) > 0)
              Notice(
                  'Ada ${widget.session.store.startupRecovery!.failed} baris jurnal yang gagal dibaca. Periksa laporan di folder recovered.',
                  warning: true),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Jumlah baris per RT',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 12),
                          if (counts.isEmpty)
                            const Text('Belum ada data yang diketik.',
                                style: TextStyle(color: Colors.black54)),
                          for (final row in counts)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                    'RT ${intValue(row['rt']).toString().padLeft(2, '0')} · ${row['jumlah']} baris · ${row['tanpa_nik']} tanpa NIK')),
                          if (_countFor(widget.session.rt) == null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                    'RT ${widget.session.rt.toString().padLeft(2, '0')} · 0 baris · 0 tanpa NIK',
                                    style: const TextStyle(
                                        color: Colors.black54))),
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
                'Ekspor & Pemulihan',
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

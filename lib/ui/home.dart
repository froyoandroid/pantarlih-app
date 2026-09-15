import 'package:flutter/material.dart';
import '../core/format.dart';
import 'common.dart';
import 'import_screen.dart';
import 'search_screen.dart';
import 'remaining_screen.dart';
import 'history_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<int> rts = [], selected = [];
  Map<String, Object?>? progress;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {});
    rts = await widget.session.store.rtList(widget.session.rw);
    selected = [widget.session.rt];
    progress = await widget.session.store
        .progress(widget.session.rt, widget.session.rw);
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
    // Controllers are owned by the dialog until its closing animation finishes.
    if (chosen != null) await _change(chosen.$1, chosen.$2);
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
                            for (final rt in rts)
                              ChoiceChip(
                                  label: Text(
                                      'RT ${rt.toString().padLeft(2, '0')}'),
                                  selected: selected.contains(rt),
                                  onSelected: (_) => _change(rt))
                          ]),
                          const SizedBox(height: 10),
                          Text(
                              'RW ${widget.session.rw.toString().padLeft(2, '0')} · ${widget.session.village}',
                              style: const TextStyle(color: Colors.black54)),
                        ]))),
            if (busy) const LinearProgressIndicator(),
            if ((widget.session.store.startupRecovery?.failed ?? 0) > 0)
              Notice(
                  'Ada ${widget.session.store.startupRecovery!.failed} baris jurnal yang gagal dibaca. Periksa laporan di folder recovered.',
                  warning: true),
            if (progress != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Progres RT aktif',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 14),
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  _stat('${progress!['surveyed']}', 'tertaut'),
                                  _stat('${progress!['remaining']}', 'sisa'),
                                  _stat('${progress!['grey']}', 'abu-abu'),
                                  _stat('${progress!['inputs']}', 'input baru')
                                ]),
                            const SizedBox(height: 14),
                            LinearProgressIndicator(
                                value: intValue(progress!['total']) == 0
                                    ? 0
                                    : intValue(progress!['surveyed']) /
                                        intValue(progress!['total'])),
                            const SizedBox(height: 8),
                            Text(
                                '${progress!['surveyed']} / ${progress!['total']} data lama tertaut',
                                style: const TextStyle(fontSize: 12)),
                          ]))),
            const SizedBox(height: 8),
            _action(
                Icons.person_search,
                'Cari & Input',
                'Isi data sesuai KK satu per satu',
                () => _open(SearchScreen(session: widget.session))),
            _action(
                Icons.pending_actions_outlined,
                'Daftar Sisa',
                'Warga lama yang belum ditautkan',
                () => _open(RemainingScreen(session: widget.session))),
            _action(
                Icons.history,
                'Riwayat',
                '20 input terakhir dan koreksi cepat',
                () => _open(HistoryScreen(session: widget.session))),
            _action(
                Icons.file_upload_outlined,
                'Impor Data Lama',
                'Mulai dari workbook Excel',
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
  Widget _stat(String value, String label) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: forest)),
        Text(label, style: const TextStyle(fontSize: 11))
      ]);
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

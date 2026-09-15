import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/spreadsheets.dart';
import 'common.dart';
import 'history_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.session});
  final Session session;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool busy = false, allRt = true, combined = false;
  List<File> files = [], snapshots = [];
  String? report;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.session.store.snapshots();
    if (mounted) setState(() => snapshots = result);
  }

  Future<void> run(Future<String> Function() action) async {
    setState(() {
      busy = true;
      report = null;
    });
    try {
      final result = await action();
      if (mounted) {
        setState(() => report = result);
        await load();
      }
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share(List<File> selected) async {
    if (!await confirm(context, 'Bagikan data pribadi?',
        'Berkas memuat NIK, nama, dan tanggal lahir. Pilih penerima tepercaya; aplikasi lain yang Anda pilih dapat mengirimkan berkas ke internet.',
        action: 'PILIH PENERIMA')) {
      return;
    }
    try {
      await Share.shareXFiles(selected.map((f) => XFile(f.path)).toList(),
          subject: 'Pendataan DPS Kalitorong');
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Ekspor & pemulihan',
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Pemeriksaan data',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Card(
            child: ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: const Text('Konflik RT / RW'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HistoryScreen(
                                session: widget.session,
                                kind: SurveyListKind.conflicts))))),
        Card(
            child: ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: const Text('Duplikat NIK'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HistoryScreen(
                                session: widget.session,
                                kind: SurveyListKind.duplicates))))),
        const SizedBox(height: 24),
        const Text('Ekspor Excel',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Semua RT di RW ${widget.session.rw}'),
            subtitle: const Text('Nonaktif: hanya RT aktif'),
            value: allRt,
            onChanged: busy ? null : (v) => setState(() => allRt = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gabungan, satu sheet per RT'),
            subtitle: const Text('Nonaktif: satu file per RT'),
            value: combined,
            onChanged: busy ? null : (v) => setState(() => combined = v)),
        const Notice(
            'Data survei diurut waktu input, lalu data pending ditempel di bawahnya. Pending, duplikat, dan konflik juga dibuat sebagai file terpisah.'),
        FilledButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                      files = await ExportService(widget.session.store)
                          .generate(
                              rw: widget.session.rw,
                              rt: allRt ? null : widget.session.rt,
                              combined: combined);
                      return '${files.length} berkas Excel dibuat. Belum dibagikan ke siapa pun.';
                    }),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('BUAT FILE EXCEL')),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final file in files)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(file.path.split('/').last,
                    style: const TextStyle(fontSize: 12))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: busy ? null : () => share(files),
              icon: const Icon(Icons.share_outlined),
              label: const Text('BAGIKAN FILE')),
        ],
        const SizedBox(height: 28),
        const Text('Ketahanan & pemulihan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Notice(
            'Jurnal dicatat sebelum database pada setiap aksi. Snapshot menyimpan 20 cadangan terbaru; snapshot paling lama dirotasi otomatis. Jurnal tidak pernah dihapus.',
            icon: Icons.shield_outlined),
        OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                      final f = await widget.session.store.snapshot();
                      return 'Snapshot tersimpan: ${f.path}';
                    }),
            icon: const Icon(Icons.save_alt),
            label: const Text('BUAT SNAPSHOT SEKARANG')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    if (!await confirm(context, 'Bangun ulang dari jurnal?',
                        'Database saat ini dipindahkan ke recovered, tidak dihapus. Semua jurnal diputar ulang. Baris rusak dicatat ke laporan dan tidak menghentikan pemulihan.',
                        action: 'BANGUN ULANG', dangerous: true)) {
                      return;
                    }
                    await run(() async {
                      final result = await widget.session.store.rebuild();
                      await widget.session.load();
                      return '$result\nDatabase lama: ${result.previousDatabase}${result.failurePath == null ? '' : '\nLaporan gagal: ${result.failurePath}'}';
                    });
                  },
            icon: const Icon(Icons.restore),
            label: const Text('BANGUN ULANG DATABASE')),
        if (busy)
          const Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (report != null) Notice(report!),
        const SizedBox(height: 16),
        Text('Snapshot (${snapshots.length}/20)',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        if (snapshots.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada snapshot.')),
        for (final file in snapshots)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(file.path.split('/').last,
                  style: const TextStyle(fontSize: 12)),
              leading: const Icon(Icons.storage, size: 20),
              trailing: IconButton(
                  tooltip: 'Bagikan snapshot',
                  onPressed: busy ? null : () => share([file]),
                  icon: const Icon(Icons.share_outlined))),
        const SizedBox(height: 16),
        SelectableText('Lokasi berkas\n${widget.session.store.root.path}',
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        const Text(
            'Salin folder ini lewat kabel USB secara berkala. Berkas tidak terenkripsi; simpan cadangan di lokasi yang aman.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
      ]));
}

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/format.dart';
import '../data/exchange.dart';
import '../data/spreadsheets.dart';
import 'common.dart';
import 'history_screen.dart';
import 'journal_screen.dart';
import 'snapshot_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, required this.session});
  final Session session;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  bool busy = false, allRt = true, combined = false, kop = false;
  List<File> files = [], snapshots = [];
  String? report;
  Map<String, String> pack = {};
  int missingKode = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await widget.session.store.snapshots();
    final groups = await widget.session.store.missingKodeGroups();
    final meta = await widget.session.wilayah.meta();
    if (mounted) {
      setState(() {
        snapshots = result;
        pack = meta;
        missingKode = groups.fold<int>(0, (n, r) => n + intValue(r['jumlah']));
      });
    }
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
        'Berkas memuat NIK, nama, dan tanggal lahir. Pilih penerima tepercaya, aplikasi lain yang Anda pilih dapat mengirimkan berkas ke internet.',
        action: 'PILIH PENERIMA')) {
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(
          files: selected.map((f) => XFile(f.path)).toList(),
          subject: 'Pendataan DPS'));
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  /// Picks a `cadangan_<stamp>.zip` (the picker needs no storage permission)
  /// and replaces database plus journal with the bundle's contents.
  Future<void> _pulihkanDariCadangan() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['zip']);
    if (file == null || !mounted) return;
    if (!await confirm(context, 'Pulihkan dari cadangan?',
        'Database dan jurnal sekarang diganti dengan isi ${file.name}. Keduanya diamankan dulu ke folder recovered. Semua yang diketik setelah cadangan itu dibuat hilang dari daftar.',
        action: 'PULIHKAN', dangerous: true)) {
      return;
    }
    await run(() async {
      final result = await pulihkanCadangan(
          widget.session.store, await file.readAsBytes());
      await widget.session.load();
      return 'Cadangan ${file.name} dipulihkan. $result';
    });
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
        Card(
            child: ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Duplikat nama'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => HistoryScreen(
                                session: widget.session,
                                kind: SurveyListKind.duplicateNames))))),
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
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sertakan kop di atas tabel'),
            subtitle: const Text('Header tabel bergeser ke baris 7.'),
            value: kop,
            onChanged: busy ? null : (v) => setState(() => kop = v)),
        const Notice(
            'Urutan mengikuti nomor sisip, bukan waktu input. Nomor di file mulai 1 di tiap RT. Duplikat NIK, duplikat nama, dan daftar tanpa NIK dibuat terpisah.'),
        FilledButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                      final folder =
                          await widget.session.folderPertukaran(minta: true);
                      files = await ExportService(widget.session.store)
                          .generate(
                              tujuan: folder!.ekspor,
                              rw: widget.session.rw,
                              rt: allRt ? null : widget.session.rt,
                              combined: combined,
                              kop: kop);
                      return '${files.length} berkas Excel dibuat di ${folder.label}/ekspor. Belum dibagikan ke siapa pun.';
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
        const Text('Wilayah',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Notice(widget.session.wilayah.available
            ? '${pack['kepmendagri'] ?? '—'}\n${pack['jumlah_total'] ?? '—'} baris · SHA ${pack['sha_sumber'] ?? '—'}'
            : 'Paket wilayah tidak terbaca'
                '${widget.session.wilayah.alasanGagal == null ? '' : ': ${widget.session.wilayah.alasanGagal!.replaceAll(';', ',')}'}.'
                ' Mode manual tetap berfungsi.'),
        if (missingKode > 0)
          OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final kode = widget.session.kodeWilayah;
                      if (kode == null || kode.isEmpty) {
                        feedback(context,
                            'Pilih lokasi kerja dulu sebelum menetapkan kode pada warga lama.',
                            error: true);
                        return;
                      }
                      final groups =
                          await widget.session.store.missingKodeGroups();
                      final ringkas = groups
                          .map((g) =>
                              '• ${g['desa'] == '' ? '(kosong)' : g['desa']} · ${g['jumlah']} warga')
                          .join('\n');
                      if (!context.mounted) return;
                      if (!await confirm(
                          context,
                          'Tetapkan kode wilayah untuk warga lama?',
                          '$missingKode warga tanpa kode akan diisi $kode.\n\n$ringkas\n\nIni bukan tebakan otomatis. Anda harus yakin warga lama berasal dari desa yang sekarang dipilih.',
                          action: 'TETAPKAN')) {
                        return;
                      }
                      await run(() async {
                        final n = await widget.session.store
                            .backfillKodeWilayah(kode);
                        return '$n warga diperbarui.';
                      });
                    },
              icon: const Icon(Icons.pin_drop_outlined),
              label: const Text('TETAPKAN KODE WILAYAH UNTUK WARGA LAMA')),
        const SizedBox(height: 28),
        const Text('Ketahanan & pemulihan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Notice(
            'Jurnal dicatat sebelum database pada setiap aksi. Snapshot menyimpan 20 salinan terbaru di dalam aplikasi, yang paling lama dirotasi otomatis. Setiap snapshot juga dibundel bersama jurnal ke folder cadangan publik bila izin berkas sudah diberikan. Jurnal tidak pernah dihapus.',
            icon: Icons.shield_outlined),
        OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                      final f = await widget.session.store.snapshot();
                      final folder =
                          await widget.session.folderPertukaran(minta: true);
                      final zip = await tulisCadangan(
                          widget.session.store, f, folder!.cadangan);
                      return 'Snapshot tersimpan. Cadangan ${zip.uri.pathSegments.last} ditulis ke ${folder.label}/cadangan.';
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
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: busy ? null : _pulihkanDariCadangan,
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('PULIHKAN DARI CADANGAN')),
        if (busy)
          const Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (report != null) Notice(report!),
        const SizedBox(height: 16),
        Card(
            child: ListTile(
                leading: const Icon(Icons.history_toggle_off),
                title: Text('Snapshot (${snapshots.length}/20)',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Lihat isi, bandingkan, pulihkan'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    SnapshotScreen(session: widget.session)))
                        .then((_) => load()))),
        Card(
            child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Jurnal',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle:
                    const Text('Telusuri catatan, periksa, kembalikan versi'),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                JournalScreen(session: widget.session))))),
        const SizedBox(height: 28),
        const Text('Folder pertukaran',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Notice(
            'Excel, cadangan, dan berkas impor berada di ${widget.session.labelFolderPertukaran}. Database, jurnal, dan snapshot tersimpan di dalam aplikasi dan tidak butuh izin. Izin akses berkas diminta saat pertama kali ekspor atau impor, setelah itu setiap pergantian RT menulis cadangan otomatis ke folder yang sama.',
            icon: Icons.folder_outlined),
        const Text(
            'Salin folder cadangan lewat kabel USB secara berkala. Berkas tidak terenkripsi, simpan di lokasi yang aman. Data di dalam aplikasi ikut hilang bila aplikasi dihapus, cadangan di folder publik tidak.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 28),
        const Text('Tentang',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Notice(
            'Pantarlih memakai data wilayah administrasi dari proyek WILAYAH oleh Cahya DSN (github.com/cahyadsn/wilayah), lisensi MIT, sesuai Kepmendagri No. 300.2.2-2430 Tahun 2025. Nama desa pada data yang sudah tersimpan adalah snapshot dan tidak berubah saat pack wilayah diperbarui.',
            icon: Icons.info_outline),
      ]));
}

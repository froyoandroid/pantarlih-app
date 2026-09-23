import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/format.dart';
import '../data/exchange.dart';
import '../data/spreadsheets.dart';
import '../data/storage.dart' show bukaBerkas;
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
    if (!await confirm(context, 'Bagikan Data Pribadi?',
        'Berkas berisi NIK, nama, dan tanggal lahir. Pilih penerima yang tepercaya. Aplikasi yang dipilih untuk membagikan berkas dapat mengirimkannya ke internet.',
        action: 'Pilih Penerima')) {
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
    final lampau = await lampauiBatasUkuran(file.length);
    if (!mounted) return;
    if (lampau != null) {
      feedback(context, lampau, error: true);
      return;
    }
    if (!await confirm(context, 'Pulihkan dari Cadangan?',
        'Data dan riwayat perubahan saat ini akan diganti dengan isi ${file.name}. Perubahan setelah cadangan dibuat tidak akan muncul di daftar. Salinan data sebelumnya tetap disimpan di dalam aplikasi.',
        action: 'Pulihkan', dangerous: true)) {
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
      title: 'Ekspor & Pemulihan',
      child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Pemeriksaan Data',
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
                title: const Text('Duplikat Nama'),
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
            subtitle: const Text('Matikan untuk mengekspor RT aktif saja'),
            value: allRt,
            onChanged: busy ? null : (v) => setState(() => allRt = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Gabungan, Satu Lembar Per RT'),
            subtitle:
                const Text('Matikan untuk membuat berkas terpisah per RT'),
            value: combined,
            onChanged: busy ? null : (v) => setState(() => combined = v)),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sertakan Kop di Atas Tabel'),
            subtitle: const Text('Tambahkan identitas wilayah di atas tabel'),
            value: kop,
            onChanged: busy ? null : (v) => setState(() => kop = v)),
        const Notice(
            'Urutan mengikuti susunan warga yang disimpan. Penomoran dimulai dari 1 pada setiap RT. Jika ditemukan, NIK ganda, nama ganda, dan warga tanpa NIK ditampilkan pada lembar tambahan dalam berkas yang sama.'),
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
                      return '${files.length} berkas Excel tersimpan di folder ekspor. Berkas belum dibagikan ke siapa pun.';
                    }),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Buat File Excel')),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final file in files)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                      child: Text(file.path.split('/').last,
                          style: const TextStyle(fontSize: 12))),
                  TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final pesan = await bukaBerkas(file.path);
                              if (pesan != null && context.mounted) {
                                feedback(context, pesan, error: true);
                              }
                            },
                      child: const Text('Buka')),
                ])),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: busy ? null : () => share(files),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Bagikan File')),
        ],
        const SizedBox(height: 28),
        const Text('Wilayah',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Notice(widget.session.wilayah.available
            ? '${pack['kepmendagri'] ?? '—'}\n${pack['jumlah_total'] ?? '—'} wilayah tersedia untuk dipilih'
            : 'Daftar wilayah belum dapat dibuka. Lokasi kerja tetap dapat diisi secara manual.'),
        if (missingKode > 0)
          OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final kode = widget.session.kodeWilayah;
                      if (kode == null || kode.isEmpty) {
                        feedback(context,
                            'Pilih lokasi kerja terlebih dahulu untuk melengkapi kode wilayah pada data warga lama.',
                            error: true);
                        return;
                      }
                      final groups =
                          await widget.session.store.missingKodeGroups();
                      final ringkas = groups
                          .map((g) =>
                              '• ${g['desa'] == '' ? '(kosong)' : g['desa']} · ${g['jumlah']} Warga')
                          .join('\n');
                      if (!context.mounted) return;
                      if (!await confirm(
                          context,
                          'Tetapkan Kode Wilayah untuk Warga Lama?',
                          '$missingKode warga akan diberi kode wilayah $kode.\n\n$ringkas\n\nPastikan semua warga ini berasal dari desa yang sedang dipilih sebelum melanjutkan.',
                          action: 'Tetapkan')) {
                        return;
                      }
                      await run(() async {
                        final n = await widget.session.store
                            .backfillKodeWilayah(kode);
                        return '$n warga diperbarui.';
                      });
                    },
              icon: const Icon(Icons.pin_drop_outlined),
              label: const Text('Tetapkan Kode Wilayah untuk Warga Lama')),
        const SizedBox(height: 28),
        const Text('Cadangan & Pemulihan',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Notice(
            'Jurnal menyimpan riwayat perubahan data. Snapshot adalah salinan data pada waktu tertentu, dengan 20 salinan terbaru tersimpan di dalam aplikasi. Setelah izin berkas tersedia, salinan data dan jurnal juga disimpan dalam cadangan ZIP di luar aplikasi saat berpindah RT.',
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
                      return 'Snapshot tersimpan. Berkas ${zip.uri.pathSegments.last} tersedia di folder cadangan.';
                    }),
            icon: const Icon(Icons.save_alt),
            label: const Text('Buat Snapshot Sekarang')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    if (!await confirm(context, 'Pulihkan dari Jurnal?',
                        'Data aktif akan disusun kembali dari riwayat perubahan. Catatan yang rusak akan dilewati, sehingga sebagian data mungkin belum kembali. Salinan data saat ini tetap disimpan di dalam aplikasi. Periksa hasilnya setelah pemulihan selesai.',
                        action: 'Pulihkan', dangerous: true)) {
                      return;
                    }
                    await run(() async {
                      final result = await widget.session.store.rebuild();
                      await widget.session.load();
                      return '$result\nSalinan data sebelumnya tetap tersimpan di dalam aplikasi.${result.failurePath == null ? '' : '\nSebagian catatan belum berhasil dipulihkan. Periksa kembali data warga.'}';
                    });
                  },
            icon: const Icon(Icons.restore),
            label: const Text('Pulihkan dari Jurnal')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: busy ? null : _pulihkanDariCadangan,
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('Pulihkan dari Cadangan')),
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
        const Text('Penyimpanan Berkas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Notice(
            'Excel, cadangan, dan berkas impor berada di folder pertukaran pada penyimpanan perangkat. Data utama tetap tersimpan di dalam aplikasi. Izin akses berkas hanya diminta saat ekspor, impor, atau membuat cadangan. Setelah diizinkan, cadangan otomatis dibuat saat berpindah RT.',
            icon: Icons.folder_outlined),
        const Text(
            'Cadangan di luar aplikasi tidak dienkripsi. Simpan di tempat aman dan salin secara berkala, misalnya ke komputer melalui kabel USB. Menghapus aplikasi atau data aplikasi akan menghapus data di dalamnya. Cadangan yang sudah dibuat di folder publik tetap terpisah.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 28),
        const Text('Tentang',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Notice(
            'TilikSuara bekerja tanpa internet dan menyimpan data di perangkat. Aplikasi membantu pencatatan, tidak memotret dokumen atau menentukan hak pilih warga.',
            icon: Icons.shield_outlined),
        const Notice(
            'Data wilayah berasal dari proyek Wilayah oleh Cahya DSN dengan lisensi MIT, sesuai Kepmendagri No. 300.2.2-2430 Tahun 2025. Pembaruan daftar wilayah tidak mengubah nama desa pada data warga yang sudah disimpan.',
            icon: Icons.info_outline),
        const SizedBox(height: 32),
        const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Dikembangkan oleh Firenza',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
          Text('2026 - Kalitorong',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
        ])),
      ]));
}

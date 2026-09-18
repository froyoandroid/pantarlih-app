import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/exchange.dart';
import '../data/store.dart';
import 'common.dart';

/// Snapshots are only worth keeping if they can be opened. This screen lists
/// each one with what it holds, and lets the user read it, compare it with
/// the live data, or roll the database back to it.
class SnapshotScreen extends StatefulWidget {
  const SnapshotScreen({super.key, required this.session});
  final Session session;
  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> {
  List<SnapshotInfo>? items;
  int rusak = 0;
  bool busy = false;
  String? report;

  AppStore get store => widget.session.store;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final files = await store.snapshots();
    final loaded = <SnapshotInfo>[];
    var gagal = 0;
    for (final f in files) {
      try {
        loaded.add(await store.infoSnapshot(f));
      } catch (_) {
        gagal++;
      }
    }
    if (mounted) {
      setState(() {
        items = loaded;
        rusak = gagal;
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
      if (mounted) setState(() => report = result);
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    }
  }

  Future<void> _buat() => run(() async {
        final f = await store.snapshot();
        final folder = await widget.session.folderPertukaran(minta: true);
        final zip = await tulisCadangan(store, f, folder!.cadangan);
        return 'Snapshot baru tersimpan. Cadangan ${zip.uri.pathSegments.last} ditulis ke ${folder.label}/cadangan.';
      });

  Future<void> _pulihkan(SnapshotInfo info) async {
    final waktu = waktuTampil(timestamp(info.dibuat));
    if (!await confirm(context, 'Pulihkan snapshot ini?',
        'Database kembali ke keadaan $waktu dengan ${info.jumlah} warga. Warga yang diketik setelah itu hilang dari daftar, yang dihapus kembali muncul.\n\nDatabase sekarang diamankan ke folder recovered dan jurnal tetap lengkap. Pemulihan ini juga tercatat di jurnal.',
        action: 'Pulihkan', dangerous: true)) {
      return;
    }
    await run(() async {
      final result = await store.restoreSnapshot(info.file);
      await widget.session.load();
      return 'Database dipulihkan ke $waktu. $result';
    });
  }

  Future<void> _bagikan(SnapshotInfo info) async {
    if (!await confirm(context, 'Bagikan data pribadi?',
        'Snapshot memuat NIK, nama, dan tanggal lahir semua warga. Pilih penerima tepercaya, aplikasi lain yang Anda pilih dapat mengirimkan berkas ke internet.',
        action: 'Pilih Penerima')) {
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(
          files: [XFile(info.file.path)], subject: 'Snapshot TilikSuara'));
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  void _buka(Widget page) {
    if (busy) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Snapshot',
      subtitle: items == null ? null : '${items!.length} dari 20 tersimpan',
      actions: [
        TextButton(
            onPressed: busy ? null : _buat, child: const Text('Buat Baru'))
      ],
      child: items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Notice(
                    'Snapshot adalah salinan utuh database lokal pada titik waktu tertentu. Dibuat otomatis setiap berpindah RT dan lewat tombol Buat Baru. Tersimpan hingga 20 salinan terbaru secara bergantian. Tombol Pulihkan mengembalikan database ke keadaan pada waktu snapshot tersebut.',
                    icon: Icons.history_toggle_off),
                if (busy) const LinearProgressIndicator(),
                if (report != null) Notice(report!),
                if (rusak > 0)
                  Notice(
                      '$rusak berkas snapshot tidak dapat dibaca dan tidak ditampilkan.',
                      warning: true),
                if (items!.isEmpty)
                  const EmptyState('Belum Ada Snapshot',
                      'Snapshot pertama dibuat otomatis saat berpindah RT atau saat Anda menekan Buat Baru.',
                      icon: Icons.photo_camera_back_outlined),
                for (var i = 0; i < items!.length; i++)
                  _SnapshotCard(
                      info: items![i],
                      terbaru: i == 0,
                      busy: busy,
                      onLihat: () => _buka(SnapshotIsiScreen(
                          session: widget.session, info: items![i])),
                      onBanding: () => _buka(SnapshotBandingScreen(
                          session: widget.session, info: items![i])),
                      onPulihkan: () => _pulihkan(items![i]),
                      onBagikan: () => _bagikan(items![i])),
              ])));
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard(
      {required this.info,
      required this.terbaru,
      required this.busy,
      required this.onLihat,
      required this.onBanding,
      required this.onPulihkan,
      required this.onBagikan});
  final SnapshotInfo info;
  final bool terbaru, busy;
  final VoidCallback onLihat, onBanding, onPulihkan, onBagikan;

  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(waktuTampil(timestamp(info.dibuat)),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16))),
              if (terbaru)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: forest.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Terbaru',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: forest))),
              IconButton(
                  tooltip: 'Bagikan snapshot',
                  onPressed: busy ? null : onBagikan,
                  icon: const Icon(Icons.share_outlined, size: 20)),
            ]),
            const SizedBox(height: 4),
            Text(
                '${info.jumlah} warga · ${info.tanpaNik} tanpa NIK · ${ukuranTampil(info.ukuran)}',
                style: TextStyle(color: Colors.grey.shade800)),
            if (info.eventTerakhir > 0)
              Text(
                  'Jurnal sampai catatan ke-${info.eventTerakhir}${info.waktuEvent.isEmpty ? '' : ', ${waktuTampil(info.waktuEvent)}'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Wrap(spacing: 4, children: [
              TextButton(
                  onPressed: busy ? null : onLihat,
                  child: const Text('Lihat Isi')),
              TextButton(
                  onPressed: busy ? null : onBanding,
                  child: const Text('Bandingkan')),
              TextButton(
                  onPressed: busy ? null : onPulihkan,
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade800),
                  child: const Text('Pulihkan')),
            ]),
          ])));
}

/// Read-only browse of the warga rows inside one snapshot, grouped by RT.
class SnapshotIsiScreen extends StatefulWidget {
  const SnapshotIsiScreen(
      {super.key, required this.session, required this.info});
  final Session session;
  final SnapshotInfo info;
  @override
  State<SnapshotIsiScreen> createState() => _SnapshotIsiScreenState();
}

class _SnapshotIsiScreenState extends State<SnapshotIsiScreen> {
  List<RecordMap>? rows;
  String? gagal;

  @override
  void initState() {
    super.initState();
    widget.session.store.wargaSnapshot(widget.info.file).then((r) {
      if (mounted) setState(() => rows = r);
    }, onError: (e) {
      if (mounted) setState(() => gagal = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (rows != null) {
      RtRw? grup;
      for (final row in rows!) {
        final pair = RtRw(intValue(row['rw']), intValue(row['rt']));
        if (pair != grup) {
          grup = pair;
          children.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
              child: Text(pair.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: forest))));
        }
        children.add(ResidentCard(row));
      }
    }
    return AppPage(
        session: widget.session,
        title: 'Isi Snapshot',
        subtitle: waktuTampil(timestamp(widget.info.dibuat)),
        child: rows == null && gagal == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (gagal != null)
                  const Notice('Snapshot tidak dapat dibaca.', error: true)
                else if (rows!.isEmpty)
                  const EmptyState('Snapshot Kosong',
                      'Tidak ada data warga tersimpan pada waktu tersebut.')
                else
                  const Notice(
                      'Tampilan baca saja. Untuk mengembalikan keadaan ini, pakai Pulihkan pada daftar snapshot.'),
                ...children,
              ]));
  }
}

/// What changed between the snapshot and the live database.
class SnapshotBandingScreen extends StatefulWidget {
  const SnapshotBandingScreen(
      {super.key, required this.session, required this.info});
  final Session session;
  final SnapshotInfo info;
  @override
  State<SnapshotBandingScreen> createState() => _SnapshotBandingScreenState();
}

class _SnapshotBandingScreenState extends State<SnapshotBandingScreen> {
  PerbandinganSnapshot? hasil;
  String? gagal;

  @override
  void initState() {
    super.initState();
    widget.session.store.bandingkanSnapshot(widget.info.file).then((r) {
      if (mounted) setState(() => hasil = r);
    }, onError: (e) {
      if (mounted) setState(() => gagal = '$e');
    });
  }

  Widget _judul(String text, int n) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Text('$text ($n)',
          style: const TextStyle(fontWeight: FontWeight.w800, color: forest)));

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Bandingkan Snapshot',
      subtitle: waktuTampil(timestamp(widget.info.dibuat)),
      child: hasil == null && gagal == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (gagal != null)
                const Notice('Snapshot tidak dapat dibaca.', error: true)
              else if (hasil!.kosong)
                const EmptyState('Tidak Ada Perbedaan',
                    'Kondisi data saat ini identik dengan snapshot ini.',
                    icon: Icons.check_circle_outline)
              else ...[
                const Notice(
                    'Perubahan sejak snapshot diambil. Memulihkan snapshot akan membalik semua perubahan di bawah ini.'),
                if (hasil!.ditambah.isNotEmpty) ...[
                  _judul('Ditambah sejak snapshot', hasil!.ditambah.length),
                  for (final r in hasil!.ditambah)
                    ResidentCard(r, label: 'Baru'),
                ],
                if (hasil!.dihapus.isNotEmpty) ...[
                  _judul('Dihapus sejak snapshot', hasil!.dihapus.length),
                  for (final r in hasil!.dihapus)
                    ResidentCard(r, label: 'Dihapus · Ada di Snapshot'),
                ],
                if (hasil!.berubah.isNotEmpty) ...[
                  _judul('Berubah', hasil!.berubah.length),
                  for (final (lama, kini, beda) in hasil!.berubah) ...[
                    ResidentCard(kini,
                        label:
                            'Sekarang · Berubah: ${beda.map(namaKolomTampil).join(', ')}'),
                    ResidentCard(lama, label: 'Di Snapshot'),
                    const SizedBox(height: 6),
                  ],
                ],
              ],
            ]));
}

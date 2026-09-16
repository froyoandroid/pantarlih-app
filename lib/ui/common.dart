import 'dart:io';

import 'package:flutter/material.dart';
import '../core/format.dart';
import '../data/storage.dart';
import '../data/store.dart';
import '../data/spreadsheets.dart';
import '../data/wilayah.dart';
import 'lokasi_screen.dart';

const forest = Color(0xFF194B3C);
const canvas = Color(0xFFF5F5EF);
const amber = Color(0xFF95641A);

class Session extends ChangeNotifier {
  Session(this.store, {this.usingPublic = true, WilayahRepo? wilayah})
      : wilayah = wilayah ?? WilayahRepo.unavailable();
  AppStore store;
  bool usingPublic;
  WilayahRepo wilayah;
  int rt = 0, rw = 0;
  String village = '';
  String? kodeWilayah;
  Lokasi? lokasi;
  List<RtRw> workspace = [];
  String get label =>
      'RT ${rt.toString().padLeft(2, '0')} / RW ${rw.toString().padLeft(2, '0')}';
  String get lokasiLabel {
    if (kodeWilayah == null || kodeWilayah!.isEmpty) {
      return 'Lokasi belum diatur';
    }
    if (village.isEmpty) return 'Lokasi belum diatur';
    if (rt <= 0 || rw <= 0) return village;
    return '$village · $label';
  }

  Map<int, List<RtRw>> get workspaceByRw {
    final grouped = <int, List<RtRw>>{};
    for (final item in [...workspace]..sort()) {
      grouped.putIfAbsent(item.rw, () => []).add(item);
    }
    return grouped;
  }

  /// Read-only state refresh. Safe from anywhere: startup, after saving a
  /// lokasi, after a folder move, after a rebuild.
  Future<void> load() async {
    final values = await store.settings();
    rt = intValue(values['rt_aktif']);
    rw = intValue(values['rw_aktif']);
    kodeWilayah = nullableText(values['kode_wilayah_aktif'] ?? '');
    lokasi = await store.activeLokasi();
    village = values['desa_default'] ?? '';
    // lokasi.nama_desa is the fallback label source: a rebuilt database no
    // longer seeds desa_default from a lokasi event, and no typed name may
    // exist yet.
    if (village.isEmpty && lokasi != null) village = lokasi!.namaDesa;
    workspace = RtRw.decode(values['ruang_kerja'] ?? '');
    notifyListeners();
  }

  /// Reconstructs a lost workspace and persists it. This writes a setelan
  /// row through the journal, so it belongs to startup only - load() stays
  /// read-only for every other caller.
  Future<void> pastikanWorkspace() async {
    await load();
    var persist = false;
    if (workspace.isEmpty && rt > 0 && rw > 0) {
      final known = await store.rtListReferensi(rw);
      workspace = [
        for (final n in {...known, rt}) RtRw(rw, n)
      ]..sort();
      persist = true;
    } else if (rt > 0 && rw > 0 && !workspace.contains(RtRw(rw, rt))) {
      workspace = [...workspace, RtRw(rw, rt)]..sort();
      persist = true;
    }
    if (persist) {
      await store.setSession(rt, rw, ruangKerja: RtRw.encode(workspace));
      notifyListeners();
    }
  }

  Future<void> saveLokasi(Lokasi next) async {
    await store.setLokasi(next.toRow());
    await load();
    await selaraskanFolderDesa();
  }

  Future<void> selaraskanFolderDesa() async {
    final nama = (lokasi?.namaDesa ?? village).trim();
    if (nama.isEmpty) return;
    final ingin = namaFolderDesa(nama, kodeWilayah: lokasi?.kode);
    if (basenameDir(store.root) == ingin) {
      await tulisFolderAktif(store.root.parent, ingin);
      return;
    }
    final next = Directory('${store.root.parent.path}/$ingin');
    await store.recordStorageMove(store.root.path, next.path);
    final lama = store.root;
    await store.close();
    await relocateDataRoot(lama, next);
    store = AppStore(next);
    await store.open();
    await tulisFolderAktif(next.parent, ingin);
    await load();
  }

  Future<void> _remember(int newRt, int newRw) async {
    rt = newRt;
    rw = newRw;
    await store.setSession(rt, rw, ruangKerja: RtRw.encode(workspace));
    notifyListeners();
  }

  Future<void> focusRt(RtRw pair) async {
    if (rt == pair.rt && rw == pair.rw) return;
    // ponytail: unconditional snapshot + auto-export on every switch; a
    // dirty-since-last-snapshot check needs change tracking we don't have.
    await store.snapshot();
    await ExportService(store).generate(rw: rw, rt: rt, automatic: true);
    if (!workspace.contains(pair)) {
      workspace = [...workspace, pair]..sort();
    }
    await _remember(pair.rt, pair.rw);
  }

  Future<void> addRtRw(int newRt, int newRw) async {
    final pair = RtRw(newRw, newRt);
    if (!workspace.contains(pair)) {
      workspace = [...workspace, pair]..sort();
    }
    await _remember(newRt, newRw);
  }

  Future<void> removeRtRw(RtRw pair) async {
    if (workspace.length <= 1) {
      throw AppException('Wilayah kerja perlu minimal satu RT.');
    }
    workspace = [
      for (final item in workspace)
        if (item != pair) item
    ];
    var nextRt = rt;
    var nextRw = rw;
    if (rt == pair.rt && rw == pair.rw) {
      nextRt = workspace.first.rt;
      nextRw = workspace.first.rw;
    }
    await _remember(nextRt, nextRw);
  }

  Future<void> setVillage(String value) async {
    await store.setDesa(value);
    final bersih = value.trim();
    // For a manual lokasi the typed name IS the desa record: keep the row in
    // sync. The kode stays stable - warga rows reference it, and renaming
    // must not orphan kode_wilayah values already on disk.
    final loc = lokasi;
    if (loc != null && loc.manual && loc.namaDesa.trim() != bersih) {
      await store.setLokasi({...loc.toRow(), 'nama_desa': bersih});
      await load();
      return;
    }
    village = (await store.settings())['desa_default'] ?? '';
    notifyListeners();
  }

  Future<bool> adoptPublicRoot(ResolvedStorage resolved) async {
    if (!resolved.usingPublic) return false;
    if (store.root.path == resolved.root.path) {
      usingPublic = true;
      notifyListeners();
      return true;
    }
    await store.recordStorageMove(store.root.path, resolved.root.path);
    await store.close();
    await relocateDataRoot(store.root, resolved.root);
    store = AppStore(resolved.root);
    await store.open();
    usingPublic = true;
    await tulisFolderAktif(resolved.root.parent, basenameDir(resolved.root));
    await load();
    return true;
  }
}

class AppPage extends StatelessWidget {
  const AppPage(
      {super.key,
      required this.session,
      required this.title,
      required this.child,
      this.bottom,
      this.actions,
      this.storageBanner = false});
  final Session session;
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;

  /// The red internal-storage banner eats vertical space on small screens,
  /// so it renders only where storage decisions happen (Beranda and Admin).
  final bool storageBanner;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
            appBar: AppBar(
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      InkWell(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      LokasiScreen(session: session))),
                          child: Container(
                              constraints: const BoxConstraints(minHeight: 44),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.place_outlined, size: 12),
                                    const SizedBox(width: 3),
                                    Text(session.lokasiLabel,
                                        style: const TextStyle(
                                            fontSize: 11, letterSpacing: .6)),
                                  ]))),
                    ]),
                actions: actions),
            body: SafeArea(
                child: Column(children: [
              if (storageBanner && !session.usingPublic)
                _PrivateStorageBanner(session: session),
              Expanded(
                  child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 840),
                          child: child))),
            ])),
            bottomNavigationBar: bottom == null
                ? null
                : SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(16), child: bottom)),
          ));
}

class _PrivateStorageBanner extends StatelessWidget {
  const _PrivateStorageBanner({required this.session});
  final Session session;
  @override
  Widget build(BuildContext context) {
    return Material(
        color: const Color(0xFF8B1E1E),
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(children: [
              const Text(
                  'Cadangan tidak tersimpan ke Documents atau Dokumen. Ekspor manual dan bagikan berkas secara berkala.',
                  style: TextStyle(color: Colors.white, height: 1.35)),
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () async {
                        try {
                          final resolved = await resolveDataRoot();
                          final moved = await session.adoptPublicRoot(resolved);
                          if (!moved && context.mounted) {
                            feedback(context,
                                'Izin berkas masih ditolak. Aplikasi tetap memakai folder internal.');
                          }
                        } catch (e) {
                          if (context.mounted) {
                            feedback(context, e, error: true);
                          }
                        }
                      },
                      child: const Text('Coba minta izin lagi',
                          style: TextStyle(color: Colors.white))))
            ])));
  }
}

class Notice extends StatelessWidget {
  const Notice(this.text,
      {super.key,
      this.warning = false,
      this.error = false,
      this.icon,
      this.actions});
  final String text;
  final bool warning, error;
  final IconData? icon;
  final Widget? actions;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? Colors.red.shade800
        : warning
            ? amber
            : forest;
    return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
              icon ??
                  (warning || error
                      ? Icons.info_outline
                      : Icons.check_circle_outline),
              size: 20,
              color: color),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(text, style: TextStyle(color: color, height: 1.45)),
                if (actions != null) actions!,
              ])),
        ]));
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.detail,
      {super.key, this.icon = Icons.inbox_outlined});
  final String title, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: forest.withValues(alpha: .5), size: 44),
        const SizedBox(height: 16),
        Text(title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, height: 1.5)),
      ]));
}

void feedback(BuildContext context, Object message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$message'),
      backgroundColor: error ? Colors.red.shade800 : forest,
      duration: Duration(seconds: error ? 7 : 3)));
}

Future<bool> confirm(BuildContext context, String title, String message,
        {String action = 'Lanjutkan', bool dangerous = false}) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(child: Text(message)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal')),
                  FilledButton(
                      style: dangerous
                          ? FilledButton.styleFrom(
                              backgroundColor: Colors.red.shade800)
                          : null,
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(action)),
                ])) ??
    false;

class ResidentCard extends StatelessWidget {
  const ResidentCard(this.row,
      {super.key,
      this.score,
      this.onTap,
      this.label,
      this.trailing,
      this.highlight = false});
  final RecordMap row;
  final double? score;
  final VoidCallback? onTap;
  final String? label;
  final Widget? trailing;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final nik = teks(row['nik']);
    final tgl = teks(row['tgl_lahir_raw']).isEmpty
        ? tanggalTampil(row['tgl_lahir'])
        : teks(row['tgl_lahir_raw']);
    return Card(
        color: highlight ? const Color(0xFFFFF4D6) : null,
        child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        if (label != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(label!,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: amber))),
                        Text('${row['nama']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 6),
                        Text('$tgl · ${jkTampil(row['jenis_kelamin'])}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        Text(
                            'RT ${row['rt']} / RW ${row['rw']}'
                            '${row['urut_asli'] == null ? '' : ' · No. ${row['urut_asli']}'}'
                            '${nik.isEmpty ? '' : ' · $nik'}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700)),
                        if (row['dibuat_pada'] != null)
                          Text(waktuTampil(row['dibuat_pada']),
                              style: const TextStyle(fontSize: 11)),
                      ])),
                  if (score != null)
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: (score! < 60 ? amber : forest)
                                .withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${score!.round()}%',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: score! < 60 ? amber : forest))),
                  if (trailing != null) trailing!,
                ]))));
  }
}

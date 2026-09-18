import 'dart:io';

import 'package:flutter/material.dart';
import '../core/app_info.dart';
import '../core/format.dart';
import '../data/exchange.dart';
import '../data/storage.dart';
import '../data/store.dart';
import '../data/spreadsheets.dart';
import '../data/wilayah.dart';

const forest = Color(0xFF194B3C);
const canvas = Color(0xFFF5F5EF);
const amber = Color(0xFF95641A);

class Session extends ChangeNotifier {
  Session(this.store, {WilayahRepo? wilayah, this.pertukaranInduk})
      : wilayah = wilayah ?? WilayahRepo.unavailable();
  AppStore store;
  WilayahRepo wilayah;

  /// Overrides the public Documents parent of the exchange folder. Tests and
  /// desktop pass a temp dir, Android leaves it null and asks the platform.
  final Directory? pertukaranInduk;

  /// Why the last automatic cadangan could not be written, or null when the
  /// last RT switch mirrored fine (or had no permission yet, which is not
  /// an error). Beranda shows it so a silent backup failure never hides.
  String? peringatanCadangan;
  int rt = 0, rw = 0;
  String village = '';
  String? kodeWilayah;
  Lokasi? lokasi;
  List<RtRw> workspace = [];
  String get label => formatRtRw(rt, rw);
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
  /// lokasi, after a rebuild.
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
  }

  /// Public exchange folder for this desa. [minta] true prompts for the
  /// storage permission (export, import), false never prompts and yields
  /// null while the permission is missing (automatic backups).
  Future<ExchangeFolder?> folderPertukaran({required bool minta}) =>
      bukaFolderPertukaran(
          desa: (lokasi?.namaDesa ?? village).trim(),
          kodeWilayah: lokasi?.kode,
          minta: minta,
          induk: pertukaranInduk);

  /// Label of the exchange folder for the UI, without touching storage.
  String get labelFolderPertukaran =>
      'Documents/${namaFolderDesa((lokasi?.namaDesa ?? village).trim(), kodeWilayah: lokasi?.kode)}';

  Future<void> _remember(int newRt, int newRw) async {
    rt = newRt;
    rw = newRw;
    await store.setSession(rt, rw, ruangKerja: RtRw.encode(workspace));
    notifyListeners();
  }

  Future<void> focusRt(RtRw pair) async {
    if (rt == pair.rt && rw == pair.rw) return;
    // Every switch snapshots privately, then mirrors it as a cadangan bundle
    // plus automatic Excel into the public folder, but only when the storage
    // permission is already granted: a switch must never open a dialog.
    final snap = await store.snapshot();
    try {
      final folder = await folderPertukaran(minta: false);
      if (folder != null) {
        await tulisCadangan(store, snap, folder.cadangan);
        await ExportService(store).generate(
            tujuan: folder.eksporOtomatis, rw: rw, rt: rt, automatic: true);
      }
      peringatanCadangan = null;
    } catch (e) {
      // The private snapshot already exists, so the switch must go on. A
      // public folder that cannot be written is reported, not fatal.
      peringatanCadangan =
          'Cadangan otomatis ke folder publik gagal ditulis. Snapshot di dalam aplikasi tetap tersimpan. Buka Ekspor & pemulihan untuk mencoba lagi.';
    }
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

  /// Releasing the last RT is allowed: a fresh install also starts with an
  /// empty workspace, and Beranda already explains how to add one.
  Future<void> removeRtRw(RtRw pair) async {
    workspace = [
      for (final item in workspace)
        if (item != pair) item
    ];
    var nextRt = rt;
    var nextRw = rw;
    if (rt == pair.rt && rw == pair.rw) {
      nextRt = workspace.isEmpty ? 0 : workspace.first.rt;
      nextRw = workspace.isEmpty ? 0 : workspace.first.rw;
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
}

class AppPage extends StatelessWidget {
  const AppPage(
      {super.key,
      required this.session,
      required this.title,
      required this.child,
      this.bottom,
      this.actions,
      this.subtitle,
      this.showVersion = false});
  final Session session;
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;

  /// Small secondary line rendered directly under the title, e.g. the
  /// long-form date on Beranda.
  final String? subtitle;

  /// Opt-in version chip in the app bar. Only Beranda shows it.
  final bool showVersion;
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
                      if (subtitle != null)
                        Text(subtitle!,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600)),
                    ]),
                actions: [
                  if (actions != null) ...actions!,
                  if (showVersion)
                    Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Center(
                            child: Text('v$appVersion',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w600)))),
                ]),
            body: SafeArea(
                child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 840),
                        child: child))),
            bottomNavigationBar: bottom == null
                ? null
                : SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(16), child: bottom)),
          ));
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
      this.kelengkapan,
      this.onTap,
      this.label,
      this.labelColor,
      this.trailing,
      this.highlight = false});
  final RecordMap row;
  final double? kelengkapan;
  final VoidCallback? onTap;
  final String? label;
  final Color? labelColor;
  final Widget? trailing;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final nik = teks(row['nik']);
    // Always render the parsed date so referensi and warga rows look the
    // same side by side; the raw spreadsheet value stays a tooltip.
    final tgl = tanggalTampil(row['tgl_lahir']);
    final tglRaw = teks(row['tgl_lahir_raw']);
    final barisTgl = Text('$tgl · ${jkTampil(row['jenis_kelamin'])}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700));
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
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: labelColor ??
                                          Colors.blueGrey.shade700))),
                        Text('${row['nama']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 6),
                        (tglRaw.isEmpty || tglRaw == tgl)
                            ? barisTgl
                            : Tooltip(message: tglRaw, child: barisTgl),
                        const SizedBox(height: 4),
                        Text(
                            formatRtRw(row['rt'], row['rw']) +
                                (row['urut_asli'] == null
                                    ? ''
                                    : ' · No. ${row['urut_asli']}') +
                                (nik.isEmpty ? '' : ' · $nik'),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700)),
                        if (row['dibuat_pada'] != null)
                          Text(waktuTampil(row['dibuat_pada']),
                              style: const TextStyle(fontSize: 11)),
                      ])),
                  if (kelengkapan != null)
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color:
                                (kelengkapan! < 60 ? Colors.deepOrange : forest)
                                    .withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(10)),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${kelengkapan!.round()}%',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: kelengkapan! < 60
                                      ? Colors.deepOrange
                                      : forest)),
                          const Text('Terisi',
                              style: TextStyle(
                                  fontSize: 9, fontWeight: FontWeight.w700)),
                        ])),
                  if (trailing != null) trailing!,
                ]))));
  }
}

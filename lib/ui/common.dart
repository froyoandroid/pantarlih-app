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
  String source = 'LAPANGAN';
  String village = '';
  String? kodeWilayah;
  Lokasi? lokasi;
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

  Future<void> load() async {
    final values = await store.settings();
    rt = intValue(values['rt_aktif']);
    rw = intValue(values['rw_aktif']);
    kodeWilayah = nullableText(values['kode_wilayah_aktif'] ?? '');
    lokasi = await store.activeLokasi();
    village = values['desa_default'] ?? '';
    notifyListeners();
  }

  Future<void> saveLokasi(Lokasi next) async {
    await store.setLokasi(next.toRow());
    await load();
  }

  Future<void> change(int newRt, int newRw) async {
    if (rt != newRt || rw != newRw) {
      await store.snapshot();
      await ExportService(store).generate(rw: rw, rt: rt, automatic: true);
    }
    await store.setSession(newRt, newRw);
    rt = newRt;
    rw = newRw;
    notifyListeners();
  }

  Future<void> setVillage(String value) async {
    await store.setDesa(value);
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
      this.actions});
  final Session session;
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: session,
      builder: (context, _) => Scaffold(
            appBar: AppBar(
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          child: Text(session.lokasiLabel,
                              style: const TextStyle(
                                  fontSize: 11, letterSpacing: .6))),
                    ]),
                actions: actions),
            body: SafeArea(
                child: Column(children: [
              if (!session.usingPublic)
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
                  'Cadangan tidak tersimpan ke Documents. Ekspor manual dan bagikan berkas secara berkala.',
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
      {super.key, this.warning = false, this.error = false, this.icon});
  final String text;
  final bool warning, error;
  final IconData? icon;
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
              child: Text(text, style: TextStyle(color: color, height: 1.45))),
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
  Widget build(BuildContext context) => Card(
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
                      Text(
                          '${row['tgl_lahir_raw'] ?? tanggalTampil(row['tgl_lahir'])} · ${jkTampil(row['jenis_kelamin'])}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text(
                          'RT ${row['rt']} / RW ${row['rw']}'
                          '${row['urut_asli'] == null ? '' : ' · No. ${row['urut_asli']}'}'
                          '${row['nik'] == null || '${row['nik']}'.isEmpty ? '' : ' · ${row['nik']}'}',
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

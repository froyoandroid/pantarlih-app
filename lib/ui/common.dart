import 'package:flutter/material.dart';
import '../core/format.dart';
import '../data/store.dart';
import '../data/spreadsheets.dart';

const forest = Color(0xFF194B3C);
const canvas = Color(0xFFF5F5EF);
const amber = Color(0xFF95641A);

class Session extends ChangeNotifier {
  Session(this.store);
  final AppStore store;
  int rt = 3, rw = 3;
  String source = 'LAPANGAN';
  String village = 'KALITORONG';
  String get label =>
      'RT ${rt.toString().padLeft(2, '0')} / RW ${rw.toString().padLeft(2, '0')}';
  Future<void> load() async {
    final values = await store.settings();
    rt = intValue(values['rt_aktif'], 3);
    rw = intValue(values['rw_aktif'], 3);
    village = values['desa_default']!;
    notifyListeners();
  }

  Future<void> change(int newRt, int newRw) async {
    if (rt != newRt || rw != newRw) {
      await store.snapshot();
      await ExportService(store).generate(rw: rw, automatic: true);
    }
    await store.setSession(newRt, newRw);
    rt = newRt;
    rw = newRw;
    notifyListeners();
  }

  Future<void> setVillage(String value) async {
    await store.setDesa(value);
    village = (await store.settings())['desa_default']!;
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
      this.actions});
  final Session session;
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              Text('${session.village} · ${session.label}',
                  style: const TextStyle(fontSize: 11, letterSpacing: .6)),
            ]),
            actions: actions),
        body: SafeArea(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: child))),
        bottomNavigationBar: bottom == null
            ? null
            : SafeArea(
                child:
                    Padding(padding: const EdgeInsets.all(16), child: bottom)),
      );
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

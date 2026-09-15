import 'package:flutter/material.dart';
import '../core/format.dart';
import 'common.dart';
import 'survey_form.dart';

class RemainingScreen extends StatefulWidget {
  const RemainingScreen({super.key, required this.session});
  final Session session;
  @override
  State<RemainingScreen> createState() => _RemainingScreenState();
}

class _RemainingScreenState extends State<RemainingScreen> {
  List<RecordMap>? rows;
  RecordMap? progress;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final s = widget.session;
      final loaded = await s.store.remaining(s.rt, s.rw);
      final p = await s.store.progress(s.rt, s.rw);
      if (mounted) {
        setState(() {
          rows = loaded;
          progress = p;
        });
      }
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Daftar sisa',
      child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                        '${progress?['surveyed']} / ${progress?['total']} tersurvei · sisa ${progress?['remaining']}',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700))),
                const Notice(
                    'Abu-abu adalah tanda manual Anda: tidak perlu dikejar. Bukan keputusan kelayakan dari aplikasi.',
                    icon: Icons.touch_app_outlined),
                if (rows!.isEmpty)
                  const EmptyState('Tidak ada sisa',
                      'Semua data lama di RT ini telah ditautkan, atau data belum diimpor.'),
                for (final row in rows!)
                  ResidentCard(row,
                      grey: row['abu_abu'] == 1,
                      label: row['survey_id'] == null
                          ? null
                          : 'SUDAH TERCATAT DI RT ${row['rt_baru']} / RW ${row['rw_baru']}',
                      onTap: row['survey_id'] != null
                          ? null
                          : () async {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => SurveyForm(
                                          session: widget.session,
                                          legacy: row)));
                              await load();
                            },
                      trailing: row['survey_id'] != null
                          ? const Icon(Icons.link, color: amber)
                          : IconButton(
                              tooltip: row['abu_abu'] == 1
                                  ? 'Hapus tanda abu-abu'
                                  : 'Tandai abu-abu',
                              icon: Icon(row['abu_abu'] == 1
                                  ? Icons.visibility_off
                                  : Icons.visibility_outlined),
                              onPressed: () async {
                                try {
                                  await widget.session.store.mark(
                                      row['id'] as int, row['abu_abu'] != 1);
                                  await load();
                                } catch (e) {
                                  if (context.mounted) {
                                    feedback(context, e, error: true);
                                  }
                                }
                              })),
              ])));
}

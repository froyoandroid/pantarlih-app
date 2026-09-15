import 'package:flutter/material.dart';
import '../core/format.dart';
import 'common.dart';
import 'survey_form.dart';

enum SurveyListKind { history, conflicts, duplicates }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen(
      {super.key, required this.session, this.kind = SurveyListKind.history});
  final Session session;
  final SurveyListKind kind;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<RecordMap>? rows;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final store = widget.session.store;
      final loaded = await switch (widget.kind) {
        SurveyListKind.history => store.history(),
        SurveyListKind.conflicts => store.conflicts(),
        SurveyListKind.duplicates => store.duplicateRows()
      };
      if (mounted) setState(() => rows = loaded);
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: switch (widget.kind) {
        SurveyListKind.history => 'Riwayat · 20 terakhir',
        SurveyListKind.conflicts => 'Konflik RT / RW',
        SurveyListKind.duplicates => 'Duplikat NIK'
      },
      child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.kind == SurveyListKind.conflicts)
                  const Notice(
                      'Ekspor mengikuti RT/RW baru. Konflik tidak pernah mengubah keterangan.',
                      warning: true),
                if (widget.kind == SurveyListKind.duplicates)
                  const Notice(
                      'Semua baris dengan NIK berulang. Buka baris untuk memeriksa dan mengoreksi sesuai KK.',
                      warning: true),
                if (rows!.isEmpty)
                  const EmptyState('Belum ada baris',
                      'Data yang sesuai akan ditampilkan di sini.'),
                for (final row in rows!)
                  ResidentCard(row,
                      label: widget.kind == SurveyListKind.conflicts
                          ? 'LAMA RT ${row['rt_lama']}/RW ${row['rw_lama']} → BARU RT ${row['rt_baru']}/RW ${row['rw_baru']}'
                          : widget.kind == SurveyListKind.duplicates
                              ? 'NIK ${row['nik']}'
                              : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                    final survey =
                        await widget.session.store.survey(row['id'] as int);
                    if (!context.mounted || survey == null) return;
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SurveyForm(
                                session: widget.session, survey: survey)));
                    await load();
                  }),
              ])));
}

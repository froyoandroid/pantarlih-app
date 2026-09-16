import 'package:flutter/material.dart';
import '../core/format.dart';
import 'common.dart';
import 'survey_form.dart';

enum SurveyListKind { history, duplicates }

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
      final loaded = widget.kind == SurveyListKind.history
          ? await store.history()
          : await store.duplicateRows();
      if (mounted) setState(() => rows = loaded);
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: widget.kind == SurveyListKind.history
          ? 'Riwayat · 20 terakhir'
          : 'Duplikat NIK',
      child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.kind == SurveyListKind.duplicates)
                  const Notice(
                      'Semua baris dengan NIK berulang. Buka baris untuk memeriksa dan mengoreksi sesuai KK.',
                      warning: true),
                if (rows!.isEmpty)
                  const EmptyState('Belum ada baris',
                      'Data yang sesuai akan ditampilkan di sini.'),
                for (final row in rows!)
                  ResidentCard(row,
                      label: widget.kind == SurveyListKind.duplicates
                          ? 'NIK ${row['nik']}'
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                    final warga =
                        await widget.session.store.warga(row['id'] as int);
                    if (!context.mounted || warga == null) return;
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => SurveyForm(
                                session: widget.session, warga: warga)));
                    await load();
                  }),
              ])));
}

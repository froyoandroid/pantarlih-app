import 'package:flutter/material.dart';
import '../core/format.dart';
import 'common.dart';
import 'survey_form.dart';

enum SurveyListKind { history, duplicates, duplicateNames }

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
      final loaded = switch (widget.kind) {
        SurveyListKind.history => await store.history(),
        SurveyListKind.duplicates => await store.duplicateRows(),
        SurveyListKind.duplicateNames => await store.duplicateNameRows(),
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
        SurveyListKind.duplicates => 'Duplikat NIK',
        SurveyListKind.duplicateNames => 'Duplikat nama',
      },
      child: rows == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (widget.kind == SurveyListKind.duplicates)
                  const Notice(
                      'Daftar warga dengan NIK yang sama. Ketuk warga untuk memeriksa dan mencocokkan dengan dokumen kependudukan.',
                      warning: true),
                if (widget.kind == SurveyListKind.duplicateNames)
                  const Notice(
                      'Daftar warga dengan nama serupa di RT yang sama, termasuk yang belum memiliki NIK. Ketuk warga untuk memeriksa ketepatan data.',
                      warning: true),
                if (rows!.isEmpty)
                  EmptyState(
                      switch (widget.kind) {
                        SurveyListKind.history => 'Belum ada riwayat',
                        SurveyListKind.duplicates => 'Tidak ada duplikat NIK',
                        SurveyListKind.duplicateNames =>
                          'Tidak ada duplikat nama',
                      },
                      switch (widget.kind) {
                        SurveyListKind.history =>
                          'Riwayat perubahan data warga akan ditampilkan di sini.',
                        SurveyListKind.duplicates =>
                          'Semua NIK warga tercatat unik atau belum diisi.',
                        SurveyListKind.duplicateNames =>
                          'Tidak ditemukan nama serupa pada RT yang sama.',
                      }),
                for (final row in rows!)
                  ResidentCard(row,
                      label: widget.kind == SurveyListKind.duplicates
                          ? 'NIK ${row['nik']}'
                          : widget.kind == SurveyListKind.duplicateNames
                              ? '${formatRt(row['rt'])} · ${row['nama']}'
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

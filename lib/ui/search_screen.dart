import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/nama.dart';
import '../core/nik.dart';
import 'common.dart';
import 'survey_form.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen(
      {super.key,
      required this.session,
      this.pickOnly = false,
      this.currentSurveyId});
  final Session session;
  final bool pickOnly;
  final int? currentSurveyId;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  final focus = FocusNode();
  List<RecordMap> residents = [];
  bool byDate = false, loading = true;
  String? error;
  Session get session => widget.session;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await session.store.allLegacy(session.rw);
      if (mounted) {
        setState(() {
          residents = rows;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    query.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> _open(RecordMap? row) async {
    if (widget.pickOnly) {
      Navigator.pop(context, row);
      return;
    }
    if (row?['survey_id'] != null) {
      final survey = await session.store.survey(row!['survey_id'] as int);
      if (!mounted || survey == null) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SurveyForm(session: session, survey: survey)));
    } else {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => SurveyForm(
                  session: session,
                  legacy: row,
                  initialName: row == null && !byDate ? query.text : null)));
    }
    if (!mounted) return;
    query.clear();
    await _load();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final q = query.text.trim();
    final active = byDate ? parseTanggal(q) != null : q.length >= 3;
    var candidates = <(RecordMap, double)>[];
    var expanded = false;
    if (active) {
      if (byDate) {
        candidates = residents
            .where((r) => r['tgl_lahir'] == parseTanggal(q))
            .map((r) => (r, 100.0))
            .toList();
        candidates.sort((a, b) => (a.$1['rt'] == session.rt ? 0 : 1)
            .compareTo(b.$1['rt'] == session.rt ? 0 : 1));
      } else {
        var pool = residents.where((r) => r['rt'] == session.rt).toList();
        if (pool.isEmpty) {
          pool = residents;
          expanded = true;
        }
        candidates = pool.map((r) => (r, skorNama(q, '${r['nama']}'))).toList();
        candidates.sort((a, b) {
          final cmp = b.$2.compareTo(a.$2);
          return cmp != 0
              ? cmp
              : intValue(a.$1['id']).compareTo(intValue(b.$1['id']));
        });
        candidates = candidates.take(5).toList();
      }
    }
    return AppPage(
        session: session,
        title: widget.pickOnly ? 'Pilih tautan data lama' : 'Cari & input',
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!widget.pickOnly)
                      SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'LAPANGAN',
                                label: Text('Lapangan'),
                                icon: Icon(Icons.directions_walk)),
                            ButtonSegment(
                                value: 'KERTAS',
                                label: Text('Dari kertas'),
                                icon: Icon(Icons.description_outlined)),
                          ],
                          selected: {
                            session.source
                          },
                          onSelectionChanged: (value) =>
                              setState(() => session.source = value.first)),
                    const SizedBox(height: 16),
                    TextField(
                        controller: query,
                        focusNode: focus,
                        autofocus: true,
                        keyboardType: byDate
                            ? TextInputType.datetime
                            : TextInputType.name,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                            labelText: byDate
                                ? 'Tanggal lahir · DD-MM-YYYY'
                                : 'Cari nama di data lama',
                            prefixIcon: Icon(byDate
                                ? Icons.calendar_today_outlined
                                : Icons.search),
                            suffixIcon: q.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () => setState(query.clear),
                                    icon: const Icon(Icons.close))),
                        onChanged: (_) => setState(() {})),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            onPressed: () => setState(() {
                                  byDate = !byDate;
                                  query.clear();
                                }),
                            icon: Icon(
                                byDate
                                    ? Icons.person_search_outlined
                                    : Icons.event_outlined,
                                size: 18),
                            label: Text(byDate
                                ? 'Cari dengan nama'
                                : 'Nama berbeda? Cari tanggal lahir'))),
                  ])),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                          if (error != null) Notice(error!, error: true),
                          if (!active)
                            EmptyState(
                                byDate
                                    ? 'Cocokkan lewat tanggal lahir'
                                    : 'Mulai dari nama di KK',
                                byDate
                                    ? 'Isi tanggal lengkap. Semua kecocokan ditampilkan, RT aktif lebih dulu.'
                                    : 'Ketik sedikitnya 3 karakter. Nama dapat dicari dari kata mana pun.',
                                icon: Icons.person_search_outlined),
                          if (expanded)
                            const Notice(
                                'RT aktif tidak memiliki data lama. Pencarian diperluas ke seluruh RW aktif.',
                                warning: true),
                          if (active && candidates.isEmpty)
                            const EmptyState('Belum ada kandidat',
                                'Anda tetap dapat membuat data baru.'),
                          for (final candidate in candidates)
                            ResidentCard(candidate.$1,
                                score: byDate ? null : candidate.$2,
                                label: candidate.$1['survey_id'] != null
                                    ? 'SUDAH TERCATAT DI RT ${candidate.$1['rt_baru']} / RW ${candidate.$1['rw_baru']}'
                                    : candidate.$1['rt'] != session.rt
                                        ? 'DITEMUKAN DI RT ${candidate.$1['rt']}'
                                        : null,
                                onTap: widget.pickOnly &&
                                        candidate.$1['survey_id'] != null &&
                                        candidate.$1['survey_id'] !=
                                            widget.currentSurveyId
                                    ? null
                                    : () => _open(candidate.$1)),
                          if (!widget.pickOnly)
                            Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: FilledButton.icon(
                                    onPressed: () => _open(null),
                                    icon: const Icon(Icons.person_add_alt_1),
                                    label: const Text('BUAT BARU'))),
                          if (!widget.pickOnly)
                            const Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                    'Tidak menemukan orang yang sama? Buat baris baru sesuai KK.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.black54))),
                        ])),
        ]));
  }
}

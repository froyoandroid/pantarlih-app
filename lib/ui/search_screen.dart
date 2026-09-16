import 'dart:async';
import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/nama.dart';
import '../core/nik.dart';
import 'common.dart';
import 'survey_form.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen(
      {super.key, required this.session, this.afterId, this.beforeId});
  final Session session;
  final int? afterId;
  final int? beforeId;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final query = TextEditingController();
  final focus = FocusNode();
  List<RecordMap> referensi = [];
  List<RecordMap> warga = [];
  bool byDate = false, loading = true;
  String typed = '';
  String? error;
  Timer? debounce;
  Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final refs = await session.store.allReferensi(session.rw);
      final rows = await session.store.allWarga();
      if (mounted) {
        setState(() {
          referensi = refs;
          warga = rows;
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
    debounce?.cancel();
    query.dispose();
    focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() => typed = value);
    });
  }

  Future<void> _openForm({RecordMap? wargaRow, RecordMap? seed}) async {
    final saved = await Navigator.push<int>(
        context,
        MaterialPageRoute(
            builder: (_) => SurveyForm(
                session: session,
                warga: wargaRow,
                seed: seed,
                afterId: wargaRow == null ? widget.afterId : null,
                beforeId: wargaRow == null ? widget.beforeId : null,
                initialName: wargaRow == null && seed == null && !byDate
                    ? query.text
                    : null)));
    if (!mounted) return;
    if (saved != null && wargaRow == null) {
      Navigator.pop(context, saved);
      return;
    }
    query.clear();
    typed = '';
    await _load();
    focus.requestFocus();
  }

  List<(RecordMap, double)> _score(List<RecordMap> pool, String q) {
    final ranked = pool.map((r) => (r, skorNama(q, '${r['nama']}'))).toList();
    ranked.sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      return cmp != 0
          ? cmp
          : intValue(a.$1['id']).compareTo(intValue(b.$1['id']));
    });
    return ranked;
  }

  @override
  Widget build(BuildContext context) {
    final q = typed.trim();
    final active = byDate ? parseTanggal(q) != null : q.length >= 3;
    var existing = <(RecordMap, double)>[];
    var refs = <(RecordMap, double)>[];
    var expanded = false;
    if (active) {
      if (byDate) {
        final iso = parseTanggal(q);
        refs = referensi
            .where((r) => r['tgl_lahir'] == iso)
            .map((r) => (r, 100.0))
            .toList();
        refs.sort((a, b) => (a.$1['rt'] == session.rt ? 0 : 1)
            .compareTo(b.$1['rt'] == session.rt ? 0 : 1));
      } else {
        existing = _score(
                warga
                    .where(
                        (r) => r['rt'] == session.rt && r['rw'] == session.rw)
                    .toList(),
                q)
            .where((e) => e.$2 >= 30)
            .take(10)
            .toList();
        if (existing.isEmpty) {
          existing =
              _score(warga, q).where((e) => e.$2 >= 30).take(10).toList();
        }
        var pool = referensi.where((r) => r['rt'] == session.rt).toList();
        if (pool.isEmpty) {
          pool = referensi;
          expanded = referensi.isNotEmpty;
        }
        refs = _score(pool, q).take(5).toList();
      }
    }
    return AppPage(
        session: session,
        title: 'Ketik nama',
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                                : 'Cari nama',
                            prefixIcon: Icon(byDate
                                ? Icons.calendar_today_outlined
                                : Icons.search),
                            suffixIcon: q.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      query.clear();
                                      setState(() => typed = '');
                                    },
                                    icon: const Icon(Icons.close))),
                        onChanged: _onChanged),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            onPressed: () => setState(() {
                                  byDate = !byDate;
                                  query.clear();
                                  typed = '';
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
                                'RT aktif tidak memiliki referensi. Pencarian diperluas ke seluruh RW aktif.',
                                warning: true),
                          if (active && existing.isNotEmpty) ...[
                            const Padding(
                                padding: EdgeInsets.only(top: 8, bottom: 4),
                                child: Text('SUDAH DIINPUT',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .6))),
                            for (final candidate in existing)
                              ResidentCard(candidate.$1,
                                  highlight: true,
                                  score: byDate ? null : candidate.$2,
                                  label: candidate.$1['rt'] != session.rt
                                      ? 'SUDAH DIINPUT · RT ${candidate.$1['rt']}'
                                      : 'SUDAH DIINPUT',
                                  onTap: () =>
                                      _openForm(wargaRow: candidate.$1)),
                          ],
                          if (active) ...[
                            const Padding(
                                padding: EdgeInsets.only(top: 12, bottom: 4),
                                child: Text('REFERENSI',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .6))),
                            if (refs.isEmpty)
                              const Text(
                                  'Tidak ada saran referensi. Ketik manual lewat TAMBAH BARU.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                            for (final candidate in refs)
                              ResidentCard(candidate.$1,
                                  score: byDate ? null : candidate.$2,
                                  label: candidate.$1['rt'] != session.rt
                                      ? 'REFERENSI · RT ${candidate.$1['rt']}'
                                      : null,
                                  onTap: () => _openForm(seed: candidate.$1)),
                          ],
                          Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: FilledButton.icon(
                                  onPressed: () => _openForm(),
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('TAMBAH BARU'))),
                          const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                  'Saran hanya mengisi field. Setelah dipilih, warga berdiri sendiri.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black54))),
                        ])),
        ]));
  }
}

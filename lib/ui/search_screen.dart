import 'dart:async';
import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/nama.dart';
import '../core/nik.dart';
import 'common.dart';
import 'survey_form.dart';

/// Precomputed search results for one query, computed outside build() so
/// keyboard pops and snackbars never re-run Levenshtein over every row.
class HasilCari {
  const HasilCari(
      {this.aktif = false,
      this.diperluas = false,
      this.warga = const [],
      this.referensi = const []});
  final bool aktif;
  final bool diperluas;
  final List<(RecordMap, double)> warga;
  final List<(RecordMap, double)> referensi;
}

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
  HasilCari hasil = const HasilCari();
  final cacheSkor = <String, HasilCari>{};
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
        cacheSkor.clear();
        if (query.text.trim().isNotEmpty) _perbaruiSkor(query.text);
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
    // 180 ms: scoring stays out of build and waits for a typing pause.
    debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _perbaruiSkor(value);
    });
  }

  /// Scores outside build, memoized per query and mode. The cache lives
  /// only between data loads; _load() clears it since rows may have changed.
  void _perbaruiSkor(String value) {
    final q = value.trim();
    final kunci = '$byDate|$q';
    final hasilBaru =
        cacheSkor.putIfAbsent(kunci, () => _hitung(q, byDate));
    cacheSkor
      ..remove(kunci)
      ..[kunci] = hasilBaru;
    while (cacheSkor.length > 8) {
      cacheSkor.remove(cacheSkor.keys.first);
    }
    setState(() {
      typed = value;
      hasil = hasilBaru;
    });
  }

  HasilCari _hitung(String q, bool tanggal) {
    if (!tanggal) {
      if (q.length < 3) return const HasilCari();
      var pool = warga
          .where((r) => r['rt'] == session.rt && r['rw'] == session.rw)
          .toList();
      var existing = _rank(pool, q, 10);
      if (existing.isEmpty) existing = _rank(warga, q, 10);
      var refPool = referensi.where((r) => r['rt'] == session.rt).toList();
      final diperluas = refPool.isEmpty && referensi.isNotEmpty;
      if (diperluas) refPool = referensi;
      return HasilCari(
          aktif: true,
          diperluas: diperluas,
          warga: existing,
          referensi: _rank(refPool, q, 5));
    }
    final iso = parseTanggal(q);
    if (iso == null) return const HasilCari();
    final refs = [
      for (final r in referensi)
        if (r['tgl_lahir'] == iso) (r, 100.0),
    ]..sort((a, b) => (a.$1['rt'] == session.rt ? 0 : 1)
        .compareTo(b.$1['rt'] == session.rt ? 0 : 1));
    return HasilCari(aktif: true, referensi: refs);
  }

  List<(RecordMap, double)> _rank(List<RecordMap> pool, String q, int batas) {
    final ranked = pool.map((r) => (r, skorNama(q, '${r['nama']}'))).toList();
    ranked.sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      return cmp != 0
          ? cmp
          : intValue(a.$1['id']).compareTo(intValue(b.$1['id']));
    });
    return ranked.where((e) => e.$2 >= 30).take(batas).toList();
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
    cacheSkor.clear();
    _perbaruiSkor('');
    await _load();
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final q = typed.trim();
    final active = hasil.aktif;
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
                          if (hasil.diperluas)
                            const Notice(
                                'RT aktif tidak memiliki referensi. Pencarian diperluas ke seluruh RW aktif.',
                                warning: true),
                          if (active && hasil.warga.isNotEmpty) ...[
                            const Padding(
                                padding: EdgeInsets.only(top: 8, bottom: 4),
                                child: Text('SUDAH DIINPUT',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .6))),
                            for (final candidate in hasil.warga)
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
                            if (hasil.referensi.isEmpty)
                              const Text(
                                  'Tidak ada saran referensi. Ketik manual lewat TAMBAH BARU.',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.black54)),
                            for (final candidate in hasil.referensi)
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

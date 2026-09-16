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
      this.wargaDiperluas = false,
      this.warga = const [],
      this.referensi = const []});
  final bool aktif;

  /// True when the typed-warga list widened from the active RT to the whole
  /// active RW, so the screen can say so instead of doing it silently.
  final bool wargaDiperluas;
  final List<(RecordMap, double)> warga;

  /// Every match in the active RW, active RT first - never limited to the
  /// active RT, since a person already logged for a neighboring RT should
  /// still surface instead of inviting a duplicate entry.
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
    final hasilBaru = cacheSkor.putIfAbsent(kunci, () => _hitung(q, byDate));
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
      // Typed-warga list: active RT first, widened to the whole active RW
      // only when the RT has no match - and the widening is announced,
      // never silent.
      var pool = warga
          .where((r) => r['rt'] == session.rt && r['rw'] == session.rw)
          .toList();
      var existing = _rank(pool, q, 5);
      var wargaDiperluas = false;
      if (existing.isEmpty && pool.isNotEmpty) {
        pool = warga.where((r) => r['rw'] == session.rw).toList();
        existing = _rank(pool, q, 5);
        wargaDiperluas = existing.isNotEmpty;
      }
      return HasilCari(
          aktif: true,
          wargaDiperluas: wargaDiperluas,
          warga: existing,
          referensi: _rankReferensi(q));
    }
    final iso = parseTanggal(q);
    if (iso == null) return const HasilCari();
    // Birthdate mode also answers the real question: has this person been
    // typed already? Same RT-first, RW-wide scope as the name mode.
    var wargaBaris = [
      for (final r in warga)
        if (teks(r['tgl_lahir']) == iso &&
            r['rt'] == session.rt &&
            r['rw'] == session.rw)
          (r, 100.0),
    ];
    var wargaDiperluas = false;
    if (wargaBaris.isEmpty) {
      final rwBaris = [
        for (final r in warga)
          if (teks(r['tgl_lahir']) == iso && r['rw'] == session.rw) (r, 100.0),
      ];
      if (rwBaris.isNotEmpty) {
        wargaBaris = rwBaris;
        wargaDiperluas = true;
      }
    }
    final refs = [
      for (final r in referensi)
        if (r['tgl_lahir'] == iso) (r, 100.0),
    ]..sort((a, b) => (a.$1['rt'] == session.rt ? 0 : 1)
        .compareTo(b.$1['rt'] == session.rt ? 0 : 1));
    return HasilCari(
        aktif: true,
        wargaDiperluas: wargaDiperluas,
        warga: wargaBaris,
        referensi: refs);
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

  /// Active RT and every other RT get their own top-5 budget instead of
  /// sharing one - a name-rich active RT filling all five slots must never
  /// crowd out an explicit match sitting in a neighboring RT.
  List<(RecordMap, double)> _rankReferensi(String q) {
    final aktif = referensi.where((r) => r['rt'] == session.rt).toList();
    final lain = referensi.where((r) => r['rt'] != session.rt).toList();
    return [..._rank(aktif, q, 5), ..._rank(lain, q, 5)];
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
    // One exit behavior: any save pops and hands the row id back so the
    // caller (Daftar RT) can scroll to it.
    if (saved != null) {
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
                        keyboardType:
                            byDate ? TextInputType.number : TextInputType.name,
                        // Same formatter as the form: digits only, dashes
                        // inserted while typing, so 20122001 reads as
                        // 20-12-2001 without the user hunting for a dash.
                        inputFormatters:
                            byDate ? [TanggalInputFormatter()] : null,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                            labelText: byDate
                                ? 'Tanggal lahir · ketik 8 angka'
                                : 'Cari nama',
                            hintText: byDate ? 'contoh 20122001' : null,
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
                          if (hasil.wargaDiperluas)
                            const Notice(
                                'Tidak ada yang cocok di RT aktif. Daftar warga diperluas ke seluruh RW aktif.',
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
                                      ? 'Referensi di RT ${candidate.$1['rt']}'
                                      : null,
                                  labelColor: candidate.$1['rt'] != session.rt
                                      ? amber
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

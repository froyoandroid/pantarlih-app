import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/keterangan.dart';
import '../data/order.dart';
import 'common.dart';
import 'referensi_screen.dart';
import 'search_screen.dart';
import 'survey_form.dart';
import 'tanda_bukti_screen.dart';

const _warnaKartu = <String, Color>{
  'kuning': Color(0xFFFFF4D6),
  'hijau': Color(0xFFE7F3EE),
  'merah': Color(0xFFF8E4E4),
  'biru': Color(0xFFE4EEF8),
};

const _labelWarna = <String, String>{
  'kuning': 'Kuning',
  'hijau': 'Hijau',
  'merah': 'Merah',
  'biru': 'Biru',
};

const _ambangGeserHapus = .85; // HARDCODED: requires a deliberate long swipe.

class RtListScreen extends StatefulWidget {
  const RtListScreen({super.key, required this.session, this.focusId});
  final Session session;
  final int? focusId;
  @override
  State<RtListScreen> createState() => _RtListScreenState();
}

class _RtListScreenState extends State<RtListScreen> {
  final scroll = ScrollController();
  List<RecordMap> rows = [];
  RecordMap? counts;
  bool loading = true;
  String filter = '';
  String? filterKeterangan;
  int? sorot;

  @override
  void initState() {
    super.initState();
    _load(scrollTo: widget.focusId);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load({int? scrollTo}) async {
    final s = widget.session;
    final loaded = await s.store.wargaRt(s.rw, s.rt);
    final c = await s.store.counts(s.rw, s.rt);
    if (!mounted) return;
    setState(() {
      rows = loaded;
      counts = c;
      loading = false;
    });
    if (scrollTo != null) {
      // Real row heights vary (three-line cards), so ensureVisible targets
      // the row itself instead of index * fixedHeight, then the row is
      // highlighted for a moment so the landing spot is obvious.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = GlobalObjectKey(scrollTo).currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 300), alignment: .25);
        setState(() => sorot = scrollTo);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && sorot == scrollTo) setState(() => sorot = null);
        });
      });
    }
  }

  Future<void> _openKetik({int? afterId, int? beforeId}) async {
    final id = await Navigator.push<int>(
        context,
        MaterialPageRoute(
            builder: (_) => SearchScreen(
                session: widget.session,
                afterId: afterId,
                beforeId: beforeId)));
    if (id != null) {
      await _load(scrollTo: id);
    } else {
      await _load();
    }
  }

  Future<void> _edit(RecordMap row) async {
    final saved = await Navigator.push<int>(
        context,
        MaterialPageRoute(
            builder: (_) => SurveyForm(session: widget.session, warga: row)));
    if (!mounted || saved == null) return;
    await _load();
  }

  Future<void> _opsiKartu(RecordMap row) async {
    final id = row['id'] as int;
    final pilih = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_left),
                  title: const Text('Tambahkan Sebelumnya'),
                  onTap: () => Navigator.pop(ctx, 'sebelum')),
              ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_right),
                  title: const Text('Tambahkan Sesudahnya'),
                  onTap: () => Navigator.pop(ctx, 'sesudah')),
              ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Ubah Warna'),
                  onTap: () => Navigator.pop(ctx, 'warna')),
              ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Hapus Warga'),
                  onTap: () => Navigator.pop(ctx, 'hapus')),
            ])));
    if (!mounted || pilih == null) return;
    if (pilih == 'sebelum') {
      await _openKetik(beforeId: id);
    } else if (pilih == 'sesudah') {
      await _openKetik(afterId: id);
    } else if (pilih == 'warna') {
      await _ubahWarna(row);
    } else if (pilih == 'hapus') {
      if (await _konfirmasiHapus(row)) await _hapus(row);
    }
  }

  Future<bool> _konfirmasiHapus(RecordMap row) => confirm(
      context,
      'Hapus ${row['nama']}?',
      'Warga ini dihapus dari daftar. Jejak lengkap tetap ada di jurnal.',
      action: 'Hapus',
      dangerous: true);

  Future<void> _hapus(RecordMap row) async {
    try {
      await widget.session.store.deleteWarga(row['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  Widget _titikWarna(Color color) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26)));

  Future<void> _ubahWarna(RecordMap row) async {
    final sekarang = teks(row['warna']);
    final pilih = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 4),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Ubah Warna',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)))),
              ListTile(
                  leading: _titikWarna(Colors.white),
                  title: const Text('Tanpa Warna'),
                  selected: sekarang.isEmpty,
                  onTap: () => Navigator.pop(ctx, '')),
              for (final e in _labelWarna.entries)
                ListTile(
                    leading: _titikWarna(_warnaKartu[e.key]!),
                    title: Text(e.value),
                    selected: sekarang == e.key,
                    onTap: () => Navigator.pop(ctx, e.key)),
            ])));
    if (!mounted || pilih == null) return;
    try {
      await widget.session.store.saveWarga({
        'nik': row['nik'],
        'nama': row['nama'],
        'jenis_kelamin': row['jenis_kelamin'],
        'tempat_lahir': row['tempat_lahir'],
        'tgl_lahir': row['tgl_lahir'],
        'desa': row['desa'],
        'kode_wilayah': row['kode_wilayah'],
        'rt': row['rt'],
        'rw': row['rw'],
        'keterangan': row['keterangan'],
        'warna': pilih,
      }, id: row['id'] as int);
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (filter.trim().isNotEmpty || filterKeterangan != null) {
      return; // drag is locked while filtering
    }
    // onReorderItem delivers newIndex already adjusted for the removed row,
    // so convert back to the raw onReorder-style index for the helper.
    final ids = [for (final row in rows) row['id'] as int];
    final neighbors = reorderNeighbors(
        ids, oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex);
    if (oldIndex == newIndex) return;
    final moved = rows[oldIndex];
    final next = [...rows]..removeAt(oldIndex);
    next.insert(newIndex, moved);
    final beforeId = neighbors.beforeId;
    final afterId = neighbors.afterId;
    setState(() => rows = next);
    try {
      await widget.session.store
          .reorderWarga(moved['id'] as int, beforeId, afterId);
      await _load();
    } catch (e) {
      if (mounted) {
        feedback(context, e, error: true);
        await _load();
      }
    }
  }

  Future<void> _promosikanBatch() async {
    final s = widget.session;
    try {
      final sisa = await s.store.referensiBelum(s.rw, s.rt);
      if (!mounted) return;
      if (sisa.isEmpty) {
        feedback(context, 'Semua referensi RT ini sudah diinput');
        return;
      }
      final layak = sisa.where((r) => s.store.alasanPromosi(r).isEmpty).length;
      if (layak == 0) {
        feedback(context,
            'Tidak ada yang memenuhi syarat promosi. Periksa di Belum Diinput.',
            error: true);
        return;
      }
      final setuju = await confirm(context, 'Promosikan Referensi',
          '$layak dari ${sisa.length} baris referensi RT ini memenuhi syarat dan akan disimpan sebagai data warga di akhir daftar.',
          action: 'Promosikan');
      if (!setuju || !mounted) return;
      final hasil = await s.store.promosikanBatch(s.rw, s.rt);
      if (!mounted) return;
      if (hasil.gagal.isEmpty) {
        feedback(context, '${hasil.berhasil} warga ditambahkan dari referensi');
      } else {
        await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text(
                        '${hasil.berhasil} Dipromosikan, ${hasil.gagal.length} Dilewati'),
                    content: SingleChildScrollView(child: Text('Baris berikut dilewati karena datanya belum lengkap:\n${hasil.gagal.map((g) => '• $g').join('\n')}\n\nPeriksa lewat menu Belum Diinput untuk melengkapinya.')),
                    actions: [
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Tutup'))
                    ]));
      }
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  Future<void> _bukaSisa() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SisaReferensiScreen(session: widget.session)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final jumlah = intValue(counts?['jumlah']);
    final tanpa = intValue(counts?['tanpa_nik']);
    // Original position numbers survive filtering: id -> 1-based row number.
    final posisi = {
      for (var i = 0; i < rows.length; i++) rows[i]['id'] as int: i + 1,
    };
    final kunci = filter.trim().toLowerCase();
    final filterAktif = kunci.isNotEmpty || filterKeterangan != null;
    final tampil = filterAktif
        ? rows.where((r) {
            final cocokTeks = kunci.isEmpty ||
                '${r['nama']}'.toLowerCase().contains(kunci) ||
                teks(r['nik']).contains(kunci);
            final cocokKeterangan = filterKeterangan == null ||
                chipKeterangan(teks(r['keterangan'])) == filterKeterangan;
            return cocokTeks && cocokKeterangan;
          }).toList()
        : rows;
    return AppPage(
        session: widget.session,
        title: 'Daftar Warga',
        subtitle: widget.session.label,
        actions: [
          TextButton(
              onPressed: () => _openKetik(), child: const Text('Tambah')),
          PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'sisa') _bukaSisa();
                if (value == 'promosi') _promosikanBatch();
                if (value == 'tanda_bukti') {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              TandaBuktiScreen(session: widget.session)));
                }
              },
              itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'sisa', child: Text('Belum Diinput')),
                    PopupMenuItem(
                        value: 'promosi', child: Text('Promosikan Referensi')),
                    PopupMenuItem(
                        value: 'tanda_bukti', child: Text('Tanda Bukti')),
                  ]),
        ],
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: rows.isEmpty
                    ? ListView(children: const [
                        EmptyState('Belum Ada Warga di RT Ini',
                            'Tekan Tambah Warga untuk mulai mencatat warga pertama.',
                            icon: Icons.person_add_alt_1)
                      ])
                    : Column(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('$jumlah Warga · $tanpa Tanpa NIK',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)))),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: TextField(
                                onChanged: (v) => setState(() => filter = v),
                                decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.filter_list),
                                    suffixIcon: filter.isEmpty
                                        ? null
                                        : IconButton(
                                            onPressed: () =>
                                                setState(() => filter = ''),
                                            icon: const Icon(Icons.close)),
                                    labelText: 'Saring nama atau NIK',
                                    isDense: true))),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child:
                                    Wrap(spacing: 8, runSpacing: 4, children: [
                                  for (final code in [
                                    keteranganNormal,
                                    ...keteranganKode.keys
                                  ])
                                    ChoiceChip(
                                        label: Text(code == keteranganNormal
                                            ? 'Normal'
                                            : code),
                                        selected: filterKeterangan == code,
                                        onSelected: (selected) => setState(() =>
                                            filterKeterangan =
                                                selected ? code : null)),
                                ]))),
                        if (filterAktif)
                          const Padding(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                      'Urutan dikunci selama filter aktif.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54)))),
                        Expanded(
                            child: tampil.isEmpty
                                ? ListView(children: const [
                                    EmptyState('Tidak Ada Warga yang Cocok',
                                        'Coba periksa kembali ejaan nama atau kata kunci pencarian.',
                                        icon: Icons.filter_alt_off_outlined)
                                  ])
                                : ReorderableListView.builder(
                                    scrollController: scroll,
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 24),
                                    buildDefaultDragHandles: false,
                                    itemCount: tampil.length,
                                    onReorderItem: _reorder,
                                    itemBuilder: (context, index) {
                                      final row = tampil[index];
                                      final id = row['id'] as int;
                                      final nik = teks(row['nik']);
                                      final tgl =
                                          tanggalTampil(row['tgl_lahir']);
                                      final catatan =
                                          keteranganTampil(row['keterangan']);
                                      final kodeKet = kodeKeterangan(
                                          teks(row['keterangan']));
                                      final warnaKode = teks(row['warna']);
                                      // Unknown color codes (legacy rows) get
                                      // a distinct shade instead of masquerading
                                      // as "tanpa warna" white.
                                      final warnaKartu =
                                          _warnaKartu[warnaKode] ??
                                              (warnaKode.isEmpty
                                                  ? Colors.white
                                                  : Colors.grey.shade300);
                                      return KeyedSubtree(
                                          key: ValueKey(id),
                                          child: Dismissible(
                                              key: ValueKey('hapus-$id'),
                                              direction:
                                                  DismissDirection.endToStart,
                                              dismissThresholds: const {
                                                DismissDirection.endToStart:
                                                    _ambangGeserHapus
                                              },
                                              background: Container(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  padding: const EdgeInsets.only(
                                                      right: 20),
                                                  color: Colors.red.shade800,
                                                  child: const Icon(Icons.delete,
                                                      color: Colors.white)),
                                              confirmDismiss: (_) =>
                                                  _konfirmasiHapus(row),
                                              onDismissed: (_) => _hapus(row),
                                              child: Card(
                                                  color: sorot == id
                                                      ? const Color(0xFFFFF4D6)
                                                      : warnaKartu,
                                                  child: ListTile(
                                                      isThreeLine: kodeKet == null &&
                                                          catatan.isNotEmpty,
                                                      trailing: IconButton(
                                                          icon: const Icon(
                                                              Icons.more_vert),
                                                          tooltip: 'Menu baris',
                                                          onPressed: () =>
                                                              _opsiKartu(row)),
                                                      leading:
                                                          ReorderableDragStartListener(
                                                              index: index,
                                                              child: Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Text(
                                                                        '${posisi[id]}',
                                                                        style: const TextStyle(
                                                                            fontWeight:
                                                                                FontWeight.w800,
                                                                            color: forest)),
                                                                    const Icon(
                                                                        Icons
                                                                            .drag_handle,
                                                                        size:
                                                                            18)
                                                                  ])),
                                                      title: Text('${row['nama']}',
                                                          style: const TextStyle(
                                                              fontWeight: FontWeight.w700)),
                                                      subtitle: Text.rich(TextSpan(children: [
                                                        TextSpan(
                                                            text: nik.isEmpty
                                                                ? 'Belum ada NIK'
                                                                : nik,
                                                            style: nik.isEmpty
                                                                ? const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700)
                                                                : null),
                                                        if (tgl.isNotEmpty)
                                                          TextSpan(
                                                              text: ' · $tgl'),
                                                        if (kodeKet != null)
                                                          TextSpan(
                                                              text:
                                                                  ' · $kodeKet',
                                                              style: const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700)),
                                                        if (kodeKet == null &&
                                                            catatan.isNotEmpty)
                                                          TextSpan(
                                                              text:
                                                                  '\n$catatan'),
                                                      ])),
                                                      onTap: () => _edit(row),
                                                      onLongPress: () => _opsiKartu(row)))));
                                    })),
                      ])));
  }
}

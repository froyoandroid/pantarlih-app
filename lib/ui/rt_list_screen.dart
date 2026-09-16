import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/keterangan.dart';
import '../data/order.dart';
import 'common.dart';
import 'search_screen.dart';
import 'survey_form.dart';

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
      final index = loaded.indexWhere((r) => r['id'] == scrollTo);
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scroll.hasClients) return;
          scroll.animateTo(
              (index * 108.0).clamp(0, scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut);
        });
      }
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
                  title: const Text('TAMBAHKAN SEBELUMNYA'),
                  onTap: () => Navigator.pop(ctx, 'sebelum')),
              ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_right),
                  title: const Text('TAMBAHKAN SESUDAHNYA'),
                  onTap: () => Navigator.pop(ctx, 'sesudah')),
              ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('UBAH WARNA'),
                  onTap: () => Navigator.pop(ctx, 'warna')),
            ])));
    if (!mounted || pilih == null) return;
    if (pilih == 'sebelum') {
      await _openKetik(beforeId: id);
    } else if (pilih == 'sesudah') {
      await _openKetik(afterId: id);
    } else if (pilih == 'warna') {
      await _ubahWarna(row);
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
    final sekarang = '${row['warna'] ?? ''}';
    final pilih = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 4),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('UBAH WARNA',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)))),
              ListTile(
                  leading: _titikWarna(Colors.white),
                  title: const Text('Tanpa warna'),
                  selected: sekarang.isEmpty,
                  onTap: () => Navigator.pop(ctx, '')),
              for (final e in _labelWarna.entries)
                ListTile(
                    leading: _titikWarna(_warnaKartu[e.key]!),
                    title: Text(e.value.toUpperCase()),
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

  @override
  Widget build(BuildContext context) {
    final jumlah = intValue(counts?['jumlah']);
    final tanpa = intValue(counts?['tanpa_nik']);
    return AppPage(
        session: widget.session,
        title: 'Daftar RT',
        actions: [
          TextButton(onPressed: () => _openKetik(), child: const Text('TAMBAH'))
        ],
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: rows.isEmpty
                    ? ListView(children: const [
                        EmptyState('Belum ada data di RT ini',
                            'Tekan TAMBAH untuk mengetik orang pertama. Aplikasi tetap berjalan tanpa impor referensi.',
                            icon: Icons.person_add_alt_1)
                      ])
                    : Column(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('$jumlah warga · $tanpa tanpa NIK',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700)))),
                        Expanded(
                            child: ReorderableListView.builder(
                                scrollController: scroll,
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                buildDefaultDragHandles: false,
                                itemCount: rows.length,
                                onReorderItem: _reorder,
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  final id = row['id'] as int;
                                  final nik = '${row['nik'] ?? ''}'.trim();
                                  final tgl = tanggalTampil(row['tgl_lahir']);
                                  final catatan =
                                      keteranganTampil(row['keterangan']);
                                  final kodeKet = kodeKeterangan(
                                      '${row['keterangan'] ?? ''}');
                                  final warnaKode = '${row['warna'] ?? ''}';
                                  final warnaKartu =
                                      _warnaKartu[warnaKode] ?? Colors.white;
                                  return KeyedSubtree(
                                      key: ValueKey(id),
                                      child: Dismissible(
                                          key: ValueKey('hapus-$id'),
                                          direction:
                                              DismissDirection.endToStart,
                                          background: Container(
                                              alignment: Alignment.centerRight,
                                              padding: const EdgeInsets.only(
                                                  right: 20),
                                              color: Colors.red.shade800,
                                              child: const Icon(Icons.delete,
                                                  color: Colors.white)),
                                          confirmDismiss: (_) => confirm(
                                              context,
                                              'Hapus ${row['nama']}?',
                                              'Warga ini dihapus dari daftar. Jejak lengkap tetap ada di jurnal.',
                                              action: 'HAPUS',
                                              dangerous: true),
                                          onDismissed: (_) async {
                                            try {
                                              await widget.session.store
                                                  .deleteWarga(id);
                                              await _load();
                                            } catch (e) {
                                              // The row is already gone from
                                              // the widget tree; reload or the
                                              // screen pretends it was deleted.
                                              await _load();
                                              // Closure context from the item
                                              // builder, so guard it directly.
                                              if (context.mounted) {
                                                feedback(context, e,
                                                    error: true);
                                              }
                                            }
                                          },
                                          child: Card(
                                              color: warnaKartu,
                                              child: ListTile(
                                                  isThreeLine: kodeKet == null &&
                                                      catatan.isNotEmpty,
                                                  leading:
                                                      ReorderableDragStartListener(
                                                          index: index,
                                                          child: Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              children: [
                                                                Text(
                                                                    '${index + 1}',
                                                                    style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w800,
                                                                        color:
                                                                            forest)),
                                                                const Icon(
                                                                    Icons
                                                                        .drag_handle,
                                                                    size: 18)
                                                              ])),
                                                  title: Text('${row['nama']}',
                                                      style:
                                                          const TextStyle(fontWeight: FontWeight.w700)),
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
                                                      TextSpan(text: ' · $tgl'),
                                                    if (kodeKet != null)
                                                      TextSpan(
                                                          text: ' · $kodeKet',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700)),
                                                    if (kodeKet == null &&
                                                        catatan.isNotEmpty)
                                                      TextSpan(
                                                          text: '\n$catatan'),
                                                  ])),
                                                  onTap: () => _edit(row),
                                                  onLongPress: () => _opsiKartu(row)))));
                                })),
                      ])));
  }
}

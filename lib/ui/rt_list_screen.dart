import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/keterangan.dart';
import '../data/order.dart';
import 'common.dart';
import 'search_screen.dart';
import 'survey_form.dart';

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
  int? highlight;

  @override
  void initState() {
    super.initState();
    highlight = widget.focusId;
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
    final c = await s.store.counts(s.rt, s.rw);
    if (!mounted) return;
    setState(() {
      rows = loaded;
      counts = c;
      loading = false;
      if (scrollTo != null) highlight = scrollTo;
    });
    if (scrollTo != null) {
      final index = loaded.indexWhere((r) => r['id'] == scrollTo);
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scroll.hasClients) return;
          scroll.animateTo((index * 108.0).clamp(0, scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut);
        });
      }
    }
  }

  Future<void> _openKetik({int? afterId}) async {
    final id = await Navigator.push<int>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                SearchScreen(session: widget.session, afterId: afterId)));
    if (id != null) {
      await _load(scrollTo: id);
    } else {
      await _load();
    }
  }

  Future<void> _edit(RecordMap row) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                SurveyForm(session: widget.session, warga: row)));
    await _load();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final ids = [for (final row in rows) row['id'] as int];
    final neighbors = reorderNeighbors(ids, oldIndex, newIndex);
    if (newIndex > oldIndex) newIndex -= 1;
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
          TextButton(
              onPressed: () => _openKetik(),
              child: const Text('TAMBAH'))
        ],
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: rows.isEmpty
                    ? ListView(children: const [
                        EmptyState(
                            'Belum ada data di RT ini',
                            'Tekan TAMBAH untuk mengetik orang pertama. Aplikasi tetap berjalan tanpa impor referensi.',
                            icon: Icons.person_add_alt_1)
                      ])
                    : Column(children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('$jumlah baris · $tanpa tanpa NIK',
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
                                onReorder: _reorder, // ignore: deprecated_member_use
                                itemBuilder: (context, index) {
                                  final row = rows[index];
                                  final id = row['id'] as int;
                                  final nik = '${row['nik'] ?? ''}'.trim();
                                  final catatan =
                                      keteranganTampil(row['keterangan']);
                                  return Dismissible(
                                      key: ValueKey(id),
                                      direction: DismissDirection.endToStart,
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
                                          'Baris ini dihapus dari daftar. Jejak lengkap tetap ada di jurnal.',
                                          action: 'HAPUS',
                                          dangerous: true),
                                      onDismissed: (_) async {
                                        try {
                                          await widget.session.store
                                              .deleteWarga(id);
                                          await _load();
                                        } catch (e) {
                                          if (context.mounted) {
                                            feedback(context, e, error: true);
                                          }
                                        }
                                      },
                                      child: Column(children: [
                                        Card(
                                            color: highlight == id
                                                ? const Color(0xFFE7F3EE)
                                                : null,
                                            child: ListTile(
                                                isThreeLine:
                                                    catatan.isNotEmpty,
                                                leading: ReorderableDragStartListener(
                                                    index: index,
                                                    child: Column(mainAxisAlignment:
                                                        MainAxisAlignment.center,
                                                        children: [
                                                      Text('${index + 1}',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: forest)),
                                                      const Icon(
                                                          Icons.drag_handle,
                                                          size: 18)
                                                    ])),
                                                title: Text('${row['nama']}',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                subtitle: Text([
                                                  [
                                                    nik.isEmpty
                                                        ? '— belum ada NIK —'
                                                        : nik,
                                                    tanggalTampil(
                                                        row['tgl_lahir']),
                                                  ]
                                                      .where((s) =>
                                                          s.isNotEmpty)
                                                      .join(' · '),
                                                  if (catatan.isNotEmpty)
                                                    catatan,
                                                ].join('\n')),
                                                onTap: () => _edit(row))),
                                        Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                                onPressed: () =>
                                                    _openKetik(afterId: id),
                                                icon: const Icon(Icons.add),
                                                label: const Text('+')))
                                      ]));
                                })),
                      ])));
  }
}

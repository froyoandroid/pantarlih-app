import 'package:flutter/material.dart';
import '../core/format.dart';
import 'common.dart';

class ReferensiScreen extends StatefulWidget {
  const ReferensiScreen({super.key, required this.session});
  final Session session;
  @override
  State<ReferensiScreen> createState() => _ReferensiScreenState();
}

class _ReferensiScreenState extends State<ReferensiScreen> {
  List<RecordMap>? sumber;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.session.store.sumberReferensi();
      if (mounted) setState(() => sumber = loaded);
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  String _namaFile(Object? raw) {
    final nama = teks(raw);
    return nama.isEmpty ? 'File tanpa nama' : nama;
  }

  Future<void> _buka(RecordMap file) async {
    final sumberFile = nullableText(teks(file['sumber_file']));
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReferensiFileScreen(
                session: widget.session,
                sumberFile: sumberFile,
                namaFile: _namaFile(file['sumber_file']))));
  }

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: 'Referensi',
      child: sumber == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    Text('${sumber!.length} file referensi',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                        'Ketuk file untuk membaca isinya. Referensi hanya-baca dan tidak mengubah data hasil ketikan.'),
                    const SizedBox(height: 12),
                    if (sumber!.isEmpty)
                      const EmptyState('Belum ada file referensi',
                          'Impor file .XLSX atau .CSV untuk melihatnya di sini.',
                          icon: Icons.folder_open_outlined),
                    for (final file in sumber!)
                      Card(
                          child: ListTile(
                              leading: const Icon(Icons.description_outlined,
                                  color: forest),
                              title: Text(_namaFile(file['sumber_file']),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text('${intValue(file['jumlah'])} baris'
                                  '${waktuTampil(file['terakhir']).isEmpty ? '' : ' · diimpor ${waktuTampil(file['terakhir'])}'}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _buka(file))),
                  ])));
}

class ReferensiFileScreen extends StatefulWidget {
  const ReferensiFileScreen(
      {super.key,
      required this.session,
      required this.sumberFile,
      required this.namaFile});
  final Session session;
  final String? sumberFile;
  final String namaFile;
  @override
  State<ReferensiFileScreen> createState() => _ReferensiFileScreenState();
}

class _ReferensiFileScreenState extends State<ReferensiFileScreen> {
  List<RecordMap>? rows;
  String filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded =
          await widget.session.store.referensiFile(widget.sumberFile);
      if (mounted) setState(() => rows = loaded);
    } catch (e) {
      if (mounted) {
        setState(() => rows ??= const []);
        feedback(context, e, error: true);
      }
    }
  }

  List<RecordMap> _tampil(List<RecordMap> loaded) {
    final q = filter.trim().toLowerCase();
    if (q.isEmpty) return loaded;
    return [
      for (final row in loaded)
        if ([
          teks(row['nama']),
          teks(row['nik_lama']),
          teks(row['rt']),
          teks(row['rw']),
          teks(row['desa'])
        ].join(' ').toLowerCase().contains(q))
          row
    ];
  }

  String _detail(RecordMap row) {
    final bagian = <String>[];
    final nik = teks(row['nik_lama']);
    final tanggal = tanggalTampil(row['tgl_lahir']);
    final rt = intValue(row['rt']);
    final rw = intValue(row['rw']);
    final desa = teks(row['desa']);
    final urut = intValue(row['urut_asli']);
    final baris = intValue(row['sumber_baris']);
    if (nik.isNotEmpty) bagian.add('NIK lama $nik');
    if (tanggal.isNotEmpty) {
      bagian.add('$tanggal · ${jkTampil(row['jenis_kelamin'])}');
    }
    if (rt > 0 || rw > 0) bagian.add('RT $rt / RW $rw');
    if (desa.isNotEmpty) bagian.add(desa);
    if (urut > 0) bagian.add('No. $urut');
    if (baris > 0) bagian.add('Baris file $baris');
    return bagian.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final loaded = rows;
    final tampil = loaded == null ? const <RecordMap>[] : _tampil(loaded);
    return AppPage(
        session: widget.session,
        title: 'Referensi',
        subtitle: widget.namaFile,
        child: loaded == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      Text(
                          filter.trim().isEmpty
                              ? '${loaded.length} baris referensi'
                              : '${tampil.length} dari ${loaded.length} baris',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      TextField(
                          onChanged: (value) => setState(() => filter = value),
                          decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: filter.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () =>
                                          setState(() => filter = ''),
                                      icon: const Icon(Icons.close)),
                              labelText: 'Cari nama, RT, RW, atau NIK lama')),
                      const SizedBox(height: 10),
                      if (tampil.isEmpty)
                        EmptyState(
                            filter.trim().isEmpty
                                ? 'File ini belum memiliki baris'
                                : 'Tidak ada yang cocok',
                            filter.trim().isEmpty
                                ? 'Impor ulang file bila data seharusnya ada.'
                                : 'Coba kata kunci lain.',
                            icon: Icons.search_off_outlined),
                      for (final row in tampil)
                        Card(
                            child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 6),
                                title: Text(teks(row['nama']),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(_detail(row)),
                                isThreeLine:
                                    _detail(row).split('\n').length > 2)),
                    ])));
  }
}

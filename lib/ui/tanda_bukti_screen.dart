import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../core/format.dart';
import '../data/spreadsheets.dart';
import 'common.dart';

/// Isian tanda bukti. Semua kolom yang tidak ada di database (status
/// perkawinan, centang keterangan, nama petugas dan penerima) diisi di sini
/// tepat sebelum file dibuat - produksi sedang berjalan, jadi tidak ada
/// migrasi skema demi tiga kolom cetak ini.
class TandaBuktiScreen extends StatefulWidget {
  const TandaBuktiScreen({super.key, required this.session});
  final Session session;
  @override
  State<TandaBuktiScreen> createState() => _TandaBuktiScreenState();
}

class _TandaBuktiScreenState extends State<TandaBuktiScreen> {
  static const statusPilihan = ['', 'Kawin', 'Belum Kawin', 'Cerai'];

  List<RecordMap>? rows;
  final dipilih = <int>{};
  final status = <int, String>{};
  final ektp = <int, bool>{};
  final suket = <int, bool>{};
  final belum = <int, bool>{};
  final krt = TextEditingController();
  final petugas = TextEditingController();
  final penerima = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    krt.dispose();
    petugas.dispose();
    penerima.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = widget.session;
      final loaded = await s.store.wargaRt(s.rw, s.rt);
      if (mounted) setState(() => rows = loaded);
    } catch (e) {
      if (mounted) {
        setState(() => rows ??= const []);
        feedback(context, e, error: true);
      }
    }
  }

  Future<void> _buat() async {
    final terpilih = [
      for (final row in rows!)
        if (dipilih.contains(row['id'])) row,
    ];
    if (terpilih.isEmpty) {
      feedback(context, 'Pilih minimal satu warga', error: true);
      return;
    }
    if (petugas.text.trim().isEmpty) {
      feedback(context, 'Nama petugas wajib diisi', error: true);
      return;
    }
    final s = widget.session;
    try {
      final bytes = await rootBundle.load('assets/tanda_bukti_template.xlsx');
      final book = buatTandaBukti(
        bytes.buffer.asUint8List(),
        [
          for (final row in terpilih)
            TandaBuktiIsi(
                row: row,
                statusPerkawinan: status[row['id']] ?? '',
                ektp: ektp[row['id']] ?? false,
                suket: suket[row['id']] ?? false,
                belumRekaman: belum[row['id']] ?? false),
        ],
        desa: s.village.isEmpty ? 'KALITORONG' : s.village,
        kecamatan: s.lokasi?.namaKec ?? '',
        krt: krt.text.trim(),
        rt: s.rt,
        rw: s.rw,
        petugas: petugas.text.trim(),
        penerima: penerima.text.trim(),
      );
      final encoded = book.encode();
      if (encoded == null) throw StateError('gagal mengkodekan');
      final folder = await s.folderPertukaran(minta: true);
      if (!mounted) return;
      if (folder == null) {
        feedback(context,
            'Izin berkas dibutuhkan untuk menyimpan tanda bukti',
            error: true);
        return;
      }
      await folder.siapkan();
      if (!mounted) return;
      final file = File(
          '${folder.ekspor.path}/TANDA_BUKTI_${formatRt(s.rt).replaceAll(' ', '')}_RW${intValue(s.rw).toString().padLeft(2, '0')}_${fileStamp()}.xlsx');
      await file.writeAsBytes(encoded, flush: true);
      if (!mounted) return;
      feedback(context, 'Tanda bukti tersimpan di ${file.path}');
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = rows;
    return AppPage(
        session: widget.session,
        title: 'Tanda Bukti',
        subtitle: widget.session.label,
        child: loaded == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text('${dipilih.length} dari ${loaded.length} warga dipilih',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text(
                      'Centang warga yang masuk tanda bukti. Status perkawinan dan keterangan diisi di sini, tidak tersimpan ke database.'),
                  const SizedBox(height: 12),
                  for (final row in loaded) _barisWarga(row),
                  const SizedBox(height: 8),
                  TextField(
                      controller: krt,
                      decoration: const InputDecoration(
                          labelText: 'Nama Kepala Rumah Tangga')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: petugas,
                      decoration: const InputDecoration(
                          labelText: 'Nama Petugas (wajib)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: penerima,
                      decoration: const InputDecoration(
                          labelText: 'Nama Penerima (yang menerima)')),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                      onPressed: _buat,
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Buat Tanda Bukti')),
                ]));
  }

  Widget _barisWarga(RecordMap row) {
    final id = row['id'] as int;
    final aktif = dipilih.contains(id);
    return Card(
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(children: [
              CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(teks(row['nama']),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    tanggalTampil(row['tgl_lahir']),
                    teks(row['nik']),
                  ].where((s) => s.isNotEmpty).join(' · ')),
                  value: aktif,
                  onChanged: (v) => setState(() {
                        if (v == true) {
                          dipilih.add(id);
                        } else {
                          dipilih.remove(id);
                        }
                      })),
              if (aktif)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<String>(
                              initialValue: status[id] ?? '',
                              decoration: const InputDecoration(
                                  labelText: 'Status Perkawinan',
                                  isDense: true),
                              items: [
                                for (final s in statusPilihan)
                                  DropdownMenuItem(
                                      value: s,
                                      child: Text(s.isEmpty ? '—' : s))
                              ],
                              onChanged: (v) =>
                                  setState(() => status[id] = v ?? ''))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Wrap(spacing: 4, children: [
                        FilterChip(
                            label: const Text('E-KTP'),
                            selected: ektp[id] ?? false,
                            onSelected: (v) => setState(() => ektp[id] = v)),
                        FilterChip(
                            label: const Text('Suket'),
                            selected: suket[id] ?? false,
                            onSelected: (v) => setState(() => suket[id] = v)),
                        FilterChip(
                            label: const Text('Belum'),
                            selected: belum[id] ?? false,
                            onSelected: (v) => setState(() => belum[id] = v)),
                      ])),
                    ])),
            ])));
  }
}

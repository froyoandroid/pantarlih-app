import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/format.dart';
import '../data/spreadsheets.dart';
import 'common.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.session});
  final Session session;
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  TabularSource? source;
  String? sheet, report;
  Map<String, int> mapping = {};
  final start = TextEditingController(text: '2');
  late final TextEditingController rt, rw;
  bool rowRt = false, confirmed = false, busy = false;
  int referensiCount = 0;
  @override
  void initState() {
    super.initState();
    rt = TextEditingController(text: '${widget.session.rt}');
    rw = TextEditingController(text: '${widget.session.rw}');
    _count();
  }

  Future<void> _count() async {
    referensiCount = await widget.session.store.referensiCount();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    start.dispose();
    rt.dispose();
    rw.dispose();
    super.dispose();
  }

  void chooseSheet(String value) {
    sheet = value;
    mapping = source!.suggestedMapping(value);
    confirmed = false;
    report = null;
    final match =
        RegExp(r'^RT\s*0*(\d+)', caseSensitive: false).firstMatch(value);
    if (match != null) rt.text = int.parse(match.group(1)!).toString();
  }

  Future<void> pick() async {
    setState(() => busy = true);
    try {
      final file = await FilePicker.pickFile(
          type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final loaded = openTabular(file.name, bytes);
      if (mounted) {
        setState(() {
          source = loaded;
          chooseSheet(loaded.sheets.firstWhere(
              (name) => loaded.suggestedMapping(name)['nama']! >= 0,
              orElse: () => loaded.sheets.first));
        });
      }
    } catch (e) {
      if (mounted) feedback(context, 'Gagal membaca berkas: $e', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    setState(() => busy = true);
    try {
      final prep = source!.prepare(sheet!, mapping, intValue(start.text),
          intValue(rt.text), intValue(rw.text),
          useRowRt: rowRt);
      if (!mounted) return;
      if (!await confirm(
          context,
          'Impor ${prep.records.length} referensi?',
          'Sheet $sheet · RT ${rt.text} / RW ${rw.text}\n'
              '${prep.skipped.length} baris akan dilewati.\n\n'
              'Referensi hanya bantuan pengetikan. Impor ulang file yang sama diperbolehkan.',
          action: 'IMPOR SEKARANG')) {
        return;
      }
      final stamped = [
        for (final row in prep.records)
          {...row, 'kode_wilayah': widget.session.kodeWilayah}
      ];
      await source!.archiveAndImport(widget.session.store, sheet!, stamped,
          mapping, intValue(start.text), intValue(rt.text),
          skipped: prep.skipped);
      await _count();
      if (mounted) {
        setState(() {
          report =
              '${prep.records.length} baris masuk, ${prep.skipped.length} dilewati dari $sheet.';
          confirmed = false;
        });
        if (prep.skipped.isNotEmpty) {
          await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: Text(
                          '${prep.records.length} baris masuk, ${prep.skipped.length} dilewati'),
                      content: SizedBox(
                          width: 420,
                          height: 320,
                          child: ListView(children: [
                            for (final row in prep.skipped)
                              ListTile(
                                  dense: true,
                                  title: Text('Baris ${row['baris']}'),
                                  subtitle: Text('${row['alasan']}')),
                          ])),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Tutup'))
                      ]));
        }
      }
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clearAll() async {
    if (!await confirm(context, 'Hapus semua referensi?',
        'Data hasil ketikan tidak ikut terhapus. Saran pengetikan akan kosong sampai Anda impor lagi.',
        action: 'HAPUS SEMUA', dangerous: true)) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.session.store.clearReferensi();
      await _count();
      if (mounted) {
        setState(() => report = 'Semua referensi dihapus.');
      }
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = source == null || sheet == null
        ? <List<String>>[]
        : source!.rows(sheet!);
    final columns = rows.isEmpty
        ? 0
        : rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    return AppPage(
        session: widget.session,
        title: 'Impor referensi',
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Referensi tersimpan: $referensiCount baris',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Aplikasi tetap berfungsi tanpa impor. Referensi hanya mengisi saran ketik.'),
          Notice(
              'Lokasi berkas ini: ${widget.session.village.isEmpty ? 'belum diatur' : widget.session.village}. Kode wilayah aktif dipakai untuk seluruh baris impor.'),
          const SizedBox(height: 12),
          if (referensiCount > 0)
            OutlinedButton.icon(
                onPressed: busy ? null : clearAll,
                icon: const Icon(Icons.delete_outline),
                label: const Text('HAPUS SEMUA REFERENSI')),
          const SizedBox(height: 20),
          const Text('1. Pilih workbook',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Workbook gabungan didukung. Impor sheet RT satu per satu, jangan pilih sheet REKAP.'),
          const SizedBox(height: 14),
          OutlinedButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.upload_file),
              label: Text(source?.name ?? 'PILIH FILE .XLSX ATAU .CSV')),
          if (source != null) ...[
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
                key: ValueKey('${source!.name}:$sheet'),
                value: sheet, // ignore: deprecated_member_use
                decoration: const InputDecoration(labelText: 'Sheet'),
                items: source!.sheets
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged:
                    busy ? null : (s) => setState(() => chooseSheet(s!))),
            const SizedBox(height: 14),
            Text('Pratinjau · ${rows.length} baris pada sheet',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 52,
                    columns: [
                      const DataColumn(label: Text('Baris')),
                      for (var i = 0; i < columns; i++)
                        DataColumn(label: Text('Kolom ${i + 1}'))
                    ],
                    rows: [
                      for (var i = 0; i < rows.length && i < 10; i++)
                        DataRow(cells: [
                          DataCell(Text('${i + 1}')),
                          for (var j = 0; j < columns; j++)
                            DataCell(Text(j < rows[i].length ? rows[i][j] : ''))
                        ])
                    ])),
            const SizedBox(height: 20),
            const Text('2. Petakan kolom',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final entry in importFields.entries)
              Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                      key:
                          ValueKey('$sheet:${entry.key}:${mapping[entry.key]}'),
                      initialValue: mapping[entry.key] ??
                          -1, // ignore: deprecated_member_use
                      isExpanded: true,
                      decoration: InputDecoration(labelText: entry.value),
                      items: [
                        const DropdownMenuItem(
                            value: -1,
                            child: Text('Tidak dipetakan / default')),
                        for (var i = 0; i < columns; i++)
                          DropdownMenuItem(
                              value: i,
                              child: Text(
                                  '${i + 1} · ${rows.isNotEmpty && i < rows.first.length ? rows.first[i] : ''}',
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                                mapping[entry.key] = v!;
                                confirmed = false;
                              }))),
            TextField(
                controller: start,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Baris data pertama (bukan header)'),
                onChanged: (_) => setState(() => confirmed = false)),
            const SizedBox(height: 20),
            const Text('3. Konfirmasi wilayah',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: rt,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'RT file ini'),
                      onChanged: (_) => setState(() => confirmed = false))),
              const SizedBox(width: 12),
              Expanded(
                  child: TextField(
                      controller: rw,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'RW default'),
                      onChanged: (_) => setState(() => confirmed = false))),
            ]),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gunakan RT dari setiap baris'),
                subtitle: const Text(
                    'Aktifkan hanya bila satu sheet berisi beberapa RT.'),
                value: rowRt,
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                          rowRt = v;
                          confirmed = false;
                        })),
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    'Saya sudah memeriksa pemetaan dan RT ${rt.text} / RW ${rw.text}.'),
                value: confirmed,
                onChanged: busy ? null : (v) => setState(() => confirmed = v!)),
            if (report != null) Notice(report!),
            FilledButton.icon(
                onPressed: busy || !confirmed ? null : import,
                icon: const Icon(Icons.download_done),
                label: Text(busy ? 'Memproses…' : 'IMPOR REFERENSI')),
          ],
          const SizedBox(height: 12),
          const Notice(
              'NIK tersamar disimpan apa adanya. Referensi tidak dihubungkan ke data hasil, tidak diubah, dan boleh kotor.',
              icon: Icons.shield_outlined),
        ]));
  }
}

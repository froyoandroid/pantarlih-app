import 'package:flutter/material.dart';
import '../core/keterangan.dart';
import 'common.dart';

/// Kustomisasi chip keterangan. Empat kode resmi selalu ada dan tidak bisa
/// dihapus; kode buatan disimpan sebagai satu string di setelan sehingga
/// tidak ada migrasi skema dan tidak ada jurnal baru. Warga yang memakai
/// kode yang dihapus otomatis masuk kelompok 'Lainnya'.
class PengaturanScreen extends StatefulWidget {
  const PengaturanScreen({super.key, required this.session});
  final Session session;
  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  late Map<String, String> kustom;

  @override
  void initState() {
    super.initState();
    kustom = Map<String, String>.of(widget.session.keteranganKustom);
  }

  Future<void> _simpan(Map<String, String> peta) async {
    try {
      await widget.session.saveKeteranganKustom(peta);
      if (mounted) setState(() => kustom = Map<String, String>.of(peta));
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    }
  }

  Future<void> _tambah() async {
    final hasil = await showDialog<(String, String)>(
        context: context, builder: (_) => const _ChipKeteranganDialog());
    if (hasil == null) return;
    final peta = Map<String, String>.of(kustom);
    peta[hasil.$1] = hasil.$2;
    await _simpan(peta);
  }

  Future<void> _hapus(String kode) async {
    if (!await confirm(context, 'Hapus chip $kode?',
        'Warga yang memakai $kode akan masuk kelompok Lainnya di filter. Nilai pada data tidak dihapus.',
        action: 'Hapus', dangerous: true)) {
      return;
    }
    final peta = Map<String, String>.of(kustom)..remove(kode);
    await _simpan(peta);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = kustom;
    return AppPage(
        session: widget.session,
        title: 'Pengaturan',
        subtitle: 'Chip keterangan warga',
        child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                    const Text('Keterangan Warga',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                        'Chip keterangan tampil di formulir warga dan menjadi filter di Daftar Warga.'),
                    const SizedBox(height: 12),
                    const Text('Bawaan',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Card(
                        child: Column(children: [
                      for (final e in keteranganKode.entries)
                        ListTile(
                            dense: true,
                            title: Text(e.key,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(e.value)),
                    ])),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Expanded(
                          child: Text('Buatan',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700))),
                      TextButton.icon(
                          onPressed: _tambah,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Tambah')),
                    ]),
                    if (loaded.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'Belum ada chip buatan. Contoh: R untuk Rukoh, H untuk Hilang.',
                              style: TextStyle(color: Colors.black54)))
                    else
                      Card(
                          child: Column(children: [
                        for (final e in loaded.entries)
                          ListTile(
                              dense: true,
                              title: Text(e.key,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(e.value),
                              trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                  tooltip: 'Hapus chip',
                                  onPressed: () => _hapus(e.key))),
                      ])),
                  ]));
  }
}

class _ChipKeteranganDialog extends StatefulWidget {
  const _ChipKeteranganDialog();
  @override
  State<_ChipKeteranganDialog> createState() => _ChipKeteranganDialogState();
}

class _ChipKeteranganDialogState extends State<_ChipKeteranganDialog> {
  final kode = TextEditingController();
  final arti = TextEditingController();
  String? galat;

  @override
  void dispose() {
    kode.dispose();
    arti.dispose();
    super.dispose();
  }

  void _simpan() {
    final k = kode.text.trim().toUpperCase();
    final a = arti.text.trim();
    if (k.isEmpty || a.isEmpty) {
      setState(() => galat = 'Kode dan arti wajib diisi');
      return;
    }
    if (keteranganKode.containsKey(k)) {
      setState(() => galat = '$k sudah menjadi kode bawaan');
      return;
    }
    Navigator.pop(context, (k, a));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Chip Keterangan Baru'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: kode,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Kode', hintText: 'Mis. R')),
            const SizedBox(height: 12),
            TextField(
                controller: arti,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Arti singkat', hintText: 'Mis. Rukoh')),
            if (galat != null)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(galat!,
                      style:
                          TextStyle(fontSize: 12, color: Colors.red.shade800))),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal')),
            FilledButton(onPressed: _simpan, child: const Text('Simpan')),
          ]);
}

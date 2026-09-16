import 'package:flutter/material.dart';
import '../core/format.dart';
import '../data/wilayah.dart';
import 'common.dart';

class LokasiScreen extends StatefulWidget {
  const LokasiScreen(
      {super.key,
      required this.session,
      this.allowSkip = false,
      this.nextPage});
  final Session session;
  final bool allowSkip;
  final Widget? nextPage;
  @override
  State<LokasiScreen> createState() => _LokasiScreenState();
}

class _LokasiScreenState extends State<LokasiScreen> {
  Wilayah? prov, kab, kec, desa;
  List<Wilayah> provs = [], kabs = [], kecs = [], desas = [];
  List<(Wilayah, String)> hits = [];
  final globalSearch = TextEditingController();
  bool busy = false;

  WilayahRepo get repo => widget.session.wilayah;

  @override
  void initState() {
    super.initState();
    _loadProv();
  }

  @override
  void dispose() {
    globalSearch.dispose();
    super.dispose();
  }

  Future<void> _loadProv() async {
    provs = await repo.anak(null);
    if (mounted) setState(() {});
  }

  Future<void> _pickProv(Wilayah value) async {
    setState(() {
      prov = value;
      kab = kec = desa = null;
      kabs = kecs = desas = [];
    });
    kabs = await repo.anak(value.kode);
    if (mounted) setState(() {});
  }

  Future<void> _pickKab(Wilayah value) async {
    setState(() {
      kab = value;
      kec = desa = null;
      kecs = desas = [];
    });
    kecs = await repo.anak(value.kode);
    if (mounted) setState(() {});
  }

  Future<void> _pickKec(Wilayah value) async {
    setState(() {
      kec = value;
      desa = null;
      desas = [];
    });
    desas = await repo.anak(value.kode);
    if (mounted) setState(() {});
  }

  void _pickDesa(Wilayah value) => setState(() => desa = value);

  Future<void> _search(String raw) async {
    if (raw.trim().length < 3) {
      setState(() => hits = []);
      return;
    }
    final found = await repo.cari(raw);
    final labeled = <(Wilayah, String)>[];
    for (final w in found) {
      labeled.add((w, await repo.jalur(w.kode)));
    }
    if (mounted) setState(() => hits = labeled);
  }

  Future<void> _applyHit(Wilayah w) async {
    final chain = await repo.leluhur(w.kode);
    Wilayah? p, k, c, d;
    if (w.level == 1) {
      p = w;
    } else if (w.level == 2) {
      p = chain.isNotEmpty ? chain[0] : null;
      k = w;
    } else if (w.level == 3) {
      p = chain.isNotEmpty ? chain[0] : null;
      k = chain.length > 1 ? chain[1] : null;
      c = w;
    } else {
      p = chain.isNotEmpty ? chain[0] : null;
      k = chain.length > 1 ? chain[1] : null;
      c = chain.length > 2 ? chain[2] : null;
      d = w;
    }
    setState(() {
      prov = p;
      kab = k;
      kec = c;
      desa = d;
      hits = [];
      globalSearch.clear();
    });
    if (p != null) kabs = await repo.anak(p.kode);
    if (k != null) kecs = await repo.anak(k.kode);
    if (c != null) desas = await repo.anak(c.kode);
    if (mounted) setState(() {});
  }

  Future<void> _finish() {
    final next = widget.nextPage;
    if (next != null) {
      return Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => next));
    }
    Navigator.pop(context, true);
    return Future.value();
  }

  Future<void> saveOfficial() async {
    if (desa == null) {
      feedback(context, 'Pilih desa atau kelurahan dulu, atau ketik manual.',
          error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final meta = await repo.meta();
      await widget.session.saveLokasi(Lokasi(
          kode: desa!.kode,
          namaDesa: desa!.nama,
          namaKec: kec?.nama,
          namaKab: kab?.nama,
          namaProv: prov?.nama,
          kodeKec: kec?.kode,
          nikPrefix: kec?.kodePolos,
          sumberVersi: meta['kepmendagri'],
          manual: false,
          dicatatPada: timestamp()));
      if (!mounted) return;
      await _finish();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveManual() async {
    final desaC = TextEditingController();
    final kecC = TextEditingController();
    final kabC = TextEditingController();
    final provC = TextEditingController();
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Ketik lokasi secara manual'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Pakai ini bila desa tidak ada di daftar resmi, atau berkas wilayah gagal dibuka. Aplikasi tetap bisa dipakai penuh.'),
                  const SizedBox(height: 12),
                  TextField(
                      controller: desaC,
                      textCapitalization: TextCapitalization.characters,
                      decoration:
                          const InputDecoration(labelText: 'Desa / kelurahan *')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: kecC,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Kecamatan')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: kabC,
                      textCapitalization: TextCapitalization.characters,
                      decoration:
                          const InputDecoration(labelText: 'Kabupaten / kota')),
                  const SizedBox(height: 10),
                  TextField(
                      controller: provC,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Provinsi')),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('SIMPAN')),
                ]));
    final namaDesa = desaC.text;
    final namaKec = kecC.text;
    final namaKab = kabC.text;
    final namaProv = provC.text;
    desaC.dispose();
    kecC.dispose();
    kabC.dispose();
    provC.dispose();
    if (ok != true) return;
    if (!mounted) return;
    if (namaDesa.trim().isEmpty) {
      feedback(context, 'Nama desa wajib diisi pada mode manual.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await widget.session.saveLokasi(Lokasi(
          kode: kodeLokasiManual(namaDesa),
          namaDesa: namaDesa.trim(),
          namaKec: nullableText(namaKec),
          namaKab: nullableText(namaKab),
          namaProv: nullableText(namaProv),
          manual: true,
          dicatatPada: timestamp()));
      if (!mounted) return;
      await _finish();
    } catch (e) {
      if (mounted) feedback(context, e, error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _picker(
      String title, List<Wilayah> items, Wilayah? selected, ValueChanged<Wilayah> onPick,
      {String? emptyHint}) {
    if (items.isEmpty) {
      return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InputDecorator(
              decoration: InputDecoration(labelText: title),
              child: Text(emptyHint ?? 'Pilih tingkat di atasnya terlebih dahulu.',
                  style: const TextStyle(color: Colors.black54))));
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
            key: ValueKey('$title:${selected?.kode}:${items.length}'),
            value: selected?.kode, // ignore: deprecated_member_use
            isExpanded: true,
            itemHeight: null,
            decoration: InputDecoration(
                labelText: title, helperText: selected?.kode),
            hint: const Text('Pilih'),
            selectedItemBuilder: (ctx) => [
                  for (final w in items)
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text(w.nama,
                            overflow: TextOverflow.ellipsis, maxLines: 1))
                ],
            items: [
              for (final w in items)
                DropdownMenuItem(
                    value: w.kode,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(w.nama, overflow: TextOverflow.ellipsis),
                          Text(w.kode,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black54)),
                        ]))
            ],
            onChanged: busy
                ? null
                : (kode) {
                    if (kode == null) return;
                    for (final w in items) {
                      if (w.kode == kode) {
                        onPick(w);
                        return;
                      }
                    }
                  }));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('Pilih lokasi kerja'),
          automaticallyImplyLeading: widget.nextPage == null),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        if (!repo.available)
          const Notice(
              'Berkas wilayah tidak dapat dibuka. Ketik lokasi secara manual. Data pengguna tidak terpengaruh.',
              warning: true),
        const Text(
            'Pilih Provinsi, Kabupaten/Kota, Kecamatan, lalu Desa/Kelurahan. Kode ditampilkan agar desa bernama sama bisa dibedakan.'),
        const SizedBox(height: 14),
        TextField(
            controller: globalSearch,
            onChanged: _search,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Cari di seluruh Indonesia',
                hintText: 'minimal 3 huruf, contoh kalitorong')),
        if (hits.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final hit in hits)
            Card(
                child: ListTile(
                    title: Text(hit.$1.nama,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${hit.$2}\n${hit.$1.kode}',
                        style: const TextStyle(fontSize: 12, height: 1.35)),
                    isThreeLine: true,
                    onTap: () => _applyHit(hit.$1))),
        ],
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Column(children: [
                  _picker('Provinsi', provs, prov, _pickProv),
                  if (prov != null)
                    _picker('Kabupaten / Kota', kabs, kab, _pickKab),
                  if (kab != null) _picker('Kecamatan', kecs, kec, _pickKec),
                  if (kec != null)
                    _picker('Desa / Kelurahan', desas, desa, _pickDesa),
                ]))),
        if (desa != null) ...[
          const SizedBox(height: 8),
          Notice(
              'Provinsi ${prov?.nama ?? '—'}\n'
              'Kabupaten/Kota ${kab?.nama ?? '—'}\n'
              'Kecamatan ${kec?.nama ?? '—'}\n'
              'Desa/Kelurahan ${desa!.nama}\n'
              'Kode ${desa!.kode}\n'
              'Prefix NIK ${kec?.kodePolos ?? '—'}\n'
              'Sumber ${widget.session.wilayah.available ? 'Kepmendagri' : 'manual'}'),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: busy ? null : saveOfficial,
            icon: const Icon(Icons.check),
            label: const Text('SIMPAN LOKASI')),
        const SizedBox(height: 8),
        OutlinedButton(
            onPressed: busy ? null : saveManual,
            child: const Text('Tidak ada di daftar — ketik manual')),
        if (widget.allowSkip)
          TextButton(
              onPressed: busy ? null : _finish,
              child: const Text('Lewati untuk sekarang')),
        if (busy)
          const Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
      ])));
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/format.dart';
import '../core/keterangan.dart';
import '../core/nik.dart';
import '../data/store.dart';
import 'common.dart';

class SurveyForm extends StatefulWidget {
  const SurveyForm(
      {super.key,
      required this.session,
      this.warga,
      this.seed,
      this.initialName,
      this.afterId,
      this.beforeId,
      this.chainCount = 1});
  final Session session;
  final RecordMap? warga;
  final RecordMap? seed;
  final String? initialName;
  final int? afterId;
  final int? beforeId;
  final int chainCount;
  @override
  State<SurveyForm> createState() => _SurveyFormState();
}

class _SurveyFormState extends State<SurveyForm> {
  late final TextEditingController name,
      nik,
      birthPlace,
      birthDate,
      village,
      rt,
      rw,
      note;
  String? gender;
  String? ketChip;
  final noteFocus = FocusNode(skipTraversal: true);
  bool saving = false;
  int? get wargaId => widget.warga?['id'] as int?;
  double get _persenKelengkapan => persenKelengkapanWarga({
        'nama': name.text,
        'nik': nik.text,
        'jenis_kelamin': gender,
        'tempat_lahir': birthPlace.text,
        'tgl_lahir': parseTanggal(birthDate.text),
        'desa': village.text,
        'rt': rt.text,
        'rw': rw.text,
      });

  @override
  void initState() {
    super.initState();
    final edit = widget.warga;
    final seed = widget.seed;
    String pilih(List<Object?> values, [String fallback = '']) {
      for (final v in values) {
        final t = teks(v);
        if (t.isNotEmpty) return t;
      }
      return fallback;
    }

    name = TextEditingController(
        text: pilih([edit?['nama'], seed?['nama'], widget.initialName])
            .toUpperCase());
    nik = TextEditingController(text: pilih([edit?['nik']]));
    birthPlace = TextEditingController(
        text: pilih([edit?['tempat_lahir'], seed?['tempat_lahir']])
            .toUpperCase());
    birthDate = TextEditingController(
        text: edit?['tgl_lahir'] != null
            ? tanggalTampil(edit?['tgl_lahir'])
            : pilih(
                [seed?['tgl_lahir_raw'], tanggalTampil(seed?['tgl_lahir'])]));
    village = TextEditingController(
        text: pilih([edit?['desa'], seed?['desa']], widget.session.village)
            .toUpperCase());
    rt = TextEditingController(
        text: teks(edit?['rt'] ?? seed?['rt'] ?? widget.session.rt));
    rw = TextEditingController(
        text: teks(edit?['rw'] ?? seed?['rw'] ?? widget.session.rw));
    final rawNote = pilih([edit?['keterangan']]).toUpperCase();
    note = TextEditingController(text: rawNote);
    ketChip = chipKeterangan(rawNote);
    gender = (edit?['jenis_kelamin'] ?? seed?['jenis_kelamin']) as String?;
  }

  void _pilihKeterangan(String? next) {
    setState(() {
      ketChip = next ?? keteranganNormal;
      if (ketChip == keteranganNormal) {
        note.clear();
        return;
      }
      if (ketChip == keteranganLainnya) {
        if (kodeKeterangan(note.text) != null) note.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) noteFocus.requestFocus();
        });
        return;
      }
      note.text = ketChip!;
    });
  }

  @override
  void dispose() {
    for (final c in [name, nik, birthPlace, birthDate, village, rt, rw, note]) {
      c.dispose();
    }
    noteFocus.dispose();
    super.dispose();
  }

  Future<void> save({bool lanjut = false}) async {
    setState(() => saving = true);
    try {
      if (name.text.trim().isEmpty) throw AppException('Nama wajib diisi');
      final iso =
          birthDate.text.trim().isEmpty ? null : parseTanggal(birthDate.text);
      if (birthDate.text.trim().isNotEmpty && iso == null) {
        // The input formatter only lets dashes through, so that is the one
        // shape worth naming.
        throw AppException('Tanggal harus DD-MM-YYYY');
      }
      final data = <String, Object?>{
        'nik': nullableText(nik.text),
        'nama': name.text.toUpperCase(),
        'jenis_kelamin': gender,
        'tempat_lahir': nullableText(birthPlace.text.toUpperCase()),
        'tgl_lahir': iso,
        'desa': nullableText(village.text.toUpperCase()),
        'kode_wilayah':
            widget.warga?['kode_wilayah'] ?? widget.session.kodeWilayah,
        'rt': int.tryParse(rt.text),
        'rw': int.tryParse(rw.text),
        'keterangan': nilaiKeterangan(ketChip, note.text.toUpperCase()),
        'warna': widget.warga?['warna'],
      };
      // A typed RT/RW outside the workspace would silently store the row in
      // an invisible area, so offer to add the pair first.
      final rtBaru = int.tryParse(rt.text) ?? 0;
      final rwBaru = int.tryParse(rw.text) ?? 0;
      // Required fields are validated up front, before any dialog, instead
      // of surfacing as a red snackbar after the flow.
      if (rtBaru <= 0 || rwBaru <= 0) {
        throw AppException('RT dan RW wajib diisi dengan angka lebih dari nol');
      }
      if (rtBaru > 0 &&
          rwBaru > 0 &&
          !widget.session.workspace.contains(RtRw(rwBaru, rtBaru))) {
        final tambah = await confirm(
            context,
            '${formatRtRw(rtBaru, rwBaru)} belum ada di wilayah kerja',
            'Tambahkan agar data ini tampil di daftar. Bila dilewati, data tetap tersimpan dan bisa ditambahkan dari Beranda.',
            action: 'TAMBAHKAN');
        if (!mounted) return;
        if (tambah) await widget.session.addRtRw(rtBaru, rwBaru);
      }
      final duplicates = nik.text.trim().isEmpty
          ? <RecordMap>[]
          : await widget.session.store
              .duplicates(nik.text.trim(), exceptId: wargaId);
      // Format warnings stay inline under the field; the dialog is only for
      // duplicate NIK, which needs the list of the rows already holding it.
      if (duplicates.isNotEmpty) {
        if (!mounted) return;
        final positions = <int, int>{};
        for (final row in duplicates) {
          positions[row['id'] as int] = await widget.session.store
              .posisi(row['id'] as int, row['rw'] as int, row['rt'] as int);
        }
        if (!mounted) return;
        final isi = [
          'NIK yang sama sudah tercatat pada:\n${duplicates.map((r) => '• ${r['nama']} · ${formatRt(r['rt'])} · posisi ${positions[r['id']]} · ${waktuTampil(r['dibuat_pada'])}').join('\n')}',
          'Simpan tetap bila memang dua orang berbeda.',
        ].join('\n\n');
        final decision = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text('NIK ini sudah terpakai',
                        style: TextStyle(color: Colors.red.shade800)),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(isi),
                      for (final row in duplicates)
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, 'open:${row['id']}'),
                            child: Text('Buka ${row['nama']}')),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, 'cancel'),
                          child: const Text('Batal')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, 'save'),
                          child: const Text('SIMPAN TETAP'))
                    ]));
        if (!mounted) return;
        if (decision != 'save') {
          setState(() => saving = false);
          if (decision?.startsWith('open:') ?? false) {
            final other = await widget.session.store
                .warga(int.parse(decision!.split(':').last));
            if (!mounted || other == null) return;
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        SurveyForm(session: widget.session, warga: other)));
          }
          return;
        }
      }
      final saved = await widget.session.store.saveWarga(data,
          id: wargaId, afterId: widget.afterId, beforeId: widget.beforeId);
      if (!mounted) return;
      feedback(context,
          wargaId == null ? 'Data tersimpan.' : 'Perubahan tersimpan.');
      if (lanjut) {
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => SurveyForm(
                        session: widget.session,
                        afterId: saved['id'] as int,
                        chainCount: widget.chainCount + 1,
                        seed: {
                          'desa': nullableText(village.text) ??
                              widget.session.village,
                          'rt': int.tryParse(rt.text),
                          'rw': int.tryParse(rw.text),
                        })));
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.pop(context, saved['id'] as int);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        feedback(context, e, error: true);
      }
    }
  }

  InputDecoration deco(String label, {String? hint}) =>
      InputDecoration(labelText: label, hintText: hint);

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: wargaId == null ? 'Warga baru' : 'Ubah data warga',
      bottom: Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined),
                label: const Text('SIMPAN'))),
        const SizedBox(width: 10),
        Expanded(
            child: OutlinedButton(
                onPressed: saving ? null : () => save(lanjut: true),
                child: const Text('SIMPAN & LANJUT'))),
      ]),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            if (wargaId == null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Orang ke-${widget.chainCount} sejak masuk form',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600))),
            const Text(
                'Baca dan isi sesuai KK asli. Aplikasi tidak menilai kelayakan warga.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            Card(
                child: ListTile(
              dense: true,
              title: const Text('Kelengkapan data'),
              subtitle: const Text('NIK belum diisi'),
              trailing: Text('${_persenKelengkapan.round()}%',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: forest)),
            )),
            const SizedBox(height: 18),
            TextField(
                controller: name,
                autofocus: widget.warga == null,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [HurufKapitalFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: deco('NAMA *')),
            const SizedBox(height: 14),
            TextField(
                controller: nik,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16)
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 20, letterSpacing: 2),
                decoration: deco('NIK')),
            if (nik.text.isNotEmpty)
              ...periksaNik(
                      nik.text,
                      DateTime.tryParse(parseTanggal(birthDate.text) ?? ''),
                      gender,
                      prefixWilayah: widget.session.lokasi?.nikPrefix)
                  .map((w) => Notice(w, warning: true)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
                value: gender, // ignore: deprecated_member_use
                decoration: deco('JENIS KELAMIN'),
                items: const [
                  DropdownMenuItem(value: 'L', child: Text('LAKI-LAKI')),
                  DropdownMenuItem(value: 'P', child: Text('PEREMPUAN')),
                ],
                onChanged: (value) => setState(() => gender = value)),
            const SizedBox(height: 14),
            TextField(
                controller: birthPlace,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [HurufKapitalFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: deco('TEMPAT LAHIR')),
            const SizedBox(height: 14),
            TextField(
                controller: birthDate,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                inputFormatters: [TanggalInputFormatter()],
                decoration: deco('TANGGAL LAHIR', hint: 'DD-MM-YYYY')),
            const SizedBox(height: 14),
            TextField(
                controller: village,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [HurufKapitalFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: deco('DESA / DUSUN')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: rt,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: deco('RT *'))),
              const SizedBox(width: 14),
              Expanded(
                  child: TextField(
                      controller: rw,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: deco('RW *')))
            ]),
            const SizedBox(height: 14),
            InputDecorator(
                decoration: deco('KETERANGAN (opsional)'),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ChoiceChip(
                            label: const Text('Normal'),
                            selected: ketChip == keteranganNormal,
                            onSelected: (_) =>
                                _pilihKeterangan(keteranganNormal)),
                        for (final code in keteranganKode.keys)
                          ChoiceChip(
                              label: Text(code),
                              selected: ketChip == code,
                              onSelected: (on) => _pilihKeterangan(
                                  on ? code : keteranganNormal)),
                        ChoiceChip(
                            label: const Text('Lainnya'),
                            selected: ketChip == keteranganLainnya,
                            onSelected: (on) => _pilihKeterangan(
                                on ? keteranganLainnya : keteranganNormal)),
                      ]),
                      if (keteranganArti(ketChip) != null) ...[
                        const SizedBox(height: 8),
                        Text(keteranganArti(ketChip)!,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                                height: 1.4)),
                      ],
                    ])),
            if (ketChip == keteranganLainnya) ...[
              const SizedBox(height: 14),
              TextField(
                  controller: note,
                  focusNode: noteFocus,
                  maxLines: 3,
                  inputFormatters: [HurufKapitalFormatter()],
                  decoration: deco('LAINNYA',
                      hint:
                          'Tulis keterangan. Tidak dipakai untuk penilaian atau pencarian')),
            ],
            const SizedBox(height: 18),
            const Notice(
                'NIK boleh kosong dan tetap dapat disimpan, tetapi kelengkapan belum 100%. Bila diisi, kurang dari 16 digit hanya peringatan.',
                warning: true),
          ]));
}

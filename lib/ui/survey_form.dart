import 'dart:async';
import 'dart:convert';
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
  Map<String, String> get _kustom => widget.session.keteranganKustom;
  final noteFocus = FocusNode(skipTraversal: true);
  bool saving = false;

  /// Autosave for the half-filled new-warga form, the last place a killed
  /// app can still lose typing. New-warga mode only: an edit form already
  /// has its data safe in the database, and an edit draft could silently
  /// shadow a save made from another screen.
  Timer? _draftTimer;
  Future<void> _draftWrite = Future<void>.value();
  bool _draftReady = false;
  late final bool _drafAktif;

  void _jadwalkanDraf(String _) {
    if (!_drafAktif || !_draftReady || saving) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 500), () {
      if (!saving && _draftReady) _simpanDraf();
    });
  }

  Map<String, Object?> _isiDraf() => {
        'rt': widget.session.rt,
        'rw': widget.session.rw,
        'nama': name.text,
        'nik': nik.text,
        'tempat_lahir': birthPlace.text,
        'tgl_lahir': birthDate.text,
        'desa': village.text,
        'f_rt': rt.text,
        'f_rw': rw.text,
        'jenis_kelamin': gender,
        'ket_chip': ketChip,
        'keterangan': note.text,
      };

  Future<void> _simpanDraf() async {
    final store = widget.session.store;
    final isi = _isiDraf();
    final kosong = ['nama', 'nik', 'tempat_lahir', 'tgl_lahir', 'keterangan']
        .every((k) => teks(isi[k]).isEmpty);
    _draftWrite = _draftWrite.then((_) async {
      try {
        if (kosong) {
          await store.clearDraft();
        } else {
          await store.saveDraft(jsonEncode(isi));
        }
      } catch (_) {
        // A draft write must never break the form.
      }
    });
    await _draftWrite;
  }

  Future<void> _selesaikanDraf(AppStore store) async {
    if (!_drafAktif) return;
    _draftReady = false;
    _draftTimer?.cancel();
    await _draftWrite;
    try {
      await store.clearDraft();
    } catch (_) {
      // The resident is already committed. A transient cleanup failure must
      // not offer to save the same resident again.
    }
  }

  Future<void> _tawarkanDraf() async {
    final raw = await widget.session.store.loadDraft();
    if (!mounted) return;
    if (raw == null) {
      setState(() => _draftReady = true);
      return;
    }
    RecordMap draf;
    try {
      draf = Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      await widget.session.store.clearDraft();
      if (mounted) setState(() => _draftReady = true);
      return;
    }
    // A draft from another RT/RW session would prefill the wrong context.
    if (intValue(draf['rt']) != widget.session.rt ||
        intValue(draf['rw']) != widget.session.rw) {
      await widget.session.store.clearDraft();
      if (mounted) setState(() => _draftReady = true);
      return;
    }
    final nama = teks(draf['nama']);
    if (!mounted) return;
    final lanjut = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Lanjutkan Draf?'),
                content: Text(
                    'Ada formulir yang belum disimpan${nama.isEmpty ? '' : ' untuk $nama'}. Lanjutkan mengisi atau buang draf ini?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Buang')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Lanjutkan')),
                ]));
    if (!mounted) return;
    if (lanjut ?? false) {
      setState(() {
        name.text = teks(draf['nama']);
        nik.text = teks(draf['nik']);
        birthPlace.text = teks(draf['tempat_lahir']);
        birthDate.text = teks(draf['tgl_lahir']);
        village.text = teks(draf['desa']);
        rt.text = teks(draf['f_rt']);
        rw.text = teks(draf['f_rw']);
        note.text = teks(draf['keterangan']);
        gender = draf['jenis_kelamin'] as String?;
        ketChip = draf['ket_chip'] as String?;
      });
    } else {
      await widget.session.store.clearDraft();
    }
    if (mounted) setState(() => _draftReady = true);
  }

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
    _drafAktif = widget.warga == null;
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
    // NIK dari referensi dibawa ke form: NIK utuh terisi penuh, NIK tersensor
    // menyumbang digit awalnya saja karena kolom NIK hanya menerima angka.
    final nikSeed = awalanNikReferensi(seed?['nik_lama']);
    nik = TextEditingController(text: pilih([edit?['nik'], nikSeed]));
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
    ketChip = chipKeterangan(rawNote, _kustom);
    gender = (edit?['jenis_kelamin'] ?? seed?['jenis_kelamin']) as String?;
    if (_drafAktif) {
      for (final c in [
        name,
        nik,
        birthPlace,
        birthDate,
        village,
        rt,
        rw,
        note
      ]) {
        c.addListener(() => _jadwalkanDraf(c.text));
      }
      // Offer a stored draft only over a truly empty form; a form opened
      // with a seed (reference row) or an initial name already carries data.
      final kosong = widget.seed == null &&
          (widget.initialName == null || widget.initialName!.trim().isEmpty);
      if (kosong) {
        _tawarkanDraf();
      } else {
        _draftReady = true;
      }
    }
  }

  void _pilihKeterangan(String? next) {
    setState(() {
      ketChip = next ?? keteranganNormal;
      if (ketChip == keteranganNormal) {
        note.clear();
        return;
      }
      if (ketChip == keteranganLainnya) {
        if (kodeKeterangan(note.text, _kustom) != null) note.clear();
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
    _draftTimer?.cancel();
    if (_drafAktif && _draftReady && !saving) unawaited(_simpanDraf());
    for (final c in [name, nik, birthPlace, birthDate, village, rt, rw, note]) {
      c.dispose();
    }
    noteFocus.dispose();
    super.dispose();
  }

  Future<void> save({bool lanjut = false}) async {
    if (saving) return;
    final store = widget.session.store;
    _draftTimer?.cancel();
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
            action: 'Tambahkan');
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
          'NIK yang sama sudah tercatat pada data warga berikut:\n${duplicates.map((r) => '• ${r['nama']} · ${formatRt(r['rt'])} · urutan ${positions[r['id']]} · ${waktuTampil(r['dibuat_pada'])}').join('\n')}',
          'Pilih Simpan Tetap jika kedua warga memang berbeda dan tercatat dengan NIK yang sama pada berkas.',
        ].join('\n\n');
        final decision = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text('NIK Sudah Terdaftar',
                        style: TextStyle(color: Colors.red.shade800)),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Text(isi),
                          const SizedBox(height: 12),
                          for (final row in duplicates)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: OutlinedButton.icon(
                                    onPressed: () =>
                                        Navigator.pop(ctx, 'open:${row['id']}'),
                                    icon:
                                        const Icon(Icons.open_in_new, size: 18),
                                    label: Text('Buka data ${row['nama']}'))),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, 'cancel'),
                          child: const Text('Batal')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, 'save'),
                          child: const Text('Simpan Tetap'))
                    ]));
        if (!mounted) return;
        if (decision != 'save') {
          setState(() => saving = false);
          _jadwalkanDraf('');
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
      await _selesaikanDraf(store);
      if (!mounted) return;
      final namaLabel =
          name.text.trim().isEmpty ? 'Data warga' : 'Data ${name.text.trim()}';
      feedback(
          context,
          wargaId == null
              ? '$namaLabel berhasil disimpan'
              : '$namaLabel berhasil diperbarui');
      if (lanjut) {
        FocusManager.instance.primaryFocus?.unfocus();
        final next = SurveyForm(
            session: widget.session,
            afterId: saved['id'] as int,
            chainCount: widget.chainCount + 1,
            seed: {
              'desa': nullableText(village.text) ?? widget.session.village,
              'rt': int.tryParse(rt.text),
              'rw': int.tryParse(rw.text),
            });
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => next));
        return;
      }
      FocusManager.instance.primaryFocus?.unfocus();
      final idBaru = saved['id'] as int;
      Navigator.pop(context, idBaru);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        _jadwalkanDraf('');
        feedback(context, e, error: true);
      }
    }
  }

  InputDecoration deco(String label, {String? hint, String? helper}) =>
      InputDecoration(labelText: label, hintText: hint, helperText: helper);

  @override
  Widget build(BuildContext context) => AppPage(
      session: widget.session,
      title: wargaId == null ? 'Warga Baru' : 'Ubah Data Warga',
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
                label: const Text('Simpan'))),
        const SizedBox(width: 10),
        Expanded(
            child: OutlinedButton(
                onPressed: saving ? null : () => save(lanjut: true),
                child: const Text('Simpan & Lanjut'))),
      ]),
      child: AbsorbPointer(
          absorbing: saving,
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                if (wargaId == null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                          'Orang ke-${widget.chainCount} sejak masuk form',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600))),
                const Text(
                    'Periksa dan isi sesuai dokumen kependudukan. Aplikasi tidak menilai kelayakan hak pilih warga.',
                    style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 12),
                Card(
                    child: ListTile(
                  dense: true,
                  title: const Text('Kelengkapan Data'),
                  subtitle: Text(statusIsianNik(nik.text)),
                  trailing: Text('${_persenKelengkapan.round()}%',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: forest)),
                )),
                const SizedBox(height: 18),
                TextField(
                    key: const ValueKey('f_nama'),
                    controller: name,
                    autofocus: widget.warga == null,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [HurufKapitalFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: deco('Nama *')),
                const SizedBox(height: 14),
                TextField(
                    key: const ValueKey('f_nik'),
                    controller: nik,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(16)
                    ],
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 20, letterSpacing: 2),
                    decoration: deco('NIK',
                        helper:
                            '16 digit angka sesuai KTP atau KK. Boleh dikosongkan bila belum ada')),
                if (nik.text.isNotEmpty)
                  ...periksaNik(
                          nik.text,
                          DateTime.tryParse(parseTanggal(birthDate.text) ?? ''),
                          gender,
                          prefixWilayah: widget.session.lokasi?.nikPrefix)
                      .map((w) => Notice(w, warning: true)),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                    key: const ValueKey('f_jk'),
                    value: gender, // ignore: deprecated_member_use
                    decoration: deco('Jenis Kelamin'),
                    items: const [
                      DropdownMenuItem(value: 'L', child: Text('Laki-laki')),
                      DropdownMenuItem(value: 'P', child: Text('Perempuan')),
                    ],
                    onChanged: (value) {
                      setState(() => gender = value);
                      _jadwalkanDraf('');
                    }),
                const SizedBox(height: 14),
                TextField(
                    key: const ValueKey('f_tempat_lahir'),
                    controller: birthPlace,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [HurufKapitalFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: deco('Tempat Lahir')),
                const SizedBox(height: 14),
                TextField(
                    key: const ValueKey('f_tgl_lahir'),
                    controller: birthDate,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.number,
                    inputFormatters: [TanggalInputFormatter()],
                    decoration: deco('Tanggal Lahir', hint: 'HH-BB-TTTT')),
                const SizedBox(height: 14),
                TextField(
                    key: const ValueKey('f_desa'),
                    controller: village,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [HurufKapitalFormatter()],
                    onChanged: (_) => setState(() {}),
                    decoration: deco('Desa / Dusun')),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: TextField(
                          key: const ValueKey('f_rt'),
                          controller: rt,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: deco('RT *'))),
                  const SizedBox(width: 14),
                  Expanded(
                      child: TextField(
                          key: const ValueKey('f_rw'),
                          controller: rw,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: deco('RW *')))
                ]),
                const SizedBox(height: 14),
                InputDecorator(
                    decoration: deco('Keterangan (opsional)'),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            ChoiceChip(
                                label: const Text('Normal'),
                                selected: ketChip == keteranganNormal,
                                onSelected: (_) =>
                                    _pilihKeterangan(keteranganNormal)),
                            for (final code in [
                              ...keteranganKode.keys,
                              ..._kustom.keys
                            ])
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
                          if (keteranganArti(ketChip, _kustom) != null) ...[
                            const SizedBox(height: 8),
                            Text(keteranganArti(ketChip, _kustom)!,
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
                      decoration: deco('Lainnya',
                          hint:
                              'Tulis keterangan. Tidak dipakai untuk penilaian atau pencarian')),
                ],
                const SizedBox(height: 18),
                const Notice(
                    'NIK boleh dikosongkan dan data tetap dapat disimpan. Peringatan format NIK hanya sebagai pengingat ketelitian.'),
              ])));
}

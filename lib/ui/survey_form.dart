import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/format.dart';
import '../core/nik.dart';
import 'common.dart';

class SurveyForm extends StatefulWidget {
  const SurveyForm(
      {super.key,
      required this.session,
      this.warga,
      this.seed,
      this.initialName,
      this.afterId});
  final Session session;
  final RecordMap? warga;
  final RecordMap? seed;
  final String? initialName;
  final int? afterId;
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
  final noteFocus = FocusNode(skipTraversal: true);
  bool saving = false;
  int? get wargaId => widget.warga?['id'] as int?;

  @override
  void initState() {
    super.initState();
    final edit = widget.warga;
    final seed = widget.seed;
    name = TextEditingController(
        text: '${edit?['nama'] ?? seed?['nama'] ?? widget.initialName ?? ''}');
    nik = TextEditingController(
        text: '${edit?['nik'] ?? ''}' == 'null' ? '' : '${edit?['nik'] ?? ''}');
    birthPlace = TextEditingController(
        text: '${edit?['tempat_lahir'] ?? seed?['tempat_lahir'] ?? ''}' == 'null'
            ? ''
            : '${edit?['tempat_lahir'] ?? seed?['tempat_lahir'] ?? ''}');
    birthDate = TextEditingController(
        text: edit?['tgl_lahir'] != null
            ? tanggalTampil(edit?['tgl_lahir'])
            : seed?['tgl_lahir_raw'] as String? ??
                tanggalTampil(seed?['tgl_lahir']));
    village = TextEditingController(
        text: '${edit?['desa'] ?? seed?['desa'] ?? widget.session.village}' ==
                'null'
            ? widget.session.village
            : '${edit?['desa'] ?? seed?['desa'] ?? widget.session.village}');
    rt = TextEditingController(text: '${edit?['rt'] ?? widget.session.rt}');
    rw = TextEditingController(text: '${edit?['rw'] ?? widget.session.rw}');
    note = TextEditingController(
        text: '${edit?['keterangan'] ?? ''}' == 'null'
            ? ''
            : '${edit?['keterangan'] ?? ''}');
    gender = (edit?['jenis_kelamin'] ?? seed?['jenis_kelamin']) as String?;
  }

  @override
  void dispose() {
    for (final c in [name, nik, birthPlace, birthDate, village, rt, rw, note]) {
      c.dispose();
    }
    noteFocus.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      if (name.text.trim().isEmpty) throw Exception('Nama wajib diisi');
      final iso =
          birthDate.text.trim().isEmpty ? null : parseTanggal(birthDate.text);
      if (birthDate.text.trim().isNotEmpty && iso == null) {
        throw Exception(
            'Tanggal harus DD-MM-YYYY, DD/MM/YYYY, atau DD.MM.YYYY');
      }
      final data = <String, Object?>{
        'nik': nullableText(nik.text),
        'nama': name.text,
        'jenis_kelamin': gender,
        'tempat_lahir': nullableText(birthPlace.text),
        'tgl_lahir': iso,
        'desa': nullableText(village.text),
        'rt': int.tryParse(rt.text),
        'rw': int.tryParse(rw.text),
        'keterangan': note.text,
        'sumber_input': widget.warga?['sumber_input'] ?? widget.session.source,
      };
      final warnings = periksaNik(
          nik.text.trim(), iso == null ? null : DateTime.parse(iso), gender);
      final duplicates = nik.text.trim().isEmpty
          ? <RecordMap>[]
          : await widget.session.store
              .duplicates(nik.text.trim(), exceptId: wargaId);
      if (warnings.isNotEmpty || duplicates.isNotEmpty) {
        if (!mounted) return;
        final positions = <int, int>{};
        for (final row in duplicates) {
          positions[row['id'] as int] = await widget.session.store
              .posisi(row['id'] as int, row['rw'] as int, row['rt'] as int);
        }
        if (!mounted) return;
        final duplicateText = duplicates.isEmpty
            ? ''
            : '\n\nNIK ini sudah dipakai oleh:\n${duplicates.map((r) => '• ${r['nama']} · RT ${r['rt']} · posisi ${positions[r['id']]} · ${waktuTampil(r['dibuat_pada'])}').join('\n')}\n\n';
        final decision = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
                    title: Text(
                        duplicates.isNotEmpty
                            ? 'Peringatan NIK duplikat'
                            : 'Periksa NIK',
                        style: TextStyle(
                            color: duplicates.isNotEmpty
                                ? Colors.red.shade800
                                : amber)),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          '${warnings.map((w) => '• $w').join('\n')}${duplicateText}Peringatan ini boleh diabaikan.'),
                      for (final row in duplicates)
                        TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, 'open:${row['id']}'),
                            child: Text('BUKA BARIS ITU · ${row['nama']}')),
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
      final saved = await widget.session.store
          .saveWarga(data, id: wargaId, afterId: widget.afterId);
      if (!mounted) return;
      feedback(context,
          wargaId == null ? 'Data tersimpan.' : 'Perubahan tersimpan.');
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
      title: wargaId == null ? 'Input satu orang' : 'Edit data',
      bottom: FilledButton.icon(
          onPressed: saving ? null : save,
          icon: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined),
          label: const Text('SIMPAN')),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            const Text(
                'Baca dan isi sesuai KK asli. Aplikasi tidak menilai kelayakan warga.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),
            TextField(
                controller: name,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
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
                decoration: deco('NIK', hint: 'boleh kosong')),
            if (nik.text.isNotEmpty)
              ...periksaNik(
                      nik.text,
                      DateTime.tryParse(parseTanggal(birthDate.text) ?? ''),
                      gender)
                  .map((w) => Notice(w, warning: true)),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
                initialValue: gender,
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
                decoration: deco('TEMPAT LAHIR')),
            const SizedBox(height: 14),
            TextField(
                controller: birthDate,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.datetime,
                decoration: deco('TANGGAL LAHIR', hint: 'DD-MM-YYYY')),
            const SizedBox(height: 14),
            TextField(
                controller: village,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                decoration: deco('DESA / DUSUN')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: rt,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: deco('RT'))),
              const SizedBox(width: 14),
              Expanded(
                  child: TextField(
                      controller: rw,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: deco('RW')))
            ]),
            const SizedBox(height: 14),
            TextField(
                controller: note,
                focusNode: noteFocus,
                maxLines: 3,
                decoration: deco('KETERANGAN (opsional)',
                    hint:
                        'Teks bebas, tidak dipakai untuk penilaian atau pencarian')),
            const SizedBox(height: 18),
            const Notice(
                'NIK boleh kosong. Bila diisi, panjang selain 16 digit hanya peringatan dan tetap bisa disimpan.',
                warning: true),
          ]));
}

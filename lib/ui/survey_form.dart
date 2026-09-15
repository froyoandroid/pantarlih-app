import 'package:flutter/material.dart';
import '../core/format.dart';
import '../core/nik.dart';
import '../data/store.dart';
import 'common.dart';
import 'search_screen.dart';

class SurveyForm extends StatefulWidget {
  const SurveyForm(
      {super.key,
      required this.session,
      this.legacy,
      this.survey,
      this.initialName});
  final Session session;
  final RecordMap? legacy, survey;
  final String? initialName;
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
  RecordMap? linkedLegacy;
  final noteFocus = FocusNode(skipTraversal: true);
  bool saving = false;
  RecordMap? get source => widget.survey ?? widget.legacy;
  int? get surveyId => widget.survey?['id'] as int?;
  int? get legacyId =>
      widget.survey?['id_lama'] as int? ?? widget.legacy?['id'] as int?;
  @override
  void initState() {
    super.initState();
    final row = source;
    linkedLegacy = widget.legacy;
    if (linkedLegacy == null && legacyId != null) {
      widget.session.store.legacy(legacyId!).then((r) {
        if (mounted) setState(() => linkedLegacy = r);
      });
    }
    name = TextEditingController(
        text: '${row?['nama'] ?? widget.initialName ?? ''}');
    nik = TextEditingController(
        text: '${row?['nik'] ?? ''}' == 'null' ? '' : '${row?['nik'] ?? ''}');
    birthPlace = TextEditingController(
        text: '${row?['tempat_lahir'] ?? ''}' == 'null'
            ? ''
            : '${row?['tempat_lahir'] ?? ''}');
    birthDate = TextEditingController(
        text: row?['tgl_lahir_raw'] as String? ??
            tanggalTampil(row?['tgl_lahir']));
    village = TextEditingController(
        text: '${row?['desa'] ?? widget.session.village}' == 'null'
            ? widget.session.village
            : '${row?['desa'] ?? widget.session.village}');
    rt = TextEditingController(
        text: '${widget.survey?['rt_baru'] ?? widget.session.rt}');
    rw = TextEditingController(
        text: '${widget.survey?['rw_baru'] ?? widget.session.rw}');
    note = TextEditingController(
        text: '${row?['keterangan'] ?? ''}' == 'null'
            ? ''
            : '${row?['keterangan'] ?? ''}');
    gender = row?['jenis_kelamin'] as String?;
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
      if (!RegExp(r'^\d{16}$').hasMatch(nik.text.trim())) {
        throw AppException('NIK harus 16 digit angka');
      }
      if (name.text.trim().isEmpty) throw AppException('Nama wajib diisi');
      final iso =
          birthDate.text.trim().isEmpty ? null : parseTanggal(birthDate.text);
      if (birthDate.text.trim().isNotEmpty && iso == null) {
        throw AppException(
            'Tanggal harus DD-MM-YYYY, DD/MM/YYYY, atau DD.MM.YYYY');
      }
      final data = <String, Object?>{
        'nik': nik.text.trim(),
        'nama': name.text,
        'jenis_kelamin': gender,
        'tempat_lahir': nullableText(birthPlace.text),
        'tgl_lahir': iso,
        'desa': nullableText(village.text),
        'rt_baru': int.tryParse(rt.text),
        'rw_baru': int.tryParse(rw.text),
        'keterangan': note.text,
        'sumber_input': widget.survey?['sumber_input'] ?? widget.session.source,
      };
      final warnings = periksaNik(
          nik.text.trim(),
          iso == null ? null : DateTime.parse(iso),
          gender,
          linkedLegacy?['nik_prefix'] as String?);
      final duplicates = await widget.session.store
          .duplicates(nik.text.trim(), exceptId: surveyId);
      if (warnings.isNotEmpty || duplicates.isNotEmpty) {
        if (!mounted) return;
        final duplicateText = duplicates.isEmpty
            ? ''
            : '\n\nNIK ini sudah dipakai oleh:\n${duplicates.map((r) => '• ${r['nama']} · RT ${r['rt_baru']}/RW ${r['rw_baru']} · ${waktuTampil(r['dibuat_pada'])}').join('\n')}\n\n';
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
                          '${warnings.map((w) => '• $w').join('\n')}${duplicateText}Prefix / tanggal yang berbeda dan NIK duplikat tetap boleh disimpan.'),
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
                .survey(int.parse(decision!.split(':').last));
            if (!mounted || other == null) return;
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        SurveyForm(session: widget.session, survey: other)));
          }
          return;
        }
      }
      await widget.session.store
          .saveSurvey(data, id: surveyId, oldId: legacyId);
      if (!mounted) return;
      feedback(context,
          surveyId == null ? 'Data tersimpan.' : 'Perubahan tersimpan.');
      Navigator.pop(context);
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
      title: surveyId == null ? 'Input satu orang' : 'Edit data survei',
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
            if (legacyId != null)
              Notice(
                  'Terhubung dengan data lama: ${linkedLegacy?['nama'] ?? widget.survey?['nama']} · No. ${linkedLegacy?['urut_asli'] ?? '—'}',
                  icon: Icons.link),
            if (linkedLegacy != null &&
                (intValue(rt.text) != linkedLegacy!['rt'] ||
                    intValue(rw.text) != linkedLegacy!['rw']))
              Notice(
                  'KONFLIK DOMISILI · Data lama RT ${linkedLegacy!['rt']} / RW ${linkedLegacy!['rw']}. Ekspor mengikuti RT ${rt.text} / RW ${rw.text}. Pastikan kondisi sesuai survei.',
                  warning: true),
            const Text(
                'Baca dan isi sesuai KK asli. Aplikasi tidak menilai kelayakan warga.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),
            TextField(
                controller: name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.characters,
                decoration: deco('NAMA *')),
            const SizedBox(height: 14),
            TextField(
                controller: nik,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 20, letterSpacing: 2),
                decoration: deco('NIK *', hint: '16 digit angka')),
            if (nik.text.isNotEmpty)
              ...periksaNik(
                      nik.text,
                      DateTime.tryParse(parseTanggal(birthDate.text) ?? ''),
                      gender,
                      linkedLegacy?['nik_prefix'] as String?)
                  .map((w) => Notice(w,
                      warning: true,
                      error: !RegExp(r'^\d{16}$').hasMatch(nik.text))),
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
                textCapitalization: TextCapitalization.characters,
                decoration: deco('DESA / DUSUN')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: rt,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: deco('RT BARU'))),
              const SizedBox(width: 14),
              Expanded(
                  child: TextField(
                      controller: rw,
                      onChanged: (_) => setState(() {}),
                      keyboardType: TextInputType.number,
                      decoration: deco('RW BARU')))
            ]),
            const SizedBox(height: 14),
            TextField(
                controller: note,
                focusNode: noteFocus,
                maxLines: 3,
                decoration: deco('KETERANGAN (opsional)',
                    hint:
                        'Teks bebas; tidak dipakai untuk penilaian atau pencarian')),
            const SizedBox(height: 18),
            const Notice(
                'NIK harus tepat 16 digit agar bisa disimpan. Perbedaan prefix wilayah atau tanggal lahir hanya peringatan.',
                warning: true),
            if (surveyId != null && legacyId != null)
              OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final unlink = await confirm(context, 'Lepas tautan?',
                              'Baris survei tetap ada, tetapi kembali menjadi warga baru tanpa induk. Data lama muncul lagi di daftar sisa.',
                              action: 'LEPAS TAUTAN', dangerous: true);
                          if (!unlink || !context.mounted) {
                            return;
                          }
                          try {
                            await widget.session.store.relink(surveyId!, null);
                            if (context.mounted) {
                              feedback(context, 'Tautan dilepas.');
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              feedback(context, e, error: true);
                            }
                          }
                        },
                  icon: const Icon(Icons.link_off),
                  label: const Text('LEPAS TAUTAN')),
            if (surveyId != null)
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              if (!await confirm(context, 'Tautkan ulang?',
                                  'Perubahan form yang belum disimpan tidak ikut diterapkan. Pilih data lama yang benar; isi survei tetap sesuai KK.',
                                  action: 'PILIH DATA LAMA')) {
                                return;
                              }
                              if (!context.mounted) return;
                              final chosen = await Navigator.push<RecordMap>(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => SearchScreen(
                                          session: widget.session,
                                          pickOnly: true,
                                          currentSurveyId: surveyId)));
                              if (chosen == null) {
                                return;
                              }
                              try {
                                await widget.session.store
                                    .relink(surveyId!, chosen['id'] as int);
                                if (context.mounted) {
                                  feedback(context, 'Tautan diperbarui.');
                                  Navigator.pop(context);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  feedback(context, e, error: true);
                                }
                              }
                            },
                      icon: const Icon(Icons.link),
                      label: const Text('TAUTKAN ULANG'))),
          ]));
}

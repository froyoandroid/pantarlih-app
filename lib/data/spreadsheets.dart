import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../core/format.dart';
import '../core/nama.dart';
import '../core/nik.dart';
import 'schema.dart';
import 'store.dart';

const importFields = <String, String>{
  'urut_asli': 'Nomor urut',
  'nama': 'Nama',
  'nik_lama': 'NIK lama',
  'jenis_kelamin': 'Jenis kelamin',
  'tempat_lahir': 'Tempat lahir',
  'tgl_lahir_raw': 'Tanggal lahir',
  'desa': 'Desa / dusun',
  'rt': 'RT',
  'rw': 'RW',
};
const dpsHeaders = [
  'NO',
  'NAMA',
  'NIK',
  'JENIS KELAMIN',
  'TEMPAT LAHIR',
  'TANGGAL LAHIR',
  'DESA',
  'RT',
  'RW',
  'KETERANGAN'
];

String slugWilayah(String nama) {
  final slug = nama
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) return '';
  return slug.length <= 24 ? slug : slug.substring(0, 24);
}

String kodeBerkasEkspor(RecordMap? lokasi) {
  if (lokasi == null || intValue(lokasi['manual']) == 1) return 'TANPALOKASI';
  final kode = '${lokasi['kode'] ?? ''}'.replaceAll('.', '');
  return kode.isEmpty ? 'TANPALOKASI' : kode;
}

String namaBerkasBagian(List<String> parts) =>
    parts.where((p) => p.isNotEmpty).join('_');

class ImportPrep {
  ImportPrep(this.records, this.skipped);
  final List<RecordMap> records;
  final List<RecordMap> skipped;
}

String cellText(Data? cell) {
  final value = cell?.value;
  if (value == null) return '';
  if (value is DateCellValue) {
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  }
  if (value is DateTimeCellValue) {
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
  }
  if (value is DoubleCellValue && value.value == value.value.roundToDouble()) {
    return value.value.toInt().toString();
  }
  return value.toString();
}

abstract class TabularSource {
  String get name;
  Uint8List get bytes;
  List<String> get sheets;
  List<List<String>> rows(String sheet);

  Map<String, int> suggestedMapping(String sheet) {
    final values = rows(sheet);
    final header = values.isEmpty
        ? <String>[]
        : values.first.map((s) => s.trim().toUpperCase()).toList();
    const aliases = <String, List<String>>{
      'urut_asli': ['NO', 'NOMOR', 'NOMOR URUT'],
      'nama': ['NAMA', 'NAMA PEMILIH'],
      'nik_lama': ['NIK'],
      'jenis_kelamin': ['JENIS KELAMIN', 'JK'],
      'tempat_lahir': ['TEMPAT LAHIR'],
      'tgl_lahir_raw': ['TANGGAL LAHIR', 'TGL LAHIR'],
      'desa': ['DESA', 'DUSUN'],
      'rt': ['RT'],
      'rw': ['RW'],
    };
    return {
      for (final field in importFields.keys)
        // Unmapped field names degrade to not-found (-1) instead of crashing.
        field:
            header.indexWhere((h) => (aliases[field] ?? const []).contains(h))
    };
  }

  ImportPrep prepare(String sheet, Map<String, int> mapping, int startRow,
      int confirmedRt, int defaultRw,
      {bool useRowRt = false}) {
    if (confirmedRt <= 0 || defaultRw <= 0) {
      throw AppException('Konfirmasi RT dan RW wajib diisi.');
    }
    if ((mapping['nama'] ?? -1) < 0) {
      throw AppException('Petakan kolom Nama terlebih dahulu.');
    }
    final selected = mapping.values.where((v) => v >= 0).toList();
    if (selected.toSet().length != selected.length) {
      throw AppException('Satu kolom tidak boleh dipetakan ke dua field.');
    }
    final source = rows(sheet);
    final records = <RecordMap>[];
    final skipped = <RecordMap>[];
    if (startRow < 1 || startRow > source.length) {
      throw AppException('Baris awal tidak valid.');
    }
    void skip(int line, List<String> cells, String reason) {
      skipped.add({
        'baris': line,
        'cells': cells,
        'alasan': reason,
      });
    }

    for (var i = startRow - 1; i < source.length; i++) {
      final row = source[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      String get(String key) {
        final column = mapping[key] ?? -1;
        return column < 0 || column >= row.length ? '' : row[column];
      }

      final name = get('nama');
      final order = int.tryParse(get('urut_asli').trim());
      final line = i + 1;
      if (name.trim().isEmpty) {
        skip(line, row, 'Nama kosong');
        continue;
      }
      final rowRt = int.tryParse(get('rt').trim());
      final rowRw = int.tryParse(get('rw').trim());
      if (!useRowRt && get('rt').trim().isNotEmpty && rowRt != confirmedRt) {
        skip(line, row,
            'RT pada file (${get('rt')}) berbeda dari konfirmasi RT $confirmedRt');
        continue;
      }
      if (useRowRt && (rowRt == null || rowRt <= 0)) {
        skip(line, row, 'RT tidak valid');
        continue;
      }
      if (get('rw').trim().isNotEmpty && (rowRw == null || rowRw <= 0)) {
        skip(line, row, 'RW tidak valid');
        continue;
      }
      final rawDate = get('tgl_lahir_raw');
      final date = parseTanggal(rawDate);
      final rawGender = get('jenis_kelamin').trim().toUpperCase();
      final gender = ['L', 'LAKI-LAKI', 'LAKI LAKI'].contains(rawGender)
          ? 'L'
          : ['P', 'PEREMPUAN'].contains(rawGender)
              ? 'P'
              : null;
      records.add({
        'urut_asli': order != null && order > 0 ? order : line,
        'nama': name,
        'nama_norm': normalisasiNama(name),
        'nik_lama': nullableText(get('nik_lama')),
        'jenis_kelamin': gender,
        'tempat_lahir': nullableText(get('tempat_lahir')),
        'tgl_lahir': date,
        'tgl_lahir_raw': rawDate,
        'desa': nullableText(get('desa')),
        'rt': useRowRt ? rowRt : confirmedRt,
        'rw': rowRw ?? defaultRw,
        'sumber_file': nameForStorage,
        'sumber_baris': line,
      });
    }
    final attempted = records.length + skipped.length;
    if (attempted == 0) {
      throw AppException('Tidak ada data pada sheet yang dipilih.');
    }
    if (skipped.length * 2 > attempted) {
      throw AppException(
          'Lebih dari setengah baris ditolak (${skipped.length} dari $attempted). Periksa pemetaan kolom.');
    }
    return ImportPrep(records, skipped);
  }

  String get nameForStorage => name.split(RegExp(r'[/\\]')).last;

  Future<void> archiveAndImport(AppStore store, String sheet,
      List<RecordMap> records, Map<String, int> mapping, int startRow, int rt,
      {List<RecordMap> skipped = const []}) async {
    // Unique archive directory keeps repeated attempts and original basename intact.
    final batch =
        '${fileStamp()}_${sheet.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    for (final stage in ['raw', 'parsed', 'ready']) {
      await Directory('${store.root.path}/import/$stage/$batch')
          .create(recursive: true);
    }
    await File('${store.root.path}/import/raw/$batch/$nameForStorage')
        .writeAsBytes(bytes, flush: true);
    final raw = rows(sheet);
    final parsed = <RecordMap>[
      {
        'sheet': sheet,
        'mapping': mapping,
        'start_row': startRow,
        'rt_konfirmasi': rt
      },
      for (var i = 0; i < raw.length; i++)
        {'sheet': sheet, 'baris': i + 1, 'cells': raw[i]},
    ];
    await File('${store.root.path}/import/parsed/$batch/$nameForStorage.jsonl')
        .writeAsString('${parsed.map(jsonEncode).join('\n')}\n', flush: true);
    await File('${store.root.path}/import/ready/$batch/$nameForStorage.jsonl')
        .writeAsString(
            records.isEmpty ? '' : '${records.map(jsonEncode).join('\n')}\n',
            flush: true);
    await File('${store.root.path}/import/ready/$batch/dilewati.jsonl')
        .writeAsString(
            skipped.isEmpty ? '' : '${skipped.map(jsonEncode).join('\n')}\n',
            flush: true);
    if (records.isNotEmpty) {
      await store.importRows(records, nameForStorage);
    }
  }
}

class WorkbookSource extends TabularSource {
  /// Sync constructor for small in-memory fixtures; the UI path uses open().
  WorkbookSource(this.name, this.bytes) : workbook = _decodeWorkbook(bytes);
  WorkbookSource._decoded(this.name, this.bytes, this.workbook);

  /// Decodes on a background isolate: unzipping and re-parsing a workbook
  /// blocks the UI thread for seconds on multi-MB files.
  static Future<WorkbookSource> open(String name, Uint8List bytes) async =>
      WorkbookSource._decoded(
          name, bytes, await compute(_decodeWorkbook, bytes));
  @override
  final String name;
  @override
  final Uint8List bytes;
  final Excel workbook;
  @override
  List<String> get sheets => workbook.tables.keys.toList();
  @override
  List<List<String>> rows(String sheet) => workbook.tables[sheet]!.rows
      .map((row) => row.map(cellText).toList())
      .toList();
}

class CsvSource extends TabularSource {
  /// Sync constructor for small in-memory fixtures; the UI path uses open().
  CsvSource(this.name, this.bytes) : table = parseCsv(decodeCsvBytes(bytes));
  CsvSource._parsed(this.name, this.bytes, this.table);

  /// Build from an already-decoded table, used when the user picked an
  /// explicit text encoding for the file.
  factory CsvSource.fromTable(
          String name, Uint8List bytes, List<List<String>> table) =>
      CsvSource._parsed(name, bytes, table);
  static Future<CsvSource> open(String name, Uint8List bytes) async =>
      CsvSource._parsed(name, bytes, await compute(_csvTable, bytes));
  @override
  final String name;
  @override
  final Uint8List bytes;
  final List<List<String>> table;
  @override
  List<String> get sheets => const ['CSV'];
  @override
  List<List<String>> rows(String sheet) => table;
}

List<List<String>> _csvTable(Uint8List bytes) =>
    parseCsv(decodeCsvBytes(bytes));

bool csvBerkas(String name) => name.toLowerCase().endsWith('.csv');

Future<TabularSource> openTabular(String name, Uint8List bytes) async {
  if (csvBerkas(name)) return CsvSource.open(name, bytes);
  return WorkbookSource.open(name, bytes);
}

String decodeCsvBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

List<List<String>> parseCsv(String text) {
  final first = text
      .split(RegExp(r'\r\n|\n|\r'))
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
  final comma = _countUnquoted(first, ',');
  final semi = _countUnquoted(first, ';');
  final separator = semi > comma ? ';' : ',';
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == separator) {
      row.add(field.toString());
      field = StringBuffer();
    } else if (ch == '\n' ||
        (ch == '\r' && (i + 1 >= text.length || text[i + 1] != '\n'))) {
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((c) => c.isNotEmpty)) rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (quoted || field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((c) => c.isNotEmpty)) rows.add(row);
  }
  return rows;
}

int _countUnquoted(String line, String mark) {
  var count = 0;
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted && ch == mark) {
      count++;
    }
  }
  return count;
}

Excel _decodeWorkbook(Uint8List bytes) {
  // openpyxl and other conforming writers use package-absolute relationship
  // targets. excel 4.x incorrectly prefixes those targets with "xl/" again.
  // Normalize ONLY the in-memory parsing copy; archive the original bytes.
  final archive = ZipDecoder().decodeBytes(bytes);
  const relationshipPath = 'xl/_rels/workbook.xml.rels';
  final rel = archive.findFile(relationshipPath);
  if (rel == null) return Excel.decodeBytes(bytes);
  final doc = XmlDocument.parse(utf8.decode(rel.content as List<int>));
  for (final element in doc.findAllElements('Relationship')) {
    final target = element.getAttribute('Target');
    if (target != null && target.startsWith('/xl/')) {
      element.setAttribute('Target', target.substring(4));
    }
  }
  final replacement = utf8.encode(doc.toXmlString());
  final normalized = Archive();
  for (final file in archive.files) {
    if (file.name == relationshipPath) {
      normalized.addFile(
          ArchiveFile(relationshipPath, replacement.length, replacement));
    } else if (file.name.startsWith('xl/worksheets/') &&
        file.name.endsWith('.xml')) {
      final worksheet =
          XmlDocument.parse(utf8.decode(file.content as List<int>));
      for (final cell in worksheet.findAllElements('c')) {
        if (cell.getAttribute('t') != 'inlineStr') continue;
        final textNodes = cell.findAllElements('t');
        if (textNodes.isNotEmpty) continue;
        final isNode = cell.findElements('is');
        if (isNode.isEmpty) {
          cell.children
              .add(XmlElement(XmlName('is'), [], [XmlElement(XmlName('t'))]));
        } else {
          isNode.first.children.add(XmlElement(XmlName('t')));
        }
      }
      final xml = utf8.encode(worksheet.toXmlString());
      normalized.addFile(ArchiveFile(file.name, xml.length, xml));
    } else {
      normalized.addFile(file);
    }
  }
  final encoded = ZipEncoder().encode(normalized);
  if (encoded == null) {
    throw AppException(
        'Berkas spreadsheet tidak dapat dibaca. Simpan ulang berkas dari Excel, lalu coba lagi.');
  }
  return Excel.decodeBytes(encoded);
}

class ExportService {
  ExportService(this.store);
  final AppStore store;

  List<Object?> dpsRow(RecordMap row, int number) => [
        number,
        row['nama'],
        row['nik'],
        row['jenis_kelamin'] == null ? null : jkTampil(row['jenis_kelamin']),
        row['tempat_lahir'],
        row['tgl_lahir'] == null ? null : tanggalTampil(row['tgl_lahir']),
        row['desa'],
        row['rt'],
        row['rw'],
        row['keterangan'],
      ];

  void _sheet(
      Excel book, String name, List<String> headers, List<List<Object?>> rows,
      {List<List<Object?>> kop = const []}) {
    final sheet = book[name];
    CellValue? value(Object? raw) => raw == null
        ? null
        : raw is int
            ? IntCellValue(raw)
            : TextCellValue(raw.toString());
    for (final row in kop) {
      sheet.appendRow(row.map(value).toList());
    }
    final headerRow = kop.length;
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(value).toList());
    }
    for (var i = 0; i < headers.length; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: headerRow))
              .cellStyle =
          CellStyle(
              bold: true,
              backgroundColorHex: ExcelColor.fromHexString('#173F35'),
              fontColorHex: ExcelColor.white);
      sheet.setColumnWidth(
          i,
          i == 1 || i == 9
              ? 30
              : i == 2
                  ? 24
                  : 18);
    }
  }

  List<List<Object?>> _kop(RecordMap? lokasi, int rw, int rt) => [
        ['Provinsi', lokasi?['nama_prov'] ?? ''],
        ['Kabupaten/Kota', lokasi?['nama_kab'] ?? ''],
        ['Kecamatan', lokasi?['nama_kec'] ?? ''],
        ['Desa/Kelurahan', lokasi?['nama_desa'] ?? ''],
        [
          'RT / RW',
          '${rt.toString().padLeft(2, '0')} / ${rw.toString().padLeft(2, '0')}'
        ],
        [
          'Kode wilayah',
          intValue(lokasi?['manual']) == 1
              ? '(manual)'
              : (lokasi?['kode'] ?? 'TANPALOKASI')
        ],
      ];

  (List<String>, List<List<Object?>>) _info(
      {required RecordMap? lokasi,
      required int rw,
      int? rt,
      required int jumlah,
      required int tanpaNik}) {
    final kode =
        intValue(lokasi?['manual']) == 1 ? '(manual)' : (lokasi?['kode'] ?? '');
    return (
      ['Label', 'Nilai'],
      [
        ['Provinsi', lokasi?['nama_prov'] ?? ''],
        ['Kabupaten/Kota', lokasi?['nama_kab'] ?? ''],
        ['Kecamatan', lokasi?['nama_kec'] ?? ''],
        ['Desa/Kelurahan', lokasi?['nama_desa'] ?? ''],
        ['Kode wilayah', kode],
        ['RT', rt == null ? '' : rt.toString().padLeft(2, '0')],
        ['RW', rw.toString().padLeft(2, '0')],
        ['Jumlah warga', jumlah],
        ['Tanpa NIK', tanpaNik],
        ['Diekspor pada', waktuTampil(timestamp())],
        ['Sumber kode wilayah', lokasi?['sumber_versi'] ?? ''],
        ['Versi aplikasi', appVersion],
      ]
    );
  }

  Future<List<File>> generate(
      {required int rw,
      int? rt,
      bool combined = false,
      bool automatic = false,
      bool kop = false}) async {
    final rts = rt == null ? await store.rtList(rw) : [rt];
    final date = timestamp().substring(0, 10);
    final kind = automatic ? 'auto' : 'manual';
    var stamp = fileStamp();
    var target = Directory('${store.root.path}/export/$kind/$stamp');
    var extra = 1;
    while (await target.exists()) {
      target = Directory('${store.root.path}/export/$kind/${stamp}_$extra');
      extra++;
    }
    await target.create(recursive: true);
    final files = <File>[];
    final metadata = <RecordMap>[];
    final lokasiRow = (await store.activeLokasi())?.toRow();
    Future<void> write(
        String name, Map<String, (List<String>, List<List<Object?>>)> sheets,
        {List<List<Object?>> kopRows = const []}) async {
      final book = Excel.createExcel();
      final initial = book.getDefaultSheet();
      var first = true;
      for (final entry in sheets.entries) {
        _sheet(book, entry.key, entry.value.$1, entry.value.$2,
            kop: first ? kopRows : const []);
        first = false;
      }
      if (initial != null && !sheets.containsKey(initial)) book.delete(initial);
      if (sheets.isEmpty) _sheet(book, 'DPS', dpsHeaders, []);
      book.setDefaultSheet(sheets.isEmpty ? 'DPS' : sheets.keys.first);
      final bytes = book.encode();
      if (bytes == null) throw AppException('Gagal membuat spreadsheet.');
      final file =
          await File('${target.path}/$name').writeAsBytes(bytes, flush: true);
      files.add(file);
      metadata.add({
        'nama_file': file.path,
        'jumlah_baris': sheets.values.fold<int>(0, (n, s) => n + s.$2.length),
        'rt': rts
      });
    }

    String slugFrom(List<RecordMap> warga) => slugWilayah(
        '${lokasiRow?['nama_desa'] ?? (warga.isEmpty ? '' : warga.first['desa'] ?? '')}');
    final code = kodeBerkasEkspor(lokasiRow);
    final rwPad = rw.toString().padLeft(2, '0');

    final dpsSheets = <String, (List<String>, List<List<Object?>>)>{};
    var combinedRows = 0;
    var combinedMissing = 0;
    for (final selectedRt in rts) {
      final warga = await store.exportWarga(selectedRt, rw);
      final rows = [
        for (var i = 0; i < warga.length; i++) dpsRow(warga[i], i + 1)
      ];
      combinedRows += rows.length;
      combinedMissing +=
          warga.where((r) => r['nik'] == null || '${r['nik']}'.isEmpty).length;
      final info = _info(
          lokasi: lokasiRow,
          rw: rw,
          rt: selectedRt,
          jumlah: rows.length,
          tanpaNik: warga
              .where((r) => r['nik'] == null || '${r['nik']}'.isEmpty)
              .length);
      final kopRows =
          kop ? _kop(lokasiRow, rw, selectedRt) : const <List<Object?>>[];
      if (combined) {
        dpsSheets['RT $selectedRt'] = (dpsHeaders, rows);
      } else {
        await write(
            '${namaBerkasBagian([
                  'DPS',
                  code,
                  slugFrom(warga),
                  'RT${selectedRt.toString().padLeft(2, '0')}',
                  'RW$rwPad',
                  date
                ])}.xlsx',
            {'RT $selectedRt': (dpsHeaders, rows), 'INFO': info},
            kopRows: kopRows);
      }
    }
    if (combined) {
      final info = _info(
          lokasi: lokasiRow,
          rw: rw,
          rt: null,
          jumlah: combinedRows,
          tanpaNik: combinedMissing);
      await write(
          '${namaBerkasBagian(['DPS_GABUNGAN', code, 'RW$rwPad', date])}.xlsx',
          {...dpsSheets, 'INFO': info},
          kopRows: kop && rts.isNotEmpty
              ? _kop(lokasiRow, rw, rts.first)
              : const []);
    }
    if (automatic) {
      await store.recordExport(metadata, rw, rts);
      await _rotateAutoExports();
      return files;
    }
    final duplicateRows = await store.duplicateRows(rw: rw, rt: rt);
    final duplicateNames = await store.duplicateNameRows(rw: rw, rt: rt);
    final missing = await store.tanpaNik(rw: rw, rt: rt);
    // One wargaRt query per (rw, rt) group instead of one query per row.
    final nomorDari =
        await _posisiPeta([...duplicateRows, ...duplicateNames, ...missing]);
    int nomor(RecordMap row) => nomorDari[row['id'] as int] ?? 0;
    await write('${namaBerkasBagian(['DUPLIKAT_NIK', code, date])}.xlsx', {
      'DUPLIKAT NIK': (
        dpsHeaders,
        [for (final row in duplicateRows) dpsRow(row, nomor(row))],
      ),
      'INFO': _info(
          lokasi: lokasiRow,
          rw: rw,
          rt: rt,
          jumlah: duplicateRows.length,
          tanpaNik: 0),
    });
    await write('${namaBerkasBagian(['DUPLIKAT_NAMA', code, date])}.xlsx', {
      'DUPLIKAT NAMA': (
        dpsHeaders,
        [for (final row in duplicateNames) dpsRow(row, nomor(row))],
      ),
      'INFO': _info(
          lokasi: lokasiRow,
          rw: rw,
          rt: rt,
          jumlah: duplicateNames.length,
          tanpaNik: 0),
    });
    await write('${namaBerkasBagian(['TANPA_NIK', code, date])}.xlsx', {
      'TANPA NIK': (
        dpsHeaders,
        [for (final row in missing) dpsRow(row, nomor(row))],
      ),
      'INFO': _info(
          lokasi: lokasiRow,
          rw: rw,
          rt: rt,
          jumlah: missing.length,
          tanpaNik: missing.length),
    });
    await store.recordExport(metadata, rw, rts);
    return files;
  }

  /// Position (1-based) of every given row in its RT list, computed with
  /// one wargaRt query per (rw, rt) group instead of one query per row.
  Future<Map<int, int>> _posisiPeta(List<RecordMap> rows) async {
    final groups = <(int, int)>{};
    for (final row in rows) {
      groups.add((row['rw'] as int, row['rt'] as int));
    }
    final posisi = <int, int>{};
    for (final (rw, rt) in groups) {
      final list = await store.wargaRt(rw, rt);
      for (var i = 0; i < list.length; i++) {
        posisi[list[i]['id'] as int] = i + 1;
      }
    }
    return posisi;
  }

  Future<void> _rotateAutoExports({int keep = 10}) async {
    final dir = Directory('${store.root.path}/export/auto');
    if (!await dir.exists()) return;
    final folders = await dir
        .list()
        .where((e) => e is Directory)
        .cast<Directory>()
        .toList();
    folders.sort((a, b) => b.path.compareTo(a.path));
    for (final old in folders.skip(keep)) {
      await old.delete(recursive: true);
    }
  }
}

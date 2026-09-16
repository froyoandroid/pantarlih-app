import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';
import '../core/format.dart';
import '../core/nama.dart';
import '../core/nik.dart';
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

class WorkbookSource {
  WorkbookSource(this.name, this.bytes) : workbook = _decodeWorkbook(bytes);
  final String name;
  final Uint8List bytes;
  final Excel workbook;
  List<String> get sheets => workbook.tables.keys.toList();
  List<List<String>> rows(String sheet) => workbook.tables[sheet]!.rows
      .map((row) => row.map(cellText).toList())
      .toList();

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
        field: header.indexWhere((h) => aliases[field]!.contains(h))
    };
  }

  List<RecordMap> prepare(String sheet, Map<String, int> mapping, int startRow,
      int confirmedRt, int defaultRw,
      {bool useRowRt = false}) {
    if (confirmedRt <= 0 || defaultRw <= 0) {
      throw AppException('Konfirmasi RT dan RW wajib diisi.');
    }
    if ((mapping['nama'] ?? -1) < 0 || (mapping['urut_asli'] ?? -1) < 0) {
      throw AppException('Petakan kolom Nama dan Nomor urut terlebih dahulu.');
    }
    final selected = mapping.values.where((v) => v >= 0).toList();
    if (selected.toSet().length != selected.length) {
      throw AppException('Satu kolom tidak boleh dipetakan ke dua field.');
    }
    final source = rows(sheet);
    final records = <RecordMap>[];
    if (startRow < 1 || startRow > source.length) {
      throw AppException('Baris awal tidak valid.');
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
      if (name.trim().isEmpty || order == null || order <= 0) {
        throw AppException(
            'Sheet $sheet baris ${i + 1}: nama / nomor urut tidak valid. '
            'Periksa baris awal dan pemetaan. Tidak ada baris yang diabaikan diam-diam.');
      }
      final rowRt = int.tryParse(get('rt').trim());
      final rowRw = int.tryParse(get('rw').trim());
      if (!useRowRt && get('rt').trim().isNotEmpty && rowRt != confirmedRt) {
        throw AppException(
            'Baris ${i + 1}: RT pada file (${get('rt')}) berbeda dari konfirmasi '
            'RT $confirmedRt. Koreksi konfirmasi atau aktifkan RT per baris.');
      }
      if (useRowRt && (rowRt == null || rowRt <= 0)) {
        throw AppException('RT baris ${i + 1} tidak valid.');
      }
      if (get('rw').trim().isNotEmpty && (rowRw == null || rowRw <= 0)) {
        throw AppException('RW baris ${i + 1} tidak valid.');
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
        'urut_asli': order,
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
        'sumber_baris': i + 1,
      });
    }
    if (records.isEmpty) {
      throw AppException('Tidak ada data pada sheet yang dipilih.');
    }
    return records;
  }

  String get nameForStorage => name.split(RegExp(r'[/\\]')).last;

  Future<void> archiveAndImport(
      AppStore store,
      String sheet,
      List<RecordMap> records,
      Map<String, int> mapping,
      int startRow,
      int rt) async {
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
        .writeAsString('${records.map(jsonEncode).join('\n')}\n', flush: true);
    await store.importRows(records, nameForStorage);
  }
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
  return Excel.decodeBytes(ZipEncoder().encode(normalized)!);
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
      Excel book, String name, List<String> headers, List<List<Object?>> rows) {
    final sheet = book[name];
    CellValue? value(Object? raw) => raw == null
        ? null
        : raw is int
            ? IntCellValue(raw)
            : TextCellValue(raw.toString());
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(value).toList());
    }
    for (var i = 0; i < headers.length; i++) {
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
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

  Future<List<File>> generate(
      {required int rw,
      int? rt,
      bool combined = false,
      bool automatic = false}) async {
    final rts = rt == null ? await store.rtList(rw) : [rt];
    final date = timestamp().substring(0, 10);
    final target = Directory(
        '${store.root.path}/export/${automatic ? 'auto' : 'manual'}/${fileStamp()}');
    await target.create(recursive: true);
    final files = <File>[];
    final metadata = <RecordMap>[];
    Future<void> write(String name,
        Map<String, (List<String>, List<List<Object?>>)> sheets) async {
      final book = Excel.createExcel();
      final initial = book.getDefaultSheet();
      for (final entry in sheets.entries) {
        _sheet(book, entry.key, entry.value.$1, entry.value.$2);
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

    final dpsSheets = <String, (List<String>, List<List<Object?>>)>{};
    for (final selectedRt in rts) {
      final warga = await store.exportWarga(selectedRt, rw);
      final rows = [
        for (var i = 0; i < warga.length; i++) dpsRow(warga[i], i + 1)
      ];
      if (combined) {
        dpsSheets['RT $selectedRt'] = (dpsHeaders, rows);
      } else {
        await write('DPS_RT${selectedRt}_RW${rw}_$date.xlsx',
            {'RT $selectedRt': (dpsHeaders, rows)});
      }
    }
    if (combined) await write('DPS_GABUNGAN_RW${rw}_$date.xlsx', dpsSheets);
    final duplicateRows = await store.duplicateRows();
    await write('DUPLIKAT_NIK_$date.xlsx', {
      'DUPLIKAT NIK': (
        dpsHeaders,
        [
          for (final row in duplicateRows)
            dpsRow(row, await store.posisi(row['id'] as int, row['rw'] as int,
                row['rt'] as int))
        ],
      )
    });
    final duplicateNames = await store.duplicateNameRows();
    await write('DUPLIKAT_NAMA_$date.xlsx', {
      'DUPLIKAT NAMA': (
        dpsHeaders,
        [
          for (final row in duplicateNames)
            dpsRow(row, await store.posisi(row['id'] as int, row['rw'] as int,
                row['rt'] as int))
        ],
      )
    });
    final missing = await store.tanpaNik(rw: rw, rt: rt);
    await write('TANPA_NIK_$date.xlsx', {
      'TANPA NIK': (
        dpsHeaders,
        [
          for (final row in missing)
            dpsRow(row, await store.posisi(row['id'] as int, row['rw'] as int,
                row['rt'] as int))
        ],
      )
    });
    await store.recordExport(metadata, rw, rts);
    return files;
  }
}

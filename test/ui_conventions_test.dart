import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiliksuara/core/format.dart';

void main() {
  group('Konvensi format RT dan RW', () {
    test('formatRtRw menghasilkan dua digit dengan spasi slash', () {
      expect(formatRtRw(1, 2), 'RT 01 / RW 02');
      expect(formatRtRw('3', '4'), 'RT 03 / RW 04');
      expect(formatRtRw(12, 5), 'RT 12 / RW 05');
      expect(formatRt(7), 'RT 07');
      expect(formatRw(8), 'RW 08');
      expect(const RtRw(3, 1).label, 'RT 01 / RW 03');
    });
  });

  group('Pemindai string UI', () {
    final targets = <File>[];
    for (final dirPath in ['lib/ui', 'lib/core']) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        targets.addAll(dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')));
      }
    }
    targets.add(File('lib/main.dart'));

    test('tidak ada titik koma (;) pada string teks antarmuka', () {
      final violations = <String>[];
      final stringRegex = RegExp(r"'(.*?)'|" r'"(.*?)"');

      for (final file in targets) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') ||
              line.startsWith('*') ||
              line.contains('.replaceAll')) {
            continue;
          }

          for (final match in stringRegex.allMatches(line)) {
            final raw = match.group(1) ?? match.group(2) ?? '';
            if (raw.contains(';')) {
              // Abaikan import/uri, query SQL, atau kode sanitasi internal
              if (raw.startsWith('package:') ||
                  raw.startsWith('dart:') ||
                  raw.contains('SELECT') ||
                  raw.contains('INSERT') ||
                  raw.contains('CREATE TABLE') ||
                  raw.contains('.replaceAll')) {
                continue;
              }
              violations.add('${file.path}:${i + 1}: "$raw"');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'Ditemukan titik koma (;) pada string UI:\n'
              '${violations.join('\n')}');
    });

    test('tidak ada tanda elipsis (...) atau (…) pada string antarmuka', () {
      final violations = <String>[];
      final stringRegex = RegExp(r"'(.*?)'|" r'"(.*?)"');

      for (final file in targets) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || line.startsWith('*')) continue;

          for (final match in stringRegex.allMatches(line)) {
            final raw = match.group(1) ?? match.group(2) ?? '';
            if (raw.contains('...') || raw.contains('…')) {
              // Abaikan spread operator jika lolos regex
              if (raw.contains('...[')) continue;
              violations.add('${file.path}:${i + 1}: "$raw"');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'Ditemukan elipsis pada string UI:\n'
              '${violations.join('\n')}');
    });

    test('semua titik tengah (·) harus diapit spasi tunggal ( · )', () {
      final violations = <String>[];

      for (final file in targets) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trim().startsWith('//')) continue;
          if (line.contains('·')) {
            // Hapus setiap kemunculan ' · ' yang valid
            final sisa = line.replaceAll(' · ', '');
            if (sisa.contains('·')) {
              violations.add('${file.path}:${i + 1}: ${line.trim()}');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'Ditemukan titik tengah tanpa spasi baku " · ":\n'
              '${violations.join('\n')}');
    });
    test('tidak ada spasi ganda di dalam string antarmuka', () {
      final violations = <String>[];
      final stringRegex = RegExp(r"'(.*?)'|" r'"(.*?)"');

      for (final file in targets) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('//') || line.startsWith('*')) continue;

          for (final match in stringRegex.allMatches(line)) {
            final raw = match.group(1) ?? match.group(2) ?? '';
            if (raw.contains('  ')) {
              violations.add('${file.path}:${i + 1}: "$raw"');
            }
          }
        }
      }

      expect(violations, isEmpty,
          reason: 'Ditemukan spasi ganda pada string UI:\n'
              '${violations.join('\n')}');
    });

    test('setiap berkas layar terdaftar di tabel judul README', () {
      final readme = File('README.md').readAsLinesSync();
      final screens = Directory('lib/ui')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.dart') && n != 'common.dart')
          .toList()
        ..sort();
      final missing = screens
          .where((n) => !readme.any((line) => line.contains('lib/ui/$n')))
          .toList();

      expect(missing, isEmpty,
          reason: 'Berkas layar tanpa baris di tabel judul README:\n'
              '${missing.join('\n')}');
    });
  });
}

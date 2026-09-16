import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pantarlih_kalitorong/core/app_info.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    final declared = line.substring('version:'.length).trim();
    expect(appVersion, declared);
  });
}

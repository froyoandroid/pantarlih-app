import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/data/store.dart';
import 'package:pantarlih_kalitorong/ui/common.dart';
import 'package:pantarlih_kalitorong/ui/rt_list_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late AppStore store;
  late Session session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pantarlih-rt-list-test-');
    store = AppStore(root, factory: databaseFactoryFfi);
    await store.open();
    await store.setSession(3, 3);
    for (final (name, keterangan) in const [
      ('WARGA NORMAL', ''),
      ('WARGA TMS', 'TMS'),
      ('WARGA PD', 'PD'),
      ('WARGA B', 'B'),
      ('WARGA MD', 'MD'),
    ]) {
      await store.saveWarga({
        'nama': name,
        'jenis_kelamin': null,
        'tempat_lahir': null,
        'tgl_lahir': null,
        'desa': 'KALITORONG',
        'kode_wilayah': null,
        'rt': 3,
        'rw': 3,
        'keterangan': keterangan,
      });
    }
    session = Session(store);
    await session.load();
  });

  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(MaterialApp(home: RtListScreen(session: session)));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  }

  testWidgets('status chips filter rows and can be cleared', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      for (final label in ['Normal', 'TMS', 'PD', 'B', 'MD']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      expect(find.text('WARGA NORMAL'), findsOneWidget);
      expect(find.text('WARGA TMS'), findsOneWidget);

      final tms = find.widgetWithText(ChoiceChip, 'TMS');
      await tester.tap(tms);
      await tester.pump();
      expect(find.text('WARGA TMS'), findsOneWidget);
      expect(find.text('WARGA NORMAL'), findsNothing);
      expect(find.text('WARGA PD'), findsNothing);

      await tester.tap(tms);
      await tester.pump();
      expect(find.text('WARGA NORMAL'), findsOneWidget);
      expect(find.text('WARGA MD'), findsOneWidget);
    });
  });
}

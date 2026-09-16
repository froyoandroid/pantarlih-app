import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pantarlih_kalitorong/core/format.dart';
import 'package:pantarlih_kalitorong/core/nama.dart';
import 'package:pantarlih_kalitorong/data/store.dart';
import 'package:pantarlih_kalitorong/ui/common.dart';
import 'package:pantarlih_kalitorong/ui/search_screen.dart';

/// Referensi search must never hide a neighboring RT's row: the whole RW is
/// searched every time, active RT first, other RTs labelled and pushed
/// below - so nobody retypes someone already logged for RT 3 while sitting
/// in RT 4.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late AppStore store;
  late Session session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pantarlih-search-test-');
    store = AppStore(root, factory: databaseFactoryFfi);
    await store.open();
    await store.importRows([
      {
        'urut_asli': 1,
        'nama': 'SUPARMAN JAYA',
        'nama_norm': normalisasiNama('SUPARMAN JAYA'),
        'rt': 4,
        'rw': 3,
        'tgl_lahir': '1980-01-01',
      },
      {
        'urut_asli': 1,
        'nama': 'SUPARMAN WIJAYA',
        'nama_norm': normalisasiNama('SUPARMAN WIJAYA'),
        'rt': 3,
        'rw': 3,
        'tgl_lahir': '1980-01-01',
      },
    ], 'gabungan.xlsx');
    await store.setSession(4, 3,
        ruangKerja: RtRw.encode([RtRw(3, 3), RtRw(3, 4)]));
    session = Session(store);
    await session.load();
  });

  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });

  // sqflite_common_ffi does real process I/O, which never completes inside
  // the FakeAsync zone testWidgets wraps its body in - runAsync steps out of
  // that zone so the store's own database calls (triggered from initState)
  // actually resolve, then pump() drains the resulting frames as usual.
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SearchScreen(session: session)));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    }
  }

  testWidgets('name search shows the active RT then the neighboring RT below',
      (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'SUPARMAN');
      // Past the 180ms score debounce.
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      expect(find.text('SUPARMAN JAYA'), findsOneWidget);
      expect(find.text('SUPARMAN WIJAYA'), findsOneWidget);
      expect(find.text('Referensi di RT 3'), findsOneWidget);

      final jaya = tester.getTopLeft(find.text('SUPARMAN JAYA'));
      final wijaya = tester.getTopLeft(find.text('SUPARMAN WIJAYA'));
      expect(jaya.dy, lessThan(wijaya.dy));

      final label = tester.widget<Text>(find.text('Referensi di RT 3'));
      expect(label.style?.color, amber);
    });
  });

  testWidgets('date search shows every RT, active RT first', (tester) async {
    await tester.runAsync(() async {
      await pump(tester);
      await tester.tap(find.text('Nama berbeda? Cari tanggal lahir'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '01011980');
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }

      expect(find.text('SUPARMAN JAYA'), findsOneWidget);
      expect(find.text('SUPARMAN WIJAYA'), findsOneWidget);
      expect(find.text('Referensi di RT 3'), findsOneWidget);

      final jaya = tester.getTopLeft(find.text('SUPARMAN JAYA'));
      final wijaya = tester.getTopLeft(find.text('SUPARMAN WIJAYA'));
      expect(jaya.dy, lessThan(wijaya.dy));
    });
  });
}

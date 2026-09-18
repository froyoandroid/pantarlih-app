import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiliksuara/main.dart';

void main() {
  testWidgets(
      'offline startup explains public files and requests explicit access',
      (tester) async {
    await tester.pumpWidget(PantarlihApp(introSudah: () async => false));
    await tester.pump();
    expect(find.text('TilikSuara'), findsOneWidget);
    expect(find.text('Buka Aplikasi'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

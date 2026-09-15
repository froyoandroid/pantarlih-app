import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pantarlih_kalitorong/main.dart';

void main() {
  testWidgets(
      'offline startup explains public files and requests explicit access',
      (tester) async {
    await tester.pumpWidget(const PantarlihApp());
    expect(find.text('Pantarlih'), findsOneWidget);
    expect(find.text('BUKA APLIKASI'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

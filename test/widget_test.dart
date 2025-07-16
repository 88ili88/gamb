import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gamb/main.dart';

void main() {
  testWidgets('App builds and shows status', (WidgetTester tester) async {
    await tester.pumpWidget(const TimeSyncApp());
    expect(find.text('BLE Sensor Logger'), findsOneWidget);
    expect(find.textContaining('Status:'), findsOneWidget);
  });
}

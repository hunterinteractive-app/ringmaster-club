import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RingMaster Club smoke test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('RingMaster Club'))),
      ),
    );

    expect(find.text('RingMaster Club'), findsOneWidget);
  });
}

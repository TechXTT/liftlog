import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/main.dart';

void main() {
  testWidgets('LiftLog app renders root widget inside ProviderScope', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: LiftLogApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('LiftLog'), findsWidgets);
  });
}

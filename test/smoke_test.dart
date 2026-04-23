import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/main.dart';
import 'package:liftlog_app/providers/app_providers.dart';

void main() {
  testWidgets('LiftLog app renders home screen with totals and empty state',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const LiftLogApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('LiftLog'), findsOneWidget);
    expect(find.textContaining('Today,'), findsOneWidget);
    expect(find.text('kcal'), findsOneWidget);
    expect(find.text('g protein'), findsOneWidget);
    expect(find.textContaining('No entries yet'), findsOneWidget);

    // Drift schedules a zero-duration Timer when its stream is cancelled
    // on dispose. Advance fake_async's clock so it fires before the
    // framework's post-test !timersPending invariant check runs.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

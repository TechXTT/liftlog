import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/features/food/food_log_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: FoodLogScreen()),
      );

  testWidgets('empty state shows when no entries today', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('No entries yet'), findsOneWidget);
    expect(find.text('0'), findsWidgets, reason: 'totals show 0 kcal');

    await _drainDriftTimers(tester);
  });

  testWidgets('renders today\'s entries and totals', (tester) async {
    final repo = FoodEntryRepository(db);
    final now = DateTime.now();
    await repo.add(FoodEntriesCompanion.insert(
      timestamp: now,
      name: const Value('Eggs'),
      kcal: 140,
      proteinG: 12.0,
      mealType: MealType.breakfast,
      entryType: FoodEntryType.manual,
    ));
    await repo.add(FoodEntriesCompanion.insert(
      timestamp: now,
      name: const Value('Chicken'),
      kcal: 310,
      proteinG: 45.0,
      mealType: MealType.lunch,
      entryType: FoodEntryType.manual,
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Eggs'), findsOneWidget);
    expect(find.text('Chicken'), findsOneWidget);
    expect(find.text('450'), findsOneWidget, reason: 'kcal total');
    expect(find.text('57'), findsOneWidget, reason: 'protein total');

    await _drainDriftTimers(tester);
  });
}

/// Drift schedules a zero-duration Timer when its stream is cancelled on
/// dispose. Advance fake_async's clock so the Timer fires before the
/// framework's post-test !timersPending invariant check runs.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

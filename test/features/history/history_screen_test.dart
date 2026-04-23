import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/history/history_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HistoryScreen()),
      );

  testWidgets('empty history shows explicit "no past" copy for each section',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Past food days'), findsOneWidget);
    expect(find.text('Past workouts'), findsOneWidget);
    expect(find.textContaining('No past days'), findsOneWidget);
    expect(find.textContaining('No completed workouts'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('past food days list excludes today and matches derived totals',
      (tester) async {
    final foodRepo = FoodEntryRepository(db);
    final now = DateTime.now();

    // Today — should NOT appear in history.
    await foodRepo.add(FoodEntriesCompanion.insert(
      timestamp: now,
      name: const Value('Today snack'),
      kcal: 250,
      proteinG: 10.0,
      mealType: MealType.snack,
      entryType: FoodEntryType.manual,
    ));

    // Yesterday — two entries to verify summing.
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    await foodRepo.add(FoodEntriesCompanion.insert(
      timestamp: yesterday,
      name: const Value('Breakfast'),
      kcal: 400,
      proteinG: 25.0,
      mealType: MealType.breakfast,
      entryType: FoodEntryType.manual,
    ));
    await foodRepo.add(FoodEntriesCompanion.insert(
      timestamp: yesterday.add(const Duration(hours: 6)),
      name: const Value('Dinner'),
      kcal: 700,
      proteinG: 45.0,
      mealType: MealType.dinner,
      entryType: FoodEntryType.manual,
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('1100 kcal'), findsOneWidget,
        reason: 'summed yesterday kcal (400 + 700)');
    expect(find.textContaining('70'), findsWidgets,
        reason: 'summed yesterday protein (25 + 45)');
    expect(find.text('Today snack'), findsNothing,
        reason: 'today must not leak into past-days history');

    await _drainDriftTimers(tester);
  });

  testWidgets('past workouts section only lists ended sessions', (tester) async {
    final wrepo = WorkoutSessionRepository(db);
    await wrepo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 20, 10),
      endedAt: Value(DateTime(2026, 4, 20, 11)),
    ));
    await wrepo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 18),
      // Still in progress — should be filtered out.
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('Workout · Apr 20'), findsOneWidget);
    expect(find.textContaining('Workout · Apr 23'), findsNothing);

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

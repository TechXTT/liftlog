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
  late FoodEntryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FoodEntryRepository(db);
  });

  tearDown(() async => db.close());

  Widget app() => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: FoodLogScreen()),
  );

  Future<int> add({
    required DateTime timestamp,
    required String name,
    required int kcal,
    double proteinG = 10.0,
    MealType mealType = MealType.breakfast,
    FoodEntryType entryType = FoodEntryType.manual,
  }) {
    return repo.add(
      FoodEntriesCompanion.insert(
        timestamp: timestamp,
        name: Value(name),
        kcal: kcal,
        proteinG: proteinG,
        mealType: mealType,
        entryType: entryType,
      ),
    );
  }

  group('listRecentDistinctNames', () {
    test('collapses duplicates keeping newest per name', () async {
      // Three Eggs rows; the newest one wins.
      await add(timestamp: DateTime(2026, 4, 20, 8), name: 'Eggs', kcal: 120);
      await add(timestamp: DateTime(2026, 4, 21, 8), name: 'Eggs', kcal: 130);
      await add(timestamp: DateTime(2026, 4, 22, 8), name: 'Eggs', kcal: 140);
      await add(
        timestamp: DateTime(2026, 4, 19, 12),
        name: 'Chicken',
        kcal: 310,
      );

      final recent = await repo.listRecentDistinctNames();
      expect(recent.map((e) => e.name), ['Eggs', 'Chicken']);
      // Newest Eggs wins (140 kcal, 2026-04-22).
      expect(recent.first.kcal, 140);
      expect(recent.first.timestamp, DateTime(2026, 4, 22, 8));
    });

    test('respects the limit', () async {
      for (var i = 0; i < 15; i++) {
        await add(
          timestamp: DateTime(2026, 4, 23, 8, i),
          name: 'Food $i',
          kcal: 100 + i,
        );
      }
      final recent = await repo.listRecentDistinctNames(limit: 5);
      expect(recent, hasLength(5));
      // Newest-first ordering — highest minute index sorted top.
      expect(recent.first.name, 'Food 14');
    });

    test('newest-first ordering holds for distinct names', () async {
      await add(timestamp: DateTime(2026, 4, 22, 8), name: 'Oats', kcal: 300);
      await add(timestamp: DateTime(2026, 4, 23, 9), name: 'Banana', kcal: 90);
      await add(timestamp: DateTime(2026, 4, 23, 12), name: 'Salad', kcal: 200);

      final recent = await repo.listRecentDistinctNames();
      expect(recent.map((e) => e.name), ['Salad', 'Banana', 'Oats']);
    });
  });

  group('FoodLogScreen recent-foods strip', () {
    testWidgets('renders distinct chips in newest-first order', (tester) async {
      await add(
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        name: 'Eggs',
        kcal: 140,
      );
      // Duplicate Eggs — collapsed away.
      await add(
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
        name: 'Eggs',
        kcal: 150,
      );
      await add(
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        name: 'Chicken',
        kcal: 310,
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // Chicken first (newest), then the latest-Eggs label (150 kcal).
      expect(find.text('Chicken · 310 kcal'), findsOneWidget);
      expect(find.text('Eggs · 150 kcal'), findsOneWidget);
      expect(find.text('Eggs · 140 kcal'), findsNothing);

      await _drainDriftTimers(tester);
    });

    testWidgets('empty state: strip renders nothing when there are no rows', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // No action chips at all — the strip collapses to SizedBox.shrink()
      // so it reserves zero vertical space.
      expect(find.byType(ActionChip), findsNothing);

      await _drainDriftTimers(tester);
    });

    testWidgets(
      'tapping a chip inserts a new row and shows the success snackbar',
      (tester) async {
        await add(
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
          name: 'Eggs',
          kcal: 140,
          proteinG: 12.0,
        );

        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        expect(await repo.listAll(), hasLength(1));

        await tester.tap(find.text('Eggs · 140 kcal'));
        await tester.pump();

        final after = await repo.listAll();
        expect(after, hasLength(2));
        // The newest row is the re-log; timestamp is fresh, but name/kcal/protein
        // match the template.
        final newest = after.first;
        expect(newest.name, 'Eggs');
        expect(newest.kcal, 140);
        expect(newest.proteinG, 12.0);
        expect(newest.entryType, FoodEntryType.manual);

        // Settle the snackbar animation and confirm its text.
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Added Eggs (140 kcal)'), findsOneWidget);

        await _drainDriftTimers(tester);
      },
    );

    testWidgets('re-log clones entryType (estimate stays estimate)', (
      tester,
    ) async {
      await add(
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        name: 'Guess Bowl',
        kcal: 500,
        proteinG: 25.0,
        mealType: MealType.dinner,
        entryType: FoodEntryType.estimate,
      );

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guess Bowl · 500 kcal'));
      await tester.pump();

      final after = await repo.listAll();
      expect(after, hasLength(2));
      // Both rows — original and re-log — carry the estimate type.
      expect(
        after.every((e) => e.entryType == FoodEntryType.estimate),
        isTrue,
        reason: 'entryType must be cloned from the template, not hardcoded',
      );

      await _drainDriftTimers(tester);
    });
  });
}

/// Drift schedules a zero-duration Timer when its stream is cancelled on
/// dispose. Advance fake_async's clock so the Timer fires before the
/// framework's post-test !timersPending invariant check runs.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/features/food/food_entry_form_screen.dart';
import 'package:liftlog_app/features/food/food_log_screen.dart';
import 'package:liftlog_app/features/history/past_day_food_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/ui/timestamp_field.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: child),
  );
}

void main() {
  late AppDatabase db;
  late FoodEntryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FoodEntryRepository(db);
  });

  tearDown(() async => db.close());

  Future<FoodEntry> seed({
    String name = 'Oats',
    int kcal = 300,
    double proteinG = 10.0,
    MealType mealType = MealType.breakfast,
  }) async {
    await repo.add(
      FoodEntriesCompanion.insert(
        timestamp: DateTime.now(),
        name: Value(name),
        kcal: kcal,
        proteinG: proteinG,
        mealType: mealType,
        entryType: FoodEntryType.manual,
      ),
    );
    return (await repo.listAll()).single;
  }

  testWidgets('add form: rejects empty name and non-numeric calories', (
    tester,
  ) async {
    await tester.pumpWidget(_host(db, const FoodEntryFormScreen()));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Enter a whole number'), findsOneWidget);
    expect(find.text('Enter a number'), findsOneWidget);
  });

  testWidgets('add form: valid submission persists entry and pops', (
    tester,
  ) async {
    await tester.pumpWidget(_host(db, const FoodEntryFormScreen()));

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Eggs');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Calories (kcal)'),
      '140',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Protein (g)'),
      '12',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final entries = await repo.listAll();
    expect(entries, hasLength(1));
    expect(entries.first.name, 'Eggs');
    expect(entries.first.kcal, 140);
    expect(entries.first.proteinG, 12.0);
    expect(entries.first.entryType, FoodEntryType.manual);
  });

  testWidgets('edit form shows current values and updates on save', (
    tester,
  ) async {
    final entry = await seed();

    await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    expect(find.text('Oats'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Oatmeal',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Calories (kcal)'),
      '320',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = (await repo.listAll()).single;
    expect(after.name, 'Oatmeal');
    expect(after.kcal, 320);
  });

  testWidgets(
    'edit form: delete shows confirm dialog; cancel keeps the entry',
    (tester) async {
      final entry = await seed(
        name: 'Apple',
        kcal: 95,
        proteinG: 0.5,
        mealType: MealType.snack,
      );

      await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete entry'));
      await tester.pumpAndSettle();

      expect(find.text('Delete entry?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await repo.listAll(), hasLength(1));
    },
  );

  testWidgets('edit form: delete → confirm removes the entry', (tester) async {
    final entry = await seed(
      name: 'Apple',
      kcal: 95,
      proteinG: 0.5,
      mealType: MealType.snack,
    );

    await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repo.listAll(), isEmpty);
  });

  testWidgets('add as estimate: toggle on → save → entry typed as estimate and '
      'badge appears on the log', (tester) async {
    await tester.pumpWidget(_host(db, const FoodEntryFormScreen()));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Guess Bowl',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Calories (kcal)'),
      '500',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Protein (g)'),
      '25',
    );

    await tester.tap(find.text('This is an estimate'));
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final entries = await repo.listAll();
    expect(entries, hasLength(1));
    expect(entries.first.entryType, FoodEntryType.estimate);

    // Unmount the form (whose Navigator is in an odd state after pop-to-empty)
    // before mounting a fresh FoodLogScreen tree.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));

    await tester.pumpWidget(_host(db, const FoodLogScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Guess Bowl'), findsOneWidget);
    expect(find.text('Est.'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets(
    'edit form: flipping estimate toggle off rewrites type to manual',
    (tester) async {
      await repo.add(
        FoodEntriesCompanion.insert(
          timestamp: DateTime.now(),
          name: const Value('Eyeballed soup'),
          kcal: 250,
          proteinG: 8.0,
          mealType: MealType.dinner,
          entryType: FoodEntryType.estimate,
        ),
      );
      final entry = (await repo.listAll()).single;

      await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
      await tester.pumpAndSettle();

      // Toggle off — flips estimate -> manual.
      await tester.tap(find.text('This is an estimate'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final after = (await repo.listAll()).single;
      expect(after.entryType, FoodEntryType.manual);
    },
  );

  testWidgets(
    'add form: picked past timestamp persists and appears on past-day screen',
    (tester) async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final picked = DateTime(
        twoDaysAgo.year,
        twoDaysAgo.month,
        twoDaysAgo.day,
        9,
        30,
      );

      await tester.pumpWidget(
        _host(
          db,
          FoodEntryFormScreen(timestampPicker: (ctx, current) async => picked),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Porridge',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories (kcal)'),
        '250',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Protein (g)'),
        '8',
      );

      // Tap the timestamp field — opens (stubbed) picker, which returns `picked`.
      await tester.tap(
        find.descendant(
          of: find.byType(TimestampField),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final entries = await repo.listAll();
      expect(entries, hasLength(1));
      expect(entries.first.timestamp, picked);

      // Unmount the form and mount the past-day screen for the picked day.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));

      final day = DateTime(picked.year, picked.month, picked.day);
      await tester.pumpWidget(_host(db, PastDayFoodScreen(day: day)));
      await tester.pumpAndSettle();

      expect(find.text('Porridge'), findsOneWidget);

      await _drainDriftTimers(tester);
    },
  );

  testWidgets(
    'add form: timestamp >1h in the future blocks save (no new row)',
    (tester) async {
      final future = DateTime.now().add(const Duration(hours: 2));

      await tester.pumpWidget(
        _host(
          db,
          FoodEntryFormScreen(timestampPicker: (ctx, current) async => future),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'Ghost meal',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories (kcal)'),
        '100',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Protein (g)'),
        '5',
      );

      await tester.tap(
        find.descendant(
          of: find.byType(TimestampField),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Validator rejected — no row created.
      expect(await repo.listAll(), isEmpty);
      expect(
        find.text('Time cannot be more than 1 hour in the future'),
        findsOneWidget,
      );
    },
  );
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

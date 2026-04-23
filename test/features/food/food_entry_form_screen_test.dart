import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/features/food/food_entry_form_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

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
    await repo.add(FoodEntriesCompanion.insert(
      timestamp: DateTime.now(),
      name: Value(name),
      kcal: kcal,
      proteinG: proteinG,
      mealType: mealType,
      entryType: FoodEntryType.manual,
    ));
    return (await repo.listAll()).single;
  }

  testWidgets('add form: rejects empty name and non-numeric calories',
      (tester) async {
    await tester.pumpWidget(_host(db, const FoodEntryFormScreen()));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Enter a whole number'), findsOneWidget);
    expect(find.text('Enter a number'), findsOneWidget);
  });

  testWidgets('add form: valid submission persists entry and pops',
      (tester) async {
    await tester.pumpWidget(_host(db, const FoodEntryFormScreen()));

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Eggs');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories (kcal)'), '140');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Protein (g)'), '12');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final entries = await repo.listAll();
    expect(entries, hasLength(1));
    expect(entries.first.name, 'Eggs');
    expect(entries.first.kcal, 140);
    expect(entries.first.proteinG, 12.0);
    expect(entries.first.entryType, FoodEntryType.manual);
  });

  testWidgets('edit form shows current values and updates on save',
      (tester) async {
    final entry = await seed();

    await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    expect(find.text('Oats'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Oatmeal');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Calories (kcal)'), '320');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = (await repo.listAll()).single;
    expect(after.name, 'Oatmeal');
    expect(after.kcal, 320);
  });

  testWidgets('edit form: delete shows confirm dialog; cancel keeps the entry',
      (tester) async {
    final entry = await seed(name: 'Apple', kcal: 95, proteinG: 0.5,
        mealType: MealType.snack);

    await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();

    expect(find.text('Delete entry?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await repo.listAll(), hasLength(1));
  });

  testWidgets('edit form: delete → confirm removes the entry', (tester) async {
    final entry = await seed(name: 'Apple', kcal: 95, proteinG: 0.5,
        mealType: MealType.snack);

    await tester.pumpWidget(_host(db, FoodEntryFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repo.listAll(), isEmpty);
  });
}

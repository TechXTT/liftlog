import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';

void main() {
  late AppDatabase db;
  late FoodEntryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FoodEntryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  FoodEntriesCompanion sample({
    DateTime? timestamp,
    int kcal = 500,
    double proteinG = 30.0,
    MealType mealType = MealType.lunch,
    FoodEntryType entryType = FoodEntryType.manual,
  }) {
    return FoodEntriesCompanion.insert(
      timestamp: timestamp ?? DateTime(2026, 4, 23, 12, 30),
      kcal: kcal,
      proteinG: proteinG,
      mealType: mealType,
      entryType: entryType,
    );
  }

  test('add + watchAll round-trips an entry with enum values as text', () async {
    await repo.add(sample());

    final entries = await repo.watchAll().first;
    expect(entries, hasLength(1));
    expect(entries.first.kcal, 500);
    expect(entries.first.proteinG, 30.0);
    expect(entries.first.mealType, MealType.lunch);
    expect(entries.first.entryType, FoodEntryType.manual);

    final raw = await db
        .customSelect('SELECT meal_type, entry_type FROM food_entries')
        .getSingle();
    expect(raw.read<String>('meal_type'), 'lunch');
    expect(raw.read<String>('entry_type'), 'manual');
  });

  test('update persists new field values', () async {
    final id = await repo.add(sample());
    final original = (await repo.watchAll().first).single;
    final edited = original.copyWith(kcal: 600, proteinG: 40.0);

    await repo.update(edited);

    final after = (await repo.watchAll().first).single;
    expect(after.id, id);
    expect(after.kcal, 600);
    expect(after.proteinG, 40.0);
  });

  test('delete removes the entry', () async {
    final id = await repo.add(sample());
    final removed = await repo.delete(id);
    expect(removed, 1);
    expect(await repo.watchAll().first, isEmpty);
  });

  test('watchByDate scopes to local calendar day', () async {
    await repo.add(sample(timestamp: DateTime(2026, 4, 22, 23, 59)));
    await repo.add(sample(timestamp: DateTime(2026, 4, 23, 0, 1), kcal: 200));
    await repo.add(sample(timestamp: DateTime(2026, 4, 23, 23, 59), kcal: 300));
    await repo.add(sample(timestamp: DateTime(2026, 4, 24, 0, 1)));

    final onDay = await repo.watchByDate(DateTime(2026, 4, 23)).first;
    expect(onDay.map((e) => e.kcal), unorderedEquals([200, 300]));
  });

  test('watchDailyTotals sums kcal and protein for the given day', () async {
    await repo.add(sample(
      timestamp: DateTime(2026, 4, 23, 8),
      kcal: 400,
      proteinG: 25.0,
    ));
    await repo.add(sample(
      timestamp: DateTime(2026, 4, 23, 13),
      kcal: 650,
      proteinG: 42.5,
    ));
    await repo.add(sample(
      timestamp: DateTime(2026, 4, 22, 20),
      kcal: 999,
      proteinG: 99.0,
    ));

    final totals = await repo.watchDailyTotals(DateTime(2026, 4, 23)).first;
    expect(totals.kcal, 1050);
    expect(totals.proteinG, closeTo(67.5, 1e-9));
  });
}

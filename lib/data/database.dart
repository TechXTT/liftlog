import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'enums.dart';

part 'database.g.dart';

class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get kcal => integer()();
  RealColumn get proteinG => real()();
  TextColumn get mealType => textEnum<MealType>()();
  TextColumn get entryType => textEnum<FoodEntryType>()();
  TextColumn get note => text().nullable()();
  // Provenance (v2.0 trust rule — every entity declares its `Source`).
  // Defaulted so existing rows and inserts that pre-date the v3 schema
  // stay valid without a data migration. Orthogonal to `entryType`.
  TextColumn get source =>
      textEnum<Source>().withDefault(const Constant('userEntered'))();
}

class WorkoutSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get source =>
      textEnum<Source>().withDefault(const Constant('userEntered'))();
}

class ExerciseSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseName => text()();
  IntColumn get reps => integer()();
  RealColumn get weight => real()();
  TextColumn get weightUnit => textEnum<WeightUnit>()();
  TextColumn get status => textEnum<WorkoutSetStatus>()();
  IntColumn get orderIndex => integer()();
  // Nullable FK to the first-class `Exercises` table (schema v3). Populated
  // by the v2→v3 seeding pass and by future adaptive-programming work.
  // UI still reads `exerciseName` as the authoritative name source for now.
  IntColumn get exerciseId =>
      integer().nullable().references(Exercises, #id)();
  TextColumn get source =>
      textEnum<Source>().withDefault(const Constant('userEntered'))();
}

class BodyWeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();
  RealColumn get value => real()();
  TextColumn get unit => textEnum<WeightUnit>()();
  TextColumn get source =>
      textEnum<Source>().withDefault(const Constant('userEntered'))();
}

/// Exercise as a first-class entity (schema v3).
///
/// Introduced so future adaptive-programming features (progression,
/// volume-per-muscle-group analytics) can address the exercise once by
/// id rather than round-tripping free-form `exerciseName` strings. For
/// sprint 1 the column is populated by the v2→v3 seeding pass only;
/// workout UI continues to write `exerciseName` as the authoritative
/// name source. `canonicalName` is globally unique so the seeding pass
/// is trivially idempotent (see `_seedExercisesFromHistory`).
class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get canonicalName => text().unique()();
  TextColumn get muscleGroup => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(tables: [
  FoodEntries,
  WorkoutSessions,
  ExerciseSets,
  BodyWeightLogs,
  Exercises,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // When advancing schemaVersion: document the manual backup path
          // in vault/05 Architecture/Runbooks.md before releasing the migration.
          if (from < 2) {
            await m.addColumn(foodEntries, foodEntries.name);
          }
          if (from < 3) {
            // Additive-only — no drops, no renames, no transforms beyond
            // the one-time exercise seeding (idempotent via UNIQUE).
            //
            // 1. Provenance columns on every entity.
            await m.addColumn(foodEntries, foodEntries.source);
            await m.addColumn(bodyWeightLogs, bodyWeightLogs.source);
            await m.addColumn(workoutSessions, workoutSessions.source);
            await m.addColumn(exerciseSets, exerciseSets.source);
            // 2. First-class `exercises` table.
            await m.createTable(exercises);
            // 3. Nullable FK from exercise_sets → exercises (no backfill
            //    in this PR; UI still reads `exerciseName`).
            await m.addColumn(exerciseSets, exerciseSets.exerciseId);
            // 4. Seed exercises from the distinct historical names.
            await _seedExercisesFromHistory();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// Seeds `exercises` with the distinct `exercise_name` values already
  /// present in `exercise_sets`. Idempotent: the `canonicalName UNIQUE`
  /// constraint plus `InsertMode.insertOrIgnore` means running this
  /// twice yields the same row count as running it once.
  Future<void> _seedExercisesFromHistory() async {
    final rows = await customSelect(
      'SELECT DISTINCT exercise_name FROM exercise_sets',
    ).get();
    final now = DateTime.now();
    for (final row in rows) {
      final name = row.read<String>('exercise_name');
      await into(exercises).insert(
        ExercisesCompanion.insert(
          canonicalName: name,
          createdAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'liftlog.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

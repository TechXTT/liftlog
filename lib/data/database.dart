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
  IntColumn get exerciseId => integer().nullable().references(Exercises, #id)();
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

/// Routine — a reusable workout template (schema v4, issue #52).
///
/// A routine names a lineup of exercises (and optional per-exercise
/// target sets/reps/weight) that the user can later spin up into a
/// concrete `WorkoutSession`. Sprint 5 lands the data layer only — no
/// UI renders routines yet, and "start workout from routine" is
/// deferred. The model is shaped so future adaptive-programming work
/// (E7) can read routine definitions without schema churn.
///
/// `source` follows the v2.0 trust rule that every entity declares its
/// provenance. Defaulted to `'userEntered'` so the v3→v4 migration can
/// add the column without a data backfill (no existing rows on a fresh
/// table anyway, but keeping the pattern consistent with every other
/// entity).
class Routines extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get source =>
      textEnum<Source>().withDefault(const Constant('userEntered'))();
}

/// Line items on a routine (schema v4, issue #52).
///
/// Each row links a routine to an exercise with an explicit
/// `orderIndex` (the `RoutineRepository.reorderExercises` transactional
/// rewrite preserves this as the authoritative ordering). Target
/// columns are nullable because a routine can prescribe as much or as
/// little detail as the user wants — a bodyweight routine might leave
/// `targetWeight` / `targetWeightUnit` null, and a free-form one might
/// leave every target null. `routineId` uses `ON DELETE CASCADE` so
/// deleting a routine removes its lineup automatically (enforced by
/// `PRAGMA foreign_keys = ON` in `beforeOpen`).
class RoutineExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get routineId =>
      integer().references(Routines, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get orderIndex => integer()();
  IntColumn get targetSets => integer().nullable()();
  IntColumn get targetReps => integer().nullable()();
  RealColumn get targetWeight => real().nullable()();
  TextColumn get targetWeightUnit => textEnum<WeightUnit>().nullable()();
}

/// Daily calorie + protein target (schema v5, issue #59 — E5 kickoff).
///
/// Targets are historical: a new row is inserted whenever the user
/// changes their goal, and the "active" target on a given day is the
/// one with the largest `effectiveFrom` that is still `<=` the day.
/// This preserves intent over time — a target set on Apr 1 still
/// governs Apr 5 even after a new target lands on Apr 10 — and keeps
/// the "no hidden auto-adjustment" trust rule honest: the UI can show
/// the user exactly which target was in effect when a day was logged.
///
/// `source` defaults to `'userEntered'` so the additive v4→v5
/// migration can `createTable(dailyTargets)` without needing to seed a
/// backfill row — the column is always explicit when the user sets a
/// target. No delete API: historical integrity means we never remove a
/// prior target from the table (user edits add a new row with a new
/// `effectiveFrom`).
class DailyTargets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get kcal => integer()();
  RealColumn get proteinG => real()();
  DateTimeColumn get effectiveFrom => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get source =>
      textEnum<Source>().withDefault(const Constant('userEntered'))();
}

@DriftDatabase(
  tables: [
    FoodEntries,
    WorkoutSessions,
    ExerciseSets,
    BodyWeightLogs,
    Exercises,
    Routines,
    RoutineExercises,
    DailyTargets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

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
      if (from < 4) {
        // Additive-only — two brand-new tables with no data transform
        // on existing tables. Backup path documented in Runbooks
        // ("Manual backup path — v3 → v4") per the platform-risk
        // guardrail. `routines.source` has a default ('userEntered'),
        // but there are no existing rows to backfill anyway.
        await m.createTable(routines);
        await m.createTable(routineExercises);
      }
      if (from < 5) {
        // Additive-only — a single brand-new table (`daily_targets`).
        // No transform on existing tables, no backfill. Backup path
        // documented in Runbooks ("Manual backup path — v4 → v5") per
        // the platform-risk guardrail. `daily_targets.source` has a
        // default ('userEntered'); every other column is non-null and
        // populated explicitly when the user sets a target (kcal,
        // protein_g, effective_from, created_at), so no DEFAULT rows
        // are needed for an empty table — every insert supplies the
        // values.
        await m.createTable(dailyTargets);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Backfill `exercise_sets.exercise_id` from the `exercises` table.
      //
      // Why: the v2→v3 migration (issue #42) seeded `exercises` from the
      // distinct historical `exerciseName` values and added a nullable
      // `exercise_id` FK on `exercise_sets`, but did NOT link existing
      // sets to their seeded exercise row. This statement closes that
      // carryover (issue #47) so historical sets are addressable by id
      // for future adaptive-programming features.
      //
      // Idempotency: the `WHERE exercise_id IS NULL` guard makes every
      // subsequent open a no-op — rows already linked stay linked, rows
      // that still lack a matching `exercises` entry (e.g. a set whose
      // name was deleted from `exercises`) stay null. Safe to run on
      // every boot.
      //
      // Trust rule: this populates a nullable FK that was introduced
      // specifically to enable this link — restoration of intent, not
      // silent mutation of user-visible totals or units.
      await customStatement('''
            UPDATE exercise_sets
               SET exercise_id = (SELECT id FROM exercises WHERE canonical_name = exercise_sets.exercise_name)
             WHERE exercise_id IS NULL
          ''');
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
        ExercisesCompanion.insert(canonicalName: name, createdAt: now),
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

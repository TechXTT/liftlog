// ignore_for_file: depend_on_referenced_packages
// `sqlite3` is used only here — and only in a test — to stand up a
// schema-v2 shape on disk so the live AppDatabase's onUpgrade can be
// exercised. It's a transitive dep via `drift/native.dart` +
// `sqlite3_flutter_libs` (NativeDatabase uses it under the hood), so
// no new pub dep is introduced. Adding it to `dev_dependencies` would
// also work but widens the dependency surface for a single test.

import 'dart:io';

import 'package:drift/drift.dart' show InsertMode, Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';

void main() {
  group('v2 → v3 migration', () {
    // Simulates an upgrade from schema v2 (pre-issue #42) to v3:
    //  - Creates a fresh sqlite file with the v2 table shape via raw SQL
    //    and sets `PRAGMA user_version = 2` so Drift reads it as v2.
    //  - Inserts sample rows in each of the 4 entities.
    //  - Opens AppDatabase (schemaVersion = 3) which fires onUpgrade.
    //  - Asserts: `source` column added to all 4 tables with default
    //    `'userEntered'` on existing rows; `exercises` table exists and
    //    contains exactly the distinct historical `exerciseName` values;
    //    seeding is idempotent across successive opens.
    //
    // Why raw sqlite3 for setup: Drift's own API can't address a
    // "previous-schema" layout; we have to build the v2 shape by hand
    // to prove the upgrade path runs. The dependency is transitive
    // through `drift/native.dart` + `sqlite3_flutter_libs`.

    Directory tempDir() {
      final dir = Directory.systemTemp.createTempSync('liftlog_migrate_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    /// Writes a schema-v2-shaped database to [path]. The schema mirrors
    /// what existed before issue #42: no `source` column on any table,
    /// no `exercises` table, no `exercise_id` FK on `exercise_sets`. It
    /// also inserts three sample rows so we can prove both the column
    /// default and the seeding pass. PRAGMA user_version is set to 2
    /// so Drift sees "from = 2" on open and runs the v3 upgrade branch.
    void seedV2Database(String path) {
      final raw = sqlite3.open(path);
      try {
        raw.execute('PRAGMA foreign_keys = ON');
        raw.execute('''
          CREATE TABLE food_entries (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            kcal INTEGER NOT NULL,
            protein_g REAL NOT NULL,
            meal_type TEXT NOT NULL,
            entry_type TEXT NOT NULL,
            note TEXT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE workout_sessions (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NULL,
            note TEXT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE exercise_sets (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES workout_sessions (id) ON DELETE CASCADE,
            exercise_name TEXT NOT NULL,
            reps INTEGER NOT NULL,
            weight REAL NOT NULL,
            weight_unit TEXT NOT NULL,
            status TEXT NOT NULL,
            order_index INTEGER NOT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE body_weight_logs (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            value REAL NOT NULL,
            unit TEXT NOT NULL
          )
        ''');
        // Drift stores DateTime as int (unix seconds). Values don't
        // matter for the assertions here — only the row count and the
        // distinct exerciseName set do.
        raw.execute(
          "INSERT INTO food_entries (timestamp, name, kcal, protein_g, meal_type, entry_type) "
          "VALUES (1000, 'Eggs', 140, 12.0, 'breakfast', 'manual')",
        );
        raw.execute(
          "INSERT INTO body_weight_logs (timestamp, value, unit) "
          "VALUES (1000, 80.0, 'kg')",
        );
        raw.execute("INSERT INTO workout_sessions (started_at) VALUES (1000)");
        raw.execute(
          "INSERT INTO exercise_sets (session_id, exercise_name, reps, weight, weight_unit, status, order_index) "
          "VALUES (1, 'Bench Press', 8, 80.0, 'kg', 'completed', 0)",
        );
        raw.execute(
          "INSERT INTO exercise_sets (session_id, exercise_name, reps, weight, weight_unit, status, order_index) "
          "VALUES (1, 'Bench Press', 7, 82.5, 'kg', 'completed', 1)",
        );
        raw.execute(
          "INSERT INTO exercise_sets (session_id, exercise_name, reps, weight, weight_unit, status, order_index) "
          "VALUES (1, 'Squat', 5, 100.0, 'kg', 'completed', 2)",
        );
        raw.execute('PRAGMA user_version = 2');
      } finally {
        raw.close();
      }
    }

    test(
      'adds source columns with default "userEntered" on every table',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV2Database(dbPath);

        // Trigger onUpgrade by opening AppDatabase against the v2 file.
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);

        Future<List<String>> readSource(String table) async {
          final rows = await db
              .customSelect('SELECT source FROM $table ORDER BY id ASC')
              .get();
          return rows.map((r) => r.read<String>('source')).toList();
        }

        expect(await readSource('food_entries'), ['userEntered']);
        expect(await readSource('body_weight_logs'), ['userEntered']);
        expect(await readSource('workout_sessions'), ['userEntered']);
        expect(await readSource('exercise_sets'), [
          'userEntered',
          'userEntered',
          'userEntered',
        ]);
      },
    );

    test(
      'creates exercises table and seeds distinct exercise names once',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV2Database(dbPath);

        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);

        final rows = await db
            .customSelect(
              'SELECT canonical_name FROM exercises ORDER BY canonical_name ASC',
            )
            .get();
        final names = rows
            .map((r) => r.read<String>('canonical_name'))
            .toList();
        // V2 sample has "Bench Press" (x2) and "Squat" (x1) → 2 distinct.
        expect(names, ['Bench Press', 'Squat']);

        // Confirm `exercise_id` FK column was added AND backfilled by the
        // `beforeOpen` pass (issue #47). Historical sets are now linked to
        // their seeded `exercises` row by matching `exercise_name` →
        // `canonical_name`.
        final setRows = await db
            .customSelect(
              'SELECT exercise_name, exercise_id FROM exercise_sets ORDER BY id ASC',
            )
            .get();
        expect(setRows, hasLength(3));
        expect(
          setRows.every((r) => r.read<int?>('exercise_id') != null),
          isTrue,
          reason: 'beforeOpen backfill must populate every matchable set',
        );
        // Both "Bench Press" rows should map to the same exercise id.
        final benchIds = setRows
            .where((r) => r.read<String>('exercise_name') == 'Bench Press')
            .map((r) => r.read<int>('exercise_id'))
            .toSet();
        expect(benchIds, hasLength(1));
      },
    );

    test('seeding is idempotent across successive opens', () async {
      final dir = tempDir();
      final dbPath = p.join(dir.path, 'liftlog.sqlite');
      seedV2Database(dbPath);

      // First open: runs onUpgrade + seeds from v2 rows.
      {
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        // Force the connection lazily by touching the DB.
        await db.customSelect('SELECT 1 AS x').getSingle();
        await db.close();
      }

      Future<int> countExercises() async {
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        try {
          final row = await db
              .customSelect('SELECT COUNT(*) AS c FROM exercises')
              .getSingle();
          return row.read<int>('c');
        } finally {
          await db.close();
        }
      }

      final firstCount = await countExercises();
      expect(firstCount, 2);

      // Re-open: schemaVersion is now 3 on disk so onUpgrade should
      // NOT fire again, but even if some future change re-ran the
      // seeding helper, `INSERT OR IGNORE` + `canonicalName UNIQUE`
      // guarantees the row count stays constant.
      final secondCount = await countExercises();
      expect(
        secondCount,
        firstCount,
        reason: 'seeding must be idempotent under repeated open',
      );
    });
  });

  group('v3 → v4 migration', () {
    // Simulates an upgrade from schema v3 (post-issue #42) to v4:
    //  - Creates a fresh sqlite file with the v3 table shape via raw SQL
    //    and sets `PRAGMA user_version = 3` so Drift reads it as v3.
    //  - Inserts sample rows across the five v3 entities.
    //  - Opens AppDatabase (schemaVersion = 4) which fires onUpgrade.
    //  - Asserts: existing rows survive untouched; the two new tables
    //    (`routines`, `routine_exercises`) exist and are empty; new
    //    inserts work; cascade delete on routine removes child rows.
    //
    // Same raw-sqlite3 setup rationale as the v2→v3 group above: Drift
    // can't address a "previous-schema" layout from its own API, so we
    // build the v3 shape by hand.

    Directory tempDir() {
      final dir = Directory.systemTemp.createTempSync('liftlog_migrate_v4_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    /// Writes a schema-v3-shaped database to [path]. Mirrors the shape
    /// `AppDatabase` had immediately after the v2→v3 migration landed:
    /// provenance column on every entity, first-class `exercises`
    /// table, nullable `exercise_id` FK on `exercise_sets`. No
    /// `routines` / `routine_exercises` tables yet. PRAGMA user_version
    /// is set to 3 so Drift sees "from = 3" on open.
    void seedV3Database(String path) {
      final raw = sqlite3.open(path);
      try {
        raw.execute('PRAGMA foreign_keys = ON');
        raw.execute('''
          CREATE TABLE food_entries (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            kcal INTEGER NOT NULL,
            protein_g REAL NOT NULL,
            meal_type TEXT NOT NULL,
            entry_type TEXT NOT NULL,
            note TEXT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE workout_sessions (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NULL,
            note TEXT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE exercises (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            canonical_name TEXT NOT NULL UNIQUE,
            muscle_group TEXT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE exercise_sets (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES workout_sessions (id) ON DELETE CASCADE,
            exercise_name TEXT NOT NULL,
            reps INTEGER NOT NULL,
            weight REAL NOT NULL,
            weight_unit TEXT NOT NULL,
            status TEXT NOT NULL,
            order_index INTEGER NOT NULL,
            exercise_id INTEGER NULL REFERENCES exercises (id),
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE body_weight_logs (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            value REAL NOT NULL,
            unit TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute(
          "INSERT INTO food_entries (timestamp, name, kcal, protein_g, meal_type, entry_type) "
          "VALUES (1000, 'Eggs', 140, 12.0, 'breakfast', 'manual')",
        );
        raw.execute(
          "INSERT INTO body_weight_logs (timestamp, value, unit) "
          "VALUES (1000, 80.0, 'kg')",
        );
        raw.execute("INSERT INTO workout_sessions (started_at) VALUES (1000)");
        raw.execute(
          "INSERT INTO exercises (canonical_name, created_at) VALUES ('Bench Press', 1000)",
        );
        // One set explicitly linked to the seeded exercise so we can
        // prove the v3 exercise_id value survives the upgrade.
        raw.execute(
          "INSERT INTO exercise_sets (session_id, exercise_name, reps, weight, weight_unit, status, order_index, exercise_id) "
          "VALUES (1, 'Bench Press', 8, 80.0, 'kg', 'completed', 0, 1)",
        );
        raw.execute('PRAGMA user_version = 3');
      } finally {
        raw.close();
      }
    }

    test('existing rows across v3 entities survive the upgrade intact', () async {
      final dir = tempDir();
      final dbPath = p.join(dir.path, 'liftlog.sqlite');
      seedV3Database(dbPath);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final foods = await db
          .customSelect(
            'SELECT id, name, kcal, protein_g, meal_type, entry_type, source '
            'FROM food_entries ORDER BY id ASC',
          )
          .get();
      expect(foods, hasLength(1));
      expect(foods.single.read<String>('name'), 'Eggs');
      expect(foods.single.read<int>('kcal'), 140);
      expect(foods.single.read<double>('protein_g'), 12.0);
      expect(foods.single.read<String>('meal_type'), 'breakfast');
      expect(foods.single.read<String>('entry_type'), 'manual');
      expect(foods.single.read<String>('source'), 'userEntered');

      final weights = await db
          .customSelect(
            'SELECT value, unit, source FROM body_weight_logs ORDER BY id ASC',
          )
          .get();
      expect(weights, hasLength(1));
      expect(weights.single.read<double>('value'), 80.0);
      expect(weights.single.read<String>('unit'), 'kg');
      expect(weights.single.read<String>('source'), 'userEntered');

      final sessions = await db
          .customSelect(
            'SELECT id, started_at, source FROM workout_sessions ORDER BY id ASC',
          )
          .get();
      expect(sessions, hasLength(1));
      expect(sessions.single.read<String>('source'), 'userEntered');

      final exercises = await db
          .customSelect('SELECT canonical_name FROM exercises ORDER BY id ASC')
          .get();
      expect(exercises.map((r) => r.read<String>('canonical_name')).toList(), [
        'Bench Press',
      ]);

      final sets = await db
          .customSelect(
            'SELECT exercise_name, reps, weight, weight_unit, status, order_index, '
            'exercise_id, source FROM exercise_sets ORDER BY id ASC',
          )
          .get();
      expect(sets, hasLength(1));
      final setRow = sets.single;
      expect(setRow.read<String>('exercise_name'), 'Bench Press');
      expect(setRow.read<int>('reps'), 8);
      expect(setRow.read<double>('weight'), 80.0);
      expect(setRow.read<String>('weight_unit'), 'kg');
      expect(setRow.read<String>('status'), 'completed');
      expect(setRow.read<int>('order_index'), 0);
      expect(
        setRow.read<int?>('exercise_id'),
        1,
        reason: 'v3 exercise_id linkage must survive the upgrade',
      );
      expect(setRow.read<String>('source'), 'userEntered');
    });

    test(
      'routines and routine_exercises tables exist and start empty',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV3Database(dbPath);

        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);

        final routines = await db
            .customSelect('SELECT COUNT(*) AS c FROM routines')
            .getSingle();
        expect(routines.read<int>('c'), 0);

        final routineExercises = await db
            .customSelect('SELECT COUNT(*) AS c FROM routine_exercises')
            .getSingle();
        expect(routineExercises.read<int>('c'), 0);
      },
    );

    test(
      'can insert into routines + routine_exercises after upgrade',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV3Database(dbPath);

        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);

        final routineId = await db
            .into(db.routines)
            .insert(
              RoutinesCompanion.insert(
                name: 'Push A',
                createdAt: DateTime(2026, 4, 20, 12),
              ),
            );
        expect(routineId, isPositive);

        // Reference the `exercises.id = 1` seeded row above.
        final reId = await db
            .into(db.routineExercises)
            .insert(
              RoutineExercisesCompanion.insert(
                routineId: routineId,
                exerciseId: 1,
                orderIndex: 0,
                targetSets: const Value(4),
                targetReps: const Value(8),
                targetWeight: const Value(80.0),
                targetWeightUnit: const Value(WeightUnit.kg),
              ),
            );
        expect(reId, isPositive);

        // The FK must have resolved — a bogus exercise_id should fail.
        expect(
          () => db
              .into(db.routineExercises)
              .insert(
                RoutineExercisesCompanion.insert(
                  routineId: routineId,
                  exerciseId: 9999,
                  orderIndex: 1,
                ),
              ),
          throwsA(anything),
          reason: 'FK to exercises.id must be enforced after migration',
        );
      },
    );

    test('deleting a routine cascades to its routine_exercises rows', () async {
      final dir = tempDir();
      final dbPath = p.join(dir.path, 'liftlog.sqlite');
      seedV3Database(dbPath);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final routineId = await db
          .into(db.routines)
          .insert(
            RoutinesCompanion.insert(
              name: 'Push A',
              createdAt: DateTime(2026, 4, 20, 12),
            ),
          );
      await db
          .into(db.routineExercises)
          .insert(
            RoutineExercisesCompanion.insert(
              routineId: routineId,
              exerciseId: 1,
              orderIndex: 0,
            ),
          );
      await db
          .into(db.routineExercises)
          .insert(
            RoutineExercisesCompanion.insert(
              routineId: routineId,
              exerciseId: 1,
              orderIndex: 1,
            ),
          );

      final before = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM routine_exercises WHERE routine_id = ?',
            variables: [Variable<int>(routineId)],
          )
          .getSingle();
      expect(before.read<int>('c'), 2);

      await (db.delete(db.routines)..where((t) => t.id.equals(routineId))).go();

      final after = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM routine_exercises WHERE routine_id = ?',
            variables: [Variable<int>(routineId)],
          )
          .getSingle();
      expect(
        after.read<int>('c'),
        0,
        reason: 'ON DELETE CASCADE must remove the lineup',
      );
    });
  });

  group('v4 → v5 migration', () {
    // Simulates an upgrade from schema v4 (post-issue #52) to v5:
    //  - Creates a fresh sqlite file with the v4 table shape via raw SQL
    //    and sets `PRAGMA user_version = 4` so Drift reads it as v4.
    //  - Inserts sample rows across the v4 entities (including the
    //    routines + routine_exercises tables added in S5.5).
    //  - Opens AppDatabase (schemaVersion = 5) which fires onUpgrade.
    //  - Asserts: existing rows survive untouched; the new
    //    `daily_targets` table exists and is empty; new inserts work
    //    with source defaulting to 'userEntered'.
    //
    // Same raw-sqlite3 setup rationale as the v2→v3 / v3→v4 groups
    // above: Drift can't address a "previous-schema" layout from its
    // own API, so we build the v4 shape by hand.

    Directory tempDir() {
      final dir = Directory.systemTemp.createTempSync('liftlog_migrate_v5_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    /// Writes a schema-v4-shaped database to [path]. Mirrors the shape
    /// `AppDatabase` had immediately after the v3→v4 migration landed:
    /// v3 entities + the `routines` and `routine_exercises` tables. No
    /// `daily_targets` table yet. PRAGMA user_version is set to 4 so
    /// Drift sees "from = 4" on open.
    void seedV4Database(String path) {
      final raw = sqlite3.open(path);
      try {
        raw.execute('PRAGMA foreign_keys = ON');
        raw.execute('''
          CREATE TABLE food_entries (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            kcal INTEGER NOT NULL,
            protein_g REAL NOT NULL,
            meal_type TEXT NOT NULL,
            entry_type TEXT NOT NULL,
            note TEXT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE workout_sessions (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NULL,
            note TEXT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE exercises (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            canonical_name TEXT NOT NULL UNIQUE,
            muscle_group TEXT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE exercise_sets (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES workout_sessions (id) ON DELETE CASCADE,
            exercise_name TEXT NOT NULL,
            reps INTEGER NOT NULL,
            weight REAL NOT NULL,
            weight_unit TEXT NOT NULL,
            status TEXT NOT NULL,
            order_index INTEGER NOT NULL,
            exercise_id INTEGER NULL REFERENCES exercises (id),
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE body_weight_logs (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            timestamp INTEGER NOT NULL,
            value REAL NOT NULL,
            unit TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE routines (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            notes TEXT NULL,
            created_at INTEGER NOT NULL,
            source TEXT NOT NULL DEFAULT 'userEntered'
          )
        ''');
        raw.execute('''
          CREATE TABLE routine_exercises (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            routine_id INTEGER NOT NULL REFERENCES routines (id) ON DELETE CASCADE,
            exercise_id INTEGER NOT NULL REFERENCES exercises (id),
            order_index INTEGER NOT NULL,
            target_sets INTEGER NULL,
            target_reps INTEGER NULL,
            target_weight REAL NULL,
            target_weight_unit TEXT NULL
          )
        ''');
        raw.execute(
          "INSERT INTO food_entries (timestamp, name, kcal, protein_g, meal_type, entry_type) "
          "VALUES (1000, 'Eggs', 140, 12.0, 'breakfast', 'manual')",
        );
        raw.execute(
          "INSERT INTO body_weight_logs (timestamp, value, unit) "
          "VALUES (1000, 80.0, 'kg')",
        );
        raw.execute("INSERT INTO workout_sessions (started_at) VALUES (1000)");
        raw.execute(
          "INSERT INTO exercises (canonical_name, created_at) VALUES ('Bench Press', 1000)",
        );
        raw.execute(
          "INSERT INTO exercise_sets (session_id, exercise_name, reps, weight, weight_unit, status, order_index, exercise_id) "
          "VALUES (1, 'Bench Press', 8, 80.0, 'kg', 'completed', 0, 1)",
        );
        raw.execute(
          "INSERT INTO routines (name, created_at) VALUES ('Push A', 1000)",
        );
        raw.execute(
          "INSERT INTO routine_exercises (routine_id, exercise_id, order_index, target_sets, target_reps, target_weight, target_weight_unit) "
          "VALUES (1, 1, 0, 4, 8, 80.0, 'kg')",
        );
        raw.execute('PRAGMA user_version = 4');
      } finally {
        raw.close();
      }
    }

    test(
      'existing rows across v4 entities survive the upgrade intact',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV4Database(dbPath);

        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);

        // Spot-check one row per entity — the v2→v3 / v3→v4 groups
        // cover every field already, and this group's focus is the
        // v4→v5 delta (new `daily_targets` table), not re-asserting
        // every prior upgrade.
        final foods = await db
            .customSelect('SELECT name, kcal FROM food_entries')
            .get();
        expect(foods, hasLength(1));
        expect(foods.single.read<String>('name'), 'Eggs');

        final routines = await db
            .customSelect('SELECT name FROM routines')
            .get();
        expect(routines, hasLength(1));
        expect(routines.single.read<String>('name'), 'Push A');

        final routineExercises = await db
            .customSelect('SELECT routine_id, exercise_id FROM routine_exercises')
            .get();
        expect(routineExercises, hasLength(1));
      },
    );

    test('daily_targets table exists and starts empty', () async {
      final dir = tempDir();
      final dbPath = p.join(dir.path, 'liftlog.sqlite');
      seedV4Database(dbPath);

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM daily_targets')
          .getSingle();
      expect(count.read<int>('c'), 0);
    });

    test(
      'can insert into daily_targets after upgrade with source defaulted',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV4Database(dbPath);

        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);

        final id = await db
            .into(db.dailyTargets)
            .insert(
              DailyTargetsCompanion.insert(
                kcal: 2000,
                proteinG: 140,
                effectiveFrom: DateTime(2026, 4, 1),
                createdAt: DateTime(2026, 4, 1, 9),
              ),
            );
        expect(id, isPositive);

        final row = await db
            .customSelect(
              'SELECT kcal, protein_g, source FROM daily_targets WHERE id = ?',
              variables: [Variable<int>(id)],
            )
            .getSingle();
        expect(row.read<int>('kcal'), 2000);
        expect(row.read<double>('protein_g'), 140.0);
        expect(
          row.read<String>('source'),
          'userEntered',
          reason: 'source column default must be applied by the migration',
        );
      },
    );

    test(
      'schemaVersion is 5 after the upgrade fires',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');
        seedV4Database(dbPath);

        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        addTearDown(db.close);
        // Touch the DB so the connection opens and the migration runs.
        await db.customSelect('SELECT 1 AS x').getSingle();

        final userVersion = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(userVersion.read<int>('user_version'), 5);
      },
    );
  });

  group('exercise_id backfill', () {
    // Exercises the `beforeOpen` UPDATE introduced in issue #47 directly —
    // not the v2→v3 migration path. Builds a schema-v3-shaped DB in a
    // specific state (sets present, exercises present, exercise_id
    // deliberately null), closes it, reopens via AppDatabase, and
    // asserts the FK is populated after re-open.

    Directory tempDir() {
      final dir = Directory.systemTemp.createTempSync('liftlog_backfill_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    /// Phase-1 helper: writes the v3 schema via AppDatabase.forTesting,
    /// inserts a session + sets + exercises rows, forces `exercise_id`
    /// to null on every set, and closes the DB. The next open against
    /// the same file must trigger the `beforeOpen` backfill.
    Future<void> seedV3DatabaseWithNullExerciseIds({
      required String dbPath,
      required List<String> setNames,
      required List<String> exerciseCanonicalNames,
    }) async {
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      try {
        final sessionId = await db
            .into(db.workoutSessions)
            .insert(
              WorkoutSessionsCompanion.insert(
                startedAt: DateTime(2026, 4, 23, 9),
              ),
            );
        for (var i = 0; i < setNames.length; i++) {
          await db
              .into(db.exerciseSets)
              .insert(
                ExerciseSetsCompanion.insert(
                  sessionId: sessionId,
                  exerciseName: setNames[i],
                  reps: 5,
                  weight: 80.0,
                  weightUnit: WeightUnit.kg,
                  status: WorkoutSetStatus.completed,
                  orderIndex: i,
                ),
              );
        }
        for (final name in exerciseCanonicalNames) {
          await db
              .into(db.exercises)
              .insert(
                ExercisesCompanion.insert(
                  canonicalName: name,
                  createdAt: DateTime(2026, 4, 23, 8),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
        // Force exercise_id back to null — `beforeOpen` already ran on
        // this handle when it was first opened, so without this the
        // sets would already be linked and the backfill assertion
        // below would tautologically pass.
        await db.customStatement('UPDATE exercise_sets SET exercise_id = NULL');
      } finally {
        await db.close();
      }
    }

    test('populates exercise_id for every matchable set on re-open', () async {
      final dir = tempDir();
      final dbPath = p.join(dir.path, 'liftlog.sqlite');

      await seedV3DatabaseWithNullExerciseIds(
        dbPath: dbPath,
        setNames: const ['Bench Press', 'Squat', 'Bench Press'],
        exerciseCanonicalNames: const ['Bench Press', 'Squat'],
      );

      // Re-open triggers `beforeOpen` → backfill.
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            'SELECT exercise_name, exercise_id FROM exercise_sets ORDER BY id ASC',
          )
          .get();
      expect(rows, hasLength(3));
      expect(
        rows.every((r) => r.read<int?>('exercise_id') != null),
        isTrue,
        reason: 'every set whose name matches an exercise must be linked',
      );

      // Both "Bench Press" rows point at the same id; "Squat" points at
      // a different one.
      final benchIds = rows
          .where((r) => r.read<String>('exercise_name') == 'Bench Press')
          .map((r) => r.read<int>('exercise_id'))
          .toSet();
      expect(benchIds, hasLength(1));

      final squatId = rows
          .firstWhere((r) => r.read<String>('exercise_name') == 'Squat')
          .read<int>('exercise_id');
      expect(benchIds.single, isNot(squatId));

      // And each id matches the canonical_name on `exercises`.
      Future<String> canonicalFor(int id) async {
        final row = await db
            .customSelect(
              'SELECT canonical_name FROM exercises WHERE id = ?',
              variables: [Variable<int>(id)],
            )
            .getSingle();
        return row.read<String>('canonical_name');
      }

      expect(await canonicalFor(benchIds.single), 'Bench Press');
      expect(await canonicalFor(squatId), 'Squat');
    });

    test('leaves exercise_id null when no matching exercise exists', () async {
      final dir = tempDir();
      final dbPath = p.join(dir.path, 'liftlog.sqlite');

      await seedV3DatabaseWithNullExerciseIds(
        dbPath: dbPath,
        setNames: const ['ThisNameDoesntExist'],
        exerciseCanonicalNames: const [], // no matching exercises row.
      );

      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      addTearDown(db.close);

      final rows = await db
          .customSelect('SELECT exercise_id FROM exercise_sets')
          .get();
      expect(rows, hasLength(1));
      expect(
        rows.single.read<int?>('exercise_id'),
        isNull,
        reason: 'no matching exercise → exercise_id must stay null',
      );
    });

    test(
      'is idempotent: second re-open does not mutate row contents',
      () async {
        final dir = tempDir();
        final dbPath = p.join(dir.path, 'liftlog.sqlite');

        await seedV3DatabaseWithNullExerciseIds(
          dbPath: dbPath,
          setNames: const ['Bench Press', 'Squat'],
          exerciseCanonicalNames: const ['Bench Press', 'Squat'],
        );

        Future<List<Map<String, Object?>>> snapshot() async {
          final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
          try {
            final rows = await db
                .customSelect(
                  'SELECT id, session_id, exercise_name, reps, weight, '
                  'weight_unit, status, order_index, exercise_id, source '
                  'FROM exercise_sets ORDER BY id ASC',
                )
                .get();
            return rows.map((r) => r.data).toList();
          } finally {
            await db.close();
          }
        }

        final firstSnapshot = await snapshot();
        expect(firstSnapshot, hasLength(2));
        expect(firstSnapshot.every((r) => r['exercise_id'] != null), isTrue);

        final secondSnapshot = await snapshot();
        expect(
          secondSnapshot,
          equals(firstSnapshot),
          reason: 'backfill must be a no-op when exercise_id is already set',
        );
      },
    );
  });

  test(
    'entries across all 4 entities survive DB close + reopen against same file',
    () async {
      final dir = Directory.systemTemp.createTempSync('liftlog_persist_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final dbPath = p.join(dir.path, 'liftlog.sqlite');
      final today = DateTime(2026, 4, 23, 12, 30);

      late int sessionId;

      // Phase 1: open DB, write rows, close.
      {
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        final food = FoodEntryRepository(db);
        final weight = BodyWeightLogRepository(db);
        final sessions = WorkoutSessionRepository(db);
        final sets = ExerciseSetRepository(db);

        await food.add(
          FoodEntriesCompanion.insert(
            timestamp: today,
            name: const Value('Eggs'),
            kcal: 140,
            proteinG: 12.0,
            mealType: MealType.breakfast,
            entryType: FoodEntryType.manual,
          ),
        );
        await food.add(
          FoodEntriesCompanion.insert(
            timestamp: today.add(const Duration(hours: 4)),
            name: const Value('Chicken'),
            kcal: 310,
            proteinG: 45.0,
            mealType: MealType.lunch,
            entryType: FoodEntryType.manual,
          ),
        );

        await weight.add(
          BodyWeightLogsCompanion.insert(
            timestamp: today,
            value: 80.0,
            unit: WeightUnit.kg,
          ),
        );

        sessionId = await sessions.add(
          WorkoutSessionsCompanion.insert(
            startedAt: today.add(const Duration(hours: 6)),
          ),
        );

        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: sessionId,
            exerciseName: 'Bench Press',
            reps: 8,
            weight: 80.0,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 0,
          ),
        );
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: sessionId,
            exerciseName: 'Bench Press',
            reps: 7,
            weight: 82.5,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 1,
          ),
        );

        await db.close();
      }

      // File must be on disk between phases.
      expect(
        File(dbPath).existsSync(),
        isTrue,
        reason: 'DB file must survive close',
      );

      // Phase 2: reopen DB against the same file, assert round-trip.
      {
        final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
        final food = FoodEntryRepository(db);
        final weight = BodyWeightLogRepository(db);
        final sessions = WorkoutSessionRepository(db);
        final sets = ExerciseSetRepository(db);

        final foodRows = await food.listAll();
        expect(foodRows, hasLength(2));
        final byName = {for (final r in foodRows) r.name: r};
        expect(byName['Eggs']!.kcal, 140);
        expect(byName['Eggs']!.proteinG, 12.0);
        expect(byName['Eggs']!.mealType, MealType.breakfast);
        expect(byName['Chicken']!.kcal, 310);

        final totals = await food.watchDailyTotals(today).first;
        expect(totals.kcal, 450);
        expect(totals.proteinG, closeTo(57.0, 1e-9));

        final weightRows = await weight.listAll();
        expect(weightRows, hasLength(1));
        expect(weightRows.first.value, 80.0);
        expect(weightRows.first.unit, WeightUnit.kg);

        final sessionRows = await sessions.listAll();
        expect(sessionRows, hasLength(1));
        expect(sessionRows.first.id, sessionId);

        final setRows = await sets.listForSession(sessionId);
        expect(setRows, hasLength(2));
        expect(setRows[0].orderIndex, 0);
        expect(setRows[0].weight, 80.0);
        expect(setRows[1].orderIndex, 1);
        expect(setRows[1].weight, 82.5);
        expect(
          setRows.every((s) => s.status == WorkoutSetStatus.completed),
          isTrue,
        );

        await db.close();
      }
    },
  );
}

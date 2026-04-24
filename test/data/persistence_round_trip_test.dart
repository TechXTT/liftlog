// ignore_for_file: depend_on_referenced_packages
// `sqlite3` is used only here — and only in a test — to stand up a
// schema-v2 shape on disk so the live AppDatabase's onUpgrade can be
// exercised. It's a transitive dep via `drift/native.dart` +
// `sqlite3_flutter_libs` (NativeDatabase uses it under the hood), so
// no new pub dep is introduced. Adding it to `dev_dependencies` would
// also work but widens the dependency surface for a single test.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
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
        raw.execute(
          "INSERT INTO workout_sessions (started_at) VALUES (1000)",
        );
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

    test('adds source columns with default "userEntered" on every table',
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
      expect(
        await readSource('exercise_sets'),
        ['userEntered', 'userEntered', 'userEntered'],
      );
    });

    test('creates exercises table and seeds distinct exercise names once',
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
      final names =
          rows.map((r) => r.read<String>('canonical_name')).toList();
      // V2 sample has "Bench Press" (x2) and "Squat" (x1) → 2 distinct.
      expect(names, ['Bench Press', 'Squat']);

      // Also confirm `exercise_id` FK column was added (nullable, no
      // backfill in this PR — see database.dart onUpgrade comment).
      final setRows = await db
          .customSelect('SELECT exercise_id FROM exercise_sets ORDER BY id ASC')
          .get();
      expect(setRows, hasLength(3));
      expect(
        setRows.every((r) => r.read<int?>('exercise_id') == null),
        isTrue,
        reason: 'v2→v3 migration does not backfill exercise_id',
      );
    });

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
      expect(secondCount, firstCount,
          reason: 'seeding must be idempotent under repeated open');
    });
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

      await food.add(FoodEntriesCompanion.insert(
        timestamp: today,
        name: const Value('Eggs'),
        kcal: 140,
        proteinG: 12.0,
        mealType: MealType.breakfast,
        entryType: FoodEntryType.manual,
      ));
      await food.add(FoodEntriesCompanion.insert(
        timestamp: today.add(const Duration(hours: 4)),
        name: const Value('Chicken'),
        kcal: 310,
        proteinG: 45.0,
        mealType: MealType.lunch,
        entryType: FoodEntryType.manual,
      ));

      await weight.add(BodyWeightLogsCompanion.insert(
        timestamp: today,
        value: 80.0,
        unit: WeightUnit.kg,
      ));

      sessionId = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: today.add(const Duration(hours: 6)),
      ));

      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: sessionId,
        exerciseName: 'Bench Press',
        reps: 8,
        weight: 80.0,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 0,
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: sessionId,
        exerciseName: 'Bench Press',
        reps: 7,
        weight: 82.5,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 1,
      ));

      await db.close();
    }

    // File must be on disk between phases.
    expect(File(dbPath).existsSync(), isTrue,
        reason: 'DB file must survive close');

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
      expect(setRows.every((s) => s.status == WorkoutSetStatus.completed), isTrue);

      await db.close();
    }
  });
}

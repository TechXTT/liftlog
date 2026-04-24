// Unit tests for the LiftLog data-export service (issue #37).
//
// The export service is intentionally pure: `buildExportJson` takes a
// `db` + `now` and returns a UTF-8 JSON string, no side effects. That
// lets us seed an in-memory Drift DB with rows across all four
// entities, call the service, and assert the full JSON shape in one
// place. Deterministic ordering (id ascending within each array) and
// enum-as-`.name` serialization are the stability contract; we test
// both explicitly because any regression there is a silent data-shape
// break for anyone already backing up their data.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/data/repositories/daily_target_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/data/repositories/routine_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/export/export_service.dart';

void main() {
  late AppDatabase db;
  late FoodEntryRepository foods;
  late BodyWeightLogRepository weights;
  late WorkoutSessionRepository sessions;
  late ExerciseSetRepository sets;
  late ExerciseRepository exerciseCatalog;
  late RoutineRepository routines;
  late DailyTargetRepository dailyTargets;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    foods = FoodEntryRepository(db);
    weights = BodyWeightLogRepository(db);
    sessions = WorkoutSessionRepository(db);
    sets = ExerciseSetRepository(db);
    exerciseCatalog = ExerciseRepository(db);
    routines = RoutineRepository(db);
    dailyTargets = DailyTargetRepository(db);
  });

  tearDown(() async => db.close());

  // Seeds a representative slice of data across all four entities.
  // Chosen to exercise the edges the export contract cares about:
  //  - multiple rows per entity (so sort-by-id asc matters)
  //  - a food entry with `FoodEntryType.estimate` (enum serialization)
  //  - a food entry with `note: null` (null round-trips as JSON null)
  //  - an in-progress workout session with `endedAt: null`
  //  - a completed workout with ≥ 2 sets, one of them `skipped`.
  Future<void> seedAll() async {
    // Food entries — insertion order deliberately scrambles timestamp
    // vs id so the sort-by-id assertion isn't trivially satisfied.
    await foods.add(
      FoodEntriesCompanion.insert(
        timestamp: DateTime.utc(2026, 4, 23, 8, 30),
        name: const Value('Eggs'),
        kcal: 140,
        proteinG: 12.0,
        mealType: MealType.breakfast,
        entryType: FoodEntryType.manual,
      ),
    );
    await foods.add(
      FoodEntriesCompanion.insert(
        timestamp: DateTime.utc(2026, 4, 22, 13, 15),
        name: const Value('Eyeball guac'),
        kcal: 300,
        proteinG: 3.5,
        mealType: MealType.snack,
        entryType: FoodEntryType.estimate,
        note: const Value('rough'),
      ),
    );

    // Body weight logs — two units to catch remap bugs.
    await weights.add(
      BodyWeightLogsCompanion.insert(
        timestamp: DateTime.utc(2026, 4, 23, 7),
        value: 80.5,
        unit: WeightUnit.kg,
      ),
    );
    await weights.add(
      BodyWeightLogsCompanion.insert(
        timestamp: DateTime.utc(2026, 4, 22, 7),
        value: 177.5,
        unit: WeightUnit.lb,
      ),
    );

    // Workout sessions — one completed, one in progress (null endedAt).
    final completedId = await sessions.add(
      WorkoutSessionsCompanion.insert(
        startedAt: DateTime.utc(2026, 4, 21, 18),
        endedAt: Value(DateTime.utc(2026, 4, 21, 19, 5)),
      ),
    );
    await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime.utc(2026, 4, 23, 18)),
    );

    // Sets on the completed session. Include a skipped one.
    await sets.add(
      ExerciseSetsCompanion.insert(
        sessionId: completedId,
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
        sessionId: completedId,
        exerciseName: 'Bench Press',
        reps: 8,
        weight: 80.0,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.skipped,
        orderIndex: 1,
      ),
    );

    // Routines + line items (schema v4, issue #52). Seed one routine
    // with two lineup entries — one fully targeted, one with every
    // target field null — so the export proves both paths.
    final bench = await exerciseCatalog.addIfMissing(
      'Bench Press',
      source: Source.userEntered,
    );
    final squat = await exerciseCatalog.addIfMissing(
      'Squat',
      source: Source.userEntered,
    );
    final routineId = await routines.add(
      RoutinesCompanion.insert(
        name: 'Push A',
        createdAt: DateTime.utc(2026, 4, 20, 12),
      ),
    );
    await routines.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: routineId,
        exerciseId: bench.id,
        orderIndex: 0,
        targetSets: const Value(4),
        targetReps: const Value(8),
        targetWeight: const Value(80.0),
        targetWeightUnit: const Value(WeightUnit.kg),
      ),
    );
    await routines.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: routineId,
        exerciseId: squat.id,
        orderIndex: 1,
      ),
    );

    // Daily targets (schema v5, issue #59). One default-sourced row and
    // one with `source: imported` so the enum path is exercised.
    await dailyTargets.add(
      DailyTargetsCompanion.insert(
        kcal: 1800,
        proteinG: 120,
        effectiveFrom: DateTime.utc(2026, 1, 1),
        createdAt: DateTime.utc(2026, 1, 1, 9),
      ),
    );
    await dailyTargets.add(
      DailyTargetsCompanion.insert(
        kcal: 2000,
        proteinG: 140,
        effectiveFrom: DateTime.utc(2026, 4, 1),
        createdAt: DateTime.utc(2026, 4, 1, 9),
        source: const Value(Source.imported),
      ),
    );
  }

  test('top-level keys are exactly meta + four entity arrays', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(
      decoded.keys.toSet(),
      {
        'meta',
        'food_entries',
        'body_weight_logs',
        'workout_sessions',
        'exercise_sets',
        'routines',
        'routine_exercises',
        'daily_targets',
      },
      reason: 'exact set of top-level keys is part of the format contract',
    );
  });

  test('meta block carries correct types + counts + exported_at', () async {
    await seedAll();

    final now = DateTime.utc(2026, 4, 24, 9, 14);
    final json = await buildExportJson(db: db, now: now);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final meta = decoded['meta'] as Map<String, dynamic>;

    expect(meta['format_version'], '1');
    expect(meta['format_version'], isA<String>());
    expect(meta['app_version'], isA<String>());
    expect(meta['schema_version'], db.schemaVersion);
    expect(meta['schema_version'], isA<int>());
    expect(meta['exported_at'], now.toIso8601String());
    expect(meta['note'], isA<String>());

    final counts = meta['counts'] as Map<String, dynamic>;
    expect(counts['food_entries'], 2);
    expect(counts['body_weight_logs'], 2);
    expect(counts['workout_sessions'], 2);
    expect(counts['exercise_sets'], 2);
    expect(counts['routines'], 1);
    expect(counts['routine_exercises'], 2);
    expect(counts['daily_targets'], 2);
  });

  test('food entry every-field round-trip with enum + null note', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final foodEntries = (decoded['food_entries'] as List).cast<Map>();
    expect(foodEntries, hasLength(2));

    // Seeded order: "Eggs" first (id=1, breakfast, manual, null note),
    // "Eyeball guac" second (id=2, snack, estimate, note='rough').
    // Export sorts by id ascending, so array order matches insertion.
    final eggs = foodEntries[0];
    expect(eggs['id'], 1);
    expect(eggs['timestamp'], '2026-04-23T08:30:00.000Z');
    expect(eggs['name'], 'Eggs');
    expect(eggs['kcal'], 140);
    expect(eggs['protein_g'], 12.0);
    expect(eggs['meal_type'], 'breakfast');
    expect(eggs['entry_type'], 'manual');
    expect(eggs['note'], isNull);

    final guac = foodEntries[1];
    expect(guac['id'], 2);
    expect(guac['timestamp'], '2026-04-22T13:15:00.000Z');
    expect(guac['name'], 'Eyeball guac');
    expect(guac['kcal'], 300);
    expect(guac['protein_g'], 3.5);
    expect(guac['meal_type'], 'snack');
    // `FoodEntryType.estimate` → exact Dart `.name` string.
    expect(guac['entry_type'], 'estimate');
    expect(guac['note'], 'rough');
  });

  test('body weight log every-field round-trip with both units', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final logs = (decoded['body_weight_logs'] as List).cast<Map>();
    expect(logs, hasLength(2));

    final kgLog = logs[0];
    expect(kgLog['id'], 1);
    expect(kgLog['timestamp'], '2026-04-23T07:00:00.000Z');
    expect(kgLog['value'], 80.5);
    expect(kgLog['unit'], 'kg');

    final lbLog = logs[1];
    expect(lbLog['id'], 2);
    expect(lbLog['timestamp'], '2026-04-22T07:00:00.000Z');
    expect(lbLog['value'], 177.5);
    expect(lbLog['unit'], 'lb');
  });

  test('workout session serializes ended_at as null for in-progress', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final ws = (decoded['workout_sessions'] as List).cast<Map>();
    expect(ws, hasLength(2));

    final completed = ws[0];
    expect(completed['id'], 1);
    expect(completed['started_at'], '2026-04-21T18:00:00.000Z');
    expect(completed['ended_at'], '2026-04-21T19:05:00.000Z');
    expect(completed['note'], isNull);

    final inProgress = ws[1];
    expect(inProgress['id'], 2);
    expect(inProgress['started_at'], '2026-04-23T18:00:00.000Z');
    // Null timestamp must serialize as JSON null, not an empty string
    // and not be omitted. Anyone parsing the export in Python relies
    // on this key always being present.
    expect(inProgress.containsKey('ended_at'), isTrue);
    expect(inProgress['ended_at'], isNull);
    expect(inProgress['note'], isNull);
  });

  test('exercise set every-field round-trip with skipped enum', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final sets = (decoded['exercise_sets'] as List).cast<Map>();
    expect(sets, hasLength(2));

    final first = sets[0];
    expect(first['id'], 1);
    expect(first['session_id'], 1);
    expect(first['exercise_name'], 'Bench Press');
    expect(first['reps'], 8);
    expect(first['weight'], 80.0);
    expect(first['weight_unit'], 'kg');
    expect(first['status'], 'completed');
    expect(first['order_index'], 0);

    final second = sets[1];
    expect(second['id'], 2);
    expect(second['session_id'], 1);
    // The skipped enum must serialize as its Dart `.name` string.
    expect(second['status'], 'skipped');
    expect(second['order_index'], 1);
  });

  test('two consecutive calls produce byte-identical output', () async {
    await seedAll();

    final now = DateTime.utc(2026, 4, 24, 9, 14);
    final a = await buildExportJson(db: db, now: now);
    final b = await buildExportJson(db: db, now: now);
    expect(
      a,
      b,
      reason: 'determinism: same DB + same `now` must emit identical bytes',
    );
  });

  test('each entity array is sorted by id ascending', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    List<int> ids(String key) =>
        (decoded[key] as List).cast<Map>().map((m) => m['id'] as int).toList();

    for (final key in [
      'food_entries',
      'body_weight_logs',
      'workout_sessions',
      'exercise_sets',
      'routines',
      'routine_exercises',
      'daily_targets',
    ]) {
      final got = ids(key);
      final expected = [...got]..sort();
      expect(got, expected, reason: '$key must be id-ascending');
    }
  });

  test('no derived summary keys appear anywhere in the output', () async {
    await seedAll();

    final json = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24, 9, 14),
    );

    // Keyword-level sanity check; if any of these ever leak in, it's
    // a scope violation worth failing loudly on.
    for (final forbidden in [
      'daily_totals',
      'averages',
      'weekly_volumes',
      'weekly_volume',
      'daily_summary',
      'daily_summaries',
    ]) {
      expect(
        json.contains(forbidden),
        isFalse,
        reason: 'derived key "$forbidden" must not appear in export',
      );
    }
  });

  test(
    'empty database still produces a valid shape with zero counts',
    () async {
      // No seed. Exports against an empty DB should still emit the full
      // shape with empty arrays and zeroed counts — a freshly-installed
      // app tapping "export" must not crash.
      final json = await buildExportJson(
        db: db,
        now: DateTime.utc(2026, 4, 24, 9, 14),
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded.keys.toSet(), {
        'meta',
        'food_entries',
        'body_weight_logs',
        'workout_sessions',
        'exercise_sets',
        'routines',
        'routine_exercises',
        'daily_targets',
      });
      expect((decoded['food_entries'] as List), isEmpty);
      expect((decoded['body_weight_logs'] as List), isEmpty);
      expect((decoded['workout_sessions'] as List), isEmpty);
      expect((decoded['exercise_sets'] as List), isEmpty);
      expect((decoded['routines'] as List), isEmpty);
      expect((decoded['routine_exercises'] as List), isEmpty);
      expect((decoded['daily_targets'] as List), isEmpty);

      final counts = (decoded['meta'] as Map<String, dynamic>)['counts'] as Map;
      expect(counts['food_entries'], 0);
      expect(counts['body_weight_logs'], 0);
      expect(counts['workout_sessions'], 0);
      expect(counts['exercise_sets'], 0);
      expect(counts['routines'], 0);
      expect(counts['routine_exercises'], 0);
      expect(counts['daily_targets'], 0);
    },
  );

  test(
    'routines every-field round-trip with source + nullable notes',
    () async {
      await seedAll();

      final json = await buildExportJson(
        db: db,
        now: DateTime.utc(2026, 4, 24, 9, 14),
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final list = (decoded['routines'] as List).cast<Map>();
      expect(list, hasLength(1));

      final r = list.single;
      expect(r['id'], 1);
      expect(r['name'], 'Push A');
      expect(r['notes'], isNull);
      expect(r['created_at'], '2026-04-20T12:00:00.000Z');
      // Source.userEntered is the default applied by the schema.
      expect(r['source'], 'userEntered');
    },
  );

  test(
    'daily_targets every-field round-trip with source + effective_from',
    () async {
      await seedAll();

      final json = await buildExportJson(
        db: db,
        now: DateTime.utc(2026, 4, 24, 9, 14),
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final list = (decoded['daily_targets'] as List).cast<Map>();
      expect(list, hasLength(2));

      // First row: defaulted source.
      final first = list[0];
      expect(first['id'], 1);
      expect(first['kcal'], 1800);
      expect(first['protein_g'], 120.0);
      expect(first['effective_from'], '2026-01-01T00:00:00.000Z');
      expect(first['created_at'], '2026-01-01T09:00:00.000Z');
      expect(first['source'], 'userEntered');

      // Second row: explicit source = imported (enum path).
      final second = list[1];
      expect(second['id'], 2);
      expect(second['kcal'], 2000);
      expect(second['protein_g'], 140.0);
      expect(second['effective_from'], '2026-04-01T00:00:00.000Z');
      expect(second['source'], 'imported');
    },
  );

  test(
    'routine_exercises every-field round-trip including all-null targets',
    () async {
      await seedAll();

      final json = await buildExportJson(
        db: db,
        now: DateTime.utc(2026, 4, 24, 9, 14),
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final list = (decoded['routine_exercises'] as List).cast<Map>();
      expect(list, hasLength(2));

      // First row — fully-targeted lineup entry.
      final first = list[0];
      expect(first['id'], 1);
      expect(first['routine_id'], 1);
      expect(first['exercise_id'], isA<int>());
      expect(first['order_index'], 0);
      expect(first['target_sets'], 4);
      expect(first['target_reps'], 8);
      expect(first['target_weight'], 80.0);
      expect(first['target_weight_unit'], 'kg');

      // Second row — every target column null.
      final second = list[1];
      expect(second['id'], 2);
      expect(second['routine_id'], 1);
      expect(second['order_index'], 1);
      expect(second['target_sets'], isNull);
      expect(second['target_reps'], isNull);
      expect(second['target_weight'], isNull);
      // Null enum serializes as JSON null and the key is always present.
      expect(second.containsKey('target_weight_unit'), isTrue);
      expect(second['target_weight_unit'], isNull);
    },
  );
}

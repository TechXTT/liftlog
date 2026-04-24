// Unit tests for the LiftLog data-import service (issue #41).
//
// The import service is the round-trip partner of the export service
// (`export_service.dart`, issue #37). Tests here enforce four things:
//
//   1. Round-trip fidelity. Seed every entity → `buildExportJson` →
//      wipe-then-import → every field of every row matches.
//   2. Fail-closed validation. A payload with a wrong `format_version`,
//      malformed JSON, or an unknown enum string returns a specific
//      `ImportResult` subclass and does NOT touch the DB.
//   3. Safe mode refuses a non-empty DB. `importJson(safeMode)` returns
//      `ImportDatabaseNotEmpty` with the existing row count intact.
//   4. `importJsonReplacing` wipes-then-inserts atomically via a
//      transaction — pre-existing rows are fully replaced.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/export/export_service.dart';
import 'package:liftlog_app/features/export/import_service.dart';

void main() {
  late AppDatabase db;
  late FoodEntryRepository foods;
  late BodyWeightLogRepository weights;
  late WorkoutSessionRepository sessions;
  late ExerciseSetRepository sets;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    foods = FoodEntryRepository(db);
    weights = BodyWeightLogRepository(db);
    sessions = WorkoutSessionRepository(db);
    sets = ExerciseSetRepository(db);
  });

  tearDown(() async => db.close());

  // Seed mirrors the export-test fixture for parity: two foods (one
  // with a null note, one with an 'estimate' enum value), two weight
  // logs in different units, one completed and one in-progress session,
  // and two sets (one completed, one skipped).
  Future<void> seedAll() async {
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

    final completedId = await sessions.add(
      WorkoutSessionsCompanion.insert(
        startedAt: DateTime.utc(2026, 4, 21, 18),
        endedAt: Value(DateTime.utc(2026, 4, 21, 19, 5)),
      ),
    );
    await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime.utc(2026, 4, 23, 18)),
    );

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
  }

  test('round-trip: export + importReplacing preserves every field', () async {
    await seedAll();

    final now = DateTime.utc(2026, 4, 24, 9, 14);
    final exportedJson = await buildExportJson(db: db, now: now);

    // Capture pre-import snapshots so we can compare after restore.
    final preFoods = [...await foods.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));
    final preWeights = [...await weights.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));
    final preSessions = [...await sessions.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));
    final preSets = [...await sets.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));

    // Wipe + re-import via the replacing path.
    final result = await importJsonReplacing(
      db: db,
      jsonPayload: exportedJson,
      now: now,
    );

    expect(result, isA<ImportSuccess>());
    expect(
      (result as ImportSuccess).rowsImported,
      preFoods.length + preWeights.length + preSessions.length + preSets.length,
    );

    final postFoods = [...await foods.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));
    final postWeights = [...await weights.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));
    final postSessions = [...await sessions.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));
    final postSets = [...await sets.listAll()]
      ..sort((a, b) => a.id.compareTo(b.id));

    expect(postFoods.length, preFoods.length);
    for (var i = 0; i < preFoods.length; i++) {
      final a = preFoods[i];
      final b = postFoods[i];
      expect(b.id, a.id);
      expect(b.timestamp.toUtc(), a.timestamp.toUtc());
      expect(b.name, a.name);
      expect(b.kcal, a.kcal);
      expect(b.proteinG, a.proteinG);
      expect(b.mealType, a.mealType);
      expect(b.entryType, a.entryType);
      expect(b.note, a.note);
    }

    expect(postWeights.length, preWeights.length);
    for (var i = 0; i < preWeights.length; i++) {
      final a = preWeights[i];
      final b = postWeights[i];
      expect(b.id, a.id);
      expect(b.timestamp.toUtc(), a.timestamp.toUtc());
      expect(b.value, a.value);
      expect(b.unit, a.unit);
    }

    expect(postSessions.length, preSessions.length);
    for (var i = 0; i < preSessions.length; i++) {
      final a = preSessions[i];
      final b = postSessions[i];
      expect(b.id, a.id);
      expect(b.startedAt.toUtc(), a.startedAt.toUtc());
      expect(b.endedAt?.toUtc(), a.endedAt?.toUtc());
      expect(b.note, a.note);
    }

    expect(postSets.length, preSets.length);
    for (var i = 0; i < preSets.length; i++) {
      final a = preSets[i];
      final b = postSets[i];
      expect(b.id, a.id);
      expect(b.sessionId, a.sessionId);
      expect(b.exerciseName, a.exerciseName);
      expect(b.reps, a.reps);
      expect(b.weight, a.weight);
      expect(b.weightUnit, a.weightUnit);
      expect(b.status, a.status);
      expect(b.orderIndex, a.orderIndex);
    }
  });

  test('round-trip: second export after import is byte-identical', () async {
    await seedAll();

    final now = DateTime.utc(2026, 4, 24, 9, 14);
    final first = await buildExportJson(db: db, now: now);

    await importJsonReplacing(db: db, jsonPayload: first, now: now);

    final second = await buildExportJson(db: db, now: now);
    expect(
      second,
      first,
      reason:
          'round-trip must preserve id values + ordering exactly, '
          'so re-exporting emits the identical bytes',
    );
  });

  test('format_version mismatch returns ImportFormatVersionMismatch', () async {
    final payload = jsonEncode(<String, Object?>{
      'meta': <String, Object?>{
        'format_version': '2',
        'app_version': '1.0.0+1',
        'schema_version': 2,
        'exported_at': '2026-04-24T09:14:00.000Z',
        'counts': <String, Object?>{
          'food_entries': 0,
          'body_weight_logs': 0,
          'workout_sessions': 0,
          'exercise_sets': 0,
        },
      },
      'food_entries': <Object?>[],
      'body_weight_logs': <Object?>[],
      'workout_sessions': <Object?>[],
      'exercise_sets': <Object?>[],
    });

    // Seed something so we can verify DB is untouched.
    await seedAll();
    final preFoodCount = (await foods.listAll()).length;

    final result = await importJson(
      db: db,
      jsonPayload: payload,
      now: DateTime.utc(2026, 4, 24),
    );

    expect(result, isA<ImportFormatVersionMismatch>());
    final mismatch = result as ImportFormatVersionMismatch;
    expect(mismatch.got, '2');
    expect(mismatch.expected, '1');

    // DB untouched — existing rows still there.
    expect((await foods.listAll()).length, preFoodCount);
  });

  test('safe-mode import on non-empty DB returns ImportDatabaseNotEmpty '
      'without wiping', () async {
    await seedAll();
    final preFoodCount = (await foods.listAll()).length;
    final preTotal =
        preFoodCount +
        (await weights.listAll()).length +
        (await sessions.listAll()).length +
        (await sets.listAll()).length;

    // Build a valid payload from the current DB; importing it into the
    // same (non-empty) DB under safe mode must refuse.
    final payload = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24),
    );

    final result = await importJson(
      db: db,
      jsonPayload: payload,
      now: DateTime.utc(2026, 4, 24),
    );

    expect(result, isA<ImportDatabaseNotEmpty>());
    expect((result as ImportDatabaseNotEmpty).existingRowCount, preTotal);

    // DB state is exactly what it was — safe mode guarantee.
    expect((await foods.listAll()).length, preFoodCount);
  });

  test('malformed JSON returns ImportMalformed without touching DB', () async {
    await seedAll();
    final preFoodCount = (await foods.listAll()).length;

    final result = await importJson(
      db: db,
      jsonPayload: 'not valid json {',
      now: DateTime.utc(2026, 4, 24),
    );

    expect(result, isA<ImportMalformed>());
    expect((result as ImportMalformed).reason, contains('not valid JSON'));
    expect((await foods.listAll()).length, preFoodCount);
  });

  test(
    'unknown enum value (meal_type=brunch) returns ImportMalformed',
    () async {
      final payload = jsonEncode(<String, Object?>{
        'meta': <String, Object?>{
          'format_version': '1',
          'app_version': '1.0.0+1',
          'schema_version': 2,
          'exported_at': '2026-04-24T09:14:00.000Z',
          'counts': <String, Object?>{
            'food_entries': 1,
            'body_weight_logs': 0,
            'workout_sessions': 0,
            'exercise_sets': 0,
          },
        },
        'food_entries': <Object?>[
          <String, Object?>{
            'id': 1,
            'timestamp': '2026-04-23T08:30:00.000Z',
            'name': 'Eggs',
            'kcal': 140,
            'protein_g': 12.0,
            // Invalid enum value.
            'meal_type': 'brunch',
            'entry_type': 'manual',
            'note': null,
          },
        ],
        'body_weight_logs': <Object?>[],
        'workout_sessions': <Object?>[],
        'exercise_sets': <Object?>[],
      });

      final result = await importJsonReplacing(
        db: db,
        jsonPayload: payload,
        now: DateTime.utc(2026, 4, 24),
      );

      expect(result, isA<ImportMalformed>());
      expect(
        (result as ImportMalformed).reason,
        contains('brunch'),
        reason: 'error surfaces the offending enum value for debugging',
      );
      // Empty DB stayed empty — validation failed BEFORE the wipe.
      expect((await foods.listAll()).length, 0);
    },
  );

  test('missing meta block returns ImportMalformed', () async {
    final payload = jsonEncode(<String, Object?>{
      'food_entries': <Object?>[],
      'body_weight_logs': <Object?>[],
      'workout_sessions': <Object?>[],
      'exercise_sets': <Object?>[],
    });

    final result = await importJson(
      db: db,
      jsonPayload: payload,
      now: DateTime.utc(2026, 4, 24),
    );

    expect(result, isA<ImportMalformed>());
    expect((result as ImportMalformed).reason, contains('meta'));
  });

  test(
    'ImportReplacing preserves FK integrity (session_id stays valid)',
    () async {
      await seedAll();
      final json = await buildExportJson(
        db: db,
        now: DateTime.utc(2026, 4, 24),
      );

      await importJsonReplacing(
        db: db,
        jsonPayload: json,
        now: DateTime.utc(2026, 4, 24),
      );

      // Every restored exercise_set.sessionId must reference an existing
      // workout_session.id — if the insert order were wrong we'd either
      // hit a FK violation (exception on insert) or orphan the child
      // rows. A plain lookup is sufficient here.
      final allSessions = await sessions.listAll();
      final sessionIds = allSessions.map((s) => s.id).toSet();
      final allSets = await sets.listAll();
      expect(allSets, isNotEmpty);
      for (final s in allSets) {
        expect(
          sessionIds.contains(s.sessionId),
          isTrue,
          reason:
              'exercise_set.session_id=${s.sessionId} must reference '
              'an existing session after round-trip',
        );
      }
    },
  );

  test('empty payload into empty DB succeeds with 0 rows', () async {
    final payload = await buildExportJson(
      db: db,
      now: DateTime.utc(2026, 4, 24),
    );

    final result = await importJson(
      db: db,
      jsonPayload: payload,
      now: DateTime.utc(2026, 4, 24),
    );
    expect(result, isA<ImportSuccess>());
    expect((result as ImportSuccess).rowsImported, 0);
  });
}

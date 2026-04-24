import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';

void main() {
  late AppDatabase db;
  late WorkoutSessionRepository sessions;
  late ExerciseSetRepository sets;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessions = WorkoutSessionRepository(db);
    sets = ExerciseSetRepository(db);
  });

  tearDown(() async => db.close());

  test(
    'session lifecycle: add → end (update with endedAt) → delete cascades sets',
    () async {
      final sessionId = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 18)),
      );

      for (var i = 0; i < 3; i++) {
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: sessionId,
            exerciseName: 'Bench Press',
            reps: 8,
            weight: 80.0,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: i,
          ),
        );
      }

      expect(await sets.listForSession(sessionId), hasLength(3));

      final session = await sessions.findById(sessionId);
      expect(session, isNotNull);
      await sessions.update(
        session!.copyWith(endedAt: Value(DateTime(2026, 4, 23, 19))),
      );
      expect((await sessions.findById(sessionId))!.endedAt, isNotNull);

      await sessions.delete(sessionId);
      expect(await sessions.findById(sessionId), isNull);
      expect(
        await sets.listForSession(sessionId),
        isEmpty,
        reason: 'onDelete: cascade should remove child sets',
      );
    },
  );

  test(
    'sets for a session are returned ordered by orderIndex ascending',
    () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );

      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Squat',
          reps: 5,
          weight: 100,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 2,
        ),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Squat',
          reps: 5,
          weight: 100,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.planned,
          orderIndex: 0,
        ),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Squat',
          reps: 5,
          weight: 100,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.skipped,
          orderIndex: 1,
        ),
      );

      final ordered = await sets.watchForSession(id).first;
      expect(ordered.map((s) => s.status), [
        WorkoutSetStatus.planned,
        WorkoutSetStatus.skipped,
        WorkoutSetStatus.completed,
      ]);
    },
  );

  test('all three WorkoutSetStatus values round-trip', () async {
    final id = await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
    );

    for (final (i, status) in [
      WorkoutSetStatus.planned,
      WorkoutSetStatus.completed,
      WorkoutSetStatus.skipped,
    ].indexed) {
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Deadlift',
          reps: 5,
          weight: 140,
          weightUnit: WeightUnit.kg,
          status: status,
          orderIndex: i,
        ),
      );
    }

    final rows = await db
        .customSelect('SELECT status FROM exercise_sets ORDER BY order_index')
        .get();
    expect(rows.map((r) => r.read<String>('status')), [
      'planned',
      'completed',
      'skipped',
    ]);
  });

  test('watchAll returns sessions newest-first by startedAt', () async {
    await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 20)),
    );
    await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
    );
    await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 22)),
    );

    final all = await sessions.watchAll().first;
    expect(all.map((s) => s.startedAt), [
      DateTime(2026, 4, 23),
      DateTime(2026, 4, 22),
      DateTime(2026, 4, 20),
    ]);
  });

  group('updateNote', () {
    test('persists a non-null note and round-trips', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );

      await sessions.updateNote(id, 'Felt strong today');
      final row = await sessions.findById(id);
      expect(row, isNotNull);
      expect(row!.note, 'Felt strong today');
    });

    test('empty string and whitespace normalize to null', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(
          startedAt: DateTime(2026, 4, 23),
          note: const Value('Initial'),
        ),
      );

      // Clear via empty string.
      await sessions.updateNote(id, '');
      expect((await sessions.findById(id))!.note, isNull);

      // Whitespace-only also normalizes to null.
      await sessions.updateNote(id, '   ');
      expect((await sessions.findById(id))!.note, isNull);

      // Explicit null clears too.
      await sessions.updateNote(id, 'something');
      await sessions.updateNote(id, null);
      expect((await sessions.findById(id))!.note, isNull);
    });

    test('overwrites existing note (no silent preserve)', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(
          startedAt: DateTime(2026, 4, 23),
          note: const Value('first'),
        ),
      );

      await sessions.updateNote(id, 'second');
      expect((await sessions.findById(id))!.note, 'second');
    });

    test('missing session id throws StateError', () async {
      await expectLater(
        sessions.updateNote(999, 'note'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('listRecentDistinctExerciseNames', () {
    test('empty DB returns an empty list', () async {
      expect(await sets.listRecentDistinctExerciseNames(), isEmpty);
    });

    test('dedups keeping the newest occurrence per name '
        '(Bench → Squat → Bench → Row yields [Row, Bench, Squat])', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );

      // Inserted in order — `id` autoincrements, so id-desc gives us
      // the recency order we want.
      for (final (i, name) in ['Bench', 'Squat', 'Bench', 'Row'].indexed) {
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: name,
            reps: 5,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: i,
          ),
        );
      }

      expect(await sets.listRecentDistinctExerciseNames(), [
        'Row',
        'Bench',
        'Squat',
      ]);
    });

    test('limit caps the returned list', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );

      for (var i = 0; i < 15; i++) {
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Exercise $i',
            reps: 5,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: i,
          ),
        );
      }

      final names = await sets.listRecentDistinctExerciseNames(limit: 5);
      expect(names, hasLength(5));
      // Newest-first — last inserted wins.
      expect(names.first, 'Exercise 14');
      expect(names.last, 'Exercise 10');
    });

    test('treats whitespace-only-different names as distinct '
        '(known behavior — no silent canonicalization)', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );

      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Bench Press',
          reps: 5,
          weight: 80,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 0,
        ),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Bench Press ', // trailing space
          reps: 5,
          weight: 80,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 1,
        ),
      );

      final names = await sets.listRecentDistinctExerciseNames();
      expect(names, ['Bench Press ', 'Bench Press']);
    });
  });

  group('listSessionSetsWithExercise', () {
    test(
      'joins canonical exercise by FK; legacy null-FK rows surface with exercise: null',
      () async {
        final exercisesRepo = ExerciseRepository(db);
        final bench = await exercisesRepo.addIfMissing(
          'Bench Press',
          source: Source.userEntered,
        );

        final id = await sessions.add(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
        );

        // Canonical-linked row.
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Bench Press',
            reps: 8,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 0,
            exerciseId: Value(bench.id),
          ),
        );
        // Legacy row — no FK. Repo must still surface it.
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Mystery Lift',
            reps: 10,
            weight: 40,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 1,
          ),
        );

        final rows = await sets.listSessionSetsWithExercise(id);
        expect(rows, hasLength(2));

        expect(rows[0].set.exerciseName, 'Bench Press');
        expect(rows[0].exercise, isNotNull);
        expect(rows[0].exercise!.canonicalName, 'Bench Press');

        expect(rows[1].set.exerciseName, 'Mystery Lift');
        expect(
          rows[1].exercise,
          isNull,
          reason: 'LEFT JOIN preserves legacy rows without a FK',
        );
      },
    );

    test('returns rows in orderIndex ascending order', () async {
      final exercisesRepo = ExerciseRepository(db);
      final bench = await exercisesRepo.addIfMissing(
        'Bench Press',
        source: Source.userEntered,
      );

      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );

      // Insert out-of-order to ensure the repo query sorts.
      for (final i in [2, 0, 1]) {
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Bench Press',
            reps: 5,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: i,
            exerciseId: Value(bench.id),
          ),
        );
      }

      final rows = await sets.listSessionSetsWithExercise(id);
      expect(rows.map((r) => r.set.orderIndex), [0, 1, 2]);
    });

    test('empty session returns empty list', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23)),
      );
      expect(await sets.listSessionSetsWithExercise(id), isEmpty);
    });
  });

  group('listRangeWithSets', () {
    test('returns only sessions in [from, to) with their sets, '
        'ordered by orderIndex', () async {
      // Before window.
      final oldId = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 3, 1)),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: oldId,
          exerciseName: 'Old lift',
          reps: 5,
          weight: 80,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 0,
        ),
      );

      // Inside window — two sessions, 2 + 1 sets.
      final aId = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 20, 12)),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: aId,
          exerciseName: 'Squat',
          reps: 5,
          weight: 100,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 1,
        ),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: aId,
          exerciseName: 'Squat',
          reps: 5,
          weight: 100,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.planned,
          orderIndex: 0,
        ),
      );

      final bId = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 22, 18)),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: bId,
          exerciseName: 'Bench',
          reps: 8,
          weight: 80,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 0,
        ),
      );

      // Outside window (after `to`).
      final laterId = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 5, 1)),
      );
      await sets.add(
        ExerciseSetsCompanion.insert(
          sessionId: laterId,
          exerciseName: 'Future lift',
          reps: 5,
          weight: 80,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 0,
        ),
      );

      final result = await sessions.listRangeWithSets(
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 27),
      );

      expect(
        result.length,
        2,
        reason: 'only sessions in [from, to) — oldId and laterId excluded',
      );
      expect(result.map((r) => r.session.id), [aId, bId]);
      // Session A sets: orderIndex ascending (planned first, completed second).
      expect(result[0].sets.map((s) => s.orderIndex), [0, 1]);
      expect(result[0].sets.map((s) => s.status), [
        WorkoutSetStatus.planned,
        WorkoutSetStatus.completed,
      ]);
      expect(result[1].sets.length, 1);
    });

    test('returns sessions with no sets as an empty sets list', () async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 21)),
      );

      final result = await sessions.listRangeWithSets(
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 27),
      );
      expect(result.length, 1);
      expect(result.single.session.id, id);
      expect(result.single.sets, isEmpty);
    });

    test('empty window returns empty list', () async {
      final result = await sessions.listRangeWithSets(
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 27),
      );
      expect(result, isEmpty);
    });
  });
}

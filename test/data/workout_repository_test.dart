import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
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

  test('session lifecycle: add → end (update with endedAt) → delete cascades sets',
      () async {
    final sessionId = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 18),
    ));

    for (var i = 0; i < 3; i++) {
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: sessionId,
        exerciseName: 'Bench Press',
        reps: 8,
        weight: 80.0,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: i,
      ));
    }

    expect(await sets.listForSession(sessionId), hasLength(3));

    final session = await sessions.findById(sessionId);
    expect(session, isNotNull);
    await sessions.update(session!.copyWith(
      endedAt: Value(DateTime(2026, 4, 23, 19)),
    ));
    expect((await sessions.findById(sessionId))!.endedAt, isNotNull);

    await sessions.delete(sessionId);
    expect(await sessions.findById(sessionId), isNull);
    expect(await sets.listForSession(sessionId), isEmpty,
        reason: 'onDelete: cascade should remove child sets');
  });

  test('sets for a session are returned ordered by orderIndex ascending',
      () async {
    final id = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23),
    ));

    await sets.add(ExerciseSetsCompanion.insert(
      sessionId: id,
      exerciseName: 'Squat',
      reps: 5,
      weight: 100,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.completed,
      orderIndex: 2,
    ));
    await sets.add(ExerciseSetsCompanion.insert(
      sessionId: id,
      exerciseName: 'Squat',
      reps: 5,
      weight: 100,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.planned,
      orderIndex: 0,
    ));
    await sets.add(ExerciseSetsCompanion.insert(
      sessionId: id,
      exerciseName: 'Squat',
      reps: 5,
      weight: 100,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.skipped,
      orderIndex: 1,
    ));

    final ordered = await sets.watchForSession(id).first;
    expect(ordered.map((s) => s.status),
        [WorkoutSetStatus.planned, WorkoutSetStatus.skipped, WorkoutSetStatus.completed]);
  });

  test('all three WorkoutSetStatus values round-trip', () async {
    final id = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23),
    ));

    for (final (i, status) in [
      WorkoutSetStatus.planned,
      WorkoutSetStatus.completed,
      WorkoutSetStatus.skipped,
    ].indexed) {
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: id,
        exerciseName: 'Deadlift',
        reps: 5,
        weight: 140,
        weightUnit: WeightUnit.kg,
        status: status,
        orderIndex: i,
      ));
    }

    final rows = await db
        .customSelect('SELECT status FROM exercise_sets ORDER BY order_index')
        .get();
    expect(rows.map((r) => r.read<String>('status')),
        ['planned', 'completed', 'skipped']);
  });

  test('watchAll returns sessions newest-first by startedAt', () async {
    await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 20),
    ));
    await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23),
    ));
    await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 22),
    ));

    final all = await sessions.watchAll().first;
    expect(
      all.map((s) => s.startedAt),
      [
        DateTime(2026, 4, 23),
        DateTime(2026, 4, 22),
        DateTime(2026, 4, 20),
      ],
    );
  });

  group('listRangeWithSets', () {
    test('returns only sessions in [from, to) with their sets, '
        'ordered by orderIndex', () async {
      // Before window.
      final oldId = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 3, 1),
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: oldId,
        exerciseName: 'Old lift',
        reps: 5,
        weight: 80,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 0,
      ));

      // Inside window — two sessions, 2 + 1 sets.
      final aId = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 4, 20, 12),
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: aId,
        exerciseName: 'Squat',
        reps: 5,
        weight: 100,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 1,
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: aId,
        exerciseName: 'Squat',
        reps: 5,
        weight: 100,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.planned,
        orderIndex: 0,
      ));

      final bId = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 4, 22, 18),
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: bId,
        exerciseName: 'Bench',
        reps: 8,
        weight: 80,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 0,
      ));

      // Outside window (after `to`).
      final laterId = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 5, 1),
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: laterId,
        exerciseName: 'Future lift',
        reps: 5,
        weight: 80,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 0,
      ));

      final result = await sessions.listRangeWithSets(
        DateTime(2026, 4, 20),
        DateTime(2026, 4, 27),
      );

      expect(result.length, 2,
          reason: 'only sessions in [from, to) — oldId and laterId excluded');
      expect(result.map((r) => r.session.id), [aId, bId]);
      // Session A sets: orderIndex ascending (planned first, completed second).
      expect(result[0].sets.map((s) => s.orderIndex), [0, 1]);
      expect(result[0].sets.map((s) => s.status),
          [WorkoutSetStatus.planned, WorkoutSetStatus.completed]);
      expect(result[1].sets.length, 1);
    });

    test('returns sessions with no sets as an empty sets list', () async {
      final id = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 4, 21),
      ));

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

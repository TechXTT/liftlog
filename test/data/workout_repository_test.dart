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
}

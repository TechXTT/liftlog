import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ExerciseRepository(db);
  });

  tearDown(() async => db.close());

  test('listAll returns rows newest-first (createdAt DESC, id DESC tiebreak)',
      () async {
    // Distinct createdAt timestamps so primary ordering is unambiguous.
    await repo.addIfMissing('Squat', source: Source.userEntered);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    final middle = await repo.addIfMissing('Bench Press', source: Source.userEntered);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.addIfMissing('Deadlift', source: Source.userEntered);

    final rows = await repo.listAll();
    expect(rows.map((r) => r.canonicalName).toList(),
        ['Deadlift', 'Bench Press', 'Squat']);
    expect(rows[1].id, middle.id);
  });

  test('findByName: hit returns row; miss returns null', () async {
    await repo.addIfMissing('Overhead Press', source: Source.userEntered);

    final hit = await repo.findByName('Overhead Press');
    expect(hit, isNotNull);
    expect(hit!.canonicalName, 'Overhead Press');

    final miss = await repo.findByName('Nonexistent Lift');
    expect(miss, isNull);
  });

  test('findByName is case-sensitive and does not trim whitespace', () async {
    // Silent canonicalization would mutate what the user sees — trust
    // rule violation. See repo docstring.
    await repo.addIfMissing('Bench Press', source: Source.userEntered);
    expect(await repo.findByName('bench press'), isNull);
    expect(await repo.findByName('Bench Press '), isNull);
    expect(await repo.findByName('Bench Press'), isNotNull);
  });

  test('addIfMissing then findByName round-trip', () async {
    final row =
        await repo.addIfMissing('Pull-Up', source: Source.userEntered);
    expect(row.canonicalName, 'Pull-Up');

    final found = await repo.findByName('Pull-Up');
    expect(found, isNotNull);
    expect(found!.id, row.id);
  });

  test('addIfMissing is idempotent: second call returns the same row', () async {
    final first = await repo.addIfMissing('Row', source: Source.userEntered);
    final second = await repo.addIfMissing('Row', source: Source.userEntered);
    expect(second.id, first.id);
    expect(second.canonicalName, first.canonicalName);

    final all = await repo.listAll();
    expect(all, hasLength(1), reason: 'UNIQUE should prevent duplicate rows');
  });

  test('addIfMissing accepts an optional muscleGroup', () async {
    final row = await repo.addIfMissing(
      'Incline Bench',
      muscleGroup: 'Chest',
      source: Source.userEntered,
    );
    expect(row.muscleGroup, 'Chest');

    // Second call with no muscle group doesn't clear the existing one —
    // addIfMissing only acts when the row is absent.
    final again =
        await repo.addIfMissing('Incline Bench', source: Source.userEntered);
    expect(again.muscleGroup, 'Chest');
  });

  test('watchAll emits ordered rows', () async {
    await repo.addIfMissing('Deadlift', source: Source.userEntered);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.addIfMissing('Squat', source: Source.userEntered);

    final rows = await repo.watchAll().first;
    expect(rows.map((r) => r.canonicalName).toList(), ['Squat', 'Deadlift']);
  });
}

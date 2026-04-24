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

  test('addIfMissingUserEntered is the feature-facing wrapper over addIfMissing',
      () async {
    // Feature code (lib/features/**) must not reference `Source.` directly
    // (see test/arch/data_access_boundary_test.dart Rule 4). The set-form
    // picker calls this wrapper; it must behave identically to
    // addIfMissing(name, source: Source.userEntered).
    final viaWrapper = await repo.addIfMissingUserEntered('Bench Press');
    expect(viaWrapper.canonicalName, 'Bench Press');

    // Second call is idempotent — UNIQUE on canonicalName + insertOrIgnore.
    final again = await repo.addIfMissingUserEntered('Bench Press');
    expect(again.id, viaWrapper.id);

    // And the underlying addIfMissing returns the same row on a third
    // call — proving the wrapper and the raw API share storage.
    final raw =
        await repo.addIfMissing('Bench Press', source: Source.userEntered);
    expect(raw.id, viaWrapper.id);

    expect(await repo.listAll(), hasLength(1));
  });
}

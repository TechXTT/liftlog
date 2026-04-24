import 'package:drift/drift.dart';

import '../database.dart';
import '../enums.dart';

/// Access to the first-class `Exercises` table (schema v3 — issue #42).
///
/// The `exercises` table was introduced so future adaptive-programming
/// features can address an exercise by id rather than free-form name.
/// For sprint 1 the UI still writes `exerciseName` on `ExerciseSets` as
/// the authoritative name source; this repository is the read surface
/// for the catalogue plus an `addIfMissing` write path so callers (e.g.
/// the v2→v3 seeding pass, or future exercise-pickers) can idempotently
/// register a new exercise without racing the UNIQUE constraint.
class ExerciseRepository {
  ExerciseRepository(this._db);

  final AppDatabase _db;

  /// Streams every row, newest-first. Ordering prefers `createdAt DESC`
  /// and breaks ties on `id DESC` so rows created inside the same Dart
  /// tick (seeding pass uses a single `DateTime.now()`) stay stable.
  Stream<List<Exercise>> watchAll() => (_db.select(_db.exercises)
        ..orderBy([
          (t) => OrderingTerm.desc(t.createdAt),
          (t) => OrderingTerm.desc(t.id),
        ]))
      .watch();

  /// One-shot counterpart to [watchAll]. Widget tests use this to avoid
  /// the Drift + fake_async hang — see the v2 trust-rules note in
  /// `CLAUDE.md` about always pairing `watch*` with `list*`.
  Future<List<Exercise>> listAll() => (_db.select(_db.exercises)
        ..orderBy([
          (t) => OrderingTerm.desc(t.createdAt),
          (t) => OrderingTerm.desc(t.id),
        ]))
      .get();

  /// Returns the row whose `canonicalName == name`, or `null` if no
  /// row matches. Exact-match lookup (case-sensitive, no trimming) —
  /// mirrors how `ExerciseSetRepository.listRecentDistinctExerciseNames`
  /// refuses to canonicalize whitespace: silent normalization would
  /// mutate what the user sees (trust-rule violation).
  Future<Exercise?> findByName(String name) => (_db.select(_db.exercises)
        ..where((t) => t.canonicalName.equals(name))
        ..limit(1))
      .getSingleOrNull();

  /// Returns the row with `id`, or `null` if no row matches.
  ///
  /// Added (#61) for the start-workout-from-routine flow, which reads
  /// `RoutineExercise.exerciseId` and needs the canonical name to seed
  /// `ExerciseSet.exerciseName`. Mirrors `findByName` (exact-match,
  /// single-row, null on miss).
  Future<Exercise?> findById(int id) =>
      (_db.select(_db.exercises)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Feature-facing convenience entry point for the set form's canonical
  /// picker (issue #60).
  ///
  /// The arch guardrail `test/arch/data_access_boundary_test.dart` forbids
  /// `lib/features/**` from referencing `Source.` directly — features must
  /// receive `Source`-typed values from repositories, not construct them
  /// raw. The set-form picker always inserts with `Source.userEntered`
  /// (the user typed a new exercise name), so we expose a dedicated
  /// wrapper that hides the enum from the call site. Delegates to
  /// [addIfMissing] with `source: Source.userEntered`.
  ///
  /// Use this from feature code; use [addIfMissing] from data-layer
  /// callers that need to declare a different provenance (e.g. the
  /// v2→v3 seeding pass, future import flows).
  Future<Exercise> addIfMissingUserEntered(String name) =>
      addIfMissing(name, source: Source.userEntered);

  /// Inserts `name` if it isn't already present, then returns the row
  /// (either the existing one or the one just inserted).
  ///
  /// Idempotent: the `canonicalName UNIQUE` constraint combined with
  /// `InsertMode.insertOrIgnore` means concurrent callers race safely —
  /// at worst we no-op and re-read. The `source` argument is required
  /// (first-class provenance per v2.0 trust rules) but is not persisted
  /// on the `Exercises` table itself; it exists on the argument list so
  /// callers are forced to declare where the insert came from, and so
  /// future schema additions (e.g. per-row `source`) don't require
  /// call-site changes. `muscleGroup` is optional.
  Future<Exercise> addIfMissing(
    String name, {
    String? muscleGroup,
    required Source source,
  }) async {
    await _db.into(_db.exercises).insert(
          ExercisesCompanion.insert(
            canonicalName: name,
            createdAt: DateTime.now(),
            muscleGroup: Value(muscleGroup),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final row = await findByName(name);
    if (row == null) {
      // Should be unreachable: the insert-or-ignore either created the
      // row or found one already present. Surface rather than silently
      // return a placeholder — no silent fallbacks (CLAUDE.md).
      throw StateError(
        'ExerciseRepository.addIfMissing: row for "$name" not found after '
        'insertOrIgnore; the UNIQUE constraint may have been dropped.',
      );
    }
    return row;
  }
}

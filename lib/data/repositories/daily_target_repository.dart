import 'package:drift/drift.dart';

import '../database.dart';

/// Access to the `DailyTargets` table (schema v5 — issue #59, E5 kickoff).
///
/// A daily target is a (kcal, protein_g) pair the user commits to as of
/// a given `effective_from` date. Targets are historical: every edit
/// inserts a new row with a newer `effective_from`; prior rows remain
/// so the UI can show exactly which target governed a given day. This
/// repository has no delete method on purpose — removing a historical
/// target would retroactively change the "active on day X" lookup for
/// every day between the prior and next target, which is a trust-rule
/// violation ("no silent mutation of user-visible numbers" + "no
/// hidden auto-adjustment"). Users who mistype a target create a new
/// row to correct it.
///
/// Ordering convention: `listAll` / `watchAll` return newest-first by
/// `effective_from desc, id desc`. The secondary `id desc` handles the
/// tie where the user set two targets on the same day — the one
/// inserted later wins.
class DailyTargetRepository {
  DailyTargetRepository(this._db);

  final AppDatabase _db;

  /// Inserts [target] and returns the new row's `id`.
  Future<int> add(DailyTargetsCompanion target) =>
      _db.into(_db.dailyTargets).insert(target);

  /// Writes every column of [target] including any nullable columns
  /// that are being cleared. We use `replace` rather than
  /// `update(...).write(...)` because `write` serializes with
  /// `nullToAbsent: true` and would silently preserve cleared
  /// nullables — a trust-rule violation ("no silent mutation"). See the
  /// arch guardrail in `test/arch/data_access_boundary_test.dart`.
  /// `replace` applies its own `whereSamePrimaryKey` so the caller must
  /// not add one. Defensive: the current `DailyTargets` table has no
  /// nullables, but keeping the pattern consistent with every other
  /// repository future-proofs this the day a nullable column lands.
  Future<void> update(DailyTarget target) async {
    await _db.update(_db.dailyTargets).replace(target);
  }

  /// Every target, newest-first by `effectiveFrom desc, id desc`. The
  /// secondary `id desc` is the tie-breaker when two targets share the
  /// same `effectiveFrom` (e.g. user sets twice on the same day — the
  /// later insert wins).
  Future<List<DailyTarget>> listAll() =>
      (_db.select(_db.dailyTargets)..orderBy([
            (t) => OrderingTerm.desc(t.effectiveFrom),
            (t) => OrderingTerm.desc(t.id),
          ]))
          .get();

  /// Streaming counterpart to [listAll]. Widget tests should prefer
  /// [listAll] to avoid the Drift + fake_async hang.
  Stream<List<DailyTarget>> watchAll() =>
      (_db.select(_db.dailyTargets)..orderBy([
            (t) => OrderingTerm.desc(t.effectiveFrom),
            (t) => OrderingTerm.desc(t.id),
          ]))
          .watch();

  /// Returns the target whose `effective_from <= day` with the largest
  /// `effective_from` (and the largest `id` on a tie). `null` when no
  /// target exists yet, or when every target's `effective_from` is
  /// strictly after [day] (i.e. the user hadn't set anything yet on
  /// that day).
  ///
  /// This is the authoritative "what target governed day X" query.
  /// Anyone rendering target-based copy on the Food tab or History
  /// should go through here rather than eyeballing [listAll].
  Future<DailyTarget?> activeOn(DateTime day) =>
      (_db.select(_db.dailyTargets)
            ..where((t) => t.effectiveFrom.isSmallerOrEqualValue(day))
            ..orderBy([
              (t) => OrderingTerm.desc(t.effectiveFrom),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Deletes every row — used ONLY by the import-replace flow
  /// (`importJsonReplacing` in `import_service.dart`). Mirrors
  /// `Workout`/`Food`/etc. delete loops in that file, where the
  /// destructive wipe is gated behind the two-stage confirm dialog.
  ///
  /// Intentionally NOT a user-facing delete: the repository has no
  /// `delete(id)` by design (historical integrity — see the class
  /// doc comment). Callers outside the import flow must NOT use this
  /// method; a mistaken call erases every historical target and
  /// retroactively changes every `activeOn(...)` result.
  Future<void> deleteAllForImport() async {
    await _db.delete(_db.dailyTargets).go();
  }
}

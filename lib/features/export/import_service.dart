// LiftLog data import — deserializes a JSON payload produced by
// `buildExportJson` (issue #37) and restores it into an empty-or-to-be-
// wiped Drift DB. This is the round-trip partner of `export_service.dart`.
//
// Scope (issue #41):
//  - One-shot full restore. No merge semantics, no partial import, no
//    diffing against existing rows. If the DB has rows, the caller picks
//    between refusing (safe mode) or wiping.
//  - Trust rules apply: no silent fallbacks, no silent data mutation,
//    explicit user confirm lives in the UI layer. The service-level
//    invariant is "if we return anything other than ImportSuccess, the
//    DB has NOT been modified".
//  - Pure and testable: all inputs passed in, no Flutter / platform
//    imports. Feature-layer code runs under the arch guardrail, which
//    allows only `package:drift/drift.dart' show Value` — hence the
//    dance of writing through Companions rather than constructing Drift
//    table accessors directly.
//
// API surface — two entry points:
//  - `importJson(safeMode: true)` — refuses to touch a non-empty DB,
//    returning `ImportDatabaseNotEmpty(rowCount)`. Use this when the
//    caller hasn't yet confirmed a destructive replace.
//  - `importJsonReplacing()` — always wipes then inserts. Use this
//    AFTER the UI has collected the second destructive confirm.
// Both validate format_version, JSON shape, and every enum string
// BEFORE touching the DB. The two methods share a single transactional
// insert path; only the pre-insert wipe differs.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../data/repositories/body_weight_log_repository.dart';
import '../../data/repositories/daily_target_repository.dart';
import '../../data/repositories/exercise_set_repository.dart';
import '../../data/repositories/food_entry_repository.dart';
import '../../data/repositories/routine_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import 'export_service.dart';

/// Result of an import attempt.
///
/// Sealed so controllers can `switch` exhaustively without a default —
/// any new result type at the service layer forces a compile-time visit
/// of every caller. The `reason` / metadata on each non-success subclass
/// is what the UI renders into the SnackBar.
sealed class ImportResult {
  const ImportResult();
}

/// Import succeeded. [rowsImported] is the total count across all four
/// entity tables — matches the sum of counts in the source payload.
class ImportSuccess extends ImportResult {
  const ImportSuccess({required this.rowsImported});
  final int rowsImported;
}

/// The payload's `meta.format_version` didn't match the current app's
/// [kExportFormatVersion]. No rows were inserted and the DB was not
/// touched. [got] is the offending value verbatim.
class ImportFormatVersionMismatch extends ImportResult {
  const ImportFormatVersionMismatch({
    required this.got,
    required this.expected,
  });
  final String got;
  final String expected;
}

/// The DB had rows and the caller asked for a safe import. No rows were
/// inserted and the DB was not touched. [existingRowCount] is the total
/// across all four entities — surfaced in the UI so the user sees what
/// they'd be replacing.
class ImportDatabaseNotEmpty extends ImportResult {
  const ImportDatabaseNotEmpty({required this.existingRowCount});
  final int existingRowCount;
}

/// The JSON was malformed, missing a required key, had a wrong type, or
/// contained an unknown enum string. No rows were inserted and the DB
/// was not touched. [reason] is a short human-readable string suitable
/// for the SnackBar.
class ImportMalformed extends ImportResult {
  const ImportMalformed({required this.reason});
  final String reason;
}

/// Parses and validates [jsonPayload] without modifying the DB when the
/// DB already has rows.
///
/// Validation order (fail-fast, DB-untouched):
///  1. JSON decodes to a `Map`.
///  2. `meta.format_version` equals [kExportFormatVersion].
///  3. The four entity arrays are lists of maps; every field deserializes
///     cleanly (types + enum `.values.byName` lookups).
///  4. DB is empty — if not, returns `ImportDatabaseNotEmpty`.
///
/// Only after all four passes does it wipe (nothing to wipe — empty DB)
/// and insert. On any validation failure, returns the appropriate
/// `ImportResult` subclass; the DB stays as it was.
///
/// [now] is accepted so the caller can stamp deterministic logs — today
/// we don't actually use it, but the signature mirrors `buildExportJson`
/// and leaves room for a future `imported_at` audit row without changing
/// callers.
Future<ImportResult> importJson({
  required AppDatabase db,
  required String jsonPayload,
  required DateTime now,
}) async {
  final parsed = _parseAndValidate(jsonPayload);
  if (parsed is _ParseFailure) {
    return parsed.result;
  }
  final payload = (parsed as _ParseSuccess).payload;

  final existingRowCount = await _totalRowCount(db);
  if (existingRowCount > 0) {
    return ImportDatabaseNotEmpty(existingRowCount: existingRowCount);
  }

  await _insertAll(db, payload);
  return ImportSuccess(rowsImported: payload.totalRows);
}

/// Always-wipes variant. Assumes the caller has already collected the
/// double-confirm from the user; validates the payload first (so a bad
/// payload does NOT wipe), then wipes and inserts atomically.
///
/// Wipe order is reverse-FK — `exercise_sets` (child) before
/// `workout_sessions` (parent) — and the insert order is forward-FK so
/// parent rows land before children that reference them. Original `id`
/// values are preserved via `Value(id)` on each Companion so
/// `exercise_sets.session_id` continues to reference the correct
/// session row.
Future<ImportResult> importJsonReplacing({
  required AppDatabase db,
  required String jsonPayload,
  required DateTime now,
}) async {
  final parsed = _parseAndValidate(jsonPayload);
  if (parsed is _ParseFailure) {
    return parsed.result;
  }
  final payload = (parsed as _ParseSuccess).payload;

  await db.transaction(() async {
    await _wipeAll(db);
    await _insertAll(db, payload);
  });
  return ImportSuccess(rowsImported: payload.totalRows);
}

/// Two-shot parser result — either the decoded payload, or the
/// pre-formed failure result to return.
sealed class _ParseOutcome {
  const _ParseOutcome();
}

class _ParseSuccess extends _ParseOutcome {
  const _ParseSuccess(this.payload);
  final _ParsedPayload payload;
}

class _ParseFailure extends _ParseOutcome {
  const _ParseFailure(this.result);
  final ImportResult result;
}

/// Fully-validated in-memory shape of the payload. Everything here is
/// ready to pass straight into Companion constructors — type coercions
/// and enum lookups already happened upstream.
class _ParsedPayload {
  _ParsedPayload({
    required this.foodEntries,
    required this.bodyWeightLogs,
    required this.workoutSessions,
    required this.exerciseSets,
    required this.routines,
    required this.routineExercises,
    required this.dailyTargets,
  });

  final List<FoodEntriesCompanion> foodEntries;
  final List<BodyWeightLogsCompanion> bodyWeightLogs;
  final List<WorkoutSessionsCompanion> workoutSessions;
  final List<ExerciseSetsCompanion> exerciseSets;
  final List<RoutinesCompanion> routines;
  final List<RoutineExercisesCompanion> routineExercises;
  final List<DailyTargetsCompanion> dailyTargets;

  int get totalRows =>
      foodEntries.length +
      bodyWeightLogs.length +
      workoutSessions.length +
      exerciseSets.length +
      routines.length +
      routineExercises.length +
      dailyTargets.length;
}

_ParseOutcome _parseAndValidate(String jsonPayload) {
  final Object? raw;
  try {
    raw = jsonDecode(jsonPayload);
  } catch (e) {
    return _ParseFailure(ImportMalformed(reason: 'not valid JSON: $e'));
  }
  if (raw is! Map<String, dynamic>) {
    return const _ParseFailure(
      ImportMalformed(reason: 'top-level JSON value is not an object'),
    );
  }

  final meta = raw['meta'];
  if (meta is! Map<String, dynamic>) {
    return const _ParseFailure(
      ImportMalformed(reason: 'missing or malformed "meta" block'),
    );
  }
  final formatVersion = meta['format_version'];
  if (formatVersion is! String) {
    return const _ParseFailure(
      ImportMalformed(reason: '"meta.format_version" missing or not a string'),
    );
  }
  if (formatVersion != kExportFormatVersion) {
    return _ParseFailure(
      ImportFormatVersionMismatch(
        got: formatVersion,
        expected: kExportFormatVersion,
      ),
    );
  }

  // Each entity array is optional (empty DB exports as empty list); but
  // if present it must be a List<Map>. We also tolerate the key being
  // absent — treat as empty. `routines` / `routine_exercises` were
  // added in schema v4 (issue #52) and `daily_targets` in schema v5
  // (issue #59) — older export files won't have the keys, so the
  // tolerant "missing → empty" behavior is what keeps the
  // `format_version` at '1' across those additions (pre-v4/v5 payloads
  // remain valid).
  final List<FoodEntriesCompanion> foodEntries;
  final List<BodyWeightLogsCompanion> bodyWeightLogs;
  final List<WorkoutSessionsCompanion> workoutSessions;
  final List<ExerciseSetsCompanion> exerciseSets;
  final List<RoutinesCompanion> routines;
  final List<RoutineExercisesCompanion> routineExercises;
  final List<DailyTargetsCompanion> dailyTargets;
  try {
    foodEntries = _parseList(raw['food_entries'], _parseFoodEntry);
    bodyWeightLogs = _parseList(raw['body_weight_logs'], _parseBodyWeightLog);
    workoutSessions = _parseList(raw['workout_sessions'], _parseWorkoutSession);
    exerciseSets = _parseList(raw['exercise_sets'], _parseExerciseSet);
    routines = _parseList(raw['routines'], _parseRoutine);
    routineExercises = _parseList(
      raw['routine_exercises'],
      _parseRoutineExercise,
    );
    dailyTargets = _parseList(raw['daily_targets'], _parseDailyTarget);
  } on _MalformedRow catch (e) {
    return _ParseFailure(ImportMalformed(reason: e.reason));
  }

  return _ParseSuccess(
    _ParsedPayload(
      foodEntries: foodEntries,
      bodyWeightLogs: bodyWeightLogs,
      workoutSessions: workoutSessions,
      exerciseSets: exerciseSets,
      routines: routines,
      routineExercises: routineExercises,
      dailyTargets: dailyTargets,
    ),
  );
}

List<T> _parseList<T>(Object? raw, T Function(Map<String, dynamic>) parseOne) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw _MalformedRow('expected array, got ${raw.runtimeType}');
  }
  return [
    for (final row in raw)
      if (row is Map<String, dynamic>)
        parseOne(row)
      else
        throw _MalformedRow('expected object in array, got ${row.runtimeType}'),
  ];
}

/// Thrown inside the per-row parsers to bubble a reason up to the outer
/// `_parseAndValidate` frame without littering the signature with
/// `Result` returns at every level.
class _MalformedRow implements Exception {
  _MalformedRow(this.reason);
  final String reason;
}

FoodEntriesCompanion _parseFoodEntry(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'food_entries');
  final timestamp = _dateTime(row, 'timestamp', 'food_entries');
  final name = _string(row, 'name', 'food_entries');
  final kcal = _int(row, 'kcal', 'food_entries');
  final proteinG = _double(row, 'protein_g', 'food_entries');
  final mealType = _enum<MealType>(
    row,
    'meal_type',
    'food_entries',
    MealType.values,
  );
  final entryType = _enum<FoodEntryType>(
    row,
    'entry_type',
    'food_entries',
    FoodEntryType.values,
  );
  final note = _nullableString(row, 'note', 'food_entries');

  return FoodEntriesCompanion.insert(
    id: Value(id),
    timestamp: timestamp,
    name: Value(name),
    kcal: kcal,
    proteinG: proteinG,
    mealType: mealType,
    entryType: entryType,
    note: Value(note),
  );
}

BodyWeightLogsCompanion _parseBodyWeightLog(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'body_weight_logs');
  final timestamp = _dateTime(row, 'timestamp', 'body_weight_logs');
  final value = _double(row, 'value', 'body_weight_logs');
  final unit = _enum<WeightUnit>(
    row,
    'unit',
    'body_weight_logs',
    WeightUnit.values,
  );

  return BodyWeightLogsCompanion.insert(
    id: Value(id),
    timestamp: timestamp,
    value: value,
    unit: unit,
  );
}

WorkoutSessionsCompanion _parseWorkoutSession(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'workout_sessions');
  final startedAt = _dateTime(row, 'started_at', 'workout_sessions');
  final endedAt = _nullableDateTime(row, 'ended_at', 'workout_sessions');
  final note = _nullableString(row, 'note', 'workout_sessions');

  return WorkoutSessionsCompanion.insert(
    id: Value(id),
    startedAt: startedAt,
    endedAt: Value(endedAt),
    note: Value(note),
  );
}

RoutinesCompanion _parseRoutine(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'routines');
  final name = _string(row, 'name', 'routines');
  final notes = _nullableString(row, 'notes', 'routines');
  final createdAt = _dateTime(row, 'created_at', 'routines');
  final sourceRaw = _string(row, 'source', 'routines');
  // `parseSourceName` lives in `lib/data/enums.dart` so the arch
  // guardrail (features never reference `Source.` directly) holds.
  // Translates the thrown `ArgumentError` into the malformed-row
  // contract this file already uses for every other enum mismatch.
  final Source source;
  try {
    source = parseSourceName(sourceRaw);
  } on ArgumentError {
    throw _MalformedRow('routines.source: unknown enum value "$sourceRaw"');
  }

  return RoutinesCompanion.insert(
    id: Value(id),
    name: name,
    notes: Value(notes),
    createdAt: createdAt,
    source: Value(source),
  );
}

DailyTargetsCompanion _parseDailyTarget(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'daily_targets');
  final kcal = _int(row, 'kcal', 'daily_targets');
  final proteinG = _double(row, 'protein_g', 'daily_targets');
  final effectiveFrom = _dateTime(row, 'effective_from', 'daily_targets');
  final createdAt = _dateTime(row, 'created_at', 'daily_targets');
  final sourceRaw = _string(row, 'source', 'daily_targets');
  // `parseSourceName` lives in `lib/data/enums.dart` so the arch
  // guardrail (features never reference `Source.` directly) holds.
  final Source source;
  try {
    source = parseSourceName(sourceRaw);
  } on ArgumentError {
    throw _MalformedRow(
      'daily_targets.source: unknown enum value "$sourceRaw"',
    );
  }

  return DailyTargetsCompanion.insert(
    id: Value(id),
    kcal: kcal,
    proteinG: proteinG,
    effectiveFrom: effectiveFrom,
    createdAt: createdAt,
    source: Value(source),
  );
}

RoutineExercisesCompanion _parseRoutineExercise(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'routine_exercises');
  final routineId = _int(row, 'routine_id', 'routine_exercises');
  final exerciseId = _int(row, 'exercise_id', 'routine_exercises');
  final orderIndex = _int(row, 'order_index', 'routine_exercises');
  final targetSets = _nullableInt(row, 'target_sets', 'routine_exercises');
  final targetReps = _nullableInt(row, 'target_reps', 'routine_exercises');
  final targetWeight = _nullableDouble(
    row,
    'target_weight',
    'routine_exercises',
  );
  final targetWeightUnit = _nullableEnum<WeightUnit>(
    row,
    'target_weight_unit',
    'routine_exercises',
    WeightUnit.values,
  );

  return RoutineExercisesCompanion.insert(
    id: Value(id),
    routineId: routineId,
    exerciseId: exerciseId,
    orderIndex: orderIndex,
    targetSets: Value(targetSets),
    targetReps: Value(targetReps),
    targetWeight: Value(targetWeight),
    targetWeightUnit: Value(targetWeightUnit),
  );
}

ExerciseSetsCompanion _parseExerciseSet(Map<String, dynamic> row) {
  final id = _int(row, 'id', 'exercise_sets');
  final sessionId = _int(row, 'session_id', 'exercise_sets');
  final exerciseName = _string(row, 'exercise_name', 'exercise_sets');
  final reps = _int(row, 'reps', 'exercise_sets');
  final weight = _double(row, 'weight', 'exercise_sets');
  final weightUnit = _enum<WeightUnit>(
    row,
    'weight_unit',
    'exercise_sets',
    WeightUnit.values,
  );
  final status = _enum<WorkoutSetStatus>(
    row,
    'status',
    'exercise_sets',
    WorkoutSetStatus.values,
  );
  final orderIndex = _int(row, 'order_index', 'exercise_sets');

  return ExerciseSetsCompanion.insert(
    id: Value(id),
    sessionId: sessionId,
    exerciseName: exerciseName,
    reps: reps,
    weight: weight,
    weightUnit: weightUnit,
    status: status,
    orderIndex: orderIndex,
  );
}

int _int(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  if (v is int) return v;
  throw _MalformedRow('$entity.$key: expected int, got ${v.runtimeType}');
}

double _double(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  // JSON numbers decoded to Dart may arrive as `int` when the value has
  // no fractional part (e.g. `12` vs `12.0`). Accept both and coerce.
  if (v is double) return v;
  if (v is int) return v.toDouble();
  throw _MalformedRow('$entity.$key: expected number, got ${v.runtimeType}');
}

String _string(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  if (v is String) return v;
  throw _MalformedRow('$entity.$key: expected string, got ${v.runtimeType}');
}

int? _nullableInt(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  if (v == null) return null;
  if (v is int) return v;
  throw _MalformedRow(
    '$entity.$key: expected int or null, got ${v.runtimeType}',
  );
}

double? _nullableDouble(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  throw _MalformedRow(
    '$entity.$key: expected number or null, got ${v.runtimeType}',
  );
}

String? _nullableString(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  if (v == null) return null;
  if (v is String) return v;
  throw _MalformedRow(
    '$entity.$key: expected string or null, got ${v.runtimeType}',
  );
}

DateTime _dateTime(Map<String, dynamic> row, String key, String entity) {
  final v = row[key];
  if (v is! String) {
    throw _MalformedRow(
      '$entity.$key: expected ISO-8601 string, got ${v.runtimeType}',
    );
  }
  try {
    // Export writes `toUtc().toIso8601String()` — the trailing `Z` makes
    // `DateTime.parse` return a UTC `DateTime`. We keep it in UTC (no
    // `.toLocal()` call) per the round-trip contract: store what was
    // exported, not a timezone-shifted copy.
    return DateTime.parse(v);
  } catch (e) {
    throw _MalformedRow('$entity.$key: not a valid ISO-8601 string: $v');
  }
}

DateTime? _nullableDateTime(
  Map<String, dynamic> row,
  String key,
  String entity,
) {
  final v = row[key];
  if (v == null) return null;
  return _dateTime(row, key, entity);
}

/// Resolves [row]`[key]` against [values] via `Enum.values.byName`.
///
/// Trust-rule: NEVER fall back to a default on unknown strings — a
/// typo'd enum (`"brunch"` for a meal_type) is a malformed payload, not
/// a license to silently pick `MealType.other`.
T _enum<T extends Enum>(
  Map<String, dynamic> row,
  String key,
  String entity,
  List<T> values,
) {
  final v = row[key];
  if (v is! String) {
    throw _MalformedRow(
      '$entity.$key: expected enum string, got ${v.runtimeType}',
    );
  }
  try {
    return values.byName(v);
  } catch (_) {
    throw _MalformedRow('$entity.$key: unknown enum value "$v"');
  }
}

/// Nullable companion of [_enum]. Accepts `null` (or a missing key) and
/// returns `null`; otherwise resolves like [_enum]. Unknown non-null
/// strings still fail loudly — the `null` tolerance is only for
/// genuinely optional enum columns (e.g. `routine_exercises.target_weight_unit`).
T? _nullableEnum<T extends Enum>(
  Map<String, dynamic> row,
  String key,
  String entity,
  List<T> values,
) {
  final v = row[key];
  if (v == null) return null;
  return _enum<T>(row, key, entity, values);
}

Future<int> _totalRowCount(AppDatabase db) async {
  final foods = FoodEntryRepository(db);
  final weights = BodyWeightLogRepository(db);
  final sessions = WorkoutSessionRepository(db);
  final sets = ExerciseSetRepository(db);
  final routines = RoutineRepository(db);
  final dailyTargets = DailyTargetRepository(db);
  final results = await Future.wait<int>([
    foods.listAll().then((l) => l.length),
    weights.listAll().then((l) => l.length),
    sessions.listAll().then((l) => l.length),
    sets.listAll().then((l) => l.length),
    routines.listAll().then((l) => l.length),
    routines.listAllExercises().then((l) => l.length),
    dailyTargets.listAll().then((l) => l.length),
  ]);
  return results.fold<int>(0, (a, b) => a + b);
}

/// Deletes every row across all four entities in reverse-FK order so
/// `exercise_sets` (child) is cleared before `workout_sessions`
/// (parent). `body_weight_logs` / `food_entries` have no FK relationship
/// to the other two, so their order is arbitrary — we pick a
/// deterministic ordering anyway.
Future<void> _wipeAll(AppDatabase db) async {
  // Feature code can only use `Value` from drift — but `_wipeAll` lives
  // in a service file that the arch guardrail treats as feature code.
  // Use the repositories' existing delete methods in a loop; we don't
  // have a bulk-delete repo method, so we list-then-delete.
  final foods = FoodEntryRepository(db);
  final weights = BodyWeightLogRepository(db);
  final sessions = WorkoutSessionRepository(db);
  final sets = ExerciseSetRepository(db);
  final routines = RoutineRepository(db);
  final dailyTargets = DailyTargetRepository(db);

  // Child first (exercise_sets). Cascade would also handle this via the
  // sessions' `onDelete: cascade`, but being explicit keeps the step
  // visible and doesn't rely on FK semantics that could change.
  for (final s in await sets.listAll()) {
    await sets.delete(s.id);
  }
  for (final s in await sessions.listAll()) {
    await sessions.delete(s.id);
  }
  for (final w in await weights.listAll()) {
    await weights.delete(w.id);
  }
  for (final f in await foods.listAll()) {
    await foods.delete(f.id);
  }
  // Routines cascade to routine_exercises, so deleting the parent is
  // sufficient. We still iterate the parent list explicitly so the
  // order is visible and matches the pattern above.
  for (final r in await routines.listAll()) {
    await routines.delete(r.id);
  }
  // Daily targets — uses the narrow import-only wipe method because
  // the repository deliberately does not expose a per-row delete API
  // (historical integrity — see the repository doc comment).
  await dailyTargets.deleteAllForImport();
}

/// Inserts all rows in FK-forward order (parents before children so
/// `exercise_sets.session_id` resolves to an existing row). Original
/// `id` values from the payload are preserved via `Value(id)` on each
/// Companion — this is what makes `exercise_sets.session_id` continue
/// to reference the correct session after restore.
Future<void> _insertAll(AppDatabase db, _ParsedPayload payload) async {
  final foods = FoodEntryRepository(db);
  final weights = BodyWeightLogRepository(db);
  final sessions = WorkoutSessionRepository(db);
  final sets = ExerciseSetRepository(db);
  final routines = RoutineRepository(db);
  final dailyTargets = DailyTargetRepository(db);

  // food_entries and body_weight_logs have no FK dependencies — order
  // among these two is arbitrary. workout_sessions must precede
  // exercise_sets. `routine_exercises` FK-references both `routines`
  // (parent) and `exercises` (sibling table whose rows are populated
  // by historical seeding, not by this import flow — round-tripping
  // routines currently requires the destination DB to already have
  // the exercise catalog, which mirrors how workout_sessions +
  // exercise_sets share the session-parent contract). `daily_targets`
  // has no FKs to the other entities so its insert order is arbitrary.
  for (final row in payload.foodEntries) {
    await foods.add(row);
  }
  for (final row in payload.bodyWeightLogs) {
    await weights.add(row);
  }
  for (final row in payload.workoutSessions) {
    await sessions.add(row);
  }
  for (final row in payload.exerciseSets) {
    await sets.add(row);
  }
  for (final row in payload.routines) {
    await routines.add(row);
  }
  for (final row in payload.routineExercises) {
    await routines.addExercise(row);
  }
  for (final row in payload.dailyTargets) {
    await dailyTargets.add(row);
  }
}

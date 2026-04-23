// LiftLog data export — builds a deterministic JSON dump of every
// user-entered row across the four domain entities (food entries, body
// weight logs, workout sessions, exercise sets).
//
// Scope (issue #37):
//  - User-entered rows only. Derived values (daily kcal totals, weight
//    deltas, weekly volumes, averages) are computed at read time and
//    are intentionally omitted — their absence is part of the contract
//    documented in `docs/export-format.md`.
//  - Output is UTF-8 JSON. Bytes are deterministic across runs with the
//    same DB + `now`: each array is sorted by `id` ascending in Dart
//    (we don't trust DB order), enum values serialize as their Dart
//    `.name` string (matches Drift's `textEnum` storage verbatim —
//    no remapping), timestamps serialize via `toUtc().toIso8601String()`.
//  - Repository-only data access: every query goes through the four
//    repositories (arch guardrail enforces this for `lib/features/**`).
//
// The authoritative JSON shape lives in `docs/export-format.md`. Any
// change to the shape requires a `format_version` bump (bumped here
// and documented there in the same PR).

import 'dart:convert';

import '../../data/database.dart';
import '../../data/repositories/body_weight_log_repository.dart';
import '../../data/repositories/exercise_set_repository.dart';
import '../../data/repositories/food_entry_repository.dart';
import '../../data/repositories/workout_session_repository.dart';

/// Current export format version. Bump when the JSON shape changes.
const String kExportFormatVersion = '1';

/// Builds the full LiftLog export JSON.
///
/// All four entity arrays are fetched in parallel via the existing
/// repositories, sorted by `id` ascending in Dart, and serialized with
/// stable key order and enum-as-`.name` strings. The result is a single
/// UTF-8 JSON string; encoding is compact (`jsonEncode`'s default) so
/// bytes match deterministically between runs.
///
/// [now] is the caller-supplied timestamp for `meta.exported_at` —
/// passing it in (rather than reading `DateTime.now()` here) is what
/// lets tests assert byte-identical output across two calls.
///
/// [formatVersion] defaults to [kExportFormatVersion]; tests may override.
/// [appVersion] defaults to the current `pubspec.yaml` version; callers
/// at runtime pass through `package_info_plus` values if needed, but
/// today the app pins `1.0.0+1` and that's what we emit.
///
/// [db] is required so we can read `db.schemaVersion` for `meta` and
/// so we can construct the four repositories without needing a Riverpod
/// scope (keeps this function pure and unit-testable).
Future<String> buildExportJson({
  required AppDatabase db,
  required DateTime now,
  String formatVersion = kExportFormatVersion,
  String appVersion = '1.0.0+1',
}) async {
  final foodRepo = FoodEntryRepository(db);
  final weightRepo = BodyWeightLogRepository(db);
  final sessionRepo = WorkoutSessionRepository(db);
  final setRepo = ExerciseSetRepository(db);

  // Fan out all four reads in parallel. None of them depend on each
  // other so there's no ordering concern here.
  final results = await Future.wait<List<Object>>([
    foodRepo.listAll(),
    weightRepo.listAll(),
    sessionRepo.listAll(),
    setRepo.listAll(),
  ]);

  // Each repo's `listAll` orders by timestamp descending (or similar);
  // for the export we want deterministic ordering by `id` ascending so
  // consecutive calls produce byte-identical output even if the
  // repository's default order changes later.
  final foodEntries = [...results[0] as List<FoodEntry>]
    ..sort((a, b) => a.id.compareTo(b.id));
  final bodyWeightLogs = [...results[1] as List<BodyWeightLog>]
    ..sort((a, b) => a.id.compareTo(b.id));
  final workoutSessions = [...results[2] as List<WorkoutSession>]
    ..sort((a, b) => a.id.compareTo(b.id));
  final exerciseSets = [...results[3] as List<ExerciseSet>]
    ..sort((a, b) => a.id.compareTo(b.id));

  final payload = <String, Object?>{
    'meta': <String, Object?>{
      'format_version': formatVersion,
      'app_version': appVersion,
      'schema_version': db.schemaVersion,
      'exported_at': now.toUtc().toIso8601String(),
      'counts': <String, Object?>{
        'food_entries': foodEntries.length,
        'body_weight_logs': bodyWeightLogs.length,
        'workout_sessions': workoutSessions.length,
        'exercise_sets': exerciseSets.length,
      },
      'note':
          'All arrays below are user-entered rows exactly as stored. '
          'Daily totals, weight deltas, weekly workout volumes, and '
          'other summaries are derived by the app at read time and '
          'intentionally not included.',
    },
    'food_entries': foodEntries.map(_foodEntryToJson).toList(),
    'body_weight_logs': bodyWeightLogs.map(_bodyWeightLogToJson).toList(),
    'workout_sessions': workoutSessions.map(_workoutSessionToJson).toList(),
    'exercise_sets': exerciseSets.map(_exerciseSetToJson).toList(),
  };

  return jsonEncode(payload);
}

Map<String, Object?> _foodEntryToJson(FoodEntry e) => <String, Object?>{
      'id': e.id,
      'timestamp': e.timestamp.toUtc().toIso8601String(),
      'name': e.name,
      'kcal': e.kcal,
      'protein_g': e.proteinG,
      'meal_type': e.mealType.name,
      'entry_type': e.entryType.name,
      'note': e.note,
    };

Map<String, Object?> _bodyWeightLogToJson(BodyWeightLog e) => <String, Object?>{
      'id': e.id,
      'timestamp': e.timestamp.toUtc().toIso8601String(),
      'value': e.value,
      'unit': e.unit.name,
    };

Map<String, Object?> _workoutSessionToJson(WorkoutSession s) =>
    <String, Object?>{
      'id': s.id,
      'started_at': s.startedAt.toUtc().toIso8601String(),
      // Nullable: `null` for in-progress sessions. jsonEncode writes
      // JSON `null`, which is the documented format.
      'ended_at': s.endedAt?.toUtc().toIso8601String(),
      'note': s.note,
    };

Map<String, Object?> _exerciseSetToJson(ExerciseSet s) => <String, Object?>{
      'id': s.id,
      'session_id': s.sessionId,
      'exercise_name': s.exerciseName,
      'reps': s.reps,
      'weight': s.weight,
      'weight_unit': s.weightUnit.name,
      'status': s.status.name,
      'order_index': s.orderIndex,
    };

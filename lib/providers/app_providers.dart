import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repositories/body_weight_log_repository.dart';
import '../data/repositories/daily_target_repository.dart';
import '../data/repositories/exercise_repository.dart';
import '../data/repositories/exercise_set_repository.dart';
import '../data/repositories/food_entry_repository.dart';
import '../data/repositories/routine_repository.dart';
import '../data/repositories/workout_session_repository.dart';
import '../sources/cloudkit/cloud_kit_source.dart';
import '../sources/cloudkit/method_channel_cloud_kit_source.dart';
import '../sources/health_kit/health_source.dart';
import '../sources/health_kit/health_source_impl.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final foodEntryRepositoryProvider = Provider<FoodEntryRepository>((ref) {
  return FoodEntryRepository(ref.watch(appDatabaseProvider));
});

final workoutSessionRepositoryProvider = Provider<WorkoutSessionRepository>((
  ref,
) {
  return WorkoutSessionRepository(ref.watch(appDatabaseProvider));
});

final exerciseSetRepositoryProvider = Provider<ExerciseSetRepository>((ref) {
  return ExerciseSetRepository(ref.watch(appDatabaseProvider));
});

final bodyWeightLogRepositoryProvider = Provider<BodyWeightLogRepository>((
  ref,
) {
  return BodyWeightLogRepository(ref.watch(appDatabaseProvider));
});

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepository(ref.watch(appDatabaseProvider));
});

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return RoutineRepository(ref.watch(appDatabaseProvider));
});

final dailyTargetRepositoryProvider = Provider<DailyTargetRepository>((ref) {
  return DailyTargetRepository(ref.watch(appDatabaseProvider));
});

/// HealthKit façade provider (issue #43).
///
/// Production wiring returns [HealthSourceImpl] — the concrete
/// `package:health`-backed bridge. Widget tests override this with
/// `HealthSourceFake` from `lib/sources/health_kit/health_source_fake.dart`
/// so nothing in the test tree reaches a real HealthKit channel.
final healthSourceProvider = Provider<HealthSource>((ref) {
  return HealthSourceImpl();
});

/// CloudKit façade provider (issue #69, S7.1 walking skeleton).
///
/// Production wiring returns [MethodChannelCloudKitSource] — the concrete
/// `dev.techxtt.liftlog/cloudkit` method-channel bridge. Tests override
/// this with `FakeCloudKitSource` from
/// `lib/sources/cloudkit/fake_cloud_kit_source.dart` so nothing in the
/// test tree reaches a real platform channel.
final cloudKitSourceProvider = Provider<CloudKitSource>((ref) {
  return MethodChannelCloudKitSource();
});

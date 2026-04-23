import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repositories/body_weight_log_repository.dart';
import '../data/repositories/exercise_set_repository.dart';
import '../data/repositories/food_entry_repository.dart';
import '../data/repositories/workout_session_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final foodEntryRepositoryProvider = Provider<FoodEntryRepository>((ref) {
  return FoodEntryRepository(ref.watch(appDatabaseProvider));
});

final workoutSessionRepositoryProvider = Provider<WorkoutSessionRepository>((ref) {
  return WorkoutSessionRepository(ref.watch(appDatabaseProvider));
});

final exerciseSetRepositoryProvider = Provider<ExerciseSetRepository>((ref) {
  return ExerciseSetRepository(ref.watch(appDatabaseProvider));
});

final bodyWeightLogRepositoryProvider = Provider<BodyWeightLogRepository>((ref) {
  return BodyWeightLogRepository(ref.watch(appDatabaseProvider));
});

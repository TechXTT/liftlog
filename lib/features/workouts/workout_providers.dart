import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';

final workoutSessionsProvider = StreamProvider<List<WorkoutSession>>((ref) {
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.watchAll();
});

final sessionByIdProvider = StreamProvider.family<WorkoutSession?, int>((ref, id) {
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.watchById(id);
});

final setsForSessionProvider =
    StreamProvider.family<List<ExerciseSet>, int>((ref, id) {
  final repo = ref.watch(exerciseSetRepositoryProvider);
  return repo.watchForSession(id);
});

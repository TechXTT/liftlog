import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/repositories/food_entry_repository.dart';
import '../../providers/app_providers.dart';

final pastFoodDaysProvider = StreamProvider<List<DailySummary>>((ref) {
  final repo = ref.watch(foodEntryRepositoryProvider);
  return repo.watchDailySummaries().map((summaries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return summaries.where((s) => s.day.isBefore(today)).toList();
  });
});

final pastWorkoutsProvider = StreamProvider<List<WorkoutSession>>((ref) {
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.watchAll().map((all) => all.where((s) => s.endedAt != null).toList());
});

final entriesForDayProvider =
    StreamProvider.family<List<FoodEntry>, DateTime>((ref, day) {
  final repo = ref.watch(foodEntryRepositoryProvider);
  return repo.watchByDate(day);
});

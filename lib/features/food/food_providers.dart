import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/repositories/food_entry_repository.dart';
import '../../providers/app_providers.dart';

final todayFoodEntriesProvider = StreamProvider<List<FoodEntry>>((ref) {
  final repo = ref.watch(foodEntryRepositoryProvider);
  return repo.watchByDate(DateTime.now());
});

final todayTotalsProvider = StreamProvider<DailyTotals>((ref) {
  final repo = ref.watch(foodEntryRepositoryProvider);
  return repo.watchDailyTotals(DateTime.now());
});

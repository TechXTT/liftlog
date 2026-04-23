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

/// Feeds the Food tab's recent-foods quick-add strip. Streams the newest
/// distinct-by-name entries across all days (not just today) so the chip
/// strip stays populated even on a fresh morning. See
/// `FoodEntryRepository.watchRecentDistinctNames` for the collapse rule.
final recentFoodsProvider = StreamProvider<List<FoodEntry>>((ref) {
  final repo = ref.watch(foodEntryRepositoryProvider);
  return repo.watchRecentDistinctNames();
});

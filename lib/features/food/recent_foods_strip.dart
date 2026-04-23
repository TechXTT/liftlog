import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import '../../ui/formatters.dart';
import '../../ui/show_save_error.dart';
import 'food_providers.dart';

/// Horizontal strip of one-tap re-log chips shown above the food log list.
///
/// Each chip represents the most recent distinct-named food the user has
/// logged. Tapping inserts a new row that clones the template's
/// `name`/`kcal`/`proteinG`/`mealType`/`entryType` with a fresh `timestamp`
/// of `DateTime.now()`. `note` is deliberately not copied — notes are
/// per-occasion, not per-food.
///
/// When there is nothing to show, the strip collapses to `SizedBox.shrink()`
/// so it reserves zero vertical space.
class RecentFoodsStrip extends ConsumerWidget {
  const RecentFoodsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentFoodsProvider);
    return recent.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 56,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (final e in entries) ...[
                  _RecentFoodChip(template: e),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        );
      },
      // Keep the space collapsed while loading / on error — the rest of
      // the log screen is already the source of truth for entries. A
      // chip-strip error must not mask the main list.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _RecentFoodChip extends ConsumerWidget {
  const _RecentFoodChip({required this.template});

  final FoodEntry template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label =
        '${template.name.isEmpty ? "(unnamed)" : template.name}'
        ' · ${formatKcal(template.kcal)} kcal';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: ActionChip(
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: () => _relog(context, ref),
      ),
    );
  }

  Future<void> _relog(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(foodEntryRepositoryProvider);
    try {
      // Clone the template. `entryType` is copied from the template — a
      // re-log of an `estimate` stays an estimate. We intentionally do NOT
      // copy `note`; notes are per-occasion and would be misleading on a
      // one-tap re-log.
      await repo.add(
        FoodEntriesCompanion.insert(
          timestamp: DateTime.now(),
          name: Value(template.name),
          kcal: template.kcal,
          proteinG: template.proteinG,
          mealType: template.mealType,
          entryType: template.entryType,
        ),
      );
      if (!context.mounted) return;
      showSaveSuccess(
        context,
        'Added ${template.name} (${formatKcal(template.kcal)} kcal)',
      );
    } catch (e) {
      if (!context.mounted) return;
      showSaveError(context, 'add entry', e);
    }
  }
}

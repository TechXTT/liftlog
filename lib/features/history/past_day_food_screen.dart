import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../ui/formatters.dart';
import '../../ui/labels.dart';
import '../food/date_label.dart';
import '../food/estimate_badge.dart';
import 'history_providers.dart';

class PastDayFoodScreen extends ConsumerWidget {
  const PastDayFoodScreen({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesForDayProvider(day));

    return Scaffold(
      appBar: AppBar(title: Text(shortDate(day))),
      body: entries.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No entries for this day.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = list[i];
                  return ListTile(
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            e.name.isEmpty ? '(unnamed)' : e.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        EstimateBadge(entryType: e.entryType),
                      ],
                    ),
                    subtitle: _EntrySubtitle(entry: e),
                    trailing: Text(_formatTime(e.timestamp)),
                  );
                },
              ),
        loading: () => const SizedBox.shrink(),
        error: (err, _) => Center(child: Text('Could not load entries: $err')),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Two-line subtitle for a food entry row: the meal/kcal/protein summary,
/// and (when present) the user-provided note clipped to one line. Mirrors
/// the same widget in `food_log_screen.dart` — kept as a per-screen private
/// class to avoid leaking a UI type across feature folders for a 20-line
/// widget.
class _EntrySubtitle extends StatelessWidget {
  const _EntrySubtitle({required this.entry});

  final FoodEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary =
        '${mealTypeLabel(entry.mealType)} · ${formatKcal(entry.kcal)} kcal · ${formatGrams(entry.proteinG)} g protein';
    final note = entry.note;
    if (note == null || note.isEmpty) {
      return Text(summary);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary),
        Text(
          note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

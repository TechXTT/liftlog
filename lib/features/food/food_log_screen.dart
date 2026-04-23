import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/repositories/food_entry_repository.dart';
import '../../ui/formatters.dart';
import '../../ui/labels.dart';
import 'date_label.dart';
import 'estimate_badge.dart';
import 'food_entry_form_screen.dart';
import 'food_providers.dart';

class FoodLogScreen extends ConsumerWidget {
  const FoodLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(todayFoodEntriesProvider);
    final totals = ref.watch(todayTotalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LiftLog'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TotalsHeader(totals: totals),
          const Divider(height: 1),
          Expanded(
            child: entries.when(
              data: (list) => list.isEmpty
                  ? const _EmptyState()
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
                          onTap: () => _openForm(context, entry: e),
                        );
                      },
                    ),
              loading: () => const SizedBox.shrink(),
              error: (err, _) => _ErrorView(err: err.toString()),
            ),
          ),
        ],
      ),
    );
  }

  void _openForm(BuildContext context, {FoodEntry? entry}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FoodEntryFormScreen(entry: entry),
    ));
  }
}

class _TotalsHeader extends StatelessWidget {
  const _TotalsHeader({required this.totals});
  final AsyncValue<DailyTotals> totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Today, ${shortDate(DateTime.now())}',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          totals.when(
            data: (t) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Metric(value: formatKcal(t.kcal), label: 'kcal'),
                _Metric(value: formatGrams(t.proteinG), label: 'g protein'),
              ],
            ),
            loading: () => const SizedBox(height: 48),
            error: (err, _) => Text('Totals unavailable: $err'),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Text(value, style: theme.textTheme.headlineMedium),
      Text(label, style: theme.textTheme.titleMedium),
    ]);
  }
}

/// Two-line subtitle for a food entry row: the meal/kcal/protein summary,
/// and (when present) the user-provided note clipped to one line.
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No entries yet today.\nTap + to log your first one.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.err});
  final String err;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load entries: $err'),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

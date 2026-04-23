import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/repositories/food_entry_repository.dart';
import 'food_entry_form_screen.dart';
import 'food_providers.dart';
import 'meal_type_label.dart';

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
                          title: Text(e.name.isEmpty ? '(unnamed)' : e.name),
                          subtitle: Text(
                            '${mealTypeLabel(e.mealType)} · ${e.kcal} kcal · ${_formatProtein(e.proteinG)}g protein',
                          ),
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
    final style = Theme.of(context).textTheme.titleMedium;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: totals.when(
        data: (t) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(children: [
              Text('${t.kcal}', style: Theme.of(context).textTheme.headlineMedium),
              Text('kcal today', style: style),
            ]),
            Column(children: [
              Text(
                _formatProtein(t.proteinG),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text('g protein', style: style),
            ]),
          ],
        ),
        loading: () => const SizedBox(height: 48),
        error: (err, _) => Text('Totals unavailable: $err'),
      ),
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

String _formatProtein(double g) {
  if (g == g.roundToDouble()) return g.toStringAsFixed(0);
  return g.toStringAsFixed(1);
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

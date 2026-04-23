import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/labels.dart';
import '../food/date_label.dart';
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
                    title: Text(e.name.isEmpty ? '(unnamed)' : e.name),
                    subtitle: Text(
                      '${mealTypeLabel(e.mealType)} · ${e.kcal} kcal · ${_formatProtein(e.proteinG)}g protein',
                    ),
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

String _formatProtein(double g) {
  if (g == g.roundToDouble()) return g.toStringAsFixed(0);
  return g.toStringAsFixed(1);
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/formatters.dart';
import '../food/date_label.dart';
import '../workouts/workout_session_screen.dart';
import 'history_providers.dart';
import 'past_day_food_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foodDays = ref.watch(pastFoodDaysProvider);
    final workouts = ref.watch(pastWorkoutsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        children: [
          const _SectionHeader(label: 'Past food days'),
          foodDays.when(
            data: (list) => list.isEmpty
                ? const _EmptyInline(text: 'No past days logged yet.')
                : Column(
                    children: [
                      for (final d in list) ...[
                        ListTile(
                          title: Text(shortDate(d.day)),
                          subtitle: Text(
                            '${formatKcal(d.kcal)} kcal · ${formatGrams(d.proteinG)} g protein',
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PastDayFoodScreen(day: d.day),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (err, _) => _ErrorInline(text: 'Food history: $err'),
          ),
          const SizedBox(height: 16),
          const _SectionHeader(label: 'Past workouts'),
          workouts.when(
            data: (list) => list.isEmpty
                ? const _EmptyInline(text: 'No completed workouts yet.')
                : Column(
                    children: [
                      for (final s in list) ...[
                        ListTile(
                          title: Text('Workout · ${shortDate(s.startedAt)}'),
                          subtitle: Text(_workoutSubtitle(s.startedAt, s.endedAt)),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  WorkoutSessionScreen(sessionId: s.id),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    ],
                  ),
            loading: () => const SizedBox.shrink(),
            error: (err, _) => _ErrorInline(text: 'Workout history: $err'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ErrorInline extends StatelessWidget {
  const _ErrorInline({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

String _workoutSubtitle(DateTime start, DateTime? end) {
  final s = '${_two(start.hour)}:${_two(start.minute)}';
  if (end == null) return 'Started $s';
  return 'Started $s · ended ${_two(end.hour)}:${_two(end.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

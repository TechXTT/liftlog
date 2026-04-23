import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import '../food/date_label.dart';
import 'workout_providers.dart';
import 'workout_session_screen.dart';

class WorkoutListScreen extends ConsumerWidget {
  const WorkoutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(workoutSessionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workouts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startSession(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Start workout'),
      ),
      body: sessions.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No workouts yet.\nTap Start workout to begin.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = list[i];
                  final status = s.endedAt == null ? 'In progress' : 'Ended';
                  return ListTile(
                    title: Text('Workout · ${shortDate(s.startedAt)}'),
                    subtitle: Text(status),
                    trailing: Text(_formatTime(s.startedAt)),
                    onTap: () => _openSession(context, s),
                  );
                },
              ),
        loading: () => const SizedBox.shrink(),
        error: (err, _) => Center(child: Text('Could not load workouts: $err')),
      ),
    );
  }

  Future<void> _startSession(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(workoutSessionRepositoryProvider);
    try {
      final id = await repo.add(WorkoutSessionsCompanion.insert(
        startedAt: DateTime.now(),
      ));
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkoutSessionScreen(sessionId: id),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start workout: $e')),
      );
    }
  }

  void _openSession(BuildContext context, WorkoutSession session) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WorkoutSessionScreen(sessionId: session.id),
    ));
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

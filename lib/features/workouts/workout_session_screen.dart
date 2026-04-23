import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import '../../ui/formatters.dart';
import '../../ui/labels.dart';
import '../food/date_label.dart';
import 'exercise_set_form_screen.dart';
import 'workout_providers.dart';

class WorkoutSessionScreen extends ConsumerWidget {
  const WorkoutSessionScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionByIdProvider(sessionId));
    final sets = ref.watch(setsForSessionProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete workout',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      floatingActionButton: session.maybeWhen(
        data: (s) => s == null
            ? null
            : FloatingActionButton(
                onPressed: () => _addSet(context, ref, s.id),
                child: const Icon(Icons.add),
              ),
        orElse: () => null,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionHeader(
            sessionAsync: session,
            onEndSession: () => _endSession(context, ref),
          ),
          const Divider(height: 1),
          Expanded(
            child: sets.when(
              data: (list) => list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No sets yet.\nTap + to add one.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = list[i];
                        return ListTile(
                          title: Text(s.exerciseName),
                          subtitle: Text(
                            '${s.reps} reps · ${formatWeight(s.weight, s.weightUnit)} · ${workoutSetStatusLabel(s.status)}',
                          ),
                          onTap: () =>
                              _editSet(context, s, sessionId, list.length),
                        );
                      },
                    ),
              loading: () => const SizedBox.shrink(),
              error: (err, _) => Center(child: Text('Could not load sets: $err')),
            ),
          ),
        ],
      ),
    );
  }

  void _addSet(BuildContext context, WidgetRef ref, int sessionId) {
    // Use a fresh, synchronous read so we pick the correct next orderIndex
    // even if the stream hasn't emitted the most recent add yet.
    final nextIndex = ref
            .read(setsForSessionProvider(sessionId))
            .maybeWhen(data: (l) => l.length, orElse: () => 0);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExerciseSetFormScreen(
        sessionId: sessionId,
        nextOrderIndex: nextIndex,
      ),
    ));
  }

  void _editSet(
      BuildContext context, ExerciseSet existing, int sessionId, int count) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExerciseSetFormScreen(
        sessionId: sessionId,
        existing: existing,
        nextOrderIndex: count,
      ),
    ));
  }

  Future<void> _endSession(BuildContext context, WidgetRef ref) async {
    final session = await ref
        .read(workoutSessionRepositoryProvider)
        .findById(sessionId);
    if (session == null) return;
    if (session.endedAt != null) return;
    try {
      await ref.read(workoutSessionRepositoryProvider).update(
            session.copyWith(endedAt: Value(DateTime.now())),
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not end session: $e')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workout?'),
        content: const Text(
          'This will delete the session and all of its sets. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      await ref
          .read(workoutSessionRepositoryProvider)
          .delete(sessionId);
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete workout: $e')),
      );
    }
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.sessionAsync,
    required this.onEndSession,
  });

  final AsyncValue<WorkoutSession?> sessionAsync;
  final VoidCallback onEndSession;

  @override
  Widget build(BuildContext context) {
    return sessionAsync.when(
      data: (s) {
        if (s == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Workout not found.'),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Started ${shortDate(s.startedAt)} · ${_formatTime(s.startedAt)}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    if (s.endedAt != null)
                      Text(
                        'Ended ${_formatTime(s.endedAt!)}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                  ],
                ),
              ),
              if (s.endedAt == null)
                FilledButton.tonal(
                  onPressed: onEndSession,
                  child: const Text('End'),
                ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 48),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load workout: $err'),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

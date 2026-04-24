import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import '../../sources/health_kit/health_source.dart';
import '../../ui/labels.dart';
import '../food/date_label.dart';
import 'hk_workout_providers.dart';
import 'workout_providers.dart';
import 'workout_session_screen.dart';

class WorkoutListScreen extends ConsumerWidget {
  const WorkoutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(workoutSessionsProvider);
    final hkAuthorized = ref.watch(hkIsAuthorizedProvider);
    final hkWorkouts = ref.watch(hkWorkoutsLast90dProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Workouts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startSession(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Start workout'),
      ),
      body: sessions.when(
        data: (list) => _buildBody(
          context,
          sessions: list,
          hkAuthorized: hkAuthorized,
          hkWorkouts: hkWorkouts,
        ),
        loading: () => const SizedBox.shrink(),
        error: (err, _) => Center(child: Text('Could not load workouts: $err')),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<WorkoutSession> sessions,
    required AsyncValue<bool> hkAuthorized,
    required AsyncValue<List<HKWorkoutSample>> hkWorkouts,
  }) {
    // Collapse the authorized-state read to a boolean. `loading` and
    // `error` both default to "not authorized" — we never want to flash
    // the external section while we're still resolving auth state, and
    // an error resolving auth state means we don't know, so err toward
    // hiding (per the no-nag-toast fallback).
    final isAuthorized = hkAuthorized.maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );
    // When not authorized, the external section doesn't render at all —
    // no nag, no empty state, just the LiftLog section.
    final externalSamples = isAuthorized
        ? hkWorkouts.maybeWhen(
            data: (v) => v,
            orElse: () => const <HKWorkoutSample>[],
          )
        : const <HKWorkoutSample>[];
    final showExternalSection = isAuthorized;

    if (sessions.isEmpty && !showExternalSection) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No workouts yet.\nTap Start workout to begin.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Single flat `ListView` with manually placed header / divider / row
    // entries. Using one ListView keeps scroll smooth across both
    // sections and avoids nested-scroll quirks.
    final items = <Widget>[];

    if (sessions.isEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No LiftLog workouts yet.\nTap Start workout to begin.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      for (var i = 0; i < sessions.length; i++) {
        final s = sessions[i];
        final status = s.endedAt == null ? 'In progress' : 'Ended';
        items.add(
          ListTile(
            title: Text('Workout · ${shortDate(s.startedAt)}'),
            subtitle: Text(status),
            trailing: Text(_formatTime(s.startedAt)),
            onTap: () => _openSession(context, s),
          ),
        );
        if (i != sessions.length - 1) {
          items.add(const Divider(height: 1));
        }
      }
    }

    if (showExternalSection) {
      items.add(const Divider(height: 1));
      items.add(const _SectionHeader('External workouts'));
      if (externalSamples.isEmpty) {
        items.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'No HealthKit workouts in the last 90 days.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        );
      } else {
        for (var i = 0; i < externalSamples.length; i++) {
          final sample = externalSamples[i];
          items.add(
            ListTile(
              title: Text(hkWorkoutTypeLabel(sample.type)),
              subtitle: Text(
                '${shortDate(sample.startedAt)} · '
                '${_formatTime(sample.startedAt)}'
                '–${_formatTime(sample.endedAt)} · '
                '${_formatDuration(sample.duration)}',
              ),
            ),
          );
          if (i != externalSamples.length - 1) {
            items.add(const Divider(height: 1));
          }
        }
      }
    }

    return ListView(children: items);
  }

  Future<void> _startSession(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(workoutSessionRepositoryProvider);
    try {
      final id = await repo.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime.now()),
      );
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WorkoutSessionScreen(sessionId: id)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start workout: $e')));
    }
  }

  void _openSession(BuildContext context, WorkoutSession session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutSessionScreen(sessionId: session.id),
      ),
    );
  }
}

/// Lightweight section header used between the LiftLog and HealthKit
/// lists. Kept local to this file — no design-system header component
/// exists in this codebase yet and S5.4 doesn't call for one.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Compact duration label — `1h 23m`, `45m`, `42s` for sub-minute.
/// Kept local to the workout-list surface; formatters.dart doesn't have
/// a duration helper and S5.4 is the first consumer that needs one.
String _formatDuration(Duration d) {
  if (d.inMinutes < 1) {
    return '${d.inSeconds}s';
  }
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  return '${h}h ${m}m';
}

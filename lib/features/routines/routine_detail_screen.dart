import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import '../../ui/formatters.dart';
import '../../ui/show_save_error.dart';
import '../workouts/workout_session_screen.dart';
import 'routine_form_screen.dart';
import 'start_from_routine_service.dart';

/// Per-routine detail surface (#61).
///
/// One-shot reads (Future-backed) rather than streams because the form
/// screen is the only place that writes to this routine, and the detail
/// screen is pushed → user pops back → list re-streams. A live stream
/// here would be over-engineering for a single-user tracker.
class RoutineDetailScreen extends ConsumerStatefulWidget {
  const RoutineDetailScreen({super.key, required this.routineId});

  final int routineId;

  @override
  ConsumerState<RoutineDetailScreen> createState() =>
      _RoutineDetailScreenState();
}

class _RoutineDetailScreenState extends ConsumerState<RoutineDetailScreen> {
  Future<_RoutineView>? _future;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RoutineView> _load() async {
    final routineRepo = ref.read(routineRepositoryProvider);
    final exerciseRepo = ref.read(exerciseRepositoryProvider);
    final routine = await routineRepo.findById(widget.routineId);
    if (routine == null) {
      return _RoutineView.missing();
    }
    final lineItems = await routineRepo.listExercises(widget.routineId);
    final rows = <_LineView>[];
    for (final re in lineItems) {
      final ex = await exerciseRepo.findById(re.exerciseId);
      rows.add(
        _LineView(
          name: ex?.canonicalName ?? '(missing exercise)',
          targetSets: re.targetSets,
          targetReps: re.targetReps,
          targetWeight: re.targetWeight,
          targetWeightUnit: re.targetWeightUnit,
        ),
      );
    }
    return _RoutineView(routine: routine, rows: rows);
  }

  Future<void> _openEdit(Routine routine) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutineFormScreen(existing: routine),
      ),
    );
    // Refresh after return — the form might have edited or deleted.
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
  }

  Future<void> _startWorkout() async {
    if (_starting) return;
    setState(() => _starting = true);
    final service = StartFromRoutineService(
      routineRepo: ref.read(routineRepositoryProvider),
      exerciseRepo: ref.read(exerciseRepositoryProvider),
      exerciseSetRepo: ref.read(exerciseSetRepositoryProvider),
      sessionRepo: ref.read(workoutSessionRepositoryProvider),
    );
    try {
      final sessionId = await service.start(
        widget.routineId,
        now: DateTime.now(),
      );
      if (!mounted) return;
      // `pushReplacement` so back navigation from the session screen
      // returns to Routines (the list), not the routine detail. Keeps
      // the "I started a workout" mental model: detail → workout, not
      // detail → workout → detail again.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WorkoutSessionScreen(sessionId: sessionId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      showSaveError(context, 'start workout', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Routine')),
      body: FutureBuilder<_RoutineView>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load: ${snapshot.error}'));
          }
          final view = snapshot.data!;
          if (view.missing) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Routine not found.'),
              ),
            );
          }
          return _RoutineBody(
            view: view,
            starting: _starting,
            onEdit: () => _openEdit(view.routine!),
            onStart: _startWorkout,
          );
        },
      ),
    );
  }
}

class _RoutineBody extends StatelessWidget {
  const _RoutineBody({
    required this.view,
    required this.starting,
    required this.onEdit,
    required this.onStart,
  });

  final _RoutineView view;
  final bool starting;
  final VoidCallback onEdit;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final routine = view.routine!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(routine.name, style: Theme.of(context).textTheme.titleLarge),
              if (routine.notes != null && routine.notes!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(routine.notes!),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: starting || view.rows.isEmpty ? null : onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start workout'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: starting ? null : onEdit,
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: view.rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No exercises yet. Tap Edit to add some.'),
                  ),
                )
              : ListView.separated(
                  itemCount: view.rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = view.rows[i];
                    return ListTile(
                      title: Text(r.name),
                      subtitle: Text(r.formattedTargets()),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// View-model bundle for a single routine.
class _RoutineView {
  _RoutineView({required this.routine, required this.rows}) : missing = false;
  _RoutineView.missing() : routine = null, rows = const [], missing = true;

  final Routine? routine;
  final List<_LineView> rows;
  final bool missing;
}

class _LineView {
  _LineView({
    required this.name,
    required this.targetSets,
    required this.targetReps,
    required this.targetWeight,
    required this.targetWeightUnit,
  });

  final String name;
  final int? targetSets;
  final int? targetReps;
  final double? targetWeight;
  final WeightUnit? targetWeightUnit;

  String formattedTargets() {
    final parts = <String>[];
    if (targetSets != null && targetReps != null) {
      parts.add('${targetSets!} × ${targetReps!}');
    } else if (targetSets != null) {
      parts.add('${targetSets!} sets');
    } else if (targetReps != null) {
      parts.add('${targetReps!} reps');
    }
    if (targetWeight != null && targetWeightUnit != null) {
      parts.add(formatWeight(targetWeight!, targetWeightUnit!));
    }
    if (parts.isEmpty) return 'No targets set';
    return parts.join(' · ');
  }
}

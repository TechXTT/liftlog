import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';

final workoutSessionsProvider = StreamProvider<List<WorkoutSession>>((ref) {
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.watchAll();
});

final sessionByIdProvider = StreamProvider.family<WorkoutSession?, int>((
  ref,
  id,
) {
  final repo = ref.watch(workoutSessionRepositoryProvider);
  return repo.watchById(id);
});

final setsForSessionProvider = StreamProvider.family<List<ExerciseSet>, int>((
  ref,
  id,
) {
  final repo = ref.watch(exerciseSetRepositoryProvider);
  return repo.watchForSession(id);
});

/// Streams each set in a session paired with its canonical [Exercise] row
/// (via the `exercise_id` FK) when one exists. Feeds the grouped session-
/// detail view (S7.5 / issue #73).
///
/// Sets with a null FK surface with `exercise: null`; the feature layer
/// groups those separately using the raw `exerciseName` and renders a
/// muted "(legacy)" suffix on the group header. The trust rule that
/// estimates must be visibly labeled extends to provenance: conflating
/// canonical and non-canonical rows silently is a trust-rule violation.
final setsWithExerciseForSessionProvider =
    StreamProvider.family<List<({ExerciseSet set, Exercise? exercise})>, int>((
      ref,
      id,
    ) {
      final repo = ref.watch(exerciseSetRepositoryProvider);
      return repo.watchSessionSetsWithExercise(id);
    });

/// Feeds the Exercise Set form's recent-exercises chip strip (issue #39).
///
/// `FutureProvider` (not `StreamProvider`) is deliberate: the form is a
/// transient surface opened once per set edit. We don't want a live stream
/// re-rendering chip labels while the user is typing a new exercise name —
/// that would jitter the row beneath the text field as the just-typed name
/// gets persisted and promoted.
final recentExerciseNamesProvider = FutureProvider<List<String>>((ref) {
  final repo = ref.watch(exerciseSetRepositoryProvider);
  return repo.listRecentDistinctExerciseNames();
});

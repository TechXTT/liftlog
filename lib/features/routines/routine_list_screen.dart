import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import 'routine_detail_screen.dart';
import 'routine_form_screen.dart';

/// Stream of routines, newest-first (see `RoutineRepository.watchAll`).
///
/// Lives with the feature rather than in a shared `routines_providers.dart`
/// because no other feature currently consumes it.
final _routinesListProvider = StreamProvider<List<Routine>>((ref) {
  final repo = ref.watch(routineRepositoryProvider);
  return repo.watchAll();
});

/// Routines tab entry point (#61).
///
/// Renders the user's saved routines newest-first with a `+` FAB to open
/// `RoutineFormScreen` in create mode. Tapping a routine opens
/// `RoutineDetailScreen` where the user can edit or start a workout from
/// it.
///
/// The empty-state copy mirrors the Workouts tab — brief, actionable,
/// no marketing fluff.
class RoutineListScreen extends ConsumerWidget {
  const RoutineListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(_routinesListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Routines')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreate(context),
        child: const Icon(Icons.add),
      ),
      body: routines.when(
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No routines yet. Tap + to create one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final r = list[i];
              return ListTile(
                title: Text(r.name),
                subtitle: r.notes == null || r.notes!.trim().isEmpty
                    ? null
                    : Text(
                        r.notes!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => _openDetail(context, r.id),
              );
            },
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (err, _) =>
            Center(child: Text('Could not load routines: $err')),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RoutineFormScreen()),
    );
  }

  void _openDetail(BuildContext context, int routineId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutineDetailScreen(routineId: routineId),
      ),
    );
  }
}

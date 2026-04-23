import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workout_providers.dart';

/// Horizontal strip of recent-exercise-name chips shown beneath the
/// `Exercise` field on the set form (issue #39).
///
/// Tap a chip → [onSelected] fires with the chip's raw exercise name.
/// The caller is responsible for applying that to its `TextEditingController`
/// (setting text + caret) — this widget deliberately stays UI-only so the
/// form keeps ownership of the text field state.
///
/// When there is nothing to show, the strip collapses to `SizedBox.shrink()`
/// so it reserves zero vertical space. Same pattern as the food log's
/// `RecentFoodsStrip`.
///
/// Layout notes:
/// - Chip row height is 48pt (Material `ActionChip` default inside an
///   8pt vertical-padded scroller).
/// - Each chip label is capped at 180pt and uses `TextOverflow.ellipsis`
///   so long names (e.g. "Romanian Deadlift w/ Pause") don't blow up the
///   row height.
class RecentExercisesStrip extends ConsumerWidget {
  const RecentExercisesStrip({super.key, required this.onSelected});

  final void Function(String name) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentExerciseNamesProvider);
    return recent.when(
      data: (names) {
        if (names.isEmpty) return const SizedBox.shrink();
        return Padding(
          // Sit visually close to the Exercise field above — 8pt reads
          // as "for that field".
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final name in names) ...[
                    _RecentExerciseChip(name: name, onSelected: onSelected),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        );
      },
      // Collapse while loading / on error — the form is already usable
      // via direct typing. A chip-strip failure must not block the save
      // path.
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _RecentExerciseChip extends StatelessWidget {
  const _RecentExerciseChip({required this.name, required this.onSelected});

  final String name;
  final void Function(String name) onSelected;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: ActionChip(
        label: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        onPressed: () => onSelected(name),
      ),
    );
  }
}

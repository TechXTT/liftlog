// Daily targets section on the Settings tab (schema v5, issue #59 —
// E5 kickoff).
//
// Renders three things:
//   1. The target that's currently active (via
//      `DailyTargetRepository.activeOn(DateTime.now())`) as a raw
//      "Current: 2000 kcal · 140 g protein (since Apr 1)" string — or
//      "No target set yet" when the repo returns null.
//   2. An Edit button that pushes a `DailyTargetFormScreen`. Every
//      save inserts a new row (historical integrity); the previous
//      active target becomes a past entry in the list below.
//   3. The three most recent targets preceding the active one as a
//      "Previous targets" list, each showing its kcal/protein/date.
//
// Trust rule: raw arithmetic, no inference copy, numbers routed
// through `lib/ui/formatters.dart`. Dates use `shortDate` from
// `lib/features/food/date_label.dart` — same format as the Food tab
// totals header so the visual language stays consistent.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database.dart';
import '../../../providers/app_providers.dart';
import '../../../ui/formatters.dart';
import '../../food/date_label.dart';
import '../daily_target_form_screen.dart';

/// Lists every daily target ever set, newest-first. The section
/// derives both the "current active" row and the "previous targets"
/// list from this single source so the rendering stays consistent
/// with `DailyTargetRepository.activeOn(now)` — the row at index 0
/// whose `effectiveFrom <= today` is the active one, everything
/// after it is history.
final allDailyTargetsProvider = FutureProvider<List<DailyTarget>>((ref) {
  final repo = ref.watch(dailyTargetRepositoryProvider);
  return repo.listAll();
});

class DailyTargetsSection extends ConsumerWidget {
  const DailyTargetsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allDailyTargetsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        async.when(
          data: (targets) => _body(context, ref, targets),
          loading: () => const ListTile(
            title: Text('Loading targets...'),
            leading: Icon(Icons.hourglass_empty),
          ),
          error: (err, _) => ListTile(
            title: const Text('Could not load targets'),
            subtitle: Text('$err'),
            leading: const Icon(Icons.error_outline),
          ),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    List<DailyTarget> targets,
  ) {
    // targets is newest-first by (effectiveFrom desc, id desc). The
    // "active" target is the first whose effectiveFrom <= today —
    // matches `DailyTargetRepository.activeOn(now)`.
    final now = DateTime.now();
    DailyTarget? active;
    final previous = <DailyTarget>[];
    for (final t in targets) {
      if (active == null && !t.effectiveFrom.isAfter(now)) {
        active = t;
      } else if (active != null) {
        previous.add(t);
      }
    }

    final editButton = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          onPressed: () => _openForm(context, ref),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit target'),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active == null)
          const ListTile(
            title: Text('No target set yet'),
            leading: Icon(Icons.flag_outlined),
          )
        else
          ListTile(
            title: Text(
              'Current: ${formatKcal(active.kcal)} kcal · '
              '${formatGrams(active.proteinG)} g protein '
              '(since ${shortDate(active.effectiveFrom)})',
            ),
            leading: const Icon(Icons.flag),
          ),
        editButton,
        if (previous.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Previous targets'),
          ),
          // Cap at 3 per the issue.
          for (final t in previous.take(3))
            ListTile(
              dense: true,
              title: Text(
                '${formatKcal(t.kcal)} kcal · '
                '${formatGrams(t.proteinG)} g protein',
              ),
              subtitle: Text('From ${shortDate(t.effectiveFrom)}'),
            ),
        ],
      ],
    );
  }

  Future<void> _openForm(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DailyTargetFormScreen()),
    );
    // Re-read on return so the section reflects the just-inserted row.
    ref.invalidate(allDailyTargetsProvider);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/delete_confirm.dart';
import '../../ui/formatters.dart';
import '../../ui/show_save_error.dart';
import '../export/export_controller.dart';
import '../export/import_controller.dart';
import '../export/import_service.dart';
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
          const _ExportSection(),
          const SizedBox(height: 12),
          const _ImportSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Export-all-data entry point. Lives at the bottom of the History
/// `ListView` so it scrolls with the rest of the page rather than
/// sitting pinned to the viewport. Disabled during the export run
/// (driven by `ExportController`'s `AsyncValue.isLoading`); shows a
/// success SnackBar on completion or the standard save-error SnackBar
/// on failure.
class _ExportSection extends ConsumerWidget {
  const _ExportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final busy = state.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: FilledButton.tonalIcon(
          onPressed: busy
              ? null
              : () async {
                  try {
                    await ref
                        .read(exportControllerProvider.notifier)
                        .exportNow();
                    if (context.mounted) {
                      showSaveSuccess(context, 'Export shared');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showSaveError(context, 'export data', e);
                    }
                  }
                },
          icon: const Icon(Icons.ios_share),
          label: const Text('Export all data (JSON)'),
        ),
      ),
    );
  }
}

/// Import-all-data entry point. Sits directly below the export button
/// (12pt gap, mirrored styling) so the "backup / restore" pair reads as
/// a unit.
///
/// Flow:
///   1. Tap → iOS document picker (JSON only).
///   2. Parse happens in safe mode — if the payload is malformed or the
///      format_version doesn't match, SnackBar with the reason and bail
///      BEFORE asking any destructive confirms.
///   3. If safe-mode import returns `ImportDatabaseNotEmpty`, show the
///      first destructive confirm (names the row count), then a second
///      destructive amplifier. Only on both confirms do we call
///      `pickAndImport(replace: true)`.
///   4. If safe-mode already succeeded (empty DB), we show the
///      per-entity counts as the success SnackBar and stop.
///
/// Trust rules enforced:
///   - Every destructive path goes through `showDeleteConfirm`.
///   - Non-success `ImportResult`s surface specific SnackBars — no
///     silent swallows.
///   - Button is disabled for the whole round-trip so a double-tap
///     can't race two file pickers.
class _ImportSection extends ConsumerWidget {
  const _ImportSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    final busy = state.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: busy ? null : () => _onTap(context, ref),
          icon: const Icon(Icons.file_download),
          label: const Text('Import all data (replaces current data)'),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(importControllerProvider.notifier);

    // First pass: safe mode. Parses + validates; only touches the DB
    // if it's already empty. This gives us a clean place to surface
    // malformed / version-mismatch failures without a destructive prompt.
    final ImportAttempt first;
    try {
      first = await controller.pickAndImport(replace: false);
    } catch (e) {
      if (context.mounted) showSaveError(context, 'import data', e);
      return;
    }

    if (first is ImportCancelled) return; // quiet cancel, per picker norms
    final firstResult = (first as ImportCompleted).result;

    switch (firstResult) {
      case ImportSuccess(:final rowsImported):
        if (context.mounted) {
          showSaveSuccess(context, 'Imported $rowsImported entries.');
        }
        return;
      case ImportFormatVersionMismatch(:final got, :final expected):
        if (context.mounted) {
          showSaveError(
            context,
            'import data',
            'format_version "$got" is not supported '
                '(this app expects "$expected").',
          );
        }
        return;
      case ImportMalformed(:final reason):
        if (context.mounted) {
          showSaveError(context, 'import data', reason);
        }
        return;
      case ImportDatabaseNotEmpty(:final existingRowCount):
        // Fall through to destructive-confirm flow below.
        if (!context.mounted) return;
        await _confirmAndReplace(context, ref, existingRowCount);
        return;
    }
  }

  /// Two-stage destructive confirm. Both use `showDeleteConfirm` so the
  /// `Delete` button picks up the red destructive styling. Cancel at
  /// either stage leaves the DB unchanged.
  Future<void> _confirmAndReplace(
    BuildContext context,
    WidgetRef ref,
    int existingRowCount,
  ) async {
    final first = await showDeleteConfirm(
      context,
      title: 'Replace all current data?',
      message:
          'Import will replace your local data with the contents of the '
          'picked file. This cannot be undone.',
    );
    if (!first) return;
    if (!context.mounted) return;

    final second = await showDeleteConfirm(
      context,
      title: 'Are you sure?',
      message:
          'Your local DB has $existingRowCount rows. '
          'Import will replace them. Continue?',
    );
    if (!second) return;
    if (!context.mounted) return;

    final controller = ref.read(importControllerProvider.notifier);
    final ImportAttempt attempt;
    try {
      attempt = await controller.pickAndImport(replace: true);
    } catch (e) {
      if (context.mounted) showSaveError(context, 'import data', e);
      return;
    }

    if (attempt is ImportCancelled) return;
    final result = (attempt as ImportCompleted).result;

    switch (result) {
      case ImportSuccess(:final rowsImported):
        if (context.mounted) {
          showSaveSuccess(context, 'Imported $rowsImported entries.');
        }
        return;
      case ImportFormatVersionMismatch(:final got, :final expected):
        if (context.mounted) {
          showSaveError(
            context,
            'import data',
            'format_version "$got" is not supported '
                '(this app expects "$expected").',
          );
        }
        return;
      case ImportMalformed(:final reason):
        if (context.mounted) {
          showSaveError(context, 'import data', reason);
        }
        return;
      case ImportDatabaseNotEmpty():
        // Can't happen on the replace path (service doesn't check), but
        // switch is exhaustive — surface defensively.
        if (context.mounted) {
          showSaveError(
            context,
            'import data',
            'Unexpected non-empty DB during replace.',
          );
        }
        return;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
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

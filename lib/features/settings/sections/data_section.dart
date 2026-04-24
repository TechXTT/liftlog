// Data section of the Settings tab (issue #48). Hosts the
// "Export all data (JSON)" and "Import all data (replaces current data)"
// entry points. Moved here from `lib/features/history/history_screen.dart`
// as part of S5.6 — the controllers (`exportControllerProvider`,
// `importControllerProvider`) are unchanged; only the UI moved.
//
// The two-stage destructive confirm flow for import (first confirm →
// amplifier confirm → `pickAndImport(replace: true)`) is identical to
// the prior History implementation — trust rules enforced there apply
// here too:
//   - Non-success `ImportResult`s surface specific SnackBars — no
//     silent swallows.
//   - Every destructive path goes through `showDeleteConfirm`.
//   - Button is disabled for the whole round-trip so a double-tap
//     can't race two file pickers.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/delete_confirm.dart';
import '../../../ui/show_save_error.dart';
import '../../export/export_controller.dart';
import '../../export/import_controller.dart';
import '../../export/import_service.dart';

class DataSection extends StatelessWidget {
  const DataSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExportTile(),
        SizedBox(height: 12),
        _ImportTile(),
      ],
    );
  }
}

class _ExportTile extends ConsumerWidget {
  const _ExportTile();

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

class _ImportTile extends ConsumerWidget {
  const _ImportTile();

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

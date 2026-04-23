// Export flow controller. Wraps "build JSON → write to temp file →
// open iOS share sheet" as a single `exportNow()` call.
//
// Shape is deliberately minimal: a single `AsyncNotifier<void>` whose
// `AsyncValue.isLoading` drives the button's disabled state in the
// History screen. Errors flow through the notifier (the UI surfaces
// them via `showSaveError`); successes resolve with `AsyncData(null)`.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../providers/app_providers.dart';
import 'export_service.dart';

/// Sanitizes an ISO 8601 timestamp into an iOS-safe filename segment.
///
/// iOS's share sheet / Files app is happy with `:`, but some downstream
/// destinations (e.g. email attachment names rendered into a filesystem
/// that isn't APFS) aren't. `.` in the milliseconds tail is also
/// unnecessary noise in a filename, so we strip both characters. Result
/// looks like `2026-04-24T091400Z`.
String exportFilenameStamp(DateTime now) {
  return now.toUtc().toIso8601String().replaceAll(':', '').replaceAll('.', '');
}

/// State shape is `AsyncValue<void>`:
///  - `AsyncData(null)`  — idle or just-succeeded.
///  - `AsyncLoading()`   — export in flight; button disabled.
///  - `AsyncError(...)`  — last export failed; UI surfaces via
///    `showSaveError` and then the next `exportNow()` clears it.
class ExportController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Idle state. Nothing to prepare.
  }

  /// Builds the export JSON, writes it to a temp file, and opens the
  /// iOS share sheet. Rethrows on failure so the caller can show the
  /// standard save-error SnackBar; trust-rule: no silent fallbacks.
  Future<void> exportNow() async {
    state = const AsyncLoading();
    try {
      final db = ref.read(appDatabaseProvider);
      final now = DateTime.now();
      final json = await buildExportJson(db: db, now: now);

      final tmp = await getTemporaryDirectory();
      final filename = 'liftlog-export-${exportFilenameStamp(now)}.json';
      final file = File('${tmp.path}/$filename');
      await file.writeAsString(json);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'LiftLog export',
        ),
      );
      state = const AsyncData(null);
    } catch (error, stack) {
      // Trust rule: persistence/IO failures must surface. We record
      // the error in state (drives any future UI that observes it),
      // then rethrow so the caller's `catch` block can run the
      // standard save-error SnackBar and keep the user in control.
      state = AsyncError(error, stack);
      rethrow;
    }
  }
}

final exportControllerProvider =
    AsyncNotifierProvider<ExportController, void>(ExportController.new);

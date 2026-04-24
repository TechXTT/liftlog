// Import flow controller. Wraps "open iOS file picker → read UTF-8 →
// parse/validate → return ImportResult" as a single `pickAndImport()`
// call. The UI layer (History tab) is responsible for the two-stage
// destructive confirm flow — this controller stays thin and keeps its
// surface synchronous-looking to the widget.
//
// State shape is `AsyncValue<void>`:
//  - `AsyncData(null)`  — idle or just-succeeded.
//  - `AsyncLoading()`   — import in flight; button disabled.
//  - `AsyncError(...)`  — last import failed with an unhandled exception.
//    Non-success `ImportResult`s do NOT throw — they flow through the
//    return value of `pickAndImport()` so the UI can surface a
//    specific SnackBar per result type.
//
// v2 trust rule: import is restoration, not creation. No entitlement
// gate in this PR (StoreKit is E9); future wiring will NOT gate this
// flow — the comment stays for anyone skimming what "gated" means here.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import 'import_service.dart';

/// The piece of work the controller returns to the widget. Bundles the
/// service-level `ImportResult` with the user-cancel case (no file
/// picked) which otherwise would need its own exception / sentinel.
sealed class ImportAttempt {
  const ImportAttempt();
}

/// User dismissed the file picker. No DB change, no SnackBar — the
/// widget should quietly do nothing.
class ImportCancelled extends ImportAttempt {
  const ImportCancelled();
}

/// File was picked, payload parsed. The wrapped [result] is whatever
/// the service returned — the widget switches on it to decide which
/// SnackBar / follow-up confirm to show.
class ImportCompleted extends ImportAttempt {
  const ImportCompleted(this.result);
  final ImportResult result;
}

/// Opens the iOS document picker, reads the chosen file as UTF-8, and
/// runs the requested import variant against it.
///
/// [replace] — when `false`, uses `importJson` (safe mode: refuses a
/// non-empty DB). When `true`, uses `importJsonReplacing` (wipes then
/// inserts). The UI collects the user's second destructive confirm
/// before setting `replace: true`.
class ImportController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {
    // Idle state. Nothing to prepare.
  }

  Future<ImportAttempt> pickAndImport({required bool replace}) async {
    state = const AsyncLoading();
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) {
        state = const AsyncData(null);
        return const ImportCancelled();
      }
      final path = picked.files.single.path;
      if (path == null) {
        // iOS normally always populates `path`, but defensively handle
        // the cloud-picked case where `bytes` is set and `path` is not.
        final bytes = picked.files.single.bytes;
        if (bytes == null) {
          throw StateError(
            'Selected file has neither a local path nor byte buffer.',
          );
        }
        final payload = utf8.decode(bytes);
        final result = await _runImport(payload, replace: replace);
        state = const AsyncData(null);
        return ImportCompleted(result);
      }
      final payload = await File(path).readAsString();
      final result = await _runImport(payload, replace: replace);
      state = const AsyncData(null);
      return ImportCompleted(result);
    } catch (error, stack) {
      // Trust rule: IO / platform failures must surface. Record in
      // state (drives any observers) and rethrow so the caller's
      // catch can SnackBar it.
      state = AsyncError(error, stack);
      rethrow;
    }
  }

  Future<ImportResult> _runImport(String payload, {required bool replace}) {
    final db = ref.read(appDatabaseProvider);
    final now = DateTime.now();
    if (replace) {
      return importJsonReplacing(db: db, jsonPayload: payload, now: now);
    }
    return importJson(db: db, jsonPayload: payload, now: now);
  }
}

final importControllerProvider = AsyncNotifierProvider<ImportController, void>(
  ImportController.new,
);

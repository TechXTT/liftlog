import 'package:flutter/material.dart';

/// Standardized save/delete error SnackBar.
///
/// Renders `Could not <operation>: <error>` as a SnackBar on the nearest
/// [ScaffoldMessenger]. Use from every save/delete `catch` block in the
/// form screens so the wording stays consistent.
///
/// Trust rule: persistence failures must surface to the UI — no silent
/// fallbacks (see `CLAUDE.md`). This helper is the surfacing mechanism.
void showSaveError(BuildContext context, String operation, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Could not $operation: $error')));
}

/// Standardized success SnackBar for quick, non-destructive actions.
///
/// Neutral visual (no success-green tint — we use the default SnackBar
/// styling so the signal stays calm) and a short 2-second duration so it
/// doesn't linger over the main content. No action button: success paths
/// that need an undo must wire one up explicitly — this helper is for the
/// "done, you can keep going" case.
void showSaveSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

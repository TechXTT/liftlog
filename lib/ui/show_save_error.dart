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
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Could not $operation: $error')),
  );
}

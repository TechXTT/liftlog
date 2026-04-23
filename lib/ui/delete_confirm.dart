import 'package:flutter/material.dart';

/// Unified delete-confirm dialog.
///
/// Returns `true` if the user tapped "Delete", `false` if they tapped
/// "Cancel", and `false` if they dismissed the dialog (barrier tap / back).
///
/// Trust rule: every delete of a logged entry must go through an explicit
/// confirm step (see `CLAUDE.md` — "Delete flows must be explicit and
/// confirmed"). This helper is that step — route every form-level delete
/// through it.
Future<bool> showDeleteConfirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result ?? false;
}

import 'package:flutter/material.dart';

/// Neutral-palette provenance badge that renders "Source: HealthKit"
/// next to body-weight rows that came from the HealthKit bridge.
///
/// Trust rule: provenance is first-class. HK-sourced rows must be
/// visibly distinguishable from user-entered rows. The badge is muted
/// neutral so it stays visually distinct from the mauve `Est.` badge
/// used on food-estimate rows.
///
/// Arch rule: this widget is feature-layer code, so it cannot reference
/// `Source.` directly — the discipline is that features receive
/// provenance as a domain-typed flag (see `_WeightRow.isFromHealthKit`
/// in `body_weight_screen.dart`) and render accordingly.
class SourceBadge extends StatelessWidget {
  const SourceBadge.healthKit({super.key}) : _label = 'Source: HealthKit';

  final String _label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Neutral-surface palette on both light and dark themes. `surfaceContainerHighest`
    // is the Material 3 neutral container token; `onSurfaceVariant` is the
    // matching readable foreground. Deliberately NOT `secondaryContainer`
    // (which the Est. badge uses on a mauve-leaning scheme).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

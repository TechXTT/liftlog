import 'package:flutter/material.dart';

import '../../data/enums.dart';

/// Visible "Est." tag that surfaces when a food entry is an estimate.
///
/// Trust rule: estimated values must be visibly labeled in the UI. Never
/// present an estimate as directly logged.
///
/// The renderer enumerates every [FoodEntryType] case explicitly — no
/// fallthrough default. `savedFood` and `barcode` have no UI producers
/// today, so they resolve to no badge until a real producer lands.
class EstimateBadge extends StatelessWidget {
  const EstimateBadge({super.key, required this.entryType});

  final FoodEntryType entryType;

  @override
  Widget build(BuildContext context) {
    switch (entryType) {
      case FoodEntryType.estimate:
        return const _EstBadge();
      case FoodEntryType.manual:
        return const SizedBox.shrink();
      case FoodEntryType.savedFood:
        // no UI producer today
        return const SizedBox.shrink();
      case FoodEntryType.barcode:
        // no UI producer today
        return const SizedBox.shrink();
    }
  }
}

class _EstBadge extends StatelessWidget {
  const _EstBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Est.',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

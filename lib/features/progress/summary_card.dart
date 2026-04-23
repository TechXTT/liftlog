import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/enums.dart';
import '../../ui/formatters.dart';
import 'progress_data.dart';
import 'progress_providers.dart';

/// Summary card above the window selector on the Progress tab. Renders four
/// metrics in a 2×2 grid: average kcal/day, average protein/day, weight
/// delta, and sessions completed in the window.
///
/// Layout: we use [Wrap] with a fixed-width [_MetricTile] rather than a
/// [GridView] so that at the iPhone 15 viewport (393pt logical width minus
/// two 16pt margins = 361pt usable) the tiles always fit as 2×2 with ~180pt
/// each, but the layout degrades gracefully to 1-per-row on any narrower
/// surface without a hard break. [GridView] would need a nested
/// `shrinkWrap` + `physics: NeverScrollable...` to coexist with the outer
/// `ListView` — [Wrap] sidesteps that complexity.
///
/// Trust rule: every metric that can't be computed honestly (mixed units,
/// no entries, etc) renders as an em-dash (`—`, U+2014), never as `0`. The
/// aggregator in [buildProgressSummary] returns null for those cases; this
/// widget just renders the null.
class SummaryCard extends ConsumerWidget {
  const SummaryCard({super.key});

  /// Fixed tile width. 2 × 170 + 16pt inter-tile gap = 356pt, which fits
  /// inside the ~361pt usable width on iPhone 15 portrait and leaves enough
  /// room for headline-sized numbers without mid-value truncation. Long
  /// values (e.g. `-99.9 kg`) fit on a single line; overflow falls back to
  /// ellipsis via the tile's Text widgets.
  static const double _tileWidth = 170;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(progressSummaryProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: async.when(
          data: (s) => _grid(s),
          loading: () => const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Text('Summary unavailable: $err'),
        ),
      ),
    );
  }

  Widget _grid(ProgressSummary s) {
    return Wrap(
      direction: Axis.horizontal,
      spacing: 16,
      runSpacing: 16,
      children: [
        _MetricTile(
          width: _tileWidth,
          label: 'Avg kcal / day',
          value: s.avgKcalPerDay == null ? null : formatKcal(s.avgKcalPerDay!),
        ),
        _MetricTile(
          width: _tileWidth,
          label: 'Avg protein / day',
          value: s.avgProteinGPerDay == null
              ? null
              : '${formatGrams(s.avgProteinGPerDay!)} g',
        ),
        _MetricTile(
          width: _tileWidth,
          label: 'Weight change',
          value: _formatWeightDelta(s.weightDelta, s.weightDeltaUnit),
        ),
        _MetricTile(
          width: _tileWidth,
          label: 'Sessions completed',
          // Sessions-completed is never null: 0 is an honest number
          // ("you finished nothing this window"), not a missing-data case.
          value: s.sessionsCompleted.toString(),
        ),
      ],
    );
  }

  /// Signed weight delta, routed through [formatWeight] so the unit suffix
  /// stays canonical. Negative values already carry their own minus sign
  /// from `formatGrams`; we only need to prepend `+` for positive values
  /// so the user can distinguish "gained 0.5" from "lost 0.5" at a glance.
  /// Zero renders as `0 kg` with no sign — matching how the number
  /// formatters elsewhere treat it.
  String? _formatWeightDelta(double? delta, WeightUnit? unit) {
    if (delta == null || unit == null) return null;
    final formatted = formatWeight(delta, unit);
    if (delta > 0) return '+$formatted';
    return formatted;
  }
}

/// One tile in the 2×2 summary grid. Fixed-width so the `Wrap` parent can
/// deterministically lay out two-per-row at iPhone 15 width. Renders the
/// label in `bodySmall`, the value in bold `headlineSmall`. Null values
/// become an em-dash (U+2014) — never hidden, never `0`.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            // U+2014 EM DASH — the shared null-marker across the card.
            // Unit tests assert on this literal, so it must match exactly.
            value ?? '\u2014',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

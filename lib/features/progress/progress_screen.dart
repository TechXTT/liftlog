import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/labels.dart';
import 'kcal_bars.dart';
import 'progress_data.dart';
import 'progress_providers.dart';
import 'weight_sparkline.dart';

/// Progress tab v1. Top: 7 / 30 / all segmented selector. Below: body-weight
/// sparkline + daily kcal bars. No tooltips, no axes, no zoom — explicitly
/// scoped out (see issue #23).
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(progressWindowProvider);
    final weight = ref.watch(weightSeriesProvider);
    final kcal = ref.watch(kcalSeriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ProgressWindow>(
                segments: const [
                  ButtonSegment(
                    value: ProgressWindow.sevenDays,
                    label: Text('7d'),
                  ),
                  ButtonSegment(
                    value: ProgressWindow.thirtyDays,
                    label: Text('30d'),
                  ),
                  ButtonSegment(
                    value: ProgressWindow.all,
                    label: Text('All'),
                  ),
                ],
                selected: {window},
                onSelectionChanged: (sel) {
                  ref.read(progressWindowProvider.notifier).state = sel.first;
                },
              ),
            ),
          ),
          _CombinedOrSections(weight: weight, kcal: kcal),
        ],
      ),
    );
  }
}

/// When both series are empty, issue #23 asks for a single combined message
/// rather than two separate empty cards. This widget makes that decision
/// once we have data from both providers.
class _CombinedOrSections extends StatelessWidget {
  const _CombinedOrSections({required this.weight, required this.kcal});

  final AsyncValue<WeightSeries> weight;
  final AsyncValue<KcalSeries> kcal;

  @override
  Widget build(BuildContext context) {
    final wData = weight.asData?.value;
    final kData = kcal.asData?.value;

    if (wData != null && kData != null) {
      final weightEmpty = !wData.hasEnoughForSparkline;
      final kcalEmpty = kData.loggedDayCount == 0;
      if (weightEmpty && kcalEmpty) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 32, 16, 16),
          child: Center(child: Text('Not enough data yet.')),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeightSection(weight: weight),
        const SizedBox(height: 16),
        _KcalSection(kcal: kcal),
      ],
    );
  }
}

class _WeightSection extends StatelessWidget {
  const _WeightSection({required this.weight});

  final AsyncValue<WeightSeries> weight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(label: 'Body weight'),
        weight.when(
          data: (s) => _weightBody(context, s),
          loading: () => const SizedBox(height: WeightSparkline.height),
          error: (err, _) => _ErrorInline(text: 'Weight data: $err'),
        ),
      ],
    );
  }

  Widget _weightBody(BuildContext context, WeightSeries s) {
    if (!s.hasEnoughForSparkline) {
      return const _EmptyInline(
        text: 'Not enough weight data yet — log at least 2 entries.',
      );
    }
    final dominant = s.dominantUnit;
    final children = <Widget>[];
    if (s.mixedUnits && dominant != null) {
      children.add(_MixedUnitsBanner(
        text: 'Mixed units — showing ${weightUnitLabel(dominant)} only',
      ));
    }
    children.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: WeightSparkline(points: s.points),
    ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _KcalSection extends StatelessWidget {
  const _KcalSection({required this.kcal});

  final AsyncValue<KcalSeries> kcal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(label: 'Daily kcal'),
        kcal.when(
          data: (s) => s.loggedDayCount == 0
              ? const _EmptyInline(text: 'No calorie data for this window.')
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: KcalBars(days: s.days),
                ),
          loading: () => const SizedBox(height: KcalBars.height),
          error: (err, _) => _ErrorInline(text: 'Kcal data: $err'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _MixedUnitsBanner extends StatelessWidget {
  const _MixedUnitsBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall,
      ),
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

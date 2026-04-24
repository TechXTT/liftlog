import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import '../../sources/health_kit/health_source.dart';
import '../../ui/formatters.dart';
import '../food/date_label.dart';
import 'body_weight_form_screen.dart';
import 'body_weight_providers.dart';
import 'source_badge.dart';

/// Merged display row for the body-weight list.
///
/// Feature-local type. The `isFromHealthKit` flag is the ONLY provenance
/// signal the UI reads — we deliberately do not reference `Source.` from
/// feature code (arch rule, see `test/arch/data_access_boundary_test.dart`).
/// `userEntry` is set iff the row came from Drift; `hkSample` is set iff
/// the row came from the HealthKit façade. Exactly one is non-null.
class _WeightRow {
  _WeightRow.fromUser(BodyWeightLog entry)
    : userEntry = entry,
      hkSample = null,
      timestamp = entry.timestamp,
      value = entry.value,
      // Unit comes from the Drift row for user entries.
      unit = entry.unit,
      isFromHealthKit = false;

  _WeightRow.fromHealthKit(HKBodyWeightSample sample)
    : userEntry = null,
      hkSample = sample,
      timestamp = sample.timestamp,
      value = sample.value,
      unit = sample.unit,
      isFromHealthKit = true;

  final BodyWeightLog? userEntry;
  final HKBodyWeightSample? hkSample;
  final DateTime timestamp;
  final double value;
  final WeightUnit unit;
  final bool isFromHealthKit;
}

class BodyWeightScreen extends ConsumerWidget {
  const BodyWeightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(bodyWeightLogsProvider);
    final hkSamples = ref.watch(hkBodyWeightProvider);

    // HK auth state drives the "Sync with HealthKit" button visibility.
    // Treat "loading" and "error" as "hide the button" — we don't want
    // the button to flash in and out during the initial fetch, and an
    // error is surfaced via the list error path anyway.
    final bool hasHkData = hkSamples.asData?.value.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Body weight')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Show the "Sync with HealthKit" affordance only when we have
          // no HK data yet — once the stream returns anything, the user
          // has clearly authorized already.
          if (!hasHkData)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.tonalIcon(
                onPressed: () => _requestHealthKit(ref),
                icon: const Icon(Icons.favorite_outline),
                label: const Text('Sync with HealthKit'),
              ),
            ),
          FloatingActionButton(
            onPressed: () => _openForm(context),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: logs.when(
        data: (userEntries) {
          final hk = hkSamples.asData?.value ?? const <HKBodyWeightSample>[];
          final merged = _mergeAndSort(userEntries, hk);
          if (merged.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No weight logs yet.\nTap + to record one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: merged.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final row = merged[i];
              return ListTile(
                title: Text(formatWeight(row.value, row.unit)),
                subtitle: Row(
                  children: [
                    Text(shortDate(row.timestamp)),
                    if (row.isFromHealthKit) ...[
                      const SizedBox(width: 8),
                      const SourceBadge.healthKit(),
                    ],
                  ],
                ),
                // HK rows are read-only this sprint — no tap target. User
                // rows tap to edit, as before.
                onTap: row.userEntry == null
                    ? null
                    : () => _openForm(context, entry: row.userEntry),
              );
            },
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load weight logs: $err'),
          ),
        ),
      ),
    );
  }

  Future<void> _requestHealthKit(WidgetRef ref) async {
    final hk = ref.read(healthSourceProvider);
    await hk.requestPermissions();
    // Invalidate so the provider refetches — if the user granted
    // access, the list now populates with samples and the button hides.
    ref.invalidate(hkBodyWeightProvider);
  }

  void _openForm(BuildContext context, {BodyWeightLog? entry}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BodyWeightFormScreen(entry: entry)),
    );
  }

  static List<_WeightRow> _mergeAndSort(
    List<BodyWeightLog> userEntries,
    List<HKBodyWeightSample> hkSamples,
  ) {
    final rows = <_WeightRow>[
      for (final e in userEntries) _WeightRow.fromUser(e),
      for (final s in hkSamples) _WeightRow.fromHealthKit(s),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return rows;
  }
}

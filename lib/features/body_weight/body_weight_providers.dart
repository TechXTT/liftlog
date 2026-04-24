import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import '../../sources/health_kit/health_source.dart';

final bodyWeightLogsProvider = StreamProvider<List<BodyWeightLog>>((ref) {
  final repo = ref.watch(bodyWeightLogRepositoryProvider);
  return repo.watchAll();
});

/// Default look-back window for HealthKit body-weight merging on the
/// weight screen. Ninety days is wide enough to catch a typical cutting/
/// bulking cycle without loading years of history on every screen build.
const Duration _kHkBodyWeightLookback = Duration(days: 90);

/// HealthKit body-weight samples for the last ~90 days.
///
/// Returns an empty list when not authorized (per façade contract — no
/// error, no nag). Any other failure surfaces as an `AsyncError` via the
/// `.when(...)` consumer on the screen.
///
/// Arch rule: feature code imports only the `_source.dart` façade. This
/// file is the single entry point in the body-weight feature that
/// touches the HealthKit source.
final hkBodyWeightProvider = FutureProvider<List<HKBodyWeightSample>>((
  ref,
) async {
  final hk = ref.watch(healthSourceProvider);
  final now = DateTime.now();
  return hk.listBodyWeight(from: now.subtract(_kHkBodyWeightLookback), to: now);
});

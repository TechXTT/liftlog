import '../data/enums.dart';
import 'labels.dart';

/// Formats a calorie value (whole kcal only). Example: `1200`, `0`.
String formatKcal(int kcal) => kcal.toString();

/// Formats a gram value with at most one decimal place.
/// - Integer values render without a decimal (`12`, `0`).
/// - Decimal values render with one decimal, except trailing `.0` is trimmed
///   (so `12.0` becomes `12`, while `12.5` stays `12.5`).
String formatGrams(double g) {
  if (g == g.roundToDouble()) return g.toStringAsFixed(0);
  return g.toStringAsFixed(1);
}

/// Formats a weight value + unit label. Example: `80 kg`, `80.5 kg`, `176 lb`.
/// Uses the same trim-trailing-.0 rule as [formatGrams] for the value, and
/// routes the unit through [weightUnitLabel] so the suffix stays canonical.
String formatWeight(double value, WeightUnit unit) =>
    '${formatGrams(value)} ${weightUnitLabel(unit)}';

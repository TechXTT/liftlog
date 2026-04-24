enum MealType { breakfast, lunch, dinner, snack, other }

enum FoodEntryType { manual, savedFood, barcode, estimate }

enum WorkoutSetStatus { planned, completed, skipped }

enum WeightUnit { kg, lb }

/// Provenance — where a row's values came from.
///
/// First-class per v2.0 trust rules: every entity (food, body weight,
/// workout session, exercise set) must declare its `Source`. Orthogonal
/// to `FoodEntryType` — do not conflate. `FoodEntryType` captures the
/// food-domain shape of an entry (manual text, a saved template, a
/// barcode lookup, an estimate); `Source` captures the provenance
/// channel the row came in through (user-entered, HealthKit import,
/// photo/voice-estimated, derived, etc.).
///
/// Stored via `textEnum<Source>()` — Dart `.name` is the storage string
/// (`"userEntered"`, `"savedTemplate"`, ...) — consistent with the
/// existing `MealType` / `FoodEntryType` / `WeightUnit` pattern.
///
/// See CLAUDE.md (canonical enums) and the v2.0 contract. Features must
/// never construct `Source` values directly — they receive them from
/// repositories. Enforced by `test/arch/data_access_boundary_test.dart`.
enum Source {
  userEntered,
  savedTemplate,
  healthKit,
  photoEstimate,
  voiceEstimate,
  barcode,
  derived,
  imported,
}

import '../data/enums.dart';
import '../sources/health_kit/health_source.dart';

String mealTypeLabel(MealType t) {
  switch (t) {
    case MealType.breakfast:
      return 'Breakfast';
    case MealType.lunch:
      return 'Lunch';
    case MealType.dinner:
      return 'Dinner';
    case MealType.snack:
      return 'Snack';
    case MealType.other:
      return 'Other';
  }
}

String weightUnitLabel(WeightUnit u) {
  switch (u) {
    case WeightUnit.kg:
      return 'kg';
    case WeightUnit.lb:
      return 'lb';
  }
}

String workoutSetStatusLabel(WorkoutSetStatus s) {
  switch (s) {
    case WorkoutSetStatus.planned:
      return 'Planned';
    case WorkoutSetStatus.completed:
      return 'Completed';
    case WorkoutSetStatus.skipped:
      return 'Skipped';
  }
}

/// Human-readable label for a HealthKit workout type bucket.
///
/// Enumerates every [HKWorkoutType] case (canonical-enum rule). If a new
/// bucket is added, the analyzer flags this switch before it reaches the
/// UI.
String hkWorkoutTypeLabel(HKWorkoutType t) {
  switch (t) {
    case HKWorkoutType.traditionalStrengthTraining:
      return 'Strength training';
    case HKWorkoutType.functionalStrengthTraining:
      return 'Functional strength';
    case HKWorkoutType.coreTraining:
      return 'Core training';
    case HKWorkoutType.highIntensityIntervalTraining:
      return 'HIIT';
    case HKWorkoutType.running:
      return 'Running';
    case HKWorkoutType.walking:
      return 'Walking';
    case HKWorkoutType.cycling:
      return 'Cycling';
    case HKWorkoutType.yoga:
      return 'Yoga';
    case HKWorkoutType.other:
      return 'Other';
  }
}

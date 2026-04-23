import '../data/enums.dart';

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

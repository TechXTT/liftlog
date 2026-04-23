import '../../data/enums.dart';

String weightUnitLabel(WeightUnit u) {
  switch (u) {
    case WeightUnit.kg:
      return 'kg';
    case WeightUnit.lb:
      return 'lb';
  }
}

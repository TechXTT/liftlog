import 'package:flutter_test/flutter_test.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/ui/formatters.dart';

void main() {
  group('formatGrams', () {
    test('integer double renders without decimals', () {
      expect(formatGrams(80), '80');
      expect(formatGrams(80.0), '80');
    });

    test('one-decimal value renders with one decimal', () {
      expect(formatGrams(80.5), '80.5');
      expect(formatGrams(12.5), '12.5');
    });

    test('zero renders as 0', () {
      expect(formatGrams(0), '0');
    });
  });

  group('formatKcal', () {
    test('zero renders as 0', () {
      expect(formatKcal(0), '0');
    });

    test('positive integer renders as-is', () {
      expect(formatKcal(1200), '1200');
    });
  });

  group('formatWeight', () {
    test('integer value with kg', () {
      expect(formatWeight(80, WeightUnit.kg), '80 kg');
    });

    test('integer-valued double with lb', () {
      expect(formatWeight(176.0, WeightUnit.lb), '176 lb');
    });

    test('one-decimal value with kg', () {
      expect(formatWeight(80.5, WeightUnit.kg), '80.5 kg');
    });
  });
}

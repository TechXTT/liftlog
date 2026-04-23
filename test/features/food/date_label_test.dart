import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/features/food/date_label.dart';

void main() {
  test('shortDate formats as "MMM d" for each month', () {
    expect(shortDate(DateTime(2026, 1, 1)), 'Jan 1');
    expect(shortDate(DateTime(2026, 4, 23)), 'Apr 23');
    expect(shortDate(DateTime(2026, 12, 31)), 'Dec 31');
  });
}

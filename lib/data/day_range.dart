class DayRange {
  DayRange(DateTime day)
      : start = DateTime(day.year, day.month, day.day),
        end = DateTime(day.year, day.month, day.day).add(const Duration(days: 1));

  final DateTime start;
  final DateTime end;
}

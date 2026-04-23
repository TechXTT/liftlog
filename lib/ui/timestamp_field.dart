import 'package:flutter/material.dart';

/// Function signature for opening the date+time picker chain. Exposed so widget
/// tests can bypass the Material dialog UI by injecting a deterministic picker;
/// production callers use the default [showDatePicker]+[showTimePicker] combo.
typedef TimestampPicker =
    Future<DateTime?> Function(BuildContext context, DateTime current);

/// Tappable form field that combines [showDatePicker] + [showTimePicker] into a
/// single entry. Used by food and body-weight forms so logged-after-the-fact
/// entries land on the correct day.
///
/// Uses [FormField] so [validator] errors surface beneath the field through the
/// parent [Form] — no bespoke SnackBar wiring needed. Time changes are pushed
/// out through [onChanged] so the parent remains the source of truth.
class TimestampField extends StatelessWidget {
  const TimestampField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.label = 'When',
    this.validator,
    this.enabled = true,
    this.picker,
  });

  final DateTime initialValue;
  final ValueChanged<DateTime> onChanged;
  final String label;
  final FormFieldValidator<DateTime>? validator;
  final bool enabled;

  /// Override to inject a test-time picker. Defaults to the Material date+time
  /// picker pair.
  final TimestampPicker? picker;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: initialValue,
      validator: validator,
      builder: (state) {
        final value = state.value ?? initialValue;
        return InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: state.errorText,
            suffixIcon: const Icon(Icons.edit_calendar_outlined),
          ),
          child: InkWell(
            onTap: enabled ? () => _pick(context, state) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_format(value)),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pick(
    BuildContext context,
    FormFieldState<DateTime> state,
  ) async {
    final current = state.value ?? initialValue;
    final open = picker ?? _defaultPicker;
    final result = await open(context, current);
    if (result == null) return;
    state.didChange(result);
    onChanged(result);
  }
}

Future<DateTime?> _defaultPicker(BuildContext context, DateTime current) async {
  final now = DateTime.now();
  // Window generous enough for back-logging a missed meal or a future-dated
  // weigh-in. 2y back / 1y forward keeps the picker bounded without being
  // restrictive for realistic use.
  final firstDate = DateTime(now.year - 2);
  final lastDate = DateTime(now.year + 1, 12, 31);

  final pickedDate = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: firstDate,
    lastDate: lastDate,
  );
  if (pickedDate == null) return null;
  if (!context.mounted) return null;

  final pickedTime = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current),
  );
  if (pickedTime == null) return null;

  return DateTime(
    pickedDate.year,
    pickedDate.month,
    pickedDate.day,
    pickedTime.hour,
    pickedTime.minute,
  );
}

String _format(DateTime t) {
  final y = t.year.toString().padLeft(4, '0');
  final mo = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  final h = t.hour.toString().padLeft(2, '0');
  final mi = t.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}

/// Rejects timestamps more than 1 hour in the future. Centralised here so both
/// food and body-weight forms share the same rule.
String? futureGuardValidator(DateTime? value) {
  if (value == null) return 'Pick a date & time';
  final now = DateTime.now();
  if (value.isAfter(now.add(const Duration(hours: 1)))) {
    return 'Time cannot be more than 1 hour in the future';
  }
  return null;
}

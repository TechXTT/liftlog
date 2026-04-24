// Daily target form (schema v5, issue #59 — E5 kickoff).
//
// One form, one submit. Captures the kcal + protein + effective-from
// triple, then calls `DailyTargetRepository.add(...)` and pops. Edits
// work by inserting a NEW row (historical integrity — see the
// repository doc comment); there is no Update path here. The Settings
// section just re-opens this form, the user types a new target, and
// the most-recent row wins.
//
// `effective_from` is locked to midnight in the user's local time so
// `activeOn(DateTime.now())` is inclusive of the selected day. That
// matches the "set a target starting today" mental model.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';
import '../../ui/show_save_error.dart';
import '../../ui/timestamp_field.dart';

class DailyTargetFormScreen extends ConsumerStatefulWidget {
  const DailyTargetFormScreen({super.key, this.timestampPicker});

  /// Optional — only set by widget tests that want a deterministic
  /// "effective from" date without driving the Material date+time
  /// dialogs. Null in production.
  final TimestampPicker? timestampPicker;

  @override
  ConsumerState<DailyTargetFormScreen> createState() =>
      _DailyTargetFormScreenState();
}

class _DailyTargetFormScreenState extends ConsumerState<DailyTargetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _kcalController;
  late final TextEditingController _proteinController;
  late DateTime _effectiveFrom;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _kcalController = TextEditingController();
    _proteinController = TextEditingController();
    _effectiveFrom = _midnight(DateTime.now());
  }

  @override
  void dispose() {
    _kcalController.dispose();
    _proteinController.dispose();
    super.dispose();
  }

  /// Floors [t] to midnight in the local zone so `activeOn(...)` for
  /// "today" is inclusive of the selected day. See file-level note.
  DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final kcal = int.parse(_kcalController.text.trim());
    final protein = double.parse(_proteinController.text.trim());
    final now = DateTime.now();

    try {
      final repo = ref.read(dailyTargetRepositoryProvider);
      await repo.add(
        DailyTargetsCompanion.insert(
          kcal: kcal,
          proteinG: protein,
          effectiveFrom: _effectiveFrom,
          createdAt: now,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'save target', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set daily target'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _kcalController,
                decoration: const InputDecoration(labelText: 'kcal per day'),
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a whole number';
                  if (n < 0) return 'Must be zero or positive';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _proteinController,
                decoration: const InputDecoration(
                  labelText: 'Protein per day (g)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number';
                  if (n < 0) return 'Must be zero or positive';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TimestampField(
                initialValue: _effectiveFrom,
                label: 'Effective from',
                enabled: !_saving,
                picker: widget.timestampPicker,
                onChanged: (t) => setState(() => _effectiveFrom = _midnight(t)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

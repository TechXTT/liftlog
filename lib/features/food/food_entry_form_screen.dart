import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import '../../ui/delete_confirm.dart';
import '../../ui/formatters.dart';
import '../../ui/labels.dart';
import '../../ui/show_save_error.dart';
import '../../ui/timestamp_field.dart';

/// Soft cap on the free-form note field. `maxLength` on [TextField] enforces
/// this at the UI level; the DB column is unconstrained text.
const int kFoodNoteMaxLength = 200;

class FoodEntryFormScreen extends ConsumerStatefulWidget {
  const FoodEntryFormScreen({super.key, this.entry, this.timestampPicker});

  final FoodEntry? entry;

  /// Optional — only set by widget tests that want a deterministic timestamp
  /// without driving the Material date+time dialogs. Null in production.
  final TimestampPicker? timestampPicker;

  @override
  ConsumerState<FoodEntryFormScreen> createState() =>
      _FoodEntryFormScreenState();
}

class _FoodEntryFormScreenState extends ConsumerState<FoodEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _kcalController;
  late final TextEditingController _proteinController;
  late final TextEditingController _noteController;
  late MealType _mealType;
  late bool _isEstimate;
  late DateTime _timestamp;
  bool _saving = false;

  bool get _isEdit => widget.entry != null;

  /// Toggle is visible when adding, or when editing an entry whose current
  /// type is part of the flippable set (`manual` / `estimate`).
  bool get _showEstimateToggle =>
      !_isEdit || _canFlipType(widget.entry!.entryType);

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameController = TextEditingController(text: e?.name ?? '');
    _kcalController = TextEditingController(text: e == null ? '' : '${e.kcal}');
    _proteinController = TextEditingController(
      text: e == null ? '' : e.proteinG.toString(),
    );
    _noteController = TextEditingController(text: e?.note ?? '');
    _mealType = e?.mealType ?? MealType.other;
    _isEstimate = e?.entryType == FoodEntryType.estimate;
    _timestamp = e?.timestamp ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(foodEntryRepositoryProvider);
    final name = _nameController.text.trim();
    final kcal = int.parse(_kcalController.text.trim());
    final protein = double.parse(_proteinController.text.trim());

    final newType = _isEstimate ? FoodEntryType.estimate : FoodEntryType.manual;
    // Empty trimmed text means "no note" — store null, not "". Distinguishes
    // note-clear from note-unchanged at the DB level (note column is nullable).
    final rawNote = _noteController.text.trim();
    final noteValue = rawNote.isEmpty ? null : rawNote;

    try {
      if (_isEdit) {
        // Only flip between manual <-> estimate. Never rewrite savedFood /
        // barcode types from the UI (no producers exist yet; preserving the
        // stored type is the safe default).
        final current = widget.entry!.entryType;
        final nextType = _canFlipType(current) ? newType : current;
        await repo.update(
          widget.entry!.copyWith(
            timestamp: _timestamp,
            name: name,
            kcal: kcal,
            proteinG: protein,
            mealType: _mealType,
            entryType: nextType,
            note: Value(noteValue),
          ),
        );
      } else {
        await repo.add(
          FoodEntriesCompanion.insert(
            timestamp: _timestamp,
            name: Value(name),
            kcal: kcal,
            proteinG: protein,
            mealType: _mealType,
            entryType: newType,
            note: Value(noteValue),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'save entry', e);
    }
  }

  /// Enumerates every [FoodEntryType] case explicitly — no fallthrough.
  /// The edit toggle only exposes a flip between `manual` and `estimate`;
  /// `savedFood` / `barcode` are not UI-editable today (no producers).
  bool _canFlipType(FoodEntryType t) {
    switch (t) {
      case FoodEntryType.manual:
        return true;
      case FoodEntryType.estimate:
        return true;
      case FoodEntryType.savedFood:
        // no UI producer today
        return false;
      case FoodEntryType.barcode:
        // no UI producer today
        return false;
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteConfirm(
      context,
      title: 'Delete entry?',
      message:
          'Delete "${widget.entry!.name}" (${formatKcal(widget.entry!.kcal)} kcal)? '
          'This cannot be undone.',
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _saving = true);
    final repo = ref.read(foodEntryRepositoryProvider);
    try {
      await repo.delete(widget.entry!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'delete entry', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit food' : 'Add food'),
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
          // The input fields scroll inside the Expanded; the destructive
          // "Delete entry" action stays pinned at the bottom, always visible
          // and always hit-testable (widget tests rely on this — the form
          // can be taller than the viewport once the note field is present).
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<MealType>(
                        initialValue: _mealType,
                        decoration: const InputDecoration(labelText: 'Meal'),
                        items: [
                          for (final m in MealType.values)
                            DropdownMenuItem(
                              value: m,
                              child: Text(mealTypeLabel(m)),
                            ),
                        ],
                        onChanged: (m) {
                          if (m != null) setState(() => _mealType = m);
                        },
                      ),
                      const SizedBox(height: 12),
                      TimestampField(
                        initialValue: _timestamp,
                        validator: futureGuardValidator,
                        enabled: !_saving,
                        picker: widget.timestampPicker,
                        onChanged: (t) => setState(() => _timestamp = t),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _kcalController,
                        decoration: const InputDecoration(
                          labelText: 'Calories (kcal)',
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null) return 'Enter a whole number';
                          if (n < 0) return 'Must be zero or more';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _proteinController,
                        decoration: const InputDecoration(
                          labelText: 'Protein (g)',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        validator: (v) {
                          final n = double.tryParse((v ?? '').trim());
                          if (n == null) return 'Enter a number';
                          if (n < 0) return 'Must be zero or more';
                          return null;
                        },
                      ),
                      if (_showEstimateToggle) ...[
                        const SizedBox(height: 4),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('This is an estimate'),
                          subtitle: const Text(
                            'Tag entries you eyeballed so totals stay honest.',
                          ),
                          value: _isEstimate,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _isEstimate = v),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextField(
                        controller: _noteController,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          // Hide the default character counter — the limit is
                          // a soft cap, not a hard UX signal worth a visible
                          // number.
                          counterText: '',
                        ),
                        enabled: !_saving,
                        maxLength: kFoodNoteMaxLength,
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                      ),
                    ],
                  ),
                ),
              ),
              if (_isEdit)
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete entry'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

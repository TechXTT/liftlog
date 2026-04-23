import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import '../../ui/delete_confirm.dart';
import '../../ui/labels.dart';
import '../../ui/show_save_error.dart';

class ExerciseSetFormScreen extends ConsumerStatefulWidget {
  const ExerciseSetFormScreen({
    super.key,
    required this.sessionId,
    this.existing,
    this.nextOrderIndex,
  });

  final int sessionId;
  final ExerciseSet? existing;
  final int? nextOrderIndex;

  @override
  ConsumerState<ExerciseSetFormScreen> createState() =>
      _ExerciseSetFormScreenState();
}

class _ExerciseSetFormScreenState extends ConsumerState<ExerciseSetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late WeightUnit _unit;
  late WorkoutSetStatus _status;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.exerciseName ?? '');
    _repsController =
        TextEditingController(text: e == null ? '' : '${e.reps}');
    _weightController =
        TextEditingController(text: e == null ? '' : e.weight.toString());
    _unit = e?.weightUnit ?? WeightUnit.kg;
    _status = e?.status ?? WorkoutSetStatus.completed;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(exerciseSetRepositoryProvider);
    final name = _nameController.text.trim();
    final reps = int.parse(_repsController.text.trim());
    final weight = double.parse(_weightController.text.trim());

    try {
      if (_isEdit) {
        await repo.update(widget.existing!.copyWith(
          exerciseName: name,
          reps: reps,
          weight: weight,
          weightUnit: _unit,
          status: _status,
        ));
      } else {
        await repo.add(ExerciseSetsCompanion.insert(
          sessionId: widget.sessionId,
          exerciseName: name,
          reps: reps,
          weight: weight,
          weightUnit: _unit,
          status: _status,
          orderIndex: widget.nextOrderIndex ?? 0,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'save set', e);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteConfirm(
      context,
      title: 'Delete set?',
      message: 'This cannot be undone.',
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _saving = true);
    final repo = ref.read(exerciseSetRepositoryProvider);
    try {
      await repo.delete(widget.existing!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'delete set', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit set' : 'Add set'),
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
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Exercise'),
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Exercise name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _repsController,
                decoration: const InputDecoration(labelText: 'Reps'),
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
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _weightController,
                      decoration: const InputDecoration(labelText: 'Weight'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null) return 'Enter a number';
                        if (n < 0) return 'Must be zero or more';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<WeightUnit>(
                      initialValue: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: [
                        for (final u in WeightUnit.values)
                          DropdownMenuItem(
                              value: u, child: Text(weightUnitLabel(u))),
                      ],
                      onChanged: (u) {
                        if (u != null) setState(() => _unit = u);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WorkoutSetStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  for (final s in WorkoutSetStatus.values)
                    DropdownMenuItem(
                        value: s, child: Text(workoutSetStatusLabel(s))),
                ],
                onChanged: (s) {
                  if (s != null) setState(() => _status = s);
                },
              ),
              if (_isEdit) ...[
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete set'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

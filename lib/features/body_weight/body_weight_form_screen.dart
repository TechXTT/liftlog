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

class BodyWeightFormScreen extends ConsumerStatefulWidget {
  const BodyWeightFormScreen({super.key, this.entry, this.timestampPicker});

  final BodyWeightLog? entry;

  /// Optional — only set by widget tests that want a deterministic timestamp
  /// without driving the Material date+time dialogs. Null in production.
  final TimestampPicker? timestampPicker;

  @override
  ConsumerState<BodyWeightFormScreen> createState() =>
      _BodyWeightFormScreenState();
}

class _BodyWeightFormScreenState extends ConsumerState<BodyWeightFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _valueController;
  late WeightUnit _unit;
  late DateTime _timestamp;
  bool _saving = false;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _valueController = TextEditingController(
      text: e == null ? '' : e.value.toString(),
    );
    _unit = e?.unit ?? WeightUnit.kg;
    _timestamp = e?.timestamp ?? DateTime.now();
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(bodyWeightLogRepositoryProvider);
    final value = double.parse(_valueController.text.trim());

    try {
      if (_isEdit) {
        await repo.update(
          widget.entry!.copyWith(
            timestamp: _timestamp,
            value: value,
            unit: _unit,
          ),
        );
      } else {
        await repo.add(
          BodyWeightLogsCompanion.insert(
            timestamp: _timestamp,
            value: value,
            unit: _unit,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'save weight', e);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteConfirm(
      context,
      title: 'Delete weight log?',
      message:
          'Delete ${formatWeight(widget.entry!.value, widget.entry!.unit)}? '
          'This cannot be undone.',
    );
    if (!confirmed) return;
    if (!mounted) return;

    setState(() => _saving = true);
    final repo = ref.read(bodyWeightLogRepositoryProvider);
    try {
      await repo.delete(widget.entry!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'delete weight', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit weight' : 'Add weight'),
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
                controller: _valueController,
                decoration: const InputDecoration(labelText: 'Weight'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number';
                  if (n <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<WeightUnit>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: [
                  for (final u in WeightUnit.values)
                    DropdownMenuItem(value: u, child: Text(weightUnitLabel(u))),
                ],
                onChanged: (u) {
                  if (u != null) setState(() => _unit = u);
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
              if (_isEdit) ...[
                const SizedBox(height: 32),
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete entry'),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import 'weight_unit_label.dart';

class BodyWeightFormScreen extends ConsumerStatefulWidget {
  const BodyWeightFormScreen({super.key, this.entry});

  final BodyWeightLog? entry;

  @override
  ConsumerState<BodyWeightFormScreen> createState() =>
      _BodyWeightFormScreenState();
}

class _BodyWeightFormScreenState extends ConsumerState<BodyWeightFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _valueController;
  late WeightUnit _unit;
  bool _saving = false;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _valueController =
        TextEditingController(text: e == null ? '' : e.value.toString());
    _unit = e?.unit ?? WeightUnit.kg;
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
        await repo.update(widget.entry!.copyWith(value: value, unit: _unit));
      } else {
        await repo.add(BodyWeightLogsCompanion.insert(
          timestamp: DateTime.now(),
          value: value,
          unit: _unit,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save weight: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete weight log?'),
        content: Text(
          'Delete ${widget.entry!.value} ${weightUnitLabel(widget.entry!.unit)}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    final repo = ref.read(bodyWeightLogRepositoryProvider);
    try {
      await repo.delete(widget.entry!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete weight: $e')),
      );
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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

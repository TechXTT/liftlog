import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import 'meal_type_label.dart';

class FoodEntryFormScreen extends ConsumerStatefulWidget {
  const FoodEntryFormScreen({super.key, this.entry});

  final FoodEntry? entry;

  @override
  ConsumerState<FoodEntryFormScreen> createState() =>
      _FoodEntryFormScreenState();
}

class _FoodEntryFormScreenState extends ConsumerState<FoodEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _kcalController;
  late final TextEditingController _proteinController;
  late MealType _mealType;
  bool _saving = false;

  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameController = TextEditingController(text: e?.name ?? '');
    _kcalController = TextEditingController(text: e == null ? '' : '${e.kcal}');
    _proteinController =
        TextEditingController(text: e == null ? '' : e.proteinG.toString());
    _mealType = e?.mealType ?? MealType.other;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(foodEntryRepositoryProvider);
    final name = _nameController.text.trim();
    final kcal = int.parse(_kcalController.text.trim());
    final protein = double.parse(_proteinController.text.trim());

    try {
      if (_isEdit) {
        await repo.update(widget.entry!.copyWith(
          name: name,
          kcal: kcal,
          proteinG: protein,
          mealType: _mealType,
        ));
      } else {
        await repo.add(FoodEntriesCompanion.insert(
          timestamp: DateTime.now(),
          name: Value(name),
          kcal: kcal,
          proteinG: protein,
          mealType: _mealType,
          entryType: FoodEntryType.manual,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save entry: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Delete "${widget.entry!.name}" (${widget.entry!.kcal} kcal)? '
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
    final repo = ref.read(foodEntryRepositoryProvider);
    try {
      await repo.delete(widget.entry!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete entry: $e')),
      );
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
          child: ListView(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MealType>(
                initialValue: _mealType,
                decoration: const InputDecoration(labelText: 'Meal'),
                items: [
                  for (final m in MealType.values)
                    DropdownMenuItem(value: m, child: Text(mealTypeLabel(m))),
                ],
                onChanged: (m) {
                  if (m != null) setState(() => _mealType = m);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _kcalController,
                decoration: const InputDecoration(labelText: 'Calories (kcal)'),
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
                decoration: const InputDecoration(labelText: 'Protein (g)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                validator: (v) {
                  final n = double.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a number';
                  if (n < 0) return 'Must be zero or more';
                  return null;
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

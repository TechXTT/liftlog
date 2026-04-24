import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import '../../ui/delete_confirm.dart';
import '../../ui/labels.dart';
import '../../ui/show_save_error.dart';

/// Create-or-edit form for a routine (#61).
///
/// Holds the full in-memory draft — name, notes, and an ordered list of
/// line items — and writes it out to the repositories on Save. We keep
/// the draft entirely local (in `_rows`) so reorder / add / remove stay
/// instant and the user can cancel without polluting the DB. On Save the
/// persisted rows are replaced wholesale: delete every existing
/// `RoutineExercise` for this routine and re-insert from the draft in
/// the user's order. That keeps the persistence shape simple while
/// honouring the cascade-delete + FK constraints (the routine row is
/// preserved; only its line items are rewritten).
///
/// Autocomplete picker note (#61): the Exercise field reuses Flutter's
/// built-in `Autocomplete<Exercise>` pattern from S6.2
/// (`exercise_set_form_screen.dart`). A second copy rather than a shared
/// widget — shared extraction turned out invasive because the set-form
/// additionally owns recent-exercise chips and a latched canonical-id
/// dance that routines don't need. Follow-up note: if a third consumer
/// appears, extract both into `lib/features/workouts/exercise_picker.dart`.
class RoutineFormScreen extends ConsumerStatefulWidget {
  const RoutineFormScreen({super.key, this.existing});

  /// Routine being edited. `null` → create mode.
  final Routine? existing;

  @override
  ConsumerState<RoutineFormScreen> createState() => _RoutineFormScreenState();
}

class _RoutineFormScreenState extends ConsumerState<RoutineFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  final List<_DraftRow> _rows = [];
  bool _saving = false;
  bool _loadedInitial = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _notesController = TextEditingController(
      text: widget.existing?.notes ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  /// One-shot load of existing line items (edit mode only). Widget-test
  /// safe: uses `listExercises`, not `watchExercises`.
  Future<void> _loadExisting() async {
    final existing = widget.existing;
    if (existing == null) return;
    final repo = ref.read(routineRepositoryProvider);
    final rows = await repo.listExercises(existing.id);
    if (!mounted) return;
    setState(() {
      _rows.clear();
      for (final r in rows) {
        _rows.add(_DraftRow.fromPersisted(r));
      }
      _loadedInitial = true;
    });
  }

  void _addRow() {
    setState(() {
      _rows.add(_DraftRow.blank());
    });
  }

  void _removeRow(int index) async {
    final confirmed = await showDeleteConfirm(
      context,
      title: 'Remove exercise?',
      message: 'This exercise will be removed from the routine.',
    );
    if (!confirmed) return;
    if (!mounted) return;
    setState(() {
      final removed = _rows.removeAt(index);
      removed.dispose();
    });
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final row = _rows.removeAt(index);
      _rows.insert(index - 1, row);
    });
  }

  void _moveDown(int index) {
    if (index >= _rows.length - 1) return;
    setState(() {
      final row = _rows.removeAt(index);
      _rows.insert(index + 1, row);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Additional rule: every row must have a resolved exercise id. The
    // row-level validator also catches this, but we double-check here
    // because Autocomplete rows that have free-typed text without a
    // selection would otherwise pass field-level validation (their text
    // field is non-empty).
    for (final row in _rows) {
      if (row.exerciseId == null) {
        _formKey.currentState!.validate();
        if (!mounted) return;
        showSaveError(context, 'save routine', 'Pick an exercise from the list');
        return;
      }
    }

    setState(() => _saving = true);
    final routineRepo = ref.read(routineRepositoryProvider);
    final name = _nameController.text.trim();
    final notesRaw = _notesController.text.trim();
    final notes = notesRaw.isEmpty ? null : notesRaw;

    try {
      int routineId;
      if (_isEdit) {
        // Preserve createdAt + source via copyWith (trust rule — no
        // silent mutation of provenance).
        await routineRepo.update(
          widget.existing!.copyWith(name: name, notes: Value(notes)),
        );
        routineId = widget.existing!.id;
        // Clear and re-insert line items in the user's order. We use
        // the public delete-routine-exercises primitive if it exists,
        // or fall back to the reorder + trim pattern. Since
        // `RoutineRepository` doesn't expose a "delete all line items"
        // method, we loop individual deletes — keeps the repo minimal.
        final existingItems = await routineRepo.listExercises(routineId);
        for (final r in existingItems) {
          await routineRepo.deleteExercise(r.id);
        }
      } else {
        routineId = await routineRepo.add(
          RoutinesCompanion.insert(
            name: name,
            notes: Value(notes),
            createdAt: DateTime.now(),
          ),
        );
      }
      // Insert line items in display order; orderIndex == loop index.
      for (var i = 0; i < _rows.length; i++) {
        final row = _rows[i];
        await routineRepo.addExercise(
          RoutineExercisesCompanion.insert(
            routineId: routineId,
            exerciseId: row.exerciseId!,
            orderIndex: i,
            targetSets: Value(row.targetSets),
            targetReps: Value(row.targetReps),
            targetWeight: Value(row.targetWeight),
            targetWeightUnit: Value(row.targetWeightUnit),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'save routine', e);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDeleteConfirm(
      context,
      title: 'Delete routine?',
      message:
          'This routine and its exercises will be removed. This cannot be undone.',
    );
    if (!confirmed) return;
    if (!mounted) return;
    setState(() => _saving = true);
    final repo = ref.read(routineRepositoryProvider);
    try {
      await repo.delete(widget.existing!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showSaveError(context, 'delete routine', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lazy one-shot load of existing line items. We do this in `build`
    // (not `initState`) because `ref.read` at initState time is allowed
    // but awaits + setState are cleaner here. Guard with `_loadedInitial`
    // so we don't re-fire on every rebuild.
    if (_isEdit && !_loadedInitial) {
      _loadedInitial = true;
      Future.microtask(_loadExisting);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit routine' : 'New routine'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete routine',
              onPressed: _saving ? null : _delete,
            ),
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
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLength: 500,
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text(
                'Exercises',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No exercises yet. Tap + Add exercise to start.',
                  ),
                ),
              for (var i = 0; i < _rows.length; i++)
                _RoutineExerciseRowEditor(
                  key: ValueKey(_rows[i].key),
                  row: _rows[i],
                  index: i,
                  isFirst: i == 0,
                  isLast: i == _rows.length - 1,
                  onMoveUp: () => _moveUp(i),
                  onMoveDown: () => _moveDown(i),
                  onDelete: () => _removeRow(i),
                  onChanged: () => setState(() {}),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _addRow,
                icon: const Icon(Icons.add),
                label: const Text('Add exercise'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-memory draft of a single line item. Holds its own controllers so
/// reorder/move operations don't lose the user's in-progress input.
class _DraftRow {
  _DraftRow.blank()
      : key = _nextKey(),
        setsController = TextEditingController(),
        repsController = TextEditingController(),
        weightController = TextEditingController(),
        targetWeightUnit = WeightUnit.kg,
        exerciseId = null,
        exerciseName = '';

  _DraftRow.fromPersisted(RoutineExercise re)
      : key = _nextKey(),
        setsController = TextEditingController(
          text: re.targetSets?.toString() ?? '',
        ),
        repsController = TextEditingController(
          text: re.targetReps?.toString() ?? '',
        ),
        weightController = TextEditingController(
          text: re.targetWeight == null ? '' : _formatWeight(re.targetWeight!),
        ),
        targetWeightUnit = re.targetWeightUnit ?? WeightUnit.kg,
        exerciseId = re.exerciseId,
        exerciseName = '';
  // `exerciseName` populated once the row editor resolves it from the
  // exercises table (see `_RoutineExerciseRowEditor.initState`).

  static int _keyCounter = 0;
  static int _nextKey() => _keyCounter++;

  final int key;
  final TextEditingController setsController;
  final TextEditingController repsController;
  final TextEditingController weightController;
  WeightUnit targetWeightUnit;
  int? exerciseId;
  String exerciseName;

  int? get targetSets {
    final t = setsController.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  int? get targetReps {
    final t = repsController.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  double? get targetWeight {
    final t = weightController.text.trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  void dispose() {
    setsController.dispose();
    repsController.dispose();
    weightController.dispose();
  }

  static String _formatWeight(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

/// Per-row editor with Autocomplete picker + target fields + reorder /
/// delete buttons.
class _RoutineExerciseRowEditor extends ConsumerStatefulWidget {
  const _RoutineExerciseRowEditor({
    super.key,
    required this.row,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onChanged,
  });

  final _DraftRow row;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  @override
  ConsumerState<_RoutineExerciseRowEditor> createState() =>
      _RoutineExerciseRowEditorState();
}

class _RoutineExerciseRowEditorState
    extends ConsumerState<_RoutineExerciseRowEditor> {
  TextEditingController? _nameController;
  bool _primedFromRow = false;

  @override
  void initState() {
    super.initState();
    // Resolve the exercise name for pre-populated rows (edit mode) on
    // first frame so the Autocomplete field's initial value matches.
    if (widget.row.exerciseId != null && widget.row.exerciseName.isEmpty) {
      Future.microtask(_resolveExerciseName);
    }
  }

  Future<void> _resolveExerciseName() async {
    final repo = ref.read(exerciseRepositoryProvider);
    final exercise = await repo.findById(widget.row.exerciseId!);
    if (!mounted || exercise == null) return;
    setState(() {
      widget.row.exerciseName = exercise.canonicalName;
      if (_nameController != null &&
          _nameController!.text != exercise.canonicalName) {
        _nameController!.text = exercise.canonicalName;
      }
    });
  }

  /// Autocomplete options builder. Mirrors the set form's algorithm —
  /// substring match, prefix-first, alphabetical tiebreak, cap at 8.
  Future<Iterable<Exercise>> _buildSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <Exercise>[];
    final repo = ref.read(exerciseRepositoryProvider);
    final all = await repo.listAll();
    final needle = trimmed.toLowerCase();
    final matches = <Exercise>[];
    for (final e in all) {
      if (e.canonicalName.toLowerCase().contains(needle)) {
        matches.add(e);
      }
    }
    matches.sort((a, b) {
      final aPrefix = a.canonicalName.toLowerCase().startsWith(needle);
      final bPrefix = b.canonicalName.toLowerCase().startsWith(needle);
      if (aPrefix != bPrefix) return aPrefix ? -1 : 1;
      return a.canonicalName.toLowerCase().compareTo(
        b.canonicalName.toLowerCase(),
      );
    });
    if (matches.length > 8) return matches.sublist(0, 8);
    return matches;
  }

  void _onSuggestionSelected(Exercise e) {
    setState(() {
      widget.row.exerciseId = e.id;
      widget.row.exerciseName = e.canonicalName;
    });
    widget.onChanged();
  }

  void _onFieldChanged(String text) {
    // Editing away from the resolved name drops the id — save path will
    // re-validate that the user picked a canonical exercise.
    if (widget.row.exerciseId == null) return;
    if (text != widget.row.exerciseName) {
      setState(() {
        widget.row.exerciseId = null;
      });
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exercise ${widget.index + 1}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Move up',
                  onPressed: widget.isFirst ? null : widget.onMoveUp,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  tooltip: 'Move down',
                  onPressed: widget.isLast ? null : widget.onMoveDown,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove exercise',
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            Autocomplete<Exercise>(
              displayStringForOption: (e) => e.canonicalName,
              optionsBuilder: (TextEditingValue v) =>
                  _buildSuggestions(v.text),
              onSelected: _onSuggestionSelected,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                if (!_primedFromRow) {
                  _nameController = controller;
                  if (row.exerciseName.isNotEmpty) {
                    controller.text = row.exerciseName;
                  }
                  _primedFromRow = true;
                }
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(labelText: 'Exercise'),
                  textInputAction: TextInputAction.next,
                  onChanged: _onFieldChanged,
                  onFieldSubmitted: (_) => onFieldSubmitted(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Exercise is required';
                    }
                    if (row.exerciseId == null) {
                      return 'Pick an exercise from the list';
                    }
                    return null;
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: row.setsController,
                    decoration: const InputDecoration(labelText: 'Sets'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null) return 'Whole number';
                      if (n < 1) return 'Must be ≥ 1';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: row.repsController,
                    decoration: const InputDecoration(labelText: 'Reps'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null) return 'Whole number';
                      if (n < 1) return 'Must be ≥ 1';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: row.weightController,
                    decoration: const InputDecoration(
                      labelText: 'Weight (optional)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => widget.onChanged(),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return null; // bodyweight / rep-only
                      final n = double.tryParse(t);
                      if (n == null) return 'Number';
                      if (n < 0) return 'Must be ≥ 0';
                      return null;
                    },
                  ),
                ),
                if ((row.weightController.text).trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<WeightUnit>(
                      initialValue: row.targetWeightUnit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: [
                        for (final u in WeightUnit.values)
                          DropdownMenuItem(
                            value: u,
                            child: Text(weightUnitLabel(u)),
                          ),
                      ],
                      onChanged: (u) {
                        if (u != null) {
                          setState(() => row.targetWeightUnit = u);
                          widget.onChanged();
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

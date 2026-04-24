import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../providers/app_providers.dart';
import '../../ui/delete_confirm.dart';
import '../../ui/labels.dart';
import '../../ui/show_save_error.dart';
import 'recent_exercises_strip.dart';

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
  // `_nameController` is owned by the Autocomplete widget (created via its
  // `fieldViewBuilder`); we keep a handle to it so our save/edit/chip-tap
  // flows can read and mutate the text field. The Autocomplete's
  // field-view-builder hands us the same controller instance on every
  // rebuild, so latching it once on first build is safe.
  TextEditingController? _nameController;
  late final TextEditingController _repsController;
  late final TextEditingController _weightController;
  late WeightUnit _unit;
  late WorkoutSetStatus _status;
  bool _saving = false;

  /// Canonical `exercises.id` the user has explicitly selected via a
  /// typeahead suggestion tap (or a recent-exercise chip tap whose name
  /// resolves to an existing row). Cleared when the user edits the text
  /// after selecting, so a mid-selection free-type falls back to the
  /// find-or-create path on save. See [_save].
  int? _selectedExerciseId;

  /// Cached canonical name for [_selectedExerciseId]. Used at save time to
  /// decide whether the text still matches the selected exercise — if the
  /// user edited the text after selecting, we drop the id and go through
  /// find-or-create.
  String? _selectedExerciseName;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _repsController =
        TextEditingController(text: e == null ? '' : '${e.reps}');
    _weightController =
        TextEditingController(text: e == null ? '' : e.weight.toString());
    _unit = e?.weightUnit ?? WeightUnit.kg;
    _status = e?.status ?? WorkoutSetStatus.completed;
    // Prefill the selected-exercise-id from the existing row if it has
    // one. The text controller itself is created lazily by Autocomplete;
    // we seed it via `initialValue` on `RawAutocomplete` below.
    if (e != null && e.exerciseId != null) {
      _selectedExerciseId = e.exerciseId;
      _selectedExerciseName = e.exerciseName;
    }
  }

  @override
  void dispose() {
    _repsController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  /// Refill the `Exercise` text field from a recent-exercises chip tap.
  /// Caret lands at the end of the name so the user can continue typing
  /// (e.g. append " (variant)") without hitting End first. No
  /// auto-advance, no auto-submit — the user still chooses to save.
  ///
  /// Additionally (#60): if the chip name matches an `Exercise` row
  /// exactly, latch the canonical `exerciseId` so save links the FK
  /// without a second lookup. This is additive — the typeahead and the
  /// chip strip feed the same selection state.
  Future<void> _applyRecentName(String name) async {
    _nameController?.value = TextEditingValue(
      text: name,
      selection: TextSelection.fromPosition(TextPosition(offset: name.length)),
    );
    final repo = ref.read(exerciseRepositoryProvider);
    final row = await repo.findByName(name);
    if (!mounted) return;
    setState(() {
      _selectedExerciseId = row?.id;
      _selectedExerciseName = row?.canonicalName;
    });
  }

  /// Called when the Autocomplete surface emits a selection (user tapped
  /// a suggestion). Latches both the canonical id and name so the save
  /// path can short-circuit the find-or-create lookup.
  void _onSuggestionSelected(Exercise suggestion) {
    setState(() {
      _selectedExerciseId = suggestion.id;
      _selectedExerciseName = suggestion.canonicalName;
    });
  }

  /// Called whenever the raw text in the Exercise field changes. If the
  /// user edits away from the selected exercise's canonical name, we
  /// drop the latched id so save falls through to find-or-create. If
  /// they edit back to match, we do NOT auto-relatch — the user must
  /// explicitly re-select from the typeahead. This is the safer default:
  /// a free-typed match to an existing exercise still goes through
  /// `findByName` at save time, which will find and link the row.
  void _onFieldChanged(String text) {
    if (_selectedExerciseId == null) return;
    if (text != _selectedExerciseName) {
      setState(() {
        _selectedExerciseId = null;
        _selectedExerciseName = null;
      });
    }
  }

  /// Typeahead suggestion source (#60). Non-empty queries match the
  /// canonical name as a case-insensitive substring. Results are capped
  /// at 8 and sorted so prefix matches come before interior-substring
  /// matches, then alphabetically A–Z. Empty queries return an empty
  /// iterable — we keep the surface clean until the user starts typing.
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final setsRepo = ref.read(exerciseSetRepositoryProvider);
    final exercisesRepo = ref.read(exerciseRepositoryProvider);
    final name = (_nameController?.text ?? '').trim();
    final reps = int.parse(_repsController.text.trim());
    final weight = double.parse(_weightController.text.trim());

    try {
      // Resolve the canonical exercise id for the FK.
      //
      // 1. User tapped a suggestion AND the text still matches the
      //    selected exercise's canonical name → use the latched id.
      // 2. Otherwise find-or-create: exact-match lookup, then insert
      //    via the feature-facing wrapper if still missing.
      int exerciseId;
      if (_selectedExerciseId != null && name == _selectedExerciseName) {
        exerciseId = _selectedExerciseId!;
      } else {
        final existing = await exercisesRepo.findByName(name);
        if (existing != null) {
          exerciseId = existing.id;
        } else {
          final created = await exercisesRepo.addIfMissingUserEntered(name);
          exerciseId = created.id;
        }
      }

      if (_isEdit) {
        await setsRepo.update(widget.existing!.copyWith(
          exerciseName: name,
          exerciseId: Value(exerciseId),
          reps: reps,
          weight: weight,
          weightUnit: _unit,
          status: _status,
        ));
      } else {
        await setsRepo.add(ExerciseSetsCompanion.insert(
          sessionId: widget.sessionId,
          exerciseName: name,
          reps: reps,
          weight: weight,
          weightUnit: _unit,
          status: _status,
          orderIndex: widget.nextOrderIndex ?? 0,
          exerciseId: Value(exerciseId),
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
    final initialName = widget.existing?.exerciseName ?? '';
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
              // Canonical-exercise typeahead (#60). Flutter's built-in
              // `Autocomplete<T>` widget — no new pub dep needed.
              // `optionsBuilder` reads from `ExerciseRepository.listAll`
              // (one-shot, widget-test-safe); empty queries yield no
              // suggestions; non-empty queries return ≤ 8 substring
              // matches, prefix-matches first, alphabetical tiebreak.
              Autocomplete<Exercise>(
                displayStringForOption: (e) => e.canonicalName,
                optionsBuilder: (TextEditingValue value) =>
                    _buildSuggestions(value.text),
                onSelected: _onSuggestionSelected,
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  // Seed the controller from the existing row the first
                  // time we see it. Autocomplete hands us a fresh
                  // controller; on subsequent builds it's the same
                  // instance, so we only seed once.
                  if (_nameController == null) {
                    _nameController = controller;
                    if (initialName.isNotEmpty) {
                      controller.text = initialName;
                    }
                  }
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Exercise'),
                    textInputAction: TextInputAction.next,
                    onChanged: _onFieldChanged,
                    onFieldSubmitted: (_) => onFieldSubmitted(),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Exercise name is required'
                        : null,
                  );
                },
              ),
              // Recent-exercises chip strip (issue #39). Sits directly
              // under the Exercise field — clearly "for" that field. Tap
              // fills the text box, parks the caret at the end, and (new
              // in #60) latches the canonical `exerciseId` if the chip
              // name matches an `Exercise` row.
              RecentExercisesStrip(onSelected: _applyRecentName),
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

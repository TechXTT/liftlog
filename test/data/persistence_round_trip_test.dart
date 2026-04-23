import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';

void main() {
  test(
      'entries across all 4 entities survive DB close + reopen against same file',
      () async {
    final dir = Directory.systemTemp.createTempSync('liftlog_persist_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final dbPath = p.join(dir.path, 'liftlog.sqlite');
    final today = DateTime(2026, 4, 23, 12, 30);

    late int sessionId;

    // Phase 1: open DB, write rows, close.
    {
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      final food = FoodEntryRepository(db);
      final weight = BodyWeightLogRepository(db);
      final sessions = WorkoutSessionRepository(db);
      final sets = ExerciseSetRepository(db);

      await food.add(FoodEntriesCompanion.insert(
        timestamp: today,
        name: const Value('Eggs'),
        kcal: 140,
        proteinG: 12.0,
        mealType: MealType.breakfast,
        entryType: FoodEntryType.manual,
      ));
      await food.add(FoodEntriesCompanion.insert(
        timestamp: today.add(const Duration(hours: 4)),
        name: const Value('Chicken'),
        kcal: 310,
        proteinG: 45.0,
        mealType: MealType.lunch,
        entryType: FoodEntryType.manual,
      ));

      await weight.add(BodyWeightLogsCompanion.insert(
        timestamp: today,
        value: 80.0,
        unit: WeightUnit.kg,
      ));

      sessionId = await sessions.add(WorkoutSessionsCompanion.insert(
        startedAt: today.add(const Duration(hours: 6)),
      ));

      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: sessionId,
        exerciseName: 'Bench Press',
        reps: 8,
        weight: 80.0,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 0,
      ));
      await sets.add(ExerciseSetsCompanion.insert(
        sessionId: sessionId,
        exerciseName: 'Bench Press',
        reps: 7,
        weight: 82.5,
        weightUnit: WeightUnit.kg,
        status: WorkoutSetStatus.completed,
        orderIndex: 1,
      ));

      await db.close();
    }

    // File must be on disk between phases.
    expect(File(dbPath).existsSync(), isTrue,
        reason: 'DB file must survive close');

    // Phase 2: reopen DB against the same file, assert round-trip.
    {
      final db = AppDatabase.forTesting(NativeDatabase(File(dbPath)));
      final food = FoodEntryRepository(db);
      final weight = BodyWeightLogRepository(db);
      final sessions = WorkoutSessionRepository(db);
      final sets = ExerciseSetRepository(db);

      final foodRows = await food.listAll();
      expect(foodRows, hasLength(2));
      final byName = {for (final r in foodRows) r.name: r};
      expect(byName['Eggs']!.kcal, 140);
      expect(byName['Eggs']!.proteinG, 12.0);
      expect(byName['Eggs']!.mealType, MealType.breakfast);
      expect(byName['Chicken']!.kcal, 310);

      final totals = await food.watchDailyTotals(today).first;
      expect(totals.kcal, 450);
      expect(totals.proteinG, closeTo(57.0, 1e-9));

      final weightRows = await weight.listAll();
      expect(weightRows, hasLength(1));
      expect(weightRows.first.value, 80.0);
      expect(weightRows.first.unit, WeightUnit.kg);

      final sessionRows = await sessions.listAll();
      expect(sessionRows, hasLength(1));
      expect(sessionRows.first.id, sessionId);

      final setRows = await sets.listForSession(sessionId);
      expect(setRows, hasLength(2));
      expect(setRows[0].orderIndex, 0);
      expect(setRows[0].weight, 80.0);
      expect(setRows[1].orderIndex, 1);
      expect(setRows[1].weight, 82.5);
      expect(setRows.every((s) => s.status == WorkoutSetStatus.completed), isTrue);

      await db.close();
    }
  });
}

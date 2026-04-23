import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'enums.dart';

part 'database.g.dart';

class FoodEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get kcal => integer()();
  RealColumn get proteinG => real()();
  TextColumn get mealType => textEnum<MealType>()();
  TextColumn get entryType => textEnum<FoodEntryType>()();
  TextColumn get note => text().nullable()();
}

class WorkoutSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
}

class ExerciseSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId =>
      integer().references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseName => text()();
  IntColumn get reps => integer()();
  RealColumn get weight => real()();
  TextColumn get weightUnit => textEnum<WeightUnit>()();
  TextColumn get status => textEnum<WorkoutSetStatus>()();
  IntColumn get orderIndex => integer()();
}

class BodyWeightLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();
  RealColumn get value => real()();
  TextColumn get unit => textEnum<WeightUnit>()();
}

@DriftDatabase(tables: [FoodEntries, WorkoutSessions, ExerciseSets, BodyWeightLogs])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // When advancing schemaVersion: document the manual backup path
          // in vault/05 Architecture/Runbooks.md before releasing the migration.
          if (from < 2) {
            await m.addColumn(foodEntries, foodEntries.name);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'liftlog.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/workouts/workout_list_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: WorkoutListScreen()),
      );

  testWidgets('empty state shown when no sessions', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('No workouts yet'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('renders sessions newest-first with in-progress / ended status',
      (tester) async {
    final repo = WorkoutSessionRepository(db);
    await repo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 20, 10),
      endedAt: Value(DateTime(2026, 4, 20, 11)),
    ));
    await repo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 18),
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final inProgress = find.text('In progress');
    final ended = find.text('Ended');
    expect(inProgress, findsOneWidget);
    expect(ended, findsOneWidget);

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

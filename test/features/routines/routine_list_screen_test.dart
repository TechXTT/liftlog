// Widget tests for `RoutineListScreen` (#61).
//
// Covers the two list states — empty and populated — and asserts
// newest-first ordering. Navigation into the form / detail is exercised
// by the other two widget-test files; this one stays scoped to the list
// surface.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/repositories/routine_repository.dart';
import 'package:liftlog_app/features/routines/routine_list_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

Widget _host(AppDatabase db) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: RoutineListScreen()),
  );
}

void main() {
  late AppDatabase db;
  late RoutineRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RoutineRepository(db);
  });

  tearDown(() async => db.close());

  testWidgets('empty state renders the prompt copy', (tester) async {
    await tester.pumpWidget(_host(db));
    await tester.pumpAndSettle();

    expect(find.text('No routines yet. Tap + to create one.'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('populated list renders routines newest-first', (tester) async {
    await repo.add(
      RoutinesCompanion.insert(
        name: 'Push A',
        createdAt: DateTime(2026, 4, 10, 9),
      ),
    );
    await repo.add(
      RoutinesCompanion.insert(
        name: 'Pull B',
        createdAt: DateTime(2026, 4, 20, 9),
      ),
    );

    await tester.pumpWidget(_host(db));
    await tester.pumpAndSettle();

    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Pull B'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));

    // Newest-first ordering. Pull B (Apr 20) should be the first tile.
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    final firstTitle = (tiles.first.title! as Text).data;
    expect(firstTitle, 'Pull B');

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

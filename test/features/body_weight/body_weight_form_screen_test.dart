import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/features/body_weight/body_weight_form_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: child),
  );
}

void main() {
  late AppDatabase db;
  late BodyWeightLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BodyWeightLogRepository(db);
  });

  tearDown(() async => db.close());

  Future<BodyWeightLog> seed({
    double value = 80.0,
    WeightUnit unit = WeightUnit.kg,
  }) async {
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime.now(),
      value: value,
      unit: unit,
    ));
    return (await repo.listAll()).single;
  }

  testWidgets('rejects non-numeric and non-positive values', (tester) async {
    await tester.pumpWidget(_host(db, const BodyWeightFormScreen()));

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a number'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '0');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Must be greater than 0'), findsOneWidget);
  });

  testWidgets('saves with default unit kg', (tester) async {
    await tester.pumpWidget(_host(db, const BodyWeightFormScreen()));
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight'), '80.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final logs = await repo.listAll();
    expect(logs, hasLength(1));
    expect(logs.first.value, 80.5);
    expect(logs.first.unit, WeightUnit.kg);
  });

  testWidgets('unit selection persists (no silent conversion)', (tester) async {
    final entry = await seed(value: 176.0, unit: WeightUnit.lb);

    await tester.pumpWidget(_host(db, BodyWeightFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    final after = (await repo.listAll()).single;
    expect(after.value, 176.0);
    expect(after.unit, WeightUnit.lb,
        reason: 'unit must not be silently converted on load');
  });

  testWidgets('edit updates value and keeps unit', (tester) async {
    final entry = await seed(value: 80.0, unit: WeightUnit.kg);

    await tester.pumpWidget(_host(db, BodyWeightFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Weight'), '79.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = (await repo.listAll()).single;
    expect(after.value, 79.5);
    expect(after.unit, WeightUnit.kg);
  });

  testWidgets('delete → cancel keeps the entry', (tester) async {
    final entry = await seed();
    await tester.pumpWidget(_host(db, BodyWeightFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    expect(find.text('Delete weight log?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await repo.listAll(), hasLength(1));
  });

  testWidgets('delete → confirm removes the entry', (tester) async {
    final entry = await seed();
    await tester.pumpWidget(_host(db, BodyWeightFormScreen(entry: entry)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await repo.listAll(), isEmpty);
  });
}

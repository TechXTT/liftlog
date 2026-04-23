import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/features/body_weight/body_weight_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app() => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: BodyWeightScreen()),
      );

  testWidgets('empty state shows when no weight logs', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.textContaining('No weight logs yet'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('renders logs newest-first with unit', (tester) async {
    final repo = BodyWeightLogRepository(db);
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 20),
      value: 80.0,
      unit: WeightUnit.kg,
    ));
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 23),
      value: 176.0,
      unit: WeightUnit.lb,
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('176.0 lb'), findsOneWidget);
    expect(find.text('80.0 kg'), findsOneWidget);

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

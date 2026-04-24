import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/features/body_weight/body_weight_screen.dart';
import 'package:liftlog_app/features/body_weight/source_badge.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/sources/health_kit/health_source.dart';
import 'package:liftlog_app/sources/health_kit/health_source_fake.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app({HealthSource? healthSource}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (healthSource != null)
        healthSourceProvider.overrideWithValue(healthSource),
    ],
    child: const MaterialApp(home: BodyWeightScreen()),
  );

  testWidgets('empty state shows when no weight logs', (tester) async {
    await tester.pumpWidget(
      app(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No weight logs yet'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('renders logs newest-first with unit', (tester) async {
    final repo = BodyWeightLogRepository(db);
    await repo.add(
      BodyWeightLogsCompanion.insert(
        timestamp: DateTime(2026, 4, 20),
        value: 80.0,
        unit: WeightUnit.kg,
      ),
    );
    await repo.add(
      BodyWeightLogsCompanion.insert(
        timestamp: DateTime(2026, 4, 23),
        value: 176.0,
        unit: WeightUnit.lb,
      ),
    );

    await tester.pumpWidget(
      app(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    expect(find.text('176 lb'), findsOneWidget);
    expect(find.text('80 kg'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets(
    'authorized: merges HK + user-entered rows newest-first with HK badge',
    (tester) async {
      final repo = BodyWeightLogRepository(db);
      // User-entered row, sits between the two HK samples by timestamp.
      await repo.add(
        BodyWeightLogsCompanion.insert(
          timestamp: DateTime(2026, 4, 21),
          value: 81.2,
          unit: WeightUnit.kg,
        ),
      );

      final hkSamples = [
        HKBodyWeightSample(
          sourceId: 'com.apple.Health',
          timestamp: DateTime(2026, 4, 20),
          value: 80.0,
          unit: WeightUnit.kg,
        ),
        HKBodyWeightSample(
          sourceId: 'com.apple.Health',
          timestamp: DateTime(2026, 4, 22),
          value: 176.0,
          unit: WeightUnit.lb,
        ),
      ];

      await tester.pumpWidget(
        app(healthSource: HealthSourceFake.authorized(hkSamples)),
      );
      await tester.pumpAndSettle();

      // All three rows visible.
      expect(find.text('80 kg'), findsOneWidget);
      expect(find.text('81.2 kg'), findsOneWidget);
      expect(find.text('176 lb'), findsOneWidget);

      // Two HealthKit badges (one per HK sample); the user row has none.
      expect(find.byType(SourceBadge), findsNWidgets(2));

      // With HK data present, the Sync button is hidden.
      expect(
        find.widgetWithText(FilledButton, 'Sync with HealthKit'),
        findsNothing,
      );

      // Newest-first ordering: the 4/22 HK lb sample must appear before
      // the 4/21 user row, which in turn appears before the 4/20 HK kg
      // sample. We verify by locating the ListTiles and checking their
      // vertical positions.
      final lbTop = tester.getTopLeft(find.text('176 lb')).dy;
      final userTop = tester.getTopLeft(find.text('81.2 kg')).dy;
      final kgTop = tester.getTopLeft(find.text('80 kg')).dy;
      expect(lbTop, lessThan(userTop));
      expect(userTop, lessThan(kgTop));

      await _drainDriftTimers(tester);
    },
  );

  testWidgets('not authorized: user-entered rows only, Sync button visible', (
    tester,
  ) async {
    final repo = BodyWeightLogRepository(db);
    await repo.add(
      BodyWeightLogsCompanion.insert(
        timestamp: DateTime(2026, 4, 21),
        value: 81.2,
        unit: WeightUnit.kg,
      ),
    );

    await tester.pumpWidget(
      app(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    expect(find.text('81.2 kg'), findsOneWidget);
    expect(find.byType(SourceBadge), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Sync with HealthKit'),
      findsOneWidget,
    );

    await _drainDriftTimers(tester);
  });

  testWidgets(
    'denied state: same as not authorized (no HK rows, Sync visible)',
    (tester) async {
      final repo = BodyWeightLogRepository(db);
      await repo.add(
        BodyWeightLogsCompanion.insert(
          timestamp: DateTime(2026, 4, 21),
          value: 81.2,
          unit: WeightUnit.kg,
        ),
      );

      // A "denied" HealthKit is modeled as not-authorized with a
      // request-permissions call that returns false (the user tapped Deny
      // in the system sheet). The UI should still fall back gracefully.
      final denied = HealthSourceFake.notAuthorized(
        permissionGrantOutcome: false,
      );

      await tester.pumpWidget(app(healthSource: denied));
      await tester.pumpAndSettle();

      expect(find.text('81.2 kg'), findsOneWidget);
      expect(find.byType(SourceBadge), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Sync with HealthKit'),
        findsOneWidget,
      );

      await _drainDriftTimers(tester);
    },
  );
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

// Widget tests for `WorkoutSessionScreen` note UI (S7.4 / #72).
//
// Covers the session-level note surface:
// - non-null note renders as italic muted text above the sets list
// - null note shows a "+ Add note" affordance in the same slot
// - tap opens the edit dialog; Save persists via the repo; Cancel doesn't

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/workouts/workout_session_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/sources/health_kit/health_source_fake.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      healthSourceProvider.overrideWithValue(HealthSourceFake.notAuthorized()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  late AppDatabase db;
  late WorkoutSessionRepository sessions;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessions = WorkoutSessionRepository(db);
  });

  tearDown(() async => db.close());

  testWidgets('session with non-null note renders note text', (tester) async {
    final id = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 10),
      note: const Value('Felt strong today'),
    ));

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    expect(find.text('Felt strong today'), findsOneWidget);
    // No "Add note" CTA when a note is already present.
    expect(find.text('Add note'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('session with null note shows "+ Add note" affordance', (
    tester,
  ) async {
    final id = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 10),
    ));

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Add note'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('tapping "+ Add note" opens dialog; Save persists', (
    tester,
  ) async {
    final id = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 10),
    ));

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    // Tap the TextButton-labelled "Add note" affordance (the dialog
    // title will also render "Add note" once opened, so we scope the
    // tap to the button).
    await tester.tap(find.widgetWithText(TextButton, 'Add note'));
    await tester.pumpAndSettle();

    // Dialog is up.
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Back squat felt heavy');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // DB was updated.
    final row = await sessions.findById(id);
    expect(row!.note, 'Back squat felt heavy');

    // The note now renders above the sets list (the same find.text the
    // first test uses — proves the live stream re-renders the row).
    expect(find.text('Back squat felt heavy'), findsOneWidget);
    // Add-note CTA replaced by the rendered note.
    expect(find.widgetWithText(TextButton, 'Add note'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('Cancel from the note dialog discards (no mutation)', (
    tester,
  ) async {
    final id = await sessions.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 10),
      note: const Value('original'),
    ));

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('original'));
    await tester.pumpAndSettle();

    // Clear and type new text, then Cancel — should NOT persist.
    await tester.enterText(find.byType(TextField), 'new content');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // DB still has the original note.
    final row = await sessions.findById(id);
    expect(row!.note, 'original');
    expect(find.text('original'), findsOneWidget);

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

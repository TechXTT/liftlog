// Widget tests for the Settings tab (issue #48).
//
// Coverage:
//   1. All three section headers (`HealthKit`, `Data`, `About`) render.
//   2. The HealthKit row reflects `HealthSource.isAuthorized()` state:
//        - authorized → subtitle "Authorized", no `Open iOS Settings` CTA.
//        - not authorized → subtitle "Not authorized" + CTA visible.
//   3. The Data section shows both Export and Import buttons.
//   4. The About section shows a non-empty version string.
//   5. The History tab no longer shows the Export/Import labels.
//
// Why no file-picker mock: the iOS file picker is a platform channel
// and triggers `MissingPluginException` in widget tests. The
// import-cancel branch is covered by the dialog-only test in
// `import_cancel_test.dart` (moved here from `test/features/history/`
// in this PR).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/features/history/history_screen.dart';
import 'package:liftlog_app/features/settings/sections/about_section.dart';
import 'package:liftlog_app/features/settings/settings_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/sources/health_kit/health_source.dart';
import 'package:liftlog_app/sources/health_kit/health_source_fake.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  /// Standard `PackageInfo` test double so tests don't hit the native
  /// platform channel (which raises `MissingPluginException` in Dart VM
  /// widget tests). Values are realistic — they mirror what `pubspec.yaml`
  /// + Xcode produce at build time.
  PackageInfo fakePackageInfo() => PackageInfo(
    appName: 'LiftLog',
    packageName: 'dev.techxtt.liftlogApp',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  Widget settingsApp({
    HealthSource? healthSource,
    PackageInfo? packageInfo,
  }) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (healthSource != null)
        healthSourceProvider.overrideWithValue(healthSource),
      packageInfoProvider.overrideWith(
        (ref) async => packageInfo ?? fakePackageInfo(),
      ),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );

  testWidgets('renders all three section headers', (tester) async {
    await tester.pumpWidget(
      settingsApp(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    expect(find.text('HealthKit'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('HealthKit: authorized → "Authorized", no Open iOS Settings CTA',
      (tester) async {
    await tester.pumpWidget(
      settingsApp(healthSource: HealthSourceFake.authorized(const [])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Authorized'), findsOneWidget);
    expect(find.text('Not authorized'), findsNothing);
    expect(find.text('Open iOS Settings'), findsNothing);
  });

  testWidgets(
      'HealthKit: not authorized → "Not authorized" + Open iOS Settings CTA',
      (tester) async {
    await tester.pumpWidget(
      settingsApp(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not authorized'), findsOneWidget);
    expect(find.text('Authorized'), findsNothing);
    expect(find.text('Open iOS Settings'), findsOneWidget);
  });

  testWidgets('Data section: shows Export and Import buttons', (tester) async {
    await tester.pumpWidget(
      settingsApp(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Export all data (JSON)'), findsOneWidget);
    expect(
      find.text('Import all data (replaces current data)'),
      findsOneWidget,
    );
  });

  testWidgets('About: shows a non-empty version string', (tester) async {
    await tester.pumpWidget(
      settingsApp(healthSource: HealthSourceFake.notAuthorized()),
    );
    await tester.pumpAndSettle();

    // Matches either the "1.0.0+1" (version + build) or the bare "1.0.0"
    // line; both satisfy "non-empty version string".
    expect(
      find.textContaining('Version: '),
      findsOneWidget,
      reason: 'About section must surface a version line',
    );
    // And the injected PackageInfo sets version "1.0.0", build "1".
    expect(find.text('Version: 1.0.0+1'), findsOneWidget);
    // Also sanity-check the other About rows so a regression that blanks
    // them shows up here.
    expect(find.text('App: LiftLog'), findsOneWidget);
    expect(find.text('Bundle id: dev.techxtt.liftlogApp'), findsOneWidget);
    expect(find.textContaining('Schema version: v'), findsOneWidget);
  });

  testWidgets(
      'History tab no longer shows Export/Import labels (moved to Settings)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: HistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Export all data (JSON)'), findsNothing);
    expect(
      find.text('Import all data (replaces current data)'),
      findsNothing,
    );

    // Drain any pending Drift stream timers before teardown so the test
    // doesn't hang on fake_async leftovers (pattern from history_screen_test).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

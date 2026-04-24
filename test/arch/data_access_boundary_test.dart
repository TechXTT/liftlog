// Arch guardrail: protects the data-access boundary.
//
// Rule 1 — Feature code does not reach into Drift directly.
//   Under `lib/features/**`, the only permitted `package:drift` import is
//   the narrow companion-value form:
//       import 'package:drift/drift.dart' show Value;
//   Any broader drift import fails the test. Feature code must also never
//   call `.select(` or construct `AppDatabase()` — both are repository-only.
//
// Rule 2 — Repository `update()` methods use `replace()`, not `write()`.
//   Drift's `write()` serializes with `nullToAbsent: true`, silently
//   preserving cleared nullables. That's a trust-rule violation
//   ("no silent mutation"). Scan `lib/data/repositories/**` for any
//   `.write(` occurrence and fail if found. A line containing the literal
//   comment `// drift-write-ok:` opts out — used only when we need `write`
//   for a legitimate reason (justified in a PR).
//
// Rule 3 — `lib/sources/**` is a data-boundary layer (forward-looking,
//   anticipates S4.3 integration sources like HealthKit / barcode /
//   photo-estimate). Feature code must only import the bare façade file
//   from a source module, never the implementation files inside.
//   Convention: a façade file's path ends with `_source.dart` (e.g.
//   `lib/sources/healthkit/healthkit_source.dart`). Any feature import of
//   a non-façade file under `lib/sources/<name>/` fails. The rule runs
//   even when `lib/sources/` doesn't exist yet — it simply finds nothing
//   to flag, keeping the test machinery ready the day a first source
//   module lands. See CLAUDE.md (data-access boundary, v2.0 contract).
//
// Rule 4 — `FoodEntryType` and `Source` are orthogonal — do not conflate.
//   Feature code (`lib/features/**`) must never reference `Source.` —
//   features receive `Source`-typed values from repositories, they don't
//   construct them raw. Tests (`test/**`) may use `Source.` freely. See
//   CLAUDE.md (canonical enums, v2.0 trust rules).
//
// Implementation is deliberately plain: File.readAsStringSync + regex +
// manual Directory walks. No build_runner reflection, no glob packages.
// Keep regexes narrow; brittleness is the known risk.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Resolve the project root from the test file's location so the test
  // works whether run from the repo root, IDE, or CI working directory.
  final projectRoot = _findProjectRoot();
  final featuresDir = Directory(p.join(projectRoot, 'lib', 'features'));
  final reposDir = Directory(p.join(projectRoot, 'lib', 'data', 'repositories'));
  final sourcesDir = Directory(p.join(projectRoot, 'lib', 'sources'));

  group('data access boundary', () {
    test('feature code does not reach into Drift directly', () {
      expect(featuresDir.existsSync(), isTrue,
          reason: 'expected lib/features at ${featuresDir.path}');

      // Matches any `import 'package:drift/...';` — we'll then inspect the
      // matched line to decide if it's the allowed `show Value;` form.
      final driftImport = RegExp(r'''import\s+['"]package:drift/[^'"]+['"][^;]*;''');
      // Narrow allow-list: exactly the companion-Value import, with optional
      // whitespace. We intentionally allow no other `show` lists to keep the
      // boundary tight.
      final allowedDriftImport = RegExp(
        r'''^\s*import\s+['"]package:drift/drift\.dart['"]\s+show\s+Value\s*;\s*$''',
      );
      // `.select(` — the Drift query entry point. Feature code must go
      // through repositories, not the DB directly.
      final selectCall = RegExp(r'\.select\(');
      // `AppDatabase()` — constructing the DB directly bypasses providers.
      final appDbCtor = RegExp(r'AppDatabase\(\)');

      final violations = <String>[];
      for (final file in _dartFilesIn(featuresDir)) {
        final relPath = p.relative(file.path, from: projectRoot);
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final rawLine = lines[i];
          // Skip opt-out lines anywhere we might grow exemptions; for now
          // drift-write-ok is a repo-layer concept but honoring it here is
          // cheap and keeps escape-hatch semantics consistent.
          if (rawLine.contains('// drift-write-ok:')) continue;
          // Strip single-line comments before scanning so doc mentions of
          // `.select(`, `AppDatabase()`, or a drift import in prose don't
          // trigger false positives. Import directives are never inside
          // comments, so this is safe for the drift-import rule too.
          final commentIdx = rawLine.indexOf('//');
          final codePart = commentIdx >= 0 ? rawLine.substring(0, commentIdx) : rawLine;

          if (driftImport.hasMatch(codePart) && !allowedDriftImport.hasMatch(codePart)) {
            violations.add('$relPath:${i + 1}: disallowed drift import: ${rawLine.trim()}');
          }
          if (selectCall.hasMatch(codePart)) {
            violations.add('$relPath:${i + 1}: feature code must not call .select(: ${rawLine.trim()}');
          }
          if (appDbCtor.hasMatch(codePart)) {
            violations.add('$relPath:${i + 1}: feature code must not construct AppDatabase(): ${rawLine.trim()}');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Feature code must go through repositories. Violations:\n'
            '${violations.join('\n')}',
      );
    });

    test('feature code imports only the lib/sources/<name>/ façade', () {
      // Forward-looking rule (see Rule 3 at top of file). Convention:
      // a façade file's path ends with `_source.dart`. Implementation
      // files inside `lib/sources/<name>/` are off-limits to feature
      // code — features must depend only on the façade.
      //
      // If `lib/sources/` doesn't exist yet this test runs clean (there
      // is nothing to import); the rule still catches the first
      // offender the day a source module lands.
      //
      // Regex anatomy:
      //   ^\s*import\s+['"]          — import directive start
      //   package:liftlog_app/sources/ — our package prefix + sources/
      //   [^/]+/                     — exactly one subdirectory (module name)
      //   [^'"]*\.dart               — some file path ending in .dart
      //   ['"]                       — closing quote
      final sourcesImport = RegExp(
        r'''^\s*import\s+['"]package:liftlog_app/sources/([^/]+)/([^'"]*\.dart)['"][^;]*;''',
      );

      final violations = <String>[];
      for (final file in _dartFilesIn(featuresDir)) {
        final relPath = p.relative(file.path, from: projectRoot);
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final rawLine = lines[i];
          final commentIdx = rawLine.indexOf('//');
          final codePart =
              commentIdx >= 0 ? rawLine.substring(0, commentIdx) : rawLine;
          final match = sourcesImport.firstMatch(codePart);
          if (match == null) continue;
          final importedFile = match.group(2)!;
          // Façade convention: filename ends with `_source.dart`.
          if (importedFile.endsWith('_source.dart')) continue;
          violations.add(
            '$relPath:${i + 1}: feature code must import only the '
            '<name>_source.dart façade, not ${rawLine.trim()}',
          );
        }
      }

      // `sourcesDir` is informational — the test does not require the
      // directory to exist. Referenced here so the linter doesn't flag
      // the local as unused and so a future reader sees the link.
      assert(sourcesDir.path.endsWith('sources'));

      expect(
        violations,
        isEmpty,
        reason: 'Feature code must import only the <name>_source.dart '
            'façade from lib/sources/<name>/. Violations:\n'
            '${violations.join('\n')}',
      );
    });

    test('FoodEntryType and Source are orthogonal: features never reference Source.',
        () {
      expect(featuresDir.existsSync(), isTrue,
          reason: 'expected lib/features at ${featuresDir.path}');

      // Plain token match: `Source.` anywhere in feature code. Features
      // must never construct `Source` values raw — they receive them
      // from repositories. Tests can freely reference `Source.`; this
      // rule only scans `lib/features/**`.
      final sourceToken = RegExp(r'\bSource\.');

      final violations = <String>[];
      for (final file in _dartFilesIn(featuresDir)) {
        final relPath = p.relative(file.path, from: projectRoot);
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final rawLine = lines[i];
          final commentIdx = rawLine.indexOf('//');
          final codePart =
              commentIdx >= 0 ? rawLine.substring(0, commentIdx) : rawLine;
          if (!sourceToken.hasMatch(codePart)) continue;
          violations.add(
            '$relPath:${i + 1}: feature code must not reference Source. '
            'directly (see CLAUDE.md canonical enums): ${rawLine.trim()}',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'FoodEntryType and Source are orthogonal. Features must '
            'not construct Source values raw. Violations:\n'
            '${violations.join('\n')}',
      );
    });

    test('repository update() methods use replace(), not write()', () {
      expect(reposDir.existsSync(), isTrue,
          reason: 'expected lib/data/repositories at ${reposDir.path}');

      // `.write(` — the offending serializer. Allow opt-out only via an
      // explicit `// drift-write-ok:` marker on the same line. We also
      // strip single-line comments (`//` and `///`) before scanning so
      // docstring mentions of `write(` don't trigger false positives.
      final writeCall = RegExp(r'\.write\(');

      final violations = <String>[];
      for (final file in _dartFilesIn(reposDir)) {
        final relPath = p.relative(file.path, from: projectRoot);
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final rawLine = lines[i];
          // Minimal opt-out: raw substring check, as specified.
          if (rawLine.contains('// drift-write-ok:')) continue;
          // Strip anything from the first `//` onward — ignores both `//`
          // and `///` comments. Not perfect (misses URLs in strings and
          // `//` inside string literals), but good enough for repo files
          // which don't contain those patterns.
          final commentIdx = rawLine.indexOf('//');
          final codePart = commentIdx >= 0 ? rawLine.substring(0, commentIdx) : rawLine;
          if (!writeCall.hasMatch(codePart)) continue;
          violations.add('$relPath:${i + 1}: repository must use replace(), not write(): ${rawLine.trim()}');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Drift write() silently preserves cleared nullables. '
            'Use replace() instead. Violations:\n'
            '${violations.join('\n')}',
      );
    });
  });
}

/// Walks up from this test file until it finds a directory containing
/// `pubspec.yaml`. That's the project root. Falls back to cwd if not found
/// (e.g. when tests run from a restructured layout).
String _findProjectRoot() {
  // Script.toFilePath() is the running test's compiled source path; climb
  // from there to locate pubspec.yaml.
  var dir = Directory.fromUri(Platform.script).parent;
  for (var i = 0; i < 10; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      return dir.path;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  // Fallback: Directory.current, which is the repo root when running
  // `flutter test` from the repo.
  return Directory.current.path;
}

/// Yields every `.dart` file under [root], recursively. Plain File/Directory
/// walk — no glob dependency.
Iterable<File> _dartFilesIn(Directory root) sync* {
  if (!root.existsSync()) return;
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

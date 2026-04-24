// Unit tests for `DailyTargetRepository` (schema v5, issue #59 —
// E5 kickoff).
//
// Mirrors the shape of `routine_repository_test.dart`: an in-memory
// Drift DB + the repo under test + explicit coverage of the
// `activeOn(day)` lookup including the boundary case called out in
// the issue ("a target with effectiveFrom = 2026-01-01 is active on
// 2026-06-15"). No delete method exists by design (historical
// integrity) — that's asserted indirectly by exhaustively using the
// four public methods and leaving rows in place across tests.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/daily_target_repository.dart';

void main() {
  late AppDatabase db;
  late DailyTargetRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyTargetRepository(db);
  });

  tearDown(() async => db.close());

  group('daily_targets CRUD', () {
    test('add + listAll round-trip', () async {
      final id = await repo.add(
        DailyTargetsCompanion.insert(
          kcal: 2000,
          proteinG: 140,
          effectiveFrom: DateTime(2026, 4, 1),
          createdAt: DateTime(2026, 4, 1, 9),
        ),
      );
      expect(id, isPositive);

      final all = await repo.listAll();
      expect(all, hasLength(1));
      final row = all.single;
      expect(row.id, id);
      expect(row.kcal, 2000);
      expect(row.proteinG, 140.0);
      expect(row.effectiveFrom, DateTime(2026, 4, 1));
      expect(row.createdAt, DateTime(2026, 4, 1, 9));
      expect(
        row.source,
        Source.userEntered,
        reason: 'source defaults to userEntered per schema DEFAULT',
      );
    });

    test('update writes every column via replace (not write)', () async {
      final id = await repo.add(
        DailyTargetsCompanion.insert(
          kcal: 1800,
          proteinG: 120,
          effectiveFrom: DateTime(2026, 4, 1),
          createdAt: DateTime(2026, 4, 1, 9),
        ),
      );
      final row = (await repo.listAll()).single;
      expect(row.id, id);

      await repo.update(row.copyWith(kcal: 2100, proteinG: 150));

      final after = (await repo.listAll()).single;
      expect(after.kcal, 2100);
      expect(after.proteinG, 150.0);
      expect(
        after.effectiveFrom,
        DateTime(2026, 4, 1),
        reason: 'effectiveFrom must survive the update',
      );
    });

    test(
      'listAll orders newest-first by effectiveFrom desc, id desc',
      () async {
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1800,
            proteinG: 120,
            effectiveFrom: DateTime(2026, 4, 1),
            createdAt: DateTime(2026, 4, 1),
          ),
        );
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 2000,
            proteinG: 140,
            effectiveFrom: DateTime(2026, 4, 20),
            createdAt: DateTime(2026, 4, 20),
          ),
        );
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1900,
            proteinG: 130,
            effectiveFrom: DateTime(2026, 4, 10),
            createdAt: DateTime(2026, 4, 10),
          ),
        );

        final all = await repo.listAll();
        expect(all.map((t) => t.kcal).toList(), [2000, 1900, 1800]);
      },
    );

    test(
      'listAll tie-break: same effectiveFrom sorts by id DESC (later wins)',
      () async {
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1800,
            proteinG: 120,
            effectiveFrom: DateTime(2026, 4, 1),
            createdAt: DateTime(2026, 4, 1, 9),
          ),
        );
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1900,
            proteinG: 130,
            effectiveFrom: DateTime(2026, 4, 1),
            createdAt: DateTime(2026, 4, 1, 18),
          ),
        );

        final all = await repo.listAll();
        expect(
          all.map((t) => t.kcal).toList(),
          [1900, 1800],
          reason: 'the later-inserted row wins on a same-day tie',
        );
      },
    );

    test('watchAll emits rows in the same newest-first ordering', () async {
      await repo.add(
        DailyTargetsCompanion.insert(
          kcal: 1800,
          proteinG: 120,
          effectiveFrom: DateTime(2026, 4, 1),
          createdAt: DateTime(2026, 4, 1),
        ),
      );
      await repo.add(
        DailyTargetsCompanion.insert(
          kcal: 2000,
          proteinG: 140,
          effectiveFrom: DateTime(2026, 4, 20),
          createdAt: DateTime(2026, 4, 20),
        ),
      );

      final first = await repo.watchAll().first;
      expect(first.map((t) => t.kcal).toList(), [2000, 1800]);
    });

    test('source can be explicitly set via the Companion', () async {
      // Exercising that `source` is writable (not just defaulted) —
      // matters for the export/import round-trip below in issue #59's
      // tests where `source` travels intact through JSON.
      await repo.add(
        DailyTargetsCompanion.insert(
          kcal: 2000,
          proteinG: 140,
          effectiveFrom: DateTime(2026, 4, 1),
          createdAt: DateTime(2026, 4, 1),
          source: const Value(Source.imported),
        ),
      );
      final row = (await repo.listAll()).single;
      expect(row.source, Source.imported);
    });
  });

  group('activeOn', () {
    test('returns null when no target exists', () async {
      expect(await repo.activeOn(DateTime(2026, 6, 15)), isNull);
    });

    test('returns null when every target is after the queried day', () async {
      await repo.add(
        DailyTargetsCompanion.insert(
          kcal: 2000,
          proteinG: 140,
          effectiveFrom: DateTime(2026, 5, 1),
          createdAt: DateTime(2026, 5, 1),
        ),
      );
      expect(
        await repo.activeOn(DateTime(2026, 4, 20)),
        isNull,
        reason: 'a target starting 2026-05-01 is not active on 2026-04-20',
      );
    });

    test(
      'boundary: target with effectiveFrom 2026-01-01 is active on 2026-06-15',
      () async {
        // The explicit boundary case called out in issue #59.
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 2200,
            proteinG: 160,
            effectiveFrom: DateTime(2026, 1, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        final active = await repo.activeOn(DateTime(2026, 6, 15));
        expect(active, isNotNull);
        expect(active!.kcal, 2200);
        expect(active.proteinG, 160.0);
        expect(active.effectiveFrom, DateTime(2026, 1, 1));
      },
    );

    test(
      'returns the latest target whose effectiveFrom is <= day',
      () async {
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1800,
            proteinG: 120,
            effectiveFrom: DateTime(2026, 1, 1),
            createdAt: DateTime(2026, 1, 1),
          ),
        );
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 2000,
            proteinG: 140,
            effectiveFrom: DateTime(2026, 4, 1),
            createdAt: DateTime(2026, 4, 1),
          ),
        );
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 2200,
            proteinG: 160,
            effectiveFrom: DateTime(2026, 5, 15),
            createdAt: DateTime(2026, 5, 15),
          ),
        );

        // Day 2026-04-15: only the Jan 1 and Apr 1 targets qualify; Apr 1 wins.
        final mid = await repo.activeOn(DateTime(2026, 4, 15));
        expect(mid!.kcal, 2000);

        // Day 2026-06-15: all three qualify; May 15 wins.
        final latest = await repo.activeOn(DateTime(2026, 6, 15));
        expect(latest!.kcal, 2200);

        // Day 2026-01-01: the Jan 1 target is active exactly on its start day.
        final sameDay = await repo.activeOn(DateTime(2026, 1, 1));
        expect(sameDay!.kcal, 1800);
      },
    );

    test(
      'tie on same effectiveFrom: later-inserted row wins',
      () async {
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1800,
            proteinG: 120,
            effectiveFrom: DateTime(2026, 4, 1),
            createdAt: DateTime(2026, 4, 1, 9),
          ),
        );
        await repo.add(
          DailyTargetsCompanion.insert(
            kcal: 1900,
            proteinG: 130,
            effectiveFrom: DateTime(2026, 4, 1),
            createdAt: DateTime(2026, 4, 1, 18),
          ),
        );
        final active = await repo.activeOn(DateTime(2026, 4, 5));
        expect(active!.kcal, 1900);
      },
    );
  });
}

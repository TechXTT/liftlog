import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';

void main() {
  late AppDatabase db;
  late BodyWeightLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BodyWeightLogRepository(db);
  });

  tearDown(() async => db.close());

  test('add preserves unit exactly (no silent conversion)', () async {
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 23),
      value: 80.0,
      unit: WeightUnit.kg,
    ));
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 22),
      value: 176.0,
      unit: WeightUnit.lb,
    ));

    final all = await repo.watchAll().first;
    expect(all, hasLength(2));
    final byUnit = {for (final log in all) log.unit: log.value};
    expect(byUnit[WeightUnit.kg], 80.0);
    expect(byUnit[WeightUnit.lb], 176.0);
  });

  test('update + delete', () async {
    final id = await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 23),
      value: 80.0,
      unit: WeightUnit.kg,
    ));

    final original = (await repo.watchAll().first).single;
    await repo.update(original.copyWith(value: 79.5));
    expect((await repo.watchAll().first).single.value, 79.5);

    expect(await repo.delete(id), 1);
    expect(await repo.watchAll().first, isEmpty);
  });

  test('watchAll orders newest-first', () async {
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 20),
      value: 80.0,
      unit: WeightUnit.kg,
    ));
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 23),
      value: 79.5,
      unit: WeightUnit.kg,
    ));
    await repo.add(BodyWeightLogsCompanion.insert(
      timestamp: DateTime(2026, 4, 22),
      value: 79.8,
      unit: WeightUnit.kg,
    ));

    final values = (await repo.watchAll().first).map((l) => l.value).toList();
    expect(values, [79.5, 79.8, 80.0]);
  });
}

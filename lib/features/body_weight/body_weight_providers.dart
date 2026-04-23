import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../providers/app_providers.dart';

final bodyWeightLogsProvider = StreamProvider<List<BodyWeightLog>>((ref) {
  final repo = ref.watch(bodyWeightLogRepositoryProvider);
  return repo.watchAll();
});

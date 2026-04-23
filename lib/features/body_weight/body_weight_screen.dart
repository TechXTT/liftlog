import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../food/date_label.dart';
import 'body_weight_form_screen.dart';
import 'body_weight_providers.dart';
import 'weight_unit_label.dart';

class BodyWeightScreen extends ConsumerWidget {
  const BodyWeightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(bodyWeightLogsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Body weight')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
      body: logs.when(
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No weight logs yet.\nTap + to record one.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final e = list[i];
                  return ListTile(
                    title: Text('${e.value} ${weightUnitLabel(e.unit)}'),
                    subtitle: Text(shortDate(e.timestamp)),
                    onTap: () => _openForm(context, entry: e),
                  );
                },
              ),
        loading: () => const SizedBox.shrink(),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load weight logs: $err'),
          ),
        ),
      ),
    );
  }

  void _openForm(BuildContext context, {BodyWeightLog? entry}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BodyWeightFormScreen(entry: entry),
    ));
  }
}

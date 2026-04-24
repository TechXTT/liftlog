// Settings tab — the 6th bottom-nav destination (issue #48).
//
// Scope is intentionally minimal: three inline sections, each rendered
// by its own file under `sections/` for focus and testability. The
// screen itself only owns the `ListView` scaffolding and the section
// headers + dividers between them.
//
// Styling matches the History tab: `_SectionHeader` with 16/16/16/8 pad,
// inline content, Divider between sections. No AppBar actions — every
// Settings affordance is inside a section.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sections/about_section.dart';
import 'sections/data_section.dart';
import 'sections/healthkit_section.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          _SectionHeader(label: 'HealthKit'),
          HealthKitSection(),
          SizedBox(height: 8),
          Divider(height: 1),
          _SectionHeader(label: 'Data'),
          DataSection(),
          SizedBox(height: 8),
          Divider(height: 1),
          _SectionHeader(label: 'About'),
          AboutSection(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

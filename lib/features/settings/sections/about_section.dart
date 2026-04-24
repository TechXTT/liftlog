// About section of the Settings tab (issue #48).
//
// Shows app identity + current runtime schema version. Values come from
// `package_info_plus` (app name, version, build number, bundle id) and
// from the live `AppDatabase.schemaVersion` — the latter is deliberately
// read at runtime rather than hardcoded so the displayed "Schema version"
// stays honest across future migrations without someone having to
// remember to bump a constant in two places.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../providers/app_providers.dart';

/// Cached `PackageInfo` for the Settings → About section. Overridable
/// in widget tests via `packageInfoProvider.overrideWithValue(...)` so
/// tests don't hit the platform channel.
final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(packageInfoProvider);
    final db = ref.watch(appDatabaseProvider);
    final schemaVersion = db.schemaVersion;

    return info.when(
      data: (pkg) => _AboutList(
        appName: pkg.appName.isEmpty ? 'LiftLog' : pkg.appName,
        version: pkg.version,
        buildNumber: pkg.buildNumber,
        bundleId: pkg.packageName,
        schemaVersion: schemaVersion,
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Loading…'),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('About: $err'),
      ),
    );
  }
}

class _AboutList extends StatelessWidget {
  const _AboutList({
    required this.appName,
    required this.version,
    required this.buildNumber,
    required this.bundleId,
    required this.schemaVersion,
  });

  final String appName;
  final String version;
  final String buildNumber;
  final String bundleId;
  final int schemaVersion;

  @override
  Widget build(BuildContext context) {
    final versionLine = buildNumber.isEmpty ? version : '$version+$buildNumber';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AboutTile(label: 'App', value: appName),
        _AboutTile(label: 'Version', value: versionLine),
        _AboutTile(label: 'Bundle id', value: bundleId),
        _AboutTile(label: 'Schema version', value: 'v$schemaVersion'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Data precedence: user-entered > saved templates > HealthKit > '
            'derived > imported.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text('$label: $value'),
    );
  }
}

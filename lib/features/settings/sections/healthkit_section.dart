// HealthKit section of the Settings tab (issue #48).
//
// Surfaces the current `HealthSource.isAuthorized()` state and — when
// not authorized — offers a deep link into this app's page in the iOS
// Settings app (`app-settings:` URL scheme) so the user has a direct
// path to flip the permission.
//
// Trust rule hook: the hint under the button exists because iOS never
// reveals actual read-authorization state (HealthKit obscures it by
// design). So "Not authorized" after a grant can also mean the
// HealthKit capability isn't enabled in the build — the hint gives the
// user a useful next step without exposing vault / runbook paths.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/app_providers.dart';
import '../../../ui/show_save_error.dart';

/// Reads the current HealthKit authorization state from the façade
/// provider. Re-invalidated whenever the user returns from iOS Settings
/// (we invalidate in the `Open iOS Settings` button's async handler so
/// the row updates without the user having to switch tabs).
final healthKitAuthorizedProvider = FutureProvider<bool>((ref) async {
  final source = ref.watch(healthSourceProvider);
  return source.isAuthorized();
});

class HealthKitSection extends ConsumerWidget {
  const HealthKitSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorized = ref.watch(healthKitAuthorizedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        authorized.when(
          data: (isAuthorized) => ListTile(
            title: const Text('Body-weight read access'),
            subtitle: Text(isAuthorized ? 'Authorized' : 'Not authorized'),
            leading: Icon(
              isAuthorized ? Icons.check_circle_outline : Icons.error_outline,
            ),
          ),
          loading: () => const ListTile(
            title: Text('Body-weight read access'),
            subtitle: Text('Checking...'),
            leading: Icon(Icons.hourglass_empty),
          ),
          error: (err, _) => ListTile(
            title: const Text('Body-weight read access'),
            subtitle: Text('Error: $err'),
            leading: const Icon(Icons.error_outline),
          ),
        ),
        if (authorized.asData?.value == false)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => _openIosSettings(context, ref),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open iOS Settings'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            "If this still shows 'Not authorized' after granting "
            'permission in the iOS Settings app, the HealthKit capability '
            'may not be enabled in this build — ask the developer to '
            'verify.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Future<void> _openIosSettings(BuildContext context, WidgetRef ref) async {
    final uri = Uri.parse('app-settings:');
    try {
      final launched = await launchUrl(uri);
      if (!launched) {
        if (context.mounted) {
          showSaveError(
            context,
            'open iOS Settings',
            'the URL scheme was rejected',
          );
        }
        return;
      }
    } catch (e) {
      if (context.mounted) showSaveError(context, 'open iOS Settings', e);
      return;
    }
    // Refresh the authorization state after returning from Settings so
    // the row updates without a tab-switch.
    ref.invalidate(healthKitAuthorizedProvider);
  }
}

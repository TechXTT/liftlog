import 'package:flutter/material.dart';

import '../features/body_weight/body_weight_screen.dart';
import '../features/food/food_log_screen.dart';
import '../features/history/history_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/workouts/workout_list_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  /// Index of the Settings tab in the `_tabs` list below. Kept as a
  /// named constant so the Food tab's "Set a daily target in Settings"
  /// affordance (issue #59) can jump directly without hardcoding a
  /// magic number that falls out of sync when tabs get reordered.
  static const int _settingsTabIndex = 5;

  late final List<Widget> _tabs = [
    FoodLogScreen(onRequestSettings: _goToSettings),
    const BodyWeightScreen(),
    const WorkoutListScreen(),
    const HistoryScreen(),
    const ProgressScreen(),
    const SettingsScreen(),
  ];

  void _goToSettings() {
    if (!mounted) return;
    setState(() => _index = _settingsTabIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Food',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_weight_outlined),
            selectedIcon: Icon(Icons.monitor_weight),
            label: 'Weight',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Workouts',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Progress',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}


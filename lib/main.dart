import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/food/food_log_screen.dart';

void main() {
  runApp(const ProviderScope(child: LiftLogApp()));
}

class LiftLogApp extends StatelessWidget {
  const LiftLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiftLog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FoodLogScreen(),
    );
  }
}

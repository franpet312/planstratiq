import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/planner_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  runApp(const PlanstratiqApp());
}

class PlanstratiqApp extends StatelessWidget {
  const PlanstratiqApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planstratiq',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6FD9)),
        visualDensity: VisualDensity.compact,
      ),
      home: const PlannerPage(),
    );
  }
}

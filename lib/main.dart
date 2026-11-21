import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/theme.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  runApp(const PlanstratiqApp());
}

class PlanstratiqApp extends StatelessWidget {
  const PlanstratiqApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Planstratiq',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomePage(),
      );
}

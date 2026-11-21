import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/theme.dart';
import 'state/imported_catalog.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) BrowserContextMenu.disableContextMenu();
  ImportedCatalog.instance; // učitaj uvezene proizvode prije otvaranja projekata
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

import 'package:flutter/material.dart';

import 'config/companion_config.dart';
import 'ui/companion_home_view.dart';

/// Root widget. Loads the bundled config (R3) before building the home view.
class CompanionApp extends StatefulWidget {
  const CompanionApp({super.key});

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  final CompanionConfig _config = CompanionConfig();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _config.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'app_box companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: _ready
          ? CompanionHomeView(config: _config)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings/settings_providers.dart';
import 'features/about/about_screen.dart';
import 'features/capture/capture_screen.dart';
import 'features/export/export_screen.dart';
import 'features/measure/measure_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/stack/stack_screen.dart';
import 'features/tutorial/tutorial_screen.dart';

class InscriptionRakingLightApp extends ConsumerWidget {
  const InscriptionRakingLightApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(settingsProvider.select((s) => s.themeMode));
    final lightScheme =
        ColorScheme.fromSeed(seedColor: const Color(0xFF6E5B3A));
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF6E5B3A),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Stela',
      theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _tutorialShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _tutorialShown) return;
      final hasSeen = ref.read(settingsProvider).hasSeenTutorial;
      if (!hasSeen) {
        _tutorialShown = true;
        _openTutorial();
      }
    });
  }

  void _openTutorial() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const TutorialScreen(),
    ));
  }

  static const _tabs = <Widget>[
    CaptureScreen(),
    StackScreen(),
    MeasureScreen(),
    ExportScreen(),
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
        icon: Icon(Icons.camera_alt_outlined), label: 'Capture'),
    NavigationDestination(
        icon: Icon(Icons.layers_outlined), label: 'Stack'),
    NavigationDestination(
        icon: Icon(Icons.straighten_outlined), label: 'Measure'),
    NavigationDestination(
        icon: Icon(Icons.ios_share_outlined), label: 'Export'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_index].label),
        actions: [
          IconButton(
            tooltip: 'Tutorial',
            icon: const Icon(Icons.help_outline),
            onPressed: _openTutorial,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) {
              switch (v) {
                case 'settings':
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ));
                case 'about':
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AboutScreen(),
                  ));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('About Stela'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(child: _tabs[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

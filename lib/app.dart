import 'package:flutter/material.dart';

import 'features/capture/capture_screen.dart';
import 'features/export/export_screen.dart';
import 'features/measure/measure_screen.dart';
import 'features/stack/stack_screen.dart';

class InscriptionRakingLightApp extends StatelessWidget {
  const InscriptionRakingLightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Streiflicht',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6E5B3A)),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    CaptureScreen(),
    StackScreen(),
    MeasureScreen(),
    ExportScreen(),
  ];

  static const _destinations = <NavigationDestination>[
    NavigationDestination(icon: Icon(Icons.camera_alt_outlined), label: 'Capture'),
    NavigationDestination(icon: Icon(Icons.layers_outlined), label: 'Stack'),
    NavigationDestination(icon: Icon(Icons.straighten_outlined), label: 'Measure'),
    NavigationDestination(icon: Icon(Icons.ios_share_outlined), label: 'Export'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _tabs[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

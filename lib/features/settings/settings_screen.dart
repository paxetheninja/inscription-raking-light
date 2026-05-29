import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/image_ops/registration.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(label: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(settings.themeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) notifier.setThemeMode(v);
              },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
            ),
          ),

          _SectionHeader(label: 'Pipeline'),
          ListTile(
            leading: const Icon(Icons.aspect_ratio),
            title: const Text('Preview resolution'),
            subtitle: Text(
                'On-device gallery uses ${settings.previewMaxEdge} px on the '
                'long edge. The desktop pipeline always uses the full-res RAW.'),
            trailing: DropdownButton<int>(
              value: settings.previewMaxEdge,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) notifier.setPreviewMaxEdge(v);
              },
              items: AppSettings.previewMaxEdgeOptions
                  .map((px) => DropdownMenuItem(
                        value: px,
                        child: Text('$px px'),
                      ))
                  .toList(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.compare_arrows),
            title: const Text('Default registration'),
            subtitle: Text(_regLabel(settings.defaultRegistration)),
            trailing: DropdownButton<RegistrationMode>(
              value: settings.defaultRegistration,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) notifier.setDefaultRegistration(v);
              },
              items: const [
                DropdownMenuItem(
                    value: RegistrationMode.none, child: Text('None')),
                DropdownMenuItem(
                    value: RegistrationMode.fast, child: Text('Fast')),
                DropdownMenuItem(
                    value: RegistrationMode.accurate, child: Text('Accurate')),
                DropdownMenuItem(
                    value: RegistrationMode.orb, child: Text('ORB')),
              ],
            ),
          ),

          _SectionHeader(label: 'Capture'),
          SwitchListTile(
            secondary: const Icon(Icons.skip_next_outlined),
            title: const Text('Auto-advance light direction'),
            subtitle: const Text(
                'When starting a new session, the light-direction picker '
                'walks itself through N → NW × low → mid → high after each '
                'shutter press.'),
            value: settings.autoAdvanceDefault,
            onChanged: notifier.setAutoAdvanceDefault,
          ),

          _SectionHeader(label: 'Onboarding'),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Show tutorial again'),
            subtitle: const Text('Reset the first-launch walkthrough so it '
                'plays the next time you reopen Stela.'),
            onTap: () async {
              await notifier.resetOnboarding();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Tutorial will play on next launch.')),
              );
            },
          ),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Match the system',
        ThemeMode.light => 'Always light',
        ThemeMode.dark => 'Always dark',
      };

  static String _regLabel(RegistrationMode m) => switch (m) {
        RegistrationMode.none => 'No alignment (frames assumed aligned)',
        RegistrationMode.fast => 'Fast — NCC translation (2-DoF)',
        RegistrationMode.accurate =>
          'Accurate — NCC + rotation/scale (4-DoF)',
        RegistrationMode.orb => 'ORB + RANSAC (OpenCV) — when available',
      };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

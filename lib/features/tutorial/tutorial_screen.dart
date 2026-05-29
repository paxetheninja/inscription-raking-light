import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:introduction_screen/introduction_screen.dart';

import '../../core/settings/settings_providers.dart';

class TutorialScreen extends ConsumerWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final pageDecoration = PageDecoration(
      titleTextStyle: Theme.of(context).textTheme.headlineMedium!,
      bodyTextStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
      bodyPadding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      imagePadding: const EdgeInsets.only(top: 40),
      pageColor: scheme.surface,
    );

    Future<void> finish() async {
      await ref.read(settingsProvider.notifier).setHasSeenTutorial(true);
      if (context.mounted) Navigator.of(context).pop();
    }

    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: 'Welcome to Stela',
          bodyWidget: const _Body([
            'Stela helps you document inscriptions with raking light — '
                'photographs taken under a grazing light angle that reveals '
                'incisions invisible in flat lighting.',
            'This tour takes about 60 seconds. You can replay it any time '
                'from the AppBar "?" or from Settings.',
          ]),
          image: _CoverIcon(color: scheme.primary, icon: Icons.auto_awesome),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Capture a burst',
          bodyWidget: const _Body([
            'Mount the phone on a tripod or hold it steady against the stone. '
                'An assistant sweeps a flashlight at a low angle across the '
                'surface.',
            'In the Capture tab, tap "Start new session" and label it (the '
                'stone\'s find-number works). Lock exposure & focus once the '
                'frame is right, then tap the shutter at each light position.',
          ]),
          image: _CoverIcon(color: scheme.primary, icon: Icons.camera_alt),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Tag the light direction',
          bodyWidget: const _Body([
            'Each frame can be tagged with the direction the light came '
                'from — eight compass points × three elevations.',
            'Leave "auto" on and the picker walks itself through N → NE → … '
                '→ NW × low → mid → high after each shutter, so you can keep '
                'your hands on the light.',
            'Tagged frames let the Stack tab compute a true photometric-'
                'stereo normal map.',
          ]),
          image: _CoverIcon(color: scheme.primary, icon: Icons.explore),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Stack & gallery',
          bodyWidget: const _Body([
            'Open the Stack tab, pick a session, tap "Compute reductions". '
                'About 10–30 seconds later you get a swipeable gallery of '
                'enhanced images.',
            'Highlights: PC2 (primary relief channel), black hat (extracts '
                'carved grooves explicitly), combined relief, fusion + '
                'CLAHE, multi-scale DoG, and — when light directions are '
                'tagged — a photometric-stereo normal map.',
          ]),
          image: _CoverIcon(color: scheme.primary, icon: Icons.layers),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Measure on the image',
          bodyWidget: const _Body([
            'In the Measure tab, pick a session and tap two points on a '
                'ruler visible in the frame. Enter the real-world distance '
                'in mm — Stela saves a mm/pixel calibration.',
            'Switch to "Measure" mode and tap two points to read letter '
                'heights, stroke widths, or line spacings off the image.',
          ]),
          image:
              _CoverIcon(color: scheme.primary, icon: Icons.straighten),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: 'Export to the desktop',
          bodyWidget: const _Body([
            'When you\'re done, the Export tab lets you bundle a session '
                'into a single .zip — original frames + computed enhancement '
                'PNGs + a sidecar.json with metadata.',
            'Share the zip via AirDrop / Files / email and feed it into '
                'the desktop pipeline for full-resolution analysis.',
            'Importing a zip back into Stela works too — sessions survive '
                'a reinstall as long as you exported first.',
          ]),
          image: _CoverIcon(color: scheme.primary, icon: Icons.ios_share),
          decoration: pageDecoration,
        ),
      ],
      onDone: finish,
      onSkip: finish,
      showSkipButton: true,
      skip: const Text('Skip'),
      next: const Icon(Icons.arrow_forward),
      done:
          const Text('Get started', style: TextStyle(fontWeight: FontWeight.w600)),
      dotsDecorator: DotsDecorator(
        size: const Size(8, 8),
        color: scheme.outline,
        activeColor: scheme.primary,
        activeSize: const Size(22, 8),
        activeShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.paragraphs);

  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in paragraphs) ...[
          Text(p, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CoverIcon extends StatelessWidget {
  const _CoverIcon({required this.color, required this.icon});
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
        ),
        child: Icon(icon, size: 80, color: color),
      ),
    );
  }
}

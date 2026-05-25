import 'package:flutter/material.dart';

class StackScreen extends StatelessWidget {
  const StackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stack', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(
            'Per-pixel reductions across the captured burst, applied to a downsampled preview:',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          ..._planned.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('  -  $s'),
              )),
          const SizedBox(height: 16),
          Text(
            'Full-resolution computations run in the desktop pipeline; in-app outputs are previews only.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  static const _planned = [
    'max / min / range / stddev',
    'exposure fusion (Mertens-style)',
    'multi-scale Retinex',
    'CLAHE on the fused output',
    'normal map (photometric stereo) — if light directions known',
  ];
}

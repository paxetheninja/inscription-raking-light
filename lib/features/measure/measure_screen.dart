import 'package:flutter/material.dart';

class MeasureScreen extends StatelessWidget {
  const MeasureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Measure', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(
            'Tap two points on a reference scale in the frame to calibrate mm/pixel, '
            'then measure letter heights, line spacing, and stroke widths on the stacked image.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

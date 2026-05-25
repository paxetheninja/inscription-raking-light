import 'package:flutter/material.dart';

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Placeholder(
      title: 'Capture',
      body:
          'Phone on tripod or held steady. An assistant sweeps a raking light across the stone.\n\n'
          'v0.2 will wire the camera package, lock exposure / white-balance, and capture a burst '
          'while logging IMU-derived light-position hints between shots.',
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

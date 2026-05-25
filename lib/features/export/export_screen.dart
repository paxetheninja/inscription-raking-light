import 'package:flutter/material.dart';

class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Export', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(
            'Each capture session exports as a folder:\n'
            '  /<session-id>/\n'
            '    raw/         original frames (JPEG; DNG when supported)\n'
            '    preview/     downsampled enhancements computed on-device\n'
            '    sidecar.json metadata for desktop reprocessing',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/registration.dart';
import 'package:inscription_raking_light/core/image_ops/stack_reductions.dart';
import 'package:inscription_raking_light/features/stack/results_gallery.dart';

void main() {
  testWidgets('Results gallery shows method name and pagination dots',
      (tester) async {
    final small = Uint8List.fromList(List<int>.filled(16, 128));
    final reductions = StackReductions(
      width: 4,
      height: 4,
      maxImg: small,
      minImg: small,
      rangeImg: small,
      stddevImg: small,
    );
    final pipeline = StackPipelineOutput(
      reductions: reductions,
      fusion: small,
      fusionClahe: small,
      fusionRetinex: small,
      combinedRelief: small,
      multiscaleDog: small,
      pcaComponents: [small, small, small, small],
      registration: const RegistrationResult(
        mode: RegistrationMode.none,
        transforms: [FrameTransform.identity],
        validRect: ValidRect(0, 0, 4, 4),
        scores: [1.0],
        warpedFrames: [],
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: ResultsGalleryScreen(
        headerSubtitle: 's_test',
        pipeline: pipeline,
      ),
    ));
    await tester.pumpAndSettle();

    // With PCA components, the headline first page is PC2 (the primary
    // relief channel per desktop docstrings).
    expect(find.text('PC2 — relief'), findsOneWidget);
    // Header includes a position counter — total depends on which optional
    // outputs are present; just check it starts at 1.
    expect(find.textContaining('1 /'), findsOneWidget);
    // Subtitle is wired through.
    expect(find.textContaining('s_test'), findsOneWidget);
  });
}

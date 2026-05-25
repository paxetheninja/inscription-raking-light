import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    );

    await tester.pumpWidget(MaterialApp(
      home: ResultsGalleryScreen(
        headerSubtitle: 's_test',
        pipeline: pipeline,
      ),
    ));
    await tester.pumpAndSettle();

    // First page is fusion + CLAHE.
    expect(find.text('fusion + CLAHE'), findsOneWidget);
    // Header includes the position counter.
    expect(find.textContaining('1 / 7'), findsOneWidget);
    // Subtitle is wired through.
    expect(find.textContaining('s_test'), findsOneWidget);
  });
}

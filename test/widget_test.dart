import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inscription_raking_light/app.dart';

void main() {
  testWidgets('Home shell renders the four feature tabs', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: InscriptionRakingLightApp()),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Capture'), findsWidgets);
    expect(find.text('Stack'), findsWidgets);
    expect(find.text('Measure'), findsWidgets);
    expect(find.text('Export'), findsWidgets);
  });
}

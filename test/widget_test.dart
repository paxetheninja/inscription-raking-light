import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/app.dart';
import 'package:inscription_raking_light/core/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Home shell renders the four feature tabs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => SettingsNotifier(prefs)),
        ],
        child: const InscriptionRakingLightApp(),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    // Tab names now appear in both the AppBar (the active tab) and the
    // NavigationBar (all four destinations), so each label matches twice
    // *except* the active one which matches once in the bar plus once in
    // the AppBar — i.e. each label appears at least once.
    expect(find.text('Capture'), findsAtLeastNWidgets(1));
    expect(find.text('Stack'), findsAtLeastNWidgets(1));
    expect(find.text('Measure'), findsAtLeastNWidgets(1));
    expect(find.text('Export'), findsAtLeastNWidgets(1));
  });
}

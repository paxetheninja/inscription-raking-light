import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../image_ops/registration.dart';
import 'app_settings.dart';

/// Overridden in `main()` with the SharedPreferences instance loaded at
/// startup. Listeners get notified whenever a setting is mutated.
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  throw UnimplementedError(
      'settingsProvider must be overridden in main() with a real '
      'SharedPreferences instance.');
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static const _kPreviewMaxEdge = 'previewMaxEdge';
  static const _kDefaultRegistration = 'defaultRegistration';
  static const _kAutoAdvanceDefault = 'autoAdvanceDefault';
  static const _kThemeMode = 'themeMode';
  static const _kHasSeenTutorial = 'hasSeenTutorial';

  static AppSettings _load(SharedPreferences p) {
    final regIdx = p.getInt(_kDefaultRegistration);
    final reg = (regIdx != null &&
            regIdx >= 0 &&
            regIdx < RegistrationMode.values.length)
        ? RegistrationMode.values[regIdx]
        : RegistrationMode.fast;
    final themeIdx = p.getInt(_kThemeMode);
    final theme = (themeIdx != null &&
            themeIdx >= 0 &&
            themeIdx < ThemeMode.values.length)
        ? ThemeMode.values[themeIdx]
        : ThemeMode.system;
    return AppSettings(
      previewMaxEdge: p.getInt(_kPreviewMaxEdge) ?? 1024,
      defaultRegistration: reg,
      autoAdvanceDefault: p.getBool(_kAutoAdvanceDefault) ?? true,
      themeMode: theme,
      hasSeenTutorial: p.getBool(_kHasSeenTutorial) ?? false,
    );
  }

  Future<void> setPreviewMaxEdge(int value) async {
    await _prefs.setInt(_kPreviewMaxEdge, value);
    state = state.copyWith(previewMaxEdge: value);
  }

  Future<void> setDefaultRegistration(RegistrationMode value) async {
    await _prefs.setInt(_kDefaultRegistration, value.index);
    state = state.copyWith(defaultRegistration: value);
  }

  Future<void> setAutoAdvanceDefault(bool value) async {
    await _prefs.setBool(_kAutoAdvanceDefault, value);
    state = state.copyWith(autoAdvanceDefault: value);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    await _prefs.setInt(_kThemeMode, value.index);
    state = state.copyWith(themeMode: value);
  }

  Future<void> setHasSeenTutorial(bool value) async {
    await _prefs.setBool(_kHasSeenTutorial, value);
    state = state.copyWith(hasSeenTutorial: value);
  }

  Future<void> resetOnboarding() => setHasSeenTutorial(false);
}

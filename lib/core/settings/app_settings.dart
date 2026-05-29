import 'package:flutter/material.dart';

import '../image_ops/registration.dart';

/// User-controllable settings, persisted via shared_preferences.
class AppSettings {
  const AppSettings({
    this.previewMaxEdge = 1024,
    this.defaultRegistration = RegistrationMode.fast,
    this.autoAdvanceDefault = true,
    this.themeMode = ThemeMode.system,
    this.hasSeenTutorial = false,
    this.tagLocationOnCapture = false,
  });

  /// Long-edge size for the on-device preview pipeline. The desktop pipeline
  /// always operates on full-resolution captures; this only affects the
  /// in-app gallery outputs.
  final int previewMaxEdge;

  /// Default registration mode for new Stack-tab compute runs.
  final RegistrationMode defaultRegistration;

  /// Default auto-advance state for the light-direction picker.
  final bool autoAdvanceDefault;

  final ThemeMode themeMode;

  /// Whether the first-launch tutorial has been completed at least once.
  final bool hasSeenTutorial;

  /// When true, the Capture flow attempts a single GPS fix at the start of
  /// each new session and writes it into the sidecar. Off by default — the
  /// user must opt in, and a permission prompt fires the first time.
  final bool tagLocationOnCapture;

  static const previewMaxEdgeOptions = [768, 1024, 1536];

  AppSettings copyWith({
    int? previewMaxEdge,
    RegistrationMode? defaultRegistration,
    bool? autoAdvanceDefault,
    ThemeMode? themeMode,
    bool? hasSeenTutorial,
    bool? tagLocationOnCapture,
  }) =>
      AppSettings(
        previewMaxEdge: previewMaxEdge ?? this.previewMaxEdge,
        defaultRegistration: defaultRegistration ?? this.defaultRegistration,
        autoAdvanceDefault: autoAdvanceDefault ?? this.autoAdvanceDefault,
        themeMode: themeMode ?? this.themeMode,
        hasSeenTutorial: hasSeenTutorial ?? this.hasSeenTutorial,
        tagLocationOnCapture:
            tagLocationOnCapture ?? this.tagLocationOnCapture,
      );
}

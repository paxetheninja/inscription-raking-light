/// Draft schema for the per-session sidecar JSON consumed by the desktop pipeline.
///
/// One sidecar.json per capture session, sitting next to a `raw/` folder of frames.
library;

class SidecarV1 {
  const SidecarV1({
    required this.sessionId,
    required this.capturedAt,
    required this.deviceModel,
    required this.frames,
    this.scaleMmPerPixel,
    this.notes,
  });

  /// Stable session id (ulid).
  final String sessionId;

  /// ISO-8601 capture start.
  final String capturedAt;

  /// e.g. "iPhone15,3" or "Pixel 8".
  final String deviceModel;

  final List<SidecarFrame> frames;

  /// Set if a scale-bar calibration was performed in-app.
  final double? scaleMmPerPixel;

  final String? notes;

  Map<String, dynamic> toJson() => {
        'schema': 'inscription-raking-light/sidecar@1',
        'session_id': sessionId,
        'captured_at': capturedAt,
        'device_model': deviceModel,
        if (scaleMmPerPixel != null) 'scale_mm_per_pixel': scaleMmPerPixel,
        if (notes != null) 'notes': notes,
        'frames': frames.map((f) => f.toJson()).toList(),
      };
}

class SidecarFrame {
  const SidecarFrame({
    required this.file,
    required this.timestampMs,
    this.lightAzimuthDeg,
    this.lightElevationDeg,
    this.iso,
    this.exposureUs,
    this.focusDistanceM,
  });

  /// Path relative to the session folder, e.g. `raw/0001.jpg`.
  final String file;
  final int timestampMs;

  /// IMU-derived light hints (optional — only present if user "pings"
  /// the app at each light position, or if a future companion sensor is used).
  final double? lightAzimuthDeg;
  final double? lightElevationDeg;

  final int? iso;
  final int? exposureUs;
  final double? focusDistanceM;

  Map<String, dynamic> toJson() => {
        'file': file,
        'timestamp_ms': timestampMs,
        if (lightAzimuthDeg != null) 'light_azimuth_deg': lightAzimuthDeg,
        if (lightElevationDeg != null) 'light_elevation_deg': lightElevationDeg,
        if (iso != null) 'iso': iso,
        if (exposureUs != null) 'exposure_us': exposureUs,
        if (focusDistanceM != null) 'focus_distance_m': focusDistanceM,
      };
}

import '../sidecar/sidecar_schema.dart';

/// A capture session: a folder of frames + sidecar metadata.
class Session {
  Session({
    required this.id,
    required this.label,
    required this.capturedAt,
    required this.deviceModel,
    required this.frames,
    this.scaleMmPerPixel,
    this.notes,
  });

  /// Stable session id, e.g. `s_20260525T103045_4f2a`.
  final String id;

  /// Human-readable label entered by the user (stone name etc.).
  String label;

  final DateTime capturedAt;
  final String deviceModel;

  /// Frames captured so far, in capture order.
  final List<SessionFrame> frames;

  double? scaleMmPerPixel;
  String? notes;

  SidecarV1 toSidecar() => SidecarV1(
        sessionId: id,
        label: label,
        capturedAt: capturedAt.toUtc().toIso8601String(),
        deviceModel: deviceModel,
        scaleMmPerPixel: scaleMmPerPixel,
        notes: notes,
        frames: frames
            .map((f) => SidecarFrame(
                  file: 'raw/${f.filename}',
                  timestampMs: f.capturedAt.millisecondsSinceEpoch,
                  iso: f.iso,
                  exposureUs: f.exposureUs,
                  focusDistanceM: f.focusDistanceM,
                ))
            .toList(),
      );
}

class SessionFrame {
  const SessionFrame({
    required this.filename,
    required this.capturedAt,
    this.iso,
    this.exposureUs,
    this.focusDistanceM,
  });

  /// File name within the session's `raw/` folder, e.g. `0001.jpg`.
  final String filename;
  final DateTime capturedAt;
  final int? iso;
  final int? exposureUs;
  final double? focusDistanceM;
}

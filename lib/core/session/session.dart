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
    this.location,
  });

  /// Reconstruct an in-memory [Session] from a previously-written sidecar.
  /// Lets the capture flow resume an existing session.
  factory Session.fromSidecar(SidecarV1 sc) {
    return Session(
      id: sc.sessionId,
      label: sc.label,
      capturedAt:
          DateTime.tryParse(sc.capturedAt) ?? DateTime.now().toUtc(),
      deviceModel: sc.deviceModel,
      frames: sc.frames
          .map((f) => SessionFrame(
                filename:
                    f.file.startsWith('raw/') ? f.file.substring(4) : f.file,
                capturedAt:
                    DateTime.fromMillisecondsSinceEpoch(f.timestampMs),
                lightAzimuthDeg: f.lightAzimuthDeg,
                lightElevationDeg: f.lightElevationDeg,
                iso: f.iso,
                exposureUs: f.exposureUs,
                focusDistanceM: f.focusDistanceM,
              ))
          .toList(),
      scaleMmPerPixel: sc.scaleMmPerPixel,
      notes: sc.notes,
      location: sc.location,
    );
  }

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
  SidecarLocation? location;

  SidecarV1 toSidecar() => SidecarV1(
        sessionId: id,
        label: label,
        capturedAt: capturedAt.toUtc().toIso8601String(),
        deviceModel: deviceModel,
        scaleMmPerPixel: scaleMmPerPixel,
        notes: notes,
        location: location,
        frames: frames
            .map((f) => SidecarFrame(
                  file: 'raw/${f.filename}',
                  timestampMs: f.capturedAt.millisecondsSinceEpoch,
                  lightAzimuthDeg: f.lightAzimuthDeg,
                  lightElevationDeg: f.lightElevationDeg,
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
    this.lightAzimuthDeg,
    this.lightElevationDeg,
    this.iso,
    this.exposureUs,
    this.focusDistanceM,
  });

  /// File name within the session's `raw/` folder, e.g. `0001.jpg`.
  final String filename;
  final DateTime capturedAt;
  final double? lightAzimuthDeg;
  final double? lightElevationDeg;
  final int? iso;
  final int? exposureUs;
  final double? focusDistanceM;
}

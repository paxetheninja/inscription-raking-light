import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/sidecar/sidecar_schema.dart';

void main() {
  test('SidecarV1 round-trips through JSON', () {
    final original = SidecarV1(
      sessionId: 's_20260525T103045_4f2a',
      label: 'Weber_328',
      capturedAt: '2026-05-25T08:30:45Z',
      deviceModel: 'iPhone15,3',
      scaleMmPerPixel: 0.0421,
      notes: 'tripod, north light',
      frames: const [
        SidecarFrame(
          file: 'raw/0001.jpg',
          timestampMs: 1716640991123,
          iso: 100,
          exposureUs: 4000,
        ),
        SidecarFrame(
          file: 'raw/0002.jpg',
          timestampMs: 1716640992200,
          lightAzimuthDeg: 312.5,
          lightElevationDeg: 18.0,
        ),
      ],
    );

    final json = original.toJson();
    expect(json['schema'], 'inscription-raking-light/sidecar@1');
    expect(json['label'], 'Weber_328');

    final restored = SidecarV1.fromJson(json);
    expect(restored.sessionId, original.sessionId);
    expect(restored.label, original.label);
    expect(restored.capturedAt, original.capturedAt);
    expect(restored.deviceModel, original.deviceModel);
    expect(restored.scaleMmPerPixel, original.scaleMmPerPixel);
    expect(restored.notes, original.notes);
    expect(restored.frames.length, 2);
    expect(restored.frames[0].iso, 100);
    expect(restored.frames[1].lightAzimuthDeg, 312.5);
  });

  test('Optional fields are omitted from JSON when null', () {
    final s = SidecarV1(
      sessionId: 's_x',
      label: '',
      capturedAt: '2026-05-25T00:00:00Z',
      deviceModel: 'test',
      frames: const [],
    );
    final j = s.toJson();
    expect(j.containsKey('scale_mm_per_pixel'), isFalse);
    expect(j.containsKey('notes'), isFalse);
  });
}

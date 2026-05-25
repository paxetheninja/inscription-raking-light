import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/photometric_stereo.dart';

void main() {
  group('LightVec.fromCompass', () {
    test('north + horizon → (0, -1, 0)', () {
      final v = LightVec.fromCompass(0, 0);
      expect(v.x, closeTo(0, 1e-9));
      expect(v.y, closeTo(-1, 1e-9));
      expect(v.z, closeTo(0, 1e-9));
    });

    test('east + horizon → (1, 0, 0)', () {
      final v = LightVec.fromCompass(90, 0);
      expect(v.x, closeTo(1, 1e-9));
      expect(v.y, closeTo(0, 1e-9));
      expect(v.z, closeTo(0, 1e-9));
    });

    test('zenith → (0, 0, 1)', () {
      final v = LightVec.fromCompass(0, 90);
      expect(v.x, closeTo(0, 1e-9));
      expect(v.y, closeTo(0, 1e-9));
      expect(v.z, closeTo(1, 1e-9));
    });
  });

  group('photometricStereoNormalMap', () {
    test('forward-facing flat surface → (128, 128, 255)', () {
      // Lights along the x, y, z axes; intensities consistent with N=(0,0,1).
      final lights = const [
        LightVec(1, 0, 0),
        LightVec(0, 1, 0),
        LightVec(0, 0, 1),
      ];
      final f0 = Uint8List.fromList([0]); // L0 · N = 0
      final f1 = Uint8List.fromList([0]);
      final f2 = Uint8List.fromList([255]); // L2 · N = 1

      final rgb = photometricStereoNormalMap(PhotometricStereoInput(
        width: 1,
        height: 1,
        frames: [f0, f1, f2],
        lights: lights,
      ));
      expect(rgb, hasLength(3));
      expect(rgb[0], 128);
      expect(rgb[1], 128);
      expect(rgb[2], 255);
    });

    test('normal pointing along +x → (255, 128, 128)', () {
      final lights = const [
        LightVec(1, 0, 0),
        LightVec(0, 1, 0),
        LightVec(0, 0, 1),
      ];
      final f0 = Uint8List.fromList([255]);
      final f1 = Uint8List.fromList([0]);
      final f2 = Uint8List.fromList([0]);
      final rgb = photometricStereoNormalMap(PhotometricStereoInput(
        width: 1,
        height: 1,
        frames: [f0, f1, f2],
        lights: lights,
      ));
      expect(rgb[0], 255);
      expect(rgb[1], 128);
      expect(rgb[2], 128);
    });

    test('coplanar light directions throw', () {
      // All in the xy plane (z = 0) → cannot resolve z component of normal.
      final lights = const [
        LightVec(1, 0, 0),
        LightVec(0, 1, 0),
        LightVec(-1, 0, 0),
      ];
      expect(
        () => photometricStereoNormalMap(PhotometricStereoInput(
          width: 1,
          height: 1,
          frames: [Uint8List(1), Uint8List(1), Uint8List(1)],
          lights: lights,
        )),
        throwsStateError,
      );
    });

    test('fewer than three frames throws', () {
      expect(
        () => photometricStereoNormalMap(PhotometricStereoInput(
          width: 1,
          height: 1,
          frames: [Uint8List(1), Uint8List(1)],
          lights: const [LightVec(1, 0, 0), LightVec(0, 1, 0)],
        )),
        throwsArgumentError,
      );
    });
  });
}

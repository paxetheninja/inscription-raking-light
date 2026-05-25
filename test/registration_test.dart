import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/registration.dart';

Uint8List _randomImage(int w, int h, int seed) {
  final r = math.Random(seed);
  final out = Uint8List(w * h);
  for (var i = 0; i < out.length; i++) {
    out[i] = r.nextInt(256);
  }
  return out;
}

/// Build a copy of [src] (sized w×h) shifted by (sx, sy) — feature at
/// `src(x, y)` ends up at `out(x + sx, y + sy)`. Out-of-bounds becomes 0.
Uint8List _shifted(Uint8List src, int w, int h, int sx, int sy) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final ox = x - sx;
      final oy = y - sy;
      if (ox >= 0 && oy >= 0 && ox < w && oy < h) {
        out[y * w + x] = src[oy * w + ox];
      }
    }
  }
  return out;
}

void main() {
  group('registerStack', () {
    test('empty frames throws', () {
      expect(
        () => registerStack(const RegistrationInput(
          width: 4,
          height: 4,
          frames: [],
          mode: RegistrationMode.fast,
        )),
        throwsArgumentError,
      );
    });

    test('ORB mode throws UnimplementedError', () {
      final f = Uint8List(16);
      expect(
        () => registerStack(RegistrationInput(
          width: 4,
          height: 4,
          frames: [f, f],
          mode: RegistrationMode.orb,
        )),
        throwsUnimplementedError,
      );
    });

    test('None mode passes frames through with identity transforms', () {
      final a = Uint8List(16);
      final b = Uint8List(16);
      final result = registerStack(RegistrationInput(
        width: 4,
        height: 4,
        frames: [a, b],
        mode: RegistrationMode.none,
      ));
      expect(result.transforms, hasLength(2));
      expect(result.transforms[0].isIdentity, isTrue);
      expect(result.transforms[1].isIdentity, isTrue);
      expect(result.validRect.width, 4);
      expect(result.validRect.height, 4);
      expect(identical(result.warpedFrames[0], a), isTrue);
    });

    test('Fast mode recovers a known translation', () {
      final ref = _randomImage(128, 128, 42);
      // shifted: same content as ref, but moved (+3, +2) on the canvas.
      // With our convention, the recovered transform should be tx ≈ -3, ty ≈ -2.
      final shifted = _shifted(ref, 128, 128, 3, 2);

      final result = registerStack(RegistrationInput(
        width: 128,
        height: 128,
        frames: [ref, shifted],
        mode: RegistrationMode.fast,
      ));

      expect(result.transforms[0].isIdentity, isTrue);
      expect(result.transforms[1].tx, closeTo(-3, 0.6));
      expect(result.transforms[1].ty, closeTo(-2, 0.6));
      expect(result.scores[1], greaterThan(0.95));
    });

    test('Fast mode crops the valid region', () {
      final ref = _randomImage(128, 128, 1);
      final shifted = _shifted(ref, 128, 128, 5, 0);
      final result = registerStack(RegistrationInput(
        width: 128,
        height: 128,
        frames: [ref, shifted],
        mode: RegistrationMode.fast,
      ));
      // Convention: x-shift of +5 in the source means tx ≈ -5; the valid x
      // range in reference coords is [0, 128 + (-5)) = [0, 123).
      expect(result.validRect.width, lessThanOrEqualTo(128));
      expect(result.validRect.width, greaterThanOrEqualTo(120));
      expect(result.validRect.height, 128);
    });
  });

  group('FrameTransform serialisation', () {
    test('round-trips through JSON', () {
      const t = FrameTransform(
          tx: 1.5, ty: -2.25, rotationRad: 0.03, scale: 1.01);
      final j = t.toJson();
      final back = FrameTransform.fromJson(j);
      expect(back.tx, t.tx);
      expect(back.ty, t.ty);
      expect(back.rotationRad, t.rotationRad);
      expect(back.scale, t.scale);
    });

    test('identity is identity', () {
      expect(FrameTransform.identity.isIdentity, isTrue);
      expect(const FrameTransform(tx: 0.01).isIdentity, isFalse);
    });
  });
}

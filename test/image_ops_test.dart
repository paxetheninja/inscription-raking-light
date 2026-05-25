import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/clahe.dart';
import 'package:inscription_raking_light/core/image_ops/fusion.dart';
import 'package:inscription_raking_light/core/image_ops/retinex.dart';

void main() {
  group('clahe', () {
    test('preserves dimensions and stays in [0,255]', () {
      final src = Uint8List(64 * 32);
      for (var i = 0; i < src.length; i++) {
        src[i] = (i * 13 + 7) & 0xff; // pseudo-random pattern
      }
      final out = clahe(src, 64, 32, tilesX: 4, tilesY: 2);
      expect(out.length, src.length);
      for (final v in out) {
        expect(v, inInclusiveRange(0, 255));
      }
    });

    test('uniform input maps to uniform output', () {
      final src = Uint8List(32 * 32);
      for (var i = 0; i < src.length; i++) {
        src[i] = 100;
      }
      final out = clahe(src, 32, 32, tilesX: 4, tilesY: 4);
      for (final v in out) {
        expect(v, equals(out[0]));
      }
    });

    test('rejects mismatched lengths', () {
      expect(
        () => clahe(Uint8List(10), 4, 4),
        throwsArgumentError,
      );
    });
  });

  group('multiScaleRetinex', () {
    test('preserves dimensions and stays in [0,255]', () {
      final src = Uint8List(64 * 32);
      for (var i = 0; i < src.length; i++) {
        src[i] = ((i * 7) ^ (i >> 3)) & 0xff;
      }
      final out = multiScaleRetinex(src, 64, 32, sigmas: const [2, 8]);
      expect(out.length, src.length);
      for (final v in out) {
        expect(v, inInclusiveRange(0, 255));
      }
    });

    test('uniform input → uniform output (zeroed by stretch)', () {
      final src = Uint8List(32 * 32);
      for (var i = 0; i < src.length; i++) {
        src[i] = 80;
      }
      final out = multiScaleRetinex(src, 32, 32, sigmas: const [2, 6]);
      for (final v in out) {
        expect(v, equals(out[0]));
      }
    });

    test('empty sigmas throws', () {
      expect(
        () => multiScaleRetinex(Uint8List(4), 2, 2, sigmas: const []),
        throwsArgumentError,
      );
    });
  });

  group('exposureFusion', () {
    test('single frame is returned unchanged', () {
      final f = Uint8List.fromList([10, 50, 200, 250]);
      final out = exposureFusion([f], 2, 2);
      expect(out, equals(f));
    });

    test('two identical frames return the same image', () {
      final f = Uint8List.fromList([10, 50, 200, 250]);
      final out = exposureFusion([f, f], 2, 2);
      expect(out, equals(f));
    });

    test('frames of mismatched length throw', () {
      expect(
        () => exposureFusion([Uint8List(4), Uint8List(3)], 2, 2),
        throwsArgumentError,
      );
    });

    test('empty stack throws', () {
      expect(
        () => exposureFusion(const [], 2, 2),
        throwsArgumentError,
      );
    });
  });
}

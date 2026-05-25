import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/pca.dart';

void main() {
  group('symmetricEigenDecomposition', () {
    test('diagonal matrix returns its diagonal sorted descending', () {
      final A = [
        Float64List.fromList([5, 0, 0]),
        Float64List.fromList([0, 1, 0]),
        Float64List.fromList([0, 0, 3]),
      ];
      final (vectors, values) = symmetricEigenDecomposition(A);
      expect(values[0], closeTo(5, 1e-9));
      expect(values[1], closeTo(3, 1e-9));
      expect(values[2], closeTo(1, 1e-9));
      // Top eigenvector points along the axis with the largest diagonal.
      expect(vectors[0][0].abs(), closeTo(1, 1e-9));
      expect(vectors[0][1].abs(), closeTo(0, 1e-9));
      expect(vectors[0][2].abs(), closeTo(0, 1e-9));
    });

    test('reconstructs a known 2×2 symmetric matrix', () {
      // A = [[2, 1], [1, 2]] has eigenvalues 3 and 1.
      final A = [
        Float64List.fromList([2, 1]),
        Float64List.fromList([1, 2]),
      ];
      final (_, values) = symmetricEigenDecomposition(A);
      expect(values[0], closeTo(3, 1e-9));
      expect(values[1], closeTo(1, 1e-9));
    });
  });

  group('computePcaLayers', () {
    test('two-frame stack with a strong "all-on / all-off" mode', () {
      // 4×4 image. Frame A is constant 0, frame B is constant 200.
      // The variation between frames is entirely in PC1 (the "brightness flip").
      const w = 4;
      const h = 4;
      final a = Uint8List(w * h);
      final b = Uint8List(w * h)..fillRange(0, w * h, 200);
      final pca = computePcaLayers([a, b], w, h, nComponents: 2);

      expect(pca.components, hasLength(2));
      // First eigenvalue should dominate by a large factor since all variance
      // is along this one mode.
      expect(pca.eigenvalues[0], greaterThan(1.0));
    });

    test('rejects single-frame and mismatched-length inputs', () {
      expect(
        () => computePcaLayers([Uint8List(4)], 2, 2),
        throwsArgumentError,
      );
      expect(
        () => computePcaLayers([Uint8List(4), Uint8List(3)], 2, 2),
        throwsArgumentError,
      );
    });

    test('output components have the right size and value range', () {
      const w = 8;
      const h = 8;
      final rand = math.Random(7);
      final frames = List<Uint8List>.generate(5, (_) {
        final f = Uint8List(w * h);
        for (var i = 0; i < f.length; i++) {
          f[i] = rand.nextInt(256);
        }
        return f;
      });
      final pca = computePcaLayers(frames, w, h, nComponents: 3);
      expect(pca.components, hasLength(3));
      for (final c in pca.components) {
        expect(c.length, w * h);
        for (final v in c) {
          expect(v, inInclusiveRange(0, 255));
        }
      }
    });
  });
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inscription_raking_light/core/image_ops/dog.dart';

Uint8List _gaussianBlob(int w, int h, double cx, double cy, double sigma) {
  final out = Uint8List(w * h);
  final twoSigSq = 2 * sigma * sigma;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x - cx;
      final dy = y - cy;
      final v = 255 * math.exp(-(dx * dx + dy * dy) / twoSigSq);
      out[y * w + x] = v.round().clamp(0, 255);
    }
  }
  return out;
}

void main() {
  test('DoG on a constant image is zero', () {
    final src = Uint8List(64 * 64)..fillRange(0, 64 * 64, 100);
    final out = differenceOfGaussians(src, 64, 64, sigma1: 1, sigma2: 3);
    expect(out, hasLength(64 * 64));
    for (final v in out) {
      expect(v, lessThan(2));
    }
  });

  test('multi-scale DoG peaks near the centre of a Gaussian blob', () {
    const w = 64;
    const h = 64;
    final src = _gaussianBlob(w, h, w / 2, h / 2, 4);
    final out = multiScaleDog(src, w, h);
    // Find the index of the max response — should be near the centre.
    var best = 0;
    var bestIdx = 0;
    for (var i = 0; i < out.length; i++) {
      if (out[i] > best) {
        best = out[i];
        bestIdx = i;
      }
    }
    final by = bestIdx ~/ w;
    final bx = bestIdx % w;
    // Allow some slack: DoG peaks ring around the blob, not at the exact centre.
    expect((bx - w / 2).abs(), lessThan(w / 3));
    expect((by - h / 2).abs(), lessThan(h / 3));
    expect(best, greaterThan(200)); // CLAHE'd image should saturate near peak
  });

  test('multi-scale DoG rejects mismatched input length', () {
    expect(
      () => multiScaleDog(Uint8List(10), 4, 4),
      throwsArgumentError,
    );
  });

  test('multi-scale DoG rejects empty scales', () {
    expect(
      () => multiScaleDog(Uint8List(16), 4, 4, scales: const []),
      throwsArgumentError,
    );
  });
}

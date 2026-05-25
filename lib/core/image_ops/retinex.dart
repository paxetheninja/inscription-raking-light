import 'dart:math' as math;
import 'dart:typed_data';

import 'gaussian.dart';

/// Multi-Scale Retinex with linear stretch back to uint8 (MSR, Jobson et al.).
///
/// For each scale σ, compute  log(I + 1) − log(blur_σ(I) + 1). Average over
/// scales, then linearly stretch the [p1, p99] percentile range to [0, 255]
/// so the result is comparable to a normalised LDR image.
Uint8List multiScaleRetinex(
  Uint8List src,
  int width,
  int height, {
  List<double> sigmas = const [3, 12, 40],
}) {
  if (sigmas.isEmpty) {
    throw ArgumentError('sigmas must be non-empty');
  }
  if (src.length != width * height) {
    throw ArgumentError('src length ${src.length} != $width * $height');
  }
  final n = src.length;

  final fsrc = Float64List(n);
  final logSrc = Float64List(n);
  for (var i = 0; i < n; i++) {
    fsrc[i] = src[i].toDouble();
    logSrc[i] = math.log(src[i] + 1.0);
  }

  final acc = Float64List(n);
  for (final sigma in sigmas) {
    final blurred = gaussianBlurFloat(fsrc, width, height, sigma);
    for (var i = 0; i < n; i++) {
      acc[i] += logSrc[i] - math.log(blurred[i] + 1.0);
    }
  }
  final invN = 1.0 / sigmas.length;
  for (var i = 0; i < n; i++) {
    acc[i] *= invN;
  }

  // Percentile stretch.
  final lo = _percentile(acc, 0.01);
  final hi = _percentile(acc, 0.99);
  final out = Uint8List(n);
  if ((hi - lo).abs() < 1e-9) {
    return out; // all zeros, caller can decide
  }
  final scale = 255.0 / (hi - lo);
  for (var i = 0; i < n; i++) {
    final v = (acc[i] - lo) * scale;
    out[i] = v.round().clamp(0, 255);
  }
  return out;
}

double _percentile(Float64List src, double p) {
  final copy = Float64List.fromList(src)..sort();
  final idx = ((copy.length - 1) * p).round().clamp(0, copy.length - 1);
  return copy[idx];
}

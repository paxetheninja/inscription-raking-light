import 'dart:typed_data';

import 'clahe.dart';
import 'gaussian.dart';

/// Difference of Gaussians: |G(I, σ₁) − G(I, σ₂)| — a band-pass filter that
/// highlights features at a particular scale. For inscriptions, the relevant
/// "scale" is the typical groove width.
Uint8List differenceOfGaussians(
  Uint8List src,
  int width,
  int height, {
  required double sigma1,
  required double sigma2,
}) {
  if (src.length != width * height) {
    throw ArgumentError('src length ${src.length} != $width × $height.');
  }
  final blur1 = gaussianBlurF(src, width, height, sigma1);
  final blur2 = gaussianBlurF(src, width, height, sigma2);
  final out = Uint8List(src.length);
  var maxAbs = 0.0;
  final diffs = Float64List(src.length);
  for (var i = 0; i < src.length; i++) {
    final d = (blur1[i] - blur2[i]).abs();
    diffs[i] = d;
    if (d > maxAbs) maxAbs = d;
  }
  if (maxAbs < 1e-9) return out;
  final inv = 255.0 / maxAbs;
  for (var i = 0; i < src.length; i++) {
    out[i] = (diffs[i] * inv).round().clamp(0, 255);
  }
  return out;
}

/// Multi-scale DoG: take per-pixel max of |DoG| at several scale pairs.
/// Catches grooves of any width without picking a single tuning.
Uint8List multiScaleDog(
  Uint8List src,
  int width,
  int height, {
  List<(double, double)> scales = const [(1, 2), (2, 4), (3, 6), (4, 8)],
}) {
  if (scales.isEmpty) {
    throw ArgumentError('scales must be non-empty.');
  }
  if (src.length != width * height) {
    throw ArgumentError('src length ${src.length} != $width × $height.');
  }

  // For each scale pair we hold a Float64 magnitude image, then take a
  // running per-pixel max so we don't keep N intermediate Uint8 outputs.
  final maxResp = Float64List(src.length);
  for (final (s1, s2) in scales) {
    final blur1 = gaussianBlurF(src, width, height, s1);
    final blur2 = gaussianBlurF(src, width, height, s2);
    for (var i = 0; i < src.length; i++) {
      final v = (blur1[i] - blur2[i]).abs();
      if (v > maxResp[i]) maxResp[i] = v;
    }
  }

  // Normalise then CLAHE.
  var hi = 0.0;
  for (var i = 0; i < maxResp.length; i++) {
    if (maxResp[i] > hi) hi = maxResp[i];
  }
  final out = Uint8List(src.length);
  if (hi < 1e-9) return out;
  final inv = 255.0 / hi;
  for (var i = 0; i < src.length; i++) {
    out[i] = (maxResp[i] * inv).round().clamp(0, 255);
  }
  return clahe(out, width, height);
}

import 'dart:math' as math;
import 'dart:typed_data';

/// Single-scale Mertens-style exposure fusion on a grayscale stack.
///
/// For each pixel, each frame contributes with weight
/// `contrast^wc * well_exposedness^we`, where:
///   - contrast = |Laplacian(I)|
///   - well_exposedness = Gaussian centred at 0.5 with σ = 0.2
/// The weights are then normalised across the stack and the output is the
/// weighted blend. No pyramid blending — at preview resolution the result
/// is clean enough that the simpler single-scale fusion gives the same
/// "best-detail-from-each-frame" effect users expect.
Uint8List exposureFusion(
  List<Uint8List> frames,
  int width,
  int height, {
  double contrastPower = 1.0,
  double exposurePower = 1.0,
}) {
  if (frames.isEmpty) {
    throw ArgumentError('frames must be non-empty');
  }
  final n = width * height;
  for (final f in frames) {
    if (f.length != n) {
      throw ArgumentError('frame length ${f.length} != $n');
    }
  }

  final weights = List.generate(frames.length, (_) => Float64List(n));
  for (var k = 0; k < frames.length; k++) {
    _frameWeights(
      frames[k],
      width,
      height,
      weights[k],
      contrastPower: contrastPower,
      exposurePower: exposurePower,
    );
  }

  final out = Uint8List(n);
  const eps = 1e-12;
  for (var i = 0; i < n; i++) {
    var sumW = 0.0;
    for (var k = 0; k < frames.length; k++) {
      sumW += weights[k][i];
    }
    if (sumW < eps) {
      // Degenerate: fall back to simple mean.
      var acc = 0.0;
      for (var k = 0; k < frames.length; k++) {
        acc += frames[k][i];
      }
      out[i] = (acc / frames.length).round().clamp(0, 255);
      continue;
    }
    var acc = 0.0;
    for (var k = 0; k < frames.length; k++) {
      acc += frames[k][i] * (weights[k][i] / sumW);
    }
    out[i] = acc.round().clamp(0, 255);
  }
  return out;
}

void _frameWeights(
  Uint8List src,
  int width,
  int height,
  Float64List out, {
  required double contrastPower,
  required double exposurePower,
}) {
  // Well-exposedness: Gaussian centred at 128, σ ≈ 51 (0.2 * 255).
  // Pre-compute LUT for speed.
  final expLut = Float64List(256);
  const sigma = 0.2 * 255.0;
  const twoSigSq = 2 * sigma * sigma;
  for (var v = 0; v < 256; v++) {
    final d = v - 128.0;
    expLut[v] = math.exp(-(d * d) / twoSigSq);
  }

  // |Laplacian| with a 3x3 [[0,1,0],[1,-4,1],[0,1,0]] kernel, edges clamped.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final c = src[y * width + x];
      final l = src[y * width + (x == 0 ? x : x - 1)];
      final r = src[y * width + (x == width - 1 ? x : x + 1)];
      final u = src[(y == 0 ? y : y - 1) * width + x];
      final d = src[(y == height - 1 ? y : y + 1) * width + x];
      final lap = (l + r + u + d - 4 * c).abs().toDouble();
      // Normalise contrast into roughly [0,1] for the power op.
      final contrast = lap / 510.0; // max |lap| ≈ 510 for 0..255 inputs
      final well = expLut[c];
      final w = math.pow(contrast + 1e-6, contrastPower).toDouble() *
          math.pow(well + 1e-6, exposurePower).toDouble();
      out[y * width + x] = w;
    }
  }
}

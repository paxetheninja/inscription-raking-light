import 'dart:math' as math;
import 'dart:typed_data';

/// Separable 1D Gaussian blur over a single-channel image. Operates in
/// floating point to preserve precision for downstream log / multi-scale work.
Float64List gaussianBlurF(Uint8List src, int width, int height, double sigma) {
  final fsrc = Float64List(src.length);
  for (var i = 0; i < src.length; i++) {
    fsrc[i] = src[i].toDouble();
  }
  return gaussianBlurFloat(fsrc, width, height, sigma);
}

/// Same as [gaussianBlurF] but takes a [Float64List] input (so callers can
/// chain multiple blurs without re-quantising to uint8 in between).
Float64List gaussianBlurFloat(
  Float64List src,
  int width,
  int height,
  double sigma,
) {
  if (sigma <= 0) return Float64List.fromList(src);
  final kernel = _gaussianKernel(sigma);
  final radius = kernel.length ~/ 2;

  final tmp = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    final yw = y * width;
    for (var x = 0; x < width; x++) {
      double sum = 0;
      for (var i = -radius; i <= radius; i++) {
        var xi = x + i;
        if (xi < 0) xi = 0;
        if (xi >= width) xi = width - 1;
        sum += src[yw + xi] * kernel[i + radius];
      }
      tmp[yw + x] = sum;
    }
  }

  final out = Float64List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      double sum = 0;
      for (var i = -radius; i <= radius; i++) {
        var yi = y + i;
        if (yi < 0) yi = 0;
        if (yi >= height) yi = height - 1;
        sum += tmp[yi * width + x] * kernel[i + radius];
      }
      out[y * width + x] = sum;
    }
  }
  return out;
}

List<double> _gaussianKernel(double sigma) {
  final radius = math.max(1, (3 * sigma).ceil());
  final size = 2 * radius + 1;
  final k = List<double>.filled(size, 0);
  final twoSigSq = 2 * sigma * sigma;
  var sum = 0.0;
  for (var i = -radius; i <= radius; i++) {
    final v = math.exp(-(i * i) / twoSigSq);
    k[i + radius] = v;
    sum += v;
  }
  for (var i = 0; i < size; i++) {
    k[i] /= sum;
  }
  return k;
}

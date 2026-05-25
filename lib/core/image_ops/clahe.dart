import 'dart:math' as math;
import 'dart:typed_data';

/// Contrast-Limited Adaptive Histogram Equalization on a grayscale image.
///
/// The image is divided into a grid of [tilesX] × [tilesY] tiles. A histogram
/// of each tile is clipped at `clipLimit * (pixelsPerTile / bins)`, the excess
/// is redistributed uniformly, and a CDF is built from the redistributed
/// histogram. The output pixel value is the bilinear interpolation between
/// the CDFs of the four nearest tile centers, which avoids the blocky
/// boundaries you'd get from per-tile equalisation alone.
Uint8List clahe(
  Uint8List src,
  int width,
  int height, {
  int tilesX = 8,
  int tilesY = 8,
  double clipLimit = 2.0,
}) {
  if (tilesX < 1 || tilesY < 1) {
    throw ArgumentError('tilesX and tilesY must be >= 1');
  }
  if (src.length != width * height) {
    throw ArgumentError('src length ${src.length} != $width * $height');
  }
  const bins = 256;

  // Build per-tile CDFs.
  final cdfs = List.generate(tilesX * tilesY, (_) => Uint8List(bins));
  final hist = Int32List(bins);
  for (var ty = 0; ty < tilesY; ty++) {
    final y0 = (ty * height) ~/ tilesY;
    final y1 = ((ty + 1) * height) ~/ tilesY;
    for (var tx = 0; tx < tilesX; tx++) {
      final x0 = (tx * width) ~/ tilesX;
      final x1 = ((tx + 1) * width) ~/ tilesX;
      final tileW = x1 - x0;
      final tileH = y1 - y0;
      final pixels = tileW * tileH;
      if (pixels == 0) continue;

      hist.fillRange(0, bins, 0);
      for (var y = y0; y < y1; y++) {
        final yw = y * width;
        for (var x = x0; x < x1; x++) {
          hist[src[yw + x]]++;
        }
      }

      // Clip and redistribute.
      final clip = math.max(1, (clipLimit * pixels / bins).round());
      var excess = 0;
      for (var b = 0; b < bins; b++) {
        if (hist[b] > clip) {
          excess += hist[b] - clip;
          hist[b] = clip;
        }
      }
      final perBin = excess ~/ bins;
      var rem = excess - perBin * bins;
      for (var b = 0; b < bins; b++) {
        hist[b] += perBin;
      }
      // Spread the remainder one bin at a time.
      var b = 0;
      while (rem > 0) {
        hist[b]++;
        rem--;
        b = (b + 1) % bins;
      }

      // Build the CDF (LUT) for this tile.
      final lut = cdfs[ty * tilesX + tx];
      var cum = 0;
      for (var i = 0; i < bins; i++) {
        cum += hist[i];
        // Scale to [0,255]; pixels is the tile size, so cum max = pixels.
        lut[i] = ((cum * 255) ~/ pixels).clamp(0, 255);
      }
    }
  }

  final tileW = width / tilesX;
  final tileH = height / tilesY;
  final out = Uint8List(width * height);

  for (var y = 0; y < height; y++) {
    // Y in "tile-center" coordinates.
    final fy = (y + 0.5) / tileH - 0.5;
    final ty0 = fy.floor().clamp(0, tilesY - 1);
    final ty1 = (ty0 + 1).clamp(0, tilesY - 1);
    final wy = (fy - ty0).clamp(0.0, 1.0);

    for (var x = 0; x < width; x++) {
      final fx = (x + 0.5) / tileW - 0.5;
      final tx0 = fx.floor().clamp(0, tilesX - 1);
      final tx1 = (tx0 + 1).clamp(0, tilesX - 1);
      final wx = (fx - tx0).clamp(0.0, 1.0);

      final v = src[y * width + x];
      final c00 = cdfs[ty0 * tilesX + tx0][v];
      final c01 = cdfs[ty0 * tilesX + tx1][v];
      final c10 = cdfs[ty1 * tilesX + tx0][v];
      final c11 = cdfs[ty1 * tilesX + tx1][v];

      final top = c00 * (1 - wx) + c01 * wx;
      final bot = c10 * (1 - wx) + c11 * wx;
      final val = top * (1 - wy) + bot * wy;
      out[y * width + x] = val.round().clamp(0, 255);
    }
  }

  return out;
}

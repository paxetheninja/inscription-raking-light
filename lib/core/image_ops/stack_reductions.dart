import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Per-pixel reductions across a stack of grayscale frames, all sharing the
/// same width and height.
class StackReductions {
  const StackReductions({
    required this.width,
    required this.height,
    required this.maxImg,
    required this.minImg,
    required this.rangeImg,
    required this.stddevImg,
  });

  final int width;
  final int height;
  final Uint8List maxImg;
  final Uint8List minImg;
  final Uint8List rangeImg;
  final Uint8List stddevImg;
}

/// Input bundle for [computeStackReductions]. Defined separately so it can be
/// sent across an isolate boundary.
class StackInput {
  const StackInput({
    required this.width,
    required this.height,
    required this.frames,
  });

  final int width;
  final int height;

  /// One Uint8List per frame, each of length width * height (grayscale).
  final List<Uint8List> frames;
}

/// Compute max / min / range / stddev across the stack on a background isolate.
Future<StackReductions> computeStackReductions(StackInput input) {
  return Isolate.run(() => computeStackReductionsSync(input));
}

/// Pure synchronous version, used in tests and from inside the isolate above.
StackReductions computeStackReductionsSync(StackInput input) {
  final n = input.frames.length;
  if (n == 0) {
    throw ArgumentError('frames must not be empty');
  }
  final w = input.width;
  final h = input.height;
  final pixCount = w * h;
  for (final f in input.frames) {
    if (f.length != pixCount) {
      throw ArgumentError(
          'frame length ${f.length} != expected $pixCount (${w}x$h)');
    }
  }

  final maxImg = Uint8List(pixCount);
  final minImg = Uint8List(pixCount);
  final rangeImg = Uint8List(pixCount);
  final stddevImg = Uint8List(pixCount);

  for (var i = 0; i < pixCount; i++) {
    var mn = 255;
    var mx = 0;
    var sum = 0;
    var sumSq = 0;
    for (var k = 0; k < n; k++) {
      final v = input.frames[k][i];
      if (v < mn) mn = v;
      if (v > mx) mx = v;
      sum += v;
      sumSq += v * v;
    }
    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    final stddev = variance > 0 ? math.sqrt(variance) : 0.0;

    maxImg[i] = mx;
    minImg[i] = mn;
    rangeImg[i] = mx - mn;
    stddevImg[i] = stddev.clamp(0, 255).toInt();
  }

  return StackReductions(
    width: w,
    height: h,
    maxImg: maxImg,
    minImg: minImg,
    rangeImg: rangeImg,
    stddevImg: stddevImg,
  );
}

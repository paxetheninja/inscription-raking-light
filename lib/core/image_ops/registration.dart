import 'dart:math' as math;
import 'dart:typed_data';

/// Which alignment algorithm the pipeline should run before stacking.
enum RegistrationMode {
  /// No registration — assume frames are already pixel-aligned.
  none,

  /// NCC pyramid, 2-DoF (translation only). Handles tripod bumps and small
  /// handheld jitter. Pure Dart, no native deps.
  fast,

  /// NCC pyramid + discrete rotation / scale grid search + sub-pixel
  /// translation refinement. 4-DoF (similarity). Handles handheld tilt and
  /// small zoom changes. Still pure Dart.
  accurate,

  /// ORB feature matching + RANSAC (planned for v0.9 via opencv_dart).
  orb,
}

/// Similarity transform that maps reference-frame coords to source-frame
/// coords. Convention: to warp `src` onto the reference, for each output
/// pixel `(x', y')` sample `src` at `inverse_transform(x', y')`.
class FrameTransform {
  const FrameTransform({
    this.tx = 0,
    this.ty = 0,
    this.rotationRad = 0,
    this.scale = 1,
  });

  static const identity = FrameTransform();

  final double tx;
  final double ty;
  final double rotationRad;
  final double scale;

  bool get isIdentity =>
      tx == 0 && ty == 0 && rotationRad == 0 && scale == 1;

  Map<String, dynamic> toJson() => {
        'tx': tx,
        'ty': ty,
        'rotation_rad': rotationRad,
        'scale': scale,
      };

  static FrameTransform fromJson(Map<String, dynamic> j) => FrameTransform(
        tx: (j['tx'] as num?)?.toDouble() ?? 0,
        ty: (j['ty'] as num?)?.toDouble() ?? 0,
        rotationRad: (j['rotation_rad'] as num?)?.toDouble() ?? 0,
        scale: (j['scale'] as num?)?.toDouble() ?? 1,
      );
}

/// Axis-aligned rectangle (half-open: x in [x0, x1), y in [y0, y1)) in the
/// reference frame's coordinate system.
class ValidRect {
  const ValidRect(this.x0, this.y0, this.x1, this.y1);

  final int x0;
  final int y0;
  final int x1;
  final int y1;

  int get width => x1 - x0;
  int get height => y1 - y0;

  Map<String, dynamic> toJson() => {
        'x0': x0,
        'y0': y0,
        'x1': x1,
        'y1': y1,
      };

  static ValidRect fromJson(Map<String, dynamic> j) => ValidRect(
        j['x0'] as int,
        j['y0'] as int,
        j['x1'] as int,
        j['y1'] as int,
      );
}

class RegistrationInput {
  const RegistrationInput({
    required this.width,
    required this.height,
    required this.frames,
    required this.mode,
  });

  final int width;
  final int height;
  final List<Uint8List> frames;
  final RegistrationMode mode;
}

class RegistrationResult {
  const RegistrationResult({
    required this.mode,
    required this.transforms,
    required this.validRect,
    required this.scores,
    required this.warpedFrames,
    this.note,
  });

  final RegistrationMode mode;

  /// One transform per input frame (transforms[0] is always identity).
  final List<FrameTransform> transforms;

  /// Common valid rectangle in reference-frame coords, after intersecting
  /// every frame's valid region post-warp.
  final ValidRect validRect;

  /// Per-frame final NCC score against the reference. Lets the UI flag
  /// frames whose alignment didn't converge.
  final List<double> scores;

  /// Each frame warped onto the reference and cropped to [validRect].
  /// Same length and stride conventions as the input frames.
  final List<Uint8List> warpedFrames;

  final String? note;
}

/// Top-level entry point. Picks the algorithm based on [input.mode] and
/// returns the warped frames + per-frame transforms.
RegistrationResult registerStack(RegistrationInput input) {
  if (input.frames.isEmpty) {
    throw ArgumentError('No frames to register.');
  }
  switch (input.mode) {
    case RegistrationMode.none:
      return _passthrough(input);
    case RegistrationMode.fast:
      return _registerTranslationOnly(input);
    case RegistrationMode.accurate:
      return _registerSimilarity(input);
    case RegistrationMode.orb:
      throw UnimplementedError(
          'ORB / OpenCV registration arrives in v0.9. Pick Fast or Accurate.');
  }
}

RegistrationResult _passthrough(RegistrationInput input) {
  return RegistrationResult(
    mode: RegistrationMode.none,
    transforms: List.filled(input.frames.length, FrameTransform.identity),
    validRect: ValidRect(0, 0, input.width, input.height),
    scores: List.filled(input.frames.length, 1.0),
    warpedFrames: input.frames,
  );
}

RegistrationResult _registerTranslationOnly(RegistrationInput input) {
  final ref = input.frames.first;
  final w = input.width;
  final h = input.height;
  final refPyramid = _buildPyramid(ref, w, h);
  final transforms = <FrameTransform>[FrameTransform.identity];
  final scores = <double>[1.0];

  for (var i = 1; i < input.frames.length; i++) {
    final framePyramid = _buildPyramid(input.frames[i], w, h);
    final (dx, dy, score) = _pyramidNccTranslation(refPyramid, framePyramid);
    transforms.add(FrameTransform(tx: dx, ty: dy));
    scores.add(score);
  }

  return _bakeResult(input, transforms, scores);
}

RegistrationResult _registerSimilarity(RegistrationInput input) {
  final ref = input.frames.first;
  final w = input.width;
  final h = input.height;
  final refPyramid = _buildPyramid(ref, w, h);
  final transforms = <FrameTransform>[FrameTransform.identity];
  final scores = <double>[1.0];

  for (var i = 1; i < input.frames.length; i++) {
    final framePyramid = _buildPyramid(input.frames[i], w, h);
    final (dx, dy, _) = _pyramidNccTranslation(refPyramid, framePyramid);

    // Grid-search rotation + scale at the top pyramid level (~64 px).
    final refTop = refPyramid.last;
    final frameTop = framePyramid.last;
    final scale = w / refTop.width;
    var bestScore = -double.infinity;
    var bestRot = 0.0;
    var bestScl = 1.0;
    const rotSteps = [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0];
    const sclSteps = [0.97, 0.98, 0.99, 1.0, 1.01, 1.02, 1.03];
    for (final rotDeg in rotSteps) {
      for (final scl in sclSteps) {
        final txTop = dx / scale;
        final tyTop = dy / scale;
        final warped = _warpBilinear(
          src: frameTop.bytes,
          srcWidth: frameTop.width,
          srcHeight: frameTop.height,
          dstWidth: refTop.width,
          dstHeight: refTop.height,
          transform: FrameTransform(
            tx: txTop,
            ty: tyTop,
            rotationRad: rotDeg * math.pi / 180.0,
            scale: scl,
          ),
        );
        final s = _ncc(refTop.bytes, warped, refTop.width, refTop.height);
        if (s > bestScore) {
          bestScore = s;
          bestRot = rotDeg * math.pi / 180.0;
          bestScl = scl;
        }
      }
    }

    // Refine translation at full resolution given (rot, scale) above.
    final (rdx, rdy, finalScore) = _localNccTranslation(
      ref,
      input.frames[i],
      w,
      h,
      rotationRad: bestRot,
      scale: bestScl,
      seedTx: dx,
      seedTy: dy,
      searchRadius: 4,
    );

    transforms.add(FrameTransform(
      tx: rdx,
      ty: rdy,
      rotationRad: bestRot,
      scale: bestScl,
    ));
    scores.add(finalScore);
  }

  return _bakeResult(input, transforms, scores);
}

RegistrationResult _bakeResult(
  RegistrationInput input,
  List<FrameTransform> transforms,
  List<double> scores,
) {
  final valid = _intersectValidRect(input.width, input.height, transforms);
  if (valid.width <= 0 || valid.height <= 0) {
    return RegistrationResult(
      mode: input.mode,
      transforms: transforms,
      validRect: ValidRect(0, 0, input.width, input.height),
      scores: scores,
      warpedFrames: input.frames,
      note: 'Registration produced an empty valid region — falling back to '
          'unwarped frames. Re-shoot with the camera held more stable.',
    );
  }

  final warped = <Uint8List>[];
  for (var i = 0; i < input.frames.length; i++) {
    warped.add(_warpAndCrop(
      input.frames[i],
      input.width,
      input.height,
      transforms[i],
      valid,
    ));
  }

  return RegistrationResult(
    mode: input.mode,
    transforms: transforms,
    validRect: valid,
    scores: scores,
    warpedFrames: warped,
  );
}

// ── Pyramid + NCC ───────────────────────────────────────────────────────────

class _PyramidLevel {
  const _PyramidLevel(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width;
  final int height;
}

List<_PyramidLevel> _buildPyramid(Uint8List src, int w, int h) {
  final levels = <_PyramidLevel>[_PyramidLevel(src, w, h)];
  var current = levels.first;
  while (math.min(current.width, current.height) > 64) {
    final nw = current.width ~/ 2;
    final nh = current.height ~/ 2;
    if (nw < 32 || nh < 32) break;
    final next = Uint8List(nw * nh);
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        final sx = x * 2;
        final sy = y * 2;
        final a = current.bytes[sy * current.width + sx];
        final b = current.bytes[sy * current.width + sx + 1];
        final c = current.bytes[(sy + 1) * current.width + sx];
        final d = current.bytes[(sy + 1) * current.width + sx + 1];
        next[y * nw + x] = ((a + b + c + d) >> 2);
      }
    }
    current = _PyramidLevel(next, nw, nh);
    levels.add(current);
  }
  return levels;
}

/// NCC pyramid translation: exhaustive search at the coarsest level
/// (±half the small edge), then refine by ±2 px at each finer level.
(double, double, double) _pyramidNccTranslation(
  List<_PyramidLevel> refPyr,
  List<_PyramidLevel> srcPyr,
) {
  final levels = math.min(refPyr.length, srcPyr.length);
  var dx = 0;
  var dy = 0;
  var bestScore = -double.infinity;

  // Coarsest level — wide exhaustive search.
  final top = levels - 1;
  final refTop = refPyr[top];
  final srcTop = srcPyr[top];
  final radius = math.min(refTop.width, refTop.height) ~/ 2;
  final searchTop = _nccSearch(
    refTop.bytes,
    srcTop.bytes,
    refTop.width,
    refTop.height,
    0,
    0,
    radius,
  );
  dx = searchTop.$1;
  dy = searchTop.$2;
  bestScore = searchTop.$3;

  // Finer levels — refine by ±2 px around the upsampled estimate.
  for (var L = top - 1; L >= 0; L--) {
    dx *= 2;
    dy *= 2;
    final refL = refPyr[L];
    final srcL = srcPyr[L];
    final ref = _nccSearch(
      refL.bytes,
      srcL.bytes,
      refL.width,
      refL.height,
      dx,
      dy,
      2,
    );
    dx = ref.$1;
    dy = ref.$2;
    bestScore = ref.$3;
  }

  // Sub-pixel quadratic refinement (parabola fit around the peak in x and y).
  final ref = refPyr.first;
  final src = srcPyr.first;
  final subDx = _subpixelPeak(ref.bytes, src.bytes, ref.width, ref.height,
      dx, dy, axisX: true);
  final subDy = _subpixelPeak(ref.bytes, src.bytes, ref.width, ref.height,
      dx, dy, axisX: false);

  return (dx + subDx, dy + subDy, bestScore);
}

/// Exhaustive ±[radius] NCC search around (cx, cy). Returns (dx, dy, score).
(int, int, double) _nccSearch(
  Uint8List ref,
  Uint8List src,
  int w,
  int h,
  int cx,
  int cy,
  int radius,
) {
  var bestScore = -double.infinity;
  var bestDx = cx;
  var bestDy = cy;
  for (var dy = cy - radius; dy <= cy + radius; dy++) {
    for (var dx = cx - radius; dx <= cx + radius; dx++) {
      final s = _nccTranslated(ref, src, w, h, dx, dy);
      if (s > bestScore) {
        bestScore = s;
        bestDx = dx;
        bestDy = dy;
      }
    }
  }
  return (bestDx, bestDy, bestScore);
}

double _subpixelPeak(
  Uint8List ref,
  Uint8List src,
  int w,
  int h,
  int cx,
  int cy, {
  required bool axisX,
}) {
  final centre = _nccTranslated(ref, src, w, h, cx, cy);
  final minus = axisX
      ? _nccTranslated(ref, src, w, h, cx - 1, cy)
      : _nccTranslated(ref, src, w, h, cx, cy - 1);
  final plus = axisX
      ? _nccTranslated(ref, src, w, h, cx + 1, cy)
      : _nccTranslated(ref, src, w, h, cx, cy + 1);
  final denom = 2 * (2 * centre - minus - plus);
  if (denom.abs() < 1e-9) return 0;
  final delta = (plus - minus) / denom;
  if (delta.abs() > 1) return 0; // numerical artefact, ignore
  return delta;
}

/// Local NCC translation refinement at full resolution with the source
/// pre-warped by [rotationRad] and [scale]. Used by the Accurate mode.
(double, double, double) _localNccTranslation(
  Uint8List ref,
  Uint8List src,
  int w,
  int h, {
  required double rotationRad,
  required double scale,
  required double seedTx,
  required double seedTy,
  required int searchRadius,
}) {
  // Pre-warp the source by (rot, scale) leaving translation at the seed.
  final warped = _warpBilinear(
    src: src,
    srcWidth: w,
    srcHeight: h,
    dstWidth: w,
    dstHeight: h,
    transform: FrameTransform(
      tx: seedTx,
      ty: seedTy,
      rotationRad: rotationRad,
      scale: scale,
    ),
  );
  // Now find the residual translation that maximises NCC against ref.
  final res = _nccSearch(ref, warped, w, h, 0, 0, searchRadius);
  final subDx = _subpixelPeak(ref, warped, w, h, res.$1, res.$2, axisX: true);
  final subDy = _subpixelPeak(ref, warped, w, h, res.$1, res.$2, axisX: false);
  return (
    seedTx + res.$1 + subDx,
    seedTy + res.$2 + subDy,
    res.$3,
  );
}

double _nccTranslated(
  Uint8List ref,
  Uint8List src,
  int w,
  int h,
  int dx,
  int dy,
) {
  final x0 = math.max(0, dx);
  final y0 = math.max(0, dy);
  final x1 = math.min(w, w + dx);
  final y1 = math.min(h, h + dy);
  if (x1 <= x0 || y1 <= y0) return -1;

  // Walking sums for zero-mean normalised cross correlation.
  var n = 0;
  var sumR = 0;
  var sumS = 0;
  var sumRR = 0;
  var sumSS = 0;
  var sumRS = 0;
  for (var y = y0; y < y1; y++) {
    final refRow = y * w;
    final srcRow = (y - dy) * w;
    for (var x = x0; x < x1; x++) {
      final r = ref[refRow + x];
      final s = src[srcRow + (x - dx)];
      sumR += r;
      sumS += s;
      sumRR += r * r;
      sumSS += s * s;
      sumRS += r * s;
      n++;
    }
  }
  if (n == 0) return -1;
  final meanR = sumR / n;
  final meanS = sumS / n;
  final num = sumRS - n * meanR * meanS;
  final denomR = sumRR - n * meanR * meanR;
  final denomS = sumSS - n * meanS * meanS;
  final denom = math.sqrt(denomR * denomS);
  if (denom < 1e-9) return -1;
  return num / denom;
}

double _ncc(Uint8List a, Uint8List b, int w, int h) {
  return _nccTranslated(a, b, w, h, 0, 0);
}

// ── Bilinear warp + valid-region computation ────────────────────────────────

Uint8List _warpBilinear({
  required Uint8List src,
  required int srcWidth,
  required int srcHeight,
  required int dstWidth,
  required int dstHeight,
  required FrameTransform transform,
}) {
  final out = Uint8List(dstWidth * dstHeight);
  final cosT = math.cos(transform.rotationRad);
  final sinT = math.sin(transform.rotationRad);
  final invScale = 1.0 / transform.scale;
  for (var y = 0; y < dstHeight; y++) {
    for (var x = 0; x < dstWidth; x++) {
      // Inverse transform: ref → src.
      final rx = x - transform.tx;
      final ry = y - transform.ty;
      final sx = (cosT * rx + sinT * ry) * invScale;
      final sy = (-sinT * rx + cosT * ry) * invScale;
      if (sx < 0 || sy < 0 || sx >= srcWidth - 1 || sy >= srcHeight - 1) {
        out[y * dstWidth + x] = 0;
        continue;
      }
      final x0 = sx.floor();
      final y0 = sy.floor();
      final fx = sx - x0;
      final fy = sy - y0;
      final a = src[y0 * srcWidth + x0];
      final b = src[y0 * srcWidth + x0 + 1];
      final c = src[(y0 + 1) * srcWidth + x0];
      final d = src[(y0 + 1) * srcWidth + x0 + 1];
      final top = a + (b - a) * fx;
      final bot = c + (d - c) * fx;
      final v = top + (bot - top) * fy;
      out[y * dstWidth + x] = v.round().clamp(0, 255);
    }
  }
  return out;
}

Uint8List _warpAndCrop(
  Uint8List src,
  int srcWidth,
  int srcHeight,
  FrameTransform transform,
  ValidRect rect,
) {
  if (transform.isIdentity &&
      rect.x0 == 0 &&
      rect.y0 == 0 &&
      rect.x1 == srcWidth &&
      rect.y1 == srcHeight) {
    return src;
  }
  final out = Uint8List(rect.width * rect.height);
  final cosT = math.cos(transform.rotationRad);
  final sinT = math.sin(transform.rotationRad);
  final invScale = 1.0 / transform.scale;
  for (var y = 0; y < rect.height; y++) {
    final refY = y + rect.y0;
    for (var x = 0; x < rect.width; x++) {
      final refX = x + rect.x0;
      final rx = refX - transform.tx;
      final ry = refY - transform.ty;
      final sx = (cosT * rx + sinT * ry) * invScale;
      final sy = (-sinT * rx + cosT * ry) * invScale;
      if (sx < 0 || sy < 0 || sx >= srcWidth - 1 || sy >= srcHeight - 1) {
        out[y * rect.width + x] = 0;
        continue;
      }
      final x0 = sx.floor();
      final y0 = sy.floor();
      final fx = sx - x0;
      final fy = sy - y0;
      final a = src[y0 * srcWidth + x0];
      final b = src[y0 * srcWidth + x0 + 1];
      final c = src[(y0 + 1) * srcWidth + x0];
      final d = src[(y0 + 1) * srcWidth + x0 + 1];
      final top = a + (b - a) * fx;
      final bot = c + (d - c) * fx;
      final v = top + (bot - top) * fy;
      out[y * rect.width + x] = v.round().clamp(0, 255);
    }
  }
  return out;
}

/// Intersection of every frame's valid region after warp. For translation
/// only this is exact; for similarity transforms we use the conservative
/// axis-aligned bounding box of the warped source rectangle's corners.
ValidRect _intersectValidRect(
  int w,
  int h,
  List<FrameTransform> transforms,
) {
  var x0 = 0;
  var y0 = 0;
  var x1 = w;
  var y1 = h;
  for (final t in transforms) {
    final corners = <(double, double)>[
      _applyForward(t, 0, 0),
      _applyForward(t, w.toDouble(), 0),
      _applyForward(t, 0, h.toDouble()),
      _applyForward(t, w.toDouble(), h.toDouble()),
    ];
    final minX = corners.map((c) => c.$1).reduce(math.min);
    final maxX = corners.map((c) => c.$1).reduce(math.max);
    final minY = corners.map((c) => c.$2).reduce(math.min);
    final maxY = corners.map((c) => c.$2).reduce(math.max);
    x0 = math.max(x0, minX.ceil());
    y0 = math.max(y0, minY.ceil());
    x1 = math.min(x1, maxX.floor());
    y1 = math.min(y1, maxY.floor());
  }
  return ValidRect(x0, y0, x1, y1);
}

(double, double) _applyForward(FrameTransform t, double sx, double sy) {
  // Forward map source-frame coord → reference-frame coord.
  // ref = R(θ) * scale * src + (tx, ty)
  final cosT = math.cos(t.rotationRad);
  final sinT = math.sin(t.rotationRad);
  final rx = t.scale * (cosT * sx - sinT * sy) + t.tx;
  final ry = t.scale * (sinT * sx + cosT * sy) + t.ty;
  return (rx, ry);
}

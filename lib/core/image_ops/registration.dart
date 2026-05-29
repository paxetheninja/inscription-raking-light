import 'dart:math' as math;
import 'dart:typed_data';

import 'clahe.dart';
import 'gaussian.dart';

/// Maximum translation accepted by the NCC alignment, as a fraction of the
/// reference dimensions. Recovered translations larger than this are treated
/// as bad matches (the NCC peak was noise, not signal) and replaced with
/// identity so the frame doesn't get warped halfway off-screen.
const double _maxTranslationFraction = 0.10;

/// Minimum NCC score for an alignment to be accepted. Below this the peak
/// isn't distinguishable from noise; fall back to identity for that frame.
///
/// Lower than a naive "0.5" because we run NCC on DoG-filtered band-pass
/// maps (see [_preprocessForAlignment]), whose signal energy is lower than
/// raw intensity images — the *correct* peaks land in the 0.4 – 0.7 range.
const double _minAcceptedNcc = 0.30;

/// Sigma pair for the alignment band-pass. The high-sigma blur estimates
/// the slowly-varying illumination component (which changes per-frame under
/// raking light), the low-sigma blur keeps fine structure; their difference
/// is the illumination-invariant edge map we actually compare.
const double _alignDogSigmaLow = 2.0;
const double _alignDogSigmaHigh = 8.0;

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
    this.precomputedTransforms,
    this.precomputedScores,
  });

  final int width;
  final int height;
  final List<Uint8List> frames;
  final RegistrationMode mode;

  /// Transforms computed on the main isolate (e.g. by ORB+RANSAC via
  /// opencv_dart) and passed through to the worker isolate. When non-null,
  /// [registerStack] skips the algorithm step and goes straight to baking
  /// warped+cropped frames. Length must equal [frames.length].
  final List<FrameTransform>? precomputedTransforms;
  final List<double>? precomputedScores;
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

  // Caller may have already computed transforms outside the worker isolate
  // (e.g. ORB via opencv_dart). Just bake them.
  final pre = input.precomputedTransforms;
  if (pre != null) {
    if (pre.length != input.frames.length) {
      throw ArgumentError(
        'precomputedTransforms length ${pre.length} != frames length '
        '${input.frames.length}.',
      );
    }
    final scores = input.precomputedScores ??
        List<double>.filled(pre.length, 1.0);
    return _bakeResult(input, pre, scores);
  }

  switch (input.mode) {
    case RegistrationMode.none:
      return _passthrough(input);
    case RegistrationMode.fast:
      return _registerTranslationOnly(input);
    case RegistrationMode.accurate:
      return _registerSimilarity(input);
    case RegistrationMode.orb:
      throw StateError(
        'ORB mode requires precomputed transforms — call '
        'computeOrbTransforms() on the main isolate first and pass the '
        'result via RegistrationInput.precomputedTransforms.',
      );
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
  final w = input.width;
  final h = input.height;
  // Preprocess every frame once for alignment scoring. The actual stack
  // downstream uses the original (un-preprocessed) frames. The preprocess
  // makes NCC illumination-invariant — critical for raking-light where the
  // bright/dark pattern flips with each light direction.
  final enhanced = input.frames
      .map((f) => _preprocessForAlignment(f, w, h))
      .toList();
  final refPyramid = _buildPyramid(enhanced.first, w, h);
  final transforms = <FrameTransform>[FrameTransform.identity];
  final scores = <double>[1.0];

  for (var i = 1; i < enhanced.length; i++) {
    final framePyramid = _buildPyramid(enhanced[i], w, h);
    final (dx, dy, score) = _pyramidNccTranslation(refPyramid, framePyramid);
    final (transform, acceptedScore) = _validateTranslation(dx, dy, score, w, h);
    transforms.add(transform);
    scores.add(acceptedScore);
  }

  return _bakeResult(input, transforms, scores);
}

/// Cap recovered translation to [_maxTranslationFraction] of dimensions and
/// require [_minAcceptedNcc] score. On failure, return identity with score 0.
(FrameTransform, double) _validateTranslation(
  double dx,
  double dy,
  double score,
  int w,
  int h,
) {
  final maxTx = w * _maxTranslationFraction;
  final maxTy = h * _maxTranslationFraction;
  if (dx.abs() > maxTx ||
      dy.abs() > maxTy ||
      score < _minAcceptedNcc) {
    return (FrameTransform.identity, score < 0 ? 0 : score);
  }
  return (FrameTransform(tx: dx, ty: dy), score);
}

/// Same validation for similarity transforms.
(FrameTransform, double) _validateSimilarity(
  double dx,
  double dy,
  double rotationRad,
  double scale,
  double score,
  int w,
  int h,
) {
  final maxTx = w * _maxTranslationFraction;
  final maxTy = h * _maxTranslationFraction;
  // Rotation and scale limits mirror the desktop pipeline's SIFT validation:
  // scale ∈ [0.95, 1.05], rotation < 2°. Outside these the grid search likely
  // latched onto a noise peak rather than the actual stone motion.
  final rotDegAbs = (rotationRad * 180.0 / math.pi).abs();
  if (dx.abs() > maxTx ||
      dy.abs() > maxTy ||
      rotDegAbs > 2.0 ||
      scale < 0.95 ||
      scale > 1.05 ||
      score < _minAcceptedNcc) {
    return (FrameTransform.identity, score < 0 ? 0 : score);
  }
  return (
    FrameTransform(
      tx: dx,
      ty: dy,
      rotationRad: rotationRad,
      scale: scale,
    ),
    score,
  );
}

RegistrationResult _registerSimilarity(RegistrationInput input) {
  final w = input.width;
  final h = input.height;
  // Preprocess for alignment estimation (originals are kept for the
  // downstream stack). See [_registerTranslationOnly] / [_preprocessForAlignment].
  final enhanced = input.frames
      .map((f) => _preprocessForAlignment(f, w, h))
      .toList();
  final ref = enhanced.first;
  final refPyramid = _buildPyramid(ref, w, h);
  final transforms = <FrameTransform>[FrameTransform.identity];
  final scores = <double>[1.0];

  for (var i = 1; i < enhanced.length; i++) {
    final framePyramid = _buildPyramid(enhanced[i], w, h);
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
      enhanced[i],
      w,
      h,
      rotationRad: bestRot,
      scale: bestScl,
      seedTx: dx,
      seedTy: dy,
      searchRadius: 4,
    );

    final (transform, acceptedScore) = _validateSimilarity(
      rdx,
      rdy,
      bestRot,
      bestScl,
      finalScore,
      w,
      h,
    );
    transforms.add(transform);
    scores.add(acceptedScore);
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
  // Track the maximum NCC across all levels rather than overwriting with
  // each finer level. Refinement at fine resolution can score lower than
  // the coarse-level match because per-pixel highlight detail (which moves
  // with the raking-light direction) starts dominating; we want to report
  // the highest-confidence measurement we found, not the noisiest one.
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
    if (ref.$3 > bestScore) bestScore = ref.$3;
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

/// Two-stage preprocess for the alignment pipeline:
///
///   1. CLAHE expands the narrow midtone histogram that weathered stone
///      occupies — gives both the DoG step and NCC more headroom.
///   2. Difference-of-Gaussians band-pass strips the slowly-varying
///      illumination (which changes per-frame as the light direction sweeps
///      around the stone) and keeps only the illumination-invariant edge
///      structure (groove shoulders, cracks, stone outline). Without this,
///      NCC sees the raking-light highlights as the dominant signal and
///      anti-correlates frames lit from opposite directions.
///
/// Returns a Uint8List in the same `width * height` layout, ready for the
/// existing pyramid + NCC machinery.
Uint8List _preprocessForAlignment(Uint8List src, int width, int height) {
  final clahed = clahe(
    src,
    width,
    height,
    tilesX: 8,
    tilesY: 8,
    clipLimit: 2.0,
  );
  // Inline DoG (we don't import dog.dart here to avoid a dependency cycle
  // — dog.dart depends on clahe.dart which is fine, but keeping registration
  // self-contained simplifies the build graph).
  final blurLow = gaussianBlurF(clahed, width, height, _alignDogSigmaLow);
  final blurHigh = gaussianBlurF(clahed, width, height, _alignDogSigmaHigh);
  final diffs = Float64List(clahed.length);
  var maxAbs = 0.0;
  for (var i = 0; i < clahed.length; i++) {
    final d = (blurLow[i] - blurHigh[i]).abs();
    diffs[i] = d;
    if (d > maxAbs) maxAbs = d;
  }
  final out = Uint8List(clahed.length);
  if (maxAbs < 1e-9) return out;
  final inv = 255.0 / maxAbs;
  for (var i = 0; i < clahed.length; i++) {
    out[i] = (diffs[i] * inv).round().clamp(0, 255);
  }
  return out;
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

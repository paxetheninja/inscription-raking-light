import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'clahe.dart';
import 'dog.dart';
import 'fusion.dart';
import 'pca.dart';
import 'photometric_stereo.dart';
import 'registration.dart';
import 'retinex.dart';

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
    this.lights,
    this.registrationMode = RegistrationMode.fast,
    this.precomputedTransforms,
    this.precomputedScores,
  });

  final int width;
  final int height;

  /// One Uint8List per frame, each of length width * height (grayscale).
  final List<Uint8List> frames;

  /// Optional per-frame light direction vectors (in image coords). When
  /// provided, the pipeline also computes a photometric-stereo normal map.
  final List<LightVec>? lights;

  /// Which registration algorithm to run before stacking. Defaults to
  /// [RegistrationMode.fast] (pyramid NCC translation).
  final RegistrationMode registrationMode;

  /// When non-null, the pipeline skips the registration algorithm and uses
  /// these transforms directly. Used to thread ORB+RANSAC results computed
  /// on the main isolate (via opencv_dart) into this worker.
  final List<FrameTransform>? precomputedTransforms;
  final List<double>? precomputedScores;
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

/// Full enhancement pipeline: reductions + Mertens-style fusion + CLAHE on the
/// fusion + multi-scale Retinex on the fusion. All seven outputs are computed
/// in a single background isolate to amortise the cost of copying frames.
class StackPipelineOutput {
  const StackPipelineOutput({
    required this.reductions,
    required this.fusion,
    required this.fusionClahe,
    required this.fusionRetinex,
    required this.combinedRelief,
    required this.multiscaleDog,
    required this.pcaComponents,
    required this.registration,
    this.normalMap,
    this.normalMapNote,
    this.blackHat,
  });

  final StackReductions reductions;
  final Uint8List fusion;
  final Uint8List fusionClahe;
  final Uint8List fusionRetinex;

  /// `clahe(stddev + (max − min) / 2)` — desktop pipeline's headline output
  /// for raking-light stacks when light directions are not known.
  final Uint8List combinedRelief;

  /// Multi-scale Difference of Gaussians applied to the fusion image. Each
  /// pixel is the max |G(σ₁) − G(σ₂)| across four scale pairs.
  final Uint8List multiscaleDog;

  /// Top-k principal components of the aligned stack, descending eigenvalue.
  /// `pcaComponents[1]` is typically the primary relief channel.
  final List<Uint8List> pcaComponents;

  /// Per-frame transforms + valid-region crop + alignment scores.
  final RegistrationResult registration;

  /// RGB normal map (length = width * height * 3) when photometric stereo
  /// could be computed. Null otherwise; see [normalMapNote] for why.
  final Uint8List? normalMap;

  /// Reason the normal map is absent — e.g. "Light directions are coplanar."
  final String? normalMapNote;

  /// Black-hat morphology applied to the fusion image. Computed on the
  /// main isolate (opencv_dart) and attached after the worker isolate
  /// completes — see [StackPipelineOutput.withBlackHat].
  final Uint8List? blackHat;

  int get width => reductions.width;
  int get height => reductions.height;

  StackPipelineOutput withBlackHat(Uint8List bytes) => StackPipelineOutput(
        reductions: reductions,
        fusion: fusion,
        fusionClahe: fusionClahe,
        fusionRetinex: fusionRetinex,
        combinedRelief: combinedRelief,
        multiscaleDog: multiscaleDog,
        pcaComponents: pcaComponents,
        registration: registration,
        normalMap: normalMap,
        normalMapNote: normalMapNote,
        blackHat: bytes,
      );
}

Future<StackPipelineOutput> runStackPipeline(StackInput input) {
  return Isolate.run(() => runStackPipelineSync(input));
}

StackPipelineOutput runStackPipelineSync(StackInput input) {
  // 1. Align all frames onto the reference (frame 0). The result is the
  //    warped + cropped frames plus per-frame transforms + a common valid
  //    rect in reference-frame coordinates.
  final registration = registerStack(RegistrationInput(
    width: input.width,
    height: input.height,
    frames: input.frames,
    mode: input.registrationMode,
    precomputedTransforms: input.precomputedTransforms,
    precomputedScores: input.precomputedScores,
  ));
  final alignedFrames = registration.warpedFrames;
  final w = registration.validRect.width;
  final h = registration.validRect.height;

  // 2. Run the existing reductions + enhancement pipeline on the aligned
  //    (and cropped) frames.
  final reductionInput = StackInput(
    width: w,
    height: h,
    frames: alignedFrames,
    lights: input.lights,
    registrationMode: RegistrationMode.none, // already done above
  );
  final reductions = computeStackReductionsSync(reductionInput);
  final fusion = exposureFusion(alignedFrames, w, h);
  final fusionClahe = clahe(fusion, w, h);
  // Chain CLAHE after Retinex (matches the desktop pipeline).
  final fusionRetinex =
      clahe(multiScaleRetinex(fusion, w, h), w, h);
  final combinedRelief = _computeCombinedRelief(reductions);
  final multiscaleDogOut = multiScaleDog(fusion, w, h);
  final pca = computePcaLayers(alignedFrames, w, h);

  Uint8List? normalMap;
  String? normalMapNote;
  final lights = input.lights;
  if (lights == null) {
    normalMapNote = 'Tag each frame with a light direction on the Capture tab '
        'to enable photometric-stereo normal-map estimation.';
  } else if (lights.length != alignedFrames.length) {
    normalMapNote = 'Light directions are only set on '
        '${lights.length}/${alignedFrames.length} frames — set them on all '
        'frames to compute the normal map.';
  } else if (alignedFrames.length < 3) {
    normalMapNote = 'Need ≥ 3 frames with light directions to compute a '
        'normal map (got ${alignedFrames.length}).';
  } else {
    try {
      normalMap = photometricStereoNormalMap(PhotometricStereoInput(
        width: w,
        height: h,
        frames: alignedFrames,
        lights: lights,
      ));
    } catch (e) {
      normalMapNote = '$e';
    }
  }

  return StackPipelineOutput(
    reductions: reductions,
    fusion: fusion,
    fusionClahe: fusionClahe,
    fusionRetinex: fusionRetinex,
    combinedRelief: combinedRelief,
    multiscaleDog: multiscaleDogOut,
    pcaComponents: pca.components,
    registration: registration,
    normalMap: normalMap,
    normalMapNote: normalMapNote,
  );
}

/// stddev + range/2, normalised then CLAHE'd. This is the desktop's
/// "primary relief proxy" output when light directions are unknown
/// (lib_enhance.py:378).
Uint8List _computeCombinedRelief(StackReductions r) {
  final n = r.maxImg.length;
  final raw = Float64List(n);
  var hi = 0.0;
  for (var i = 0; i < n; i++) {
    final v = r.stddevImg[i] + (r.maxImg[i] - r.minImg[i]) / 2.0;
    raw[i] = v;
    if (v > hi) hi = v;
  }
  final out = Uint8List(n);
  if (hi < 1e-9) return out;
  final inv = 255.0 / hi;
  for (var i = 0; i < n; i++) {
    out[i] = (raw[i] * inv).round().clamp(0, 255);
  }
  return clahe(out, r.width, r.height);
}

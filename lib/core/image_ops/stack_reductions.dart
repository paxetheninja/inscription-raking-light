import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'clahe.dart';
import 'fusion.dart';
import 'photometric_stereo.dart';
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
  });

  final int width;
  final int height;

  /// One Uint8List per frame, each of length width * height (grayscale).
  final List<Uint8List> frames;

  /// Optional per-frame light direction vectors (in image coords). When
  /// provided, the pipeline also computes a photometric-stereo normal map.
  final List<LightVec>? lights;
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
    this.normalMap,
    this.normalMapNote,
  });

  final StackReductions reductions;
  final Uint8List fusion;
  final Uint8List fusionClahe;
  final Uint8List fusionRetinex;

  /// RGB normal map (length = width * height * 3) when photometric stereo
  /// could be computed. Null otherwise; see [normalMapNote] for why.
  final Uint8List? normalMap;

  /// Reason the normal map is absent — e.g. "Light directions are coplanar."
  final String? normalMapNote;

  int get width => reductions.width;
  int get height => reductions.height;
}

Future<StackPipelineOutput> runStackPipeline(StackInput input) {
  return Isolate.run(() => runStackPipelineSync(input));
}

StackPipelineOutput runStackPipelineSync(StackInput input) {
  final reductions = computeStackReductionsSync(input);
  final fusion = exposureFusion(input.frames, input.width, input.height);
  final fusionClahe = clahe(fusion, input.width, input.height);
  final fusionRetinex = multiScaleRetinex(fusion, input.width, input.height);

  Uint8List? normalMap;
  String? normalMapNote;
  final lights = input.lights;
  if (lights == null) {
    normalMapNote = 'Tag each frame with a light direction on the Capture tab '
        'to enable photometric-stereo normal-map estimation.';
  } else if (lights.length != input.frames.length) {
    normalMapNote = 'Light directions are only set on '
        '${lights.length}/${input.frames.length} frames — set them on all '
        'frames to compute the normal map.';
  } else if (input.frames.length < 3) {
    normalMapNote = 'Need ≥ 3 frames with light directions to compute a '
        'normal map (got ${input.frames.length}).';
  } else {
    try {
      normalMap = photometricStereoNormalMap(PhotometricStereoInput(
        width: input.width,
        height: input.height,
        frames: input.frames,
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
    normalMap: normalMap,
    normalMapNote: normalMapNote,
  );
}

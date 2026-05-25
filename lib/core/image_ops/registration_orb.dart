import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'registration.dart';

/// Compute ORB + RANSAC similarity transforms for each non-reference frame.
///
/// Runs on the *main* isolate (not inside `Isolate.run`): opencv_dart wraps
/// native handles with finalizers that aren't safe to send across isolate
/// boundaries. The resulting [FrameTransform] list is plain Dart and is
/// safe to send into the worker isolate via `StackInput.precomputedTransforms`.
///
/// Falls back to identity-transform + score 0 for any frame where < 10 RANSAC
/// inliers are found; callers (the Stack screen) can show a warning when a
/// score is suspiciously low.
(List<FrameTransform>, List<double>) computeOrbTransforms(
  List<Uint8List> frames,
  int width,
  int height, {
  int maxFeatures = 1000,
  int minInliers = 10,
}) {
  if (frames.isEmpty) {
    throw ArgumentError('No frames to register.');
  }
  if (frames.length == 1) {
    return ([FrameTransform.identity], [1.0]);
  }

  final refMat = cv.Mat.fromList(
    height,
    width,
    cv.MatType.CV_8UC1,
    frames.first,
  );
  final orb = cv.ORB.create(nFeatures: maxFeatures);
  final (refKp, refDesc) = orb.detectAndCompute(refMat, cv.Mat.empty());

  final transforms = <FrameTransform>[FrameTransform.identity];
  final scores = <double>[1.0];

  for (var i = 1; i < frames.length; i++) {
    final srcMat = cv.Mat.fromList(
      height,
      width,
      cv.MatType.CV_8UC1,
      frames[i],
    );
    final (srcKp, srcDesc) = orb.detectAndCompute(srcMat, cv.Mat.empty());

    if (srcKp.length < minInliers || refKp.length < minInliers) {
      transforms.add(FrameTransform.identity);
      scores.add(0);
      srcMat.dispose();
      continue;
    }

    final bf = cv.BFMatcher.create(type: cv.NORM_HAMMING, crossCheck: true);
    final matches = bf.match(srcDesc, refDesc);

    if (matches.length < minInliers) {
      transforms.add(FrameTransform.identity);
      scores.add(0);
      srcMat.dispose();
      continue;
    }

    final srcPtsList = <cv.Point2f>[];
    final dstPtsList = <cv.Point2f>[];
    for (var j = 0; j < matches.length; j++) {
      final m = matches[j];
      final sk = srcKp[m.queryIdx];
      final rk = refKp[m.trainIdx];
      srcPtsList.add(cv.Point2f(sk.x, sk.y));
      dstPtsList.add(cv.Point2f(rk.x, rk.y));
    }
    final srcPts = cv.VecPoint2f.fromList(srcPtsList);
    final dstPts = cv.VecPoint2f.fromList(dstPtsList);

    final (matrix, inliers) = cv.estimateAffinePartial2D(
      srcPts,
      dstPts,
      method: cv.RANSAC,
    );

    // Count RANSAC inliers (the mask is N×1 of 0/1).
    var inlierCount = 0;
    for (var j = 0; j < matches.length; j++) {
      if (inliers.at<int>(j, 0) != 0) inlierCount++;
    }

    if (inlierCount < minInliers || matrix.isEmpty) {
      transforms.add(FrameTransform.identity);
      scores.add(0);
    } else {
      // OpenCV returns [[s·cosθ, −s·sinθ, tx], [s·sinθ, s·cosθ, ty]].
      final a = matrix.at<double>(0, 0);
      final b = matrix.at<double>(1, 0);
      final tx = matrix.at<double>(0, 2);
      final ty = matrix.at<double>(1, 2);
      final scale = math.sqrt(a * a + b * b);
      final rotation = math.atan2(b, a);
      transforms.add(FrameTransform(
        tx: tx,
        ty: ty,
        rotationRad: rotation,
        scale: scale,
      ));
      scores.add(inlierCount / matches.length);
    }

    srcMat.dispose();
  }

  refMat.dispose();
  orb.dispose();

  return (transforms, scores);
}

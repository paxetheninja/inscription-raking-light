import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Black hat morphology — explicitly extracts dark depressions from a
/// grayscale image. For a raking-lit inscription, the carved grooves are
/// darker than the surrounding lit surface, so black hat produces a clean
/// "letters only" image.
///
/// Formula: `closing(I, kernel) − I`, where closing is dilation followed
/// by erosion. With an elliptical kernel sized just larger than the typical
/// groove width, the closing fills the grooves with the surrounding stone
/// value; subtracting the original then leaves only the groove signal.
///
/// Must run on the **main isolate** — opencv_dart FFI handles aren't safe
/// to send across isolate boundaries.
Uint8List computeBlackHat(
  Uint8List src,
  int width,
  int height, {
  int kernelSize = 15,
}) {
  if (src.length != width * height) {
    throw ArgumentError('src length ${src.length} != $width × $height.');
  }
  final srcMat = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, src);
  final kernel = cv.getStructuringElement(
    cv.MORPH_ELLIPSE,
    (kernelSize, kernelSize),
  );
  final dst = cv.morphologyEx(srcMat, cv.MORPH_BLACKHAT, kernel);
  // Pull bytes back out into a Dart Uint8List.
  final bytes = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      bytes[y * width + x] = dst.at<int>(y, x);
    }
  }
  srcMat.dispose();
  kernel.dispose();
  dst.dispose();
  return bytes;
}

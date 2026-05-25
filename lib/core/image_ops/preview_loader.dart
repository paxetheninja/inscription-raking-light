import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A grayscale preview of a captured frame, downsampled so the longest edge
/// is `maxEdge` pixels.
class GrayPreview {
  const GrayPreview({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// One byte per pixel, row-major, length = width * height.
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Load a JPEG / PNG from [path], downsample to [maxEdge] on the long side,
/// and convert to luma (ITU-R BT.601 weights). Runs in an [Isolate] so the
/// UI thread stays free.
Future<GrayPreview> loadGrayPreview(String path, {int maxEdge = 1024}) {
  return Isolate.run(() => _loadGrayPreview(path, maxEdge));
}

/// Same as [loadGrayPreview] but synchronous — used in tests so we don't
/// need an isolate to validate the math.
GrayPreview loadGrayPreviewFromBytes(Uint8List raw, {int maxEdge = 1024}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw const FormatException('image decode failed');
  }
  return _toGray(decoded, maxEdge);
}

GrayPreview _loadGrayPreview(String path, int maxEdge) {
  final raw = File(path).readAsBytesSync();
  final decoded = img.decodeImage(raw);
  if (decoded == null) {
    throw FormatException('image decode failed: $path');
  }
  return _toGray(decoded, maxEdge);
}

GrayPreview _toGray(img.Image src, int maxEdge) {
  final longest = math.max(src.width, src.height);
  img.Image resized;
  if (longest > maxEdge) {
    final scale = maxEdge / longest;
    resized = img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  } else {
    resized = src;
  }

  final w = resized.width;
  final h = resized.height;
  final bytes = Uint8List(w * h);
  var i = 0;
  for (final p in resized) {
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    bytes[i++] = (299 * r + 587 * g + 114 * b) ~/ 1000;
  }
  return GrayPreview(bytes: bytes, width: w, height: h);
}

/// Encode a grayscale buffer as a PNG suitable for a `Image.memory` widget.
Uint8List grayToPng(Uint8List gray, int width, int height) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: gray.buffer,
    numChannels: 1,
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// Encode a row-major RGB buffer (length = width * height * 3) as a PNG.
Uint8List rgbToPng(Uint8List rgb, int width, int height) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  return Uint8List.fromList(img.encodePng(image));
}

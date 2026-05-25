import 'dart:math' as math;
import 'dart:typed_data';

/// Unit vector pointing from the stone surface towards the light source.
/// Coordinate frame matches the image:
///   x → right (image +x)
///   y → down  (image +y)
///   z → out of the stone surface, towards the camera
class LightVec {
  const LightVec(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  /// Convert the in-app compass picker values (azimuth 0°=N…clockwise,
  /// elevation 0°=stone-plane…90°=zenith) into a unit light vector in
  /// image coordinates. North in the compass picker maps to the image's
  /// "up" direction, which is −y.
  factory LightVec.fromCompass(double azimuthDeg, double elevationDeg) {
    final az = azimuthDeg * math.pi / 180.0;
    final el = elevationDeg * math.pi / 180.0;
    final cosEl = math.cos(el);
    return LightVec(
      cosEl * math.sin(az),
      -cosEl * math.cos(az),
      math.sin(el),
    );
  }
}

class PhotometricStereoInput {
  const PhotometricStereoInput({
    required this.width,
    required this.height,
    required this.frames,
    required this.lights,
  });

  final int width;
  final int height;
  final List<Uint8List> frames;
  final List<LightVec> lights;
}

/// Lambertian photometric stereo. Returns an RGB normal map encoded with
/// the standard `(n + 1) / 2` convention: a forward-facing flat surface is
/// approximately (128, 128, 255).
///
/// Throws if the light directions don't span 3D — the user needs at least
/// three frames with varying azimuth *and* a non-zero elevation.
Uint8List photometricStereoNormalMap(PhotometricStereoInput input) {
  final n = input.frames.length;
  if (n < 3) {
    throw ArgumentError('Need ≥ 3 frames for photometric stereo (got $n).');
  }
  if (input.lights.length != n) {
    throw ArgumentError(
        'lights length ${input.lights.length} != frames length $n.');
  }
  final pixCount = input.width * input.height;
  for (final f in input.frames) {
    if (f.length != pixCount) {
      throw ArgumentError(
          'frame length ${f.length} != ${input.width}*${input.height}.');
    }
  }

  // Build L^T L (symmetric 3x3). Stored as the 6 unique entries.
  var a00 = 0.0, a01 = 0.0, a02 = 0.0, a11 = 0.0, a12 = 0.0, a22 = 0.0;
  for (final L in input.lights) {
    a00 += L.x * L.x;
    a01 += L.x * L.y;
    a02 += L.x * L.z;
    a11 += L.y * L.y;
    a12 += L.y * L.z;
    a22 += L.z * L.z;
  }

  // 3x3 inverse via adjugate / determinant.
  final det = a00 * (a11 * a22 - a12 * a12) -
      a01 * (a01 * a22 - a12 * a02) +
      a02 * (a01 * a12 - a11 * a02);
  if (det.abs() < 1e-9) {
    throw StateError(
        'Light directions are coplanar. Vary the elevation across frames so '
        'they span 3D.');
  }
  final invDet = 1.0 / det;
  final m00 = (a11 * a22 - a12 * a12) * invDet;
  final m01 = (a02 * a12 - a01 * a22) * invDet;
  final m02 = (a01 * a12 - a11 * a02) * invDet;
  final m11 = (a00 * a22 - a02 * a02) * invDet;
  final m12 = (a01 * a02 - a00 * a12) * invDet;
  final m22 = (a00 * a11 - a01 * a01) * invDet;

  // Pre-flatten lights into parallel arrays for cache-friendly inner loop.
  final lx = Float64List(n);
  final ly = Float64List(n);
  final lz = Float64List(n);
  for (var k = 0; k < n; k++) {
    lx[k] = input.lights[k].x;
    ly[k] = input.lights[k].y;
    lz[k] = input.lights[k].z;
  }

  final rgb = Uint8List(pixCount * 3);
  for (var p = 0; p < pixCount; p++) {
    var bx = 0.0;
    var by = 0.0;
    var bz = 0.0;
    for (var k = 0; k < n; k++) {
      final I = input.frames[k][p] / 255.0;
      bx += lx[k] * I;
      by += ly[k] * I;
      bz += lz[k] * I;
    }
    // v = M_inv * b  (M_inv is symmetric).
    final vx = m00 * bx + m01 * by + m02 * bz;
    final vy = m01 * bx + m11 * by + m12 * bz;
    final vz = m02 * bx + m12 * by + m22 * bz;
    final norm = math.sqrt(vx * vx + vy * vy + vz * vz);
    final i3 = p * 3;
    if (norm < 1e-9) {
      // Black pixel everywhere → no information. Encode as flat normal.
      rgb[i3] = 128;
      rgb[i3 + 1] = 128;
      rgb[i3 + 2] = 255;
      continue;
    }
    final nx = vx / norm;
    final ny = vy / norm;
    final nz = vz / norm;
    rgb[i3] = ((nx + 1.0) * 127.5).round().clamp(0, 255);
    rgb[i3 + 1] = ((ny + 1.0) * 127.5).round().clamp(0, 255);
    rgb[i3 + 2] = ((nz + 1.0) * 127.5).round().clamp(0, 255);
  }
  return rgb;
}

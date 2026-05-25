import 'dart:math' as math;
import 'dart:typed_data';

import 'clahe.dart';

/// PCA on a stack of grayscale frames. The first 3-4 principal components
/// usually carry: PC1 ≈ average illumination, **PC2 ≈ primary relief
/// channel**, PC3 / PC4 = finer texture or noise modes.
///
/// Implementation uses the covariance trick: build the N×N matrix
/// `C = X · Xᵀ / P` (N = number of frames, P = pixel count) and eigen-
/// decompose it. The (N×N) decomposition is microseconds — much faster
/// than the (P×P) approach.
class PcaOutput {
  const PcaOutput({
    required this.components,
    required this.eigenvalues,
    required this.width,
    required this.height,
  });

  /// Top-k components as CLAHE'd uint8 images (index 0 = PC1, 1 = PC2, …).
  final List<Uint8List> components;

  /// Eigenvalues of the top-k components, descending.
  final Float64List eigenvalues;

  final int width;
  final int height;
}

PcaOutput computePcaLayers(
  List<Uint8List> frames,
  int width,
  int height, {
  int nComponents = 4,
}) {
  if (frames.isEmpty) {
    throw ArgumentError('No frames for PCA.');
  }
  final n = frames.length;
  final p = width * height;
  if (n < 2) {
    throw ArgumentError('PCA needs at least 2 frames (got $n).');
  }
  for (final f in frames) {
    if (f.length != p) {
      throw ArgumentError(
          'frame length ${f.length} != $width × $height = $p.');
    }
  }
  final k = math.min(nComponents, n);

  // 1. Mean across frames (per-pixel).
  final mean = Float64List(p);
  for (final f in frames) {
    for (var i = 0; i < p; i++) {
      mean[i] += f[i];
    }
  }
  for (var i = 0; i < p; i++) {
    mean[i] /= n;
  }

  // 2. Mean-subtracted rows in float32 (saves ~half the RAM vs float64).
  final rows = List<Float32List>.generate(n, (rowIdx) {
    final row = Float32List(p);
    final f = frames[rowIdx];
    for (var i = 0; i < p; i++) {
      row[i] = f[i] - mean[i];
    }
    return row;
  });

  // 3. N×N covariance matrix C[i][j] = (rowᵢ · rowⱼ) / P.
  //    Symmetric, only fill the upper triangle and mirror.
  final C = List.generate(n, (_) => Float64List(n));
  for (var i = 0; i < n; i++) {
    final ri = rows[i];
    for (var j = i; j < n; j++) {
      final rj = rows[j];
      var sum = 0.0;
      for (var x = 0; x < p; x++) {
        sum += ri[x] * rj[x];
      }
      sum /= p;
      C[i][j] = sum;
      C[j][i] = sum;
    }
  }

  // 4. Eigendecomposition of C → eigenvectors sorted descending by eigenvalue.
  final (eigenvectors, eigenvalues) = symmetricEigenDecomposition(C);

  // 5. Each top-k spatial component PCₖ(pixel) = Σᵢ eigenvectorsₖ[i] · rowsᵢ[pixel].
  final components = <Uint8List>[];
  for (var ci = 0; ci < k; ci++) {
    final ev = eigenvectors[ci];
    final pc = Float64List(p);
    for (var i = 0; i < n; i++) {
      final w = ev[i];
      if (w.abs() < 1e-12) continue;
      final ri = rows[i];
      for (var x = 0; x < p; x++) {
        pc[x] += w * ri[x];
      }
    }
    components.add(_normaliseAndClahe(pc, width, height));
  }

  final topVals = Float64List(k);
  for (var i = 0; i < k; i++) {
    topVals[i] = eigenvalues[i];
  }

  return PcaOutput(
    components: components,
    eigenvalues: topVals,
    width: width,
    height: height,
  );
}

Uint8List _normaliseAndClahe(Float64List src, int width, int height) {
  // 2-98 % percentile stretch (matches the desktop pipeline) so isolated
  // extreme values from edges / shadows don't compress the inscription range.
  final sorted = Float64List.fromList(src)..sort();
  final lo = sorted[(sorted.length * 0.02).floor()];
  final hi = sorted[(sorted.length * 0.98).floor().clamp(0, sorted.length - 1)];
  final span = hi - lo;
  final out = Uint8List(src.length);
  if (span.abs() < 1e-9) {
    return out;
  }
  final inv = 255.0 / span;
  for (var i = 0; i < src.length; i++) {
    final v = (src[i] - lo) * inv;
    out[i] = v.round().clamp(0, 255);
  }
  return clahe(out, width, height);
}

/// Eigendecomposition of a real symmetric matrix via cyclic Jacobi rotations.
///
/// Returns (eigenvectors, eigenvalues) sorted by **descending** eigenvalue.
/// `eigenvectors[k]` is the k-th eigenvector (length n).
///
/// For small n (≤ ~30) cyclic Jacobi converges in a handful of sweeps and is
/// numerically stable. The input matrix `A` is modified in place.
(List<Float64List>, Float64List) symmetricEigenDecomposition(
  List<Float64List> A, {
  int maxSweeps = 50,
  double tolerance = 1e-12,
}) {
  final n = A.length;
  if (n == 1) {
    return (
      [Float64List.fromList([1.0])],
      Float64List.fromList([A[0][0]])
    );
  }

  // V starts as the identity; eigenvectors accumulate as we rotate.
  final V = List.generate(n, (i) {
    final row = Float64List(n);
    row[i] = 1.0;
    return row;
  });

  for (var sweep = 0; sweep < maxSweeps; sweep++) {
    // Magnitude of the off-diagonal — convergence criterion.
    var offDiag = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        offDiag += A[i][j] * A[i][j];
      }
    }
    if (math.sqrt(offDiag) < tolerance) break;

    for (var i = 0; i < n - 1; i++) {
      for (var j = i + 1; j < n; j++) {
        final aij = A[i][j];
        if (aij.abs() < 1e-15) continue;

        final aii = A[i][i];
        final ajj = A[j][j];

        // Closed-form rotation that zeroes A[i][j] (Givens / Jacobi).
        double t;
        if (aii == ajj) {
          t = aij >= 0 ? 1.0 : -1.0;
        } else {
          final theta = (ajj - aii) / (2 * aij);
          final sign = theta >= 0 ? 1.0 : -1.0;
          t = sign / (theta.abs() + math.sqrt(1 + theta * theta));
        }
        final c = 1.0 / math.sqrt(1 + t * t);
        final s = t * c;

        // Update diagonal pair.
        A[i][i] = aii - t * aij;
        A[j][j] = ajj + t * aij;
        A[i][j] = 0;
        A[j][i] = 0;

        // Update the rest of rows/cols i and j.
        for (var kk = 0; kk < n; kk++) {
          if (kk == i || kk == j) continue;
          final aik = A[i][kk];
          final ajk = A[j][kk];
          A[i][kk] = c * aik - s * ajk;
          A[kk][i] = A[i][kk];
          A[j][kk] = s * aik + c * ajk;
          A[kk][j] = A[j][kk];
        }

        // Apply the same rotation to V (eigenvectors stored as columns).
        for (var kk = 0; kk < n; kk++) {
          final vki = V[kk][i];
          final vkj = V[kk][j];
          V[kk][i] = c * vki - s * vkj;
          V[kk][j] = s * vki + c * vkj;
        }
      }
    }
  }

  // Eigenvalues are now on the diagonal.
  final values = Float64List(n);
  for (var i = 0; i < n; i++) {
    values[i] = A[i][i];
  }

  // Sort descending.
  final indices = List<int>.generate(n, (i) => i)
    ..sort((a, b) => values[b].compareTo(values[a]));

  final sortedVectors = List<Float64List>.generate(n, (kk) {
    final v = Float64List(n);
    final col = indices[kk];
    for (var i = 0; i < n; i++) {
      v[i] = V[i][col];
    }
    return v;
  });
  final sortedValues = Float64List(n);
  for (var i = 0; i < n; i++) {
    sortedValues[i] = values[indices[i]];
  }

  return (sortedVectors, sortedValues);
}

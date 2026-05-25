# Frame registration

Every algorithm the Stack tab runs (max / min / range / stddev, fusion,
CLAHE, Retinex, photometric stereo) assumes the frames in a session are
pixel-aligned. Tripod bumps, handheld jitter, and orientation changes
between shots break that assumption. The pipeline runs a registration
step before stacking; the user picks the algorithm from a dropdown on
the session detail screen.

## Modes

All modes write per-frame similarity transforms back to the sidecar so
the desktop pipeline can replay alignment on the full-resolution RAWs.

### None — passthrough

Identity transforms, no warp, no crop. Useful as a regression-test
sanity check ("how much of the output quality comes from registration
vs the algorithms?") and when the user trusts the tripod.

### Fast — NCC pyramid (2-DoF translation) — pure Dart

Coarse-to-fine search:
1. Build an image pyramid (each level downsampled 2×) down to ~64 px
   on the small edge.
2. At the coarsest level, exhaustively search a ±(small-edge / 2)
   pixel window for the (dx, dy) that maximises normalised cross
   correlation between reference and source. NCC is mean-invariant,
   so the brightness differences induced by raking light don't fool it.
3. Upsample the estimate (×2) and refine by ±2 px at each finer level.
4. At the original resolution, fit a parabola to the NCC scores around
   the peak to get sub-pixel translation.

Handles tripod bumps and small handheld jitter. Fails on rotation
beyond ~1° and on scale changes beyond ~2%.

Implementation: [`lib/core/image_ops/registration.dart`](../lib/core/image_ops/registration.dart),
roughly 200 LoC.

### Accurate — NCC pyramid + rotation/scale grid search (4-DoF) — pure Dart

1. Same NCC pyramid translation as **Fast** to bootstrap (tx, ty).
2. At the coarsest pyramid level, exhaustively search a 7 × 7 grid
   over (rotation ∈ [−3°, +3°], scale ∈ [0.97, 1.03]). For each
   (rot, scale) candidate: warp the source by that similarity and
   compute NCC against the reference at the coarse level.
3. With the winning (rot, scale), refine translation at full
   resolution by a small ±4-pixel NCC search + sub-pixel quadratic
   peak fit.

Handles handheld tilt and small zoom changes. Fails on large
displacements (because the grid is small) and on perspective changes
(which need a homography, not a similarity).

Roughly 5–10× slower than Fast on an 8-frame stack — still well under
a second on phone-class hardware.

### ORB — feature-based (4-DoF similarity, future) — opencv_dart

Status: **dependency added (v0.9 scaffold), implementation pending.**

When ECC / grid search can't bootstrap from a sensible initial guess
(large rotations, large displacements, partial occlusion), feature
matching is the right tool. The planned pipeline:

1. Detect ORB features in the reference and each source frame
   (`cv.ORB.empty().detectAndCompute(...)`).
2. Match descriptors with a brute-force Hamming-distance matcher
   (`cv.BFMatcher.create(type: cv.NORM_HAMMING, crossCheck: true)`).
3. RANSAC similarity fit (`cv.estimateAffinePartial2D(src, dst,
   method: cv.RANSAC)`) — returns a 2×3 matrix
   `[s·cos θ, −s·sin θ, tx; s·sin θ, s·cos θ, ty]`.
4. Convert the 2×3 matrix to our `FrameTransform`: `scale =
   √(a² + b²)`, `rotation = atan2(b, a)`, with `a = M[0][0]` and
   `b = M[1][0]`.

Two implementation considerations to resolve before shipping:

- **Isolate safety.** The existing stack pipeline runs inside
  `Isolate.run`. Some FFI bindings restrict their native handles to
  the thread they were created on. We need to confirm `opencv_dart`
  Mats can cross isolate boundaries (or accept running ORB on the main
  isolate and only sending the resulting transforms into the worker).
- **Robustness fallback.** If ORB finds < ~10 inliers, fall back to
  Accurate mode rather than returning a junk transform.

### v0.10+ candidates

- **ECC iterative refinement** (`cv.findTransformECC`) layered on top
  of ORB for sub-pixel polish. ECC's zero-mean normalised correlation
  loss is the ideal objective for raking light.
- **Homography** for non-perpendicular shots
  (`cv.findHomography(method: cv.RANSAC)`).
- **Multi-band blending** of aligned frames for output reductions, to
  hide any residual mis-alignment at edges.

## Coordinate convention

A `FrameTransform` maps **source-frame coords** onto
**reference-frame coords**:

```
ref = R(θ) · scale · src + (tx, ty)
```

The warp samples each output pixel by applying the inverse:

```
src = R(−θ) · (ref − (tx, ty)) / scale
```

The intersection of every frame's valid post-warp region becomes the
common output rectangle; pixel data outside that rect is dropped from
all downstream outputs so there are no edge artifacts.

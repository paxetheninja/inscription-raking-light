# Stela

Mobile companion for **raking-light documentation of inscriptions** — Flutter
app targeting Android and iOS, built via GitHub Actions. Repo:
`paxetheninja/inscription-raking-light`. App display name: **Stela**.

"Streiflicht" is German for raking light: a low-angle illumination technique
that reveals incised letterforms and surface detail invisible under flat light.
This app is a field tool that complements a DSLR-based workflow (Canon CR3 +
JPG, organised by stone and lighting mode) rather than replacing it.

## Capture model

- Phone is the **camera** — handheld or on a small tripod.
- An assistant sweeps an **external light** across the stone at a low angle.
- The app captures a short burst with locked exposure and white balance.
- Optional: the user "pings" the app at each light position so an IMU-derived
  azimuth/elevation hint can be stored alongside the frame.

The app does **not** try to be a desktop replacement. Heavy processing
(photometric stereo, multi-scale stacks at full resolution, RAW development)
stays on the desktop. The phone produces previews and a clean export bundle.

## v1 features

| Area | Output |
| --- | --- |
| Stack reductions | per-pixel max / min / range / stddev across the burst |
| Fusion + enhancement | Mertens-style exposure fusion → multi-scale Retinex → CLAHE |
| Normal map _(stretch)_ | photometric stereo when light directions are known |
| Scale calibration | tap a ruler in-frame → mm/pixel → measure letters & lines |
| Export | original frames + downsampled previews + `sidecar.json` for desktop |

All in-app outputs are computed on **downsampled previews** for responsiveness.
Full-resolution analysis happens in the desktop pipeline using the exported
sidecar.

## Sidecar schema (draft)

```json
{
  "schema": "inscription-raking-light/sidecar@1",
  "session_id": "01J...",
  "captured_at": "2026-05-25T14:03:11Z",
  "device_model": "iPhone15,3",
  "scale_mm_per_pixel": 0.0421,
  "frames": [
    {
      "file": "raw/0001.jpg",
      "timestamp_ms": 1716640991123,
      "light_azimuth_deg": 312.5,
      "light_elevation_deg": 18.0,
      "iso": 100,
      "exposure_us": 4000,
      "focus_distance_m": 0.42
    }
  ]
}
```

See [`lib/core/sidecar/sidecar_schema.dart`](lib/core/sidecar/sidecar_schema.dart).

## Project layout

```
lib/
  main.dart                 entry point
  app.dart                  root widget + four-tab shell
  features/
    capture/                burst capture UI (camera wiring in v0.2)
    stack/                  on-device preview enhancements
    measure/                scale calibration + measurement tools
    export/                 session bundling + share sheet
  core/
    sidecar/                JSON schema for the desktop pipeline
```

## Build

Local:

```sh
flutter pub get
flutter analyze
flutter test
flutter run                       # plug in a device / start a simulator
flutter build apk --debug         # Android
flutter build ios --no-codesign   # iOS (no Apple account needed)
```

CI on every push / PR to `main`:

- **Android** — `ubuntu-latest`, builds a debug APK and uploads it as an artifact.
- **iOS** — `macos-latest`, builds an unsigned `Runner.app` and uploads it as
  an artifact. Useful as a smoke test and for sideloading via Xcode without
  Apple Developer setup.

On `v*` tag pushes:

- **iOS Release (TestFlight)** — `macos-latest`, builds a **signed App Store
  IPA** and uploads it to TestFlight via `xcrun altool` + an App Store
  Connect API key. Internal testers receive the build instantly; external
  testers after a one-time Apple beta review. See
  [`docs/IOS_SIGNING.md`](docs/IOS_SIGNING.md) for the one-time setup.

Pinned to Flutter `3.38.8` to match the development environment.

## Roadmap

- **v0.1** ✅ — four-tab shell, CI green on both platforms, sidecar schema drafted.
- **v0.2** ✅ — camera wiring: AE/AF lock, session folders, JPEG capture, sidecar
  written on every shutter. IMU light-direction "ping" deferred to v0.4.
- **v0.3** ✅ — on-device preview reductions (max / min / range / stddev) running
  in an `Isolate`, 2×2 grid viewer.
- **v0.4** ✅ — Mertens-style exposure fusion, multi-scale Retinex (separable
  Gaussian), and CLAHE applied to the fusion. All seven outputs computed in
  one isolate pass. Manual 8-azimuth × 3-elevation light-direction picker on
  the Capture tab, persisted per frame in the sidecar.
- **v0.5** ✅ — scale calibration: tap two points on a ruler in a captured
  frame, enter the real-world distance in mm, the app writes
  `scale_mm_per_pixel` to the sidecar. Measure mode reads it back to show
  on-image distances in mm.
- **v0.6** ✅ — Stack tab persists the seven enhancement PNGs to
  `<session>/preview/` after computing. Export tab lists every session
  with frame count + on-disk size; "Share zip" bundles `raw/` + `preview/`
  + `sidecar.json` into a temp `.zip` and opens the system share sheet.
  Stack tab session tiles gain a 3-dot menu for **Rename** + **Delete**.
- **v0.7** ✅ — Lambertian photometric-stereo normal map. When every frame
  in the session has a light direction set (Capture tab compass picker),
  the pipeline solves a 3×3 system per pixel and emits an RGB normal map
  encoded with the standard `(n + 1) / 2` convention. Throws with a
  human-readable explanation when light directions are coplanar.
- **v0.8** ✅ — image registration menu. Three pure-Dart modes (None, Fast
  NCC translation, Accurate NCC + rotation/scale grid search), pre-stack
  alignment in the same isolate, valid-region crop, per-frame transforms
  written into the sidecar.
- **v0.9** ✅ — ORB + RANSAC similarity registration via `opencv_dart`,
  selectable in the same dropdown. Handles large displacements and tilt
  that the pure-Dart Fast/Accurate modes can't bootstrap. Computed on
  the main isolate (FFI handles aren't safe across isolate boundaries),
  transforms then sent into the worker isolate for warp + crop + stack.
- **v0.10** — DNG capture (Camera2 RAW_SENSOR on Android / AVCapturePhoto
  raw on iOS via custom platform channels — significant native work).

## Status

v0.5 — the on-device loop works end-to-end:

1. **Capture** a burst with AE/AF locked, optionally tagging each frame with
   a coarse light direction (8 compass azimuths × 3 elevations).
2. **Stack** the session and run the full enhancement pipeline: per-pixel
   reductions, Mertens-style fusion, fusion+CLAHE, fusion+Retinex.
3. **Measure** by tapping two points on a ruler in a captured frame, enter
   the real distance in mm, then switch to Measure mode to read letter
   heights and stroke widths off the image.

All session data persists under the app's documents directory as
`sessions/<id>/raw/*.jpg` + `sidecar.json` (now including light direction
per frame and `scale_mm_per_pixel` per session).

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
- **v0.10** ✅ — Inscription-specialised gallery outputs: PCA layers
  (PC1–PC4, where PC2 is the primary relief channel), combined relief
  (`stddev + range/2`), multi-scale Difference of Gaussians, and
  black-hat morphology on the fusion image. Retinex now CLAHE-chained
  to match the desktop pipeline.
- **v0.11** ✅ — App-shell polish: Settings + About + theme support, global
  AppBar with the tutorial replay icon and an overflow menu, six-step
  introduction_screen first-launch carousel, mass export via long-press
  multi-select on the Export tab (combined into one zip), editable
  session notes, and a "Report a problem" mailto link in About + Settings.
  Session import via `.zip` (capture and re-import survives uninstall).

## Planned (in priority order)

These are on the queue but not actively in progress.

- **Geolocation tagging on capture.** Per-session GPS coordinates
  (with explicit permission). Sidecar gets `location: {lat, lon, acc}`.
  Needs the `geolocator` package + iOS / Android usage strings. Useful
  for archaeology where each stone has a known find spot.
- **Session search / filter.** Once 30+ sessions accumulate, finding
  "all Weber stones from 2026" needs more than scrolling. Text search
  on label + notes + tags, date range filter, calibrated-only filter.
- **Multi-frame Measure.** Currently the Measure tab shows the first
  frame in a fixed-fit canvas. Add an `InteractiveViewer` (pan + zoom)
  and a frame picker so you can switch between frames to find a sharper
  one for calibration or place markers more precisely.
- **Reference scale auto-detection.** Find a ruler in the frame
  automatically (template matching against a stock ruler image, or
  edge-detected linear feature with regularly-spaced ticks). Removes a
  manual step in Measure.
- **DNG capture** (already on the original roadmap as v0.7's deferred
  half) — Camera2 `RAW_SENSOR` on Android / `AVCapturePhotoSettings.rawPixelFormatType`
  on iOS via custom platform channels. Significant native work.

## Status

v0.11 — the on-device loop works end-to-end:

1. **Capture** a burst with AE/AF locked, optionally tagging each frame with
   a coarse light direction (8 compass azimuths × 3 elevations).
2. **Stack** the session — registration (None / Fast / Accurate / ORB), then
   reductions, Mertens fusion, CLAHE, Retinex, PCA layers, multi-scale DoG,
   combined relief, black hat, and photometric-stereo normal map.
3. **Measure** by tapping two points on a ruler in a captured frame, enter
   the real distance in mm, then switch to Measure mode to read letter
   heights and stroke widths off the image.
4. **Export** individual sessions or bundle several via multi-select; import
   exported zips back after a reinstall.

Settings + About are reachable from the global AppBar overflow menu;
first-launch tutorial walks new users through the loop above.

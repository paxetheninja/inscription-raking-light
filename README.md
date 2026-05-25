# inscription-raking-light

Mobile companion for **raking-light documentation of inscriptions** — Flutter app
targeting Android and iOS, built via GitHub Actions.

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
  an artifact. Sideload via Xcode, or wire up signing secrets later for IPA /
  TestFlight.

Pinned to Flutter `3.38.8` to match the development environment.

## Roadmap

- **v0.1** _(this scaffold)_ — four-tab shell, CI green on both platforms,
  sidecar schema drafted.
- **v0.2** — camera wiring: locked exposure / WB burst capture, gallery list,
  IMU light-direction "ping".
- **v0.3** — on-device preview stack (max / min / range / stddev) in an
  isolate, side-by-side viewer.
- **v0.4** — fusion + Retinex + CLAHE on the preview pipeline.
- **v0.5** — scale calibration + measurement overlay.
- **v0.6** — export bundle (zip with raw frames + previews + sidecar) +
  share sheet.
- **v0.7** — DNG capture where supported; rough photometric-stereo normal map.

## Status

Early scaffold — feature screens are placeholders. Build chain (local +
GitHub Actions) is the deliverable of v0.1.

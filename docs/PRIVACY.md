# Stela — Privacy Policy

*Last updated: 2026-05-29*

## TL;DR

**Stela does not collect, transmit, or share any of your data.** Everything
the app captures and computes stays on your device. There are no accounts,
no analytics, no advertising SDKs, no third-party trackers, and no servers
the app talks to behind your back.

This document explains the details — what's stored, where, and why each
permission is requested — so that you can verify that claim and so that
Apple and Google's store reviewers can confirm it for the public listings.

## Who we are

Stela is developed at the University of Graz (Austria) as a field tool
for archaeological epigraphy — documenting Roman inscriptions on stone
with raking-light photography.

- Source code: <https://github.com/paxetheninja/inscription-raking-light>
- Contact: `florian.wachter698@gmail.com`

## What Stela does and does not do

Stela:

- Uses the device camera to capture photographs of inscribed stones.
- Stores captured photographs, computed enhancement images, and a
  per-session JSON metadata file (`sidecar.json`) **inside the app's
  private storage** on your device.
- Lets you share or import session zips via the operating system's
  built-in share sheet and file picker — you choose where each file goes
  and who, if anyone, receives it.
- Opens external URLs (only the source repo and the support email) when
  you tap the corresponding links in the About screen.

Stela does **not**:

- Collect or transmit personal data of any kind.
- Use third-party analytics, telemetry, or advertising SDKs.
- Access your contacts, microphone, location, photo library, or any
  other system resource beyond what is listed below.
- Talk to any server operated by the developer.
- Track you across apps or websites.

## Data we store locally

| What | Where | Why |
| --- | --- | --- |
| Captured JPEGs | `<app-sandbox>/sessions/<id>/raw/` | They're the raw material for the inscription documentation. |
| Computed enhancement PNGs | `<app-sandbox>/sessions/<id>/preview/` | So you don't have to re-run the pipeline every time. |
| Per-session metadata | `<app-sandbox>/sessions/<id>/sidecar.json` | Label, capture timestamps, per-frame light direction, scale-bar calibration, alignment transforms. |
| App settings | shared preferences | Theme, default registration mode, preview resolution, whether the tutorial has been seen. |

All of the above lives in the app's private sandbox, which iOS and
Android wipe on uninstall.

You can export any session via the Export tab to receive a single `.zip`
that you can save, share, or send to a desktop. Files leave the sandbox
only when you explicitly use the share sheet.

## Permissions

| Permission | Why |
| --- | --- |
| **Camera** | To capture the raking-light photographs. Stela never opens the camera without you tapping the shutter inside the app. |
| **Photo library "add" (iOS)** | So that exported session zips can be saved to your library when you choose that destination from the share sheet. Stela never reads from the photo library. |
| **File access via the system file picker** | To let you import a previously-exported session zip from another location. |
| **Location, when in use *(optional)*** | Off by default. Only requested if you turn on **Settings → Capture → Tag location on capture**. When enabled, Stela attempts a single GPS fix at the start of each new session and writes the latitude / longitude / accuracy into the session's local `sidecar.json` so you can correlate captures with the find-spot of an inscription. The coordinates never leave the device unless you export the session and share the zip yourself. |

No microphone, no contacts, no notifications.

## Network

Stela makes no network requests of its own. The only network traffic that
can occur is:

- The OS-provided share sheet may upload a file when you choose a cloud
  destination (e.g. AirDrop, Files, iCloud Drive). That traffic is
  handled by the operating system, not by Stela.
- The About screen has two links — the source repository on GitHub and a
  `mailto:` to the developer. When you tap them, the OS hands the URL to
  the relevant browser or mail app.

## Third parties

Stela's compute pipeline includes the
[OpenCV](https://opencv.org/) C++ library (via the `opencv_dart`
Flutter plugin) for ORB feature matching and morphology. The library
runs entirely on-device and does not phone home. Other transitive
dependencies are listed on the About → Open-source licenses screen
inside the app and at
<https://github.com/paxetheninja/inscription-raking-light/blob/main/pubspec.yaml>.

## Children

Stela is not directed at children under 13. It contains no
user-generated content, no chat, and no in-app purchases.

## Changes to this policy

This document is part of the open-source repository. Any change to it is
visible in the Git history at
<https://github.com/paxetheninja/inscription-raking-light/commits/main/docs/PRIVACY.md>.

## Contact

Questions, concerns, or requests about this policy:
`florian.wachter698@gmail.com`.

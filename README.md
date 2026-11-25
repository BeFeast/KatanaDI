# KatanaDI

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Minimal macOS menu bar utility for routing the clean DI channel from a BOSS Katana USB device to the Mac built-in output with no intentional DSP.

## Status

`v0.1.0` is the first working internal release.

Current validated setup:

- macOS 12.x on Intel Mac mini
- BOSS Katana USB input
- `Channel 3`
- `Mono -> Right`
- system output set to `Built-in Output` / `Headphones`

## What It Does

- auto-detects the Katana input device by name
- routes one selected input channel to the built-in output
- supports `Mono -> Left`, `Mono -> Right`, and `Mono -> Stereo`
- persists settings to `~/.katanadi.json`
- can install a LaunchAgent for `Start at Login`
- shows route state and live diagnostics in a menu bar app
- builds Intel, Apple Silicon, or universal `.app` bundles

## What It Does Not Do

- audio effects or amp simulation
- recording
- arbitrary multi-device routing
- custom output device selection UI
- notarized/public macOS distribution

## Requirements

- macOS 12 or newer
- Swift toolchain with Swift Package Manager
- microphone permission granted to `KatanaDI`
- system output set to the built-in analog output

Important: the app currently renders through the macOS default output unit and explicitly expects that default output to be the built-in output device. If macOS shows `Headphones`, that is still the same built-in analog output when the 3.5 mm jack is occupied.

## Quick Start

Run from source:

```bash
swift run
```

Build an Intel app bundle:

```bash
./scripts/build_intel_app.sh
```

Build a universal app bundle:

```bash
./scripts/build_app.sh --arch universal
```

Artifacts are written to `dist/`.

## First Launch

1. Launch the app.
2. Allow microphone access when macOS asks for it.
3. Make sure macOS sound output is `Built-in Output` or `Headphones`.
4. Open the menu bar item.
5. For the known-good Katana Air setup, select `Channel 3` and `Mono -> Right`.

Without microphone permission the app can appear alive while receiving silence from CoreAudio input.

## Menu Diagnostics

When routing is active, the menu shows live diagnostics:

- `Ring Buffer`: current fill level and target fill
- `Signal`: input and output peak values
- `Callbacks`: input and output callback counters
- `Corrections`: underflows, overflows, dropped frames, duplicated frames

These values should move while playing. If they do not, check the troubleshooting guide.

## Build and Packaging

The build scripts produce plain `.app` bundles with:

- generated `Info.plist`
- microphone usage description
- generated `.icns` app icon
- ad-hoc code signing when `codesign` is available

Relevant scripts:

- `scripts/build_app.sh`
- `scripts/build_intel_app.sh`
- `scripts/generate_app_icon.swift`

## Configuration and Persistence

- App config: `~/.katanadi.json`
- LaunchAgent: `~/Library/LaunchAgents/com.oklabs.katanadi.plist`

`Start at Login` uses a LaunchAgent. If the app is started from a bundle, the LaunchAgent reopens the `.app`. If it is started from a raw executable, the LaunchAgent launches that executable path directly.

## Known Limitations

- drift compensation is intentionally lightweight; long sessions still need more validation on real hardware
- no resampling path is implemented for incompatible sample rate combinations
- output routing is intentionally locked to the built-in output path for now
- no notarization, installer, or hardened distribution flow yet

## Documentation

- Product spec: [`docs/PRD.md`](docs/PRD.md)
- Architecture notes: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- Troubleshooting: [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)

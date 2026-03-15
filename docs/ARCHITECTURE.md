# KatanaDI Architecture

## Overview

KatanaDI is a small Swift Package Manager macOS menu bar app built around one runtime path:

`Katana input -> CoreAudio input callback -> mono ring buffer -> CoreAudio output callback -> built-in output`

The codebase is intentionally split into a few narrow areas so the signal path stays auditable.

## Main Modules

### App shell

- `Sources/KatanaDI/main.swift`
- `Sources/KatanaDI/App/AppDelegate.swift`
- `Sources/KatanaDI/App/ApplicationController.swift`
- `Sources/KatanaDI/App/MenuBarController.swift`

Responsibilities:

- application lifecycle
- microphone permission gating
- route refresh on startup and device changes
- menu rendering and user actions
- periodic diagnostics refresh

### Domain model

- `Sources/KatanaDI/Domain/AppConfiguration.swift`
- `Sources/KatanaDI/Domain/AppStatus.swift`

Responsibilities:

- persisted settings
- output mode enum
- active/waiting/error UI state
- diagnostics snapshot formatting

### Persistence and OS integration

- `Sources/KatanaDI/Persistence/ConfigurationStore.swift`
- `Sources/KatanaDI/Persistence/LaunchAtLoginController.swift`

Responsibilities:

- JSON config storage at `~/.katanadi.json`
- LaunchAgent creation/removal for login launch

### CoreAudio layer

- `Sources/KatanaDI/CoreAudio/AudioHardware.swift`
- `Sources/KatanaDI/CoreAudio/AudioDeviceDescriptor.swift`
- `Sources/KatanaDI/CoreAudio/AudioDeviceInventory.swift`
- `Sources/KatanaDI/CoreAudio/AudioDeviceMonitor.swift`
- `Sources/KatanaDI/CoreAudio/PCMFloatRingBuffer.swift`
- `Sources/KatanaDI/CoreAudio/AudioRoutingEngine.swift`

Responsibilities:

- device enumeration and descriptor lookup
- device change monitoring
- AUHAL input capture
- default output rendering
- channel extraction and output mode mapping
- ring buffer transport between independent callbacks
- lightweight drift correction and diagnostics counters

## Runtime Flow

1. `ApplicationController` starts and checks microphone authorization.
2. Once authorized, it starts device monitoring and loads the current inventory.
3. It resolves the input device by name match, currently targeting `KATANA`.
4. It resolves the output device by name match, currently targeting `Built-in Output`.
5. `AudioRoutingEngine` verifies that the current system default output is the expected built-in output device.
6. Input is captured through an AUHAL input unit.
7. The selected input channel is copied into a mono float ring buffer.
8. Output is rendered through the default output unit.
9. The mono signal is written to left, right, or both output channels depending on the selected output mode.
10. Menu diagnostics are refreshed on a timer and updated in place while the menu is open.

## Important Design Decisions

### Microphone permission is mandatory

macOS gates audio capture behind microphone permission even for this routing use case. The app requests permission on first launch and moves to an error state if access is denied.

### Output is tied to the system built-in output

The current implementation deliberately uses the macOS default output unit and requires that default output to be the built-in output path. This keeps the output side closer to the standard system render path and reduced compatibility issues during initial validation.

### Channel mapping happens in code

The input path renders all available input channels and then selects the requested Katana channel in software. This is more robust than relying on HAL channel map behavior for the target hardware.

### Diagnostics are live and lightweight

The app tracks callback counts, peaks, ring occupancy, and underflow/overflow corrections. These diagnostics are meant for live support and validation, not for full telemetry.

## Current Constraints

- no arbitrary output-device selection UI yet
- no resampling engine yet
- drift handling is intentionally simple, not a full clock-domain reconciliation strategy
- no automated tests yet for audio lifecycle on real hardware

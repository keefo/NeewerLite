# NeewerLite Codebase Guide

> A comprehensive reference for anyone working on this codebase.
> Last updated: April 2026

---

## Table of Contents

1. [What Is NeewerLite?](#what-is-neewerlite)
2. [Repository Layout](#repository-layout)
3. [Build & Run](#build--run)
4. [Architecture Overview](#architecture-overview)
5. [BLE Protocol & Light Communication](#ble-protocol--light-communication)
6. [Model Layer](#model-layer)
7. [View Layer](#view-layer)
8. [Sound-to-Light System](#sound-to-light-system)
9. [External Integration](#external-integration)
10. [Stream Deck Plugin](#stream-deck-plugin)
11. [Light Database](#light-database)
12. [Testing](#testing)
13. [CI / Release Pipeline](#ci--release-pipeline)
14. [Key Patterns & Conventions](#key-patterns--conventions)
15. [Common Tasks](#common-tasks)

---

## What Is NeewerLite?

NeewerLite is a **native macOS app** (Swift, AppKit) that controls Neewer Bluetooth LED lights — the same lights Neewer only provides iOS/Android apps for. It runs as a menu-bar app and provides:

- Full light control: power, brightness, CCT (3200K–8500K), RGB (HSI mode), scene effects, light source presets
- 39 professional gel presets (Lee/Rosco standards) with submultiplicative color stacking
- Sound-to-Light: real-time audio-reactive lighting with beat detection
- Automation: URL scheme (`neewerlite://`), HTTP server for Stream Deck, scriptable from Terminal/Shortcuts
- Multi-light management with per-light independent control

**Minimum deployment target:** macOS 13 (Ventura)

**Dependencies** (via SPM):
- [Vapor](https://github.com/vapor/vapor) — HTTP server framework
- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) — Model Context Protocol server (0.12.0)
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Auto-update framework
- [swift-atomics](https://github.com/apple/swift-atomics) — Lock-free atomic operations

---

## Repository Layout

```
NeewerLite/                         ← Root
├── README.md                       ← User-facing readme
├── LICENSE
├── appcast.xml                     ← Sparkle update feed
│
├── Database/                       ← Light database (deployed to GitHub CDN)
│   ├── lights.json                 ← Master light definitions (types, commands, FX, gels)
│   ├── light_images/               ← Product photos (60+)
│   └── scene_images/               ← Scene effect thumbnails
│
├── Design/                         ← Sketch design files
│
├── Docs/                           ← Documentation & shell script examples
│   ├── Codebase-Guide.md           ← This file
│   ├── Sound-to-Light-Engine.md    ← STL engine design, modes, noise gate, architecture
│   ├── Gels.md
│   ├── Integrate-with-shortcut.md
│   ├── Integrate-with-streamdeck.md
│   └── *.sh                        ← Example automation scripts
│
├── NeewerLite/                     ← Xcode project root
│   ├── Package.swift               ← SPM dependencies
│   ├── NeewerLite.xcodeproj/       ← Xcode project
│   ├── ci_scripts/                 ← Xcode Cloud CI hooks
│   │
│   ├── NeewerLite/                 ← App source
│   │   ├── AppDelegate.swift       ← App lifecycle, BLE scanning, UI orchestration
│   │   ├── ContentManager.swift    ← Light database loading & caching
│   │   ├── NeewerLiteApplication.swift  ← Custom NSApplication (suppress activation)
│   │   ├── Server.swift            ← HTTP + MCP server (localhost:18486)
│   │   │
│   │   ├── Model/                  ← Data model
│   │   │   ├── NeewerLight.swift           ← Core light model + BLE comms
│   │   │   ├── NeewerLightConstant.swift   ← BLE constants, type mapping
│   │   │   ├── NeewerLightFX.swift         ← Scene effect definitions
│   │   │   ├── NeewerLightSource.swift     ← Light source presets (with default CCT/GM)
│   │   │   ├── Command.swift               ← URL scheme command routing
│   │   │   ├── CommandPatternParser.swift   ← BLE command template engine
│   │   │   ├── NeewerGel.swift             ← Gel presets + stacking math
│   │   │   └── ImageFile.swift             ← Product image thumbnails
│   │   │
│   │   ├── Common/                 ← Shared utilities
│   │   │   ├── Observable.swift            ← Simple reactive <T> wrapper
│   │   │   ├── Logger.swift                ← Structured logging + batch upload
│   │   │   ├── StorageManager.swift        ← App Support directory I/O
│   │   │   ├── ColorUtils.swift            ← HSV ↔ RGB conversion
│   │   │   ├── DataExtensions.swift        ← Data.hexString, Comparable.clamped
│   │   │   ├── CBCharacteristicExtensions.swift  ← BLE helpers
│   │   │   ├── CodableValue.swift          ← Type-erased Codable wrapper
│   │   │   ├── NSBezierPathExtensions.swift
│   │   │   └── Utils.swift
│   │   │
│   │   ├── Views/
│   │   │   ├── SettingsView.swift           ← Settings: launch at login, server toggle
│   │   │   └── ...                         ← (see View Layer section)
│   │   │
│   │   ├── Spectrogram/            ← Sound-to-Light engine
│   │   │   ├── AudioSpectrogram.swift      ← Audio capture + mel-spectrogram
│   │   │   ├── AudioAnalysisEngine.swift   ← Feature extraction + beat detection
│   │   │   └── SoundToLightMode.swift      ← Mapping modes + throttle + presets
│   │   │
│   │   ├── ViewModels/             ← MVVM binding layer
│   │   │   ├── DeviceViewObject.swift      ← Light model ↔ UI bindings
│   │   │   ├── SpectrogramViewObject.swift ← Spectrogram display state
│   │   │   └── MySplitViewDelegate.swift   ← Split view sizing
│   │   │
│   │   ├── Views/                  ← UI components
│   │   │   ├── CollectionViewItem.swift        ← Per-light control card (main UI)
│   │   │   ├── CollectionViewItem+Gels.swift   ← Gel tab extension
│   │   │   ├── ColorWheel.swift                ← HSV color picker
│   │   │   ├── FXView.swift                    ← Scene effect parameter editor
│   │   │   ├── GelSwatchCell.swift             ← Gel color swatch cell
│   │   │   ├── NLSlider.swift                  ← Custom slider control
│   │   │   ├── PatternEditorPanel.swift        ← BLE command pattern editor
│   │   │   ├── RenameViewController.swift      ← Light rename dialog
│   │   │   ├── MyLightTableCellView.swift      ← Scan view table cell
│   │   │   ├── BlockingOverlayView.swift       ← Disconnected light overlay
│   │   │   ├── RoundedScrollView.swift
│   │   │   └── LogMonitorViewController.swift  ← Debug log viewer
│   │   │
│   │   └── Resources/
│   │       ├── Info.plist
│   │       ├── lights_db.json              ← Bundled fallback database
│   │       ├── Assets.xcassets/
│   │       ├── Base.lproj/MainMenu.xib     ← Main menu + window layouts
│   │       └── CollectionViewItem.xib      ← Per-light card layout
│   │
│   └── NeewerLiteTests/            ← Unit tests
│       ├── NeewerLiteTests.swift           ← Light naming & type mapping
│       ├── CommandParserTests.swift        ← BLE command generation
│       ├── AudioAnalysisEngineTests.swift  ← Audio feature extraction
│       ├── SoundToLightModeTests.swift     ← Mapping modes + reactivity
│       ├── GelsTests.swift                 ← Gel stacking math
│       ├── MCPServerTests.swift            ← MCP tool discovery & Value coercion
│       └── StringLocalizedTests.swift      ← Localization string tests
│
├── NeewerLiteStreamDeck/           ← Elgato Stream Deck plugin
│   ├── build.sh                    ← Build & package plugin
│   ├── neewerlite/
│   │   ├── package.json
│   │   ├── rollup.config.mjs
│   │   ├── src/                    ← TypeScript source
│   │   │   ├── actions/            ← Stream Deck actions
│   │   │   └── ipc.ts             ← HTTP client to NeewerLite server
│   │   └── com.beyondcow.neewerlite.sdPlugin/  ← Plugin bundle
│   │       └── manifest.json
│   └── *.sh                        ← Dev scripts (watch, reload, setup)
│
└── Tools/                          ← Build & release tooling
    ├── build.sh                    ← Archive + sign + DMG
    ├── publish.sh                  ← GitHub release + appcast update
    ├── validate.sh                 ← Code signing & notarization checks
    ├── clean.sh
    └── generate_appcast            ← Sparkle feed generator
```

---

## Build & Run

### Prerequisites

- Xcode 16+ (Swift 5.10+)
- macOS 13+ (Ventura)
- A Neewer Bluetooth LED light (optional — the app runs without one)

### Build the App

```bash
cd NeewerLite/NeewerLite

# Debug build
xcodebuild build \
  -project NeewerLite.xcodeproj \
  -scheme NeewerLite \
  -configuration Debug \
  -destination 'platform=macOS'
```

### Run Tests

```bash
xcodebuild test \
  -project NeewerLite.xcodeproj \
  -scheme NeewerLiteTests \
  -destination 'platform=macOS'
```

### Build Stream Deck Plugin

```bash
cd NeewerLiteStreamDeck
./build.sh
```

Requires: Node.js, npm, Elgato Stream Deck CLI (`streamdeck`).

### Archive for Release

```bash
cd Tools
./build.sh    # Creates .xcarchive + .dmg
./publish.sh  # Uploads to GitHub Releases + updates appcast.xml
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        AppDelegate                              │
│  (App lifecycle, BLE scanning, UI orchestration, command hub)   │
├──────────┬──────────┬──────────┬──────────┬─────────────────────┤
│          │          │          │          │                     │
│  ┌───────┴───────┐  │  ┌───────┴──────┐  │  ┌─────────────────┐│
│  │ CBCentralMgr  │  │  │   Server     │  │  │ ContentManager  ││
│  │ (BLE scan &   │  │  │ (HTTP+MCP    │  │  │ (Light DB,      ││
│  │  connection)  │  │  │  port 18486) │  │  │  remote fetch)  ││
│  └───────┬───────┘  │  └──────────────┘  │  └─────────────────┘│
│          │          │                    │                     │
│  ┌───────┴───────┐  │                    │                     │
│  │ NeewerLight[] │  │  Sound-to-Light    │                     │
│  │  (BLE model)  │  │  ┌────────────┐    │                     │
│  └───────┬───────┘  │  │AudioSpectro│    │                     │
│          │          │  │  (capture)  │    │                     │
│  ┌───────┴───────┐  │  └─────┬──────┘    │                     │
│  │DeviceViewObj[]│  │  ┌─────┴──────┐    │                     │
│  │ (MVVM bind)   │  │  │AnalysisEng │    │                     │
│  └───────┬───────┘  │  │ (features) │    │                     │
│          │          │  └─────┬──────┘    │                     │
│  ┌───────┴───────┐  │  ┌─────┴──────┐    │                     │
│  │CollectionView │  │  │ S2L Mode   │    │                     │
│  │  Item (UI)    │  │  │ (mapping)  │    │                     │
│  └───────────────┘  │  └─────┬──────┘    │                     │
│                     │  ┌─────┴──────┐    │                     │
│                     │  │BLE Throttle│    │                     │
│                     │  └────────────┘    │                     │
└─────────────────────┴────────────────────┴─────────────────────┘
                      │
              ┌───────┴───────┐
              │  Neewer LED   │
              │  (Bluetooth)  │
              └───────────────┘
```

### Key Architectural Decisions

| Decision | Why |
|----------|-----|
| **AppKit, not SwiftUI** | Started before SwiftUI was mature enough for BLE + custom drawing. Menu bar integration is cleaner with NSApplication. |
| **Observable&lt;T&gt;, not Combine** | Lightweight, synchronous, no framework dependency. One-liner bindings: `value.bind { ... }`. |
| **Code-driven UI (mostly)** | `CollectionViewItem` builds tabs and controls programmatically. Only the outer frame comes from XIB. This makes it easy to adapt UI per light capabilities. |
| **Command pattern templates** | BLE commands vary by light model. Instead of hardcoding, each light type defines command patterns in JSON (`{cmdtag} {ccttag} {size} {brr:uint8:range(0,100)} ...`). The `CommandPatternParser` fills in values at runtime. |
| **Database-driven light support** | Adding a new light model requires zero code changes — just add an entry to `Database/lights.json`. The app fetches the latest DB from GitHub automatically. |

### Data Flow Summary

**User adjusts slider → light changes color:**
```
CollectionViewItem (slider action)
  → DeviceViewObject.updateHSI(hue:sat:brr:)
    → NeewerLight.sendHSICommand(hue:sat:brr:)
      → CommandPatternParser.buildCommand(pattern, values)
        → Data([0x78, 0x89, ...])  // raw BLE packet
      → peripheral.writeValue(data, for: ctlCharacteristic)
        → [Light hardware executes command]
```

**Light reports state change → UI updates:**
```
CBPeripheral notification (GATT characteristic)
  → NeewerLight.parseNotification(data)
    → Observable<Int>.value = newBrightness  (triggers didSet)
      → DeviceViewObject binding closure
        → DispatchQueue.main.async { view.updateSlider() }
```

---

## BLE Protocol & Light Communication

> **See also:** [Neewer-Light-Protocol.md](Neewer-Light-Protocol.md) (raw packet captures & reverse-engineering notes) · [Neewer-Home-Protocol.md](Neewer-Home-Protocol.md) (Neewer Home app protocol)

### Service & Characteristics

All Neewer lights use a single BLE service with two characteristics:

| UUID | Name | Direction |
|------|------|-----------|
| `69400001-B5A3-F393-E0A9-E50E24DCCA99` | Service | — |
| `69400002-B5A3-F393-E0A9-E50E24DCCA99` | Control | App → Light (write) |
| `69400003-B5A3-F393-E0A9-E50E24DCCA99` | GATT | Light → App (notify) |

### Command Protocol

Every command is a `[0x78] [tag] [payload...] [checksum]` packet. Tags include power (`0x81`), CCT (`0x87`), HSI (`0x89`), scene (`0x88`), and others. Checksum is XOR of all preceding bytes. See [Neewer-Light-Protocol.md](Neewer-Light-Protocol.md) for packet format details, worked examples, and the full tag reference.

### Command Pattern Templates

Instead of hardcoding commands per light model, the database defines templates like `"{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"`. Tokens include variables with types and constraints (`{var:type:constraint}`), auto-calculated `{size}`, and literal hex values. `CommandPatternParser.buildCommand(from:values:)` takes a template + a dictionary of values and returns the raw `Data` packet.

See [Command-Patterns.md](Command-Patterns.md) for the full template grammar, token types, and worked examples.

### Discovery

The app discovers lights by scanning for BLE peripherals whose advertised name contains any of: `"nwr"`, `"neewer"`, `"nee"`, `"sl"`, `"nw-"` (case-insensitive). Once found, it connects, discovers the service/characteristics above, and wraps the peripheral in a `NeewerLight` model.

### Keep-Alive

A timer fires every **10 seconds** per connected light, sending a read request on the GATT characteristic. If the read fails (no response), `connectionBreakCounter` increments. After 2+ failures, the light is shown as disconnected (grayed out with `BlockingOverlayView`).

---

## Model Layer

### NeewerLight (`Model/NeewerLight.swift`)

The core model representing a single physical LED light. Holds:

- **BLE state**: `peripheral: CBPeripheral`, `deviceCtlCharacteristic`, `gattCharacteristic`
- **Light state** (all `Observable<T>`): `isOn`, `brrValue`, `cctValue`, `hueValue`, `satValue`, `gmmValue`, `channel`, `sourceChannel`
- **Identity**: `userLightName`, `projectName`, `nickName`, `lightType: UInt8`
- **Capabilities**: `supportRGB`, `supportCCTGM`, `supportMusic`, `support9FX`, `support17FX`, `cctRange`
- **Sound-to-Light**: `followMusic: Bool` — whether this light follows the audio engine

**Light Modes:**

| Mode | Value | Description |
|------|-------|-------------|
| `CCTMode` | 1 | Bi-color: brightness + color temperature |
| `HSIMode` | 2 | RGB: hue + saturation + brightness |
| `SCEMode` | 3 | Scene effects (per-channel animation) |
| `SRCMode` | 4 | Light source presets (sunlight, halogen, etc.) |

**Key methods:**
- `sendPowerOnCommand()` / `sendPowerOffCommand()`  
- `sendCCTCommand(brr:cct:gm:)` — builds command from pattern, writes to BLE
- `sendHSICommand(hue:sat:brr:)` — same for RGB mode
- `sendSceneCommand(scene:brr:)` — scene effects
- `getConfig()` → `[String: CodableValue]` — serializable state for persistence
- `startLightOnNotify()` — subscribe to GATT notifications

**Persistence:** All managed lights are saved to `~/Library/Application Support/NeewerLite/MyLights.dat` as JSON. Loaded at app launch so lights reconnect automatically.

### NeewerLightConstant (`Model/NeewerLightConstant.swift`)

Static utilities for:

- **Type mapping**: BLE advertised name → light type ID (`getLightType(nickName:projectName:)`)
- **Name parsing**: Raw BLE name → (nickName, projectName) (`getLightNames(rawName:identifier:)`)
- **CCT range**: Per-type min/max Kelvin (default 32–56, extended to 85 for SL80/SL140)
- **FX/Source lookup**: `getLightFX(lightType:)`, `getLightSources(lightType:)` → arrays from database

### NeewerLightSource (`Model/NeewerLightSource.swift`)

Light source presets (Sunlight, Halogen, Tungsten, etc.) loaded from the database. Each source has:
- `id`, `name` (localized), `iconName`
- `cmdPattern` / `defaultCmdPattern` — BLE command templates
- `needBRR`, `needCCT`, `needGM` — which sliders to show
- `featureValues` — per-source parameter dictionary
- `defaultCCTValue`, `defaultGMValue` — factory-set defaults (not persisted via Codable), reset on each source selection so slider changes don't permanently mutate the preset

10 factory presets with calibrated CCT/GM defaults: Sunlight (56K/+4), White Halogen (32K/+2), Xenon short-arc (60K/−8), Horizon daylight (25K/+8), Daylight (55K/0), Tungsten (32K/−4), Studio Bulb (34K/−2), Modeling Lights (45K/0), Dysprosic (58K/−6), HMI6000 (60K/+2).

### Command (`Model/Command.swift`)

URL scheme command routing. Defines:

- `CommandType` enum: `turnOnLight`, `turnOffLight`, `toggleLight`, `scanLight`, `setLightHSI`, `setLightCCT`, `setLightScene`
- `CommandParameter`: extracts typed values from URL query strings (`?light=KeyLight&CCT=5600&Brightness=100`)
- `CommandHandler`: registry of (name → action closure), dispatches URL events
- `ControlTag` enum: UI control identifiers (brr=10, cct=11, hue=13, sat=14, etc.)
- `TabId` enum: tab identifiers ("cctTab", "hsiTab", "gelTab", "sourceTab", "sceTab")

### NeewerGel (`Model/NeewerGel.swift`)

39 professional gel presets loaded from the database. Each gel has:
- `hue`, `saturation`, `transmissionPercent`, `mireds`
- `category`: ColorCorrection, Creative, or Diffusion
- `manufacturer`, `code` (e.g., Lee 201)

**Multi-gel stacking** uses physically-based math:
- RGB multiplication (subtractive mixing)
- Mired addition (color temp shifts add linearly)
- Transmission compounding

### CommandPatternParser (`Model/CommandPatternParser.swift`)

The template engine that turns pattern strings + value dictionaries into raw BLE `Data` packets. Handles type encoding (`uint8`, `uint16_le/be`), range clamping, enum mapping, checksum calculation. This is the bridge between the database-defined patterns and actual BLE writes.

---

## View Layer

### MVVM Pattern

```
NeewerLight (Model)
    ↕  Observable<T> bindings
DeviceViewObject (ViewModel)
    ↕  IBOutlet / direct reference
CollectionViewItem (View)
```

### DeviceViewObject (`ViewModels/DeviceViewObject.swift`)

The binding layer between `NeewerLight` and the UI. One created per managed light. Responsibilities:

- Binds all Observable properties to UI update closures (dispatched to main queue)
- Exposes action methods: `turnOnLight()`, `changeToMode()`, `updateHSI()`, `updateCCT()`
- Tracks per-device UI state: selected tab, current mode, follow-music flag

### CollectionViewItem (`Views/CollectionViewItem.swift`)

The main per-light control card (~1800 lines). This is the most complex view in the app. Each instance represents one connected light, displayed in a grid layout.

**Layout (520×300px):**
```
┌──────────────────────────────────────────────┐
│ ┌──────────┐  ┌────────────────────────────┐ │
│ │          │  │  [CCT] [HSI] [Gel] [Src]   │ │
│ │  Product │  │  [FX]                      │ │
│ │  Image   │  │                            │ │
│ │          │  │   (Tab content area)       │ │
│ │          │  │   Sliders, color wheel,    │ │
│ │          │  │   gel swatches, FX params   │ │
│ │          │  │                            │ │
│ ├──────────┤  └────────────────────────────┘ │
│ │ LightName│                                 │
│ │ [🔌][🎵]│                                 │
│ │ [⚙️]    │                                 │
│ └──────────┘                                 │
└──────────────────────────────────────────────┘

Left panel (0–140px): image, name, power switch, follow-music 🎵, gear menu
Right panel (140–520px): NSTabView with mode-specific controls
```

**Tab building is dynamic** — `buildView()` inspects light capabilities and only adds supported tabs. A CCT-only light won't get HSI or Gel tabs.

**Key tabs:**
- **CCT**: brightness slider + color temperature slider (+ optional GM slider)
- **HSI**: color wheel or hue slider + saturation + brightness
- **Gel**: category picker + gel swatch grid (39 presets) + multi-stack UI
- **Light Source**: preset buttons (Sunlight, Halogen, Tungsten, etc.)
- **FX/Scene**: channel dial + per-effect parameter sliders

### Other Views

| File | Purpose |
|------|---------|
| `CollectionViewItem+Gels.swift` | Gel tab: filtering, stacking UI, swatch selection |
| `ColorWheel.swift` | Interactive HSV color wheel with handle dragging |
| `FXView.swift` | Scene effect parameter editor (speed, sparks, color picks) |
| `GelSwatchCell.swift` | Individual gel color swatch in the grid |
| `NLSlider.swift` | Custom slider control used for brightness, CCT, etc. |
| `PatternEditorPanel.swift` | Advanced panel for editing BLE command patterns (for unsupported lights) |
| `RenameViewController.swift` | Light rename dialog |
| `MyLightTableCellView.swift` | Table cell in the Scan View list |
| `BlockingOverlayView.swift` | Gray overlay shown when a light disconnects |
| `LogMonitorViewController.swift` | Debug log viewer panel |
| `RoundedScrollView.swift` | Styled scroll view |

### MainMenu.xib

Defines the app's window structure with multiple views:

| View | Name | Purpose |
|------|------|---------|
| `view0` | Scan View | BLE discovery, list of found lights |
| `view1` | Control View | Per-light grid (NSCollectionView of `CollectionViewItem`) |
| `view2` | Music View | Sound-to-Light controls + spectrogram visualization |
| `view3` | Screen View | Reserved |

The Music View (view2) layout at 639×424:
- Top row (~y=379): "Listen" label, audio on/off switch, visualization popup
- Controls row (~y=345): Mode | Reactivity | Palette | Preset dropdowns
- Visualization area (~y=37, 549×295): Spectrogram/waveform/spectrum display

---

## Sound-to-Light System

> **See also:** [Sound-to-Light-Engine.md](Sound-to-Light-Engine.md) (design & architecture) · [Sound-to-Light-Technical-Report.md](Sound-to-Light-Technical-Report.md) (algorithm details & benchmarks)

The Sound-to-Light system turns live audio into real-time lighting commands. The pipeline:

```
Microphone → AudioSpectrogram → AudioAnalysisEngine → SoundToLightMode → BLESmartThrottle → BLE
  (44.1kHz)    (mel spectrum)     (features + beats)    (light commands)   (rate limit)     (write)
```

### AudioSpectrogram (`Spectrogram/AudioSpectrogram.swift`)

Captures system audio via AVFoundation and produces a 60-bin mel-spectrogram at ~46 Hz (44.1 kHz → 1024-point FFT → 60 mel filters → log-scale power).

### AudioAnalysisEngine (`Spectrogram/AudioAnalysisEngine.swift`)

Extracts musical features from the raw mel spectrum. Output: `AudioFeatures` struct with per-band energy (bass/mid/high), spectral flux, beat detection (`isBeat`, `beatIntensity`), BPM estimation, and `overallEnergy`. Uses AGC with slow decay, half-wave rectified spectral flux, and adaptive beat thresholding.

### SoundToLightMode (`Spectrogram/SoundToLightMode.swift`)

Protocol for mapping `AudioFeatures` → `LightCommand`. Three built-in modes:

- **PulseMode** — Beat-driven brightness pulsing (HSI or CCT)
- **ColorFlowMode** — Frequency-to-hue mapping via `ColorPalette` warm/cool endpoints (HSI only)
- **BassCannonMode** — Bass-driven intensity spikes with beat overlays (HSI only)

Each mode is configured with a `Reactivity` level (Subtle → Extreme) that scales sensitivity, decay, and smoothing. Six presets combine mode + reactivity + palette for common scenarios (DJ Booth, Film Score, Rock Concert, etc.).

### BLESmartThrottle

Rate-limits BLE writes to prevent saturating the radio. Skips sends under 67ms apart; forces send after 200ms heartbeat; otherwise only sends if perceptual change (brightness, hue, saturation, CCT) exceeds thresholds.

For full details on the audio pipeline, feature extraction, per-mode algorithms, noise gate design, and reactivity/palette/preset tables, see [Sound-to-Light-Engine.md](Sound-to-Light-Engine.md). For industry comparison and competitive positioning, see [Sound-to-Light-Technical-Report.md](Sound-to-Light-Technical-Report.md).

---

## External Integration

> **See also:** [Integrate-with-shortcut.md](Integrate-with-shortcut.md) (macOS Shortcuts walkthrough)

### URL Scheme (`neewerlite://`)

Registered in Info.plist. Commands:

```bash
# Power
neewerlite://turnOnLight[?light=<name>]
neewerlite://turnOffLight[?light=<name>]
neewerlite://toggleLight[?light=<name>]

# CCT mode
neewerlite://setLightCCT?CCT=<3200-8500>&Brightness=<0-100>[&GM=<-50 to 50>][&light=<name>]

# HSI mode (by RGB hex or by hue)
neewerlite://setLightHSI?RGB=<hex>&Saturation=<0-100>&Brightness=<0-100>[&light=<name>]
neewerlite://setLightHSI?HUE=<0-360>&Saturation=<0-100>&Brightness=<0-100>[&light=<name>]

# Scene effects
neewerlite://setLightScene?Scene=<name>&Brightness=<0-100>[&light=<name>]
# Scene names: SquadCar, Ambulance, FireEngine, Firework, Party, CandleLight, Lightning, Paparazzi, TVScreen

# Rescan
neewerlite://scanLight
```

If `light` is omitted, the command targets all connected lights.

### HTTP Server (port 18486)

The server (built on Vapor) hosts both the Stream Deck HTTP API and a Model Context Protocol (MCP) endpoint.

**Stream Deck HTTP routes** (require `User-Agent: neewerlite.sdPlugin/*`):

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/sd/listLights` | GET | JSON array of connected lights with state |
| `/sd/ping` | GET | Health check (`{"status": "pong"}`) |
| `/sd/switch` | POST | Toggle lights by ID/name |
| `/sd/setLight` | POST | Set light parameters (CCT/HSI/Scene) |

**MCP endpoint** (`POST /mcp`):

Exposes light control to AI assistants and automation tools via the [Model Context Protocol](https://modelcontextprotocol.io). Uses `StatefulHTTPServerTransport` from the MCP Swift SDK.

| Tool | Description |
|------|-------------|
| `list_lights` | List all lights with state, mode, and capabilities |
| `turn_on` | Turn on lights by name/index |
| `turn_off` | Turn off lights by name/index |
| `set_light_cct` | Set CCT mode (brightness, color temperature, GM) |
| `set_light_hsi` | Set HSI mode (hue, saturation, brightness) |
| `set_light_scene` | Set scene effect by name |
| `get_light_image` | Get product image for a light |
| `scan` | Trigger BLE scan for new lights |
| `get_logs` | Retrieve recent app logs |

The server can be enabled/disabled from Settings (persisted as `HTTPServerEnabled` in UserDefaults, defaults to on).

### Custom NSApplication

`NeewerLiteApplication` subclass suppresses app activation when triggered via URL scheme — the app stays in the menu bar without stealing focus.

---

## Stream Deck Plugin

> **See also:** [Integrate-with-streamdeck.md](Integrate-with-streamdeck.md) (setup & usage guide)

Located in `NeewerLiteStreamDeck/`. TypeScript-based Elgato Stream Deck plugin.

**Stack:** TypeScript 5.8 + Rollup + Terser → `com.beyondcow.neewerlite.sdPlugin` bundle

**Communication:** HTTP to `localhost:18486` via `ipc.ts` (matches Server.swift endpoints).

**Actions:**

| Action | Type | Control |
|--------|------|---------|
| Switch | Key press | Toggle lights on/off |
| Brightness | Encoder dial | Adjust brightness |
| CCT Key | Key press | Set color temperature preset |
| Temperature | Encoder dial | Adjust CCT continuously |
| Hue | Encoder dial | Adjust hue |
| Saturation | Encoder dial | Adjust saturation |
| FX Key | Key press | Select scene effect |

**Build:**
1. `./build.sh` extracts `SDPluginVersion` from app's Info.plist
2. Updates plugin `manifest.json` version to match
3. `npm run build` compiles TypeScript
4. `streamdeck validate` + `streamdeck pack` produces `.streamDeckPlugin`

---

## Light Database

> **See also:** [Gels.md](Gels.md) (gel filter system design & subtractive color mixing)

### Schema (`Database/lights.json`, version 3.0)

Two top-level arrays: `lights` (60+ entries) and `gels` (39 entries).

**Light entry:**
```json
{
  "type": 3,                           // Unique light type ID (uint8)
  "image": "<GitHub raw URL>",         // Product photo
  "link": "<product URL>",
  "supportRGB": true,
  "supportCCTGM": false,
  "supportMusic": false,
  "support9FX": true,
  "support17FX": false,
  "cctRange": { "min": 32, "max": 56 },  // Neewer units (×100 = Kelvin)
  "newPowerLightCommand": false,
  "newRGBLightCommand": false,
  "commandPatterns": {
    "power": "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}",
    "cct": "...",
    "hsi": "..."
  },
  "sourcePatterns": [ ... ],           // Light source presets
  "fxPatterns": [ ... ]                // Scene effects
}
```

**Database loading:**
1. Bundled fallback in `Resources/lights_db.json`
2. On launch, fetches from `beyondcow.com/neewerlite/lights_db.json`
3. Cached to `~/Library/Application Support/NeewerLite/`
4. Re-fetched every 12 hours

### Adding a New Light

1. Use a BLE scanner to find the light's advertised Bluetooth name
2. Add name-to-type mapping in `Database/lights.json`
3. Define `commandPatterns` (use an existing similar light as template)
4. Set capability flags (`supportRGB`, `cctRange`, etc.)
5. Add product image to `Database/light_images/`
6. Push to GitHub — every user gets the update automatically (no app update needed)

---

## Testing

**222 tests**, all under `NeewerLiteTests/`:

| File | Tests | Coverage |
|------|-------|---------|
| `NeewerLiteTests.swift` | 3 | Light name parsing, type mapping from BLE names |
| `CommandParserTests.swift` | 57 | BLE command generation: power, CCT, HSI, range validation, checksum |
| `AudioAnalysisEngineTests.swift` | 45 | Silence, per-band isolation, AGC, beat detection, spectral flux |
| `SoundToLightModeTests.swift` | 47 | PulseMode, ColorFlowMode, BassCannon, reactivity scaling, palette, presets |
| `GelsTests.swift` | 24 | Subtractive mixing, mired addition, transmission compounding |
| `MCPServerTests.swift` | 34 | MCP tool discovery, Value numeric coercion, tool metadata |
| `StringLocalizedTests.swift` | 12 | Localization string lookups and fallbacks |

**Run:**
```bash
cd NeewerLite/NeewerLite
xcodebuild test -project NeewerLite.xcodeproj -scheme NeewerLite -destination 'platform=macOS'
```

---

## CI / Release Pipeline

### Xcode Cloud (CI)

Scripts in `ci_scripts/`:
- `ci_post_clone.sh` — dependency setup
- `ci_pre_xcodebuild.sh` — pre-build configuration
- `ci_post_xcodebuild.sh` — post-build packaging

### Release

```bash
cd Tools

# 1. Build archive + DMG
./build.sh

# 2. Validate code signing & notarization
./validate.sh

# 3. Publish to GitHub Releases + update Sparkle appcast
./publish.sh
```

Auto-update uses [Sparkle](https://github.com/sparkle-project/Sparkle). The feed is `appcast.xml` at repo root. `Tools/generate_appcast` regenerates it from the latest release.

---

## Key Patterns & Conventions

### Observable Bindings

```swift
// Model
class NeewerLight {
    let brrValue = Observable<Int>(0)
}

// ViewModel binds model to view
device.brrValue.bind { [weak self] val in
    DispatchQueue.main.async {
        self?.view?.updateBrightnessSlider(val)
    }
}

// Setting a value triggers the binding
device.brrValue.value = 75  // → slider animates to 75
```

### UserDefaults Keys

| Key | Type | Purpose |
|-----|------|---------|
| `"stlMode"` | String | Sound-to-Light mode type (pulse/colorFlow/bassCannon) |
| `"stlReactivity"` | Int | Reactivity level (0–3) |
| `"stlPalette"` | Int | Color palette index (-1 = default) |

### Factory Pattern for Modes

```swift
enum SoundToLightModeType {
    case pulse, colorFlow, bassCannon

    func createMode(reactivity: Reactivity, palette: ColorPalette?) -> SoundToLightMode
}
```

### File Naming

- Model types: `NeewerLight.swift`, `NeewerGel.swift`
- Extensions: `CollectionViewItem+Gels.swift`
- ViewModels: `DeviceViewObject.swift`
- Constants go in `*Constant.swift` files

### Logging

```swift
Logger.log(.bluetooth, "Connected to \(lightName)")
// Tags: .app, .click, .bluetooth, .wifi, .heart, .server
```

Logs are written to `~/Library/Application Support/NeewerLite/Logs/` and batch-uploaded.

---

## Common Tasks

### "I want to add a new UI control to the per-light card"

1. Open `CollectionViewItem.swift`
2. Find the relevant `build*View()` method (e.g., `buildHSIView()` for HSI tab)
3. Add your NSControl programmatically (most controls are code-driven, not XIB)
4. Wire the action to the view, which delegates to `DeviceViewObject`, which calls `NeewerLight`

### "I want to add a new Sound-to-Light mode"

1. Create a struct conforming to `SoundToLightMode` in `SoundToLightMode.swift`
2. Implement `process(_ features: AudioFeatures) -> LightCommand`
3. Add a case to `SoundToLightModeType` enum
4. Update `createMode()` factory
5. The mode auto-appears in the Music View dropdown (AppDelegate reads the enum)
6. Add tests in `SoundToLightModeTests.swift`

### "I want to support a new Neewer light model"

Zero code changes needed:
1. Add entry to `Database/lights.json`
2. Define `commandPatterns`, capability flags, `cctRange`
3. Push to GitHub — the app fetches the updated DB automatically

### "I want to add a new HTTP endpoint"

1. Open `Server.swift`
2. For Stream Deck routes: add handler in the `/sd` group (auth middleware applies)
3. For MCP tools: add a `Tool` entry in `registerMCPTools()` and a handler in the tool dispatch switch
4. Update Stream Deck plugin `ipc.ts` if the SD plugin should use it

### "I want to add a new URL scheme command"

1. Add a case to `CommandType` in `Command.swift`
2. Register the handler in `AppDelegate` (search for `commandHandler.register`)
3. Implement the action closure
4. Document in README.md

### "Where do I look when a light doesn't respond?"

1. Check `Logger` output (or `LogMonitorViewController` in-app)
2. Verify the command pattern in `Database/lights.json` for that light type
3. Use `PatternEditorPanel` (in-app gear menu) to inspect/edit patterns
4. Check `NeewerLightConstant.getLightType()` — is the BLE name recognized?
5. Check `connectionBreakCounter` — has the keep-alive detected a disconnect?

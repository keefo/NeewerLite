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
- [Swifter](https://github.com/httpswift/swifter) — Lightweight HTTP server
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
│   │   ├── Server.swift            ← HTTP API (localhost:18486)
│   │   │
│   │   ├── Model/                  ← Data model
│   │   │   ├── NeewerLight.swift           ← Core light model + BLE comms
│   │   │   ├── NeewerLightConstant.swift   ← BLE constants, type mapping
│   │   │   ├── NeewerLightFX.swift         ← Scene effect definitions
│   │   │   ├── NeewerLightSource.swift     ← Light source presets
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
│       └── GelsTests.swift                 ← Gel stacking math
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
│  │ (BLE scan &   │  │  │ (HTTP API    │  │  │ (Light DB,      ││
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

### Service & Characteristics

All Neewer lights use a single BLE service with two characteristics:

| UUID | Name | Direction |
|------|------|-----------|
| `69400001-B5A3-F393-E0A9-E50E24DCCA99` | Service | — |
| `69400002-B5A3-F393-E0A9-E50E24DCCA99` | Control | App → Light (write) |
| `69400003-B5A3-F393-E0A9-E50E24DCCA99` | GATT | Light → App (notify) |

### Command Packet Format

Every command follows the same structure:
```
[0x78] [tag] [payload_size] [payload...] [checksum]
  │      │        │              │            │
  │      │        │              │            └─ XOR of all preceding bytes
  │      │        │              └─ Variable-length payload
  │      │        └─ Number of payload bytes (uint8)
  │      └─ Command tag (power=0x81, cct=0x83, hsi=0x89, etc.)
  └─ Fixed prefix (always 0x78 = 120)
```

**Example — Power On:**
```
0x78  0x81  0x01  0x01  0xFB
 │     │     │     │     └─ checksum: 0x78 ^ 0x81 ^ 0x01 ^ 0x01 = 0xFB
 │     │     │     └─ state: 1 = ON
 │     │     └─ payload size: 1 byte
 │     └─ power tag
 └─ prefix
```

**Example — Set HSI (hue=120°, sat=80%, brr=50%):**
```
0x78  0x89  0x04  0x78 0x00  0x50  0x32  [checksum]
 │     │     │     │         │     │
 │     │     │     │         │     └─ brightness: 50 (0x32)
 │     │     │     │         └─ saturation: 80 (0x50)
 │     │     │     └─ hue: 120 as uint16_le (0x0078)
 │     │     └─ payload: 4 bytes
 │     └─ HSI tag
 └─ prefix
```

### Command Tags

| Tag | Hex | Purpose |
|-----|-----|---------|
| Power | `0x81` | On/Off |
| CCT Long Brr | `0x82` | Extended CCT brightness |
| CCT Long CCT | `0x83` | Extended CCT temperature |
| RGB (legacy) | `0x86` | Old RGB format |
| CCT | `0x87` | Standard CCT |
| Scene | `0x88` | Scene effects |
| HSI | `0x89` | HSI mode (hue/sat/brr) |
| CCT Data | `0x90` | Continuous CCT data |
| RGB (new) | `0x8F` | New RGB format |

### Command Pattern Templates

Instead of hardcoding commands per light model, the database defines templates:

```
"{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"
"{cmdtag} {ccttag} {size} {brr:uint8:range(0,100)} {cct:uint8:range(32,56)} 0x32 0x00 0x00 {checksum}"
"{cmdtag} {hsitag} {size} {hue:uint16_le:range(0,360)} {sat:uint8:range(0,100)} {brr:uint8:range(0,100)} {checksum}"
```

**Token types:**
- `{cmdtag}` → always `0x78`
- `{powertag}`, `{ccttag}`, `{hsitag}` → resolved from database
- `{size}` → auto-calculated payload length
- `{var:type:constraint}` — variable with type (`uint8`, `uint16_le`, `uint16_be`, `hex`) and constraint (`range(min,max)`, `enum(...)`, `bits(...)`)
- `{checksum}` → XOR of all preceding bytes
- Literal hex like `0x32` → inserted as-is

`CommandPatternParser.buildCommand(from:values:)` takes a template + a dictionary of values and returns the raw `Data` packet.

### Discovery

The app discovers lights by scanning for BLE peripherals whose advertised name contains any of: `"nwr"`, `"neewer"`, `"nee"`, `"sl"`, `"nw-"` (case-insensitive). Once found, it connects, discovers the service/characteristics above, and wraps the peripheral in a `NeewerLight` model.

### Keep-Alive

A timer fires every **10 seconds** per connected light, sending a read request on the GATT characteristic. If the read fails (no response), `connectionBreakCounter` increments. After 2+ failures, the light is shown as disconnected (grayed out with `BlockingOverlayView`).

---

## Model Layer

### NeewerLight (`Model/NeewerLight.swift`)

The core model representing a single physical LED light. Holds:

- **BLE state**: `peripheral: CBPeripheral`, `deviceCtlCharacteristic`, `gattCharacteristic`
- **Light state** (all `Observable<T>`): `isOn`, `brrValue`, `cctValue`, `hueValue`, `satValue`, `gmmValue`, `channel`
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

The Sound-to-Light system turns live audio into real-time lighting commands. The pipeline:

```
Microphone → AudioSpectrogram → AudioAnalysisEngine → SoundToLightMode → BLESmartThrottle → BLE
  (44.1kHz)    (mel spectrum)     (features + beats)    (light commands)   (rate limit)     (write)
```

### AudioSpectrogram (`Spectrogram/AudioSpectrogram.swift`)

Captures system audio via AVFoundation and produces a 60-bin mel-spectrogram at ~46 Hz.

**Pipeline:**
1. **AVCaptureSession** captures audio at 44.1 kHz
2. **1024-point FFT** via vDSP (Accelerate framework)
3. **60 triangular mel filters** spanning 20 Hz – 20 kHz
4. **Log-scale power** with 50 dB floor
5. Fires `frequencyUpdateCallback([Float])` ~46 times/second

Also provides:
- `volumeUpdateCallback` — system volume level
- `amplitudeUpdateCallback` — microphone RMS
- `audioSpectrogramImageUpdateCallback` — waterfall CGImage (expensive, togglable)

### AudioAnalysisEngine (`Spectrogram/AudioAnalysisEngine.swift`)

Extracts musical features from the raw mel spectrum. Input: 60-bin array × ~46 Hz. Output: `AudioFeatures` struct.

**AudioFeatures:**

| Field | Range | Description |
|-------|-------|-------------|
| `bassEnergy` | 0–1 | Bins 0–7 (~20–250 Hz) |
| `midEnergy` | 0–1 | Bins 8–25 (~250–2 kHz) |
| `highEnergy` | 0–1 | Bins 26–59 (~2–20 kHz) |
| `bassFlux`, `midFlux`, `highFlux` | 0+ | Spectral flux (onset detection per band) |
| `isBeat` | bool | Onset detected this frame |
| `beatIntensity` | 0–1 | Strength of current beat |
| `bpm` | 0–300 | Estimated BPM (0 if not locked) |
| `beatPhase` | 0–1 | Position in beat cycle |
| `overallEnergy` | 0–1 | Weighted mix of all bands |

**Key processing:**
- **AGC**: Per-band peak tracking with slow decay (0.997 per frame ≈ 7.5s half-life)
- **Spectral Flux**: L1 difference with half-wave rectification (only increases count)
- **Beat Detection**: Flux peaks exceeding threshold × sensitivity, min 200ms between beats
- **BPM Estimation**: From last 16 beat timestamps

### SoundToLightMode (`Spectrogram/SoundToLightMode.swift`)

Protocol for mapping `AudioFeatures` → `LightCommand`. Three built-in modes:

**PulseMode** — Beat-driven brightness pulsing
- On beat: brightness spikes proportional to `beatIntensity × reactivity.sensitivity`
- Between beats: exponential decay (rate scaled by `reactivity.decayScale`)
- Works with both HSI and CCT lights
- Fixed warm amber hue (30°, sat 0.7)

**ColorFlowMode** — Frequency-to-hue mapping
- Bass-dominant → warm hue (e.g. red at 20°)
- Highs-dominant → cool hue (e.g. blue at 260°)
- Hue range customizable via `ColorPalette` (warmHue/coolHue)
- HSI only (needs color control)

**BassCannonMode** — Bass-driven intensity spikes
- Bass energy drives brightness with heavy smoothing
- Beat events trigger spike overlays
- Tight hue range (warm red/orange)
- HSI only

**LightCommand output:**

| Field | Range | Mode |
|-------|-------|------|
| `hue` | 0–360° | HSI |
| `saturation` | 0–1 | HSI |
| `brightness` | 0–1 | All |
| `cct` | 32–85 (Neewer units) | CCT |
| `gm` | -50–50 | CCT+GM |
| `isHSI` | bool | Mode flag |

### Reactivity

Four levels that scale how modes respond to audio:

| Level | Sensitivity | Decay Scale | Floor Scale | Smoothing |
|-------|-------------|-------------|-------------|-----------|
| Subtle | 0.3 | 0.5 | 2.0 | 0.95 |
| Moderate | 1.0 | 1.0 | 1.0 | 0.85 |
| Intense | 1.5 | 1.5 | 0.6 | 0.7 |
| Extreme | 2.0 | 2.0 | 0.3 | 0.5 |

### ColorPalette

Defines warm/cool hue endpoints for ColorFlowMode:

| Palette | Warm Hue | Cool Hue |
|---------|----------|----------|
| Sunset | 0° | 320° |
| Ocean | 180° | 260° |
| Neon | 300° | 180° |
| Fire | 0° | 50° |
| Forest | 80° | 160° |

### Presets

Pre-configured combinations of mode + reactivity + palette:

| Preset | Mode | Reactivity | Palette |
|--------|------|------------|---------|
| DJ Booth | Pulse | Intense | Neon |
| Film Score | ColorFlow | Subtle | Sunset |
| Rock Concert | BassCannon | Extreme | Fire |
| Worship | ColorFlow | Moderate | Ocean |
| Party | ColorFlow | Intense | Neon |
| Podcast | Pulse | Subtle | Default |

### BLESmartThrottle

Rate-limits BLE writes to prevent saturating the radio. Per-device tracking:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `minSendInterval` | 67ms (~15 Hz) | Hard rate limit |
| `heartbeatInterval` | 200ms | Always send if this long since last send |
| `brightnessThreshold` | 0.03 | Min brightness Δ to trigger send |
| `hueThreshold` | 5° | Min hue Δ |
| `satThreshold` | 0.05 | Min saturation Δ |
| `cctThreshold` | 2 units | Min CCT Δ |

Logic: skip if under `minSendInterval`. Force send if past `heartbeatInterval`. Otherwise, only send if perceptual change exceeds thresholds.

---

## External Integration

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

For Stream Deck plugin and programmatic control:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/listLights` | GET | JSON array of connected lights with state |
| `/ping` | GET | Health check (`{"status": "pong"}`) |
| `/switch` | POST | Toggle lights by ID/name |
| `/setLight` | POST | Set light parameters (CCT/HSI/Scene) |

**Authentication:** All requests must include `User-Agent: neewerlite.sdPlugin/*` header.

### Custom NSApplication

`NeewerLiteApplication` subclass suppresses app activation when triggered via URL scheme — the app stays in the menu bar without stealing focus.

---

## Stream Deck Plugin

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

**103 tests**, all under `NeewerLiteTests/`:

| File | Tests | Coverage |
|------|-------|----------|
| `NeewerLiteTests.swift` | ~18 | Light name parsing, type mapping from BLE names |
| `CommandParserTests.swift` | ~25 | BLE command generation: power, CCT, HSI, range validation, checksum |
| `AudioAnalysisEngineTests.swift` | ~24 | Silence, per-band isolation, AGC, beat detection, spectral flux |
| `SoundToLightModeTests.swift` | ~33 | PulseMode, ColorFlowMode, BassCannon, reactivity scaling, palette, presets |
| `GelsTests.swift` | ~3 | Subtractive mixing, mired addition, transmission compounding |

**Run:**
```bash
cd NeewerLite/NeewerLite
xcodebuild test -project NeewerLite.xcodeproj -scheme NeewerLiteTests -destination 'platform=macOS'
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
2. Add route handler (follow existing `/listLights` pattern)
3. Remember to respect the User-Agent authentication middleware
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

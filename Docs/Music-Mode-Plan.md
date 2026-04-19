# Feature Plan: Onboard Music Mode for NH Lights

**Scope:** Enable NeewerLite to activate and control the **built-in music reactive mode** on Neewer Home (NH) lights that have an onboard microphone.  
**Availability:** Only shown when the device's `supportMusic == true` in the lights database.  
**Purpose:** Let users switch an NH light into mic-driven music mode — where the light's own hardware listens to ambient audio and drives LED animations locally — without needing the NEEWER Home iOS/Android app.

---

## Background: Two Kinds of "Music Mode"

NeewerLite already has a **Sound-to-Light (STL)** engine that uses the Mac's microphone, analyzes audio via FFT, and sends standard HSI/CCT commands to any connected light at ~46 Hz. This is a host-driven pipeline — the light is passive, just receiving colour commands.

NH lights with `supportMusic: true` have a completely separate capability: an **onboard microphone** and firmware-level audio processing. The light listens to ambient sound and animates LEDs locally. The host app only needs to send a single BLE command to configure the mode, speed, sensitivity, and colour palette — then the light runs autonomously.

| Aspect | Sound-to-Light (existing) | Onboard Music Mode (this plan) |
|--------|--------------------------|-------------------------------|
| Audio source | Mac microphone | Light's built-in mic |
| Processing | Mac CPU (vDSP FFT @ 46 Hz) | Light firmware |
| BLE traffic | Continuous (~46 commands/sec) | One-shot config command |
| Latency | Mac → BLE → light (~20–50 ms) | Near-zero (on-device) |
| Light types | Any light (CCT, HSI, FX) | NH lights with `supportMusic` only |
| Colour control | Full (app computes each frame) | Limited (preset palette) |
| Mac dependency | Requires Mac mic + app running | Light runs independently after config |

Both features should coexist. A user might prefer STL for precise, host-controlled lighting, or onboard music mode for zero-latency autonomous operation (e.g., at a party where the Mac isn't nearby).

---

## Protocol Summary

Full protocol details are in [NeewerHome-Protocol.md](NeewerHome-Protocol.md) under "Music Reactive Mode".

**Command:** Standard Packet, dataId `0x0E`

```
7A 0E [size] 01 00 [brr] [mode] [speed] [sens] [colorMode] [colorCount] [colors...] [gradient] [checksum]
```

**6 music modes:**

| ID | Name | Speed control | Notes |
|----|------|:---:|-------|
| 0 | Energy | ✓ | Reactive energy pulse |
| 1 | Breathing | ✓ | Slow fade in/out synced to audio |
| 2 | Beat | ✓ | Sharp flash on beat detection |
| 3 | Meteor | ✓ | Streak/trail animation |
| 4 | Starry Sky | ✓ | Twinkling points |
| 5 | Neon | ✗ | Neon glow effect |

**Parameters:** brightness (0–100%), speed (1–100), sensitivity (1–100), color mode (auto/custom), up to 8 custom colors (hue + saturation), gradient on/off.

---

## Device Support

From `lights.json`:

- **28 of 32** NH devices have `supportMusic: true`
- **3 devices** (NF02, NF05, NW01) additionally have `twoDimensionalMusic: true` — likely a 2D matrix music animation variant (needs investigation)
- **4 devices** have `supportMusic: false` — these lack onboard mics

The `supportMusic` flag is already in the JSON database and decoded into `HomeDevice` / `NeewerLightDbItem` structs, but **currently unused in app logic**.

---

## Current State

| Component | Status | What exists |
|-----------|--------|-------------|
| Protocol | ✅ Fully decoded | BLE packet format documented, all 6 modes verified via traces |
| Database | ✅ Complete | `supportMusic` flag + `musicPreset` key on 28 NH devices, `nh_music` preset group (6 modes) in `lights.json` |
| Command generation | ✅ Implemented | `CommandPatternParser` builds packets from JSON patterns; `sendMusicCommand(_:)` on `NeewerLight` |
| Data model | ✅ Reuses NeewerLightFX | `supportedMusicFX` array loaded from `musicPreset`; `needSens` flag + `sensValue` added |
| UI | ✅ Implemented | Music tab in `CollectionViewItem` with mode picker + dynamic Speed/Sens sliders |
| Persistence | ❌ Not implemented | No save/restore of music mode settings |

---

## Implementation Plan

### Phase 1: Data-Driven Command Patterns in lights.json ✅

**Status: Complete.**

All 6 music modes are defined as an `nh_music` preset group in `lights.json`. Each mode's BLE command is a `CommandPatternParser` template with `{speed}` and `{sens}` variables (Neon bakes speed as `0x32`). Brightness is baked as `0x64` (100%). Auto rainbow colors are baked as literal hex bytes.

**Changes made:**

- **`Database/lights.json`** — Added `nh_music` preset group (6 entries) in `fxPresets`. Added `"musicPreset": "nh_music"` to all 28 NH devices with `supportMusic: true`.
- **`ContentManager.swift`** — Added `musicPreset: String?` to `HomeDevice` struct. Added `resolvedMusicPatterns(for:)` method.
- **`NeewerLightConstant.swift`** — Added `getHomeLightMusicFX(productId:)` class method.
- **`NeewerLightFX.swift`** — Added `needSens` flag, `sensValue` computed property, `sens` field parsing in `parseNamedCmdToFX`.
- **`NeewerLight.swift`** — Added `supportedMusicFX: [NeewerLightFX]` array, loaded in `_lightType` didSet. Added `sendMusicCommand(_:)` that uses `parseFields()` to discover which values to send.
- **`Command.swift`** — Added `ControlTag.sens` (22) and `TabId.music`.

#### Design decisions (preserved for reference)
- Each mode bakes the **mode ID byte** directly into its pattern (e.g., `0x02` for Beat). No enum needed.
- **Brightness** is baked as `0x64` (100%) — the official app always sends 100% and has no brightness slider in music mode.
- Auto colors (6 rainbow hues) are baked into each pattern as literal hex bytes.
- **Neon** has speed hardcoded to `0x32` (50) instead of a `{speed}` variable — `parseFields()` won't detect a speed field → no speed slider for Neon. Automatic.
- `sendMusicCommand` uses `parseFields()` to dynamically discover which values to include (not `needXxx` flags like `sendSceneCommand`).

### Phase 2: UI — Music Mode Tab ✅

**Status: Complete.**

**Changes made:**

- **`CollectionViewItem.swift`** — Added `buildMusicView(device:)` and `musicModeClicked(_:)`. Music tab appears when `supportedMusicFX` is non-empty. Mode picker (NSPopUpButton) lists all 6 modes with SF Symbol icons. Sliders are built dynamically from `parseFields()`: Speed (1–100) for modes that have `{speed}`, Sensitivity (1–100) for all modes. Selecting a mode or dragging a slider immediately sends the BLE command via `sendMusicCommand(_:)`.

### Phase 3: Persistence & Polish

1. **Save/restore** last-used music mode settings per device (UserDefaults or light state database)
2. **HTTP API** — extend `Server.swift` to accept music mode commands via the existing HTTP control interface (for Stream Deck / Shortcuts integration)
3. **`twoDimensionalMusic`** — investigate what NF02/NF05/NW01 expect differently and add support if the protocol differs

---

## Open Questions

1. ~~**Pattern vs. hardcoded command?**~~ **Resolved: Pattern.** Music modes are FX entries in `lights.json` with `cmd` patterns. Auto colors baked in as literal bytes. Mode ID baked per entry. `CommandPatternParser` handles the rest. No custom builder needed.

2. **`twoDimensionalMusic` protocol?** Three devices have this flag. Is it a different dataId, a different payload structure, or just an extra field in the same `0x0E` packet? Needs BLE trace from one of these devices.

3. **Interaction with STL:** If a light is in onboard music mode and the user also enables Sound-to-Light, the STL HSI commands would override the music mode. Should the UI warn or prevent this? Or is it fine to let STL take over (since it sends HSI commands that implicitly exit music mode)?

4. **Custom color editing UX:** The NEEWER Home app has a multi-color palette editor. What's the minimum viable UX for NeewerLite? Options:
   - Auto-only (no custom colors) — simplest, covers the main use case
   - Preset palettes (warm, cool, party, etc.) — medium complexity
   - Full per-color hue/sat editor — most flexible, most work

5. **Speed range for Neon:** Does the firmware ignore the speed byte, or does it have an effect that the NEEWER Home app simply doesn't expose? A quick test (send Neon with speed=1 vs speed=100) would answer this.

---

## Dependencies

- None external. All BLE protocol work is internal.
- Builds on the existing NH device support (`0x7A` protocol, `HomeDevice` parsing, `NHBLECommander`).
- `supportMusic` flag already in database — no DB schema changes needed.

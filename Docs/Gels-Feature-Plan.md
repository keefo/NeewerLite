# Feature Plan: Gels Tab in Control View

**Scope:** Add a **Gels** tab to the per-device `CollectionViewItem` control panel, positioned immediately after the HSI tab.  
**Availability:** Only shown when `dev.supportRGB == true` (same gate as the HSI tab).  
**Purpose:** Let users select a named photographic gel (colour filter) from a curated library and apply it to a light in one click, without having to hand-dial hue and saturation values in the HSI tab.

---

## Background: What Is a Gel?

### The Real Thing

A **lighting gel** (short for *gelatin filter*) is a thin, transparent sheet of coloured polyester or polycarbonate film clipped or taped to the front of a light fixture. The name comes from the original material: **animal gelatin**, the same protein used in food-grade gelatine. Early 20th-century stage and film lighting industry mixed pigment dyes with liquid gelatin and poured sheets to dry — a craft process done by hand until synthetic plastics replaced it in the 1970s.

The two names you'll see everywhere today are **Lee Filters** (UK, founded 1967) and **Rosco** (US, founded 1910, now part of Rosco Laboratories). Both publish numbered swatch books — physical booklets of ~200 gels you can request for free as a gaffer or DP — and their colour numbers have become an informal industry standard. A call of *"slap a 206 on that 1K"* means: clip Lee Filter #206 (Quarter CTO) onto the 1000-watt fresnel. Everyone on the crew knows what it means without further explanation.

### A Short History

| Era | Technology | How colour was achieved |
|-----|-----------|------------------------|
| 1890s–1920s | Carbon arc / limelight | Hand-painted glass roundels; fragile, heat-shattered frequently |
| 1920s–1960s | Tungsten incandescent | Gelatin sheets; vivid colour but melted near high-wattage fixtures |
| 1970s–1990s | Tungsten / early HMI | Polyester (Mylar-based) gels; heat-resistant, consistent colour |
| 1990s–2010s | HMI, fluorescent, early LED | Polycarbonate gels; some LEDs still needed heavy physical CC gels to match HMI |
| 2010s–now | Tunable LED & RGB LED | Built-in colour mixing replaces physical gels for many corrections; gel names persist as a *vocabulary* |

Modern RGB LED panels like Neewer lights can reproduce virtually any gel effect electronically — which is exactly what this tab does.

### The Standard Families

**Colour Correction (CC) gels** are the workhorses. They shift the *colour temperature* of a light to match another source:

- **CTO (Colour Temperature Orange)** — warms a cool daylight-balanced (5600 K) LED down toward tungsten (3200 K). Available in ¼, ½, ¾, and Full strengths. "Full CTO" is roughly a 2400 K shift.
- **CTB (Colour Temperature Blue)** — the inverse: cools tungsten toward daylight. Used to make a practical lamp in a scene match window light.
- **Plus Green / Minus Green** — compensate for the green spike of fluorescent tubes and some LED fixtures. Essential when mixing LEDs with overhead office fluorescents; without it, faces go slightly greenish or magenta in a mixed frame.
- **Window Green (Full Plus Green)** — makes an LED match a fluorescent fixture closely enough that both appear neutral on the same white balance.

**Creative / Atmospheric gels** are what give films and concerts their look:

- **Bastard Amber** — warm peachy amber that doesn't read as obviously orange. The go-to for "magic hour" simulation or a cosy interior without looking like a sunset.
- **Congo Blue** — deep saturated cobalt; the staple theatrical night-blue for concert stages and drama. So commonly used it has become a cultural shorthand for "theatrical lighting."
- **Surprise Pink** — a pinkish magenta named, according to industry legend, because it "surprised" the gaffer who first used it on a music shoot. Wildly flattering on skin; ubiquitous in beauty and portrait work.
- **Urban Sodium** — mimics the orange glow of old sodium-vapour street lamps. Used in urban night scenes to make LED work match pre-LED-era reference footage.
- **Straw** — a gentle sunflower yellow. Cinematographers use it to push a fill light slightly warmer without it looking artificial.

**Diffusion gels** (white/frosted) soften and scatter light without adding colour — think of them as a portable softbox. They don't translate to a digital equivalent because diffusion is a physical optics property, not a colour shift.

### How Gels Are Described on Set

On professional sets, gels are called out by **fraction + type**: "half CTO", "quarter blue", "full plus green." The fraction describes the *intensity* of the shift — a ½ CTO moves colour temperature about halfway compared to a Full CTO. This fraction vocabulary is preserved in this app's preset names.

### Why It Matters for Digital Lights

Even though Neewer RGB panels can mix any colour, the industry still *thinks* in gel names. A director of photography who says "give me a Bastard Amber feel on that backlight" expects you to know the hue and saturation that corresponds to Lee #162 — not a raw HSI value. This tab closes that translation gap: pick the gel by name, and the app handles the numbers.

### In NeewerLite

In physical film and photography lighting, a "gel" is a coloured transparent sheet placed in front of a light fixture to shift its colour. Digital lights like Neewer RGB panels replicate this by allowing arbitrary HSI values. The problem is that real gel colours (Lee, Rosco, Cinegel standard libraries) have well-known H/S values, but users must currently memorise or look them up and manually enter them in the HSI wheel.

The Gels tab solves this by providing:

1. A **browsable preset library** of standard gel colours, grouped by category, loaded from `lights.json` (the shared database file, also used for the light catalogue).
2. A **tint-over-white-balance** mode where the gel is applied as a relative shift on top of the light's current CCT rather than replacing it.

> **Extensibility:** The gel list lives in `Database/lights.json` under the `"gels"` key. Because the app can download an updated database from GitHub, new gels can be added server-side without requiring an app update. There is no in-app UI for creating gels.

---

## Tab Position & Availability

The `TabId` enum in `Command.swift` needs a new case, and `buildView()` in `CollectionViewItem.swift` needs to insert it after HSI:

```
CCT  |  HSI  |  Gels  |  Light Source  |  FX
                ^^^^
          new — only if dev.supportRGB
```

**Rule:** If the device does not support RGB (`dev.supportRGB == false`), the Gels tab is not added to the `NSTabView`. This matches the existing HSI tab gate.

---

## Gel Library: Categories & Presets

### 1. Colour Correction (CC)

These gels compensate for the colour temperature of the ambient environment. They are the most-used gels on professional sets.

| Gel Name | Hue (°) | Saturation (%) | Notes |
|----------|---------|----------------|-------|
| CTO ¼ (Quarter Orange) | 30 | 20 | Slight warm shift; everyday talking-head warmth |
| CTO ½ (Half Orange) | 30 | 38 | Moderate warm shift |
| CTO Full | 30 | 60 | ~3200 K → 5600 K correction on daylight fixtures |
| CTB ¼ (Quarter Blue) | 210 | 20 | Slight cool shift |
| CTB ½ (Half Blue) | 210 | 38 | Moderate cool shift |
| CTB Full | 215 | 60 | ~5600 K → 3200 K correction |
| Plus Green ½ | 120 | 22 | Fluorescent correction (skin on mixed sources) |
| Minus Green ½ | 300 | 22 | Counteract green cast from fluorescent ambient |

### 2. Creative / Atmospheric

| Gel Name | Hue (°) | Saturation (%) | Notes |
|----------|---------|----------------|-------|
| Bastard Amber | 38 | 55 | Classic film "magic hour" imitation |
| Straw | 53 | 50 | Warm-neutral; flattering on skin |
| Lavender | 270 | 30 | Soft purple; cool dreamy look |
| Congo Blue | 240 | 95 | Deep saturated blue; concert/theatrical |
| Surprise Pink | 340 | 60 | Pinkish magenta; portrait accent |
| Urban Sodium | 42 | 80 | Sodium vapour street-lamp simulation |
| Jungle Green | 145 | 75 | Nature / botanical look |
| Deep Red | 0 | 90 | Dramatic accent |
| Cyan | 180 | 85 | Medical / sci-fi cool accent |

### 3. Diffusion (Colour-Neutral)

Diffusion gels do not alter hue/saturation; they reduce specular harshness. Since Neewer lights have no optical diffusion control, this category contains only a placeholder UI note prompting the user to physically clip a diffusion panel. No BLE command is sent.

> *"Diffusion gels affect the quality of light, not its colour. Use a physical diffusion panel clipped to the fixture."*

---

## UI Layout: `buildGelsView(device:)`

```
┌─────────────────────────────────────────────────────────────┐
│  Category  [ CC ▾ ]                                         │
│ ─────────────────────────────────────────────────────────── │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │  ██████  │  │  ██████  │  │  ██████  │  │  ██████  │     │
│  │ CTO Full │  │ CTB Full │  │ +Green ½ │  │ -Green ½ │     │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     │
│  │  ██████  │  │  ██████  │  │  ██████  │  │  ██████  │     │
│  │ CTO ½    │  │ CTB ½    │  │ CTO ¼    │  │ CTB ¼    │     │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘     │
│                                                             │
│ ─────────────────────────────────────────────────────────── │
│  Tint Mode    ( ) Full Colour   (●) Tint over CCT           │
│  Intensity    [────────●────────]  72 %                     │
│ ─────────────────────────────────────────────────────────── │
│  Selected:  CTO Full  ████  H 30°  S 60%                    │
│                                            [Clear Gel]      │
└─────────────────────────────────────────────────────────────┘
```

### Components

| Component | Type | Tag | Notes |
|-----------|------|-----|-------|
| Category popup | `NSPopUpButton` | new `ControlTag.gelCategory` | Segments: CC / Creative / Diffusion |
| Gel grid | `NSCollectionView` (2-row horizontal scroll) | — | 4-column × N-row flow layout inside a fixed-height scroll view |
| Gel swatch cell | Custom `NSCollectionViewItem` subclass | — | Coloured `NSView`, label below, selection ring on click |
| Intensity slider | `NLSlider` (type `.brr`) | `ControlTag.brr` | Reuses existing tag; 0–100 |
| Intensity value label | `NSTextField` | `ControlTag.brr` | Shows "XX %" |
| Tint Mode radio | `NSMatrix` of two `NSButtonCell` | new `ControlTag.gelMode` | Full Colour vs. Tint over CCT |
| Selected gel info bar | `NSTextField` + colour swatch `NSView` | — | Read-only; shows name, H°, S% |
| Clear Gel button | `NSButton` | — | Resets light to previous mode (CCT or HSI) |

---

## Gel Application Logic

### Mode A: Full Colour

The gel completely replaces the light's colour output. The app switches the device to `HSIMode` and sends:

```
hue     = gel.hue            // 0–360°
sat     = gel.saturation     // 0–100
brr     = intensitySlider    // from Intensity slider (user-controlled)
```

This is identical to what the HSI tab does, but with preset H/S values.

### Mode B: Tint over CCT

This keeps the device's current CCT-mode white balance but blends a hue tint on top. It is useful when a light is being used for colour-corrected white light and the user only wants a hint of colour (e.g., CTO ¼ warming on a daylight-balanced fixture).

**Calculation:**

Let $H_g$ = gel hue, $S_g$ = gel saturation (0–1), $T$ = tint intensity (0–1, from slider):

$$S_\text{applied} = S_g \times T$$

The device is set to `HSIMode` with:
- $\text{hue} = H_g$
- $\text{sat} = S_\text{applied} \times 100$
- $\text{brr}$ = current brightness (unchanged)

At $T = 0$ all saturation is 0, which is equivalent to white (neutral / no gel). At $T = 1$ the full gel saturation is applied.

> **Edge case:** If the device was in CCT mode before Tint mode is selected, the app captures the current `CCT` value, converts it to an equivalent hue offset using a lookup table, and adds it to $H_g$ before sending. This preserves the perceived warmth/coolness from the CCT setting.

---

## Data Model

### `NeewerGel` struct

```swift
struct NeewerGel: Codable, Identifiable {
    let id: UUID
    var name: String
    var hue: Double        // 0–360°
    var saturation: Double // 0–100
    var category: GelCategory

    enum GelCategory: String, Codable, CaseIterable {
        case colorCorrection = "CC"
        case creative = "Creative"
        case diffusion = "Diffusion"
    }
}
```

### `TabId` addition

```swift
// Command.swift
public enum TabId: String {
    case cct    = "cctTab"
    case hsi    = "hsiTab"
    case gel    = "gelTab"   // ← new
    case source = "sourceTab"
    case scene  = "sceTab"
}
```

### `ControlTag` additions

```swift
// Command.swift
public enum ControlTag: Int {
    // ... existing cases ...
    case gelCategory = 20
    case gelMode     = 21
}
```

### Persistence

All gels live in `gels.json`, loaded once at startup into a static `GelLibrary.all` array. The app checks for a user-override file at `~/Library/Application Support/NeewerLite/gels.json` first; if present it is used instead of the bundled copy. This lets power users add or modify entries without recompiling, while shipping a sensible default set for everyone else.

There is no in-app UI for creating or editing gels.

---

## State Tracking

When a gel is applied, the `DeviceViewObject` (or `NeewerLight` model) needs to remember:

```swift
var activeGelID: UUID?         // nil = no gel active
var gelTintMode: Bool = false  // false = Full Colour, true = Tint over CCT
var preGelMode: NeewerLight.Mode = .CCTMode  // mode before gel was applied, for "Clear Gel"
```

These do **not** need to be persisted across launches — they are session state only.

---

## "Clear Gel" Behaviour

Pressing **[Clear Gel]**:
1. Reads `preGelMode` from the device's view object.
2. Sends the device back to `CCTMode` (if `preGelMode == .CCTMode`) or `HSIMode`, restoring the values from before the gel was applied.
3. Clears `activeGelID` and deselects the swatch in the grid.
4. The Gels tab remains visible and active (the user stays on it).

---

## Integration with Studio Tab (Future)

Once the Studio tab is implemented (see [LiteStudio.md](../LiteStudio.md)):

- Each light in a Studio Layout can store an `activeGelID` in its JSON entry (nullable).
- The Group Controls side panel can show a **"Gel"** row with the active gel name and a quick-clear button.
- Blind Mode should snapshot `activeGelID` as part of the staged state.

---

## Implementation Checklist

- [x] Add `NeewerGel.swift` model file with `NeewerGel` struct and `GelLibrary`
- [x] Add `gels.json` resource with the full built-in preset list
- [x] Implement `GelLibrary.load()` — check user-override path first, fall back to bundle
- [x] Add `TabId.gel` case to `Command.swift`
- [x] Add `ControlTag.gelCategory` and `ControlTag.gelMode` to `Command.swift`
- [x] Implement `buildGelsView(device:)` in `CollectionViewItem+Gels.swift` (extension file)
- [x] Implement `GelSwatchCell` (custom swatch cell in `GelSwatchCell.swift`)
- [x] Implement gel apply logic in `CollectionViewItem+Gels.swift` (Full Colour path)
- [x] Implement Tint over CCT calculation in `CollectionViewItem+Gels.swift` (Tint path)
- [x] Implement "Clear Gel" restore logic
- [x] Unit tests: gel H/S lookup, Tint over CCT blending calculation, `GelLibrary.load()` override path

---

## Open Questions

1. **Gel grid height** — Fixed two-row scrollable grid vs. expanding list. A scrollable 2-row grid keeps the control panel height consistent with other tabs; a list is easier to scan but requires vertical resize.
2. **GM (Green/Magenta) axis for gels** — Gels like "Plus Green" technically need the GM slider too. Should the Gels tab show the GM slider conditionally (when `dev.supportCCTGM`) alongside the Intensity slider?
3. **Gel recall on reconnect** — If the user disconnects and reconnects a Bluetooth device mid-session, should the app re-apply the last active gel automatically?
4. **Studio Layout persistence** — `activeGelID` is stored by gel `name` (string) rather than `UUID` in the Studio Layout JSON, so that a gel renamed in `gels.json` can still be matched by name heuristically. Agreed?
5. **User-override `gels.json` discoverability** — Should the app expose a "Reveal gels.json in Finder" menu item under Help or Preferences so power users know where to put their override file?

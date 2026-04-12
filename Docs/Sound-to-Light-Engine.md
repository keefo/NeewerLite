# Sound-to-Light Engine

> **Goal**: Transform NeewerLite's basic "follow music" mode into a professional-grade
> sound-reactive lighting engine, inspired by the best in the industry.

---

## 1. Current State Analysis

### What We Have

| Component | Status |
|-----------|--------|
| 60-bin mel-frequency spectrum (20Hz–20kHz) | ✅ Available at 46 Hz |
| dB→[0,1] normalization (`normalizeMelSpectrum()`) | ✅ Implemented |
| 3-band split (bass / mids / highs) with per-band AGC | ✅ Implemented |
| Beat/onset detection + BPM estimation | ✅ Implemented |
| Noise gate (RMS + spectral flatness, active-bins-only) | ✅ Implemented |
| HSI control (hue, sat, brightness) | ✅ Working |
| CCT control (color temp, brightness) | ✅ Working |
| 17 built-in FX modes | ✅ Available |
| 3 sound-to-light modes (Pulse, Color Flow, Bass Cannon) | ✅ Implemented |
| Strobe mode (onset-driven, rate-limited) | ✅ Implemented |
| BLE smart throttle (~15 Hz, delta compression) | ✅ Implemented |
| 5 color palettes + 6 quick presets | ✅ Implemented |
| 4 reactivity levels (Subtle / Moderate / Intense / Extreme) | ✅ Implemented |

### Original Limitations — Resolution Status

| Problem | Status |
|---------|--------|
| **2 Hz update rate** (0.5s throttle) | ✅ Fixed — BLESmartThrottle sends at ~15 Hz |
| **Hue = weighted-average frequency** | ✅ Fixed — 3 named modes with band-based mapping |
| **Saturation locked at 100%** | ✅ Fixed — dynamic per mode (spectral contrast in ColorFlow) |
| **HSI mode only** | ✅ Fixed — CCT lights participate via Pulse and Bass Cannon |
| **No beat detection** | ✅ Fixed — spectral flux onset detection + BPM estimation |
| **No frequency band separation** | ✅ Fixed — 3-band split (bass/mids/highs) with per-band AGC |
| **No per-light mapping** | ❌ Not yet — all follow-music lights run the same mode |
| **No user-configurable presets** | ✅ Fixed — 6 presets, palette selector, reactivity control |

---

## 2. Industry Landscape — Learning from the Best

### 2.1 Philips Hue Entertainment / Hue Sync

**The gold standard for consumer sound-to-light.**

Key design decisions:
- **Area-based mapping**: Divide room into zones, assign each light a zone
- **Intensity presets**: Subtle / Moderate / High / Extreme (controls reactivity)
- **Color palette**: User picks a palette (not raw spectrum mapping), music
  energy adjusts *which color from the palette* is active
- **Brightness floor**: Never goes fully dark — minimum 10-20% to avoid harsh flicker
- **Update rate**: 25 Hz over Zigbee Entertainment mode (dedicated streaming channel)

**Lesson**: Don't map raw frequency → hue. Pick *aesthetic color palettes* and let the
music energy *navigate within* the palette.

### 2.2 Nanoleaf Rhythm / Sound Reactive

**Best panel-based sound-to-light.**

Key design decisions:
- **Multiple algorithms**: Wheel, Fade, Explode, Pulse, Rhythm — each maps audio differently
- **Beat-centric**: Primary driver is onset/beat detection, not continuous spectrum
- **Color propagation**: Color ripples across panels from a focal point
- **Frequency sensitivity slider**: User controls bass vs treble bias

**Lesson**: Provide *multiple named modes* rather than one algorithm. Users want creative
variety, not a single equalizer-to-color mapping.

### 2.3 SoundSwitch (by Serato/inMusic)

**Professional DJ lighting integration.**

Key design decisions:
- **Auto-scripting**: Analyzes track structure (verse/chorus/drop/breakdown) and
  pre-assigns lighting scenes
- **Beat grid sync**: Lights change on beat boundaries, not continuous
- **Intensity tracking**: Uses spectral flux (rate of change) not raw amplitude —
  a sustained loud section stays stable, only *changes* trigger transitions
- **Cue-point lighting**: Different light scenes per song section

**Lesson**: Spectral flux (change detection) is more expressive than raw amplitude.
Beat-quantized transitions look intentional, not chaotic.

### 2.4 DMX / MA Lighting grandMA (Stage Lighting)

**Professional concert lighting consoles.**

Key design decisions:
- **Effect engine**: Sine, square, pulse, random generators modulate parameters
  over time — audio triggers phase/speed, not direct value
- **Parameter layering**: Separate audio feeds for intensity, color, position, beam
- **Dimmer curves**: Gamma-corrected output (human eye perceives light logarithmically)
- **Master/slave grouping**: One light leads, others follow with offset timing

**Lesson**: Map audio to *generator parameters* (speed, amplitude, phase), not directly
to light output. This creates patterns that feel designed, not random.

### 2.5 WLED Sound Reactive (Open Source)

**Best open-source reference implementation.**

Key design decisions:
- **3-band split**: Bass / Mids / Highs processed independently
- **AGC (Automatic Gain Control)**: Adapts to room volume over ~5-10 second window
- **FFT peak tracking**: Separate peak tracker for each frequency band
- **Squash/gain per band**: User-configurable multipliers for bass, mid, treble
- **Effect library**: 30+ audio-reactive effects, each using bands differently

**Lesson**: Split spectrum into bass/mids/highs as the fundamental abstraction.
Every effect becomes a function of (bass_energy, mid_energy, high_energy, beat).

### 2.6 QLC+ (Open Source Lighting Control)

**Industry-standard DMX software.**

Key design decisions:
- **Audio triggers**: Threshold-based triggers per frequency band (not continuous mapping)
- **Chasers**: Timed sequences that audio can speed up/slow down
- **Channel groups**: Multiple lights as a logical fixture

**Lesson**: Combine automated patterns with audio modulation — audio *influences* the
pattern, not replaces it.

---

## 3. Proposed Architecture

### 3.1 Audio Analysis Engine ✅ IMPLEMENTED

```
    ┌──────────────────────────┐
    │    60-Bin Mel Spectrum     │
    │  (46 Hz from AudioSpectrogram, dB scale)
    └────────────┬───────────────┘
                 │
    ┌────────────▼───────────────┐
    │  normalizeMelSpectrum()    │  ← Free function, dB→[0,1]
    │  clamp(bin / dbCeiling, 0, 1) │  (dbCeiling=20, NaN/Inf→0)
    └────────────┬───────────────┘
                 │
    ┌────────────▼───────────────┐
    │    AudioAnalysisEngine      │
    │                             │
    │  ┌─── Noise Gate ────────┐ │  ← Pre-AGC, first thing
    │  │ RMS floor (0.04)      │ │
    │  │ RMS passthrough (0.15)│ │
    │  │ Spectral flatness     │ │
    │  │  (active bins > 0.001 │ │
    │  │   minActiveBins = 8)  │ │
    │  │ Flatness threshold 0.65│ │
    │  │ Hysteresis + hold (23fr)│ │
    │  └───────────┬───────────┘ │
    │              │              │
    │  ┌───────────▼───────────┐ │
    │  │ Band Splitter          │ │
    │  │ Bass:  bins 0–7       │ │
    │  │ Mids:  bins 8–25      │ │
    │  │ Highs: bins 26–59     │ │
    │  └───────────┬───────────┘ │
    │              │              │
    │  ┌───────────▼───────────┐ │
    │  │ Per-Band Processing:   │ │
    │  │  • RMS energy          │ │
    │  │  • AGC (decay 0.997)   │ │
    │  │  • Power compression   │ │
    │  │    (exponent 0.6)      │ │
    │  │  • Spectral flux       │ │
    │  │    (half-wave rectified)│ │
    │  └───────────┬───────────┘ │
    │              │              │
    │  ┌───────────▼───────────┐ │
    │  │ Beat Detector          │ │
    │  │  • Flux vs moving avg  │ │
    │  │    (sensitivity 1.5)   │ │
    │  │  • Min interval 0.2s   │ │
    │  │  • BPM via median IBIs │ │
    │  │    (16-beat window)    │ │
    │  │  • Beat phase 0–1     │ │
    │  └───────────┬───────────┘ │
    │              │              │
    │  ┌───────────▼───────────┐ │
    │  │ Output: AudioFeatures  │ │
    │  │  .bassEnergy    (0–1)  │ │
    │  │  .midEnergy     (0–1)  │ │
    │  │  .highEnergy    (0–1)  │ │
    │  │  .bassFlux      (0–1)  │ │
    │  │  .midFlux       (0–1)  │ │
    │  │  .highFlux      (0–1)  │ │
    │  │  .isBeat        (bool) │ │
    │  │  .beatIntensity (0–1)  │ │
    │  │  .bpm           (Float)│ │
    │  │  .beatPhase     (0–1)  │ │
    │  │  .overallEnergy (0–1)  │ │
    │  │  .spectralFlatness(0–1)│ │
    │  │  .noiseGateOpen (bool) │ │
    │  │  .rawRMS       (Float) │ │
    │  └───────────────────────┘ │
    └────────────────────────────┘
```

### 3.2 Sound-to-Light Mapping Modes

Each mode is a function: `f(AudioFeatures) → LightCommand`

#### Mode 1: "Pulse" (Beat-driven) ✅ IMPLEMENTED

- **Target**: Brightness + Hue (HSI), Brightness (CCT)
- **Works on**: All lights (CCT + HSI)
- **Palette-aware**: warmHue/coolHue applied when palette is selected
- **Algorithm**: Tracks a `currentPulse` state variable.
  On beat: `currentPulse = max(currentPulse, beatIntensity × sensitivity)`.
  Every frame: exponential decay `currentPulse *= (1 - decayRate × decayScale)`.
  Hue interpolates between warmHue (at beat peak) and coolHue (at decay floor).
- **Inspired by**: Concert stage washes, WLED "Pulse" effect

```
onBeat:   currentPulse = max(currentPulse, beatIntensity × reactivity.sensitivity)
perFrame: currentPulse *= (1.0 - decayRate × reactivity.decayScale)
brightness = floor + currentPulse × beatImpact
hue = hueInterpolate(warmHue, coolHue, t: 1.0 - currentPulse)
```

Default params: baseBrightness=0.15, beatImpact=0.85, decayRate=0.08,
  warmHue=30°, coolHue=30° (amber, no hue shift without palette).

#### Mode 2: "Color Flow" (Frequency-driven) ✅ IMPLEMENTED

- **Target**: Hue + Brightness
- **Works on**: HSI lights only
- **Palette-aware**: warmHue/coolHue applied when palette is selected
- **Algorithm**: Frequency balance maps hue — bass→warmHue, highs→coolHue.
  `coolRatio = highEnergy / (bassEnergy + highEnergy)`. Hue smoothed via
  `hueInterpolate()`. Saturation from spectral contrast. Brightness from
  overall energy with beat bumps.
- **Inspired by**: Philips Hue Sync, Nanoleaf Rhythm

```
coolRatio = highEnergy / (bassEnergy + highEnergy + ε)
hue = hueInterpolate(warmHue, coolHue, t: coolRatio)
saturation = clamp01(0.6 + |bassEnergy - highEnergy| × 0.4)
brightness = floor + energy, smoothed + beat bump
```

Default params: warmHue=20° (red-orange), coolHue=260° (blue-violet),
  brightnessFloor=0.25, brightnessRange=0.75, hueSmoothing=0.85.

#### Mode 3: "Bass Cannon" (Bass-focused) ✅ IMPLEMENTED

- **Target**: Brightness + Color Temperature (CCT), or Brightness + Hue (HSI)
- **Works on**: All lights (CCT mode preferred, HSI fallback)
- **Algorithm**: Smoothed bass energy drives brightness. CCT shifts warm on
  bass hits, cool on quiet. HSI mode maps bass to hue (deep red→warm orange).
  Beat spikes add extra brightness.
- **Inspired by**: DJ booth LEDs, bass-reactive stage floods

```
smoothedBass = smoothedBass × smoothing + bassEnergy × (1 - smoothing)
brightness = floor + smoothedBass × range  (+ beat spike)
cct = warmCCT + (coolCCT - warmCCT) × (1 - smoothedBass)   // warm on bass
hue = bassHue + (quietHue - bassHue) × (1 - smoothedBass)   // HSI fallback
```

Default params: warmCCT=32 (3200K), coolCCT=56 (5600K),
  bassHue=10° (deep red), quietHue=40° (warm orange).

#### Mode 4: "Strobe" (Onset-driven) ✅ IMPLEMENTED

- **Target**: Brightness (white flash)
- **Works on**: All lights (CCT + HSI)
- **Not palette-aware**: Fixed low saturation for white strobe effect
- **Algorithm**: Flashes to full brightness on beat detection, then decays
  rapidly. Rate-limited to ~3 Hz (`minFlashInterval=0.33s`) for safety.
  Low saturation (0.1) produces near-white flashes.
- **Inspired by**: SoundSwitch auto-strobe, stage lighting

```
onBeat (if elapsed >= minFlashInterval):
  currentFlash = min(beatIntensity × sensitivity, 1.0)
  timeSinceLastFlash = 0
perFrame:
  currentFlash *= (1.0 - decayRate × reactivity.decayScale)
  brightness = floor + currentFlash × (1.0 - floor)
```

Default params: brightnessFloor=0.05, decayRate=0.15,
  minFlashInterval=0.33s (~3 Hz), flashSaturation=0.1.

#### Mode 5: "Aurora" (Ambient) ✅ IMPLEMENTED

- **Target**: Hue + Saturation + Brightness
- **Works on**: HSI lights only
- **Palette-aware**: No — palette popup disabled; Aurora drifts freely
- **Algorithm**: Continuous 360° hue wheel rotation. Base drift speed is 3°/s.
  Spectral centroid biases drift direction (bass slows/reverses, treble
  accelerates). Overall energy boosts speed (scaled by reactivity.sensitivity).
  Brightness breathes with bass energy. Saturation derived from spectral
  contrast. Very heavy smoothing on all outputs (hue 0.9975, brr 0.995,
  sat 0.99).
- **Inspired by**: Nanoleaf "Fade", Hue Sync ambient mode

```
centroid = highEnergy / (bassEnergy + highEnergy + ε)
directionBias = (centroid - 0.5) × 2.0          // −1 (bass) … +1 (treble)
energyBoost = 1 + overallEnergy × sensitivity    // reactivity scales influence
hueStep = baseDriftSpeed × (1 + directionBias × 0.5) × energyBoost × dt
currentHue = (currentHue + hueStep) mod 360      // wraps continuously
brightness = floor + bassEnergy × breathRange    (smoothed at 0.995)
saturation = 0.6 + contrast × 0.3 + energy × 0.1 (smoothed at 0.99)
```

Default params: baseDriftSpeed=3.0°/s, brightnessFloor=0.35, breathRange=0.3.

#### Mode 6: "Spectrum Split" (Multi-light) — ❌ NOT YET IMPLEMENTED

- **Target**: Per-light frequency band assignment
- **Algorithm**: Assign each light to a band (bass/mids/highs).
  Each reacts independently.
- **Inspired by**: DMX multi-fixture frequency split

#### Mode 7: "Color Palette" (Beat-driven cycling) — ❌ NOT YET IMPLEMENTED

- **Target**: Hue + Brightness
- **Algorithm**: Beat triggers advance to next palette color.
  Energy modulates brightness within current color.
- **Note**: Current palette system uses 2-hue pairs (warmHue/coolHue) applied
  to existing modes, rather than a separate cycling mode.
- **Inspired by**: Philips Hue Entertainment "color palette"

### 3.3 Update Rate Strategy ✅ IMPLEMENTED

**BLESmartThrottle** class handles adaptive rate limiting per device:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `minSendInterval` | 67ms (~15 Hz) | Max send rate |
| `heartbeatInterval` | 200ms (5 Hz) | Force-send even if no change |
| `brightnessThreshold` | 0.03 (3%) | Perceptual delta |
| `hueThreshold` | 5.0° | Perceptual delta |
| `satThreshold` | 0.05 (5%) | Perceptual delta |
| `cctThreshold` | 2.0 units | Perceptual delta |

**Algorithm in `shouldSend(command:deviceId:)`:**
1. New device → always send (first frame)
2. Elapsed < minSendInterval → skip (rate-limited)
3. Elapsed ≥ heartbeatInterval → send (keep device alive)
4. Otherwise → send only if any parameter exceeds its perceptual threshold

Per-device state tracking (dictionary of last-sent command + timestamp).

```
shouldSend = elapsed >= heartbeat
          || |newBrr - lastBrr| > 0.03
          || |newHue - lastHue| > 5.0    // shortest-path hue distance
          || |newSat - lastSat| > 0.05
          || |newCCT - lastCCT| > 2.0
```

### 3.4 Noise Gate — Design & Implementation ✅ COMPLETED

#### The Problem

In a quiet room with no music playing, the microphone picks up ambient noise —
fan hum, air conditioning, computer fans, distant traffic, keyboard clicks, etc.
This low-level noise causes the lights to flash and shift subtly but noticeably,
even though nothing "musical" is happening. The user expects the lights to remain
**steady and idle** when there's no music.

#### Why It Matters

1. **User experience**: Flickering lights in a silent room is distracting and
   makes the feature feel broken. Users run Sound-to-Light in studios and
   bedrooms where ambient noise is always present.

2. **AGC amplification**: The `AudioAnalysisEngine` uses Automatic Gain Control
   (AGC) that normalizes all audio to 0–1. In a quiet room, AGC slowly decays
   its tracking peaks toward the noise floor, then **amplifies ambient noise to
   full scale**. A 0.02 RMS noise floor becomes `bassEnergy ≈ 0.8` after AGC.
   The engine literally cannot distinguish a silent room from a loud one — it
   treats whatever it hears as "the signal."

3. **Beat false positives**: Random ambient fluctuations occasionally exceed the
   adaptive flux threshold, triggering `isBeat = true`. Each false beat causes a
   visible brightness spike across all connected lights.

4. **Mode sensitivity**: All modes react to AGC-normalized energy — none have
   minimum-energy floors. Even `BLESmartThrottle` only deduplicates redundant
   BLE commands, it does not gate on signal quality.

5. **The loud-noise blind spot**: A pure RMS gate handles silence, but
   **moderate-energy ambient noise** (loud fan, AC, dehumidifier) has enough
   energy to pass an RMS threshold. RMS alone cannot distinguish a loud fan
   from quiet music — both have similar energy levels. We need a second
   feature that captures *spectral shape*, not just energy.

#### Root Cause Analysis

The audio pipeline originally had **zero noise gating**:

```
Mic → AudioSpectrogram (mel FFT) → AudioAnalysisEngine.analyze()
                                      ├── bandRMS (per-band energy)
                                      ├── AGC normalization  ← amplifies everything
                                      ├── spectral flux
                                      └── beat detection (flux > mean × sensitivity)
    → SoundToLightMode.process(features)
    → BLE commands to lights
```

The only thresholds that existed were:
- `totalFlux > 0.001` in beat detection — near-zero, not a noise gate
- `agcPeak` floor of `0.001` — prevents division by zero, not silence detection
- `BLESmartThrottle` perceptual dedup — suppresses repeated identical commands,
  not ambient noise

#### Algorithm Selection: RMS + Spectral Flatness

**Why Two Features?**

| Scenario | RMS | Spectral Flatness | Correct Action |
|----------|-----|-------------------|----------------|
| Silent room | Low | N/A | Gate closed ✅ (RMS handles) |
| Loud fan / AC | **Medium** | **High (~0.8)** | Gate closed ✅ (flatness catches it) |
| Quiet music | **Low** | **Low (~0.2)** | Gate open ✅ (flatness detects music) |
| Loud music | High | Low | Gate open ✅ (both agree) |
| Drum hit / transient | Medium | Medium | Gate open ✅ (RMS passes it through) |

RMS alone misclassifies the **loud fan** row. Spectral flatness alone misclassifies
silence (flatness is undefined when energy is zero). Together they cover all cases.

**What Is Spectral Flatness?**

Spectral flatness (also called **Wiener Entropy**) measures how noise-like vs.
tonal a signal is. It's the ratio of geometric mean to arithmetic mean of the
power spectrum:

$$
\text{Spectral Flatness} = \frac{\left(\prod_{i=0}^{N-1} x_i\right)^{1/N}}{\frac{1}{N}\sum_{i=0}^{N-1} x_i} = \frac{\exp\!\left(\frac{1}{N}\sum_{i=0}^{N-1} \ln x_i\right)}{\frac{1}{N}\sum_{i=0}^{N-1} x_i}
$$

where $x_i$ is the energy of the $i$-th mel bin and $N = 60$ is the total number of bins.
The second form (using $\exp(\text{mean}(\ln x))$) is used in implementation to avoid
floating-point underflow from multiplying many small values.

- $\approx 1.0$ → perfectly flat spectrum → **noise** (fan, white noise, AC hum)
- $\approx 0.0$ → peaked spectrum → **tonal/musical** (instruments, vocals, bass)

This is the standard feature used in:
- **ITU-R BS.1770** (broadcast loudness)
- **WebRTC VAD** (voice activity detection)
- **Essentia / LibROSA** (music information retrieval)
- **Broadcast audio classifiers** (music vs. silence vs. noise)

**Why Not Other Algorithms?**

| Algorithm | What It Measures | Why Not Primary |
|-----------|-----------------|-----------------|
| **Spectral Entropy** | Spectrum randomness (Shannon) | Similar to flatness, slightly more expensive, no practical advantage |
| **Spectral Crest Factor** | Peak / RMS of spectrum | Less robust for broadband music (e.g., full orchestra) |
| **Minimum Statistics** (Martin 2001) | Adaptive noise floor | Gold standard for continuous noise subtraction, but overkill for a binary gate |
| **MCRA** (Cohen 2003) | Improved noise floor tracking | Complex, designed for frame-by-frame noise subtraction, not gate decisions |
| **Zero-Crossing Rate** | Waveform regularity | Requires raw PCM — we only have mel spectrum at this point in the pipeline |
| **WebRTC VAD** | Speech presence | Optimized for speech, not music; would reject instrumental music |

Spectral flatness is the best fit: cheap to compute (one pass over 60 bins),
directly measures the noise/music distinction, and works on the mel bins we
already have.

#### Implementation

**1. Dual-Feature Noise Gate: RMS + Spectral Flatness**

**Pre-AGC** check on the normalized mel bins using both RMS (energy) and spectral
flatness (spectral shape). The gate decision is a 2D classification.

> **Important**: The mel bins arriving from `AudioSpectrogram` are in dB scale
> (roughly -102 to +5). Before the noise gate or any analysis, they are passed
> through `normalizeMelSpectrum()` which clamps to [0, dbCeiling=20] and divides
> by the ceiling, producing values in [0, 1]. See "Bugs Found & Fixed" below.

```swift
// In AudioAnalysisEngine.analyze(_:), before any AGC/flux/beat processing:

// --- RMS ---
var sumSq: Float = 0
vDSP_svesq(bins, 1, &sumSq, vDSP_Length(bins.count))
let overallRMS = sqrtf(sumSq / Float(bins.count))

// --- Spectral Flatness (active-bins only) ---
// Computing over all 60 bins including zeros crushes geometric mean to ≈0,
// making every spectrum look "peaked" (flatness ≈ 0). Fix: use only bins
// above a small threshold. If fewer than minActiveBins are active, treat
// as noise (flatness = 1.0) — too sparse to be music.
let minActiveBins = 8
let activeBins = bins.filter { $0 > 0.001 }
let spectralFlatness: Float
if activeBins.count < minActiveBins {
    spectralFlatness = 1.0  // too sparse → noise
} else {
    var logSum: Float = 0
    var arithSum: Float = 0
    for v in activeBins {
        logSum += logf(max(v, 1e-10))
        arithSum += v
    }
    let geometricMean = expf(logSum / Float(activeBins.count))
    let arithmeticMean = arithSum / Float(activeBins.count)
    spectralFlatness = geometricMean / max(arithmeticMean, 1e-10)
}
// flatness ≈ 1.0 → noise, ≈ 0.0 → music
```

**Gate decision logic (2D):**

```swift
let shouldBeOpen: Bool
if overallRMS < rmsFloorThreshold {
    shouldBeOpen = false       // Too quiet — always gate
} else if overallRMS > rmsPassthroughThreshold {
    shouldBeOpen = true        // Loud enough — always pass
} else {
    shouldBeOpen = spectralFlatness < flatnessThreshold  // Ambiguous — use flatness
}
```

**Default thresholds:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `rmsFloorThreshold` | `0.04` | Below this → always gated (silence) |
| `rmsPassthroughThreshold` | `0.15` | Above this → always pass (loud signal) |
| `flatnessThreshold` | `0.65` | In ambiguous range: < 0.65 → music, ≥ 0.65 → noise |

**Key design decisions:**
- Both checks are **pre-AGC** — they work on absolute energy, not normalized.
- AGC peaks are **not updated** during gated frames, preventing noise-floor decay.
- `previousBins` is still updated so the first frame after gate-open doesn't
  produce a massive flux spike.
- Spectral flatness is essentially free: one `map`, one `reduce`, one `expf`.

**2. Hysteresis (Open/Close Thresholds)**

A single threshold causes flickering at the boundary. Use two sets of thresholds
with hysteresis on the RMS dimension:

- **Open**: RMS must exceed `rmsFloorThreshold` (or `rmsPassthroughThreshold`)
  AND flatness must be below `flatnessThreshold` (in the ambiguous range).
- **Close**: RMS must drop below `rmsCloseThreshold` (= `rmsFloorThreshold / 2`)
  OR flatness must rise above `flatnessThreshold + 0.1` (noise hysteresis band).

```swift
let rmsOpenThreshold: Float = 0.04   // to open
let rmsCloseThreshold: Float = 0.02  // to close (half of open)

if noiseGateOpen {
    let shouldClose = overallRMS < rmsCloseThreshold
                      || (overallRMS < rmsPassthroughThreshold
                          && spectralFlatness > flatnessThreshold + 0.1)
    if shouldClose { /* start hold timer */ }
} else {
    if shouldBeOpen { noiseGateOpen = true }
}
```

**3. Hold Timer**

When music pauses briefly (between songs, quiet passage), a **hold timer** keeps
the gate open after the close condition is met:

- **Hold duration**: ~0.5 seconds (≈23 frames at 46 Hz).
- If signal returns above close threshold during hold → cancel, stay open.
- After hold expires → close gate, begin fade-out.

**4. Smoothed Fade-Out on Gate Close**

During hold period, features fade to zero instead of snapping off:

```swift
if gateHoldFrames > 0 {
    let fadeRatio = 1.0 - Float(gateHoldFrames) / Float(gateHoldDuration)
    features.bassEnergy *= fadeRatio
    features.midEnergy *= fadeRatio
    features.highEnergy *= fadeRatio
    features.overallEnergy *= fadeRatio
    features.isBeat = false  // suppress false beats during fade
}
```

**5. AudioFeatures Fields**

```swift
struct AudioFeatures {
    // ... existing fields ...
    var spectralFlatness: Float = 0  // 0=tonal/musical, 1=noise/flat
    var noiseGateOpen: Bool = false   // gate state for diagnostics
}
```

#### Complete Gate Flow

```
analyze(melBins) {
    1. Compute RMS on raw bins (pre-AGC)
    2. Compute spectral flatness on raw bins (pre-AGC)
    3. Determine shouldBeOpen from 2D (RMS, flatness) logic
    4. Apply hysteresis + hold timer
    5. If gate closed and hold expired:
         → previousBins = bins
         → return .zero
    6. If gate closing (in hold):
         → proceed with normal analysis
         → scale output features by fadeRatio
    7. If gate open:
         → proceed with normal analysis (AGC, flux, beat, etc.)
}
```

#### Bugs Found & Fixed

**Bug 1: dB-Scale Mel Bins (Normalization)**

**Symptom**: Sound-to-Light pipeline appeared dead — lights would flash once on
mode switch, then stop responding.

**Root cause**: `AudioSpectrogram` outputs mel bins in **dB scale** (roughly
-102.5 to +5), but `AudioAnalysisEngine` assumed small positive values (0–~2).
The raw dB values had RMS of ~102, far exceeding all thresholds, so the noise
gate was **always open** and AGC was always saturated. Beat detection fired
constantly on the first frame but produced no visible change after that because
everything was pegged at maximum.

**Fix**: Added `normalizeMelSpectrum()` free function in `AudioAnalysisEngine.swift`.
Called from `AppDelegate.driveLightFromFrequency()` before `engine.analyze()`.
Maps negative dB → 0, clamps positive dB to [0, dbCeiling=20], divides by ceiling.
Output range: [0, 1].

**Tests**: 12 red/green tests in `AudioAnalysisEngineTests.swift` covering
negative dB, zero, ceiling clamp, typical dB values, and all-negative arrays.

**Bug 2: Spectral Flatness Crushed by Zero Bins**

**Symptom**: After Bug 1 fix, ambient noise in a quiet room still triggered
light changes. The noise gate never closed.

**Root cause**: After normalization, most bins in quiet/ambient audio are 0.0
(negative dB maps to 0). Computing flatness's geometric mean over **all 60 bins
including zeros** crushed the geometric mean to ≈0, making flatness ≈ 0 for
*every* input. The gate's flatness check (< 0.65 → music) was always true.

**Fix**: Compute flatness only over **active bins** (> 0.001). If fewer than
`minActiveBins = 8` bins are active, the spectrum is too sparse to be music —
return flatness = 1.0 (noise). This correctly identifies ambient noise (few
active bins or flat energy across them) vs. music (many active bins with
peaked distribution).

**Tests**: 3 red/green tests in `AudioAnalysisEngineTests.swift`:
- `test_RED_flatness_allZeros_shouldNotBeZero` — all-zero bins → flatness 1.0
- `test_RED_flatness_mostlyZeros_shouldNotBeZero` — sparse bins → flatness 1.0
- `test_RED_flatness_activePeakedSpectrum_shouldBeLow` — peaked music → flatness < 0.5

#### Where Implemented

| Component | File | Status |
|-----------|------|--------|
| `normalizeMelSpectrum()` | `AudioAnalysisEngine.swift` | ✅ Free function at top of file |
| RMS + flatness + gate | `AudioAnalysisEngine.swift` | ✅ Pre-AGC dual check at top of `analyze()` |
| Active-bins flatness fix | `AudioAnalysisEngine.swift` | ✅ Only bins > 0.001; minActiveBins = 8 |
| Gate state + hysteresis + hold | `AudioAnalysisEngine.swift` | ✅ `noiseGateOpen`, `gateHoldFrames` |
| AudioFeatures fields | `AudioAnalysisEngine.swift` | ✅ `spectralFlatness`, `noiseGateOpen`, `rawRMS` |
| Reset gate state | `AudioAnalysisEngine.reset()` | ✅ Resets gate + hold state |
| Normalization call site | `AppDelegate.swift` | ✅ `driveLightFromFrequency` calls `normalizeMelSpectrum()` |
| No changes needed | `SoundToLightMode.swift` | ✅ Modes receive `.zero` features when gated |

#### Threshold Tuning Guide

**RMS Thresholds:**

| Environment | `rmsFloorThreshold` | `rmsPassthroughThreshold` | Notes |
|-------------|---------------------|---------------------------|-------|
| Very quiet studio | 0.03 | 0.12 | Low ambient floor |
| Normal room (fan, AC) | 0.04 | 0.15 | Default |
| Noisy environment | 0.06 | 0.20 | Higher floor needed |

**Spectral Flatness Threshold:**

| Use Case | `flatnessThreshold` | Notes |
|----------|---------------------|-------|
| Strict noise rejection | 0.55 | May occasionally gate percussion-heavy music |
| Balanced (default) | 0.65 | Good balance for most genres |
| Permissive | 0.75 | Only blocks very flat noise; lets more through |

**Threshold Relationship:**

```
  RMS ↑
      │
 0.15 ├─────────────── rmsPassthroughThreshold ───────────────
      │  ALWAYS OPEN   (loud enough to be intentional)
      │
      │         ┌──────────────────────────┐
      │         │  flatness < 0.65 → OPEN  │  ← ambiguous zone
      │         │  flatness ≥ 0.65 → CLOSE │    (use flatness)
      │         └──────────────────────────┘
      │
 0.04 ├─────────────── rmsFloorThreshold ─────────────────────
      │  ALWAYS CLOSED  (too quiet to be anything)
 0.00 └──────────────────────────────────── Flatness →
      0.0 (tonal)                     1.0 (noise)
```

The close threshold should be roughly **half** of `rmsFloorThreshold` for
hysteresis. The hold duration of 0.5s works well for most music; increase to
1.0s for ambient/classical genres with long pauses.

#### Testing

**Unit tests** (15 red/green tests in `AudioAnalysisEngineTests.swift`):
silence gating, flat-noise gating, music passthrough, hysteresis, hold timer,
spectral flatness reporting, gate state reset, normalization edge cases.

**Manual testing** verified: silent room stability, fan/AC noise rejection,
music start/stop transitions, quiet passages, typing near mic, music over fan.

---

## 4. Beat Detection — Algorithm Options

### 4.1 Energy-Based Onset Detection (Recommended for v1)

**Simple, proven, low CPU.**

```
spectralFlux = Σ max(0, currentBin[i] - previousBin[i])  // half-wave rectified
isBeat = spectralFlux > (movingAverage × sensitivity)
```

- Used by: aubio, Essentia, most real-time beat detectors
- Latency: 1 frame (~22ms)
- CPU: negligible (one pass over 60 bins)
- Accuracy: good for 4-on-the-floor dance music, okay for complex rhythms

### 4.2 Autocorrelation BPM Estimation (v2)

```
1. Compute onset detection function over ~5 second window
2. Autocorrelate the onset signal
3. Find dominant periodicity in 60–180 BPM range
4. Track phase to predict next beat
```

- Gives BPM + phase for beat-quantized transitions
- Needs ~5 seconds to lock on
- More CPU but still manageable

### 4.3 Frequency-Band Onset Detection (v2)

Separate onset detection per frequency band:
- Bass onset → rhythm section hits (kick, bass drops)
- Mid onset → vocal/melody entrances
- High onset → hi-hat, cymbal, snare transients

Enables different light behaviors for different instruments.

---

## 5. Color Mapping — Perceptual Design

### Why Raw Spectrum → Hue Doesn't Work

The current weighted-average-frequency → hue mapping produces:
- Most music averages to mid-frequency → greenish/yellow
- Color barely changes because most music occupies the same spectral range
- Perceptually monotonous

### Better Approach: Parametric Color Engine

```
                    Audio Features
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
         Bass Energy  Mid Energy  High Energy
              │          │          │
              ▼          ▼          ▼
        ┌─────────────────────────────┐
        │     Color Mapping Function   │
        │                              │
        │  Option A: Band → Hue Axis   │
        │    bass=warm  high=cool      │
        │                              │
        │  Option B: Palette Index     │
        │    energy selects from       │
        │    user-chosen palette       │
        │                              │
        │  Option C: Spectral Centroid │
        │    brightness of sound →     │
        │    brightness of color       │
        │    (perceptually matched)    │
        └──────────────┬───────────────┘
                       │
                       ▼
              (Hue, Saturation, Brightness)
```

### Predefined Color Palettes ✅ IMPLEMENTED

Palettes are **2-hue pairs** (warmHue → coolHue) that modes interpolate
between based on frequency balance or beat state:

| Palette | warmHue (bass) | coolHue (treble) | Mood |
|---------|---------------|------------------|------|
| Sunset | 0° (red) | 320° (magenta) | Warm, energetic |
| Ocean | 180° (cyan) | 260° (blue-violet) | Cool, ambient |
| Neon | 300° (magenta) | 180° (cyan) | Club, EDM |
| Fire | 0° (red) | 50° (orange-yellow) | Aggressive, rock |
| Forest | 80° (yellow-green) | 160° (cyan-green) | Natural, organic |

Plus a "Default" option in UI that uses each mode's built-in warmHue/coolHue.

> **Design note**: The original brainstorm envisioned multi-color arrays with
> Monochrome and Custom palettes. The actual implementation uses a simpler
> 2-endpoint model — modes call `hueInterpolate(warmHue, coolHue, t)` where
> `t` comes from frequency balance (ColorFlow) or beat state (Pulse).
> This is simpler and maps naturally to the existing mode algorithms.

---

## 6. BLE Command Optimization

### Current Problem
Each `updateHSI()` call sends a full BLE write. At 10-15 Hz × N lights = potential congestion.

### Proposed Solutions

**6.1 Delta Compression**
Only send parameters that changed:
```swift
if abs(newBrr - lastBrr) > 3 { sendBrightness(newBrr) }
if abs(newHue - lastHue) > 5 { sendHue(newHue) }
```

**6.2 Priority Queuing**
Brightness changes (most visible) get priority. Hue changes can wait 1-2 frames.

**6.3 Batch Per Light**
Group all parameter changes for one light into a single BLE write when possible.

**6.4 Stagger Multi-Light Updates**
With 3+ lights, stagger sends across frames:
- Frame 0: Update light 1
- Frame 1: Update light 2
- Frame 2: Update light 3
- Frame 3: Update light 1 ...

---

## 7. User Interface Design

### 7.1 Toolbar Controls ✅ IMPLEMENTED

The actual UI is a compact toolbar row (y=381) above the visualization area:

```
┌─────────────────────────────────────────────────────────┐
│ [≡] [🎤] [Spectrum ▾] [Mode ▾] [Reactivity ▾] [Palette ▾] [Preset ▾] │
└─────────────────────────────────────────────────────────┘
```

| Control | Type | Position | Action |
|---------|------|----------|--------|
| **sidebar.left** | NSButton | x=6 | Toggle light list show/hide |
| **microphone.fill** | NSButton | x=32 | Toggle audio capture on/off |
| **Spectrum** | NSPopUpButton | x=62 | Select visualization plugin |
| **Mode** | NSPopUpButton | x=170 | Pulse / Color Flow / Bass Cannon |
| **Reactivity** | NSPopUpButton | x=266 | Subtle / Moderate / Intense / Extreme |
| **Palette** | NSPopUpButton | x=362 | Default + 5 named palettes |
| **Preset** | NSPopUpButton | x=450 | Custom + 6 named presets |

**Behavior**: When a preset is selected, Mode/Reactivity/Palette popups are
disabled (grayed out) to prevent inconsistency. Selecting "Custom" re-enables them.

All selections are persisted to UserDefaults (`stlMode`, `stlReactivity`, `stlPalette`).

> **Deviation from plan**: The original brainstorm envisioned a panel-style UI with
> sliders for Bass Sensitivity, Beat Threshold, Update Rate, and Brightness Floor,
> plus per-light mode assignment. The actual implementation uses a simpler toolbar
> of popup buttons — fewer controls, faster interaction, consistent with the
> NeewerLite menu-bar-app philosophy.

### 7.2 Quick Presets ✅ IMPLEMENTED

Named presets stored as `SoundToLightPreset` (mode + reactivity + palette index):

| Preset | Mode | Reactivity | Palette | Description |
|--------|------|------------|---------|-------------|
| DJ Booth | Pulse | Intense | Neon | Club feel, punchy beats |
| Film Score | Color Flow | Subtle | Sunset | Gentle ambient flow |
| Rock Concert | Bass Cannon | Extreme | Fire | Aggressive, bass-driven |
| Worship | Color Flow | Moderate | Ocean | Smooth, reverent |
| Party | Color Flow | Intense | Neon | Fun, energetic |
| Podcast | Pulse | Subtle | Default | Minimal, stable lighting |

Selecting a preset applies all three parameters and locks the individual
controls. Selecting "Custom" unlocks them.

---

## 8. Implementation Roadmap

### Phase 1 — Audio Analysis Engine (Foundation) ✅ COMPLETED

- [x] Create `AudioAnalysisEngine` class → `Spectrogram/AudioAnalysisEngine.swift`
- [x] Add `normalizeMelSpectrum()` — dB-scale bins → [0,1] normalization (dbCeiling=20)
- [x] Implement 3-band frequency splitter (bass 0–7, mids 8–25, highs 26–59)
- [x] Add per-band RMS energy with AGC normalization (decay 0.997, exponent 0.6)
- [x] Add spectral flux calculation (half-wave rectified, per band)
- [x] Add energy-based beat/onset detector (adaptive threshold + min-interval gating)
- [x] BPM estimation via median inter-beat interval (16-beat window, 40–300 BPM range)
- [x] Beat phase tracking (0–1 position in current beat cycle)
- [x] Noise gate: RMS floor + spectral flatness (active bins only, minActiveBins=8)
- [x] Gate hysteresis + hold timer (23 frames ≈ 0.5s)
- [x] Output `AudioFeatures` struct at 46 Hz (14 fields including noise gate state)
- [x] NaN/Inf protection throughout
- [x] Unit tests → `AudioAnalysisEngineTests.swift` (12 normalization + 3 flatness + original tests)

### Phase 2 — Basic Mapping Modes ✅ COMPLETED

- [x] `SoundToLightMode` protocol — `process(AudioFeatures) → LightCommand`
- [x] `LightCommand` output struct (hue, saturation, brightness, cct, gm, isHSI)
- [x] "Pulse" mode (beat → brightness + hue sweep, palette-aware warmHue/coolHue)
- [x] "Color Flow" mode (frequency balance → hue, spectral contrast → saturation)
- [x] "Bass Cannon" mode (bass → CCT shift + brightness, HSI fallback)
- [x] `BLESmartThrottle` — per-device delta compression + heartbeat (~15 Hz effective)
- [x] `Reactivity` enum (Subtle / Moderate / Intense / Extreme) with 5 scaling properties
- [x] `ColorPalette` — 5 predefined 2-hue palettes (Sunset, Ocean, Neon, Fire, Forest)
- [x] `SoundToLightPreset` — 6 named presets (DJ Booth, Film Score, Rock Concert, etc.)
- [x] Hue helpers: `hueInterpolate()`, `normalizeHue()`, `hueDistance()`
- [x] Unit tests → `SoundToLightModeTests.swift` (4 pulse+palette tests + original tests)

### Phase 3 — User Interface ✅ COMPLETED

- [x] Toolbar row: sidebar toggle + mic button + spectrum/mode/reactivity/palette/preset popups
- [x] Mode picker popup (Pulse / Color Flow / Bass Cannon)
- [x] Reactivity popup (Subtle / Moderate / Intense / Extreme)
- [x] Color palette popup (Default + 5 named palettes)
- [x] Preset popup (Custom + 6 presets); locks other controls when preset active
- [x] Mic toggle icon (replaces Listen label + switch)
- [x] Light list toggle (sidebar.left icon)
- [x] UserDefaults persistence (stlMode, stlReactivity, stlPalette)
- [ ] ~~Per-light mode assignment~~ — deferred (all follow-music lights run same mode)

### Phase 4 — Advanced Modes

- [ ] "Spectrum Split" multi-light mode (per-light band assignment)
- [ ] "Color Palette" with beat-driven palette cycling
- [ ] Per-band onset detection (separate kick/snare/hi-hat triggers)

### Phase 5 — Polish

- [ ] Brightness floor setting (user-configurable minimum)
- [ ] BLE command priority queue + staggered multi-light
- [ ] Dimmer curve (gamma correction for perceptual linearity)
- [ ] Save/load user-created presets
- [ ] Keyboard shortcuts for mode switching during live performance

---

## 9. Technical Design Principles

Drawn from analyzing Philips Hue, Nanoleaf, SoundSwitch, WLED, and DMX consoles:

1. **Audio modulates patterns, not replaces them.**
   Don't map raw FFT → light value. Use audio to modulate the speed, amplitude,
   or phase of a well-designed pattern.

2. **Beat is king.**
   The single most impactful improvement is beat detection. Humans perceive
   rhythm before pitch. A light that pulses on beat feels alive.

3. **Perceptual, not linear.**
   Apply gamma curves to brightness (eye perceives light logarithmically).
   Small brightness changes at low levels matter more than at high levels.

4. **Never go black.**
   A brightness floor prevents harsh flicker. Even Philips Hue at maximum
   reactivity keeps a 10% floor. Total darkness between beats is jarring.

5. **Palette > Spectrum.**
   Curated color palettes look 10× better than raw frequency→hue mapping.
   Let the algorithm navigate within aesthetic boundaries.

6. **AGC adapts to context.**
   A quiet acoustic set and a loud EDM track should both fill the dynamic range.
   Automatic gain control with slow adaptation (~5-10 seconds) is essential.

7. **Delta, don't spam.**
   Only send BLE commands when light output meaningfully changes.
   This saves bandwidth and makes the experience smoother.

8. **Per-light personality.**
   Multiple lights shouldn't all do the same thing. Offset timing, different
   frequency bands, complementary colors — this creates depth.

---

## 10. Key References

| Reference | What to Study | Link/Note |
|-----------|---------------|-----------|
| Philips Hue Sync | Palette-based mapping, intensity presets | Consumer gold standard |
| Nanoleaf Desktop | Multiple named effects, rhythm mode | Panel-based inspiration |
| WLED Sound Reactive | 3-band split, AGC, 30+ effects, open source | github.com/atuline/WLED |
| SoundSwitch | Beat-grid sync, auto-scripting, DJ integration | Professional DJ lighting |
| Essentia (MTG) | Beat detection algorithms, onset detection | essentia.upf.edu |
| aubio | Real-time onset/BPM detection, C library | aubio.org |
| QLC+ | DMX audio triggers, chasers, channel groups | qlcplus.org |
| grandMA3 | Effect engine, parameter layering | Professional reference |

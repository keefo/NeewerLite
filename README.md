<p align="center">
  <img src="https://github.com/keefo/NeewerLite/blob/main/Design/icon_128x128%402x.png?raw=true" width="128" height="128" alt="NeewerLite">
</p>

<h1 align="center">NeewerLite</h1>

<p align="center"><strong>Control your Neewer lights from your Mac. Finally.</strong></p>

<p align="center">
  <a href="https://github.com/keefo/NeewerLite/actions/workflows/ci.yml"><img src="https://github.com/keefo/NeewerLite/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/keefo/NeewerLite/releases/latest"><img src="https://img.shields.io/github/v/release/keefo/NeewerLite" alt="Latest Release"></a>
  <a href="https://github.com/keefo/NeewerLite/blob/main/LICENSE"><img src="https://img.shields.io/github/license/keefo/NeewerLite" alt="License"></a>
</p>

---

Neewer makes great LED lights. They have apps for iOS and Android. But nothing for the Mac.

NeewerLite fixes that. Open the app, and it finds your Neewer lights over Bluetooth. Control brightness, color temperature, RGB, scenes, and gels — right from your menu bar. One app. Zero friction.

<p align="center">
  <a href="https://youtu.be/pbNi6HZTDEc">
    <img src="https://github.com/keefo/NeewerLite/blob/main/screenshot.png?raw=true" width="720" alt="NeewerLite Screenshot">
  </a>
</p>

## Three Things That Make It Great

**1. Full Light Control** — Power, brightness, CCT (3200K–8500K), full RGB color, 9 built-in scene effects, music sync, and 39 professional lighting gel presets. Everything your phone app can do, now on your Mac.

**2. Sound-to-Light Engine** — Your lights now listen to the room.

NeewerLite captures audio from your microphone, runs it through a 60-bin mel-scale spectrogram at 46 Hz, extracts 14 audio features — bass, mids, highs, spectral flux, beat detection, BPM, the works — and maps them to your lights in real time. The entire pipeline, from sound wave to LED command, takes about 100 milliseconds. You hear the beat. You see the beat. No perceivable gap.

Five modes. Each one designed for a different kind of moment:

| Mode | What It Does |
|------|-------------|
| **Pulse** | Beat-driven brightness spikes. Lights punch on the kick drum and fade between hits. The default and probably all most people need. |
| **Color Flow** | Frequency becomes color. Bass pulls warm, treble pulls cool, the room shifts with the music's tone. |
| **Bass Cannon** | The subwoofer mode. Bass energy drives everything — brightness, warmth, intensity. For when the low end is the whole point. |
| **Strobe** | Sharp white flashes on detected beats. Rate-limited to 3 Hz because we care about your eyeballs. |
| **Aurora** | Slow, glacial color drift around the full 360° hue wheel. Sound gently shapes the drift — bass slows it, treble accelerates it — but the lights keep moving even in silence. Ambient lighting that breathes. |

The engine includes automatic gain control (loud or quiet, it adapts), a dual noise gate that distinguishes silence from ambient noise using spectral flatness, four reactivity levels from Subtle to Extreme, five color palettes, six one-click presets, and a smart BLE throttle that sends only perceptually meaningful changes — per device.

This isn't "volume goes up, brightness goes up." This is real-time audio analysis driving real-time light design. And it's built into a free, open-source menu bar app.

**3. Automation Built In** — Every command has a URL scheme. Script it, shortcut it, voice-control it. Say "Meow" and your lights turn on. Press a Stream Deck button and your key light shifts from warm to cool. This isn't just an app — it's a control node for your entire lighting rig.

## Install

1. Download the latest `.dmg` from the [Releases](https://github.com/keefo/NeewerLite/releases/latest) page
2. Drag NeewerLite to your Applications folder
3. Launch it — the icon appears in your menu bar
4. Your Neewer lights show up automatically via Bluetooth

That's it.

## Automate Everything

NeewerLite speaks URL schemes. Use them from Terminal, Shortcuts, Stream Deck, or anything that can open a URL.

```bash
# Lights on
open "neewerlite://turnOnLight"

# Lights off
open "neewerlite://turnOffLight"

# Set color temperature and brightness
open "neewerlite://setLightCCT?CCT=3200&Brightness=100"

# Set RGB color
open "neewerlite://setLightHSI?RGB=ff00ff&Saturation=100&Brightness=100"

# Trigger a scene
open "neewerlite://setLightScene?Scene=SquadCar"
```

Control individual lights by name:

```bash
open "neewerlite://turnOnLight?light=KeyLight"
```

> **Tip:** Paste any of these URLs into your browser address bar to test them instantly.

### Stream Deck Integration

NeewerLite includes a built-in Elgato Stream Deck plugin. Install it once, then drag light controls onto any button or dial. One press — instant lighting change.

<p align="center">
  <img src="https://github.com/keefo/NeewerLite/blob/main/Docs/StreamDeck_dial_ui.png?raw=true" width="360" alt="Stream Deck Plugin">
  <img src="https://github.com/keefo/NeewerLite/blob/main/Docs/StreamDeck_dial.jpg?raw=true" width="360" alt="Stream Deck Dial">
</p>

Or bind your own scripts — see [Stream Deck Integration Guide](Docs/Integrate-with-streamdeck.md).

### macOS Shortcuts

Integrate light commands directly into Shortcuts workflows. See the [Shortcuts Guide](Docs/Integrate-with-shortcut.md).

### Voice Control

Open **System Settings → Accessibility → Voice Control → Commands**. Create a new command, set it to open a URL like `neewerlite://toggleLight`, and give it any trigger word you want.

Say "Meow" → lights toggle. Pretty cool, huh?

## Lighting Gels

A lighting gel is a transparent colour filter placed in front of a light to shift its colour or colour temperature — used in film, photography, and theatre to match light sources or set a mood.

NeewerLite ships with **39 built-in gel presets** across two categories:

| Category | Presets | Use Case |
|----------|---------|----------|
| **Color Correction** | CTO (¼, ½, Full), CTB (¼, ½, Full), Plus/Minus Green, Window Green | Match mixed light sources on set |
| **Creative** | Bastard Amber, Congo Blue, Surprise Pink, Urban Sodium, Straw, Lavender, and more | Create mood, atmosphere, cinematic looks |

Pick a gel by its industry-standard name. The app translates it to the right HSI values and sends the command to your light. No manual lookup required.

Read more: [Gels Feature Plan](Docs/Gels-Feature-Plan.md)

## Supported Lights

NeewerLite works with a wide range of Neewer Bluetooth-enabled LED lights, including:

- **Panel Lights** — 660 RGB, 480 RGB, RGB530 PRO, SL90 Pro
- **Portable / Magnetic** — RGB176, RGB1-A, RGB62, TL21C, GR18C
- **Key Lights** — GL1, GL1 Pro, GL1C
- **Tube Lights** — BH-30S, TL60 RGB, TL40
- **Studio Lights** — CB60 RGB, CB60B, CB100C, CB120B

And many more. The full light database is [updated on GitHub](Database/lights.json) — the app downloads it automatically, so new lights get supported without an app update.

### My Light Isn't Recognized?

1. Use a Bluetooth scanner app to find your light's raw Bluetooth name
2. Check `Database/lights.json` for the matching light type
3. If it's missing or misconfigured, [open a PR](https://github.com/keefo/NeewerLite/pulls) — once merged, every user gets the fix automatically

See [Adding Support for a New Light](Database/lights.json) for the JSON format.

## URL Scheme Reference

| Command | URL |
|---------|-----|
| Turn on all lights | `neewerlite://turnOnLight` |
| Turn off all lights | `neewerlite://turnOffLight` |
| Toggle all lights | `neewerlite://toggleLight` |
| Scan for lights | `neewerlite://scanLight` |
| Set CCT | `neewerlite://setLightCCT?CCT=3200&Brightness=100` |
| Set CCT + GM | `neewerlite://setLightCCT?CCT=3200&GM=-50&Brightness=100` |
| Set HSI (RGB hex) | `neewerlite://setLightHSI?RGB=ff00ff&Saturation=100&Brightness=100` |
| Set HSI (Hue) | `neewerlite://setLightHSI?HUE=360&Saturation=100&Brightness=100` |
| Set Scene by name | `neewerlite://setLightScene?Scene=SquadCar` |
| Set Scene by ID | `neewerlite://setLightScene?SceneId=1&Brightness=100` |
| Control by light name | `neewerlite://turnOnLight?light=KeyLight` |

**Scene names:** SquadCar, Ambulance, FireEngine, Fireworks, Party, CandleLight, Lighting, Paparazzi, Screen

> Scene availability varies by light model. Use `SceneId` (1–17) for lights with more scenes.

## Contributing

Found a bug? Want to add your light model? PRs are welcome.

The simplest contribution: add your light to `Database/lights.json`. It's a JSON file — no Swift required.

## License

[MIT](LICENSE)

## Support the Project

If NeewerLite saves you time, consider [sponsoring the project](https://github.com/sponsors/keefo).

Bitcoin: `1A4mwftoNpuNCLbS8dHpk9XHrcyvtExrYF`

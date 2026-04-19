# NeewerLite Wiki

NeewerLite is a native macOS menu-bar app for controlling Neewer LED lights over Bluetooth. This wiki contains the project's technical documentation.

## What's Here

### Getting Started
- **[[Codebase Guide|Codebase-Guide]]** — Architecture overview, build/test commands, repo layout, and common task walkthroughs. Start here.

### Features
- **[[Sound-to-Light Engine|Sound-to-Light-Engine]]** — Design spec for the real-time audio-reactive lighting system: modes, noise gate, beat detection, and BLE throttle.
- **[[Sound-to-Light Technical Report|Sound-to-Light-Technical-Report]]** — Competitive analysis benchmarking NeewerLite against Philips Hue Sync, WLED, and others.
- **[[Gels|Gels]]** — Photographic gel presets (Lee/Rosco standards), tint-over-CCT math, and UI design.
- **[[Command Patterns|Command-Patterns]]** — How BLE commands are defined as human-readable templates instead of hardcoded byte arrays.

### Protocol & Research
- **[[Bluetooth Device Control Background|Bluetooth-Device-Control-Background]]** — BLE basics: ATT protocol, services, characteristics, and why packet logging matters.
- **[[Neewer Light Protocol|Neewer-Light-Protocol]]** — Reverse-engineered `0x78` protocol for CB60 RGB, GL1C, and RGB62 lights.
- **[[Neewer Home Protocol|Neewer-Home-Protocol]]** — Reverse-engineered `0x7A` protocol for Neewer Home devices (NS02, NH-PD series): per-segment HSI, gradients, music mode, 73 scene effects.

### Integrations
- **[[Integrate with macOS Shortcuts|Integrate-with-shortcut]]** — Control lights from Shortcuts.app using URL schemes.
- **[[Integrate with StreamDeck|Integrate-with-streamdeck]]** — Set up Stream Deck buttons for light control.

# NeewerLite — Principles

NeewerLite is a native macOS menu-bar app that gives users full control over Neewer Bluetooth LED lights — something Neewer only provides on iOS/Android. For architecture, build commands, and technical details, see [Docs/Codebase-Guide.md](../Docs/Codebase-Guide.md).

## Philosophy

**Native and lightweight.** This is a Mac app, not an Electron wrapper. It uses Swift, AppKit, and CoreBluetooth directly. No abstraction layers between the user and the hardware. The app should launch instantly, use minimal memory, and never get in the way.

**The menu bar is home.** NeewerLite lives in the menu bar. It is a utility, not a destination. Users open it, adjust their lights, and move on. Every interaction should be fast and forgettable.

**Real-time is a contract.** The audio-reactive pipeline runs at ~46 Hz. Latency is the enemy. When a beat hits, the lights respond — no perceivable delay. Never trade latency for architectural elegance.

**Data-driven protocol.** Light commands are defined by templates in a JSON database, not hardcoded byte arrays. Supporting a new light means adding data, not writing code. Keep it that way.

## Quality Standards

- **Always build and test after changes.** No exceptions. A change that doesn't compile or breaks tests is not a change — it's a problem.
- **Red/Green testing.** For behavioral fixes, first write a test that fails without the fix, then make it pass. This proves the fix actually fixes something.
- **Read before you write.** Understand the code you're changing. `AppDelegate` is large and central. The audio pipeline has subtle invariants. Skim first; edit second.

## Design Values

- **Simplicity over flexibility.** Don't add configuration for things that should just work. Don't build frameworks for one use case. Solve the problem in front of you.
- **Stability over features.** A crash erases trust. A missing feature is just a wish. Protect what works before adding what's new.
- **Correctness at boundaries.** Validate external input (BLE responses, HTTP requests, user data). Trust internal code paths and framework guarantees.
- **Threads are real.** BLE commands can run from any thread. UI must be on main thread. The audio callback must never touch views. Respect these boundaries — they exist for a reason.

## Anti-Patterns

- Don't over-abstract. A helper function used once is not a helper — it's a detour.
- Don't add defensive code for scenarios that can't happen internally. That's noise, not safety.
- Don't "improve" code you weren't asked to change. Stay in scope.
- Don't guess at byte-level BLE commands. They come from `CommandPatternParser` templates. If you don't understand the template, read it — don't bypass it.

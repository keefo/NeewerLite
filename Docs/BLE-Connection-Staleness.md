# BLE Connection Staleness Analysis

Last updated: April 25, 2026

## Problem Statement

Users report that if NeewerLite stays open for a long time, typically around an hour, one or more lights stop responding to commands.

Restarting the app restores control immediately.

That pattern strongly suggests the app is keeping stale CoreBluetooth session state in memory rather than losing the light permanently. The process restart rebuilds the `CBCentralManager`, rediscoveries services and characteristics, and refreshes the cached `CBPeripheral` references.

## What The Current Code Does

The relevant connection lifecycle lives in `AppDelegate` and `NeewerLight`.

### Connection setup

- `AppDelegate` creates one `CBCentralManager` at launch and starts a repeating 10-second timer via `keepLightConnectionAlive()`.
- When a peripheral is discovered, `centralManager(_:didDiscover:advertisementData:rssi:)` caches it and immediately calls `connect`.
- When the connection succeeds, `centralManager(_:didConnect:)` runs service discovery.
- When the Neewer service and both required characteristics are found, `advancePeripheralToDevice(...)` stores the `CBPeripheral` and characteristics into the matching `NeewerLight` model and enables notifications.

### Reconnect behavior today

- `centralManager(_:didDisconnectPeripheral:error:)` immediately reconnects if the peripheral belongs to a saved light.
- `centralManager(_:didFailToConnect:error:)` removes the peripheral from the transient cache and grays out the UI.

This means the app already knows how to reconnect after an explicit CoreBluetooth disconnect callback.

### The missing piece

There is a timer intended to keep connections alive, but `NeewerLight.sendKeepAlive(_:)` currently returns immediately before doing any work.

That means the timer never actually:

- probes whether the BLE link is still healthy,
- increments `connectionBreakCounter`,
- reconnects a disconnected peripheral, or
- updates the UI based on liveness.

### Why commands can fail silently

`NeewerLight.write(data:to:)` prefers `.withoutResponse` whenever the characteristic supports it.

That is fast and appropriate for real-time lighting, but it also means a successful local `writeValue` call does not prove the light is still healthy. If CoreBluetooth keeps the peripheral object around in a nominally connected state while the underlying session is stale, the app has very little signal to trigger recovery.

## Root-Cause Hypothesis

The most likely failure mode is:

1. The physical BLE session becomes half-dead after a long idle period or OS-level link churn.
2. CoreBluetooth does not immediately deliver `didDisconnectPeripheral`.
3. NeewerLite still holds a `CBPeripheral` plus cached characteristics and continues sending writes.
4. Because writes are commonly `.withoutResponse`, the app gets no immediate negative feedback.
5. Since `sendKeepAlive(_:)` is effectively disabled, there is no independent liveness probe to force reconnection.

This hypothesis matches the observed symptom that an app restart fixes the issue without requiring the user to power-cycle the light.

## Cheap Disconfirming Check

Before changing behavior, the cheapest useful check is to instrument liveness and run a soak test:

1. Add logging around the 10-second keepalive timer.
2. Replace the no-op `sendKeepAlive(_:)` with a non-destructive probe such as `readRSSI()` when the peripheral is marked connected.
3. Log:
   - probe start,
   - `peripheral.state`,
   - `peripheralDidUpdateRSSI`,
   - `didDisconnectPeripheral`,
   - any write errors.

If the stale period appears while `peripheral.state == .connected` and probes stop succeeding until reconnect, the current hypothesis is confirmed.

## Important Constraint

It is not safe to simply delete the early `return` from `sendKeepAlive(_:)` and ship that behavior.

The dormant implementation sends power commands every 10 seconds when the peripheral is connected. That is a side-effecting keepalive and could create unnecessary traffic or state churn. The reconnect logic is useful, but the probe itself should be non-mutating.

## Recommended Fix Design

### 1. Replace the no-op keepalive with an explicit health probe

Preferred first option:

- If `peripheral.state == .connected`, call `peripheral.readRSSI()` every 10 to 30 seconds.
- Treat a successful `peripheralDidUpdateRSSI` callback as proof that the session is alive.

Why this is the best first step:

- no visible light-state mutation,
- uses an existing delegate callback already implemented in `NeewerLight`,
- low risk compared with synthetic command traffic,
- directly exercises the CoreBluetooth link instead of assuming the cached state is trustworthy.

### 2. Track last-known-good communication per light

Add lightweight per-device state such as:

- `lastSuccessfulProbeAt`,
- `lastSuccessfulWriteAt` if a write-with-response path exists,
- `lastDisconnectAt`,
- `consecutiveProbeFailures`.

This turns reconnect decisions into explicit policy instead of relying on a single `connectionBreakCounter` that is currently only updated in dead code.

### 3. Define a stale-session policy

Recommended initial policy:

- If a light misses 2 or 3 consecutive probes, mark the session unhealthy.
- Cancel the peripheral connection through `CBCentralManager.cancelPeripheralConnection(_:)`.
- Clear the model's cached peripheral and characteristics.
- Reconnect through the existing discovery path.

This is safer than continuing to push writes into a probably-dead session.

### 4. Rebuild state after reconnect

On reconnect, keep the existing sequence:

- connect,
- discover services,
- discover characteristics,
- call `setPeripheral(...)`,
- re-enable notifications.

The current app already has this pipeline. The main gap is detecting when that pipeline needs to be re-entered.

### 5. Only use write acknowledgements where they help

Long term, one additional improvement is to introduce a health-check command path that prefers `.withResponse` when the characteristic supports both `.write` and `.writeWithoutResponse`.

That should be separate from the high-frequency lighting path. Real-time lighting updates should remain optimized for low latency.

## Suggested Implementation Order

1. Instrument the current connection lifecycle and add health-probe logs.
2. Convert `sendKeepAlive(_:)` from a no-op into a non-mutating probe.
3. On repeated probe failure, force a disconnect and reconnect.
4. Gray out the UI only after the reconnect attempt fails or the peripheral cannot be rehydrated.
5. Add a regression test around the new state machine where practical, but expect much of the confidence to come from a manual soak test because CoreBluetooth objects are difficult to unit test directly.

## Validation Plan

### Manual soak test

1. Launch the app with one or more lights paired.
2. Leave the app idle for at least 60 to 90 minutes.
3. Periodically inspect logs for probe success.
4. After the idle window, issue commands from the UI and from the URL scheme.
5. Confirm that if a link goes stale, the app detects it and reconnects without restart.

### Failure injection ideas

- Turn a light off and back on while the app remains open.
- Move the light briefly out of BLE range and then back.
- Toggle macOS Bluetooth off and back on.

The expected result is that the app recovers through reconnect logic instead of requiring a process restart.

## Summary

This does not look like a missing reconnect path. It looks like a missing stale-session detector.

The code already reconnects when CoreBluetooth tells it a disconnect happened. The likely bug is that long-lived sessions can become unusable without producing that callback, and NeewerLite currently has no active liveness probe because `sendKeepAlive(_:)` is disabled.

The safest first fix is to introduce a non-mutating probe such as `readRSSI()`, track repeated failures, and deliberately recycle the BLE session when the connection appears healthy in memory but unhealthy in practice.
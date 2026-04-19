# NeewerLite Command Pattern Guide

---

## Why Add the Command Pattern Subsystem?

Smart lights and similar devices often use different ways to communicate, even between models from the same brand.  
Hard-coding every possible command for every device makes the app hard to update and extend.  
The **command pattern subsystem** lets you describe how commands are built for your device in a flexible, editable way—no code changes needed.

**Benefits:**
- Easily support new devices or firmware updates.
- Fix or tweak commands without waiting for an app update.
- See and edit how commands are built, making troubleshooting easier.

Suggest to read [Bluetooth-Device-Control-Background](https://github.com/keefo/NeewerLite/wiki/Bluetooth-Device-Control-Background) before continue.

---

## What Is a Command Pattern?

A **command pattern** is a recipe that tells the app how to build the ATT command data it sends to your light over Bluetooth.  
It’s like a template: you fill in the blanks with the values you want (like brightness, color, or power state), and the app turns that into the exact bytes your light expects.

**Example:**  
Suppose your light expects a command like:  
`0x78 0x81 0x01 0xFA`  
A command pattern describes how to build this from pieces like “power on”, “mode”, or “color”.

---

## How Does It Work?

1. **You define a pattern** for each command (like power on/off, set color, etc.).
2. **The app fills in the values** (like which color or brightness you want).
3. **The pattern is translated** into the exact bytes sent over Bluetooth.

**In short:**  
- You write a pattern.
- The app uses it to build the command.
- Your light gets the right data.

---

## Command Pattern Syntax

A command pattern is a string made of tokens, each describing a part of the command.  
Tokens are separated by spaces.  
Each token can be a variable (inside `{}`), a fixed value (like `0x78`), or a special field.

### Basic Token Types

- **Variable:** `{name}`  
  Represents a value that changes (like brightness or color).
- **Variable with type:** `{name:type}`  
  Specifies how the value should be encoded (like as an 8-bit number).
- **Variable with type and options:** `{name:type:enum(...)}` or `{name:type:range(min,max)}`  
  Limits the value to certain choices or a range.
- **Fixed value:** `0xNN`  
  A constant byte (hexadecimal).
- **Special fields:** `{cmdtag}`, `{powertag}`, `{size}`, `{checksum}`  
  These are handled specially by the app.

### Example Pattern

```
{cmdtag} {powertag} {state:uint8:enum(1=on,2=off)} {checksum}
```

- `{cmdtag}`: Command type (fixed for your device)
- `{powertag}`: Power mode (fixed for your device)
- `{state:uint8:enum(1=on,2=off)}`: State, encoded as an 8-bit number, only allows 1 (on) or 2 (off)
- `{checksum}`: Automatically calculated by the app

### Supported Types

- `uint8`: 8-bit number
- `uint16_le`: 16-bit number, little-endian
- `uint16_be`: 16-bit number, big-endian
- `hex`: Raw hexadecimal value

### Supported Options

- `enum(...)`: List of allowed values, e.g. `enum(1=on,2=off)`
- `range(min,max)`: Allowed range, e.g. `range(0,255)`

### Special Fields

- `{cmdtag}`: The command’s main type (usually fixed for your device)
- `{powertag}`: Power mode (usually fixed)
- `{size}`: The total size of the command (auto-calculated)
- `{checksum}`: A simple sum of all previous bytes (auto-calculated)

---

## How Patterns Translate to Bluetooth Data

1. The app reads your pattern and fills in values from your settings.
2. Each token is converted to bytes:
    - Variables become numbers or codes.
    - Fixed values are added as-is.
    - Special fields are calculated.
3. The final byte array is sent to your light.

**Example:**  
Pattern: `{cmdtag} {powertag} {state:uint8:enum(1=on,2=off)} {checksum}`  
Values: `state = 1` (on)  
Result: `0x78 0x81 0x01 0xFA`  
- `0x78` and `0x81` are fixed for your device.
- `0x01` is the value for "on".
- `0xFA` is the checksum.

---

## Tips for Writing Patterns

- Always start with `{cmdtag}` and end with `{checksum}` for most commands.
- Use types (`uint8`, `uint16_le`, etc.) to match your device’s expectations.
- Use `enum` or `range` to restrict values and avoid mistakes.
- Use fixed values (`0xNN`) for bytes that never change.
- If you’re not sure, check your device’s documentation or existing patterns.

---

## Summary

The command pattern subsystem makes your app flexible and future-proof.  
You can easily add, edit, or fix how commands are built for your lights—no coding required.  
Just write or tweak the pattern, and the app does the rest!

---

**For more examples and details, visit:**  
[NeewerLite Command Pattern Guide](https://github.com/xulian/NeewerLite/wiki/Command-Pattern-Guide)
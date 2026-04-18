# Neewer Home - NS02 Neon Rope Light — BLE Protocol Reference

## Device Identification

| Field | Value |
|-------|-------|
| BLE Name | `NH-PD20250030` |
| Model | NS02 5M (Neon Rope Light) |
| Internal ID | `PD20250030` |
| BLE Service UUID | `69400001-B5A3-F393-E0A9-E50E24DCCA99` |
| Write Characteristic | `69400002-B5A3-F393-E0A9-E50E24DCCA99` |
| Notify Characteristic | `69400003-B5A3-F393-E0A9-E50E24DCCA99` |

### Related Models (Same Protocol Family)

All `NH-PD*` devices use the `0x7A` protocol:

| Constant | Product ID | Product |
|----------|-----------|---------|
| NG01 | PD20240039 | |
| NF01 | PD20240081 | |
| NR01 | PD20250004 | |
| NS01_3M | PD20250005 | NS01 3M |
| NS02_3M | PD20250006 | NS02 3M |
| NR02 | PD20250007 | |
| NW03 | PD20250008 | |
| NS01_5M | PD20250029 | NS01 5M |
| **NS02_5M** | **PD20250030** | **NS02 5M** |
| NF02 | PD20250039 | |
| NW01 | PD20250050 | |
| NF04 | PD20250051 | |
| NF05 | PD20250052 | |
| NF08 | PD20250058 | |
| NF06 | PD20250087 | |
| NF01_2 | PD20250092 | |
| NS03_3M | PD20250103 | NS03 3M |
| NS05 | PD20250128 | |
| BF05 | PD20250129 | |
| NF10 | PD20250130 | |
| NS09_4M | PD20250132 | |
| BF04 | PD20250133 | |
| NS09_6M | PD20250134 | |
| NF12 | PD20250138 | |
| NF13 | PD20250139 | |
| NF14 | PD20250140 | |
| NF15 | PD20250141 | |
| NS03_5M | PD20250145 | NS03 5M |
| NF03 | PD20250150 | |
| NF01_3 | PD20250151 | |
| BF01 | PD20250122 | |
| BF02 | PD20250123 | |

## Packet Frame Format

### Standard Packet (`Packet`)

```
[head] [dataId] [size] [data...] [checksum]
```

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | head | Always `0x7A` (122 decimal) |
| 1 | 1 | dataId | Command type identifier |
| 2 | 1 | size | Payload byte count |
| 3..N | size | data | Payload |
| N+1 | 1 | checksum | `(head + dataId + size + Σdata) & 0xFF` |

### Long Size Packet (`LongSizePacket`)

Used for variable-length commands (color, gradient, scene, mixed).

```
[head] [dataId] [size_hi] [size_lo] [data...] [checksum]
```

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | head | Always `0x7A` |
| 1 | 1 | dataId | Command type identifier |
| 2 | 1 | size_hi | Payload length high byte |
| 3 | 1 | size_lo | Payload length low byte |
| 4..N | size | data | Payload |
| N+1 | 1 | checksum | `(head + dataId + size_hi + size_lo + Σdata) & 0xFF` |

### Checksum

Simple byte sum modulo 256. Identical algorithm for both packet types — the size field(s) are included in the sum.

## Commands

### Power On/Off

**Class:** `SendDeviceSwitchBean` — Standard Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x0A` |
| size | `0x01` |
| data[0] | `0x01` = on, `0x02` = off |
| checksum | sum & 0xFF |

**Examples (from BLE trace):**

```
Power On:  7A 0A 01 01 86
Power Off: 7A 0A 01 02 87
```

### CCT / Lighting Mode

**Class:** `SendLightingBean` — Standard Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x0C` |
| size | `0x06` |
| data[0] | brightness / 10 |
| data[1] | brightness % 10 |
| data[2] | color temperature (raw value, e.g. 25–85 for 2500K–8500K) |
| data[3] | `0x00` |
| data[4] | `0x01` |
| data[5] | `0x00` |
| checksum | sum & 0xFF |

> **Brightness range is 0–1000** (where 1000 = 100%). The NEEWER Home app uses 0–1000 internally with 0.1% precision. For example, 50% = 500, encoded as `500/10=50=0x32, 500%10=0=0x00`. The light firmware decodes as `data[0]*10 + data[1]`.

**Example:** Brightness 500 (50%), CCT 32 (3200K):

```
7A 0C 06 32 00 20 00 01 00 DF
```

> **Note:** Brightness is encoded as two pseudo-BCD digits: `500` → `0x32, 0x00` (50*10 + 0 = 500 = 50%). This differs from the old protocol which sends a single byte `0x32` (50) for 50% brightness.

### Fixed Brightness (Brightness Only)

**Class:** `SendFixedBrightnessBean` — Standard Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x0B` |
| size | `0x03` |
| data[0] | `0x00` |
| data[1] | brightness / 10 |
| data[2] | brightness % 10 |
| checksum | sum & 0xFF |

### HSI / Color Mode

**Class:** `SendAllColorBean` — Long Size Packet

All color commands share dataId `0x0D` and use LongSizePacket (2-byte big-endian size). The `lightColorType` byte (data[2]) determines the mode:

| lightColorType | Mode | Description |
|---|---|---|
| `0x01` | **Whole light** | All segments get the same color. No colorCount field. |
| `0x02` | **Per-segment** | Each segment gets its own color. Includes colorCount. |
| `0x03` | **Choose** | Paint specific segments by index (see Choose Color section). |

> **IMPORTANT:** For solid-color HSI, use mode `0x01`. Mode `0x02` with colorCount=1 only paints segment 0 (~10cm on a rope light), not the entire light.

#### Mode 0x01 — Whole Light (Solid Color)

Used when setting the entire light to a single HSI color. This is the standard HSI mode for NeewerLite.

| Byte | Value | Notes |
|------|-------|-------|
| head | `0x7A` | |
| dataId | `0x0D` | |
| size_hi, size_lo | `0x00 0x0A` (10) | payload length, big-endian |
| data[0] | brightness / 10 | BCD high digit (brightness 0–1000) |
| data[1] | brightness % 10 | BCD low digit |
| data[2] | `0x01` | lightColorType = whole light |
| data[3] | lightness (`0x64` = 100) | per-color relative brightness, typically 100 |
| data[4] | hue high byte | hue 0–360, big-endian |
| data[5] | hue low byte | |
| data[6] | saturation (0–100) | |
| data[7] | `0x00` | trailer |
| data[8] | `0x01` | panel count |
| data[9] | `0x00` | panel index |
| checksum | sum & 0xFF | |

**Example:** Brightness 1000 (100%), Hue 240 (blue), Saturation 100:

```
7A 0D 00 0A 64 00 01 64 00 F0 64 00 01 00 8C
```

#### Mode 0x02 — Per-Segment (Multiple Colors)

Used for segmented/rainbow effects where each LED zone gets a different color. The number of segments (`controlledLightPoint`) is device-specific, fetched from Neewer's cloud API.

| Byte | Value | Notes |
|------|-------|-------|
| head | `0x7A` | |
| dataId | `0x0D` | |
| size_hi, size_lo | payload length | big-endian, = 8 + 4×N |
| data[0] | brightness / 10 | BCD high digit (brightness 0–1000) |
| data[1] | brightness % 10 | BCD low digit |
| data[2] | `0x02` | lightColorType = per-segment |
| data[3] | color count high byte | N segments, big-endian |
| data[4] | color count low byte | |
| | **Per color (repeated N times):** | |
| +0 | lightness (0–100) | per-segment relative brightness |
| +1 | hue high byte | per-segment hue 0–360 |
| +2 | hue low byte | |
| +3 | saturation (0–100) | |
| | **Trailer:** | |
| | `0x00`, `0x01`, panel_index | |
| checksum | sum & 0xFF | |

### Gradient Color Mode

**Class:** `SendGradientColorBean` — Long Size Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x0D` |
| size_hi, size_lo | payload length |
| data[0] | brightness / 10 |
| data[1] | brightness % 10 |
| data[2] | `0x04` (gradient mode identifier) |
| data[3] | gradient mode type |
| data[4] | segments high byte |
| data[5] | segments low byte |
| data[6..9] | `0x00 0x00 0x00 0x00` (reserved) |
| | **Per color:** |
| +0 | lightness |
| +1 | hue high byte |
| +2 | hue low byte |
| +3 | saturation |
| | **Optional trailer:** `0x00 0x01 panel_index` |
| checksum | sum & 0xFF |

### Choose Color (Per-Segment)

**Class:** `SendChooseColorBean` — Long Size Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x0D` |
| size_hi, size_lo | payload length |
| data[0] | brightness / 10 |
| data[1] | brightness % 10 |
| data[2] | `0x03` (choose mode identifier) |
| data[3] | choose type: `0x01` = white, `0x02` = HSI |
| data[4] | lightness (`0x00` if white type) |
| | **If type == 0x01 (white):** |
| data[5..7] | `0x00 0x00 0x00` |
| | **If type == 0x02 (HSI):** |
| data[5] | hue high byte |
| data[6] | hue low byte |
| data[7] | saturation |
| data[N] | index count high byte |
| data[N+1] | index count low byte |
| | **Per index:** 2 bytes big-endian segment index |
| checksum | sum & 0xFF |

### Music Reactive Mode

**Class:** `SendMusicDataBean` — Standard Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x0E` |
| size | payload length |
| data[0] | `0x01` |
| data[1] | `0x00` |
| data[2] | brightness / 10 |
| data[3] | music mode ID |
| data[4] | speed |
| data[5] | sensitivity |
| data[6] | color mode: `0x00` = custom colors, `0x01` = auto |
| data[7] | color count |
| | **Per color:** |
| +0 | hue high byte |
| +1 | hue low byte |
| +2 | saturation |
| data[N] | gradient: `0x01` = on, `0x00` = off |
| data[N+1] | start point |
| checksum | sum & 0xFF |

### Scene Effect

**Class:** `SendSceneEffectBean` / `SendSceneEffectBeanV2` — Long Size Packet

```
[0x7A] [0x12] [size_hi] [size_lo] [payload...] [checksum]
```

#### Payload Structure

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0–1 | 2 | effectId | Scene ID, big-endian (e.g. `0x0001` = Rainbow) |
| 2 | 1 | brightness | 0–100 integer (NOT BCD) |
| 3 | 1 | `0x00` | Always zero (scenes use integer brightness, no 0.1% precision) |
| 4 | 1 | effectCount | Number of animation phases (1–8) |
| 5 | 1 | `0x01` | Fixed |
| 6–7 | 2 | `0x00 0x00` | Fixed |
| 8 | 1 | subSize | First sub-block data size |
| 9.. | subSize | sub-block | First sub-block parameters (see below) |
| | 1 | `0x00` | **Separator** between sub-blocks (only if effectCount > 1) |
| | 1 | subSize | Next sub-block data size |
| | subSize | sub-block | Next sub-block parameters |
| | | ... | Repeat separator + sub-block for each additional phase |
| +0 | 1 | `0x00` | Trailer pad |
| +1 | 1 | `0x01` | Panel count |
| +2 | 1 | `0x01` | Panel index |

> **Multi-phase scenes:** When effectCount > 1, sub-blocks are separated by a `0x00` byte. For example, Heartbeat (effectId 51) has effectCount=3 with three Breath sub-blocks chained as: `[subSize₀][sub-block₀] 00 [subSize₁][sub-block₁] 00 [subSize₂][sub-block₂]`.

#### Sub-block Structure (effectMode 13 — "Progressive")

Most built-in scenes use effectMode 13. The sub-block varies by effectMode, but the common pattern for Progressive is:

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | effectMode | Animation type (see table below) |
| 1 | 1 | effectValue | Speed (0–100, higher = faster) |
| 2 | 1 | effectMethod | Animation variant (derived) |
| 3 | 1 | direction | `0x01` = forward |
| 4 | 1 | mainLightEffect | Main light behavior |
| 5–8 | 4 | mainLightData | CCT/brightness for main light |
| 9 | 1 | colorCount | Number of colors in the effect |
| 10.. | 4×N | colors | Per-color: `[lightness, hue_hi, hue_lo, saturation]` |

#### Sub-block Structure (effectMode 1 — "Breath")

Used by Deep Sea, Party, Heartbeat, and other breathing/pulsing scenes. Color entries are **5 bytes** (includes a weight field):

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | effectMode | `0x01` (Breath) |
| 1 | 1 | speed | Animation speed (0–100) |
| 2 | 1 | direction | `0x00` = normal, `0x01` = reverse |
| 3–4 | 2 | reserved | Always `0x00 0x00` |
| 5–7 | 3 | padding | Always `0x00 0x00 0x00` |
| 8 | 1 | colorCount | Number of color entries |
| 9.. | 5×N | colors | Per-color: `[weight, brightness, hue_hi, hue_lo, saturation]` |

The **weight** byte controls relative timing per segment (typically uniform, e.g. 20 for all). **Brightness** and **saturation** are both per-color, allowing spatial brightness/saturation gradients along the strip.

> **4 bytes vs 5 bytes per color:** Progressive mode uses 4-byte colors `[L, H_hi, H_lo, S]`. Breath mode uses 5-byte colors `[weight, L, H_hi, H_lo, S]`. The sub-block's effectMode determines which format applies.

#### Effect Modes (effectMode values)

28 animation types available for DIY/scene construction:

| effectMode | Chinese | English | Description |
|---|---|---|---|
| 1 | 呼吸 | Breath | Colors fade in/out cyclically |
| 2 | 闪烁 | Blink | Colors flash on/off |
| 3 | 追逐 | Chase | Colors chase sequentially along the strip |
| 4 | 流动 | Flow | Colors flow continuously in one direction |
| 5 | 轮换 | Alternate | Colors alternate/rotate |
| 6 | 空白 | Blank | No light (gap/rest effect) |
| 11 | 渐变 | Gradient | Smooth color transition between colors |
| 12 | 随机 | Random | Random color positions and timing |
| 13 | 递变 | Progressive | Colors progress sequentially (used by Rainbow, Starry Sky) |
| 14 | 发散 | Spread | Colors spread outward from center |
| 15 | 拖尾 | Trail | Moving light with trailing fade |
| 16 | 开幕 | Curtain | Colors reveal like an opening curtain |
| 17 | 静止 | Still | Static color display, no animation |
| 18 | 聚集 | Gather | Colors converge toward a point |
| 19 | 双段递变 | Dual Progressive | Two-segment progressive from both ends |
| 20 | 反弹 | Bounce | Colors bounce back and forth |
| 21 | 双段反弹 | Dual Bounce | Two-segment bounce from both ends |
| 22 | 单向堆砌 | One-way Stack | Colors stack up from one end |
| 23 | 双向堆砌 | Two-way Stack | Colors stack up from both ends |
| 24 | 间隔 | Interval | Colors appear at intervals along the strip |
| 25 | 交错 | Interleave | Colors interleave/alternate positions |
| 26 | 脉动 | Pulse | Colors pulse with heartbeat-like rhythm |
| 27 | 渐晕 | Vignette | Colors fade at edges like photographic vignette |

> **Note:** effectModes 7–10 are not defined in the string resources. The gap between 6 and 11 suggests they may be reserved or device-specific.

#### Effect Sub-block Parameters (Advanced)

The `Effect` class in the defines these additional parameters that may appear in the sub-block depending on effectMode:

| Parameter | Type | Description |
|---|---|---|
| effectMethod | int | Animation sub-variant |
| direction | int | `1`=forward, `2`=reverse, `3`=random |
| mainLightEffect | int | How main LED responds (`0`=follow, `1`=white, `2`=color, `3`=off) |
| longestLuminousSegment | int? | Max length of lit segment |
| longestSegmentMinimumOccurrence | int? | Min occurrences of longest segment |
| randomCycleTimes | int? | Cycles before re-randomizing |
| flickerAmount | int? | Amount of random flicker |
| disperse | int? | Color dispersion setting |
| sourceCount | int? | Number of light sources |
| runColorMultiple | int? | Color cycle multiplier |
| segmentCount | int? | Number of segments |
| mirror | int? | Mirror the effect |
| tailLength | int? | Tail/trail length |
| spacing | int? | Spacing between elements |
| decayMode | int? | How fading works |
| decayExponent | int? | Fade curve steepness |
| waitGap | int? | Pause between cycles |
| backdropColorSegmentControlType | int? | Background color behavior |
| gatherPointCount | int? | Points for gather effect |
| constructionCount | int? | Build-up count |
| runMode | int? | Run behavior variant |
| runTimes | int? | Number of run cycles |
| speed | int? | Alternative speed field |

> The exact sub-block byte layout per effectMode requires either BLE capture for each mode, or successful decompilation of `SendSceneEffectBean.conversionData()` (3046 instructions, jadx failed). The parameters above are from the `Effect` data class; not all apply to every mode.

#### Decoded BLE Traces

**Rainbow (effectId=1)**

```
7A 12 00 1E  00 01  46 05  01 01 00 00  12
0D 32 01 00  00 00 00 00 00
02  64 00 00 64  64 01 68 64
00 01 01  47
```

| Field | Hex | Decoded |
|-------|-----|---------|
| head | `7A` | |
| dataId | `12` | Scene effect |
| size | `00 1E` | 30 bytes payload |
| effectId | `00 01` | Scene #1 (Rainbow) |
| brightness | `46 05` | 70×10 + 5 = **705** (70.5%) |
| effectCount | `01` | 1 sub-effect |
| fixed | `01 00 00` | |
| subSize | `12` (18) | 18 bytes sub-block |
| effectMode | `0D` (13) | Progressive |
| effectValue | `32` (50) | Speed 50% |
| effectMethod | `01` | Variant 1 |
| direction | `00` | Default |
| mainLightEffect | `00 00 00 00` | Off |
| colorCount | `02` | 2 colors |
| color[0] | `64 00 00 64` | L=100, H=0 (red), S=100 |
| color[1] | `64 01 68 64` | L=100, H=360 (red), S=100 |
| trailer | `00 01 01` | panel |
| checksum | `47` | |

> Rainbow uses Progressive mode with 2 endpoint colors (H=0° → H=360°) — a full hue cycle.

**Starry Sky (effectId=2)**

```
7A 12 00 3E  00 02  46 05  01 01 00 00  32
0D 3C 01 00  00 00 00 00 00
0A  
32 00 E6 64  64 00 E6 28
32 00 E6 64  32 00 E6 64
64 00 E6 28  32 00 E6 64
64 00 E6 28  32 00 E6 64
32 00 E6 64  64 00 E6 28
00 01 01  51
```

| Field | Hex | Decoded |
|-------|-----|---------|
| head | `7A` | |
| dataId | `12` | Scene effect |
| size | `00 3E` | 62 bytes payload |
| effectId | `00 02` | Scene #2 (Starry Sky) |
| brightness | `46 05` | **705** (70.5%) |
| effectCount | `01` | 1 sub-effect |
| fixed | `01 00 00` | |
| subSize | `32` (50) | 50 bytes sub-block |
| effectMode | `0D` (13) | Progressive |
| effectValue | `3C` (60) | Speed 60% (fixed in payload) |
| effectMethod | `01` | |
| direction | `00` | |
| mainLightEffect | `00 00 00 00` | Off |
| colorCount | `0A` (10) | 10 colors |
| colors | see below | Alternating blue shades |
| trailer | `00 01 01` | |
| checksum | `51` | |

Starry Sky colors (10 blue-toned entries):

| # | L | H | S | Description |
|---|---|---|---|---|
| 0 | 50 | 230 | 100 | Medium blue |
| 1 | 100 | 230 | 40 | Bright pale blue |
| 2 | 50 | 230 | 100 | Medium blue |
| 3 | 50 | 230 | 100 | Medium blue |
| 4 | 100 | 230 | 40 | Bright pale blue |
| 5 | 50 | 230 | 100 | Medium blue |
| 6 | 100 | 230 | 40 | Bright pale blue |
| 7 | 50 | 230 | 100 | Medium blue |
| 8 | 50 | 230 | 100 | Medium blue |
| 9 | 100 | 230 | 40 | Bright pale blue |

> Starry Sky uses 10 blue-toned colors alternating between medium (L=50, S=100) and bright pale (L=100, S=40) at H=230°.

**Heartbeat (effectId=51) — Multi-phase Breath Scene**

Heartbeat is the most complex single-color scene: 193 bytes, effectCount=3, using Breath mode with spatial saturation gradients to simulate a cardiac pulse. It demonstrates the multi-sub-block separator pattern.

```
7A 12 00 BC 00 33 64 00 03 01 00 00 0E 01 1E 00
00 00 00 00 00 01 14 64 00 00 64 00 4F 01 46 01
00 00 00 00 00 0E 14 64 00 00 14 14 64 00 00 1E
14 64 00 00 28 14 64 00 00 32 14 64 00 00 41 14
64 00 00 50 14 64 00 00 64 14 64 00 00 64 14 64
00 00 50 14 64 00 00 41 14 64 00 00 32 14 64 00
00 28 14 64 00 00 1E 14 64 00 00 14 00 4F 01 46
01 00 00 00 00 00 0E 14 64 00 00 64 14 64 00 00
50 14 64 00 00 41 14 64 00 00 32 14 64 00 00 28
14 64 00 00 1E 14 64 00 00 14 14 64 00 00 14 14
64 00 00 1E 14 64 00 00 28 14 64 00 00 32 14 64
00 00 41 14 64 00 00 50 14 64 00 00 64 00 01 01
5D
```

Packet header:

| Field | Hex | Decoded |
|-------|-----|---------|
| head | `7A` | |
| dataId | `12` | Scene effect |
| size | `00 BC` | 188 bytes payload |
| effectId | `00 33` | Scene #51 (Heartbeat) |
| brightness | `64` | 100 (user-adjustable 0–100) |
| pad | `00` | Always 0x00 |
| effectCount | `03` | **3** animation phases |
| fixed | `01 00 00` | |

Sub-block 0 — **Rest Phase** (bytes 12–26, subSize=14):

| Field | Hex | Decoded |
|-------|-----|---------|
| subSize | `0E` | 14 bytes |
| effectMode | `01` | Breath |
| speed | `1E` | 30 (slow pulse) |
| direction | `00` | Normal |
| reserved | `00 00` | |
| padding | `00 00 00` | |
| colorCount | `01` | 1 color |

| # | Weight | Brr | Hue | Sat | Description |
|---|--------|-----|-----|-----|-------------|
| 0 | 20 | 100 | 0 | 100 | Pure red, full brightness |

> The whole strip breathes slowly in solid red — the quiet phase between heartbeats.

Separator: `0x00` (byte 27)

Sub-block 1 — **Systole / Pulse In** (bytes 28–107, subSize=79):

| Field | Hex | Decoded |
|-------|-----|---------|
| subSize | `4F` | 79 bytes |
| effectMode | `01` | Breath |
| speed | `46` | 70 (fast pulse) |
| direction | `01` | **Reverse** |
| reserved | `00 00` | |
| padding | `00 00 00` | |
| colorCount | `0E` | **14** color segments |

| # | Weight | Brr | Hue | Sat | Visual |
|---|--------|-----|-----|-----|--------|
| 0 | 20 | 100 | 0 | 20 | pale pink |
| 1 | 20 | 100 | 0 | 30 | ░░ |
| 2 | 20 | 100 | 0 | 40 | ░░░ |
| 3 | 20 | 100 | 0 | 50 | ▓▓ |
| 4 | 20 | 100 | 0 | 65 | ▓▓▓ |
| 5 | 20 | 100 | 0 | 80 | ▓▓▓▓ |
| 6 | 20 | 100 | 0 | 100 | **deep red** |
| 7 | 20 | 100 | 0 | 100 | **deep red** |
| 8 | 20 | 100 | 0 | 80 | ▓▓▓▓ |
| 9 | 20 | 100 | 0 | 65 | ▓▓▓ |
| 10 | 20 | 100 | 0 | 50 | ▓▓ |
| 11 | 20 | 100 | 0 | 40 | ░░░ |
| 12 | 20 | 100 | 0 | 30 | ░░ |
| 13 | 20 | 100 | 0 | 20 | pale pink |

> Saturation ramps inward: 20 → 100 → 20. Edges are pale pink, center is deep red. This is the "thump" — the heart contraction.

Separator: `0x00` (byte 108)

Sub-block 2 — **Diastole / Pulse Out** (bytes 109–188, subSize=79):

Same structure as Sub-block 1 but with the saturation ramp **inverted**:

| # | Weight | Brr | Hue | Sat | Visual |
|---|--------|-----|-----|-----|--------|
| 0 | 20 | 100 | 0 | 100 | **deep red** |
| 1 | 20 | 100 | 0 | 80 | ▓▓▓▓ |
| 2 | 20 | 100 | 0 | 65 | ▓▓▓ |
| 3 | 20 | 100 | 0 | 50 | ▓▓ |
| 4 | 20 | 100 | 0 | 40 | ░░░ |
| 5 | 20 | 100 | 0 | 30 | ░░ |
| 6 | 20 | 100 | 0 | 20 | pale pink |
| 7 | 20 | 100 | 0 | 20 | pale pink |
| 8 | 20 | 100 | 0 | 30 | ░░ |
| 9 | 20 | 100 | 0 | 40 | ░░░ |
| 10 | 20 | 100 | 0 | 50 | ▓▓ |
| 11 | 20 | 100 | 0 | 65 | ▓▓▓ |
| 12 | 20 | 100 | 0 | 80 | ▓▓▓▓ |
| 13 | 20 | 100 | 0 | 100 | **deep red** |

> Saturation ramps outward: 100 → 20 → 100. Deep red at edges, pale at center. This is the relaxation phase — blood flowing back.

Trailer: `00 01 01` + checksum `5D`

**Animation loop:** REST (slow solid red breath) → SYSTOLE (fast inward saturation pulse) → DIASTOLE (fast outward saturation pulse) → repeat.

**Design insight:** The entire effect is purely **saturation-driven**. Hue is always 0 (red) and brightness is always 100 across all 29 color entries. The visual heartbeat comes from modulating *how saturated* the red is across 14 spatial segments, with the speed contrast (30 vs 70) creating the rhythmic rest/beat pattern.

#### Scene Catalog

73 built-in scene effects across 5 categories. All scenes are **brightness-only** — the NEEWER Home app provides no speed, color, or CCT controls for scenes. Each scene is a fixed BLE payload with only the brightness bytes as a variable parameter.

> **No speed control.** Despite each scene packet containing a speed byte (effectValue), the NEEWER Home app does not expose this to the user. Scenes are single-tap with a brightness slider only. The speed values baked into each scene's packet are fixed.

**Full catalog** (verified via BLE capture of all 73 scenes from NEEWER Home app):

> All hex dumps below were captured at brightness 100% (`0x64 0x00`) unless noted. Bytes [0]–[1] = header (`7A 12`), [2]–[3] = payload size (big-endian), [4]–[5] = effectId, [6]–[7] = brightness (BCD), last byte = checksum.

**Natural (effectId 1–24)**

effectId 1 — **Rainbow** (35 bytes)

```
7A 12 00 1E 00 01 46 05 01 01 00 00 12 0D 32 01
00 00 00 00 00 00 02 64 00 00 64 64 01 68 64 00
01 01 47
```

effectId 2 — **Starry Sky** (67 bytes)

```
7A 12 00 3E 00 02 46 05 01 01 00 00 32 0D 3C 01
00 00 00 00 00 00 0A 32 00 E6 64 64 00 E6 28 32
00 E6 64 32 00 E6 64 64 00 E6 28 32 00 E6 64 64
00 E6 28 32 00 E6 64 32 00 E6 64 64 00 E6 28 00
01 01 51
```

effectId 3 — **Flame** (87 bytes)

```
7A 12 00 52 00 03 64 00 01 01 00 00 46 0D 50 01
00 00 00 00 00 00 0F 64 00 19 64 32 00 0A 64 64
00 14 64 64 00 1E 46 46 00 1E 64 32 00 14 64 5A
00 14 64 5A 00 1E 64 64 00 19 64 46 00 0A 64 64
00 14 64 46 00 1E 46 32 00 1E 64 55 00 14 64 5A
00 14 64 00 01 01 AF
```

effectId 4 — **Sunrise** (91 bytes)

```
7A 12 00 56 00 04 64 00 01 01 00 00 4A 0B 2D 00
00 00 00 00 00 00 10 64 00 F5 64 64 00 F5 64 64
00 F5 50 64 00 F5 3C 50 00 28 28 64 00 28 3C 64
00 23 50 64 00 1E 64 64 00 14 64 64 00 0A 64 64
00 0A 64 64 00 14 64 64 00 1E 64 64 00 28 50 50
00 28 28 50 00 28 14 00 01 01 07
```

effectId 5 — **Sunset** (91 bytes)

```
7A 12 00 56 00 05 64 00 01 01 00 00 4A 0B 28 00
00 00 00 00 00 00 10 32 00 28 32 3C 00 28 3C 46
00 23 46 50 00 23 50 5A 00 23 5A 64 00 23 64 64
00 23 64 64 00 1E 64 64 00 14 64 64 00 14 64 64
00 00 5F 64 00 00 5F 64 01 68 3C 64 00 DC 50 5A
00 DC 5A 3C 01 68 3C 00 01 01 55
```

effectId 6 — **Cherry Blossom** (109 bytes)

```
7A 12 00 68 00 06 64 00 01 01 00 00 5C 0E 1E 00
02 02 00 00 00 00 00 0F 01 64 01 63 3C 02 00 00
00 00 01 64 01 63 3C 02 00 00 00 00 01 64 00 3C
1E 02 00 00 00 00 01 64 01 5E 3C 02 00 00 00 00
01 5F 01 60 32 02 00 00 00 00 01 64 00 3C 1E 02
00 00 00 00 01 64 01 5E 3C 02 00 00 00 00 01 64
01 63 3C 01 00 5A 01 4A 14 00 01 01 45
```

effectId 7 — **Forest** (79 bytes)

```
7A 12 00 4A 00 07 64 00 01 01 00 00 3E 0D 5F 00
00 00 00 00 00 00 0D 64 00 6E 64 3C 00 6E 50 50
00 78 32 64 00 82 64 1E 00 78 64 64 00 82 64 50
00 55 3C 64 00 6E 64 3C 00 78 50 50 00 78 32 64
00 82 64 1E 00 78 64 64 00 82 64 00 01 01 57
```

effectId 8 — **Sea of Flowers** (86 bytes)

```
7A 12 00 51 00 08 64 00 01 01 00 00 45 04 1E 00
00 00 00 00 00 0F 50 01 54 5A 64 01 4A 1E 64 01
4F 41 55 00 41 64 64 01 4F 50 50 01 54 5A 46 00
4B 64 64 01 4A 1E 50 01 54 5A 64 01 4A 1E 64 01
4F 41 55 00 41 64 64 01 4F 50 50 01 54 5A 46 00
4B 64 00 01 01 F6
```

effectId 9 — **Glacier** (103 bytes)

```
7A 12 00 62 00 09 64 00 02 01 00 00 2A 0E 14 00
03 05 00 00 00 00 00 05 01 64 00 CD 64 02 00 00
00 00 01 64 00 C8 50 02 00 00 00 00 01 64 00 C8
50 01 00 32 00 CD 64 00 2A 0E 14 00 03 05 00 00
00 00 00 05 01 64 00 D2 46 02 00 00 00 00 01 64
00 D2 32 02 00 00 00 00 01 64 00 D2 0F 01 00 32
00 CD 64 00 01 01 9E
```

effectId 10 — **Wave** (228 bytes)

```
7A 12 00 DF 00 0A 64 00 03 01 00 00 45 04 50 00
00 00 00 00 00 0F 64 00 DC 64 64 00 DC 64 64 00
DC 3C 3C 00 DC 32 64 00 DC 64 64 00 DC 64 64 00
DC 3C 3C 00 DC 32 64 00 DC 64 64 00 DC 64 64 00
DC 3C 3C 00 DC 32 64 00 DC 64 64 00 DC 64 64 00
DC 3C 00 45 04 50 00 00 00 00 00 00 0F 64 00 DC
64 64 00 DC 64 64 00 DC 3C 64 00 DC 32 3C 00 DC
32 5A 00 DC 32 3C 00 DC 32 32 00 DC 32 64 00 DC
64 64 00 DC 64 64 00 DC 3C 64 00 DC 32 3C 00 DC
32 5A 00 DC 32 3C 00 DC 32 00 45 04 46 00 00 00
00 00 00 0F 64 00 DC 64 64 00 DC 64 64 00 DC 32
64 00 DC 64 64 00 DC 64 64 00 DC 3C 50 00 DC 32
3C 00 DC 32 64 00 DC 64 64 00 DC 64 64 00 DC 32
64 00 DC 64 64 00 DC 64 64 00 DC 3C 50 00 DC 32
00 01 01 61
```

effectId 11 — **Deep Sea** (61 bytes)

```
7A 12 00 38 00 0B 64 00 01 01 00 00 2C 01 14 00
00 00 00 00 00 07 0A 64 00 C8 64 0A 64 00 D2 64
0A 64 00 DC 64 0A 64 00 E6 64 0A 64 00 F0 64 0A
64 00 E6 64 0A 64 00 D2 64 00 01 01 41
```

effectId 12 — **Firefly** (91 bytes)

```
7A 12 00 56 00 0C 64 00 01 01 00 00 4A 0D 1E 01
00 00 00 00 00 00 10 64 00 78 64 1E 00 78 64 32
00 46 64 1E 00 78 64 1E 00 78 64 64 00 46 64 1E
00 78 64 64 00 78 64 1E 00 78 64 1E 00 78 64 1E
00 78 64 32 00 46 64 1E 00 78 64 64 00 46 64 1E
00 78 64 1E 00 78 64 00 01 01 F4
```

effectId 13 — **Liquid Ripple** (87 bytes)

```
7A 12 00 52 00 0D 64 00 01 01 00 00 46 0D 3C 01
00 00 00 00 00 00 0F 64 00 C3 64 3C 00 C3 64 14
00 C3 64 64 00 C3 64 50 00 C3 64 3C 00 C3 64 1E
00 C3 64 14 00 C3 64 64 00 C3 64 46 00 C3 64 32
00 C3 64 28 00 C3 64 1E 00 C3 64 14 00 C3 64 0A
00 C3 64 00 01 01 51
```

effectId 14 — **Amber Waves** (83 bytes)

```
7A 12 00 4E 00 0E 64 00 01 01 00 00 42 0D 50 01
00 00 00 00 00 00 0E 64 00 32 5A 64 00 23 5A 64
00 1E 50 64 00 23 50 46 00 28 64 64 00 23 50 64
00 23 50 64 00 23 5A 64 00 32 32 64 00 28 5A 46
00 23 64 64 00 32 5A 64 00 23 5A 64 00 32 32 00
01 01 ED
```

effectId 15 — **Lotus Lagoon** (228 bytes)

```
7A 12 00 DF 00 0F 64 00 03 01 00 00 45 04 14 00
00 00 00 00 00 0F 3C 00 7D 64 50 00 78 64 64 01
63 28 64 00 3C 1E 64 01 63 19 3C 00 7D 64 3C 00
7D 64 3C 00 7D 64 3C 00 7D 64 64 01 63 19 64 01
63 28 64 00 3C 1E 64 01 63 19 3C 00 7D 64 3C 00
7D 64 00 45 04 14 00 00 00 00 00 00 0F 3C 00 7D
64 3C 00 7D 64 50 00 78 64 64 01 63 19 64 01 63
28 50 00 78 64 3C 00 7D 64 64 00 3C 1E 3C 00 7D
64 3C 00 7D 64 50 00 78 64 64 01 63 19 64 01 63
28 50 00 78 64 3C 00 7D 64 00 45 04 14 00 00 00
00 00 00 0F 64 01 63 28 64 01 63 19 50 00 78 64
3C 00 7D 64 3C 00 7D 64 64 00 3C 1E 64 01 63 28
3C 00 7D 64 64 01 63 28 64 01 63 05 50 00 78 64
3C 00 7D 64 3C 00 7D 64 64 00 3C 1E 64 01 63 28
00 01 01 AF
```

effectId 16 — **Aurora** (59 bytes)

```
7A 12 00 36 00 10 64 00 01 01 00 00 2A 0D 46 01
00 00 00 00 00 00 08 1E 00 C8 64 3C 00 99 64 46
00 A5 64 5A 00 50 64 5A 00 50 64 1E 00 C8 64 50
00 D7 64 5A 00 50 64 00 01 01 91
```

effectId 17 — **Gobi Desert** (187 bytes)

```
7A 12 00 B6 00 11 64 00 02 01 00 00 54 01 23 01
00 00 00 00 00 0F 1E 50 00 16 52 28 64 00 49 10
1E 50 00 99 0D 28 64 00 26 20 1E 50 00 13 36 1E
50 00 61 0C 1E 50 00 B1 25 1E 50 00 32 1A 1E 50
00 16 52 28 64 00 49 10 1E 50 00 99 0D 28 64 00
26 20 1E 50 00 13 36 1E 50 00 61 0C 1E 50 00 B1
25 00 54 01 23 01 00 00 00 00 00 0F 1E 50 00 16
52 1E 50 00 99 0D 1E 50 00 13 36 1E 50 00 B1 25
28 64 00 26 20 28 64 00 49 10 1E 50 00 32 1A 1E
50 00 61 0C 1E 50 00 16 52 1E 50 00 99 0D 1E 50
00 13 36 1E 50 00 B1 25 28 64 00 26 20 28 64 00
49 10 1E 50 00 32 1A 00 01 01 FB
```

effectId 18 — **Spring** (86 bytes)

```
7A 12 00 51 00 12 64 00 01 01 00 00 45 04 2D 00
00 00 00 00 00 0F 50 00 82 64 50 00 82 64 64 01
2C 50 64 01 63 50 3C 00 82 64 64 00 28 64 46 00
82 64 64 01 63 50 50 00 82 64 64 01 2C 50 46 00
82 64 46 00 82 64 3C 00 82 50 64 00 28 64 46 00
82 64 00 01 01 30
```

effectId 19 — **Summer** (86 bytes)

```
7A 12 00 51 00 13 64 00 01 01 00 00 45 04 50 00
00 00 00 00 00 0F 64 00 32 64 64 00 32 64 46 00
BE 64 5A 00 BE 64 64 00 BE 64 64 00 BE 28 5A 00
BE 64 64 00 BE 64 64 00 BE 28 64 00 32 64 46 00
BE 64 5A 00 BE 64 64 00 BE 64 64 00 BE 28 5A 00
BE 64 00 01 01 1E
```

effectId 20 — **Autumn** (83 bytes)

```
7A 12 00 4E 00 14 64 00 01 01 00 00 42 0D 32 01
00 00 00 00 00 00 0E 64 00 19 5A 64 00 1E 64 64
00 1E 64 64 00 32 64 64 00 23 64 5A 00 32 46 64
00 0A 64 64 00 0A 64 64 00 19 5A 64 00 1E 64 64
00 19 5A 64 00 32 64 64 00 32 64 3C 00 19 64 00
01 01 25
```

effectId 21 — **Winter** (90 bytes)

```
7A 12 00 55 00 15 64 00 01 01 00 00 49 04 0F 00
00 00 00 00 00 10 64 00 DC 64 64 00 DC 64 1E 00
DC 64 64 00 DC 28 64 00 DC 64 3C 00 DC 64 1E 00
DC 64 64 00 DC 28 64 00 DC 64 3C 00 DC 64 1E 00
DC 64 64 00 DC 28 64 00 DC 64 3C 00 DC 64 1E 00
DC 64 1E 00 DC 64 00 01 01 80
```

effectId 22 — **Meteor** (100 bytes)

```
7A 12 00 5F 00 16 64 00 03 01 00 00 18 0F 62 00
01 00 00 06 06 00 05 00 00 00 00 00 01 01 00 64
00 D3 00 28 00 00 1F 0F 64 00 01 00 00 05 01 00
07 00 00 00 00 00 02 01 00 64 00 D3 00 28 01 00
64 00 D3 00 28 00 00 18 0F 5F 00 01 00 00 04 01
00 05 00 00 00 00 00 01 01 00 64 00 D3 00 28 00
00 01 01 BB
```

effectId 23 — **Lightning** (158 bytes)

```
7A 12 00 99 00 17 64 00 08 01 00 00 11 05 50 01
00 00 00 00 00 02 08 00 DC 3C 32 00 DC 3C 00 11
05 55 01 00 00 00 00 00 02 08 00 DC 3C 32 00 DC
3C 00 0E 01 4B 00 00 00 00 00 00 01 0A 64 00 DC
3C 00 11 05 3C 01 00 00 00 00 00 02 08 00 DC 3C
32 00 DC 3C 00 11 05 46 01 00 00 00 00 00 02 08
00 DC 3C 08 00 DC 3C 00 11 05 5A 01 00 00 00 00
00 02 08 00 DC 3C 32 00 DC 3C 00 0E 01 37 00 00
00 00 00 00 01 0A 64 00 DC 3C 00 0E 01 50 00 00
00 00 00 00 01 0A 64 00 DC 3C 00 01 01 25
```

effectId 24 — **Rainstorm** (228 bytes)

```
7A 12 00 DF 00 18 64 00 03 01 00 00 45 04 64 00
00 00 00 00 00 0F 64 00 C8 64 55 00 C8 64 4B 00
C8 64 3C 00 C8 64 32 00 C8 64 28 00 C8 64 1E 00
C8 64 14 00 C8 64 64 00 D3 64 3C 00 D3 64 28 00
D3 64 64 00 D3 64 3C 00 D3 64 28 00 D3 64 1E 00
D3 64 00 45 04 5F 00 00 00 00 00 00 0F 64 00 B4
64 4B 00 B4 64 32 00 B4 64 14 00 B4 64 64 00 B4
64 4B 00 B4 64 32 00 B4 64 14 00 B4 64 64 00 C8
64 55 00 C8 64 4B 00 C8 64 3C 00 C8 64 32 00 C8
64 28 00 C8 64 1E 00 C8 64 00 45 04 5F 00 00 00
00 00 00 0F 64 00 D3 64 3C 00 D3 64 28 00 D3 64
64 00 D3 64 3C 00 D3 64 28 00 D3 64 1E 00 D3 64
64 00 B4 64 4B 00 B4 64 32 00 B4 64 14 00 B4 64
64 00 B4 64 4B 00 B4 64 32 00 B4 64 14 00 B4 64
00 01 01 E1
```

**Life (effectId 25–36)**

effectId 25 — **Colorful** (43 bytes)

```
7A 12 00 26 00 19 64 00 01 01 00 00 1A 0D 5A 00
00 00 00 00 00 00 04 64 00 00 64 64 00 B4 64 64
01 68 64 64 00 B4 64 00 01 01 A9
```

effectId 26 — **Movie** (35 bytes)

```
7A 12 00 1E 00 1A 64 00 01 01 00 00 12 0B 19 00
00 00 00 00 00 00 02 64 00 E6 64 64 00 E6 28 00
01 01 84
```

effectId 27 — **Tea Time** (67 bytes)

```
7A 12 00 3E 00 1B 64 00 01 01 00 00 32 0D 28 01
00 00 00 00 00 00 0A 64 00 28 64 64 00 28 19 64
00 28 64 64 00 28 19 64 00 28 64 64 00 28 19 64
00 28 64 64 00 28 19 64 00 28 64 64 00 28 19 00
01 01 A8
```

effectId 28 — **Dream** (43 bytes)

```
7A 12 00 26 00 1C 64 00 01 01 00 00 1A 0D 3C 01
00 00 00 00 00 00 04 64 00 DC 50 64 01 4F 3C 64
00 DC 50 64 01 4F 3C 00 01 01 9E
```

effectId 29 — **Leisure** (51 bytes)

```
7A 12 00 2E 00 1D 64 00 01 01 00 00 22 0D 32 01
00 00 00 00 00 00 06 64 00 64 64 64 00 2D 64 64
00 64 64 64 00 2D 64 64 00 64 64 64 00 2D 64 00
01 01 0A
```

effectId 30 — **Technology** (75 bytes)

```
7A 12 00 46 00 1E 64 00 02 01 00 00 1C 0F 50 00
06 00 01 02 00 01 05 00 00 00 00 00 01 01 00 64
00 E1 00 64 01 64 00 E1 00 00 1C 0F 50 00 06 01
01 02 00 01 05 00 00 00 00 00 01 01 00 64 00 E1
00 64 01 64 00 E1 00 00 01 01 50
```

effectId 31 — **Morning** (51 bytes)

```
7A 12 00 2E 00 1F 64 00 01 01 00 00 22 0D 32 01
00 00 00 00 00 00 06 64 00 D2 64 64 00 32 64 64
00 D2 64 64 00 32 64 64 00 D2 64 64 00 32 64 00
01 01 65
```

effectId 32 — **Afternoon** (91 bytes)

```
7A 12 00 56 00 20 64 00 01 01 00 00 4A 0D 32 01
00 00 00 00 00 00 10 64 00 28 50 64 00 23 5F 64
00 19 64 64 00 23 5F 64 00 28 50 64 00 2D 32 64
00 2D 32 64 00 2D 32 64 00 2D 32 64 00 2D 32 64
00 2D 32 64 00 2D 32 64 00 2D 32 64 00 2D 32 64
00 2D 32 64 00 2D 32 00 01 01 CA
```

effectId 33 — **Wonder Glow** (69 bytes)

```
7A 12 00 40 00 21 64 00 01 01 00 00 34 0E 32 00
05 01 00 00 00 00 00 07 01 64 01 54 46 02 00 00
00 00 01 64 01 54 46 02 00 00 00 00 01 64 01 54
46 02 00 00 00 00 01 64 01 54 46 01 00 64 00 3C
64 00 01 01 E1
```

effectId 34 — **Romantic** (59 bytes)

```
7A 12 00 36 00 22 64 00 01 01 00 00 2A 0B 1E 00
00 00 00 00 00 00 08 1E 01 36 64 64 01 36 64 1E
01 1D 64 64 01 1D 64 1E 01 0E 64 64 01 0E 64 1E
01 1D 64 64 01 1D 64 00 01 01 D3
```

effectId 35 — **Summer Cool** (91 bytes)

```
7A 12 00 56 00 23 64 00 01 01 00 00 4A 0D 32 01
00 00 00 00 00 00 10 64 00 DC 64 64 00 DC 64 64
00 DC 1E 64 00 DC 1E 64 00 DC 64 64 00 DC 64 64
00 DC 1E 64 00 DC 1E 64 00 DC 64 64 00 DC 64 64
00 DC 1E 64 00 DC 1E 64 00 DC 64 64 00 DC 64 64
00 DC 1E 64 00 DC 1E 00 01 01 17
```

effectId 36 — **Lazy** (43 bytes)

```
7A 12 00 26 00 24 64 00 01 01 00 00 1A 0B 1E 00
00 00 00 00 00 00 04 64 00 3C 50 64 00 64 50 64
00 8C 50 64 00 B4 50 00 01 01 35
```

**Festive (effectId 37–43)**

effectId 37 — **Party** (56 bytes)

```
7A 12 00 33 00 25 64 00 01 01 00 00 27 01 50 00
00 00 00 00 00 06 14 64 00 B9 64 14 64 00 78 64
14 64 01 2C 64 14 64 01 68 64 14 64 00 3C 64 14
64 00 23 64 00 01 01 18
```

effectId 38 — **Birthday** (61 bytes)

```
7A 12 00 38 00 26 64 00 01 01 00 00 2C 0C 3C 01
05 05 05 00 00 00 00 00 08 64 00 00 64 64 00 23
64 64 00 3C 64 64 00 78 64 64 00 B4 64 64 00 DC
64 64 01 0E 64 64 01 40 64 00 01 01 D5
```

effectId 39 — **Prom** (101 bytes)

```
7A 12 00 60 00 27 64 00 01 01 00 00 54 01 50 00
00 00 00 00 00 0F 00 5A 00 14 64 00 5A 01 04 64
00 64 00 DC 64 00 5F 00 23 64 00 5A 00 FA 64 00
64 00 32 64 00 5A 00 14 64 00 5F 00 0A 64 00 64
01 40 64 00 64 01 40 64 00 5F 00 F5 64 00 5F 00
23 64 00 5A 01 22 64 00 64 00 32 64 00 5A 00 14
64 00 01 01 FC
```

effectId 40 — **Christmas** (86 bytes)

```
7A 12 00 51 00 28 64 00 01 01 00 00 45 04 32 00
00 00 00 00 00 0F 64 00 00 64 50 00 78 64 50 00
78 64 64 00 00 64 50 00 78 64 64 00 00 64 64 00
00 64 50 00 78 64 50 00 78 64 64 00 00 64 50 00
78 64 64 00 00 64 50 00 78 64 50 00 78 64 64 00
00 64 00 01 01 CF
```

effectId 41 — **Halloween** (62 bytes)

```
7A 12 00 39 00 29 64 00 01 01 00 00 2D 10 46 01
08 00 00 05 00 00 00 00 00 08 64 00 1E 64 64 00
1E 64 64 00 3C 64 5A 01 0E 64 64 00 1E 64 5A 01
0E 64 64 00 3C 64 64 00 1E 64 00 01 01 29
```

effectId 42 — **New Year** (86 bytes)

```
7A 12 00 51 00 2A 64 00 01 01 00 00 45 04 3C 00
00 00 00 00 00 0F 64 00 00 64 64 00 00 64 64 00
00 64 64 00 28 64 64 00 28 64 3C 00 A0 64 64 00
00 64 64 00 00 64 64 00 28 64 64 00 28 64 64 00
00 64 64 00 28 64 64 00 28 64 3C 00 A0 64 64 00
00 64 00 01 01 9B
```

effectId 43 — **Fireworks** (147 bytes)

```
7A 12 00 8E 00 2B 64 00 04 01 00 00 26 0F 64 00
01 00 00 0A 03 00 07 00 00 00 00 00 03 01 00 64
00 1E 00 64 01 00 64 00 78 00 64 01 00 64 00 0A
00 64 00 00 18 01 46 00 00 00 00 00 00 03 0A 64
00 1E 64 0A 64 00 78 64 0A 64 00 0A 64 00 26 0F
64 00 01 00 00 0A 03 00 07 00 00 00 00 00 03 01
00 64 00 C3 00 64 01 00 64 01 18 00 64 01 00 64
00 AF 00 64 00 00 18 01 46 00 00 00 00 00 00 03
0A 64 00 C3 64 0A 64 01 18 64 0A 64 00 AF 64 00
01 01 CE
```

**Emotional (effectId 44–51)**

effectId 44 — **Sweet** (59 bytes)

```
7A 12 00 36 00 2C 64 00 01 01 00 00 2A 0D 32 01
00 00 00 00 00 00 08 64 01 54 46 64 01 54 14 64
01 54 46 64 01 54 14 64 01 54 46 64 01 54 14 64
01 54 46 64 01 54 14 00 01 01 F8
```

effectId 45 — **Passionate** (52 bytes)

```
7A 12 00 2F 00 2D 64 00 01 01 00 00 23 0F 50 00
06 00 01 02 00 01 04 00 00 00 00 00 02 01 00 64
00 00 00 64 01 00 64 00 1E 00 64 01 64 00 00 00
00 01 01 F7
```

effectId 46 — **Comfortable** (51 bytes)

```
7A 12 00 2E 00 2E 64 00 01 01 00 00 22 0D 32 01
00 00 00 00 00 00 06 64 00 B4 64 64 00 78 64 64
00 B4 64 64 00 78 64 64 00 B4 64 64 00 78 64 00
01 01 EC
```

effectId 47 — **Mysterious** (43 bytes)

```
7A 12 00 26 00 2F 64 00 01 01 00 00 1A 0D 28 01
00 00 00 00 00 00 04 1E 00 F0 64 64 01 0E 64 1E
00 F0 64 64 01 0E 64 00 01 01 2F
```

effectId 48 — **Joyful** (62 bytes)

```
7A 12 00 39 00 30 64 00 01 01 00 00 2D 10 5A 01
05 00 00 00 00 00 00 00 00 08 64 00 0F 3C 64 00
28 64 64 00 23 32 64 00 41 64 64 00 55 64 64 00
55 32 64 00 B9 50 64 00 DC 64 00 01 01 7C
```

effectId 49 — **Melancholic** (67 bytes)

```
7A 12 00 3E 00 31 64 00 01 01 00 00 32 0D 28 01
00 00 00 00 00 00 0A 28 00 FA 64 46 00 BE 64 28
00 FA 64 46 00 BE 64 28 00 FA 64 46 00 BE 64 28
00 FA 64 46 00 BE 64 28 00 FA 64 46 00 BE 64 00
01 01 7B
```

effectId 50 — **Excited** (87 bytes)

```
7A 12 00 52 00 32 64 00 01 01 00 00 46 0F 55 00
06 01 01 01 00 01 01 00 00 00 00 00 07 01 00 64
00 1E 00 64 01 00 64 00 1E 00 46 01 00 64 00 2D
00 64 01 00 64 00 DC 00 32 01 00 64 00 DC 00 64
01 00 64 00 C8 00 32 01 00 64 00 1E 00 32 01 64
00 00 00 00 01 01 6B
```

effectId 51 — **Heartbeat** (192 bytes)

```
7A 12 00 BC 00 33 64 00 03 01 00 00 0E 01 1E 00
00 00 00 00 00 01 14 64 00 00 64 00 4F 01 46 01
00 00 00 00 00 0E 14 64 00 00 14 14 64 00 00 1E
14 64 00 00 28 14 64 00 00 32 14 64 00 00 41 14
64 00 00 50 14 64 00 00 64 14 64 00 00 64 14 64
00 00 50 14 64 00 00 41 14 64 00 00 32 14 64 00
00 28 14 64 00 00 1E 14 64 00 00 14 00 4F 01 46
01 00 00 00 00 00 0E 14 64 00 00 64 14 64 00 00
50 14 64 00 00 41 14 64 00 00 32 14 64 00 00 28
14 64 00 00 1E 14 64 00 00 14 14 64 00 00 14 14
64 00 00 1E 14 64 00 00 28 14 64 00 00 32 14 64
00 00 41 14 64 00 00 50 14 64 00 00 64 00 01 01
```

**Sport (effectId 52–73)**

effectId 52 — **Dallas Football** (123 bytes)

```
7A 12 00 76 00 34 64 00 04 01 00 00 1D 10 50 00
04 00 01 01 00 00 00 00 00 04 1E 00 D7 5F 46 00
D7 00 1E 00 D7 64 46 00 D7 00 00 1D 10 50 00 04
01 01 01 00 00 00 00 00 04 46 00 D7 00 1E 00 D7
5F 46 00 D7 00 1E 00 D7 5F 00 15 10 64 00 01 00
00 01 00 00 00 00 00 02 1E 00 D7 5F 46 00 D7 00
00 15 10 64 00 01 01 00 01 00 00 00 00 00 02 46
00 D7 00 1E 00 D7 5F 00 01 01 76
```

effectId 53 — **New England Football** (120 bytes)

```
7A 12 00 73 00 35 64 00 03 01 00 00 21 04 32 00
00 00 00 00 00 06 32 00 00 64 32 00 DC 64 50 00
00 00 32 00 00 64 32 00 DC 64 50 00 00 00 00 21
04 32 01 00 00 00 00 00 06 50 00 00 00 32 00 DC
64 32 00 00 64 50 00 00 00 32 00 DC 64 32 00 00
64 00 21 05 46 01 00 00 00 00 00 06 32 00 00 64
32 00 DC 64 50 00 00 00 32 00 00 64 32 00 DC 64
50 00 00 00 00 01 01 DC
```

effectId 54 — **Kansas City Football** (213 bytes)

```
7A 12 00 D0 00 36 64 00 05 01 00 00 31 0F 5A 00
02 00 01 05 01 00 02 00 00 00 00 00 04 01 00 46
01 5E 00 64 01 00 32 01 5E 00 00 01 00 46 01 5E
00 64 01 00 32 01 5E 00 00 01 00 00 00 00 00 1D
10 5A 00 02 00 01 01 00 00 00 00 00 04 46 01 5E
64 32 01 5E 00 46 01 5E 64 32 01 5E 00 00 31 0F
5A 00 02 01 01 05 01 00 02 00 00 00 00 00 04 01
00 32 01 5E 00 00 01 00 46 01 5E 00 64 01 00 32
01 5E 00 00 01 00 46 01 5E 00 64 01 00 00 00 00
00 1D 10 5A 00 02 01 01 01 00 00 00 00 00 04 32
01 5E 00 46 01 5E 64 32 01 5E 00 46 01 5E 64 00
20 0C 46 01 03 03 05 00 00 00 00 00 05 46 01 5E
64 32 01 5E 00 46 01 5E 64 32 01 5E 00 46 01 5E
64 00 01 01 0A
```

effectId 55 — **Madrid Soccer** (143 bytes)

```
7A 12 00 8A 00 37 64 00 05 01 00 00 1A 0D 32 01
00 00 00 00 00 00 04 50 00 00 64 50 00 2D 64 50
00 00 64 50 00 2D 64 00 16 0D 46 00 00 00 00 00
00 00 03 50 00 00 64 00 00 00 64 50 00 00 64 00
16 0D 46 00 00 00 00 00 00 00 03 50 00 2D 64 00
00 2D 64 50 00 2D 64 00 16 0D 46 00 00 00 00 00
00 00 03 50 00 D2 64 00 00 D2 64 50 00 D2 64 00
1A 0B 32 00 00 00 00 00 00 00 04 50 00 2D 64 50
00 00 64 50 00 2D 64 50 00 00 64 00 01 01 6B
```

effectId 56 — **Barcelona Soccer** (119 bytes)

```
7A 12 00 72 00 38 64 00 04 01 00 00 21 04 32 00
00 00 00 00 00 06 32 00 DC 64 32 00 00 64 46 00
32 64 32 00 DC 64 32 00 00 64 46 00 32 64 00 15
05 46 01 00 00 00 00 00 03 46 00 32 64 32 00 00
64 32 00 DC 64 00 15 04 32 01 00 00 00 00 00 03
46 00 32 64 32 00 00 64 32 00 DC 64 00 15 05 46
01 00 00 00 00 00 03 32 00 00 64 46 00 32 64 32
00 DC 64 00 01 01 89
```

effectId 57 — **Manchester Soccer** (137 bytes)

```
7A 12 00 84 00 39 64 00 05 01 00 00 1A 0D 28 01
00 00 00 00 00 00 04 46 00 00 64 14 00 00 64 50
00 32 64 14 00 32 64 00 1A 0D 28 01 00 00 00 00
00 00 04 46 00 00 64 14 00 00 64 50 00 32 64 14
00 32 64 00 11 05 37 01 00 00 00 00 00 02 46 00
00 64 50 00 32 64 00 1A 0D 28 00 00 00 00 00 00
00 04 46 00 00 64 50 00 32 64 46 00 00 64 50 00
32 64 00 11 05 37 01 00 00 00 00 00 02 50 00 32
64 46 00 00 64 00 01 01 F4
```

effectId 58 — **Paris Soccer** (169 bytes)

```
7A 12 00 A4 00 3A 64 00 06 01 00 00 1D 10 5A 00
02 00 01 01 00 00 00 00 00 04 1E 00 DC 64 32 00
00 64 1E 00 DC 64 32 00 00 64 00 15 10 64 00 01
01 00 01 00 00 00 00 00 02 32 00 00 64 1E 00 DC
64 00 1D 10 5A 00 02 01 01 01 00 00 00 00 00 04
32 00 00 64 1E 00 DC 64 32 00 00 64 1E 00 DC 64
00 15 10 64 00 01 00 00 01 00 00 00 00 00 02 1E
00 DC 64 32 00 00 64 00 15 10 55 00 04 00 01 01
00 00 00 00 00 02 32 00 00 64 1E 00 DC 64 00 15
10 55 00 04 01 01 01 00 00 00 00 00 02 1E 00 DC
64 32 00 00 64 00 01 01 B6
```

effectId 59 — **Munich Soccer** (144 bytes)

```
7A 12 00 8B 00 3B 64 00 05 01 00 00 19 04 32 00
00 00 00 00 00 04 46 00 00 64 46 00 DC 64 46 00
00 64 46 00 DC 64 00 1C 11 05 00 00 00 00 00 04
01 46 00 00 64 01 46 00 DC 64 01 46 00 00 64 01
46 00 DC 64 00 17 11 05 00 00 00 00 00 03 01 46
00 00 64 01 46 00 DC 64 01 46 00 00 64 00 12 11
05 00 00 00 00 00 02 01 46 00 DC 64 01 46 00 00
64 00 19 05 46 01 00 00 00 00 00 04 46 00 DC 64
46 00 00 64 46 00 DC 64 46 00 00 64 00 01 01 3D
```

effectId 60 — **Los Angeles Basketball** (107 bytes)

```
7A 12 00 66 00 3C 64 00 04 01 00 00 19 04 32 00
00 00 00 00 00 04 46 00 2D 64 46 01 18 64 46 00
2D 64 46 01 18 64 00 11 05 46 01 00 00 00 00 00
02 46 01 18 64 46 00 2D 64 00 19 04 32 00 00 00
00 00 00 04 46 01 18 64 46 00 2D 64 46 01 18 64
46 00 2D 64 00 11 05 46 01 00 00 00 00 00 02 46
00 2D 64 46 01 18 64 00 01 01 99
```

effectId 61 — **Golden State Basketball** (123 bytes)

```
7A 12 00 76 00 3D 64 00 04 01 00 00 1D 10 5F 00
02 01 01 01 00 00 00 00 00 04 32 00 D2 64 46 00
2F 64 32 00 D2 64 46 00 2F 64 00 15 10 50 00 04
00 01 01 00 00 00 00 00 02 46 00 2F 64 32 00 D2
64 00 15 10 5F 00 02 01 01 01 00 00 00 00 00 02
46 00 2F 64 32 00 D2 64 00 1D 10 50 00 04 00 01
01 00 00 00 00 00 04 32 00 D2 64 46 00 2F 64 32
00 D2 64 46 00 2F 64 00 01 01 54
```

effectId 62 — **Chicago Basketball** (155 bytes)

```
7A 12 00 96 00 3E 64 00 05 01 00 00 1A 0D 28 01
00 00 00 00 00 00 04 50 01 59 5A 14 01 59 5A 50
01 59 5A 14 01 59 5A 00 1A 0D 28 01 00 00 00 00
00 00 04 50 01 59 5A 14 01 59 5A 50 01 59 5A 14
01 59 5A 00 1A 0B 1E 00 00 00 00 00 00 00 04 50
01 59 5A 14 01 59 5A 50 01 59 5A 14 01 59 5A 00
1A 0D 3C 00 00 00 00 00 00 00 04 14 01 59 5A 50
01 59 5A 14 01 59 5A 50 01 59 5A 00 1A 0B 1E 00
00 00 00 00 00 00 04 50 01 59 5A 14 01 59 5A 50
01 59 5A 14 01 59 5A 00 01 01 61
```

effectId 63 — **Boston Basketball** (154 bytes)

```
7A 12 00 95 00 3F 64 00 04 01 00 00 21 10 50 00
04 00 01 01 00 00 00 00 00 05 1E 00 78 64 28 00
0A 46 2D 00 28 64 1E 00 78 64 28 00 0A 46 00 24
0C 46 01 03 03 06 00 00 00 00 00 06 28 00 0A 46
1E 00 78 64 2D 00 28 64 28 00 0A 46 1E 00 78 64
2D 00 28 64 00 21 10 50 00 04 01 01 01 00 00 00
00 00 05 2D 00 28 64 1E 00 78 64 28 00 0A 46 2D
00 28 64 1E 00 78 64 00 1D 05 4B 01 00 00 00 00
00 05 1E 00 78 64 28 00 0A 46 2D 00 28 64 1E 00
78 64 28 00 0A 46 00 01 01 4E
```

effectId 64 — **New York Baseball** (139 bytes)

```
7A 12 00 86 00 40 64 00 03 01 00 00 22 0B 32 01
00 00 00 00 00 00 06 1E 00 E1 64 64 00 E1 0F 1E
00 E1 64 64 00 E1 0F 1E 00 E1 64 64 00 E1 0F 00
2A 0D 37 01 00 00 00 00 00 00 08 1E 00 E1 64 1E
00 E1 64 64 00 E1 0F 64 00 E1 0F 64 00 E1 0F 1E
00 E1 64 64 00 E1 0F 1E 00 E1 64 00 2A 0D 37 01
00 00 00 00 00 00 08 1E 00 E1 64 1E 00 E1 64 64
00 E1 0F 64 00 E1 0F 64 00 E1 0F 1E 00 E1 64 64
00 E1 0F 1E 00 E1 64 00 01 01 ED
```

effectId 65 — **Los Angeles Baseball** (235 bytes)

```
7A 12 00 E6 00 41 64 00 06 01 00 00 22 0D 41 01
00 00 00 00 00 00 06 64 00 D2 00 1E 00 D2 64 1E
00 D2 64 00 00 D2 64 00 00 D2 64 00 00 D2 64 00
26 0D 41 01 00 00 00 00 00 00 07 1E 00 D2 64 64
00 D2 00 1E 00 D2 64 1E 00 D2 64 00 00 D2 64 00
00 D2 64 00 00 D2 64 00 22 0D 5A 01 01 00 00 00
00 00 06 64 00 D2 00 1E 00 D2 64 1E 00 D2 64 00
00 D2 64 00 00 D2 64 00 00 D2 64 00 22 0D 41 01
00 00 00 00 00 00 06 1E 00 D2 64 64 00 D2 00 1E
00 D2 64 00 00 D2 64 00 00 D2 64 00 00 D2 64 00
22 0D 41 01 00 00 00 00 00 00 06 1E 00 D2 64 64
00 D2 00 1E 00 D2 64 00 00 D2 64 00 00 D2 64 00
00 D2 64 00 22 0D 5A 01 01 00 00 00 00 00 06 64
00 D2 00 1E 00 D2 64 1E 00 D2 64 00 00 D2 64 00
00 D2 64 00 00 D2 64 00 01 01 77
```

effectId 66 — **Boston Baseball** (71 bytes)

```
7A 12 00 42 00 42 64 00 02 01 00 00 1A 0D 2D 01
00 00 00 00 00 00 04 23 00 00 64 0A 00 00 64 64
00 00 00 23 00 00 64 00 1A 0D 2D 01 01 00 00 00
00 00 04 1E 00 DC 64 0A 00 DC 64 64 00 DC 00 1E
00 DC 64 00 01 01 52
```

effectId 67 — **Chicago Baseball** (140 bytes)

```
7A 12 00 87 00 43 64 00 03 01 00 00 31 0F 3C 00
03 00 00 03 01 00 02 00 00 00 00 00 04 01 00 3C
00 00 00 64 01 00 24 00 D7 00 64 01 00 3C 00 00
00 64 01 00 24 00 D7 00 64 01 64 00 00 00 00 23
0F 3C 00 03 01 01 03 00 00 02 00 00 00 00 00 02
01 00 3C 00 00 00 64 01 00 3C 00 00 00 64 01 00
00 00 00 00 23 0F 3C 00 03 00 01 03 00 00 02 00
00 00 00 00 02 01 00 24 00 D7 00 64 01 00 24 00
D7 00 64 01 00 00 00 00 00 01 01 A7
```

effectId 68 — **San Francisco Baseball** (75 bytes)

```
7A 12 00 46 00 44 64 00 02 01 00 00 1C 0F 50 00
03 00 01 05 00 01 02 00 00 00 00 00 01 01 00 64
00 1C 00 64 01 00 00 00 00 00 1C 0F 50 00 03 01
01 05 00 01 02 00 00 00 00 00 01 01 00 64 00 1C
00 64 01 00 00 00 00 00 01 01 5C
```

effectId 69 — **Toronto Hockey** (71 bytes)

```
7A 12 00 42 00 45 64 00 02 01 00 00 1A 0D 37 01
00 00 00 00 00 00 04 32 00 DC 64 0A 00 DC 64 32
00 DC 64 0A 00 DC 64 00 1A 0D 37 01 01 00 00 00
00 00 04 32 00 DC 64 0A 00 DC 64 32 00 DC 64 0A
00 DC 64 00 01 01 33
```

effectId 70 — **Montreal Hockey** (149 bytes)

```
7A 12 00 90 00 46 64 00 03 01 00 00 35 04 32 00
00 00 00 00 00 0B 23 00 D7 64 64 00 00 00 32 00
00 64 32 00 00 64 64 00 00 00 23 00 D7 64 64 00
00 00 32 00 00 64 32 00 00 64 64 00 00 00 23 00
D7 64 00 38 0C 46 01 03 03 05 00 00 00 00 00 0B
23 00 D7 64 64 00 00 00 32 00 00 64 32 00 00 64
64 00 00 00 23 00 D7 64 64 00 00 00 32 00 00 64
32 00 00 64 64 00 00 00 23 00 D7 64 00 13 01 46
00 00 00 00 00 00 02 00 23 00 D7 64 00 32 00 00
64 00 01 01 37
```

effectId 71 — **Chicago Hockey** (116 bytes)

```
7A 12 00 6F 00 47 64 00 03 01 00 00 1D 10 41 00
04 00 00 01 00 00 00 00 00 04 64 00 00 64 64 00
32 64 28 00 9B 64 64 00 1E 64 00 21 04 41 00 00
00 00 00 00 06 23 00 9B 64 64 00 32 64 64 00 00
64 64 00 1E 64 64 00 00 64 23 00 9B 64 00 21 04
41 01 00 00 00 00 00 06 64 00 00 64 64 00 1E 64
64 00 32 64 28 00 9B 64 64 00 1E 64 28 00 9B 64
00 01 01 5B
```

effectId 72 — **New York Hockey** (101 bytes)

```
7A 12 00 60 00 48 64 00 02 01 00 00 29 04 3C 00
00 00 00 00 00 08 28 00 DC 64 64 00 DC 00 28 00
DC 64 64 00 DC 00 28 00 00 64 28 00 DC 64 64 00
DC 00 28 00 DC 64 00 29 04 3C 01 00 00 00 00 00
08 64 00 DC 00 28 00 DC 64 64 00 DC 00 28 00 DC
64 28 00 00 64 28 00 00 64 64 00 DC 00 28 00 DC
64 00 01 01 7C
```

effectId 73 — **Las Vegas Hockey** (64 bytes)

```
7A 12 00 3B 00 49 64 00 02 01 00 00 1A 0D 32 00
00 00 00 00 00 00 04 4B 00 2D 64 14 00 2D 64 4B
00 2D 64 14 00 2D 64 00 13 01 1E 00 00 00 00 00
00 02 00 41 00 2D 64 00 41 00 2D 64 00 01 01 B0
```


#### Scene Command Implementation

Each scene is sent as a fixed BLE packet with brightness substituted. The pattern in `lights.json`:

```
0x7A 0x12 {size16} <effectId_hi> <effectId_lo> {brr:uint8:range(0,100)} 0x00 <fixed payload bytes> {checksum}
```

- `{size16}` — 2-byte big-endian payload size, computed by `CommandPatternParser`
- `{brr:uint8:range(0,100)}` — brightness 0–100 (integer, **not** BCD-encoded for scenes)
- `0x00` — brr_lo, always zero (scenes use integer brightness, not 0.1% precision)
- Fixed payload — the remaining bytes from the BLE capture (effect parameters, colors, trailer)
- `{checksum}` — standard byte-sum checksum

> **Brightness encoding differs from CCT/HSI.** Scene brightness is a single integer byte (0–100), not the BCD-split format used by CCT (`value/10`, `value%10`). The `brr_lo` byte is always `0x00`.

#### Cloud API (Scene Catalog Source)

The scene catalog is originally served from Neewer's cloud API:

```
POST https://homeapp.neewer.cn/neewerhome/app/device/sceneEffect/getSceneEffectByDeviceId
Headers: accessToken: <user_token>, Content-Type: application/json
Body: {"deviceId": "<product_id>", "firmwareVersion": "<version>"}
```

**Response structure:**
```json
{
  "list": [
    {
      "effectTypeName": "Natural",    // Category name
      "effectData": [
        {
          "id": 123,
          "effectId": 1,
          "effectType": "...",
          "effectName": "Rainbow",    // Display name
          "icon": "https://...",      // Normal icon URL
          "selectedIcon": "https://...", // Selected state icon URL
          "command": "7A12001E..."    // Pre-built BLE hex packet
        }
      ]
    }
  ]
}
```

**Categories:** Natural (24 scenes), Life (12), Festive (7), Emotional (8), Sports (22) = **73 total**

> **Authentication required:** The API requires a valid user token (email/phone login via NEEWER Home app). To capture the full catalog, use a MITM proxy while opening the scene page in NEEWER Home, or capture BLE packets while triggering each scene.

> **NeewerLite approach:** All 73 scene packets were captured via BLE traces and stored as parameterized patterns in `lights.json` (`nh_scene_ns02` preset). No cloud API access is needed at runtime.

#### Pre-built Command Shortcut

When the API provides a `command` hex string, the app sends it directly as a BLE packet **without going through `conversionData()`**. For built-in scenes, only brightness is adjusted at send time — all other parameters (speed, colors, animation mode) are fixed in the pre-built packet. The `conversionData()` method (3046 instructions) is only used for custom DIY effects.

### Mixed Mode (Per-Panel)

**Class:** `SendMixedBean` — Long Size Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x11` |
| size_hi, size_lo | payload length |
| data[0] | brightness / 10 |
| data[1] | brightness % 10 |
| data[2] | `0x00` |
| data[3] | panel count |
| | **Per panel:** |
| +0 | panel index |
| +1 | panel switch (on/off) |
| +2 | speed |
| +3,+4 | sub-payload size (big-endian) |
| +5 | panel control type: `0x01`=CCT, `0x02`=color |
| | **If CCT:** `0x00`, brightness, temperature |
| | **If color type 2 (HSI):** count_hi, count_lo, then per-color: lightness, hue_hi, hue_lo, sat |
| | **If color type 4 (gradient):** gradient_effect, count_hi, count_lo, 4×0x00, then per-color |
| checksum | sum & 0xFF |

### Query Device Parameters

**Class:** `QueryDeviceAllParametersBean` / `QueryDeviceCurrentModeParametersBean` — Standard Packet

| Byte | Value |
|------|-------|
| head | `0x7A` |
| dataId | `0x08` |
| size | `0x01` |
| data[0] | `0x00` = query all, `0x01` = query current mode |
| checksum | sum & 0xFF |

**Examples:**

```
Query All:     7A 08 01 00 83
Query Current: 7A 08 01 01 84
```

## Response Mode IDs

From `NotifyDeviceParametersBean`:

| ID | Mode |
|----|------|
| 0 | Switch (power state) |
| 1 | Lighting (CCT) |
| 2 | Color (HSI) |
| 3 | Scene |
| 4 | Music |
| 5 | DIY |
| 6 | Mixed |
| 8 | DIY V2 |
| 9 | TV Screen |
| 10 | 2D Scene |
| 11 | 2D Music |

## NS02 Capabilities

From `DeviceModel.java`:

| Capability | Supported |
|------------|-----------|
| Color (HSI) | Yes |
| Scene effects | Yes |
| Normal DIY | Yes |
| Advanced DIY | No |
| Music reactive | Yes (standard, not 2D) |
| Multi-panel | No |
| Multi-segment | No |
| 2D mode | No |
| AI features | Yes |
| BLE OTA preferred | Yes |

## Comparison: Old Protocol (`0x78`) vs New Protocol (`0x7A`)

| Feature | Old (`0x78`) | New (`0x7A`) |
|---------|-------------|-------------|
| Prefix byte | `0x78` (120) | `0x7A` (122) |
| Power tag | `0x81` | `0x0A` |
| CCT tag | `0x87` | `0x0C` |
| HSI tag | `0x86` | `0x0D` (LongSizePacket) |
| Scene tag | `0x88` / `0x8B` | `0x12` (LongSizePacket) |
| Music tag | N/A | `0x0E` |
| Read/Query tag | `0x84` | `0x08` |
| Brightness encoding | Single byte (0–100) | BCD split: `value/10`, `value%10` |
| Size field | 1 byte | 1 byte (standard) or 2 bytes BE (long) |
| Checksum | Same algorithm | Same algorithm |
| HSI hue encoding | 1 byte (0–360 mapped) | 2 bytes big-endian (0–360) |

## Source Files (Decompiled)

Key classes from `com.neewer.libprotocol.bean`:
- `Packet.java` — Base packet frame (standard 1-byte size)
- `LongSizePacket.java` — Extended packet frame (2-byte size)

Key classes from `com.neewer.libcommon.model.protocol.write`:
- `SendDeviceSwitchBean.java` — Power on/off
- `SendLightingBean.java` — CCT mode
- `SendFixedBrightnessBean.java` — Brightness only
- `SendAllColorBean.java` — Solid HSI color
- `SendChooseColorBean.java` — Per-segment color
- `SendGradientColorBean.java` — Gradient color
- `SendMusicDataBean.java` — Music reactive
- `SendSceneEffectBean.java` — Scene effects
- `SendMixedBean.java` — Per-panel mixed mode
- `QueryDeviceAllParametersBean.java` — Query all params
- `QueryDeviceCurrentModeParametersBean.java` — Query current mode

Device model registry:
- `com.neewer.libcommon.model.DeviceModel.java` — Product ID → capability mapping

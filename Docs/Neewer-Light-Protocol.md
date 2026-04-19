# Neewer Light Control Protocol Research

This document outlines the reverse engineering process and findings for Neewer lighting devices, including command protocols and packet structures.

## Table of Contents
- [Android App Reverse Engineering](#android-app-reverse-engineering)
- [iOS Bluetooth Packet Logging](#ios-bluetooth-packet-logging)
- [CB60 RGB Command Protocol](#cb60-rgb-command-protocol)
- [GL1C Command Protocol](#gl1c-command-protocol)
- [RGB62 Light Command Protocol](#rgb62-light-command-protocol)

## Android App Reverse Engineering

### Prerequisites
- Install [jadx](https://github.com/skylot/jadx) for decompiling Android APK files:
  ```bash
  brew install jadx
  ```

### Process
1. **Download APK**: Get the latest Neewer APK from [APKCombo](https://apkcombo.com/neewer/neewer.nginx.annularlight/download/apk)

2. **Extract APK contents**:
   ```bash
   unzip Neewer_5.0.5_Apkpure.apk
   ```

3. **Decompile DEX files** to Java source code:
   ```bash
   jadx classes.dex
   jadx classes2.dex
   jadx classes3.dex
   jadx classes4.dex
   jadx classes5.dex
   ```

## iOS Bluetooth Packet Logging

### Prerequisites
1. **Install Neewer iOS App**: Download from the [App Store](https://apps.apple.com/us/app/neewer/id1455948340)
2. **Enable Bluetooth Logging**: Install [iOSBluetoothLogging.mobileconfig](https://tc-downloads.s3.amazonaws.com/support/iOSBluetoothLogging.mobileconfig) on your iPhone and enable it.
3. On your Macbook(macOS 15.5), **Get PacketLogger**: Download PacketLogger.app from Apple Developer Portal or use the [local copy](https://github.com/keefo/NeewerLite/blob/main/Docs/PacketLogger.zip)

### Setup Process
1. Connect your iPhone to your macOS device via USB cable
2. Launch PacketLogger.app and start logging iPhone Bluetooth packets
3. Filter by **Packet Type: ATT Send** to focus on relevant traffic
4. Use the Neewer iOS app to control your light
5. Monitor the packet stream in PacketLogger to capture command sequences.
6. Copy the captured command sequences and shared it.

The command sequences should be something looks like these:

```
Jul 25 01:43:44.423  ATT Send         0x0050  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 372F 0000 9C  
Jul 25 01:43:44.519  ATT Send         0x0050  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 371A 0000 87  
Jul 25 01:43:44.622  ATT Send         0x0050  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3714 0000 81  
```

**Reference**: [TwoCanoes Bluetooth Packet Capture Guide](https://twocanoes.com/knowledge-base/capture-bluetooth-packet-trace-on-ios/)

## CB60 RGB Command Protocol

### CCT + GM (Green/Magenta) Commands

The CB60 RGB supports Color Temperature (CCT) adjustment from 2700K to 6500K with Green/Magenta tint control:

**Example Commands:**
- CCT 2700K + -50GM: `7890 0BDF 243A B446 5D87 1D1B 0004 CE`
- CCT 6500K + +50GM: `7890 0BDF 243A B446 5D87 1D41 6404 F4`

**Command Structure:**
```
CMD  TAG  SIZE    MAC               subTAG  INT  CCT  GM  DIMMING  CHECKSUM
78   90   0B    DF243AB4465D        87     1D   1B   00    04       CE
78   90   0B    DF243AB4465D        87     1D   41   64    04       F4
```

**Parameter Ranges:**
- CCT: `0x1B` (2700K) to `0x41` (6500K)
- GM: `0x00` (-50 Green) to `0x64` (+50 Magenta)

### Scene Effect Commands

The CB60 RGB supports 17 different scene effects with the following command structure:

**Command Structure:**
```
CMD  TAG  SIZE    MAC               SCE_TAG  SCE_ID  BRR  COLOR  SPEED  CHECKSUM
78   91   0B    DF243AB4465D        8B       11      07   01     03     4F
```

**Scene Effect Types:**

| Scene Name      | ID | Parameters |
|-----------------|----| -----------|
| Lighting        | 01 | BRR, CCT, SPEED |
| Paparazzi       | 02 | BRR, CCT, GM, SPEED |
| Defective Bulb  | 03 | BRR, CCT, GM, SPEED |
| Explosion       | 04 | BRR, CCT, GM, SPEED, Sparks (01-0A) |
| Welding         | 05 | BRR_low, BRR_high, CCT, GM, SPEED |
| CCT Flash       | 06 | BRR, CCT, GM, SPEED |
| HUE Flash       | 07 | BRR, HUE (2-byte LE 0000-6801), SAT (00-64), SPEED |
| CCT Pulse       | 08 | BRR, CCT, GM, SPEED |
| HUE Pulse       | 09 | BRR, HUE (2-byte LE 0000-6801), SAT (00-64), SPEED |
| Cop Car         | 0A | BRR, Color Mode (00-05), SPEED |
| Candlelight     | 0B | BRR_low, BRR_high, CCT, GM, SPEED, Sparks |
| HUE Loop        | 0C | BRR, HUE_low, HUE_high, SPEED |
| CCT Loop        | 0D | BRR, CCT_low, CCT_high, SPEED |
| INT Loop        | 0E | BRR_low, BRR_high, HUE, SPEED |
| TV Screen       | 0F | BRR, CCT, GM, SPEED |
| Firework        | 10 | BRR, Color Mode (00-02), SPEED, Sparks |
| Party           | 11 | BRR, Color Mode (00-02), SPEED |

**Cop Car Color Modes:**
- `00`: Red only
- `01`: Blue only  
- `02`: Red and Blue
- `03`: White and Blue
- `04`: Red, Blue, White
- `05`: All colors

**Example Commands:**
```
// Cop Car - Red only (Color 00)
7891 0BDF 243A B446 5D8B 0A32 0005 74

// Cop Car - Blue only (Color 01)  
7891 0BDF 243A B446 5D8B 0A32 0105 75
```

**Device Info:**
- Model: CB60 RGB
- Identifier: NW-20210012&FFFFFFFF

## GL1C Command Protocol

### FX — Cop Car (Color Modes)

| Color Mode | Command |
|------------|---------|
| Blue | `788B 040A 1000 0526` |
| Red → Blue | `788B 040A 1001 0527` |
| Blue + Red | `788B 040A 1002 0528` |
| White + Blue | `788B 040A 1003 0529` |
| White + Blue + Red | `788B 040A 1004 052A` |

Additional capture: `788B 040A 0004 0217`

### FX — Music Reactive

```
788B 0212 3249
```

### FX — Party (Color + Speed)

| Variant | Command |
|---------|---------|
| Color 0 | `788B 0411 3200 054F` |
| Color 1 | `788B 0411 3201 0550` |
| Color 1 + Speed 9 | `788B 0411 3200 0953` |
| Color 1 + Speed 6 | `788B 0411 3200 0650` |
| Color 1 + Speed 1 | `788B 0411 3200 014B` |

### Light Source — Tungsten

**Brightness changes** (CCT=0x20, GM=0x32):
```
7887 0346 2032 9A   // BRR=0x46
7887 032F 2032 83   // BRR=0x2F
7887 0319 2032 6D   // BRR=0x19
```

**CCT changes** (BRR=0x3E, GM=0x32):
```
7887 033E 1E32 90   // CCT=0x1E
7887 033E 1F32 91   // CCT=0x1F
7887 033E 2032 92   // CCT=0x20
```

**GM changes** (BRR=0x3E, CCT=0x20):
```
7887 033E 2028 88   // GM=0x28
7887 033E 2044 A4   // GM=0x44
7887 033E 2061 C1   // GM=0x61
7887 033E 2064 C4   // GM=0x64
```

## RGB62 Light Command Protocol

### Power Control Commands

**Power OFF:**
```
7881 0102 FC
```

**Power ON:**
```
7881 0101 FB
```

### HSI Mode Color Control

The RGB62 supports HSI (Hue, Saturation, Intensity) color adjustments. Example sequence showing color transitions:

```
7886 040C 0132 3273  // Hue: 0C, Saturation: 32, Intensity: 32
7886 0413 0133 327B  // Hue: 13, Saturation: 33, Intensity: 32
7886 0415 0134 327E  // Hue: 15, Saturation: 34, Intensity: 32
7886 041F 0136 328A  // Hue: 1F, Saturation: 36, Intensity: 32
7886 0426 0138 3293  // Hue: 26, Saturation: 38, Intensity: 32
7886 0428 0139 3296  // Hue: 28, Saturation: 39, Intensity: 32
```

### CCT Mode Controls

**Green/Magenta Adjustment:**
```
7887 0532 2115 0000 6C  // CCT: 32, GM: 21
7887 0532 2315 0000 6E  // CCT: 32, GM: 23
7887 0532 2615 0000 71  // CCT: 32, GM: 26
7887 0532 2715 0000 72  // CCT: 32, GM: 27
7887 0532 2915 0000 74  // CCT: 32, GM: 29
7887 0532 2F15 0000 7A  // CCT: 32, GM: 2F
7887 0532 3115 0000 7C  // CCT: 32, GM: 31
```

**Color Temperature Adjustment:**
```
7887 0532 3315 0000 7E  // CCT: 32, GM: 33
7887 0532 3915 0000 84  // CCT: 32, GM: 39
7887 0532 3D15 0000 88  // CCT: 32, GM: 3D
7887 0532 3E15 0000 89  // CCT: 32, GM: 3E
```

**Brightness Control:**
```
7887 0536 3E15 0000 8D  // Brightness: 36
7887 0543 3E15 0000 9A  // Brightness: 43
7887 0545 3E15 0000 9C  // Brightness: 45
```

### Effect Commands

**CCT Flash Effect:**
```
788B 0506 3237 3205 AE
```

**Welding Effect (Brightness Range Control):**
```
788B 0605 0032 3732 05AE  // Lower: 32, Upper: 37
788B 0605 0050 3732 05CC  // Lower: 50, Upper: 37
788B 0605 0064 3732 05E0  // Lower: 64, Upper: 37
```

**Explosion Effect:**
```
788B 0604 3237 3205 05B2
```

### Command Structure Notes

- **Device Handle**: Commands are sent to Handle `0x000D`
- **Device Identifier**: `NEEWER-RGB62`
- **Command Format**: All commands follow a consistent hex structure with checksums
- **Parameter Ranges**: 
  - Brightness: `00-64` (0-100%)
  - CCT values vary by specific implementation
  - GM (Green/Magenta): Bidirectional tint control

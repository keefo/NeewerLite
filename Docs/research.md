# How to research Neewer phone app

0. Download a latest apk package from apkcombo website.
   https://apkcombo.com/neewer/neewer.nginx.annularlight/download/apk

1. Unpack apk file.

```
unzip Neewer_5.0.5_Apkpure.apk
```

2. Unpack dex files.
   Then use [jadx](brew install jadx) to get java code from dex file in the apk.

`brew install jadx`

```
jadx classes.dex
jadx classes2.dex
jadx classes3.dex
jadx classes4.dex
jadx classes5.dex
```

# How to do bluetooth packet logging on Neewer iOS app

Install neewer iOS app, and Connect your iPhone your dev macbook.

Download and install [iOSBluetoothLogging.mobileconfig](https://tc-downloads.s3.amazonaws.com/support/iOSBluetoothLogging.mobileconfig) on your iPhone.

Download PacketLogger.app on your macbook from Apple Developer portal.

https://twocanoes.com/knowledge-base/capture-bluetooth-packet-trace-on-ios/

Connect your iphone to your macbook through cable. Open PacketLogger.app start logging your iphone bluetooth packets. Filter by Packet Type: ATT Send.

Then use your Neewer iOS app control light, you should see packet stream in PacketLogger.app view.

## CB60 RGB command reverse engineering

### CCT + GM command

```
This command send CCT 2700K (0x1B) + -50GM(0x00) to 6500K(0x41) + +50GM(0x64)
Oct 24 21:16:33.567  ATT Send         0x005A  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7890 0BDF 243A B446 5D87 1D1B 0004 CE  SEND
Oct 24 21:16:49.551  ATT Send         0x005A  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7890 0BDF 243A B446 5D87 1D41 6404 F4  SEND


CMD  TAG   SIZE    MAC               (subTAG)    (INT)  CCT    GM  (DIMMINGCURVETYPE)    (checksum)
78   90    0B    (DF 24 3A B4 46 5D)    87       1D     (2A)  (5F) 04                    D8
```

### SCENE commands

Support 17 types of scene

```
Oct 25 01:41:40.143  ATT Send         0x004A  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 1107 0103 4F  SEND
Oct 25 01:41:42.493  ATT Send         0x004A  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 1107 0101 4D  SEND

CMD TAG   SIZE       MAC                     SCE_TAG  SCE_ID(01~0C)     (BRR 00~64)    (COLOR 00~02)      (Speed 00~0A)      (checksum)
78   91   0B         (DF 24 3A B4 46 5D)     8B       11                 07             01                 03                 4F

Name               ID
Lighting           01             BRR   CTT   SPEED
Paparazzi          02             BRR   CTT   GM       SPEED
Defective bulb     03             BRR   CTT   GM       SPEED
Explosion          04             BRR   CTT   GM       SPEED     Sparks(01~0A)
Welding            05             BRR_low   BRR_high     CTT   GM       SPEED
CCT flash          06             BRR   CTT   GM       SPEED
HUE flash          07             BRR   HUE (2Bytes little Endian 0000~6801)   SAT (00~64)   SPEED
CCT pulse          08             BRR   CCT   GM       SPEED
HUE pulse          09             BRR   HUE (2Bytes little Endian 0000~6801)   SAT (00~64)   SPEED
Cop Car            0A             BRR   RED_AND_BLUE(00~05 Red,Blue, Red and Blue, White and Blue, Red blue  white) SPEED
Candlelight        0B             BRR_low   BRR_high   CTT     GM       SPEED     Sparks
HUE Loop           0C             BRR   HUE_low  HUE_high      SPEED
CCT Loop           0D             BRR   CCT_low  CCT_high      SPEED
INT loop           0E             BRR_low   BRR_high   HUE     SPEED
TV Screen          0F             BRR   CCT   GM       SPEED
Firework           10             BRR   COLOR(00 Single color, 01 Color, 02 Combined)   SPEED   Sparks
Party              11             BRR   COLOR(00 Single color, 01 Color, 02 Combined)   SPEED
```

Cop Car Command Example

Color 00

```
Nov 07 00:58:36.544  ATT Send         0x0040  DF:24:3A:B4:46:5D  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 0A32 0005 74  SEND
```

Color 01

```
Nov 07 00:58:30.744  ATT Send         0x0040  DF:24:3A:B4:46:5D  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 0A32 0105 75  SEND
```

CB60 RGB
NW-20210012&FFFFFFFF

## RGB62 light command reverse engineering

Power Off

```
Jul 24 11:50:43.508  ATT Send         0x0050  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 7881 0102 FC
```

Power ON

```
Jul 24 11:50:48.741  ATT Send         0x0050  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 7881 0101 FB
```

HSI mode changing color

```
Jul 24 11:54:22.853  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 040C 0132 3273
Jul 24 11:54:22.953  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0413 0133 327B
Jul 24 11:54:23.047  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0415 0134 327E
Jul 24 11:54:23.154  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 041F 0136 328A
Jul 24 11:54:23.252  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0426 0138 3293
Jul 24 11:54:23.355  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0428 0139 3296
Jul 24 11:54:23.448  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0428 0139 3296
Jul 24 11:54:23.548  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0428 0139 3296
Jul 24 11:54:23.648  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0428 0139 3296
Jul 24 11:54:23.748  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7886 0428 0139 3296
```

CCT mode changing GM

```
Jul 24 11:52:52.335  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 2115 0000 6C
Jul 24 11:53:11.234  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 2315 0000 6E
Jul 24 11:53:11.332  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 2615 0000 71
Jul 24 11:53:11.433  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 2715 0000 72
Jul 24 11:53:11.531  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 2915 0000 74
Jul 24 11:53:11.630  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 2F15 0000 7A
Jul 24 11:53:11.726  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3115 0000 7C
Jul 24 11:53:11.826  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3115 0000 7C
```

CCT mode changing CCT

```
Jul 24 11:53:36.538  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3315 0000 7E
Jul 24 11:53:36.639  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3915 0000 84
Jul 24 11:53:36.737  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3D15 0000 88
Jul 24 11:53:36.836  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3E15 0000 89
Jul 24 11:53:36.936  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3E15 0000 89
Jul 24 11:53:37.036  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0532 3E15 0000 89
```

CCT mode changing BRR

```
Jul 24 11:54:00.487  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0536 3E15 0000 8D
Jul 24 11:54:00.590  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0543 3E15 0000 9A
Jul 24 11:54:00.688  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0545 3E15 0000 9C
Jul 24 11:54:00.788  ATT Send         0x0055  NEEWER-RGB62       Write Command - Handle:0x000D - Value: 7887 0545 3E15 0000 9C
```

FX CCD flash

```
Jul 24 11:55:21.895  ATT Send         0x0055  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 788B 0506 3237 3205 AE
```

FX welding chaning brr upper bound

```
Jul 24 11:55:41.712  ATT Send         0x0055  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 788B 0605 0032 3732 05AE
Jul 24 11:56:05.089  ATT Send         0x0055  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 788B 0605 0050 3732 05CC
Jul 24 11:56:21.463  ATT Send         0x0055  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 788B 0605 0064 3732 05E0
```

FX explosion

```
Jul 24 11:57:02.697  ATT Send         0x0055  00:00:00:00:00:00  Write Command - Handle:0x000D - Value: 788B 0604 3237 3205 05B2
```

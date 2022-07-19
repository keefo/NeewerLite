<p align="center">
<a  href="https://github.com/keefo/NeewerLite">
    <img src="Design/icon_128x128@2x.png" alt="Logo" width="150" height="150">
</a>
</p>

<h1 align="center">NeewerLite</h1>

# About The Project

[![Build Status](https://github.com/keefo/NeewerLite/actions/workflows/swift.yml/badge.svg?branch=main)](https://github.com/keefo/NeewerLite/actions/workflows/swift.yml)

NeewerLite is an un-official Neewer LED light control app for macOS.

[Neewer](https://neewer.com/) produces popular high-CRI LED lights for media industry. They provides android and [iOS app](https://apps.apple.com/us/app/neewer/id1455948340) to control their lights through Bluetooth. However, they don't provides any means to control lights from a PC or Mac.

This project creates a macOS app so you could control bluetooth-enabled Neewer LED lights from you Mac.

You could integrate the light control in your [Elgato Stream Deck](https://www.elgato.com/en/gaming/stream-deck) through this app. 

Here is a video I made to demo the scene: 

<p>
<a align="left" href="https://youtu.be/pbNi6HZTDEc">
	<img src="https://j.gifs.com/3Qz2Ox.gif" />
</a>
<img src="screenshot.png" width="300px" />
<img src="screenshot1.png" width="300px" />
</p>

# Features

- Power On/Off control
- Brightness control
- Correlated color temperature control
- RGB color control
- Scene control
- Script support
- Sync RGB lights with music

## Script Usage

Open the app and let it scans all Neewer lights through Bluetooth. Once it finds lights. Then you could use command to switch On/Off lights.

Turn on all lights:

```bash
open neewerlite://turnOnLight
```

Turn off all lights:
```bash
open neewerlite://turnOffLight
```

Toggle all lights:
```bash
open neewerlite://toggleLight
```

Scan all lights:
```bash
open neewerlite://scanLight
```

Turn on light by name:

```bash
open neewerlite://turnOnLight?light=left
```

The 'left' is the name I give one of my light. You could change your light's name in the app and use it in this command.

### How to use script to integrate with Elgato Stream Deck?

Read this [Integrate with Elgato Stream Deck](./Docs/Integrate-with-streamdeck.md)

### How to use script to integrate with macOS Shortcuts?

Read this [Integrate with Shortcuts](./Docs/Integrate-with-shortcut.md)

### Voice Control Interaction

You could integrate these commands into Voice Control. 

Open “System Preferences” -> “Accessibility” -> “Voice Control” -> “Commands”, Click the “+” button to create a new command, give a name to your new command such as “Meow” and choose “Any Application” then choose perform “Open URL”.  Type in “neewerlite://toggleLight” for example. 

Now, when you say “Meow” voice control will switch on/off your LED lights.

# Tested Lights

* [Neewer 660 RGB Led Light](https://neewer.com/products/neewer-led-light-10096807)
* [Neewer 480 RGB Led Light](https://neewer.com/collections/rgb-led-panel-light/products/neewer-led-light-10096594)
* [Neewer RGB176 Led Light](https://neewer.com/products/neewer-rgb176-video-light-with-app-control-10098961)
* [Neewer RGB 530PRO Led Light](https://neewer.com/products/neewer-led-light-10096806)
* [Neewer GL1 Led Key Light](https://neewer.com/products/neewer-15-5-45w-gl1-gaming-key-light-10099348)

# TO DO LIST

If you find a way to implement these features, feel free to create a pull request.

- [ ] Test more Neewer LED lights
- [ ] Add support for other Neewer LED lights
- [ ] Add command interface to support Hue, Saturation, & Brightness adjustment.

# License

Follow NeewerLite, the code and examples of this project is released under MIT License.

# Donations

If you would like to support me, donations are very welcome.
You can send bitcoin to this address:

```
1A4mwftoNpuNCLbS8dHpk9XHrcyvtExrYF
```



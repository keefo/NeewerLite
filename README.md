<p align="center">
<a  href="https://github.com/keefo/NeewerLite">
    <img src="Design/icon_128x128@2x.png" alt="Logo" width="150" height="150">
</a>
</p>

<h1 align="center">NeewerLite</h1>

# About The Project

[![CI](https://github.com/keefo/NeewerLite/actions/workflows/ci.yml/badge.svg)](https://github.com/keefo/NeewerLite/actions/workflows/ci.yml)

NeewerLite is a unofficial macOS app designed for controlling Neewer LED lights. 

While [Neewer](https://neewer.com/) provides official Android and [iOS app](https://apps.apple.com/us/app/neewer/id1455948340) for controlling their high-CRI LED lights via Bluetooth, they do not offer a means of control from a PC or Mac. 

This project aims to fill that gap by creating a macOS app that allows you to control your Bluetooth-enabled Neewer LED lights from your Mac. With NeewerLite, you can even integrate light control into your [Elgato Stream Deck](https://www.elgato.com/en/gaming/stream-deck) or shortcuts for better experince.

Here is a video I made to demo the scene: 

<p>
<a align="left" href="https://youtu.be/pbNi6HZTDEc">
	<img src="https://j.gifs.com/3Qz2Ox.gif" />
</a>
<img src="screenshot.png" width="300px" />
</p>

# Features

- Power On/Off control
- Brightness control
- Correlated color temperature control
- RGB color control
- Scene control
- Script support
- Sync RGB lights with music

# How to install pre-build app

1. Download the latest dmg file from release page, double click the dmg to open it.
2. Then drag .app file in dmg to your application folder.
3. Go to application folder to double the app you just dropped from dmg.
4. once the app is running, it should has a icon in the status bar on the right top of you screen.

## Script Usage

Open the app and let it scans all Neewer lights through Bluetooth. Once it finds lights. Then you could use command to switch On/Off lights.

Turn on all lights:

```bash
open "neewerlite://turnOnLight"
```

Turn off all lights:
```bash
open "neewerlite://turnOffLight"
```

Toggle all lights:
```bash
open "neewerlite://toggleLight"
```

Scan all lights:
```bash
open "neewerlite://scanLight"
```

Set lights CCT:
```bash
open "neewerlite://setLightCCT?CCT=3200&Brightness=100"
```

Set lights CCT+GM:
```bash
open "neewerlite://setLightCCT?CCT=3200&GM=-50&Brightness=100"
```

Most of light model support CCT range 3200K to 5600K, Some lights support long CCT range 3200K to 8500K. And some newer model of light support GM.


Set lights Hue and Saturation and Brightness:
```bash
open "neewerlite://setLightHSI?RGB=ff00ff&Saturation=100&Brightness=100"
```

```bash
open "neewerlite://setLightHSI?HUE=360&Saturation=100&Brightness=100"
```

Set lights to scene:

```bash
open "neewerlite://setLightScene?Scene=SquadCar"
```

```bash
open "neewerlite://setLightScene?SceneId=1&Brightness=100"
```

Scene Names: SquadCar, Ambulance, FireEngine, Fireworks, Party, CandleLight, Lighting, Paparazzi, Screen

Not all model follow these scene names. If your light support more scenes, you can use SceneId to switch.

SceneId Range from 1 ~ 17 depends on light type.

Turn on light by name:

```bash
open "neewerlite://turnOnLight?light=left"
```

The 'left' is the name I give one of my light. You could change your light's name in the app and use it in this command.

Another way to test these commands is to copy a command(the string in the double quote) into your browser address bar, and press enter.

For example, 


### How to use script to integrate with Elgato Stream Deck?

Read this [Integrate with Elgato Stream Deck](./Docs/Integrate-with-streamdeck.md)

### How to use script to integrate with macOS Shortcuts?

Read this [Integrate with Shortcuts](./Docs/Integrate-with-shortcut.md)

### Voice Control Interaction

You could integrate these commands into Voice Control. 

Open “System Preferences” -> “Accessibility” -> “Voice Control” -> “Commands”, Click the “+” button to create a new command, give a name to your new command such as “Meow” and choose “Any Application” then choose perform “Open URL”.  Type in “neewerlite://toggleLight” for example. 

Now, when you say “Meow” voice control will switch on/off your LED lights.

# Tested Lights

* [Neewer CB60 RGB Light](https://neewer.com/products/neewer-led-video-light-66601007)
* [Neewer 660 RGB Light](https://neewer.com/products/neewer-led-light-10096807)
* [Neewer 480 RGB Light](https://neewer.com/collections/rgb-led-panel-light/products/neewer-led-light-10096594)
* [Neewer RGB176 Light](https://neewer.com/products/neewer-rgb176-video-light-with-app-control-10098961)
* [Neewer RGB 530 PRO Light](https://www.amazon.ca/360%C2%B0Full-Streaming-Broadcasting-Conference-Photography/dp/B08MVTJTVQ)
* [Neewer RGB1-A Magnetic Handheld Light Stick](https://ca.neewer.com/products/neewer-cri98-rgb1-handheld-led-video-light-66601508)
* [Neewer SL90 Pro Aluminum Alloy RGB Panel Video Light](https://ca.neewer.com/products/neewer-sl90-12w-on-camera-rgb-panel-video-light-66600927)
* [Neewer BH-30S RGB LED Tube Light Wand](https://ca.neewer.com/products/neewer-bh30s-rgb-led-tube-light-wand-66602411)


# TO DO LIST

If you find a way to implement these features, feel free to create a pull request.

- [ ] Test more Neewer LED lights
- [ ] Add support for other Neewer LED lights
- [ ] Advanced scene management

# How to add support for a new light?

If you are unable to find your Neewer light using NeewerLite, you can easily add support for it by following these steps:

1. Use a Bluetooth app to find the name of your light.
2. Add the name to the **isValidPeripheralName** function in the Model/NeewerLight.swift file.
3. Recompile the app and test your light to ensure that it is working properly.
4. If the light is working as expected, create a pull request on the project's GitHub repository to submit your changes.

By following these steps, you can quickly add support for your Neewer light and start controlling it using NeewerLite.

# License

Follow NeewerLite, the code and examples of this project is released under MIT License.

# Donations

If you would like to support me, donations are very welcome.

You can go fund this project through my [sponsors](https://github.com/sponsors/keefo) page.

or

You can send bitcoin to this address:

```
1A4mwftoNpuNCLbS8dHpk9XHrcyvtExrYF
```



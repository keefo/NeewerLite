# NeewerLite

NeewerLite is an un-official Neewer LED light control app which is open source under MIT license.

[Neewer](https://neewer.com/) produces some very popupler high-CRI LED lights for photography industry. They provides android and ios app to control those lights through Bluetooth. However, they don't provides any means to control lights from a PC or Mac.

This project is meant to provide such app so you could control bluetooth-enabled Neewer LED light from you Mac.

You could integrate the light control in your [Elgato Stream Deck](https://www.elgato.com/en/gaming/stream-deck) through this app. 

Here is a video I made to demo the scene: 

![](https://j.gifs.com/3Qz2Ox.gif)

https://youtu.be/pbNi6HZTDEc

![screenshot.jpg](screenshot.jpg "Snapshot")

# Usage

Open the app and let it scans all Neewer lights through Bluetooth. Once it finds lights. Then you could use command to switch On/Off lights.

Use this command to turn on all lights:

```bash
open neewerlite://turnOnLight
```

Use this command to turn off all lights:
```bash
open neewerlite://turnOffLight
```

# TO DO LIST

If you find a way to implement these features, feel free to create a pull request.

- [x] Add brightness control
- [ ] Add RGB color control
- [ ] Add scene switch control

# License

Follow NeewerLite, the code and examples of this project is released under MIT License.


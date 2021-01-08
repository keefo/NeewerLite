# NeewerLite

NeewerLite is an un-official Neewer LED light control app which is open source under MIT license.

[Neewer](https://neewer.com/) produces some very popupler high-CRI LED lights for photography industry. They provides android and ios app to control those lights through Bluetooth. However, they don't provides any means to control lights from a PC or Mac.

This project is meant to provide such app so you could control bluetooth-enabled Neewer LED light from you Mac.

You could integrate the light control in your Elgato Stream Deck through this app. 

Here is a video I made to demo the scene: 

https://youtu.be/pbNi6HZTDEc

![](https://j.gifs.com/3Qz2Ox.gif)

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

1. Add brightness control
2. Add RGB color control
3. Add scene switch control

# License

Follow NeewerLite, the code and examples of this project is released under MIT License.


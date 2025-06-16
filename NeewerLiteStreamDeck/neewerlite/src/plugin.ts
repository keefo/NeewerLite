import streamDeck, { LogLevel } from "@elgato/streamdeck";

import { startHeartbeat } from "./ipc";
import { SwitchLightControl } from "./actions/switch";
import { BrightnessControl } from "./actions/brightness";
import { TemperatureControl } from "./actions/temperature";
import { BrightnessKeyControl } from "./actions/brightness_key";
import { TemperatureKeyControl } from "./actions/temperature_key";
import { CCTKeyControl } from "./actions/cct_key";
import { HSTKeyControl } from "./actions/hst_key";
import { HUEControl } from "./actions/hue";
import { SATControl } from "./actions/sat";
import { FXKeyControl } from "./actions/fx_key";


// We can enable "trace" logging so that all messages between the Stream Deck, and the plugin are recorded. When storing sensitive information
streamDeck.logger.setLevel(LogLevel.INFO);

// Register the increment action.
streamDeck.actions.registerAction(new SwitchLightControl());
streamDeck.actions.registerAction(new BrightnessControl());
streamDeck.actions.registerAction(new TemperatureControl());
streamDeck.actions.registerAction(new BrightnessKeyControl());
streamDeck.actions.registerAction(new TemperatureKeyControl());
streamDeck.actions.registerAction(new CCTKeyControl());
streamDeck.actions.registerAction(new HSTKeyControl());
streamDeck.actions.registerAction(new HUEControl());
streamDeck.actions.registerAction(new SATControl());
streamDeck.actions.registerAction(new FXKeyControl());

// Finally, connect to the Stream Deck.
streamDeck.connect();

startHeartbeat();


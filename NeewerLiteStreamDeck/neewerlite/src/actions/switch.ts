import streamDeck, { action, SingletonAction, WillAppearEvent, type JsonValue, type KeyDownEvent, type SendToPluginEvent } from "@elgato/streamdeck";
import type { Light, DataSourcePayload, DataSourceResult, GlobalSettings } from "../sdpi";
import { fetchListLights, toggleLights } from "../ipc";


@action({ UUID: "com.beyondcow.neewerlite.lightcontrol.switch" })
export class SwitchLightControl extends SingletonAction<Settings> {

	override async onWillAppear(ev: WillAppearEvent<Settings>): Promise<void> {
		streamDeck.logger.info("onWillAppear:", ev.payload.settings);
    }

	override onKeyDown(ev: KeyDownEvent<Settings>): Promise<void> | void {
		let settings = ev.payload.settings;
		if (ev.payload.settings.selectedLights.length <= 0) {
			streamDeck.logger.warn("No lights selected to toggle.");
			return;
		}
		settings.light_state = !settings.light_state;
		toggleLights(ev.payload.settings.selectedLights, settings.light_state)
			.then(response => {
				if (response.body && response.body.success) {
					streamDeck.logger.info("Lights toggled successfully:", response.body.switched);
					ev.action.setSettings(settings);
					if(settings.light_state)
					{
						ev.action.setState(0);
					}
					else{
						ev.action.setState(1);
					}
					
				} else {
					streamDeck.logger.warn("Failed to toggle lights:", response.body);
				}
			})
			.catch(err => {
				streamDeck.logger.error("toggleLights failed:", err);
			});
	}

	override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, Settings>): Promise<void> {
		streamDeck.logger.debug("Received message from property inspector:", ev);
		// Check if the payload is requesting a data source, i.e. the structure is { event: string }
		if (ev.payload instanceof Object && "event" in ev.payload && ev.payload.event === "deviceList") {
			let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
			let ui_lights = lights.map(light => ({
                label: light.name,
                value: light.id,
                disabled: light.state == -1
            }));
			streamDeck.logger.debug("Sending device list to property inspector:", ui_lights);
			streamDeck.ui.current?.sendToPropertyInspector({
				event: "deviceList",
				items: ui_lights,
			});
		}
	}
}

type Settings = {
	prop?: string;
	light: number;
    light_state: boolean;
	selectedLights: string[];
};

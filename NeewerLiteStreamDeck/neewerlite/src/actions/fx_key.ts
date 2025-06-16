import streamDeck, { action, KeyAction, DialRotateEvent, DialUpEvent, DidReceiveSettingsEvent, SingletonAction, WillAppearEvent, type JsonValue, type KeyDownEvent, type SendToPluginEvent } from "@elgato/streamdeck";
import type { GlobalSettings, Light, FXItem, DataSourcePayload, DataSourceResult } from "../sdpi";
import { setLightsFX } from "../ipc";
import { getFX17Items, getFX9Items } from "../sdpi";

@action({ UUID: "com.beyondcow.neewerlite.lightcontrol.fx.key" })
export class FXKeyControl extends SingletonAction<CounterSettings> {

    override async onWillAppear(ev: WillAppearEvent<CounterSettings>): Promise<void> {
        if (!ev.action.isKey()) return;
        let settings = ev.payload.settings;
        if (settings.selectedScene9 == null) 
        {
            settings.selectedScene9 = 1
        }
        if (settings.selectedScene17 == null) 
        {
            settings.selectedScene17 = 1
        }
        ev.action.setSettings(settings);
    }

	override onKeyDown(ev: KeyDownEvent<CounterSettings>): Promise<void> | void {
        let settings = ev.payload.settings;
        if (settings.selectedLights.length <= 0) {
            streamDeck.logger.warn("No lights selected to toggle.");
            return;
        }
        streamDeck.logger.warn("onKeyDown: ", settings);
        setLightsFX(settings.selectedLights, settings.selectedScene9, settings.selectedScene17)
            .then(response => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info("HST set successfully:", response.body.switched);
                } else {
                    streamDeck.logger.warn("Failed to set HST lights:", response.body);
                }
            })
            .catch(err => {
                streamDeck.logger.error("toggleLights failed:", err);
            });
    }

    /**
     * Listen for messages from the property inspector.
     * @param ev Event information.
     */
    override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, CounterSettings>): Promise<void> {
        streamDeck.logger.debug("Received message from property inspector:", ev);
        // Check if the payload is requesting a data source, i.e. the structure is { event: string }
        if (ev.payload instanceof Object && "event" in ev.payload && ev.payload.event === "deviceList") {
            let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
            let ui_lights = []
            for (const light of lights) {
                if (light.supportRGB)
                {
                    ui_lights.push({
                        label: light.name,
                        value: light.id,
                        disabled: light.state == -1
                    })
                }
            }
            streamDeck.logger.debug("Sending device list to property inspector:", ui_lights);
            streamDeck.ui.current?.sendToPropertyInspector({
                event: "deviceList",
                items: ui_lights,
            });
        }

        if (ev.payload instanceof Object && "event" in ev.payload && ev.payload.event === "sceneList17") {
            streamDeck.ui.current?.sendToPropertyInspector({
                event: "sceneList17",
                items: getFX17Items(),
            });
        }
        if (ev.payload instanceof Object && "event" in ev.payload && ev.payload.event === "sceneList9") {
            streamDeck.ui.current?.sendToPropertyInspector({
                event: "sceneList9",
                items: getFX9Items(),
            });
        }
    }

}

/**
 * Settings for {@link IncrementCounter}.
 */
type CounterSettings = {
	value: number;
	light: number;
	selectedScene9: number | 0 ;
	selectedScene17: number | 0 ;
	selectedLights: string[];
};


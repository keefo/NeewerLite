import streamDeck, { action, DidReceiveSettingsEvent, DialRotateEvent, DialUpEvent, SingletonAction, WillAppearEvent, type JsonValue, type KeyDownEvent, type SendToPluginEvent } from "@elgato/streamdeck";
import type { GlobalSettings, Light, DataSourcePayload, DataSourceResult } from "../sdpi";
import { fetchListLights, setLightsTemperature, toggleLights } from "../ipc";


@action({ UUID: "com.beyondcow.neewerlite.lightcontrol.temperature" })
export class TemperatureControl extends SingletonAction<DialSettings> {

    temperature_2_value(settings: DialSettings): number {
        return Math.round(100 * (settings.temperature-settings.min_temperature) / (settings.max_temperature-settings.min_temperature));
    }

    #getTitle(): string {
        return streamDeck.i18n.t("temperature");
    };

    override async onWillAppear(ev: WillAppearEvent<DialSettings>): Promise<void> {
        if (!ev.action.isDial()) return;
        let settings = ev.payload.settings;
        settings.temperature = 32;
        settings.min_temperature = 32;
        settings.max_temperature = 56;
        let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
        for (const light of lights) {
            if (light.state == -1){
                //offline
                continue;
            }
            settings.temperature = light.temperature || settings.temperature;
            settings.light_state = light.state == 1;
            settings.min_temperature = light.cctRange ? parseInt(light.cctRange.split("-")[0]) : 32;
            settings.max_temperature = light.cctRange ? parseInt(light.cctRange.split("-")[1]) : 56;
            settings.temperature = Math.max(settings.min_temperature, Math.min(settings.max_temperature, settings.temperature));
            break;
        }
        ev.action.setSettings(settings);
        ev.action.setFeedback({ 
            title: `${this.#getTitle()}`,
            icon: "imgs/actions/temperature/icon",
            indicator: { value: this.temperature_2_value(settings), bar_bg_c: "0:#ea8f2f,1:#5bcaff" }, 
            value: settings.temperature +"00K"
        });
    }

	override onDialUp(ev: DialUpEvent<DialSettings>): Promise<void> | void {
        streamDeck.logger.info("onDialUp:", ev.payload.settings);
        let settings = ev.payload.settings;
        if (settings.selectedLights.length <= 0) {
            streamDeck.logger.warn("No lights selected to toggle.");
            ev.action.setFeedback({ 
                title: `${this.#getTitle()} ⚠️`,
                icon: "imgs/actions/temperature/icon"
            });
            return;
        }
        settings.light_state = !settings.light_state;
        toggleLights(ev.payload.settings.selectedLights, settings.light_state)
            .then(response => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info("Lights toggled successfully:", response.body.switched);
                    ev.action.setSettings(settings);
                    ev.action.setFeedback({ 
                        title: `${this.#getTitle()}`,
                        icon: "imgs/actions/temperature/icon"
                    });
                } else {
                    streamDeck.logger.warn("Failed to toggle lights:", response.body);
                }
            })
            .catch(err => {
                streamDeck.logger.error("toggleLights failed:", err);
            });
	}

	/**
	 * Update the value based on the dial rotation.
	 */
	override onDialRotate(ev: DialRotateEvent<DialSettings>): Promise<void> | void {
		let settings = ev.payload.settings;
		const { ticks } = ev.payload;
        if (ev.payload.settings.selectedLights == undefined || ev.payload.settings.selectedLights.length <= 0) {
            streamDeck.logger.warn("No lights selected to adjust temperature.");
            ev.action.setFeedback({ 
                title: `${this.#getTitle()} ⚠️`,
                icon: "imgs/actions/temperature/icon"
            });
            return;
        }
        // Adjust temperature based on ticks, ensuring it stays within min/max range
		settings.temperature = Math.max(settings.min_temperature, Math.min(settings.max_temperature, settings.temperature + ticks));
        ev.action.setSettings(settings);
        ev.action.setFeedback({ 
            title: `${this.#getTitle()}`,
            icon: "imgs/actions/temperature/icon"
        });
        setLightsTemperature(ev.payload.settings.selectedLights, settings.temperature)
            .then(response => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info("Temperature set successfully:", response.body.switched);
                    ev.action.setFeedback({
                        indicator: { value: this.temperature_2_value(settings) }, 
                        value: settings.temperature +"00K"
                    });
                } else {
                    streamDeck.logger.warn("Failed to set temperature:", response.body);
                }
            })
            .catch(err => {
                streamDeck.logger.error("setLightsTemperature failed:", err);
            });
	}

    /**
     * Listen for messages from the property inspector.
     * @param ev Event information.
     */
    override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, DialSettings>): Promise<void> {
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

/**
 * Settings for {@link IncrementCounter}.
 */
type DialSettings = {
    light_state: boolean;
	value: number;
	light: number;
    min_temperature: number;
    max_temperature: number;
	temperature: number | 0 ;
	selectedLights: string[];
};


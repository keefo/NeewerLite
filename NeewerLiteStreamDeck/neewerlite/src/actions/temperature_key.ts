import streamDeck, {
    action,
    KeyAction,
    DialRotateEvent,
    DialUpEvent,
    DidReceiveSettingsEvent,
    SingletonAction,
    WillAppearEvent,
    type JsonValue,
    type KeyDownEvent,
    type SendToPluginEvent,
} from '@elgato/streamdeck';
import type { GlobalSettings, Light, DataSourcePayload, DataSourceResult } from '../sdpi';
import { setLightsBrightness, setLightsTemperature, toggleLights } from '../ipc';

@action({ UUID: 'com.beyondcow.neewerlite.lightcontrol.temperature.key' })
export class TemperatureKeyControl extends SingletonAction<CounterSettings> {
    override async onWillAppear(ev: WillAppearEvent<CounterSettings>): Promise<void> {
        if (!ev.action.isKey()) return;
        let settings = ev.payload.settings;
        if (settings.selectedLights == undefined) {
            settings.selectedLights = [];
        }
        ev.action.setSettings(settings);
    }

    override onKeyDown(ev: KeyDownEvent<CounterSettings>): Promise<void> | void {
        let settings = ev.payload.settings;
        if (settings.selectedLights.length <= 0) {
            streamDeck.logger.warn('No lights selected to toggle.');
            return;
        }
        streamDeck.logger.warn('onKeyDown: ', settings);
        setLightsTemperature(settings.selectedLights, settings.temperature)
            .then((response) => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info('Temperature set successfully:', response.body.switched);
                } else {
                    streamDeck.logger.warn('Failed to set Temperature lights:', response.body);
                }
            })
            .catch((err) => {
                streamDeck.logger.error('toggleLights failed:', err);
            });
    }

    /**
     * Listen for messages from the property inspector.
     * @param ev Event information.
     */
    override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, CounterSettings>): Promise<void> {
        streamDeck.logger.debug('Received message from property inspector:', ev);
        // Check if the payload is requesting a data source, i.e. the structure is { event: string }
        if (ev.payload instanceof Object && 'event' in ev.payload && ev.payload.event === 'deviceList') {
            let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
            let ui_lights = lights.map((light) => ({
                label: light.name,
                value: light.id,
                disabled: light.state == -1,
            }));
            streamDeck.logger.debug('Sending device list to property inspector:', ui_lights);
            streamDeck.ui.current?.sendToPropertyInspector({
                event: 'deviceList',
                items: ui_lights,
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
    temperature: number;
    selectedLights: string[];
};

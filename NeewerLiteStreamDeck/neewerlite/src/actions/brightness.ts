import streamDeck, {
    action,
    DialAction,
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
import { setLightsBrightness, toggleLights } from '../ipc';

const INTERVAL = 1000;

@action({ UUID: 'com.beyondcow.neewerlite.lightcontrol.brightness' })
export class BrightnessControl extends SingletonAction<CounterSettings> {
    private timer: NodeJS.Timeout | undefined;
    private last_dial_time: number = Date.now();

    syncSettings2UI(action: DialAction, settings: CounterSettings) {
        settings.brightness = Number(settings.brightness);
        action.setSettings(settings);
        action.setFeedback({ indicator: { value: settings.brightness }, value: settings.brightness + '%' });
        if (settings.light_state) {
            streamDeck.logger.info('settings.light_state is on');
            action.setFeedback({
                title: `${streamDeck.i18n.t('brightness')} ${streamDeck.i18n.t('on')}`,
                icon: 'imgs/actions/brightness/icon_on',
            });
        } else {
            streamDeck.logger.info('settings.light_state is off');
            action.setFeedback({
                title: `${streamDeck.i18n.t('brightness')} ${streamDeck.i18n.t('off')}`,
                icon: 'imgs/actions/brightness/icon_off',
            });
        }
    }

    override async onWillAppear(ev: WillAppearEvent<CounterSettings>): Promise<void> {
        if (!ev.action.isDial()) return;
        let settings = ev.payload.settings;
        settings.light_state = false;
        if (settings.selectedLights == undefined) {
            settings.selectedLights = [];
        }
        if (settings.brightness == undefined) {
            settings.brightness = 50;
        }
        let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
        for (const light of lights) {
            if (light.state == -1) {
                continue;
            }
            settings.brightness = light.brightness;
            settings.light_state = light.state == 1;
            break;
        }

        streamDeck.logger.info('lights:', lights);
        settings.brightness = Math.max(0, Math.min(100, settings.brightness));
        this.syncSettings2UI(ev.action, settings);

        if (!this.timer) {
            this.timer = setInterval(async () => {
                const gap_ms = Date.now() - this.last_dial_time;
                if (gap_ms < 3000) {
                    return;
                }
                let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
                for (const action of this.actions) {
                    // Verify that the action is a key so we can call setRandomCat.
                    if (action.isDial()) {
                        action.getSettings().then((settings) => {
                            for (const light of settings.selectedLights) {
                                for (const remote_light of lights) {
                                    if (remote_light.id == light) {
                                        if (
                                            remote_light.brightness != settings.brightness ||
                                            (remote_light.state == 1) != settings.light_state
                                        ) {
                                            settings.brightness = remote_light.brightness;
                                            settings.light_state = remote_light.state == 1;
                                            this.syncSettings2UI(action, settings);
                                        }
                                        break;
                                    }
                                }
                            }
                        });
                    }
                }
            }, INTERVAL);
        }
    }

    override onDialUp(ev: DialUpEvent<CounterSettings>): Promise<void> | void {
        if (!ev.action.isDial()) return;
        this.last_dial_time = Date.now();
        let settings = ev.payload.settings;
        if (settings.selectedLights.length <= 0) {
            streamDeck.logger.warn('No lights selected to toggle.');
            return;
        }
        settings.light_state = !settings.light_state;
        toggleLights(settings.selectedLights, settings.light_state)
            .then((response) => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info('Lights toggled successfully:', response.body.switched);
                    this.syncSettings2UI(ev.action, settings);
                } else {
                    streamDeck.logger.warn('Failed to toggle lights:', response.body);
                }
            })
            .catch((err) => {
                streamDeck.logger.error('toggleLights failed:', err);
            });
    }

    /**
     * Update the value based on the dial rotation.
     */
    override onDialRotate(ev: DialRotateEvent<CounterSettings>): Promise<void> | void {
        let settings = ev.payload.settings;
        const { ticks } = ev.payload;
        this.last_dial_time = Date.now();
        streamDeck.logger.info('onDialRotate:', ev.payload.settings);
        // Adjust brightness based on ticks, ensuring it stays within 0-100 range
        settings.brightness = Math.max(0, Math.min(100, settings.brightness + ticks * 5));
        setLightsBrightness(ev.payload.settings.selectedLights, settings.brightness)
            .then((response) => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info('Brightness set successfully:', response.body.switched);
                    this.syncSettings2UI(ev.action, settings);
                } else {
                    streamDeck.logger.warn('Failed to set brightness:', response.body);
                }
            })
            .catch((err) => {
                streamDeck.logger.error('setLightsBrightness failed:', err);
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
    light_state: boolean;
    value: number;
    light: number;
    brightness: number;
    selectedLights: string[];
};

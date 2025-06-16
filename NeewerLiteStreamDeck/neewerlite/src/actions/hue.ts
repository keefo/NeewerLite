import streamDeck, {
    action,
    DidReceiveSettingsEvent,
    DialAction,
    DialRotateEvent,
    DialUpEvent,
    SingletonAction,
    WillAppearEvent,
    type JsonValue,
    type KeyDownEvent,
    type SendToPluginEvent,
} from '@elgato/streamdeck';
import type { GlobalSettings, Light, DataSourcePayload, DataSourceResult } from '../sdpi';
import { fetchListLights, setLightsHUE, toggleLights } from '../ipc';

@action({ UUID: 'com.beyondcow.neewerlite.lightcontrol.hue' })
export class HUEControl extends SingletonAction<DialSettings> {
    #getTitle(): string {
        return streamDeck.i18n.t('hue');
    }

    syncSettings2UI(action: DialAction, settings: DialSettings) {
        settings.hue = Number(settings.hue);
        if (settings.selectedLights == undefined) {
            settings.selectedLights = [];
        }
        action.setSettings(settings);
        action.setFeedback({ indicator: { value: settings.hue }, value: Math.floor((settings.hue / 100.0) * 360) });
        action.setFeedback({
            title: `${this.#getTitle()}`,
            icon: 'imgs/actions/hue/icon',
        });
    }

    override async onWillAppear(ev: WillAppearEvent<DialSettings>): Promise<void> {
        if (!ev.action.isDial()) return;
        let settings = ev.payload.settings;
        if (settings.hue == null) {
            settings.hue = 0;
        }
        let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
        for (const light of lights) {
            if (light.state == -1) {
                //offline
                continue;
            }
            settings.light_state = light.state == 1;
            //settings.hue = light.hue;
            break;
        }
        ev.action.setSettings(settings);
        ev.action.setFeedback({
            title: `${this.#getTitle()}`,
            icon: 'imgs/actions/hue/icon',
            indicator: {
                value: settings.hue,
                bar_bg_c:
                    '0:#ff0000,0.1667:#ffff00,0.3333:#00ff00,0.5000:#00ffff,0.6667:#0000ff,0.8333:#ff00ff,1.0:#ff0000',
            },
            value: settings.hue + '',
        });
    }

    override onDialUp(ev: DialUpEvent<DialSettings>): Promise<void> | void {
        streamDeck.logger.info('onDialUp:', ev.payload.settings);
        let settings = ev.payload.settings;
        if (settings.selectedLights.length <= 0) {
            streamDeck.logger.warn('No lights selected to toggle.');
            ev.action.setFeedback({
                title: `${this.#getTitle()} ⚠️`,
                icon: 'imgs/actions/hue/icon',
            });
            return;
        }
        settings.light_state = !settings.light_state;
        toggleLights(ev.payload.settings.selectedLights, settings.light_state)
            .then((response) => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info('Lights toggled successfully:', response.body.switched);
                    ev.action.setSettings(settings);
                    ev.action.setFeedback({
                        title: `${this.#getTitle()}`,
                        icon: 'imgs/actions/hue/icon',
                    });
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
    override onDialRotate(ev: DialRotateEvent<DialSettings>): Promise<void> | void {
        let settings = ev.payload.settings;
        const { ticks } = ev.payload;
        if (ev.payload.settings.selectedLights == undefined || ev.payload.settings.selectedLights.length <= 0) {
            streamDeck.logger.warn('No lights selected to adjust temperature.');
            ev.action.setFeedback({
                title: `${this.#getTitle()} ⚠️`,
                icon: 'imgs/actions/hue/icon',
            });
            return;
        }

        settings.hue = Math.max(0, Math.min(256, settings.hue + ticks * 5));
        streamDeck.logger.warn('settings:', settings);
        setLightsHUE(ev.payload.settings.selectedLights, settings.hue)
            .then((response) => {
                if (response.body && response.body.success) {
                    streamDeck.logger.info('HUE set successfully:', response.body.switched);
                    this.syncSettings2UI(ev.action, settings);
                } else {
                    streamDeck.logger.warn('Failed to set HUE:', response.body);
                }
            })
            .catch((err) => {
                streamDeck.logger.error('setLightsHUE failed:', err);
            });
    }

    /**
     * Listen for messages from the property inspector.
     * @param ev Event information.
     */
    override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, DialSettings>): Promise<void> {
        streamDeck.logger.debug('Received message from property inspector:', ev);
        // Check if the payload is requesting a data source, i.e. the structure is { event: string }
        if (ev.payload instanceof Object && 'event' in ev.payload && ev.payload.event === 'deviceList') {
            let { lights = [] } = await streamDeck.settings.getGlobalSettings<GlobalSettings>();
            let ui_lights = [];
            for (const light of lights) {
                if (light.supportRGB) {
                    ui_lights.push({
                        label: light.name,
                        value: light.id,
                        disabled: light.state == -1,
                    });
                }
            }
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
type DialSettings = {
    light_state: boolean;
    value: number;
    light: number;
    hue: number;
    selectedLights: string[];
};

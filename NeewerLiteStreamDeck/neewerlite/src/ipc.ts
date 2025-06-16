import streamDeck, { LogLevel } from '@elgato/streamdeck';
import { httpGetJson, httpPostJson, HttpResponse } from './httpHelpers';
import { GlobalSettings } from './sdpi';
import type { Light } from './sdpi';

interface ListLightsResponse {
    lights: Light[];
}
interface PingResponse {
    status: string;
}
interface SwitchResponse {
    success: boolean;
    switched: string[];
}

export function pingApp(): Promise<HttpResponse<PingResponse>> {
    return httpGetJson<PingResponse>('/ping');
}

export function fetchListLights(): Promise<HttpResponse<ListLightsResponse>> {
    return httpGetJson<ListLightsResponse>('/listLights');
}

export function toggleLights(lights: string[], state: boolean): Promise<HttpResponse<SwitchResponse>> {
    state = Boolean(state);
    streamDeck.logger.trace('toggle target lights:', lights, 'state:', state);
    return httpPostJson<{ lights: string[]; state: boolean }, SwitchResponse>('/switch', {
        lights: lights,
        state: state,
    });
}

export function setLightsBrightness(lights: string[], brightness: number): Promise<HttpResponse<SwitchResponse>> {
    brightness = Number(brightness);
    streamDeck.logger.trace('setLightsBrightness target lights:', lights, 'brightness:', brightness);
    return httpPostJson<{ lights: string[]; brightness: number }, SwitchResponse>('/brightness', {
        lights: lights,
        brightness: brightness,
    });
}

export function setLightsTemperature(lights: string[], temperature: number): Promise<HttpResponse<SwitchResponse>> {
    temperature = Number(temperature);
    streamDeck.logger.trace('setLightsTemperature target lights:', lights, 'temperature:', temperature);
    return httpPostJson<{ lights: string[]; temperature: number }, SwitchResponse>('/temperature', {
        lights: lights,
        temperature: temperature,
    });
}

export function setLightsHUE(lights: string[], hue: number): Promise<HttpResponse<SwitchResponse>> {
    hue = Number(hue);
    streamDeck.logger.trace('setLightsHUE target lights:', lights, 'hue:', hue);
    return httpPostJson<{ lights: string[]; hue: number }, SwitchResponse>('/hue', { lights: lights, hue: hue });
}

export function setLightsSAT(lights: string[], sat: number): Promise<HttpResponse<SwitchResponse>> {
    sat = Number(sat);
    streamDeck.logger.trace('setLightsSAT target lights:', lights, 'sat:', sat);
    return httpPostJson<{ lights: string[]; saturation: number }, SwitchResponse>('/sat', {
        lights: lights,
        saturation: sat,
    });
}

export function setLightsFX(lights: string[], fx9: number, fx17: number): Promise<HttpResponse<SwitchResponse>> {
    fx9 = Number(fx9);
    fx17 = Number(fx17);
    streamDeck.logger.trace('setLightsFX target lights:', lights, 'fx9:', fx9, 'fx17:', fx17);
    return httpPostJson<{ lights: string[]; fx9: number; fx17: number }, SwitchResponse>('/fx', {
        lights: lights,
        fx9: fx9,
        fx17: fx17,
    });
}

export function setLightsCCT(
    lights: string[],
    brightness: number,
    temperature: number
): Promise<HttpResponse<SwitchResponse>> {
    brightness = Number(brightness);
    temperature = Number(temperature);
    streamDeck.logger.trace(
        'setLightsBrightness target lights:',
        lights,
        'brightness:',
        brightness,
        'temperature:',
        temperature
    );
    return httpPostJson<{ lights: string[]; brightness: number; temperature: number }, SwitchResponse>('/cct', {
        lights: lights,
        brightness: brightness,
        temperature: temperature,
    });
}

export function setLightsHST(
    lights: string[],
    brightness: number,
    saturation: number,
    hex_color: string
): Promise<HttpResponse<SwitchResponse>> {
    brightness = Number(brightness);
    saturation = Number(saturation);
    streamDeck.logger.info(
        'setLightsHST target lights:',
        lights,
        'brightness:',
        brightness,
        'saturation',
        saturation,
        'hex_color',
        hex_color
    );
    return httpPostJson<
        { lights: string[]; brightness: number; saturation: number; hex_color: string },
        SwitchResponse
    >('/hst', { lights: lights, brightness: brightness, saturation: saturation, hex_color: hex_color });
}

function heartbeat(): void {
    fetchListLights()
        .then((response) => {
            if (response.body && response.body.lights) {
                let lights = response.body.lights.map((light) => ({
                    id: light.id,
                    name: light.name,
                    cctRange: light.cctRange,
                    brightness: Number(light.brightness),
                    temperature: Number(light.temperature),
                    supportRGB: Number(light.supportRGB),
                    maxChannel: Number(light.maxChannel),
                    state: Number(light.state),
                }));
                // streamDeck.logger.info("Heartbeat: Found lights:", lights);
                streamDeck.settings.setGlobalSettings<GlobalSettings>({
                    lights: lights,
                    app_connected: true,
                });
            } else {
                streamDeck.logger.warn('No lights found in response.');
                streamDeck.settings.setGlobalSettings<GlobalSettings>({
                    lights: [],
                    app_connected: false,
                });
            }
        })
        .catch((err) => {
            streamDeck.logger.error('fetchListLights failed:', err);
            streamDeck.settings.setGlobalSettings<GlobalSettings>({
                lights: [],
                app_connected: false,
            });
        });
}

export function startHeartbeat() {
    setInterval(heartbeat, 1000);
}

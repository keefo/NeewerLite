import http from 'http';
import streamDeck, { LogLevel } from '@elgato/streamdeck';

export interface HttpResponse<T> {
    statusCode: number;
    headers: http.IncomingHttpHeaders;
    body: T;
}
const default_server = '127.0.0.1';
const default_port = 18486;
const user_agent = `neewerlite.sdPlugin/${streamDeck.info.plugin.version} streamDeck/${streamDeck.info.application.version}`;

/**
 * Perform a GET against localhost on the given port and path, and JSON-parse the response.
 *
 * @param path    The request path, e.g. "/listLights" or "/ping"
 * @param port    The port to talk to (default: 33445)
 */
export function httpGetJson<T>(path: string, port: number = default_port): Promise<HttpResponse<T>> {
    const options: http.RequestOptions = {
        hostname: default_server,
        port,
        path,
        method: 'GET',
        headers: {
            Accept: 'application/json',
            'user-agent': user_agent,
        },
    };

    return new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
            let data = '';
            res.setEncoding('utf8');
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                try {
                    streamDeck.logger.trace('data:', data);
                    const body = JSON.parse(data) as T;
                    resolve({
                        statusCode: res.statusCode ?? 0,
                        headers: res.headers,
                        body,
                    });
                } catch (err) {
                    reject(new Error(`httpGetJson: JSON parse error: ${err}`));
                }
            });
        });

        req.on('error', (err) => reject(err));
        req.end();
    });
}

/**
 * Perform a POST request to localhost on the given path and port with a JSON payload.
 */
export function httpPostJson<P, R>(path: string, payload: P, port: number = default_port): Promise<HttpResponse<R>> {
    const dataString = JSON.stringify(payload);
    const options: http.RequestOptions = {
        hostname: default_server,
        port,
        path,
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(dataString),
            Accept: 'application/json',
            'user-agent': user_agent,
        },
    };

    return new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
            let data = '';
            res.setEncoding('utf8');
            res.on('data', (chunk) => (data += chunk));
            res.on('end', () => {
                try {
                    const body = JSON.parse(data) as R;
                    resolve({ statusCode: res.statusCode || 0, headers: res.headers, body });
                } catch (err) {
                    reject(new Error(`httpPostJson: JSON parse error: ${err}`));
                }
            });
        });
        req.on('error', reject);
        req.write(dataString);
        req.end();
    });
}

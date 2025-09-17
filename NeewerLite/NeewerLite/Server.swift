import Foundation
import AppKit
import Swifter


extension DeviceViewObject {
    /// Matches a lightId against userLightName, rawName, or identifier (case-insensitive)
    func matches(lightId: String) -> Bool {
        let lower = lightId.lowercased()
        return device.userLightName.value.lowercased() == lower
            || device.rawName.lowercased()          == lower
            || device.identifier.lowercased()       == lower
    }
}

final class NeewerLiteServer {
    private let server = HttpServer()
    private let port: in_port_t
    private let appDelegate: AppDelegate?
    public var user_agent: String?
    
    init(appDelegate: AppDelegate, port: in_port_t = 18486) {
        self.appDelegate = appDelegate
        self.port = port
        setupRoutes()
    }

    deinit {
        stop()
    }
    
    /// Configure HTTP routes
    private func setupRoutes() {
        
        server.middleware.append { request in
            guard let ua = request.headers["user-agent"] else {
                // No UA header → reject
                return HttpResponse.unauthorized
            }
            if !ua.starts(with: "neewerlite.sdPlugin/")
            {
                return HttpResponse.unauthorized
            }
            // return nil to let the request continue on to your handlers
            return nil
        }
        
        // GET /listLights → returns dummy lights array
        server.GET["/listLights"] = { _ in
            var lights: [[String: Any]] = []
            self.appDelegate?.viewObjects.forEach {
                let name = $0.device.userLightName.value.isEmpty ? $0.device.rawName : $0.device.userLightName.value
                let cct = "\($0.device.CCTRange().minCCT)-\($0.device.CCTRange().maxCCT)"
                var item = ["id": "\($0.device.identifier)", "name": name, "cctRange": "\(cct)"]
                item["brightness"] = "\($0.device.brrValue.value)"
                item["temperature"] = "\($0.device.cctValue.value)"
                item["supportRGB"] = "\($0.device.supportRGB ? 1 : 0)"
                item["maxChannel"] = "\($0.device.maxChannel)"
                if !$0.deviceConnected
                {
                    item["state"] = "-1"
                }
                else if $0.device.isOn.value
                {
                    item["state"] = "1"
                }
                else
                {
                    item["state"] = "0"
                }
                lights.append(item)
            }
            let payload: [String: Any] = ["lights": lights]
            // Logger.debug(LogTag.server, "Received /listLights payload: \(payload)")
            return HttpResponse.ok(.json(payload))
        }

        // GET /ping → health check
        server.GET["/ping"] = { _ in
            // Logger.info(LogTag.server, "Received /ping")
            return HttpResponse.ok(.json(["status": "pong"]))
        }

        // 4. Switch lights endpoint
        //    Expects JSON payload: { "lights": ["Front", "Back"] }
        server.POST["/switch"] = { request in
            Logger.info(LogTag.server, "Received /switch request")
            let data = Data(request.body)
            struct SwitchPayload: Codable {
                let lights: [String]
                let state: Bool
            }
            let payload: SwitchPayload
            do {
                payload = try JSONDecoder().decode(SwitchPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            // Perform your switch logic here
            Logger.info(LogTag.server, "Switching lights: \(payload.lights) state: \(payload.state)")
            for light in payload.lights {
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        Task { @MainActor in
                            if payload.state {
                                if !viewObj.isON {
                                    viewObj.toggleLight()
                                }
                            }
                            else{
                                if viewObj.isON {
                                    viewObj.toggleLight()
                                }
                            }
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }

        server.POST["/brightness"] = { request in
            let data = Data(request.body)
            struct BrightnessPayload: Codable {
                let lights: [String]
                let brightness: CGFloat
            }
            let payload: BrightnessPayload
            do {
                payload = try JSONDecoder().decode(BrightnessPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            // Perform your switch logic here
            for light in payload.lights {
                Logger.info(LogTag.server, "light: \(light)")
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.device.setBRR100LightValues(payload.brightness)
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }
        
        server.POST["/temperature"] = { request in
            let data = Data(request.body)
            struct TemperaturePayload: Codable {
                let lights: [String]
                let temperature: CGFloat
            }
            let payload: TemperaturePayload
            do {
                payload = try JSONDecoder().decode(TemperaturePayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            // Perform your switch logic here
            for light in payload.lights {
                Logger.info(LogTag.server, "light: \(light)")
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                       Task { @MainActor in
                            viewObj.device.setCCTLightValues(brr: CGFloat(viewObj.device.brrValue.value), cct: CGFloat(payload.temperature), gmm: CGFloat(viewObj.device.gmmValue.value))
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }

        server.POST["/cct"] = { request in
            let data = Data(request.body)
            struct BrightnessPayload: Codable {
                let lights: [String]
                let brightness: CGFloat
                let temperature: CGFloat
            }
            let payload: BrightnessPayload
            do {
                payload = try JSONDecoder().decode(BrightnessPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            // Perform your switch logic here
            for light in payload.lights {
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                         Task { @MainActor in
                            viewObj.changeToCCTMode()
                            viewObj.device.setCCTLightValues(brr: CGFloat(payload.brightness), cct: CGFloat(payload.temperature), gmm: CGFloat(viewObj.device.gmmValue.value))
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }
        
        server.POST["/hst"] = { request in
            let data = Data(request.body)
            struct BrightnessPayload: Codable {
                let lights: [String]
                let brightness: CGFloat
                let saturation: CGFloat
                let hex_color: String
            }
            let payload: BrightnessPayload
            do {
                payload = try JSONDecoder().decode(BrightnessPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            let color = NSColor(hex: payload.hex_color, alpha: 1)
            let hueVal = CGFloat(color.hueComponent * 360.0)
            let satVal = CGFloat(payload.saturation / 100.0)
            // Perform your switch logic here
            for light in payload.lights {
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        if viewObj.device.supportRGB {
                            Task { @MainActor in
                                viewObj.changeToHSIMode()
                                viewObj.updateHSI(hue: hueVal, sat: satVal, brr: CGFloat(payload.brightness))
                            }
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }
        
        server.POST["/hue"] = { request in
            let data = Data(request.body)
            struct BrightnessPayload: Codable {
                let lights: [String]
                let hue: CGFloat  // 0-100
            }
            let payload: BrightnessPayload
            do {
                payload = try JSONDecoder().decode(BrightnessPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            let hueVal = payload.hue / 100.0 * 360.0
            // Perform your switch logic here
            for light in payload.lights {
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .filter { $0.device.supportRGB }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.changeToHSIMode()
                            viewObj.updateHSI(hue: hueVal, sat: CGFloat(viewObj.device.satValue.value), brr: CGFloat(viewObj.device.brrValue.value))
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }
        
        server.POST["/sat"] = { request in
            let data = Data(request.body)
            struct BrightnessPayload: Codable {
                let lights: [String]
                let saturation: CGFloat  // 0-100
            }
            let payload: BrightnessPayload
            do {
                payload = try JSONDecoder().decode(BrightnessPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            // Perform your switch logic here
            let satVal = CGFloat(payload.saturation / 100.0)
            Logger.info(LogTag.server, "cct lights: \(payload.lights) saturation: \(payload.saturation) satVal: \(satVal)")
            for light in payload.lights {
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .filter { $0.device.supportRGB }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.changeToHSIMode()
                            viewObj.updateHSI(hue: CGFloat(viewObj.device.hueValue.value), sat: satVal, brr: CGFloat(viewObj.device.brrValue.value))
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }
        
        server.POST["/fx"] = { request in
            let data = Data(request.body)
            struct BrightnessPayload: Codable {
                let lights: [String]
                let fx9: Int  // 1-9
                let fx17: Int  // 1-17
            }
            let payload: BrightnessPayload
            do {
                payload = try JSONDecoder().decode(BrightnessPayload.self, from: data)
            } catch {
                Logger.error(LogTag.server, "/switch: invalid JSON - \(error)")
                return HttpResponse.badRequest(.json(["error", "invalid JSON"]))
            }
            // Perform your switch logic here
            Logger.debug(LogTag.server, "cct lights: \(payload.lights) fx9: \(payload.fx9) fx17: \(payload.fx17)")
            for light in payload.lights {
                self.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                         if viewObj.device.maxChannel == 9 {
                            if payload.fx9 > 0 && payload.fx9 <= viewObj.device.maxChannel {
                                Task { @MainActor in
                                    viewObj.changeToSCEMode()
                                    viewObj.changeToSCE(payload.fx9, CGFloat(viewObj.device.brrValue.value))
                                }
                            }
                        }
                        else if viewObj.device.maxChannel == 17 {
                            if payload.fx9 > 0 && payload.fx17 <= viewObj.device.maxChannel {
                                Task { @MainActor in
                                    viewObj.changeToSCEMode()
                                    viewObj.changeToSCE(payload.fx17, CGFloat(viewObj.device.brrValue.value))
                                }
                            }
                        }
                    }
            }
            // Respond with success and echoed list
            return HttpResponse.ok(.json(["success": true, "switched": payload.lights]))
        }
        
        // Fallback for other routes
        server.notFoundHandler = { request in
            Logger.info(LogTag.server, "return notFound for \(request.path)")
            return HttpResponse.notFound
        }
    }

    /// Starts the HTTP server
    func start() {
        do {
            try server.start(self.port, forceIPv4: true)
            Logger.info(LogTag.server, "NeewerLiteServer listening on http://127.0.0.1:\(port)")
        } catch {
            Logger.error(LogTag.server, "Failed to start server: \(error)")
        }
    }

    /// Stops the HTTP server
    func stop() {
        server.stop()
        Logger.info(LogTag.server, "NeewerLiteServer stopped")
    }
}

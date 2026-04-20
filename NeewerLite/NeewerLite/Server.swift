import Foundation
import AppKit
import Vapor
import MCP

// Resolve Vapor/MCP type name conflicts
private typealias VaporRequest = Vapor.Request
private typealias VaporResponse = Vapor.Response

/// MCP SDK's `Value` decodes JSON integers as `.int`, not `.double`.
/// These helpers coerce across both numeric cases so tool handlers
/// don't silently fail when a client sends `80` instead of `80.0`.
extension Value {
    var numericDouble: Double? {
        if let d = doubleValue { return d }
        if let i = intValue { return Double(i) }
        return nil
    }

    var numericInt: Int? {
        if let i = intValue { return i }
        if let d = doubleValue { return Int(d) }
        return nil
    }
}


extension DeviceViewObject {
    /// Matches a lightId against userLightName, rawName, or identifier (case-insensitive)
    func matches(lightId: String) -> Bool {
        let lower = lightId.lowercased()
        return device.userLightName.value.lowercased() == lower
            || device.rawName.lowercased()          == lower
            || device.identifier.lowercased()       == lower
    }
}

// MARK: - Stream Deck Auth Middleware

struct StreamDeckAuthMiddleware: AsyncMiddleware {
    func respond(to request: Vapor.Request, chainingTo next: any AsyncResponder) async throws -> Vapor.Response {
        // MCP endpoint skips UA check — MCP clients send their own UA
        if request.url.path == "/mcp" {
            return try await next.respond(to: request)
        }
        guard let ua = request.headers.first(name: "User-Agent"),
              ua.hasPrefix("neewerlite.sdPlugin/") else {
            return VaporResponse(status: .unauthorized)
        }
        return try await next.respond(to: request)
    }
}

// MARK: - NeewerLite Server

final class NeewerLiteServer {
    private var app: Application?
    private var mcpServer: MCP.Server?
    private var transport: StatefulHTTPServerTransport?
    private let port: Int
    private let appDelegate: AppDelegate?
    public var user_agent: String?

    /// The actual port the server is listening on (may differ from `port` when port=0).
    private(set) var boundPort: Int?

    init(appDelegate: AppDelegate, port: Int = 18486) {
        self.appDelegate = appDelegate
        self.port = port
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    func start() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.startAsync()
            } catch {
                Logger.error(LogTag.server, "Failed to start server: \(error)")
            }
        }
    }

    /// Awaitable start — used by tests to know when the server is ready.
    func startAsync() async throws {
        let transport = StatefulHTTPServerTransport()
        self.transport = transport

        let mcpServer = await self.createMCPServer()
        self.mcpServer = mcpServer

        try await mcpServer.start(transport: transport)

        let app = try await Application.make(.development)
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = self.port
        app.logger.logLevel = .error
        app.environment.arguments = ["serve"]

        app.middleware.use(StreamDeckAuthMiddleware())
        self.setupStreamDeckRoutes(app)
        self.setupMCPRoute(app)

        try await app.startup()
        self.app = app
        self.boundPort = app.http.server.shared.localAddress?.port ?? self.port
        Logger.info(LogTag.server, "NeewerLiteServer listening on http://127.0.0.1:\(self.boundPort!)")
    }

    func stop() {
        let app = self.app
        let mcpServer = self.mcpServer
        let transport = self.transport
        self.app = nil
        self.mcpServer = nil
        self.transport = nil
        Task {
            if let app {
                try? await app.asyncShutdown()
            }
            await mcpServer?.stop()
        }
        Logger.info(LogTag.server, "NeewerLiteServer stopped")
    }

    // MARK: - MCP Server Setup

    private func createMCPServer() async -> MCP.Server {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let server = MCP.Server(
            name: "NeewerLite",
            version: version,
            instructions: "NeewerLite controls Neewer Bluetooth LED lights. Use list_lights to discover connected lights and their capabilities. Use list_scenes to see available scenes for a specific light before calling set_scene. Control lights with set_cct, set_hsi, set_scene, switch_light, or set_brightness."
        )

        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            self?.mcpToolsList() ?? ListTools.Result(tools: [])
        }

        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return toolResult("Server not available.", isError: true)
            }
            return self.handleMCPToolCall(params)
        }

        return server
    }

    // MARK: - MCP Route (Vapor ↔ MCP SDK)

    private func setupMCPRoute(_ app: Application) {
        let handler: @Sendable (VaporRequest) async throws -> VaporResponse = { [weak self] req in
            guard let self, let transport = self.transport else {
                return VaporResponse(status: .internalServerError)
            }
            // Convert Vapor Request → MCP HTTPRequest
            var headers: [String: String] = [:]
            for (name, value) in req.headers {
                headers[name] = value
            }
            let body: Data? = req.body.data.flatMap { buffer in
                buffer.getData(at: buffer.readerIndex, length: buffer.readableBytes)
            }
            let mcpRequest = MCP.HTTPRequest(
                method: req.method.rawValue,
                headers: headers,
                body: body,
                path: req.url.path
            )
            // Forward to MCP transport
            let mcpResponse = await transport.handleRequest(mcpRequest)
            // Convert MCP HTTPResponse → Vapor Response
            return self.convertMCPResponse(mcpResponse)
        }

        app.on(.POST, "mcp", use: handler)
        app.on(.GET, "mcp", use: handler)
        app.on(.DELETE, "mcp", use: handler)
    }

    private func convertMCPResponse(_ mcpResponse: MCP.HTTPResponse) -> VaporResponse {
        let status = HTTPResponseStatus(statusCode: mcpResponse.statusCode)
        var vaporHeaders = HTTPHeaders()
        for (key, value) in mcpResponse.headers {
            vaporHeaders.add(name: key, value: value)
        }

        switch mcpResponse {
        case .stream(let stream, _):
            let response = VaporResponse(status: status, headers: vaporHeaders)
            response.body = .init(asyncStream: { writer in
                do {
                    for try await chunk in stream {
                        let buffer = ByteBuffer(data: chunk)
                        try await writer.writeBuffer(buffer)
                    }
                    try await writer.write(.end)
                } catch {
                    try await writer.write(.error(error))
                }
            })
            return response
        default:
            let response = VaporResponse(status: status, headers: vaporHeaders)
            if let data = mcpResponse.bodyData {
                response.body = .init(data: data)
            }
            return response
        }
    }

    // MARK: - Stream Deck Routes

    private func setupStreamDeckRoutes(_ app: Application) {

        app.get("ping") { _ -> VaporResponse in
            return jsonResponse(["status": "pong"])
        }

        app.get("listLights") { [weak self] _ -> VaporResponse in
            var lights: [[String: Any]] = []
            self?.appDelegate?.viewObjects.forEach {
                let name = $0.device.userLightName.value.isEmpty ? $0.device.rawName : $0.device.userLightName.value
                let cct = "\($0.device.CCTRange().minCCT)-\($0.device.CCTRange().maxCCT)"
                var item: [String: Any] = ["id": "\($0.device.identifier)", "name": name, "cctRange": cct]
                item["brightness"] = "\($0.device.brrValue.value)"
                item["temperature"] = "\($0.device.cctValue.value)"
                item["supportRGB"] = "\($0.device.supportRGB ? 1 : 0)"
                item["maxChannel"] = "\($0.device.maxChannel)"
                if !$0.deviceConnected { item["state"] = "-1" }
                else if $0.device.isOn.value { item["state"] = "1" }
                else { item["state"] = "0" }
                lights.append(item)
            }
            return jsonResponse(["lights": lights])
        }

        app.post("switch") { [weak self] req async throws -> VaporResponse in
            struct SwitchPayload: Codable { let lights: [String]; let state: Bool }
            guard let payload = try? req.content.decode(SwitchPayload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        Task { @MainActor in
                            if payload.state {
                                if !viewObj.isON { viewObj.toggleLight() }
                            } else {
                                if viewObj.isON { viewObj.toggleLight() }
                            }
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("brightness") { [weak self] req async throws -> VaporResponse in
            struct Payload: Codable { let lights: [String]; let brightness: CGFloat }
            guard let payload = try? req.content.decode(Payload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.device.setBRR100LightValues(payload.brightness)
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("temperature") { [weak self] req async throws -> VaporResponse in
            struct Payload: Codable { let lights: [String]; let temperature: CGFloat }
            guard let payload = try? req.content.decode(Payload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.device.setCCTLightValues(
                                brr: CGFloat(viewObj.device.brrValue.value),
                                cct: CGFloat(payload.temperature),
                                gmm: CGFloat(viewObj.device.gmmValue.value))
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("cct") { [weak self] req async throws -> VaporResponse in
            struct Payload: Codable { let lights: [String]; let brightness: CGFloat; let temperature: CGFloat }
            guard let payload = try? req.content.decode(Payload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.changeToCCTMode()
                            viewObj.device.setCCTLightValues(
                                brr: CGFloat(payload.brightness),
                                cct: CGFloat(payload.temperature),
                                gmm: CGFloat(viewObj.device.gmmValue.value))
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("hst") { [weak self] req async throws -> VaporResponse in
            struct Payload: Codable {
                let lights: [String]; let brightness: CGFloat
                let saturation: CGFloat; let hex_color: String
            }
            guard let payload = try? req.content.decode(Payload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            let color = NSColor(hex: payload.hex_color, alpha: 1)
            let hueVal = CGFloat(color.hueComponent * 360.0)
            let satVal = CGFloat(payload.saturation / 100.0)
            for light in payload.lights {
                self?.appDelegate?.viewObjects
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
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("hue") { [weak self] req async throws -> VaporResponse in
            struct Payload: Codable { let lights: [String]; let hue: CGFloat }
            guard let payload = try? req.content.decode(Payload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            let hueVal = payload.hue / 100.0 * 360.0
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .filter { $0.device.supportRGB }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.changeToHSIMode()
                            viewObj.updateHSI(
                                hue: hueVal,
                                sat: CGFloat(viewObj.device.satValue.value),
                                brr: CGFloat(viewObj.device.brrValue.value))
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("sat") { [weak self] req async throws -> VaporResponse in
            struct Payload: Codable { let lights: [String]; let saturation: CGFloat }
            guard let payload = try? req.content.decode(Payload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            let satVal = CGFloat(payload.saturation / 100.0)
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .filter { $0.device.supportRGB }
                    .forEach { viewObj in
                        Task { @MainActor in
                            viewObj.changeToHSIMode()
                            viewObj.updateHSI(
                                hue: CGFloat(viewObj.device.hueValue.value),
                                sat: satVal,
                                brr: CGFloat(viewObj.device.brrValue.value))
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }

        app.post("fx") { [weak self] req async throws -> VaporResponse in
            struct FXPayload: Codable {
                let lights: [String]; let fx9: Int?; let fx17: Int?; let sceneId: Int?
            }
            guard let payload = try? req.content.decode(FXPayload.self) else {
                return jsonErrorResponse("invalid JSON")
            }
            for light in payload.lights {
                self?.appDelegate?.viewObjects
                    .filter { $0.matches(lightId: light) }
                    .forEach { viewObj in
                        let fxCount = viewObj.device.supportedFX.count
                        let resolvedId = payload.sceneId ?? (fxCount <= 9 ? payload.fx9 : payload.fx17)
                        if let id = resolvedId, id > 0 && id <= fxCount {
                            Task { @MainActor in
                                viewObj.changeToSCEMode()
                                viewObj.changeToSCE(id, CGFloat(viewObj.device.brrValue.value))
                            }
                        }
                    }
            }
            return jsonResponse(["success": true, "switched": payload.lights] as [String: Any])
        }
    }

    // MARK: - MCP Tool Definitions

    func mcpToolsList() -> ListTools.Result {
        let tools: [Tool] = [
            Tool(name: "list_lights",
                 description: "List all connected Neewer LED lights with their current state, brightness, color temperature, and capabilities. Shows capability flags (RGB, scenes, music) and scene count — use list_scenes to get the full scene list for a specific light.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([:]),
                    "required": .array([])
                 ])),

            Tool(name: "switch_light",
                 description: "Turn one or more Neewer lights on or off. Use list_lights first to see available light names.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "lights": .object(["type": "array", "items": .object(["type": "string"]), "description": "Light names or IDs. Use 'all' to target every connected light."]),
                        "state": .object(["type": "boolean", "description": "true = on, false = off"])
                    ]),
                    "required": .array(["lights", "state"])
                 ])),

            Tool(name: "set_brightness",
                 description: "Set brightness level for one or more lights. Does not change the current color mode.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "lights": .object(["type": "array", "items": .object(["type": "string"]), "description": "Light names or IDs."]),
                        "brightness": .object(["type": "number", "minimum": .int(0), "maximum": .int(100), "description": "Brightness percentage (0–100)."])
                    ]),
                    "required": .array(["lights", "brightness"])
                 ])),

            Tool(name: "set_cct",
                 description: "Set a light to white (CCT) mode with a specific color temperature and brightness. Good for video calls, photography, and general workspace lighting.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "lights": .object(["type": "array", "items": .object(["type": "string"]), "description": "Light names or IDs."]),
                        "brightness": .object(["type": "number", "minimum": .int(0), "maximum": .int(100), "description": "Brightness percentage (0–100)."]),
                        "temperature": .object(["type": "number", "minimum": .int(3200), "maximum": .int(8500), "description": "Color temperature in Kelvin. 3200K = warm/tungsten, 5600K = daylight, 8500K = cool/blue."])
                    ]),
                    "required": .array(["lights", "brightness", "temperature"])
                 ])),

            Tool(name: "set_hsi",
                 description: "Set a light to a specific color using hex color code. Only works on RGB-capable lights. Use list_lights to check RGB support first.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "lights": .object(["type": "array", "items": .object(["type": "string"]), "description": "Light names or IDs."]),
                        "hex_color": .object(["type": "string", "description": "Hex color code (e.g. 'FF0000' for red, '0066FF' for blue)."]),
                        "brightness": .object(["type": "number", "minimum": .int(0), "maximum": .int(100), "description": "Brightness percentage (0–100)."]),
                        "saturation": .object(["type": "number", "minimum": .int(0), "maximum": .int(100), "description": "Color saturation percentage (0–100). Default 100."])
                    ]),
                    "required": .array(["lights", "hex_color", "brightness"])
                 ])),

            Tool(name: "set_scene",
                 description: "Activate a dynamic scene effect on one or more lights. Use list_scenes first to see which scenes a light supports and their available parameters (color variants, speed, brightness). Pass the scene ID from list_scenes.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "lights": .object(["type": "array", "items": .object(["type": "string"]), "description": "Light names or IDs."]),
                        "scene_id": .object(["type": "integer", "minimum": .int(1), "description": "Scene effect ID from list_scenes. IDs are light-specific — always check list_scenes first."]),
                        "brightness": .object(["type": "integer", "minimum": .int(0), "maximum": .int(100), "description": "Scene brightness (0–100). Optional."]),
                        "speed": .object(["type": "integer", "minimum": .int(1), "maximum": .int(10), "description": "Scene animation speed (1–10). Optional."]),
                        "color": .object(["type": "integer", "minimum": .int(0), "description": "Color variant index from list_scenes. Optional."])
                    ]),
                    "required": .array(["lights", "scene_id"])
                 ])),

            Tool(name: "list_scenes",
                 description: "List all available scene effects for a specific light. Different lights support different scenes — an NS02 rope light has 73 scenes (nature, moods, holidays, sports), while a standard RGB panel has 9 or 17. Always call this before set_scene to get valid scene IDs.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "light": .object(["type": "string", "description": "Light name or ID. Must be a single light — scene lists are per-light."])
                    ]),
                    "required": .array(["light"])
                 ])),

            Tool(name: "scan_lights",
                 description: "Trigger a Bluetooth scan to discover new Neewer lights. Results will appear in list_lights after a few seconds.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([:]),
                    "required": .array([])
                 ])),

            Tool(name: "get_light_image",
                 description: "Get the product image of a connected light. Returns the image as base64-encoded PNG data. Useful for identifying the physical hardware model.",
                 inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "light": .object(["type": "string", "description": "Light name or ID."])
                    ]),
                    "required": .array(["light"])
                 ]))
        ]
        return ListTools.Result(tools: tools)
    }

    // MARK: - MCP Tool Call Dispatcher

    func handleMCPToolCall(_ params: CallTool.Parameters) -> CallTool.Result {
        Logger.info(LogTag.server, "/mcp tools/call: \(params.name)")

        switch params.name {
        case "list_lights":     return mcpToolCallListLights()
        case "switch_light":    return mcpToolCallSwitchLight(params.arguments)
        case "set_brightness":  return mcpToolCallSetBrightness(params.arguments)
        case "set_cct":         return mcpToolCallSetCCT(params.arguments)
        case "set_hsi":         return mcpToolCallSetHSI(params.arguments)
        case "set_scene":       return mcpToolCallSetScene(params.arguments)
        case "list_scenes":     return mcpToolCallListScenes(params.arguments)
        case "scan_lights":     return mcpToolCallScanLights()
        case "get_light_image": return mcpToolCallGetLightImage(params.arguments)
        default:                return toolResult("Unknown tool: \(params.name)", isError: true)
        }
    }

    // MARK: - MCP Tool Implementations

    private func mcpToolCallListLights() -> CallTool.Result {
        guard let viewObjects = appDelegate?.viewObjects else {
            return toolResult("NeewerLite is not ready.", isError: true)
        }
        if viewObjects.isEmpty {
            return toolResult("No lights found. Try scan_lights to discover new lights.")
        }
        var lines: [String] = ["Found \(viewObjects.count) light(s):"]
        for (i, obj) in viewObjects.enumerated() {
            let dev = obj.device
            let name = dev.userLightName.value.isEmpty ? dev.rawName : dev.userLightName.value
            let state: String
            if !obj.deviceConnected { state = "DISCONNECTED" }
            else if dev.isOn.value { state = "ON" }
            else { state = "OFF" }
            let cctRange = dev.CCTRange()
            var caps: [String] = []
            if dev.supportRGB { caps.append("RGB") }
            if dev.supportGMRange.value { caps.append("GM") }
            let fxCount = dev.supportedFX.count
            if fxCount > 0 { caps.append("\(fxCount) scenes") }
            if !dev.supportedMusicFX.isEmpty { caps.append("music-reactive ✓") }
            let capsStr = caps.isEmpty ? "CCT only" : caps.joined(separator: ", ")
            var modeInfo: String
            switch dev.lightMode {
            case .CCTMode:
                modeInfo = "CCT \(dev.cctValue.value)K"
                if dev.supportGMRange.value {
                    modeInfo += ", GM \(dev.gmmValue.value)"
                }
            case .HSIMode:
                modeInfo = "HSI hue \(dev.hueValue.value)° sat \(dev.satValue.value)%"
            case .SRCMode:
                if let activeSrc = dev.supportedSource.first(where: { $0.id == dev.sourceChannel.value }) {
                    modeInfo = "Source: \(activeSrc.name) (CCT \(dev.cctValue.value)K, GM \(dev.gmmValue.value))"
                } else {
                    modeInfo = "Source (id \(dev.sourceChannel.value))"
                }
            default:
                if let activeFX = dev.supportedFX.first(where: { $0.id == UInt16(dev.channel.value) }) {
                    modeInfo = "Scene: \(activeFX.name) (id \(activeFX.id))"
                } else {
                    modeInfo = "Scene (id \(dev.channel.value))"
                }
            }
            lines.append("\(i + 1). \(name) (id: \(dev.identifier)) — \(state), brightness \(dev.brrValue.value)%, \(modeInfo), CCT range \(cctRange.minCCT)-\(cctRange.maxCCT)K")
            lines.append("   Model: \(dev.projectName), rawName: \(dev.rawName), MAC: \(dev.getMAC())")
            let dbItem = ContentManager.shared.fetchLightProperty(lightType: dev.lightType)
            if let image = dbItem?.image, !image.isEmpty {
                lines.append("   Image: \(image)")
            }
            if let link = dbItem?.link, !link.isEmpty {
                lines.append("   Product URL: \(link)")
            }
            lines.append("   Capabilities: \(capsStr)")
        }
        return toolResult(lines.joined(separator: "\n"))
    }

    private func mcpToolCallSwitchLight(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let args = arguments,
              let lightsArr = args["lights"]?.arrayValue,
              let state = args["state"]?.boolValue else {
            return toolResult("Missing required parameters: lights (array), state (boolean).", isError: true)
        }
        let lights = lightsArr.compactMap { $0.stringValue }
        let targets = resolveViewObjects(lights)
        if targets.isEmpty {
            return toolResult("No matching lights found for: \(lights.joined(separator: ", "))", isError: true)
        }
        var switched: [String] = []
        for viewObj in targets {
            Task { @MainActor in
                if state {
                    if !viewObj.isON { viewObj.toggleLight() }
                } else {
                    if viewObj.isON { viewObj.toggleLight() }
                }
            }
            let name = viewObj.device.userLightName.value.isEmpty ? viewObj.device.rawName : viewObj.device.userLightName.value
            switched.append(name)
        }
        return toolResult("Turned \(state ? "on" : "off"): \(switched.joined(separator: ", "))")
    }

    private func mcpToolCallSetBrightness(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let args = arguments,
              let lightsArr = args["lights"]?.arrayValue,
              let brightness = args["brightness"]?.numericDouble else {
            return toolResult("Missing required parameters: lights (array), brightness (number).", isError: true)
        }
        let lights = lightsArr.compactMap { $0.stringValue }
        let targets = resolveViewObjects(lights)
        if targets.isEmpty {
            return toolResult("No matching lights found for: \(lights.joined(separator: ", "))", isError: true)
        }
        var updated: [String] = []
        for viewObj in targets {
            Task { @MainActor in
                let dev = viewObj.device
                if dev.lightMode == .HSIMode {
                    dev.setHSILightValues(brr100: CGFloat(brightness),
                                          hue: CGFloat(dev.hueValue.value) / 360.0,
                                          hue360: CGFloat(dev.hueValue.value),
                                          sat: CGFloat(dev.satValue.value) / 100.0)
                } else {
                    viewObj.changeToCCTMode()
                    dev.setCCTLightValues(brr: CGFloat(brightness),
                                          cct: CGFloat(dev.cctValue.value),
                                          gmm: CGFloat(dev.gmmValue.value))
                }
            }
            let name = viewObj.device.userLightName.value.isEmpty ? viewObj.device.rawName : viewObj.device.userLightName.value
            updated.append(name)
        }
        return toolResult("Set brightness to \(Int(brightness))%: \(updated.joined(separator: ", "))")
    }

    private func mcpToolCallSetCCT(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let args = arguments,
              let lightsArr = args["lights"]?.arrayValue,
              let brightness = args["brightness"]?.numericDouble,
              let temperature = args["temperature"]?.numericDouble else {
            return toolResult("Missing required parameters: lights (array), brightness (number), temperature (number).", isError: true)
        }
        let lights = lightsArr.compactMap { $0.stringValue }
        let targets = resolveViewObjects(lights)
        if targets.isEmpty {
            return toolResult("No matching lights found for: \(lights.joined(separator: ", "))", isError: true)
        }
        var updated: [String] = []
        for viewObj in targets {
            Task { @MainActor in
                viewObj.changeToCCTMode()
                viewObj.device.setCCTLightValues(
                    brr: CGFloat(brightness),
                    cct: CGFloat(temperature),
                    gmm: CGFloat(viewObj.device.gmmValue.value))
            }
            let name = viewObj.device.userLightName.value.isEmpty ? viewObj.device.rawName : viewObj.device.userLightName.value
            updated.append(name)
        }
        return toolResult("Set CCT mode — \(Int(brightness))% brightness, \(Int(temperature))K: \(updated.joined(separator: ", "))")
    }

    private func mcpToolCallSetHSI(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let args = arguments,
              let lightsArr = args["lights"]?.arrayValue,
              let hexColor = args["hex_color"]?.stringValue,
              let brightness = args["brightness"]?.numericDouble else {
            return toolResult("Missing required parameters: lights (array), hex_color (string), brightness (number).", isError: true)
        }
        let saturation = args["saturation"]?.numericDouble ?? 100.0
        let lights = lightsArr.compactMap { $0.stringValue }
        let targets = resolveViewObjects(lights)
        if targets.isEmpty {
            return toolResult("No matching lights found for: \(lights.joined(separator: ", "))", isError: true)
        }
        let color = NSColor(hex: hexColor, alpha: 1)
        let hueVal = CGFloat(color.hueComponent * 360.0)
        let satVal = CGFloat(saturation / 100.0)
        var updated: [String] = []
        var skipped: [String] = []
        for viewObj in targets {
            let name = viewObj.device.userLightName.value.isEmpty ? viewObj.device.rawName : viewObj.device.userLightName.value
            if viewObj.device.supportRGB {
                Task { @MainActor in
                    viewObj.changeToHSIMode()
                    viewObj.device.setHSILightValues(brr100: CGFloat(brightness),
                                                     hue: hueVal / 360.0,
                                                     hue360: hueVal,
                                                     sat: satVal)
                }
                updated.append(name)
            } else {
                skipped.append(name)
            }
        }
        var text = "Set HSI mode — color #\(hexColor), \(Int(brightness))% brightness, \(Int(saturation))% saturation"
        if !updated.isEmpty { text += ": \(updated.joined(separator: ", "))" }
        if !skipped.isEmpty { text += "\nSkipped (no RGB support): \(skipped.joined(separator: ", "))" }
        return toolResult(text, isError: updated.isEmpty)
    }

    private func mcpToolCallSetScene(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let args = arguments,
              let lightsArr = args["lights"]?.arrayValue,
              let sceneId = args["scene_id"]?.numericInt else {
            return toolResult("Missing required parameters: lights (array), scene_id (integer).", isError: true)
        }
        let lights = lightsArr.compactMap { $0.stringValue }
        let targets = resolveViewObjects(lights)
        if targets.isEmpty {
            return toolResult("No matching lights found for: \(lights.joined(separator: ", "))", isError: true)
        }
        let optBrightness = args["brightness"]?.numericInt
        let optSpeed = args["speed"]?.numericInt
        let optColor = args["color"]?.numericInt
        var updated: [String] = []
        var errors: [String] = []
        for viewObj in targets {
            let name = viewObj.device.userLightName.value.isEmpty ? viewObj.device.rawName : viewObj.device.userLightName.value
            let fxCount = viewObj.device.supportedFX.count
            if sceneId > 0 && sceneId <= fxCount {
                let fx = viewObj.device.supportedFX[sceneId - 1]
                if let brr = optBrightness, fx.needBRR { fx.brrValue = CGFloat(brr) }
                if let speed = optSpeed, fx.needSpeed { fx.speedValue = speed }
                if let color = optColor, fx.needColor { fx.colorValue = color }
                Task { @MainActor in
                    viewObj.device.sendSceneCommand(fx)
                }
                updated.append("\(name) → \(fx.name)")
            } else {
                errors.append("\(name): scene_id \(sceneId) out of range (1–\(fxCount))")
            }
        }
        var text = ""
        if !updated.isEmpty { text += "Activated scene: \(updated.joined(separator: ", "))" }
        if !errors.isEmpty {
            if !text.isEmpty { text += "\n" }
            text += "Errors: \(errors.joined(separator: "; "))"
        }
        return toolResult(text, isError: updated.isEmpty)
    }

    private func mcpToolCallListScenes(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let lightId = arguments?["light"]?.stringValue else {
            return toolResult("Missing required parameter: light (string).", isError: true)
        }
        guard let viewObjects = appDelegate?.viewObjects else {
            return toolResult("NeewerLite is not ready.", isError: true)
        }
        guard let viewObj = viewObjects.first(where: { $0.matches(lightId: lightId) }) else {
            return toolResult("No light found matching: \(lightId)", isError: true)
        }
        let dev = viewObj.device
        let name = dev.userLightName.value.isEmpty ? dev.rawName : dev.userLightName.value
        let scenes = dev.supportedFX
        if scenes.isEmpty {
            return toolResult("\(name) does not support scenes.")
        }
        var lines: [String] = ["\(name) — \(scenes.count) scene(s):"]
        for fx in scenes {
            var detail = "  \(fx.id). \(fx.name)"
            var params: [String] = []
            if fx.needBRR { params.append("brightness: 0–100") }
            if fx.needSpeed { params.append("speed: 1–10") }
            if fx.needColor && !fx.colors.isEmpty {
                let colorNames = fx.colors.enumerated().map { "\($0.offset): \($0.element.key)" }
                params.append("color: [\(colorNames.joined(separator: ", "))]")
            }
            if !params.isEmpty {
                detail += " (\(params.joined(separator: ", ")))"
            }
            lines.append(detail)
        }
        let musicFX = dev.supportedMusicFX
        if !musicFX.isEmpty {
            lines.append("")
            lines.append("Music-reactive modes (\(musicFX.count)):")
            for fx in musicFX {
                lines.append("  \(fx.id). \(fx.name)")
            }
        }
        return toolResult(lines.joined(separator: "\n"))
    }

    private func mcpToolCallScanLights() -> CallTool.Result {
        Task { @MainActor in
            self.appDelegate?.scanAction(self)
        }
        return toolResult("Bluetooth scan started. Use list_lights in a few seconds to see newly discovered lights.")
    }

    private func mcpToolCallGetLightImage(_ arguments: [String: Value]?) -> CallTool.Result {
        guard let args = arguments,
              let lightId = args["light"]?.stringValue else {
            return toolResult("Missing required parameter: light (string).", isError: true)
        }
        let targets = resolveViewObjects([lightId])
        guard let obj = targets.first else {
            return toolResult("Light not found or not connected: \(lightId)", isError: true)
        }
        let dev = obj.device
        let lightType = dev.lightType

        // Try to get image: cached NSImage → tiffRepresentation → PNG
        let image = ContentManager.shared.fetchCachedLightImage(lightType: lightType)

        // If no cached image, try loading from resolved URL directly
        let imageData: Data?
        if let img = image, let tiff = img.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            imageData = bitmap.representation(using: .png, properties: [:])
        } else if let imageRef = ContentManager.shared.fetchLightProperty(lightType: lightType)?.image,
                  let url = ContentManager.shared.resolveImageURL(imageRef, subdirectory: "light_images") {
            imageData = try? Data(contentsOf: url)
        } else {
            imageData = nil
        }

        guard let data = imageData, !data.isEmpty else {
            return toolResult("No product image available for this light.")
        }

        let base64 = data.base64EncodedString()
        let name = dev.userLightName.value.isEmpty ? dev.rawName : dev.userLightName.value
        return CallTool.Result(content: [
            .text(text: "Product image for \(name) (\(dev.projectName)):", annotations: nil, _meta: nil),
            .image(data: base64, mimeType: "image/png", annotations: nil, _meta: nil)
        ])
    }

    // MARK: - Helpers

    /// Resolve light name list to DeviceViewObjects. "all" expands to every connected light.
    private func resolveViewObjects(_ lights: [String]) -> [DeviceViewObject] {
        guard let viewObjects = appDelegate?.viewObjects else { return [] }
        if lights.contains(where: { $0.lowercased() == "all" }) {
            return viewObjects.filter { $0.deviceConnected }
        }
        return lights.flatMap { lightId in
            viewObjects.filter { $0.matches(lightId: lightId) && $0.deviceConnected }
        }
    }
}

// MARK: - Private Helpers

private func toolResult(_ text: String, isError: Bool = false) -> CallTool.Result {
    CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: isError)
}

private func jsonResponse(_ object: Any) -> VaporResponse {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else {
        return VaporResponse(status: .internalServerError)
    }
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    return VaporResponse(status: .ok, headers: headers, body: .init(data: data))
}

private func jsonErrorResponse(_ message: String) -> VaporResponse {
    guard let data = try? JSONSerialization.data(withJSONObject: ["error": message]) else {
        return VaporResponse(status: .internalServerError)
    }
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/json")
    return VaporResponse(status: .badRequest, headers: headers, body: .init(data: data))
}

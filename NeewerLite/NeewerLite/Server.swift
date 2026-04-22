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
        // Public endpoints — no auth required
        if request.url.path == "/mcp" || request.url.path == "/ping"
            || request.url.path == "/sse" || request.url.path == "/messages" {
            return try await next.respond(to: request)
        }
        guard let ua = request.headers.first(name: "User-Agent"),
              ua.hasPrefix("neewerlite.sdPlugin/") else {
            return VaporResponse(status: .unauthorized)
        }
        return try await next.respond(to: request)
    }
}

private final class MCPSessionContext {
    let clientKey: String
    let transport: StatefulHTTPServerTransport
    let server: MCP.Server
    var sessionID: String?
    var lastSeen: Date

    init(clientKey: String, transport: StatefulHTTPServerTransport, server: MCP.Server) {
        self.clientKey = clientKey
        self.transport = transport
        self.server = server
        self.lastSeen = Date()
    }
}

private actor SessionManager {
    private var sessionsByClientKey: [String: MCPSessionContext] = [:]
    private var clientKeyBySessionID: [String: String] = [:]
    private let maxSessions: Int

    init(maxSessions: Int) {
        self.maxSessions = maxSessions
    }

    func context(forSessionID sessionID: String) -> MCPSessionContext? {
        guard let clientKey = clientKeyBySessionID[sessionID] else { return nil }
        return sessionsByClientKey[clientKey]
    }

    func context(forClientKey clientKey: String) -> MCPSessionContext? {
        sessionsByClientKey[clientKey]
    }

    func getOrCreateContext(for clientKey: String, create: @Sendable () async throws -> MCPSessionContext) async throws -> MCPSessionContext {
        if let existing = sessionsByClientKey[clientKey] {
            existing.lastSeen = Date()
            return existing
        }

        if sessionsByClientKey.count >= maxSessions,
           let oldest = sessionsByClientKey.values.min(by: { $0.lastSeen < $1.lastSeen }) {
            await removeContext(oldest)
        }

        let context = try await create()
        sessionsByClientKey[clientKey] = context
        return context
    }

    func bindSessionID(_ sessionID: String, to context: MCPSessionContext) {
        context.sessionID = sessionID
        context.lastSeen = Date()
        clientKeyBySessionID[sessionID] = context.clientKey
    }

    func touch(_ context: MCPSessionContext) {
        context.lastSeen = Date()
    }

    func removeContext(_ context: MCPSessionContext) async {
        sessionsByClientKey.removeValue(forKey: context.clientKey)
        if let sid = context.sessionID {
            clientKeyBySessionID.removeValue(forKey: sid)
        }
        await context.server.stop()
    }

    func shutdownAll() async {
        let contexts = Array(sessionsByClientKey.values)
        sessionsByClientKey.removeAll()
        clientKeyBySessionID.removeAll()
        for context in contexts {
            await context.server.stop()
        }
    }
}

private actor BLECommandCoordinator {
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping () async -> Void) async {
        let previous = tail
        let current = Task {
            if let previous {
                _ = await previous.result
            }
            await operation()
        }
        tail = current
        _ = await current.result
    }
}

// MARK: - NeewerLite Server

final class NeewerLiteServer {
    private var app: Application?
    private let sessionManager = SessionManager(maxSessions: 24)
    private let bleCommandCoordinator = BLECommandCoordinator()
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
        let app = try await Application.make(.development)
        app.http.server.configuration.hostname = "127.0.0.1"
        app.http.server.configuration.port = self.port
        app.logger.logLevel = .error
        app.environment.arguments = ["serve"]

        app.middleware.use(StreamDeckAuthMiddleware())
        self.setupStreamDeckRoutes(app)
        self.setupMCPRoute(app)
        self.setupLegacySSERoutes(app)

        try await app.startup()
        self.app = app
        self.boundPort = app.http.server.shared.localAddress?.port ?? self.port
        Logger.info(LogTag.server, "NeewerLiteServer listening on http://127.0.0.1:\(self.boundPort!)")
    }

    func stop() {
        let app = self.app
        let sessionManager = self.sessionManager
        self.app = nil
        Task {
            if let app {
                try? await app.asyncShutdown()
            }
            await sessionManager.shutdownAll()
        }
        Logger.info(LogTag.server, "NeewerLiteServer stopped")
    }

    // MARK: - MCP Server Setup

    private func createMCPServer() async -> MCP.Server {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let server = MCP.Server(
            name: "NeewerLite",
            version: version,
            instructions: "NeewerLite controls Neewer Bluetooth LED lights. Use list_lights to discover connected lights and their capabilities. Use list_scenes to see available scenes for a specific light before calling set_scene. Control lights with set_cct, set_hsi, set_scene, switch_light, or set_brightness.",
            capabilities: MCP.Server.Capabilities(
                tools: MCP.Server.Capabilities.Tools(listChanged: false)
            )
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

    // MARK: - Legacy SSE Transport  (GET /sse  +  POST /messages)
    //
    // Supports the older MCP "HTTP+SSE" transport used by some clients (e.g. OpenClaw's
    // Python runtime) that were written before the Streamable HTTP spec.
    //
    // Protocol:
    //   1. Client opens GET /sse → receives a persistent text/event-stream.
    //      Server immediately sends:  event: endpoint\ndata: /messages?sessionId=<uuid>\n\n
    //   2. Client POSTs JSON-RPC messages to /messages?sessionId=<uuid>
    //      Server processes each via the Streamable HTTP transport and pushes
    //      the JSON-RPC response back as SSE data events on the open stream.

    private final class LegacySSESession {
        let id: String
        /// SSE events → client (the GET /sse response body reads from this)
        let outbound: AsyncStream<String>
        let outCont: AsyncStream<String>.Continuation
        /// JSON-RPC bodies → server (POST /messages writes into this)
        let inbound: AsyncStream<Data>
        let inCont: AsyncStream<Data>.Continuation

        init(id: String) {
            self.id = id
            var o: AsyncStream<String>.Continuation!
            self.outbound = AsyncStream { o = $0 }
            self.outCont = o!
            var i: AsyncStream<Data>.Continuation!
            self.inbound = AsyncStream { i = $0 }
            self.inCont = i!
        }

        func pushSSE(_ event: String) { outCont.yield(event) }
        func pushMessage(_ data: Data) { inCont.yield(data) }
        func finish() { outCont.finish(); inCont.finish() }
    }

    private let sseSessionLock = NSLock()
    private var sseSessions: [String: LegacySSESession] = [:]

    private func setupLegacySSERoutes(_ app: Application) {

        // GET /sse — open persistent SSE stream
        app.get("sse") { [weak self] req -> VaporResponse in
            guard let self else { return VaporResponse(status: .internalServerError) }

            let sessionId = UUID().uuidString
            let session = LegacySSESession(id: sessionId)
            self.sseSessionLock.withLock { self.sseSessions[sessionId] = session }
            Logger.info(LogTag.server, "[SSE-LEGACY] opened session=\(sessionId)")

            // Pump inbound messages through the MCP stack on a background task
            Task { [weak self] in
                guard let self else { return }
                await self.drainLegacySSEInbound(session: session)
            }

            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "text/event-stream")
            headers.add(name: .cacheControl, value: "no-cache, no-transform")
            headers.add(name: .connection, value: "keep-alive")

            let response = VaporResponse(status: .ok, headers: headers)
            response.body = .init(asyncStream: { writer in
                // Tell the client where to POST messages
                let endpointEvent = "event: endpoint\ndata: /messages?sessionId=\(sessionId)\n\n"
                try? await writer.writeBuffer(ByteBuffer(string: endpointEvent))

                // Stream outbound SSE events until the session ends
                for await chunk in session.outbound {
                    try? await writer.writeBuffer(ByteBuffer(string: chunk))
                }
                try? await writer.write(.end)

                // Clean up after client disconnects
                self.sseSessionLock.withLock { self.sseSessions.removeValue(forKey: sessionId) }
                Logger.info(LogTag.server, "[SSE-LEGACY] closed session=\(sessionId)")
            })
            return response
        }

        // POST /messages — deliver a JSON-RPC message to the session
        app.post("messages") { [weak self] req -> VaporResponse in
            guard let self else { return VaporResponse(status: .internalServerError) }

            guard let sessionId = req.query[String.self, at: "sessionId"],
                  let session = self.sseSessionLock.withLock({ self.sseSessions[sessionId] }) else {
                return VaporResponse(status: .notFound)
            }
            guard let buffer = req.body.data,
                  let data = buffer.getData(at: buffer.readerIndex, length: buffer.readableBytes) else {
                return VaporResponse(status: .badRequest)
            }

            Logger.info(LogTag.server, "[SSE-LEGACY] POST /messages session=\(sessionId)")
            session.pushMessage(data)
            return VaporResponse(status: .accepted)
        }
    }

    /// Reads JSON-RPC messages from a legacy SSE session's inbound queue,
    /// routes each through the (reused) Streamable HTTP session context,
    /// then pushes the response as SSE data events back to the client.
    private func drainLegacySSEInbound(session: LegacySSESession) async {
        let clientKey = "sse-legacy-\(session.id)"

        for await messageData in session.inbound {
            // Reuse (or create) an MCP session context for this SSE connection
            let context: MCPSessionContext
            do {
                context = try await sessionManager.getOrCreateContext(for: clientKey) { [weak self] in
                    guard let self else { throw MCPError.internalError("Server gone") }
                    return try await self.createSessionContext(clientKey: clientKey)
                }
            } catch {
                Logger.error(LogTag.server, "[SSE-LEGACY] could not get session context: \(error)")
                continue
            }

            // Wrap the JSON-RPC body as a fake /mcp POST
            var fakeHeaders = ["Content-Type": "application/json",
                               "Accept": "application/json, text/event-stream"]
            if let sid = context.sessionID {
                fakeHeaders["Mcp-Session-Id"] = sid
            }
            let mcpRequest = MCP.HTTPRequest(method: "POST", headers: fakeHeaders,
                                             body: messageData, path: "/mcp")

            let mcpResponse = await context.transport.handleRequest(mcpRequest)

            // Eagerly register new session IDs
            if let sid = self.headerValue("Mcp-Session-Id", from: mcpResponse.headers) {
                await sessionManager.bindSessionID(sid, to: context)
            }
            await sessionManager.touch(context)

            // Push response chunks as SSE data events
            switch mcpResponse {
            case .stream(let stream, _):
                do {
                    for try await chunk in stream {
                        guard let text = String(data: chunk, encoding: .utf8),
                              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        // Strip SSE framing if the SDK already added it; wrap bare JSON
                        let event = text.hasPrefix("data:") ? text : "data: \(text)\n\n"
                        session.pushSSE(event)
                    }
                } catch {
                    Logger.error(LogTag.server, "[SSE-LEGACY] stream error: \(error)")
                }
            default:
                if let data = mcpResponse.bodyData,
                   let text = String(data: data, encoding: .utf8) {
                    let event = text.hasPrefix("data:") ? text : "data: \(text)\n\n"
                    session.pushSSE(event)
                }
            }
        }
    }

    // MARK: - MCP Route (Vapor ↔ MCP SDK)

    private func setupMCPRoute(_ app: Application) {
        let handler: @Sendable (VaporRequest) async throws -> VaporResponse = { [weak self] req in
            guard let self else {
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

            let clientKey = self.resolveMCPClientKey(req)
            let sessionID = self.headerValue("Mcp-Session-Id", from: headers)
            Logger.info(
                LogTag.server,
                "[MCPDBG][REQ] method=\(req.method.rawValue) path=\(req.url.path) session=\(sessionID ?? "none") ua=\(self.headerValue("User-Agent", from: headers) ?? "none") accept=\(self.headerValue("Accept", from: headers) ?? "none") contentType=\(self.headerValue("Content-Type", from: headers) ?? "none")"
            )

            if req.method == .GET, sessionID == nil {
                Logger.info(LogTag.server, "[MCPDBG][GET] no-session async notification probe")
                return self.makeAsyncNotificationProbeResponse()
            }

            let context: MCPSessionContext
            if let sessionID, let existing = await self.sessionManager.context(forSessionID: sessionID) {
                Logger.info(LogTag.server, "[MCPDBG][SESSION] resolved existing context by session id=\(sessionID)")
                context = existing
            } else if self.isInitializeRequest(body) {
                Logger.info(LogTag.server, "[MCPDBG][SESSION] initialize request; resolving context by client key")
                do {
                    context = try await self.sessionManager.getOrCreateContext(for: clientKey) { [weak self] in
                        guard let self else {
                            throw MCPError.internalError("Server no longer available")
                        }
                        return try await self.createSessionContext(clientKey: clientKey)
                    }
                } catch {
                    Logger.error(LogTag.server, "Failed to create MCP session context: \(error)")
                    return VaporResponse(status: .serviceUnavailable)
                }
            } else {
                Logger.warn(LogTag.server, "[MCPDBG][SESSION] request without valid session and not initialize; returning terminated-session error")
                let invalidResponse = self.invalidTerminatedSessionResponse(sessionID: sessionID)
                return self.convertMCPResponse(invalidResponse)
            }

            let mcpResponse = await context.transport.handleRequest(mcpRequest)
            Logger.info(LogTag.server, "[MCPDBG][RESP] status=\(mcpResponse.statusCode) sessionHeader=\(self.headerValue("Mcp-Session-Id", from: mcpResponse.headers) ?? "none")")
            await self.sessionManager.touch(context)

            // Bind the session ID BEFORE converting/streaming the response body.
            // OpenClaw (and other eager clients) fire a follow-up request immediately
            // after receiving the initialize response headers — if we bind after streaming
            // the follow-up arrives before the session is registered and gets a 404.
            if let returnedSessionID = self.headerValue("Mcp-Session-Id", from: mcpResponse.headers) {
                await self.sessionManager.bindSessionID(returnedSessionID, to: context)
            }

            if req.method == .DELETE, mcpResponse.statusCode == 200 {
                await self.sessionManager.removeContext(context)
            }

            // Convert MCP HTTPResponse → Vapor Response
            return self.convertMCPResponse(mcpResponse)
        }

        app.on(.POST, "mcp", use: handler)
        app.on(.GET, "mcp", use: handler)
        app.on(.DELETE, "mcp", use: handler)
    }

    private func makeAsyncNotificationProbeResponse() -> VaporResponse {
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/event-stream")
        headers.add(name: .cacheControl, value: "no-cache, no-transform")
        headers.add(name: .connection, value: "keep-alive")

        let response = VaporResponse(status: .ok, headers: headers)
        response.body = .init(asyncStream: { writer in
            do {
                Logger.info(LogTag.server, "[MCPDBG][GET-probe] writing async notification probe comment")
                let buffer = ByteBuffer(string: ": awaiting session initialization\n\n")
                try await writer.writeBuffer(buffer)
                try await writer.write(.end)
            } catch {
                Logger.error(LogTag.server, "[MCPDBG][GET-probe] stream write failed: \(error)")
                try await writer.write(.error(error))
            }
        })
        return response
    }

    private func createSessionContext(clientKey: String) async throws -> MCPSessionContext {
        let transport = StatefulHTTPServerTransport()
        let server = await createMCPServer()
        try await server.start(transport: transport)
        return MCPSessionContext(clientKey: clientKey, transport: transport, server: server)
    }

    private func invalidTerminatedSessionResponse(sessionID: String?) -> MCP.HTTPResponse {
        MCP.HTTPResponse.error(
            statusCode: 404,
            .invalidRequest("Not Found: Session has been terminated"),
            sessionID: sessionID
        )
    }

    private func resolveMCPClientKey(_ req: VaporRequest) -> String {
        let ip = req.remoteAddress?.ipAddress ?? req.remoteAddress?.description ?? "unknown-remote"
        let ua = req.headers.first(name: "User-Agent") ?? ""

        // OpenClaw may use different stacks/user agents across requests
        // (notably undici + Python-urllib). Keep those mapped to one logical
        // client key so session creation/reuse remains stable.
        if ua.lowercased().contains("python-urllib") || ua.lowercased().contains("undici") {
            return "openclaw@\(ip)"
        }

        // For regular clients, include UA to preserve per-client isolation
        // when multiple clients connect from the same loopback IP.
        if !ua.isEmpty {
            return "\(ua)@\(ip)"
        }
        return ip
    }

    private func headerValue(_ name: String, from headers: [String: String]) -> String? {
        if let direct = headers[name] { return direct }
        return headers.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    private func isInitializeRequest(_ body: Data?) -> Bool {
        guard let body,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = payload["method"] as? String else {
            return false
        }
        return method == "initialize"
    }

    private func convertMCPResponse(_ mcpResponse: MCP.HTTPResponse) -> VaporResponse {
        let status = HTTPResponseStatus(statusCode: mcpResponse.statusCode)
        var vaporHeaders = HTTPHeaders()
        for (key, value) in mcpResponse.headers {
            vaporHeaders.add(name: key, value: value)
        }

        switch mcpResponse {
        case .stream(let stream, _):
            Logger.info(LogTag.server, "[MCPDBG][CONVERT] streaming response status=\(status.code)")
            let response = VaporResponse(status: status, headers: vaporHeaders)
            response.body = .init(asyncStream: { writer in
                do {
                    for try await chunk in stream {
                        guard let sanitizedChunk = self.sanitizedSSEChunk(chunk) else {
                            Logger.info(LogTag.server, "[MCPDBG][SSE] filtered priming/empty chunk")
                            continue
                        }
                        Logger.info(LogTag.server, "[MCPDBG][SSE] forwarding chunk bytes=\(sanitizedChunk.count)")
                        let buffer = ByteBuffer(data: sanitizedChunk)
                        try await writer.writeBuffer(buffer)
                    }
                    try await writer.write(.end)
                } catch {
                    Logger.error(LogTag.server, "[MCPDBG][SSE] stream forwarding failed: \(error)")
                    try await writer.write(.error(error))
                }
            })
            return response
        default:
            Logger.info(LogTag.server, "[MCPDBG][CONVERT] non-stream response status=\(status.code) bodyBytes=\(mcpResponse.bodyData?.count ?? 0)")
            let response = VaporResponse(status: status, headers: vaporHeaders)
            if let data = mcpResponse.bodyData {
                response.body = .init(data: data)
            }
            return response
        }
    }

    private func sanitizedSSEChunk(_ chunk: Data) -> Data? {
        guard let text = String(data: chunk, encoding: .utf8) else {
            return chunk
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return nil
        }

        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }

        let isPrimingEvent = !lines.isEmpty && lines.allSatisfy { line in
            line.hasPrefix("id: ") || line.hasPrefix("retry: ") || line == "data: "
        }

        return isPrimingEvent ? nil : chunk
    }

    // MARK: - Stream Deck Routes

    private func enqueueBLEOperation(_ operation: @escaping () async -> Void) {
        Task {
            await self.bleCommandCoordinator.enqueue(operation)
        }
    }

    private func setupStreamDeckRoutes(_ app: Application) {

        app.get("ping") { [weak self] _ -> VaporResponse in
            let lightCount = self?.appDelegate?.viewObjects.count ?? 0
            return jsonResponse(["status": "ok", "lights": lightCount])
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
                        self?.enqueueBLEOperation {
                            await MainActor.run {
                                if payload.state {
                                    if !viewObj.isON { viewObj.toggleLight() }
                                } else {
                                    if viewObj.isON { viewObj.toggleLight() }
                                }
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
                        self?.enqueueBLEOperation {
                            await MainActor.run {
                                viewObj.device.setBRR100LightValues(payload.brightness)
                            }
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
                        self?.enqueueBLEOperation {
                            await MainActor.run {
                                viewObj.device.setCCTLightValues(
                                    brr: CGFloat(viewObj.device.brrValue.value),
                                    cct: CGFloat(payload.temperature),
                                    gmm: CGFloat(viewObj.device.gmmValue.value))
                            }
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
                        self?.enqueueBLEOperation {
                            await MainActor.run {
                                viewObj.changeToCCTMode()
                                viewObj.device.setCCTLightValues(
                                    brr: CGFloat(payload.brightness),
                                    cct: CGFloat(payload.temperature),
                                    gmm: CGFloat(viewObj.device.gmmValue.value))
                            }
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
                            self?.enqueueBLEOperation {
                                await MainActor.run {
                                    viewObj.changeToHSIMode()
                                    viewObj.updateHSI(hue: hueVal, sat: satVal, brr: CGFloat(payload.brightness))
                                }
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
                        self?.enqueueBLEOperation {
                            await MainActor.run {
                                viewObj.changeToHSIMode()
                                viewObj.updateHSI(
                                    hue: hueVal,
                                    sat: CGFloat(viewObj.device.satValue.value),
                                    brr: CGFloat(viewObj.device.brrValue.value))
                            }
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
                        self?.enqueueBLEOperation {
                            await MainActor.run {
                                viewObj.changeToHSIMode()
                                viewObj.updateHSI(
                                    hue: CGFloat(viewObj.device.hueValue.value),
                                    sat: satVal,
                                    brr: CGFloat(viewObj.device.brrValue.value))
                            }
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
                            self?.enqueueBLEOperation {
                                await MainActor.run {
                                    viewObj.changeToSCEMode()
                                    viewObj.changeToSCE(id, CGFloat(viewObj.device.brrValue.value))
                                }
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
                 description: "List all connected Neewer LED lights with their current state, brightness, color temperature, and capabilities. Shows capability flags (RGB, scenes, sources, music) and preset counts — use list_scenes and list_sources to get full per-light preset lists.",
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

              Tool(name: "list_sources",
                  description: "List all available light source presets for a specific light (for lights that support source mode). Call this before setting a source preset.",
                  inputSchema: .object([
                    "type": "object",
                    "properties": .object([
                        "light": .object(["type": "string", "description": "Light name or ID. Must be a single light — source presets are per-light."])
                    ]),
                    "required": .array(["light"])
                  ])),

                            Tool(name: "list_gels",
                                    description: "List all available gel presets for a specific light. Gels are virtual color-filter presets and require RGB-capable lights.",
                                    inputSchema: .object([
                                        "type": "object",
                                        "properties": .object([
                                                "light": .object(["type": "string", "description": "Light name or ID. Must be a single light."])
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
        case "list_sources":    return mcpToolCallListSources(params.arguments)
        case "list_gels":       return mcpToolCallListGels(params.arguments)
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
            let sourceCount = dev.supportedSource.count
            if sourceCount > 0 { caps.append("\(sourceCount) sources") }
            let gelCount = GelLibrary.shared.all.count
            if dev.supportRGB && gelCount > 0 { caps.append("\(gelCount) gels") }
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
            enqueueBLEOperation {
                await MainActor.run {
                    if state {
                        if !viewObj.isON { viewObj.toggleLight() }
                    } else {
                        if viewObj.isON { viewObj.toggleLight() }
                    }
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
            enqueueBLEOperation {
                await MainActor.run {
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
            enqueueBLEOperation {
                await MainActor.run {
                    viewObj.changeToCCTMode()
                    viewObj.device.setCCTLightValues(
                        brr: CGFloat(brightness),
                        cct: CGFloat(temperature),
                        gmm: CGFloat(viewObj.device.gmmValue.value))
                }
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
                enqueueBLEOperation {
                    await MainActor.run {
                        viewObj.changeToHSIMode()
                        viewObj.updateHSI(hue: hueVal, sat: satVal, brr: brightness)
                    }
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
                enqueueBLEOperation {
                    await MainActor.run {
                        // Keep the control view in sync with MCP scene changes.
                        viewObj.changeToSCEMode()
                        viewObj.changeToSCE(sceneId, fx.needBRR ? Double(fx.brrValue) : nil)
                        viewObj.device.sendSceneCommand(fx)
                    }
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

    private func mcpToolCallListSources(_ arguments: [String: Value]?) -> CallTool.Result {
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
        let sources = dev.supportedSource
        if sources.isEmpty {
            return toolResult("\(name) does not support source presets.")
        }
        var lines: [String] = ["\(name) — \(sources.count) source preset(s):"]
        for src in sources {
            var detail = "  \(src.id). \(src.name)"
            var params: [String] = []
            if src.needBRR { params.append("brightness") }
            if src.needCCT { params.append("cct") }
            if src.needGM { params.append("gm") }
            if !params.isEmpty {
                detail += " (params: \(params.joined(separator: ", ")))"
            }
            lines.append(detail)
        }
        return toolResult(lines.joined(separator: "\n"))
    }

    private func mcpToolCallListGels(_ arguments: [String: Value]?) -> CallTool.Result {
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
        guard dev.supportRGB else {
            return toolResult("\(name) does not support gels (RGB required).")
        }

        let gels = GelLibrary.shared.all
        if gels.isEmpty {
            return toolResult("No gel presets available in database.")
        }

        var lines: [String] = ["\(name) — \(gels.count) gel preset(s):"]
        for (idx, gel) in gels.enumerated() {
            let maker = gel.manufacturer.isEmpty ? "Generic" : gel.manufacturer
            let code = gel.code.isEmpty ? "-" : gel.code
            lines.append("  \(idx + 1). \(gel.name) [\(maker) \(code)] — hue \(Int(gel.hue))°, sat \(Int(gel.saturation))%, transmission \(Int(gel.transmissionPercent))%")
        }
        return toolResult(lines.joined(separator: "\n"))
    }

    private func mcpToolCallScanLights() -> CallTool.Result {
        enqueueBLEOperation {
            await MainActor.run {
                self.appDelegate?.scanAction(self)
            }
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

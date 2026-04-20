//
//  MCPServerTests.swift
//  NeewerLiteTests
//
//  Created on 4/19/26.
//

import XCTest
import MCP
@testable import NeewerLite

final class MCPServerTests: XCTestCase {

    private var server: NeewerLiteServer!

    override func setUpWithError() throws {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        server = NeewerLiteServer(appDelegate: appDelegate, port: 0)
    }

    override func tearDownWithError() throws {
        server = nil
    }

    // MARK: - Tool List Tests

    func testToolsList_returns9Tools() throws {
        let result = server.mcpToolsList()
        XCTAssertEqual(result.tools.count, 9, "Expected 9 MCP tools")
    }

    func testToolsList_expectedToolNames() throws {
        let result = server.mcpToolsList()
        let names = Set(result.tools.map(\.name))
        let expected: Set<String> = [
            "list_lights", "switch_light", "set_brightness", "set_cct",
            "set_hsi", "set_scene", "list_scenes", "scan_lights", "get_light_image"
        ]
        XCTAssertEqual(names, expected, "Tool names mismatch")
    }

    func testToolsList_allToolsHaveDescriptionAndSchema() throws {
        let result = server.mcpToolsList()
        for tool in result.tools {
            XCTAssertFalse(tool.name.isEmpty, "Tool has empty name")
            XCTAssertNotNil(tool.description, "Tool \(tool.name) missing description")
            XCTAssertFalse(tool.description?.isEmpty ?? true, "Tool \(tool.name) has empty description")
            XCTAssertNotNil(tool.inputSchema, "Tool \(tool.name) missing inputSchema")
        }
    }

    // MARK: - Value Numeric Coercion Tests

    func testNumericInt_fromInt_returnsExactValue() {
        let value = Value.int(80)
        XCTAssertEqual(value.numericInt, 80)
    }

    func testNumericInt_fromWholeDouble_returnsInt() {
        let value = Value.double(80.0)
        XCTAssertEqual(value.numericInt, 80)
    }

    func testNumericInt_fromFractionalDouble_truncates() {
        // LLM sends brightness: 80.5 — must not silently drop to nil
        let value = Value.double(80.5)
        XCTAssertEqual(value.numericInt, 80, "Fractional double should truncate, not return nil")
    }

    func testNumericInt_fromNegativeFractionalDouble_truncates() {
        let value = Value.double(-3.7)
        XCTAssertEqual(value.numericInt, -3)
    }

    func testNumericDouble_fromDouble_returnsExactValue() {
        let value = Value.double(80.5)
        XCTAssertEqual(value.numericDouble, 80.5)
    }

    func testNumericDouble_fromInt_returnsDouble() {
        let value = Value.int(80)
        XCTAssertEqual(value.numericDouble, 80.0)
    }

    func testNumericInt_fromString_returnsNil() {
        let value = Value.string("80")
        XCTAssertNil(value.numericInt)
    }

    func testNumericDouble_fromString_returnsNil() {
        let value = Value.string("80.5")
        XCTAssertNil(value.numericDouble)
    }

    // MARK: - Tool Call Dispatcher Tests

    func testHandleMCPToolCall_unknownTool() throws {
        let params = CallTool.Parameters(name: "nonexistent_tool", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        XCTAssertTrue(text?.contains("Unknown tool") ?? false)
    }

    func testHandleMCPToolCall_listLights() throws {
        let params = CallTool.Parameters(name: "list_lights", arguments: nil)
        let result = server.handleMCPToolCall(params)
        // Either returns lights or "No lights found" — neither is an error
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        XCTAssertNotNil(text, "list_lights should return text content")
    }

    func testHandleMCPToolCall_scanLights() throws {
        let params = CallTool.Parameters(name: "scan_lights", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertNotEqual(result.isError, true)
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        XCTAssertTrue(text?.contains("scan") ?? false)
    }

    // MARK: - Missing Parameter Validation

    func testSwitchLight_missingParams() throws {
        let params = CallTool.Parameters(name: "switch_light", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    func testSetBrightness_missingParams() throws {
        let params = CallTool.Parameters(name: "set_brightness", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    func testSetCCT_missingParams() throws {
        let params = CallTool.Parameters(name: "set_cct", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    func testSetHSI_missingParams() throws {
        let params = CallTool.Parameters(name: "set_hsi", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    func testSetScene_missingParams() throws {
        let params = CallTool.Parameters(name: "set_scene", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    func testListScenes_missingParams() throws {
        let params = CallTool.Parameters(name: "list_scenes", arguments: nil)
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    // MARK: - No Matching Lights

    func testSwitchLight_noMatchingLights() throws {
        let params = CallTool.Parameters(
            name: "switch_light",
            arguments: ["lights": .array([.string("nonexistent_light_xyz")]), "state": .bool(true)]
        )
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        XCTAssertTrue(text?.contains("No matching") ?? false)
    }

    func testSetCCT_noMatchingLights() throws {
        let params = CallTool.Parameters(
            name: "set_cct",
            arguments: [
                "lights": .array([.string("nonexistent_light_xyz")]),
                "brightness": .double(50),
                "temperature": .double(5600)
            ]
        )
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
    }

    func testListScenes_noMatchingLight() throws {
        let params = CallTool.Parameters(
            name: "list_scenes",
            arguments: ["light": .string("nonexistent_light_xyz")]
        )
        let result = server.handleMCPToolCall(params)
        XCTAssertEqual(result.isError, true)
        let text = result.content.first.flatMap { content -> String? in
            if case .text(let t, _, _) = content { return t }
            return nil
        }
        XCTAssertTrue(text?.contains("No light found") ?? false)
    }
}

// MARK: - Integration Tests (real HTTP server)

final class MCPServerIntegrationTests: XCTestCase {

    private var server: NeewerLiteServer!
    private var baseURL: String!

    override func setUp() async throws {
        let appDelegate = await MainActor.run {
            NSApplication.shared.delegate as! AppDelegate
        }
        server = NeewerLiteServer(appDelegate: appDelegate, port: 0)
        try await server.startAsync()
        guard let port = server.boundPort else {
            XCTFail("Server did not bind to a port")
            return
        }
        baseURL = "http://127.0.0.1:\(port)"
    }

    override func tearDown() async throws {
        server.stop()
        // Give Vapor time to release resources
        try await Task.sleep(nanoseconds: 200_000_000)
        server = nil
    }

    // MARK: - Lifecycle

    func testServerStartAndStop() async throws {
        // Server started in setUp — just verify it's listening
        let (data, response) = try await httpGet("/ping", userAgent: "neewerlite.sdPlugin/1.0")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "pong")
    }

    // MARK: - Stream Deck Auth Middleware

    func testMiddleware_rejectsNoUserAgent() async throws {
        let (_, response) = try await httpGet("/ping")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 401)
    }

    func testMiddleware_rejectsWrongUserAgent() async throws {
        let (_, response) = try await httpGet("/ping", userAgent: "curl/7.0")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 401)
    }

    func testMiddleware_acceptsStreamDeckUA() async throws {
        let (_, response) = try await httpGet("/ping", userAgent: "neewerlite.sdPlugin/2.0")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
    }

    func testMiddleware_mcpEndpointSkipsUACheck() async throws {
        // MCP endpoint should not require Stream Deck UA
        let body = mcpJSON(id: 1, method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [:],
            "clientInfo": ["name": "test", "version": "1.0"]
        ] as [String: Any])
        let (_, response) = try await httpPostMCP(body)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        // Should be 200 (accepted) not 401
        XCTAssertNotEqual(httpResponse.statusCode, 401, "MCP endpoint should skip UA check")
    }

    // MARK: - Stream Deck Routes

    func testStreamDeck_ping() async throws {
        let (data, response) = try await httpGet("/ping", userAgent: "neewerlite.sdPlugin/1.0")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "pong")
    }

    func testStreamDeck_listLights() async throws {
        let (data, response) = try await httpGet("/listLights", userAgent: "neewerlite.sdPlugin/1.0")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["lights"], "Response should contain 'lights' key")
    }

    func testStreamDeck_switchInvalidJSON() async throws {
        let (data, response) = try await httpPost("/switch", body: Data("not json".utf8), userAgent: "neewerlite.sdPlugin/1.0")
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 400)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["error"])
    }

    // MARK: - MCP Protocol (Streamable HTTP)

    func testMCP_initialize() async throws {
        let body = mcpJSON(id: 1, method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [:],
            "clientInfo": ["name": "test-client", "version": "1.0"]
        ] as [String: Any])
        let (json, httpResponse) = try await mcpPostJSON(body)
        XCTAssertEqual(httpResponse.statusCode, 200)

        XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json?["id"] as? Int, 1)
        let result = json?["result"] as? [String: Any]
        XCTAssertNotNil(result?["serverInfo"])
        XCTAssertNotNil(result?["capabilities"])

        let serverInfo = result?["serverInfo"] as? [String: Any]
        XCTAssertEqual(serverInfo?["name"] as? String, "NeewerLite")
    }

    func testMCP_initializeThenListTools() async throws {
        // Step 1: Initialize and get session ID
        let initBody = mcpJSON(id: 1, method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [:],
            "clientInfo": ["name": "test", "version": "1.0"]
        ] as [String: Any])
        let (_, initHTTP) = try await mcpPostJSON(initBody)
        XCTAssertEqual(initHTTP.statusCode, 200)
        let sessionId = initHTTP.value(forHTTPHeaderField: "Mcp-Session-Id")

        // Step 2: Send initialized notification
        let notifBody = mcpJSON(id: nil, method: "notifications/initialized", params: [:] as [String: Any])
        let _ = try await httpPostMCP(notifBody, sessionId: sessionId)

        // Step 3: List tools
        let toolsBody = mcpJSON(id: 2, method: "tools/list", params: [:] as [String: Any])
        let (json, toolsHTTP) = try await mcpPostJSON(toolsBody, sessionId: sessionId)
        XCTAssertEqual(toolsHTTP.statusCode, 200)

        let result = json?["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 9, "Expected 9 tools from tools/list")

        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        XCTAssertTrue(names.contains("list_lights"))
        XCTAssertTrue(names.contains("scan_lights"))
    }

    func testMCP_toolCallListLights() async throws {
        // Initialize
        let initBody = mcpJSON(id: 1, method: "initialize", params: [
            "protocolVersion": "2025-03-26",
            "capabilities": [:],
            "clientInfo": ["name": "test", "version": "1.0"]
        ] as [String: Any])
        let (_, initHTTP) = try await mcpPostJSON(initBody)
        let sessionId = initHTTP.value(forHTTPHeaderField: "Mcp-Session-Id")

        // Notification
        let notifBody = mcpJSON(id: nil, method: "notifications/initialized", params: [:] as [String: Any])
        let _ = try await httpPostMCP(notifBody, sessionId: sessionId)

        // Call list_lights
        let callBody = mcpJSON(id: 3, method: "tools/call", params: [
            "name": "list_lights",
            "arguments": [:] as [String: Any]
        ] as [String: Any])
        let (json, callHTTP) = try await mcpPostJSON(callBody, sessionId: sessionId)
        XCTAssertEqual(callHTTP.statusCode, 200)

        let result = json?["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        XCTAssertNotNil(content, "tools/call should return content array")
        XCTAssertEqual(content?.first?["type"] as? String, "text")
    }

    // MARK: - HTTP Helpers

    private func httpGet(_ path: String, userAgent: String? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        if let ua = userAgent { request.setValue(ua, forHTTPHeaderField: "User-Agent") }
        return try await URLSession.shared.data(for: request)
    }

    private func httpPost(_ path: String, body: Data, userAgent: String? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let ua = userAgent { request.setValue(ua, forHTTPHeaderField: "User-Agent") }
        return try await URLSession.shared.data(for: request)
    }

    private func httpPostMCP(_ body: Data, sessionId: String? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: URL(string: baseURL + "/mcp")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sid = sessionId { request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id") }
        return try await URLSession.shared.data(for: request)
    }

    /// Posts to MCP and parses the response as JSON, handling both plain JSON
    /// and SSE-wrapped responses (`event: message\ndata: {...}\n\n`).
    private func mcpPostJSON(_ body: Data, sessionId: String? = nil) async throws -> ([String: Any]?, HTTPURLResponse) {
        let (data, resp) = try await httpPostMCP(body, sessionId: sessionId)
        let httpResp = resp as! HTTPURLResponse
        let contentType = httpResp.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("text/event-stream") {
            // Parse SSE: extract last "data:" line payload
            let text = String(data: data, encoding: .utf8) ?? ""
            let jsonPayload = text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("data:") }
                .last
                .map { String($0.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces) }
            if let payload = jsonPayload, let payloadData = payload.data(using: .utf8) {
                let json = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
                return (json, httpResp)
            }
            return (nil, httpResp)
        } else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json, httpResp)
        }
    }

    private func mcpJSON(id: Int?, method: String, params: [String: Any]) -> Data {
        var dict: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        if let id { dict["id"] = id }
        return try! JSONSerialization.data(withJSONObject: dict)
    }
}

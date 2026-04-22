# AI Integration

> NeewerLite × MCP — Exposing Neewer lights as MCP tools for agentic control, powered by the official MCP Swift SDK and Vapor.

---

## 1. Overview

NeewerLite exposes Neewer Bluetooth LED lights as [MCP](https://modelcontextprotocol.io) tools, so any MCP-compatible AI agent — VS Code Copilot, Claude Desktop, OpenClaw, Cursor — can discover and control your lights with natural language: *"set the key light to warm white at 80%"* or *"flash red if the build fails."*

**How it works:** The app embeds an MCP server using the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) and [Vapor](https://github.com/vapor/vapor). It runs entirely in-process — no CLI, no Node.js, no bridge. Users start the server from Settings and register one URL in their AI tool. The server exposes 11 tools covering every light control operation NeewerLite supports.

**Transport:** Primary transport is **Streamable HTTP** (`POST/GET/DELETE /mcp`) with per-client session isolation via a `SessionManager` actor. A legacy SSE transport (`GET /sse` + `POST /messages`) is also available for older MCP clients. The Stream Deck REST API shares the same Vapor server on `localhost:18486`.

**Why this stack:**
- **MCP Swift SDK** handles all protocol complexity — JSON-RPC, `Mcp-Session-Id` management, SSE streaming, origin/content-type validation, resumability. No hand-rolled protocol code.
- **Vapor** provides async/await HTTP with proper streaming body support. Replaced the previous Swifter dependency for both MCP and Stream Deck routes.
- **One process** — same port (18486), same server, same light control logic shared by all callers.

---

## 2. Current HTTP Server (Stream Deck)

`Server.swift` already exposes these endpoints on `localhost:18486`:

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/ping` | Health check |
| GET | `/listLights` | List all lights with state, brightness, CCT, RGB support |
| POST | `/switch` | Turn lights on/off |
| POST | `/brightness` | Set brightness |
| POST | `/temperature` | Set color temperature |
| POST | `/cct` | Set CCT mode (brightness + temperature) |
| POST | `/hst` | Set HSI mode (hex color + brightness + saturation) |
| POST | `/hue` | Set hue only |
| POST | `/sat` | Set saturation only |
| POST | `/fx` | Activate scene effect |

Auth: `User-Agent` prefix check (`neewerlite.sdPlugin/`).

These endpoints continue to serve the Stream Deck plugin unchanged. MCP traffic goes through a new `/mcp` endpoint.

---

## 3. Architecture

```
┌──────────────┐                          ┌────────────────────────────────────────┐
│   OpenClaw   │                          │           NeewerLite.app               │
│  Claude      │  Streamable HTTP         │                                        │
│  VS Code     │  POST/GET/DELETE /mcp    │  Vapor HTTP Server (:18486)            │
│  Cursor      │  ────────────────────►   │  ├── /mcp ──► SessionManager           │
│  Any MCP     │   localhost:18486        │  │             (per-client context)     │
│  Client      │                          │  │             ──► StatefulHTTP+Server  │
└──────────────┘                          │  │                 ├── 11 tool handlers │
                                          │  │                                      │
┌──────────────┐                          │  ├── /sse  ──► Legacy SSE transport     │
│  OpenClaw    │  Legacy SSE              │  ├── /messages   (older clients)        │
│ (Python UA)  │  GET /sse, POST /messages│  │                                      │
│              │  ────────────────────►   │  ├── /listLights  ← Stream Deck        │
└──────────────┘   localhost:18486        │  ├── /switch       ← Stream Deck        │
                                          │  └── ...                                │
┌──────────────┐                          │                                        │
│  Stream Deck │   REST (JSON)            │  Light control logic (shared)          │
│  Plugin      │  ────────────────────►   │         │                              │
└──────────────┘   localhost:18486        │    CoreBluetooth                       │
                                          │         │                              │
                                          └─────────┼──────────────────────────────┘
                                                    │
                                             ┌──────▼───────┐
                                             │  Neewer LED  │
                                             │   Lights     │
                                             └──────────────┘
```

### Dependency Stack

| Layer | Component | Role |
|---|---|---|
| HTTP Server | **Vapor** | Listen on port, route requests, serve responses. Replaces Swifter |
| MCP Protocol | **MCP Swift SDK** (`StatefulHTTPServerTransport` + `Server`) | JSON-RPC, sessions, SSE, tool schemas, request validation |
| Session Isolation | **`SessionManager`** actor | Per-client `StatefulHTTPServerTransport`+`Server` contexts, session ID routing, TTL eviction, max-24 cap |
| Business Logic | Tool handlers (11 tools) | Light control via `NeewerLight` device API |
| Hardware | CoreBluetooth | BLE commands to physical lights |

### How it connects

The MCP SDK's `StatefulHTTPServerTransport` is **framework-agnostic** — it takes an `HTTPRequest` (SDK type) and returns an `HTTPResponse` (SDK type). Vapor acts as the HTTP adapter:

```swift
// Vapor route → MCP SDK transport
app.on(.POST, "mcp") { req -> Response in
    let sdkRequest = HTTPRequest(
        method: "POST",
        headers: req.headers.asDictionary(),
        body: req.body.data.map { Data(buffer: $0) },
        path: "/mcp"
    )
    let sdkResponse = await transport.handleRequest(sdkRequest)
    return sdkResponse.toVaporResponse()
}
```

The MCP SDK `Server` handles `initialize`, `tools/list`, `tools/call` via registered handlers — no manual JSON-RPC parsing needed.

---

## 4. MCP Streamable HTTP Transport

NeewerLite uses the MCP Swift SDK's `StatefulHTTPServerTransport` which implements the full [MCP Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#streamable-http) specification.

### 4.1 What the SDK Handles (we don't write this code)

| Feature | SDK Component |
|---|---|
| JSON-RPC parsing & routing | `Server` + `Transport` |
| `initialize` handshake | `Server.start(transport:)` |
| `Mcp-Session-Id` management | `StatefulHTTPServerTransport` |
| SSE streaming for POST responses | `StatefulHTTPServerTransport` |
| Standalone GET SSE stream | `StatefulHTTPServerTransport` |
| Session termination via DELETE | `StatefulHTTPServerTransport` |
| Request validation (Origin, Content-Type, Accept, Protocol-Version) | `StandardValidationPipeline` |
| Event store for resumability (Last-Event-ID) | `StatefulHTTPServerTransport` |
| `notifications/initialized` handling | `Server` |
| `ping` handling | `Server` |
| Tool schema registration & discovery | `Server.withMethodHandler(ListTools.self)` |
| Tool call dispatch | `Server.withMethodHandler(CallTool.self)` |

### 4.2 What We Write

| Component | Scope |
|---|---|
| Vapor route adapter (`POST/GET/DELETE /mcp`) | Convert Vapor Request ↔ SDK HTTPRequest/HTTPResponse |
| `ListTools` handler | Return 8 tool schemas using SDK's `Tool` type |
| `CallTool` handler | Dispatch to 8 tool implementations |
| 8 tool implementations | Light control via device API (mostly reused from Phase 1) |
| Stream Deck routes | Port existing endpoints from Swifter to Vapor |

### 4.3 Protocol Version

The SDK implements MCP specification **2025-11-25** (latest). This is a version upgrade from our Phase 1 implementation which used 2025-03-26.

---

## 5. MCP Tool Definitions

> **Note:** The tool names below are from the original spec. During Phase 2 implementation, the tools evolved: `switch_light` → `turn_on`/`turn_off`, `set_brightness` merged into `set_light_cct`, `set_cct` → `set_light_cct`, `set_hsi` → `set_light_hsi`, `set_scene` → `set_light_scene`, `list_scenes` removed, `scan_lights` → `scan`, and `get_light_image`/`get_logs` added. See `Server.swift` for the actual schemas.

### 5.1 `list_lights`

> Query all connected Neewer lights and their current state.

```json
{
  "name": "list_lights",
  "description": "List all connected Neewer LED lights with their current state, brightness, color temperature, and capabilities. Shows capability flags (RGB, scenes, music) and scene count — use list_scenes to get the full scene list for a specific light.",
  "inputSchema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

**Implementation:** Reuses the same `viewObjects` iteration as `GET /listLights`, plus reads `supportedFX.count`, `supportRGB`, and `supportedMusicFX` from each `NeewerLight`.

**Return:** Human-readable text summary with capability flags so the agent knows what each light can do.

```json
{
  "content": [{
    "type": "text",
    "text": "Found 2 lights:\n1. KeyLight (NL660) — ON, brightness 80%, CCT 5600K\n   Capabilities: RGB ✓, 17 scenes, music-reactive ✓\n2. RopeLight (NS02) — ON, brightness 60%, CCT 4500K\n   Capabilities: RGB ✓, 73 scenes, music-reactive ✓"
  }]
}
```

**Design note:** `list_lights` intentionally omits scene names to keep responses concise. The NS02 alone has 73 scenes — listing all of them here would waste tokens. The agent should call `list_scenes` when it needs scene details for a specific light.

### 5.2 `switch_light`

> Turn lights on or off.

```json
{
  "name": "switch_light",
  "description": "Turn one or more Neewer lights on or off. Use list_lights first to see available light names.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "lights": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Light names or IDs to control. Use 'all' to target every connected light."
      },
      "state": {
        "type": "boolean",
        "description": "true = on, false = off"
      }
    },
    "required": ["lights", "state"]
  }
}
```

**Implementation:** Same logic as `POST /switch`.

### 5.3 `set_brightness`

> Adjust brightness without changing color mode.

```json
{
  "name": "set_brightness",
  "description": "Set brightness level for one or more lights. Does not change the current color mode.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "lights": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Light names or IDs."
      },
      "brightness": {
        "type": "number",
        "minimum": 0,
        "maximum": 100,
        "description": "Brightness percentage (0–100)."
      }
    },
    "required": ["lights", "brightness"]
  }
}
```

**Implementation:** Same logic as `POST /brightness`.

### 5.4 `set_cct`

> Set white light mode with color temperature and brightness.

```json
{
  "name": "set_cct",
  "description": "Set a light to white (CCT) mode with a specific color temperature and brightness. Good for video calls, photography, and general workspace lighting.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "lights": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Light names or IDs."
      },
      "brightness": {
        "type": "number",
        "minimum": 0,
        "maximum": 100,
        "description": "Brightness percentage (0–100)."
      },
      "temperature": {
        "type": "number",
        "minimum": 3200,
        "maximum": 8500,
        "description": "Color temperature in Kelvin. 3200K = warm/tungsten, 5600K = daylight, 8500K = cool/blue."
      }
    },
    "required": ["lights", "brightness", "temperature"]
  }
}
```

**Implementation:** Same logic as `POST /cct`.

### 5.5 `set_hsi`

> Set a colored light using hex color.

```json
{
  "name": "set_hsi",
  "description": "Set a light to a specific color using hex color code. Only works on RGB-capable lights. Use list_lights to check supportRGB first.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "lights": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Light names or IDs."
      },
      "hex_color": {
        "type": "string",
        "description": "Hex color code (e.g. 'FF0000' for red, '0066FF' for blue)."
      },
      "brightness": {
        "type": "number",
        "minimum": 0,
        "maximum": 100,
        "description": "Brightness percentage (0–100)."
      },
      "saturation": {
        "type": "number",
        "minimum": 0,
        "maximum": 100,
        "description": "Color saturation percentage (0–100). Default 100."
      }
    },
    "required": ["lights", "hex_color", "brightness"]
  }
}
```

**Implementation:** Same logic as `POST /hst`.

### 5.6 `set_scene`

> Activate a scene effect.

```json
{
  "name": "set_scene",
  "description": "Activate a dynamic scene effect on one or more lights. Use list_scenes first to see which scenes a light supports — different lights have different scene sets. Pass the scene ID from list_scenes.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "lights": {
        "type": "array",
        "items": { "type": "string" },
        "description": "Light names or IDs."
      },
      "scene_id": {
        "type": "integer",
        "minimum": 1,
        "description": "Scene effect ID from list_scenes. IDs are light-specific — always check list_scenes first."
      }
    },
    "required": ["lights", "scene_id"]
  }
}
```

**Implementation:** Same logic as `POST /fx`.

### 5.7 `list_scenes`, `list_sources`, `list_gels`

> List available scenes, light sources, or gel presets for a specific light.

`list_sources` — Returns the calibrated light-source presets (e.g. Tungsten, Daylight, HMI) for a given light. `list_gels` — Returns the 39 Neewer gel presets with their color values.

### 5.7a `list_scenes`

> List available scenes for a specific light.

```json
{
  "name": "list_scenes",
  "description": "List all available scene effects for a specific light. Different lights support different scenes — an NS02 rope light has 73 scenes (nature, moods, holidays, sports), while a standard RGB panel has 9 or 17. Always call this before set_scene to get valid scene IDs.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "light": {
        "type": "string",
        "description": "Light name or ID. Must be a single light — scene lists are per-light."
      }
    },
    "required": ["light"]
  }
}
```

**Implementation:** Looks up the `NeewerLight` by name, iterates `supportedFX`, returns each scene's `id` and `name`. Also includes `supportedMusicFX` if present.

**Return example (standard RGB panel):**
```json
{
  "content": [{
    "type": "text",
    "text": "KeyLight (NL660) — 17 scenes:\n 1. Lighting\n 2. Paparazzi\n 3. Defective bulb\n 4. Explosion\n 5. Welding\n 6. CCT flash\n 7. HUE flash\n 8. CCT pulse\n 9. HUE pulse\n10. Cop Car\n11. Candlelight\n12. HUE Loop\n13. CCT Loop\n14. INT loop\n15. TV Screen\n16. Firework\n17. Party"
  }]
}
```

**Return example (NS02 rope light, abbreviated):**
```json
{
  "content": [{
    "type": "text",
    "text": "RopeLight (NS02) — 73 scenes:\n\nNature: 1. Rainbow, 2. Starry Sky, 3. Flame, 4. Sunrise, 5. Aurora, ...\nMoods: 20. Romantic, 21. Lazy, 22. Dream, ...\nHolidays: 40. Christmas, 41. Halloween, 42. New Year, ...\nSports: 60. Dallas Football, 61. Los Angeles Basketball, ...\n\nMusic-reactive modes: 1. Energetic, 2. Rhythm, 3. Spectrum, 4. Rolling, 5. Stamping, 6. Star"
  }]
}
```

### 5.8 `scan_lights`

> Trigger a Bluetooth scan for new lights.

```json
{
  "name": "scan_lights",
  "description": "Trigger a Bluetooth scan to discover new Neewer lights. Results will appear in list_lights after a few seconds.",
  "inputSchema": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

**Implementation:** Calls the same scan logic as `neewerlite://scanLight` URL scheme, but directly via `appDelegate`.

### 5.9 `get_light_image`

> Return the product image for a light as a base64-encoded PNG data URL.

Useful for agents that want to show the user a visual of the detected light model.

---

## 6. JSON-RPC Message Flow

### 6.1 Initialization

Client POSTs:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-03-26",
    "capabilities": {},
    "clientInfo": { "name": "VSCode", "version": "1.0" }
  }
}
```

Server responds:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-03-26",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "NeewerLite",
      "version": "1.6.0"
    },
    "instructions": "NeewerLite controls Neewer Bluetooth LED lights. Use list_lights to discover connected lights and their capabilities. Use list_scenes to see available scenes for a specific light before calling set_scene. Control lights with set_cct, set_hsi, set_scene, switch_light, or set_brightness."
  }
}
```

Client sends notification:
```json
{
  "jsonrpc": "2.0",
  "method": "notifications/initialized"
}
```

Server responds: `202 Accepted` (no body).

### 6.2 Tool Discovery

Client POSTs:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list"
}
```

Server responds with all 8 tool schemas.

### 6.3 Tool Call

Client POSTs:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "set_cct",
    "arguments": {
      "lights": ["KeyLight"],
      "brightness": 80,
      "temperature": 5600
    }
  }
}
```

Server responds:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{
      "type": "text",
      "text": "Set KeyLight to CCT mode: 80% brightness, 5600K"
    }],
    "isError": false
  }
}
```

---

## 7. Implementation in Server.swift

### 7.1 Phase 1 (Completed — Hand-Rolled)

Phase 1 was implemented with hand-rolled JSON-RPC parsing on Swifter. All 8 tools were E2E tested on 3 real lights. This code is being replaced by the MCP SDK approach.

**What was built and validated:**
- 8 tool handlers with direct device API calls (bypassing view layer)
- Bug fixes: `set_brightness`, `set_hsi`, `set_scene` all use device-level API, not view-dependent methods
- Scene sub-variants: optional `color`, `speed`, `brightness` params
- `list_scenes` shows per-scene parameters (color variants, speed, brightness)
- 11 unit tests, all passing
- E2E tested with step-by-step hardware confirmation on GL1C, PD20250030, RGB660 PRO

### 7.2 Phase 2: Migrate to Vapor + MCP SDK

#### What Changes

| Change | Details |
|---|---|
| **Replace Swifter with Vapor** | New HTTP framework — all routes migrate |
| **Add MCP Swift SDK** | `modelcontextprotocol/swift-sdk` v0.12.0 |
| **Remove hand-rolled MCP code** | `handleMCP()`, `mcpInitializeResponse()`, `mcpToolsList()`, `mcpResult()`, `mcpError()`, `mcpToolResult()` — all replaced by SDK |
| **MCP Server + Transport** | `Server` + `StatefulHTTPServerTransport` from SDK |
| **Vapor adapter for /mcp** | Route handler that converts Vapor ↔ SDK request/response types |
| **Tool registration** | `withMethodHandler(ListTools.self)` and `withMethodHandler(CallTool.self)` using SDK's `Tool` type |
| **Update Package.swift** | Replace Swifter dependency with Vapor + MCP SDK |

#### What Stays

- **All 8 tool implementations** — the light control logic (device API calls) is reused
- **Stream Deck endpoints** — ported to Vapor, same functionality
- **Port 18486**
- **Settings UI toggle** — same UserDefaults key, same start/stop behavior
- **`resolveViewObjects()`** — light matching and "all" expansion logic
- **`DeviceViewObject.matches(lightId:)`** — name/ID matching

#### Code Structure

```swift
import MCP
import Vapor

final class NeewerLiteServer {
    private let app: Application          // Vapor
    private let mcpServer: MCP.Server     // MCP SDK
    private let transport: StatefulHTTPServerTransport
    private let port: Int
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate, port: Int = 18486) {
        self.appDelegate = appDelegate
        self.port = port

        // Create MCP Server
        self.mcpServer = MCP.Server(
            name: "NeewerLite",
            version: Bundle.main.shortVersion,
            capabilities: .init(tools: .init(listChanged: false))
        )

        // Create Streamable HTTP transport
        self.transport = StatefulHTTPServerTransport()

        // Create Vapor app
        self.app = Application()
        
        // Register MCP handlers
        registerMCPHandlers()
        
        // Setup all routes (MCP + Stream Deck)
        setupRoutes()
    }

    private func registerMCPHandlers() {
        // Tool list — using SDK's Tool type
        Task {
            await mcpServer.withMethodHandler(ListTools.self) { [weak self] _ in
                return .init(tools: self?.buildToolList() ?? [])
            }

            // Tool calls — dispatch to implementations
            await mcpServer.withMethodHandler(CallTool.self) { [weak self] params in
                guard let self else {
                    return .init(content: [.text("Server not ready")], isError: true)
                }
                return await self.handleToolCall(params)
            }

            // Start MCP server with transport
            try await mcpServer.start(transport: transport)
        }
    }
}
```

### 7.3 Vapor ↔ MCP SDK Adapter

The Vapor route converts between framework types:

```swift
// POST /mcp — main MCP endpoint
app.on(.POST, "mcp") { [transport] req -> Response in
    let sdkRequest = req.toMCPHTTPRequest(path: "/mcp")
    let sdkResponse = await transport.handleRequest(sdkRequest)
    return sdkResponse.toVaporResponse()
}

// GET /mcp — SSE stream for server-initiated messages
app.on(.GET, "mcp") { [transport] req -> Response in
    let sdkRequest = req.toMCPHTTPRequest(path: "/mcp")
    let sdkResponse = await transport.handleRequest(sdkRequest)
    return sdkResponse.toVaporResponse()
}

// DELETE /mcp — terminate session
app.on(.DELETE, "mcp") { [transport] req -> Response in
    let sdkRequest = req.toMCPHTTPRequest(path: "/mcp")
    let sdkResponse = await transport.handleRequest(sdkRequest)
    return sdkResponse.toVaporResponse()
}
```

Conversion extensions:
```swift
extension Vapor.Request {
    func toMCPHTTPRequest(path: String) -> MCP.HTTPRequest {
        HTTPRequest(
            method: self.method.string,
            headers: Dictionary(self.headers.map { ($0.name, $0.value) },
                               uniquingKeysWith: { _, last in last }),
            body: self.body.data.map { Data(buffer: $0) },
            path: path
        )
    }
}

extension MCP.HTTPResponse {
    func toVaporResponse() -> Vapor.Response {
        switch self {
        case .accepted(let headers):
            return Response(status: .accepted, headers: headers.toHTTPHeaders())
        case .ok(let headers):
            return Response(status: .ok, headers: headers.toHTTPHeaders())
        case .data(let data, let headers):
            return Response(status: .ok, headers: headers.toHTTPHeaders(),
                           body: .init(data: data))
        case .stream(let sseStream, let headers):
            // Pipe AsyncThrowingStream<Data, Error> to Vapor's streaming body
            return Response(status: .ok, headers: headers.toHTTPHeaders(),
                           body: .init(asyncStream: sseStream))
        case .error(let statusCode, _, _, _):
            return Response(status: HTTPStatus(statusCode: statusCode),
                           headers: self.headers.toHTTPHeaders(),
                           body: .init(data: self.bodyData ?? Data()))
        }
    }
}
```

### 7.4 Auth

- **MCP endpoint**: Validated by SDKs `StandardValidationPipeline` — origin check (localhost), Accept header, Content-Type, protocol version, session validation. No UA check.
- **Stream Deck endpoints**: Keep UA prefix check (`neewerlite.sdPlugin/`), ported to Vapor middleware.
- The server is localhost-only (`127.0.0.1`). DNS rebinding protection is handled by the SDK's `OriginValidator.localhost()`.

---

## 8. Client Registration

### VS Code

`.vscode/mcp.json` in any workspace:
```json
{
  "servers": {
    "neewerlite": {
      "type": "http",
      "url": "http://127.0.0.1:18486/mcp"
    }
  }
}
```

Or globally in VS Code settings:
```json
{
  "mcp": {
    "servers": {
      "neewerlite": {
        "type": "http",
        "url": "http://127.0.0.1:18486/mcp"
      }
    }
  }
}
```

### Claude Desktop

`~/Library/Application Support/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "neewerlite": {
      "url": "http://127.0.0.1:18486/mcp"
    }
  }
}
```

### OpenClaw

NeewerLite auto-writes this config when you enable the OpenClaw toggle in **Settings → MCP Clients**. The file is `~/.openclaw/openclaw.json`:

```json
{
  "commands": {
    "mcp": true
  },
  "mcp": {
    "servers": {
      "neewerlite": {
        "url": "http://127.0.0.1:18486/mcp",
        "type": "streamable-http"
      }
    }
  }
}
```

Key points:
- `commands.mcp: true` enables the MCP panel in OpenClaw's UI.
- `type: "streamable-http"` tells OpenClaw's Python runtime which transport to use.
- No `command` / `args` — NeewerLite is already running.
- OpenClaw's Python runtime may use `undici` for probe requests and `Python-urllib` for POST requests. NeewerLite normalises these to a single session key so no session drops occur.

---

## 9. Use Cases

### 9.1 Basic Control

| User says | Agent calls |
|---|---|
| "Turn on all the lights" | `switch_light(lights:["all"], state:true)` |
| "Set key light to 5600K, 80% brightness" | `set_cct(lights:["KeyLight"], brightness:80, temperature:5600)` |
| "Make the fill light blue" | `set_hsi(lights:["FillLight"], hex_color:"0066FF", brightness:70, saturation:100)` |
| "What lights are connected?" | `list_lights()` |
| "Activate squad car mode" | `list_scenes(light:"KeyLight")` → `set_scene(lights:["KeyLight"], scene_id:10, color:2)` |

### 9.2 Context-Aware Automation

| Trigger | Workflow |
|---|---|
| "I'm on a Zoom call" | Agent sets CCT 5600K, brightness 80%, turns on key + fill lights |
| "Xcode build failed" | Agent flashes lights red via set_hsi → wait → switch_light off |
| "It's movie time" | Agent dims to 10% warm (3200K) bias lighting |
| "Good night" | Agent turns off all lights |

### 9.3 Multi-Agent Composition

Any MCP client can compose NeewerLite tools with other tools:

- **Pomodoro agent:** Cycles light color across focus (warm) → break (cool) → alert (red flash).
- **Meeting agent:** Detects calendar events, adjusts lighting for camera-on vs. off.
- **CI agent:** Monitors build status, provides visual feedback through light color.

---

## 10. Implementation Plan

### Phase 1: Hand-Rolled MCP on Swifter ✅ DONE

Proved the concept with a working MCP endpoint. All 8 tools E2E tested on real hardware. This code is replaced by Phase 2.

| # | Task | Status |
|---|---|---|
| 1 | `POST /mcp` route + JSON-RPC dispatcher | ✅ |
| 2 | `initialize` handler | ✅ |
| 3 | `tools/list` — 8 tool schemas | ✅ |
| 4 | `tools/call` → 8 tool handlers | ✅ |
| 5 | "all" light expansion | ✅ |
| 6 | Skip UA check for `/mcp` | ✅ |
| 7 | `GET /mcp` → 405 | ✅ |
| 8 | 11 unit tests | ✅ |
| 9 | E2E test: all 8 tools on 3 real lights | ✅ |
| 10 | Fix `set_brightness` — direct device API | ✅ |
| 11 | Fix `set_hsi` — direct device API | ✅ |
| 12 | Fix `set_scene` — direct device API | ✅ |
| 13 | Scene sub-variants (color, speed, brightness) | ✅ |
| 14 | `list_scenes` with per-scene parameters | ✅ |

### Phase 2: Vapor + MCP SDK Migration ✅ DONE

Replaced Swifter + hand-rolled MCP with Vapor + official MCP Swift SDK. Final tool set: **11 tools** (`list_lights`, `switch_light`, `set_brightness`, `set_cct`, `set_hsi`, `set_scene`, `list_scenes`, `list_sources`, `list_gels`, `scan_lights`, `get_light_image`).

| # | Task | Scope | Status |
|---|---|---|---|
| 15 | Add MCP SDK + Vapor to `Package.swift`, remove Swifter | Dependencies | ✅ |
| 16 | Create `MCP.Server` + `StatefulHTTPServerTransport` | Server init | ✅ |
| 17 | Register `ListTools` handler — 11 tool schemas using SDK's `Tool` type | Tool discovery | ✅ |
| 18 | Register `CallTool` handler — 11 tool implementations | Tool dispatch | ✅ |
| 19 | Vapor route adapter: `POST/GET/DELETE /mcp` → SDK transport | HTTP adapter | ✅ |
| 20 | Vapor ↔ SDK type conversion extensions (`Request` → `HTTPRequest`, `HTTPResponse` → `Response`) | Helpers | ✅ |
| 21 | Port Stream Deck routes to Vapor (same paths, no prefix change) | Route migration | ✅ |
| 22 | Port Stream Deck UA middleware to Vapor | Auth | ✅ |
| 23 | Vapor server start/stop lifecycle (integrate with AppDelegate toggle + Settings UI) | Lifecycle | ✅ |
| 24 | 44 unit tests — MCP protocol, tool discovery, Value numeric coercion, middleware, session isolation | Tests | ✅ |
| 25 | Build & run all 234 tests | Validation | ✅ |
| 26 | E2E test: tools on real lights via curl (mini, GL1C, NS02, RGB660 PRO) | Hardware verification | ✅ |
| 27 | Verify Stream Deck plugin still works | Regression | ✅ |
| 28 | Settings UI: HTTP server toggle + Launch at Login checkbox | New UI | ✅ |
| 29 | SRCMode tracking in `list_lights` output | Mode reporting | ✅ |
| 30 | Light source preset CCT/GM defaults (reset on selection) | Source presets | ✅ |
| 31 | Localize 10 light source names in 6 languages | Localization | ✅ |
| 32 | Fix source view slider width | UI fix | ✅ |

### Phase 3: OpenClaw Integration + Session Isolation ✅ DONE

| # | Task | Status |
|---|---|---|
| 33 | OpenClaw added to Settings MCP client list with auto config-write/remove | ✅ |
| 34 | Multi-path install detection (`/Applications/OpenClaw.app` OR `~/.openclaw`) | ✅ |
| 35 | Nested dotted key-path support in config read/write (`mcp.servers`) | ✅ |
| 36 | Write `commands.mcp: true` and `type: streamable-http` to openclaw.json | ✅ |
| 37 | `SessionManager` actor — per-client `MCPSessionContext` (transport+server), session-ID routing, TTL, 24-session cap | ✅ |
| 38 | Fix session race: bind `Mcp-Session-Id` before streaming response body | ✅ |
| 39 | Fix client-key normalisation: `UA@IP` for standard clients; `openclaw@IP` for undici/Python-urllib mixed stacks | ✅ |
| 40 | Legacy SSE transport: `GET /sse` persistent stream + `POST /messages` inbound queue (separate inbound/outbound `AsyncStream` channels) | ✅ |
| 41 | Restore UA enforcement on Stream Deck routes; remove loopback bypass | ✅ |
| 42 | Multi-client isolation tests: `DELETE` from one client must not break another | ✅ |
| 43 | Full suite green: 234 tests, 0 failures | ✅ |

### Phase 4: Extended Capabilities (Future)

Enabled by the SDK's protocol support — requires minimal code.

| Capability | SDK Support | Notes |
|---|---|---|
| **Server-initiated notifications** (light connected/disconnected) | `server.notify()` + standalone GET SSE | Transport handles SSE piping |
| **MCP Resources** — light state as subscribable resources | `ListResources` + `ReadResource` handlers | Agents can watch for state changes |
| **Preset management** — save/recall named setups | New tool | "studio preset", "movie night" |
| **Sound-to-Light** — start/stop audio-reactive mode | New tool + STL engine hooks | "Start music mode" |
| **Progress tracking** for long operations | SDK's `ProgressNotification` | Scan progress, firmware updates |
| **Batch requests** | Handled automatically by SDK | Multiple tool calls in one HTTP request |

---

## 11. Testing Strategy

### 11.1 Unit Tests (44 tests in MCPServerTests.swift)

- Tool discovery: 11 tools registered with correct names.
- Tool metadata: descriptions, required parameters, input schemas.
- `Value` numeric coercion: `numericInt`/`numericDouble` across int, double, fractional, negative, and string inputs.
- MCP protocol: initialize, tools/list, tools/call, SSE response format, GET probe stream.
- Session isolation: `DELETE` from one client must not break another active session.
- Middleware: UA enforcement for Stream Deck routes; MCP and legacy SSE routes bypass UA check.
- All 234 project tests passing (including 44 MCP tests).

### 11.2 Integration Test

Use the MCP Inspector:
```bash
npx @modelcontextprotocol/inspector
```
Point it at `http://127.0.0.1:18486/mcp`. Verify:
- Initialization handshake succeeds.
- Tool list shows all 11 tools.
- Tool calls execute (check NeewerLite debug logs).

### 11.3 E2E Test

**VS Code Copilot:**
1. Launch NeewerLite (lights optional).
2. Add to `.vscode/mcp.json`:
   ```json
   { "servers": { "neewerlite": { "type": "http", "url": "http://127.0.0.1:18486/mcp" } } }
   ```
3. In VS Code Copilot: "List my Neewer lights."
4. Verify the agent calls `list_lights` and returns light info.
5. "Turn on the key light." → Verify light responds.

**OpenClaw:**
1. Enable OpenClaw in **Settings → MCP Clients** (auto-writes `~/.openclaw/openclaw.json`).
2. Restart OpenClaw.
3. Verify the NeewerLite server entry appears in OpenClaw's MCP panel.
4. Issue a natural-language light command and confirm it executes.

---

## 12. SessionManager — Multi-Client Isolation ✅ DONE

### 12.1 Architecture

`SessionManager` is a Swift `actor` that owns MCP session lifecycle and request routing.

- `clientKey → MCPSessionContext` — maps client identity to a dedicated `StatefulHTTPServerTransport` + `MCP.Server` pair.
- `sessionId → clientKey` — reverse lookup so requests with `Mcp-Session-Id` skip initialise logic.
- TTL eviction and a hard cap of **24 sessions** keep memory bounded.

`MCPSessionContext` contains:
- One `StatefulHTTPServerTransport`
- One `MCP.Server` (started on creation)
- `sessionID: String?`, `lastSeen: Date`

### 12.2 Request Routing

1. **Initialize (no `Mcp-Session-Id`)** — resolve client key (`UA@IP`), `getOrCreateContext`, forward through that context's transport, bind returned `Mcp-Session-Id`.
2. **Normal flow (with `Mcp-Session-Id`)** — look up by session ID, forward to its context.
3. **DELETE** — terminate and remove only the targeted context; other clients unaffected.

### 12.3 Client Key Strategy

| Client type | Key format | Reason |
|---|---|---|
| Standard clients (VS Code, Cursor, …) | `UserAgent@IP` | Preserves isolation when multiple tools share loopback |
| OpenClaw (undici probe + Python-urllib POST) | `openclaw@IP` | Different UA per request from same logical client |

### 12.4 Security Hardening

Same defences as originally planned, now implemented:
- `maxSessions = 24` process-wide cap
- `getOrCreateContext` — reuse existing context for same client key (1 session per client)
- Session TTL cleanup on each request
- Fast-fail for malformed requests before any transport allocation



---

## 13. Open Questions

| # | Question | Resolution |
|---|---|---|
| 1 | ~~Does Swifter support chunked/SSE responses?~~ | ✅ Resolved — migrated to Vapor + MCP SDK. SSE handled by `StatefulHTTPServerTransport`. |
| 2 | Should `list_lights` return human-readable text or structured JSON? | ✅ Resolved — returns human-readable text. Agents reason better with natural language; structured data can be added as a second content block later if needed. |
| 3 | Do we want MCP Prompts (pre-built templates like "video call setup")? | Open — deferred to Phase 3. |
| 4 | ~~Same port or separate port?~~ | ✅ Resolved — same port (18486). Stream Deck routes at their original paths; MCP on `/mcp`; legacy SSE on `/sse`+`/messages`. |
| 5 | Should `GET /sse` + `POST /messages` legacy transport be permanent or temporary? | Open — keep until OpenClaw ships native Streamable HTTP support. |
| 6 | BLE command serialization for concurrent clients? | Open — `BLECommandCoordinator` deferred to a future phase. Current behaviour: BLE is naturally serialized by Swift actor isolation on the light model. |

---

## References

- [MCP Specification — Streamable HTTP Transport](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http)
- [MCP Specification — Lifecycle](https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle)
- [MCP Specification — Tools](https://modelcontextprotocol.io/specification/2025-03-26/server/tools)
- [NeewerLite HTTP Server](../NeewerLite/NeewerLite/Server.swift)
- [NeewerLite Codebase Guide](./Codebase-Guide.md)

> **Note:** This file was previously named `OpenClaw-Integration.md`.

//
//  Command.swift
//  NeewerLite
//
//  Created by Xu Lian on 2/18/23.
//

import Foundation
import AppKit

typealias CommandAction = (_: CommandParameter) -> Void

// Define an enum for the command types
enum CommandType {
    case turnOnLight
    case turnOffLight
    case toggleLight
    case scanLight
    case setLightHSI
    case setLightCCT
    case setLightScene

    var description: String {
        switch self {
            case .turnOnLight:
                return "turnOnLight"
            case .turnOffLight:
                return "turnOffLight"
            case .toggleLight:
                return "toggleLight"
            case .scanLight:
                return "scanLight"
            case .setLightHSI:
                return "setLightHSI"
            case .setLightCCT:
                return "setLightCCT"
            case .setLightScene:
                return "setLightScene"
        }
    }
}

struct CommandParameter {
    var components: URLComponents = URLComponents()

    func lightName() -> String? {
        let lightname = components.queryItems?.first(where: { $0.name == "light" })?.value
        return lightname
    }

    func RGB() -> NSColor? {
        if let rgb = components.queryItems?.first(where: { $0.name == "RGB" })?.value {
            let color = NSColor(hex: rgb, alpha: 1)
            return color
        }
        return nil
    }

    func HUE() -> Int? {
        if let val = components.queryItems?.first(where: { $0.name == "HUE" })?.value {
            let valInt = Int(val)!
            return valInt
        }
        return nil
    }

    func CCT() -> Int {
        if let val = components.queryItems?.first(where: { $0.name == "CCT" })?.value {
            let valInt = Int(val)!
            return valInt
        }
        return 3200
    }

    func GMM() -> Int {
        if let val = components.queryItems?.first(where: { $0.name == "GM" })?.value {
            let valInt = Int(val)!
            return valInt
        }
        return 0
    }

    func saturation() -> Double {
        if let val = components.queryItems?.first(where: { $0.name == "Saturation" })?.value {
            if let sat = Double(val) {
                if sat > 1.0 {
                    return sat / 100.0
                }
                return sat
            } else {
                return 1.0
            }
        }
        return 1.0
    }

    func brightness() -> Double? {
        if let val = components.queryItems?.first(where: { $0.name == "Brightness" })?.value {
            if let brr = Double(val) {
                return brr
            }
        }
        return nil
    }

    func scene() -> Int {
        if let val = components.queryItems?.first(where: { $0.name == "Scene" })?.value {
            let valLow = val.lowercased()
            switch valLow {
                case "squadcar":
                    return 1
                case "ambulance":
                    return 2
                case "fireengine":
                    return 3
                case "fireworks":
                    return 4
                case "party":
                    return 5
                case "candlelight":
                    return 6
                case "lighting":
                    return 7
                case "paparazzi":
                    return 8
                case "screen":
                    return 9
                default:
                    return 1
            }
        }
        return 1
    }

    func sceneId() -> Int? {
        if let val = components.queryItems?.first(where: { $0.name == "SceneId" })?.value {
            let valInt = Int(val)!
            return valInt
        }
        return nil
    }
}

// Define a struct for command
struct Command {
    var type: CommandType
    var action: CommandAction
    func execute(components: URLComponents) {
        let pra = CommandParameter(components: components)
        action(pra)
    }
}

// Define a command handler class
class CommandHandler {
    private var commands: [Command] = []

    // Register commands with the handler
    func register(command: Command) {
        commands.append(command)
    }

    // Execute a command by name
    func execute(commandName: String, components: URLComponents) {
        if let command = commands.first(where: { $0.type.description == commandName }) {
            command.execute(components: components)
        } else {
            Logger.error("Command not found: \(commandName)")
        }
    }
}

public enum ControlTag: Int {
    case brr = 10
    case cct = 11
    case gmm = 12
    case hue = 13
    case sat = 14
    case wheel = 15
    case fxsubview = 16
    case speed = 17
    case spark = 18
}

public enum TabId: String {
    case cct = "cctTab"
    case hsi = "hsiTab"
    case source = "sourceTab"
    case scene = "sceTab"
}


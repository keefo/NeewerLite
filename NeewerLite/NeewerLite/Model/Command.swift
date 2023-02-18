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
    case setLightRGB

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
            case .setLightRGB:
                return "setLightRGB"
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

    func saturation() -> Double {
        if let sat = components.queryItems?.first(where: { $0.name == "Saturation" })?.value {
            return (Double(sat) ?? 100.0) / 100.0
        }
        return 1.0
    }

    func brightness() -> Double {
        if let val = components.queryItems?.first(where: { $0.name == "Brightness" })?.value {
            return (Double(val) ?? 100.0) / 100.0
        }
        return 1.0
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

//
//  String+Localized.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/18/26.
//

import Foundation

extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    func localized(comment: String) -> String {
        NSLocalizedString(self, comment: comment)
    }

    func localized(_ args: CVarArg...) -> String {
        let format = NSLocalizedString(self, comment: "")
        switch args.count {
        case 1: return String(format: format, args[0])
        case 2: return String(format: format, args[0], args[1])
        case 3: return String(format: format, args[0], args[1], args[2])
        case 4: return String(format: format, args[0], args[1], args[2], args[3])
        case 5: return String(format: format, args[0], args[1], args[2], args[3], args[4])
        default: return format
        }
    }
}

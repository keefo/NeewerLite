//
//  DataExtensions.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/16/21.
//
import Foundation
import UniformTypeIdentifiers
import CoreServices  // for LSCopyDefaultRoleHandlerForContentType

func defaultBundleID(forFileExtension ext: String) -> String? {
    // 1. Get the UTI for that extension
    guard let utType = UTType(filenameExtension: ext)?.identifier else {
        return nil
    }
    // 2. Ask LaunchServices for the default handler's bundle ID
    let handler = LSCopyDefaultRoleHandlerForContentType(
        utType as CFString,
        LSRolesMask.all
    )?.takeRetainedValue() as String?
    return handler
}

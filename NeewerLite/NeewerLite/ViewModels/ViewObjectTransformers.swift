//
//  ViewObjectTransformers.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/1/23.
//

import Foundation

@objc(MyLightTableTransformer)
public final class MyLightTableTransformer: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return NSString.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return false
    }

    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        Logger.info("transformedValue: \(value)")
        return ""
    }
}

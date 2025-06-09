//
//  NLSlider.swift
//  NeewerLite
//
//  Created by Xu Lian on 10/26/23.
//
import Cocoa

// Define an enum for the command types
enum NLSliderType {
    case brr
    case cct
    case gmm
    case hue
    case sat
    case speed
    case spark
}

class NLSlider: NSView {

    var pauseNotify: Bool = false

    var minValue: CGFloat = 0.0 {
        didSet {
            if currentValue > minValue {
                currentValue = minValue
            }
            if needUpperBound {
                if currentUpperValue < currentValue {
                    currentUpperValue = currentValue
                }
            }
        }
    }

    var maxValue: CGFloat = 100.0 {
        didSet {
            if currentValue < maxValue {
                currentValue = maxValue
            }
            if needUpperBound {
                if currentUpperValue > maxValue {
                    currentUpperValue = maxValue
                }
            }
        }
    }

    @objc dynamic var currentValue: CGFloat = 0.5 {
        didSet {
            if currentValue < minValue {
                currentValue = minValue
            } else {
                if needUpperBound {
                    if currentValue > currentUpperValue {
                        currentValue = currentUpperValue
                    }
                } else {
                    if currentValue > maxValue {
                        currentValue = maxValue
                    }
                }
            }
            if steps > 1 {
                let step = (maxValue - minValue) / CGFloat(steps)
                var roundedValue = round(currentValue / step) * step
                if roundedValue > maxValue - step {
                    roundedValue = maxValue - step
                }
                if needUpperBound {
                    if roundedValue > currentUpperValue {
                        roundedValue = currentUpperValue
                    }
                } else {
                    if roundedValue > maxValue {
                        roundedValue = maxValue
                    }
                }
                currentValue = roundedValue
            }
            needsDisplay = true
            notifyValueChange()
        }
    }

    @objc dynamic var currentUpperValue: CGFloat = 0.8 {
        didSet {
            if currentUpperValue < currentValue {
                currentUpperValue = currentValue
            } else if currentUpperValue > maxValue {
                currentUpperValue = maxValue
            }
            needsDisplay = true
            notifyUpperValueChange()
        }
    }

    var needUpperBound: Bool = false

    var barColor: NSColor = .lightGray
    var knobColor: NSColor = .white
    var buttonColor: NSColor = NSColor.controlColor
    var buttonPressColor: NSColor = NSColor.selectedControlColor
    var textColor: NSColor = .black
    var steps: Int = 0
    var type: NLSliderType = .brr
    var mTag = -1

    // Closure property for custom bar drawing
    var customBarDrawing: ((NSRect, Int) -> Void)?

    var callback: ((_ brr: CGFloat) -> Void)?

    var knobRadius: CGFloat = 3.0
    var knobSize: CGSize = CGSize(width: 12, height: 24)

    private var buttonWidth: CGFloat = 13.0
    private var spacing: CGFloat = 10.0 // Adjust the spacing value

    private var mouseDownLoc: CGPoint = .zero

    private var isKnobBeingDragged = false
    private var isKnobUpperBeingDragged = false
    private var mouseDownOnLeftBtn = false
    private var mouseDownOnRightBtn = false

    private func notifyValueChange() {
        if pauseNotify {
            return
        }
        self.willChangeValue(forKey: "currentValue")
        if let safeCallback = callback {
            safeCallback(currentValue)
        }
        self.didChangeValue(forKey: "currentValue")
    }

    private func notifyUpperValueChange() {
        if pauseNotify {
            return
        }
        self.willChangeValue(forKey: "currentUpperValue")
        if let safeCallback = callback {
            safeCallback(currentValue)
        }
        self.didChangeValue(forKey: "currentUpperValue")
    }

    override var tag: Int {
        get {
            return mTag
        }
        set {
            mTag = newValue
        }
    }

    class func brightnessBar() -> ((NSRect, Int) -> Void) {
        return { bounds, _ in
            let startColor = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) //
            let middleColor = NSColor(calibratedRed: 0.7, green: 0.7, blue: 0.7, alpha: 1.0) //
            let endColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0) //
            let gradient = NSGradient(colors: [startColor, middleColor, endColor])
            gradient?.draw(in: bounds, angle: 0)
        }
    }

    class func cttBar() -> ((NSRect, Int) -> Void) {
        return { bounds, _ in
            let startColor = NSColor(calibratedRed: 0.8, green: 0.6, blue: 0.2, alpha: 1.0) // Light yellow
            let middleColor = NSColor.white
            let endColor = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.8, alpha: 1.0) // Light blue

            let gradient = NSGradient(colors: [startColor, middleColor, endColor])
            gradient?.draw(in: bounds, angle: 0)
        }
    }

    class func gmBar() -> ((NSRect, Int) -> Void) {
        return { bounds, _ in
            let startColor = NSColor(calibratedRed: 0.88, green: 0.6, blue: 0.6, alpha: 1.0) // Light yellow
            let middleColor = NSColor.white
            let endColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 0.4, alpha: 1.0) // Light blue

            let gradient = NSGradient(colors: [startColor, middleColor, endColor])
            gradient?.draw(in: bounds, angle: 0)
        }
    }

    class func hueBar() -> ((NSRect, Int) -> Void) {
        return { bounds, _ in
            let colors: [NSColor] = [
                NSColor.red,
                NSColor.orange,
                NSColor.yellow,
                NSColor.green,
                NSColor.blue,
                NSColor.purple,
                NSColor.red
            ]

            // Define the corresponding locations (normalized between 0 and 1)
            let locations: [CGFloat] = [0.0, 1.0 / 6.0, 2.0 / 6.0, 3.0 / 6.0, 4.0 / 6.0, 5.0 / 6.0, 1.0]

            // Create an NSColorSpace for your gradient (for example, sRGB)
            let colorSpace = NSColorSpace.sRGB

            // Create the NSGradient
            let rainbowGradient = NSGradient(colors: colors, atLocations: locations, colorSpace: colorSpace)

            rainbowGradient?.draw(in: bounds, angle: 0)
        }
    }

    class func satBar() -> ((NSRect, Int) -> Void) {
        return { bounds, _ in
            let startColor = NSColor(calibratedHue: CGFloat(240) / 360.0, saturation: 0, brightness: 1, alpha: 1.0)
            let endColor = NSColor(calibratedHue: CGFloat(240) / 360.0, saturation: 1, brightness: 1, alpha: 1.0)

            let gradient = NSGradient(colors: [startColor, endColor])
            gradient?.draw(in: bounds, angle: 0)
        }
    }

    class func speedBar() -> ((NSRect, Int) -> Void) {
        return { bounds, blocks in
            if blocks > 1 {
                let width = bounds.size.width / CGFloat(blocks)
                let gap = 3.0

                // Calculate the width of each segment
                let segmentWidth = width - gap
                var offsetx = bounds.origin.x
                var col = 0.2
                for _ in 0..<blocks {
                    let color = NSColor(calibratedHue: 0.645, saturation: 0.9, brightness: col, alpha: 1.0)
                    let barRect = NSRect(x: offsetx, y: bounds.origin.y, width: segmentWidth, height: bounds.size.height)
                    color.setFill()
                    barRect.fill()
                    offsetx += width
                    col += 0.1
                }
            } else {
                let startColor = NSColor(calibratedRed: 0.88, green: 0.6, blue: 0.6, alpha: 1.0) // Light yellow
                let middleColor = NSColor.white
                let endColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 0.4, alpha: 1.0) // Light blue

                let gradient = NSGradient(colors: [startColor, middleColor, endColor])
                gradient?.draw(in: bounds, angle: 0)
            }
        }
    }

    class func sparkBar() -> ((NSRect, Int) -> Void) {
        return { bounds, blocks in
            if blocks > 1 {
                let width = bounds.size.width / CGFloat(blocks)
                let gap = 3.0

                // Calculate the width of each segment
                let segmentWidth = width - gap
                var offsetx = bounds.origin.x
                var brr = 0.3
                for _ in 0..<blocks {
                    let color = NSColor(calibratedHue: 0.045, saturation: 0.9, brightness: brr, alpha: 1.0)
                    let barRect = NSRect(x: offsetx, y: bounds.origin.y, width: segmentWidth, height: bounds.size.height)
                    color.setFill()
                    barRect.fill()
                    offsetx += width
                    brr += 0.09
                }
            } else {
                let startColor = NSColor(calibratedRed: 0.88, green: 0.6, blue: 0.6, alpha: 1.0) // Light yellow
                let middleColor = NSColor.white
                let endColor = NSColor(calibratedRed: 0.4, green: 0.6, blue: 0.4, alpha: 1.0) // Light blue

                let gradient = NSGradient(colors: [startColor, middleColor, endColor])
                gradient?.draw(in: bounds, angle: 0)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let context = NSGraphicsContext.current!.cgContext

        drawBar(context)

        drawKnob(context)

        drawButtons(context)
    }

    func drawButtons(_ context: CGContext) {
        // Draw buttons on both sides with spacing
        let offy = (bounds.height - buttonWidth) / 2.0
        let radius = buttonWidth / 2.0
        
        let leftPath = NSBezierPath(roundedRect: NSRect(x: 0, y: offy, width: buttonWidth, height: buttonWidth), xRadius: radius, yRadius: radius)
        if mouseDownOnLeftBtn {
            buttonPressColor.setFill()
        } else {
            buttonColor.setFill()
        }
        leftPath.fill()
       
        let rightPath = NSBezierPath(roundedRect: NSRect(x: bounds.size.width - buttonWidth, y: offy, width: buttonWidth, height: buttonWidth), xRadius: radius, yRadius: radius)
        if mouseDownOnRightBtn {
            buttonPressColor.setFill()
        } else {
            buttonColor.setFill()
        }
        rightPath.fill()

        NSColor.labelColor.setFill()
        let minus = NSBezierPath(roundedRect: NSRect(x: 3, y: offy+6, width: buttonWidth-6, height: 1), xRadius: 0, yRadius: 0)
        minus.fill()
        
        let cross = NSBezierPath()
        // Horizontal line
        let horizontalRect = NSRect(x: bounds.size.width - buttonWidth + 3, y: offy + 6, width: buttonWidth - 5, height: 1)
        let horizontalPath = NSBezierPath(roundedRect: horizontalRect, xRadius: 0, yRadius: 0)
        cross.append(horizontalPath)
        // Vertical line
        let verticalRect = NSRect(x: bounds.size.width - buttonWidth + buttonWidth / 2.0, y: 6, width: 1, height: buttonWidth - 5)
        let verticalPath = NSBezierPath(roundedRect: verticalRect, xRadius: 0, yRadius: 0)
        cross.append(verticalPath)
        cross.fill()
    }

    private func barRect() -> NSRect {
        let barRect = NSRect(x: buttonWidth + spacing, y: bounds.size.height / 4, width: bounds.size.width - 2 * (buttonWidth + spacing), height: bounds.size.height / 2)
        return barRect
    }

    private func drawBar(_ context: CGContext) {
        // Draw the colored bar with spacing
        let barRect = barRect()
        if let customBarDrawing = customBarDrawing {
            if steps <= 1 {
                customBarDrawing(barRect, 1)
            } else {
                customBarDrawing(barRect, steps)
            }
        } else {
            barColor.setFill()
            context.fill(barRect)
        }
    }

    private func knobPosition() -> CGFloat {
        return(currentValue - minValue) / (maxValue - minValue) * (bounds.size.width - 2 * (buttonWidth + spacing)) + (buttonWidth + spacing)
    }

    private func knobPositionUpper() -> CGFloat {
        return (currentUpperValue - minValue) / (maxValue - minValue) * (bounds.size.width - 2 * (buttonWidth + spacing)) + (buttonWidth + spacing)
    }

    private func knobRect() -> NSRect {
        // Calculate the position of the knob based on the current value
        let knobPosition = knobPosition()
        // Draw the knob rectangle with radius 5
        var knobRect = NSRect(x: knobPosition - knobRadius, y: (bounds.size.height - knobSize.height) / 2, width: knobSize.width, height: knobSize.height)
        if steps > 1 {
            knobRect.origin.x += 8
        }
        return knobRect
    }

    private func knobRectUpper() -> NSRect {
        // Calculate the position of the knob based on the current value
        let knobPosition = knobPositionUpper()
        // Draw the knob rectangle with radius 5
        let knobRect = NSRect(x: knobPosition - knobRadius, y: (bounds.size.height - knobSize.height) / 2, width: knobSize.width, height: knobSize.height)
        return knobRect
    }

    private func drawKnob(_ context: CGContext) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12) // Set the shadow color and opacity
        shadow.shadowOffset = NSSize(width: 0, height: -1) // Set the shadow offset
        shadow.shadowBlurRadius = 1.6
        // Apply the shadow to the current graphics context
        shadow.set()

        // Draw the knob rectangle with radius 5
        let knobRect = knobRect()
        let knobPath = NSBezierPath(roundedRect: knobRect, xRadius: knobRadius, yRadius: knobRadius)
        knobColor.setFill()
        knobPath.fill()

        if needUpperBound {
            let knobRectUpper = knobRectUpper()
            let knobPathUpper = NSBezierPath(roundedRect: knobRectUpper, xRadius: knobRadius, yRadius: knobRadius)
            knobColor.setFill()
            knobPathUpper.fill()
        }

        // Reset the shadow for subsequent drawing (if needed)
        NSShadow().set()
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        isKnobBeingDragged = knobRect().contains(location)
        isKnobUpperBeingDragged = knobRectUpper().contains(location)
        let dlt = (maxValue-minValue) / 10.0
        if isKnobBeingDragged || isKnobUpperBeingDragged {
            mouseDownLoc = location
        } else if location.x < buttonWidth + spacing {
            // Mouse down occurred on the left button
            mouseDownOnLeftBtn = true
            if currentValue > minValue {
                currentValue -= dlt // Adjust this value to control the step size
            }
            needsDisplay = true
        } else if location.x > bounds.size.width - (buttonWidth + spacing) {
            if needUpperBound {
                // Mouse down occurred on the right button
                mouseDownOnRightBtn = true
                if currentUpperValue < maxValue {
                    currentUpperValue += dlt // Adjust this value to control the step size
                }
                needsDisplay = true
            } else {
                // Mouse down occurred on the right button
                mouseDownOnRightBtn = true
                if currentValue < maxValue {
                    currentValue += dlt // Adjust this value to control the step size
                }
                needsDisplay = true
            }
        } else {
            let location = convert(event.locationInWindow, from: nil)
            let deltaX = location.x - knobPosition()
            let valueDelta = (deltaX / (bounds.size.width - 2 * (buttonWidth + spacing))) * (maxValue - minValue)
            currentValue += valueDelta
            needsDisplay = true
            isKnobBeingDragged = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if isKnobBeingDragged || isKnobUpperBeingDragged {
            let location = convert(event.locationInWindow, from: nil)
            let deltaX = location.x - mouseDownLoc.x
            if isKnobBeingDragged && isKnobUpperBeingDragged {
                if deltaX > 0 {
                    isKnobBeingDragged = false
                } else {
                    isKnobUpperBeingDragged = false
                }
            } else if isKnobBeingDragged && !isKnobUpperBeingDragged {
                let deltaX = location.x - knobPosition()
                let valueDelta = (deltaX / (bounds.size.width - 2 * (buttonWidth + spacing))) * (maxValue - minValue)
                currentValue += valueDelta
                needsDisplay = true
            } else if !isKnobBeingDragged && isKnobUpperBeingDragged {
                let location = convert(event.locationInWindow, from: nil)
                let deltaX = location.x - knobPositionUpper()
                let valueDelta = (deltaX / (bounds.size.width - 2 * (buttonWidth + spacing))) * (maxValue - minValue)
                currentUpperValue += valueDelta
                needsDisplay = true
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        isKnobBeingDragged = false
        isKnobUpperBeingDragged = false
        mouseDownOnLeftBtn = false
        mouseDownOnRightBtn = false
        needsDisplay = true
    }
}

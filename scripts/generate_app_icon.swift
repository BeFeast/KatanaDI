#!/usr/bin/env swift

import AppKit
import Foundation

enum IconGenerationError: Error {
    case missingOutputPath
    case bitmapCreationFailed(Int)
    case pngEncodingFailed(Int)
}

let outputPath: String

if CommandLine.arguments.count >= 2 {
    outputPath = CommandLine.arguments[1]
} else {
    throw IconGenerationError.missingOutputPath
}

let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
let fileManager = FileManager.default

if fileManager.fileExists(atPath: outputURL.path) {
    try fileManager.removeItem(at: outputURL)
}

try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconVariants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func rgbaColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func drawIcon(side: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw IconGenerationError.bitmapCreationFailed(side)
    }

    bitmap.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGenerationError.bitmapCreationFailed(side)
    }

    NSGraphicsContext.current = context

    let size = CGFloat(side)
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.06
    let cardRect = canvas.insetBy(dx: inset, dy: inset)
    let cornerRadius = size * 0.22

    NSColor.clear.setFill()
    canvas.fill()

    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
    shadow.shadowColor = rgbaColor(0.02, 0.04, 0.10, 0.22)
    shadow.set()

    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)
    cardPath.fill()

    NSGraphicsContext.current?.saveGraphicsState()
    cardPath.addClip()

    let backgroundGradient = NSGradient(
        colorsAndLocations:
            (rgbaColor(0.06, 0.11, 0.19, 1), 0.0),
            (rgbaColor(0.08, 0.48, 0.72, 1), 0.58),
            (rgbaColor(0.97, 0.76, 0.18, 1), 1.0)
    )
    backgroundGradient?.draw(in: cardRect, angle: -35)

    let glowRect = NSRect(
        x: cardRect.minX + size * 0.12,
        y: cardRect.minY + size * 0.34,
        width: size * 0.52,
        height: size * 0.42
    )
    let glowPath = NSBezierPath(ovalIn: glowRect)
    rgbaColor(1, 1, 1, 0.13).setFill()
    glowPath.fill()

    let highlightPath = NSBezierPath()
    highlightPath.move(to: NSPoint(x: cardRect.minX, y: cardRect.maxY - size * 0.10))
    highlightPath.line(to: NSPoint(x: cardRect.maxX, y: cardRect.maxY - size * 0.28))
    highlightPath.line(to: NSPoint(x: cardRect.maxX, y: cardRect.maxY))
    highlightPath.line(to: NSPoint(x: cardRect.minX, y: cardRect.maxY))
    highlightPath.close()
    rgbaColor(1, 1, 1, 0.08).setFill()
    highlightPath.fill()

    let plateWidth = size * 0.17
    let plateHeight = size * 0.58
    let plateCorner = size * 0.09
    let plateY = size * 0.21

    let leftPlate = NSBezierPath(
        roundedRect: NSRect(x: size * 0.16, y: plateY, width: plateWidth, height: plateHeight),
        xRadius: plateCorner,
        yRadius: plateCorner
    )
    rgbaColor(0.03, 0.06, 0.12, 0.32).setFill()
    leftPlate.fill()

    let rightPlate = NSBezierPath(
        roundedRect: NSRect(x: size * 0.67, y: plateY, width: plateWidth, height: plateHeight),
        xRadius: plateCorner,
        yRadius: plateCorner
    )
    rgbaColor(0.03, 0.06, 0.12, 0.30).setFill()
    rightPlate.fill()

    let portSize = size * 0.055
    for y in stride(from: size * 0.68, through: size * 0.32, by: -(size * 0.12)) {
        let leftPort = NSBezierPath(ovalIn: NSRect(x: size * 0.215, y: y, width: portSize, height: portSize))
        rgbaColor(1, 1, 1, 0.82).setFill()
        leftPort.fill()

        let rightPort = NSBezierPath(ovalIn: NSRect(x: size * 0.725, y: y, width: portSize, height: portSize))
        rgbaColor(1, 1, 1, 0.82).setFill()
        rightPort.fill()
    }

    let waveform = NSBezierPath()
    waveform.lineWidth = size * 0.075
    waveform.lineCapStyle = .round
    waveform.lineJoinStyle = .round
    waveform.move(to: NSPoint(x: size * 0.28, y: size * 0.47))
    waveform.curve(
        to: NSPoint(x: size * 0.40, y: size * 0.63),
        controlPoint1: NSPoint(x: size * 0.31, y: size * 0.47),
        controlPoint2: NSPoint(x: size * 0.35, y: size * 0.63)
    )
    waveform.curve(
        to: NSPoint(x: size * 0.49, y: size * 0.34),
        controlPoint1: NSPoint(x: size * 0.44, y: size * 0.63),
        controlPoint2: NSPoint(x: size * 0.45, y: size * 0.34)
    )
    waveform.curve(
        to: NSPoint(x: size * 0.61, y: size * 0.54),
        controlPoint1: NSPoint(x: size * 0.53, y: size * 0.34),
        controlPoint2: NSPoint(x: size * 0.56, y: size * 0.54)
    )
    waveform.curve(
        to: NSPoint(x: size * 0.72, y: size * 0.50),
        controlPoint1: NSPoint(x: size * 0.65, y: size * 0.54),
        controlPoint2: NSPoint(x: size * 0.69, y: size * 0.50)
    )
    rgbaColor(1, 1, 1, 0.94).setStroke()
    waveform.stroke()

    let routeBeam = NSBezierPath()
    routeBeam.lineWidth = size * 0.045
    routeBeam.lineCapStyle = .round
    routeBeam.move(to: NSPoint(x: size * 0.33, y: size * 0.24))
    routeBeam.line(to: NSPoint(x: size * 0.63, y: size * 0.24))
    rgbaColor(0.98, 0.85, 0.34, 0.95).setStroke()
    routeBeam.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: NSPoint(x: size * 0.64, y: size * 0.30))
    arrowHead.line(to: NSPoint(x: size * 0.76, y: size * 0.24))
    arrowHead.line(to: NSPoint(x: size * 0.64, y: size * 0.18))
    arrowHead.close()
    rgbaColor(0.98, 0.85, 0.34, 0.95).setFill()
    arrowHead.fill()

    let borderPath = NSBezierPath(roundedRect: cardRect.insetBy(dx: size * 0.01, dy: size * 0.01), xRadius: cornerRadius, yRadius: cornerRadius)
    borderPath.lineWidth = max(size * 0.01, 2)
    rgbaColor(1, 1, 1, 0.14).setStroke()
    borderPath.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError.pngEncodingFailed(side)
    }

    try data.write(to: url)
}

for (fileName, side) in iconVariants {
    try drawIcon(side: side, to: outputURL.appendingPathComponent(fileName))
}

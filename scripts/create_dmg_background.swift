#!/usr/bin/env swift
import AppKit
import CoreGraphics

// DMG background dimensions (matches window bounds)
let width: CGFloat = 440
let height: CGFloat = 300

// Create bitmap context
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil,
          width: Int(width),
          height: Int(height),
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
    print("Failed to create context")
    exit(1)
}

// Fill background with dark gradient (consistent throughout)
let gradientColors = [
    NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0).cgColor,
    NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).cgColor
]
let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

// Draw arrow (pointing right, from app to Applications)
context.setStrokeColor(NSColor(white: 0.5, alpha: 0.6).cgColor)
context.setLineWidth(3)
context.setLineCap(.round)
context.setLineJoin(.round)

// Arrow body - curved arc (icons are at y=105 in Finder coords, which is y=195 in CG coords)
let arrowStartX: CGFloat = 170
let arrowEndX: CGFloat = 270
let arrowY: CGFloat = 195

context.move(to: CGPoint(x: arrowStartX, y: arrowY))
context.addQuadCurve(to: CGPoint(x: arrowEndX - 15, y: arrowY), control: CGPoint(x: (arrowStartX + arrowEndX) / 2, y: arrowY - 30))
context.strokePath()

// Arrow head
context.move(to: CGPoint(x: arrowEndX - 28, y: arrowY - 12))
context.addLine(to: CGPoint(x: arrowEndX - 12, y: arrowY))
context.addLine(to: CGPoint(x: arrowEndX - 28, y: arrowY + 12))
context.strokePath()

// Draw custom labels in white (to replace Finder's black labels)
NSGraphicsContext.saveGraphicsState()
let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = nsContext

let labelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(white: 0.9, alpha: 1.0)
]

// Icon positions in Finder: (110, 105) and (330, 105)
// In CG coords (y from bottom): icon center at y = 300 - 105 = 195
// Labels appear below icons, roughly at y = 195 - 64 - 30 = 101 (accounting for icon size and padding)
let labelY: CGFloat = 95

// A-IQ.app label (centered under icon at x=110)
let appLabel = "A-IQ.app"
let appLabelSize = appLabel.size(withAttributes: labelAttributes)
let appLabelRect = CGRect(
    x: 110 - appLabelSize.width / 2,
    y: labelY,
    width: appLabelSize.width,
    height: appLabelSize.height
)
appLabel.draw(in: appLabelRect, withAttributes: labelAttributes)

// Applications label (centered under icon at x=330)
let appsLabel = "Applications"
let appsLabelSize = appsLabel.size(withAttributes: labelAttributes)
let appsLabelRect = CGRect(
    x: 330 - appsLabelSize.width / 2,
    y: labelY,
    width: appsLabelSize.width,
    height: appsLabelSize.height
)
appsLabel.draw(in: appsLabelRect, withAttributes: labelAttributes)

NSGraphicsContext.restoreGraphicsState()

// Create image and save
guard let image = context.makeImage() else {
    print("Failed to create image")
    exit(1)
}

let bitmapRep = NSBitmapImageRep(cgImage: image)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG data")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg_background.png"
do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Background image created: \(outputPath)")
} catch {
    print("Failed to write file: \(error)")
    exit(1)
}

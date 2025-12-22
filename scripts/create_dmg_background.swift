#!/usr/bin/env swift
import AppKit
import CoreGraphics

// DMG background dimensions (standard size for nice layout)
let width: CGFloat = 660
let height: CGFloat = 400

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

// Fill background with gradient
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

// Arrow body - curved arc
let arrowStartX: CGFloat = 220
let arrowEndX: CGFloat = 440
let arrowY: CGFloat = 200

context.move(to: CGPoint(x: arrowStartX, y: arrowY))
context.addQuadCurve(to: CGPoint(x: arrowEndX - 20, y: arrowY), control: CGPoint(x: (arrowStartX + arrowEndX) / 2, y: arrowY - 40))
context.strokePath()

// Arrow head
context.move(to: CGPoint(x: arrowEndX - 35, y: arrowY - 15))
context.addLine(to: CGPoint(x: arrowEndX - 15, y: arrowY))
context.addLine(to: CGPoint(x: arrowEndX - 35, y: arrowY + 15))
context.strokePath()

// Draw text
let textAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: NSColor(white: 0.6, alpha: 1.0)
]

// Draw "Drag to Install" text
NSGraphicsContext.saveGraphicsState()
let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.current = nsContext

let dragText = "Drag to Install"
let dragTextSize = dragText.size(withAttributes: textAttributes)
let dragTextRect = CGRect(
    x: (width - dragTextSize.width) / 2,
    y: 95,
    width: dragTextSize.width,
    height: dragTextSize.height
)
dragText.draw(in: dragTextRect, withAttributes: textAttributes)

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

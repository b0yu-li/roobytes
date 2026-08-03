#!/usr/bin/env swift
import AppKit
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.iconset")

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocusFlipped(false)
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.223

    let bg = NSBezierPath(
        roundedRect: rect.insetBy(dx: size * 0.02, dy: size * 0.02),
        xRadius: radius,
        yRadius: radius
    )
    NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1).setFill()
    bg.fill()

    let sheen = NSBezierPath(
        roundedRect: NSRect(x: size * 0.08, y: size * 0.55, width: size * 0.84, height: size * 0.35),
        xRadius: radius * 0.6,
        yRadius: radius * 0.6
    )
    NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
    sheen.fill()

    let ringInset = size * 0.22
    let ringRect = rect.insetBy(dx: ringInset, dy: ringInset)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = size * 0.085
    NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.28, alpha: 1).setStroke()
    ring.stroke()

    let inner = NSBezierPath(ovalIn: ringRect.insetBy(dx: size * 0.11, dy: size * 0.11))
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.09, alpha: 1).setFill()
    inner.fill()

    let docW = size * 0.16
    let docH = size * 0.20
    let docX = (size - docW) / 2
    let docY = (size - docH) / 2 - size * 0.01
    let doc = NSBezierPath(
        roundedRect: NSRect(x: docX, y: docY, width: docW, height: docH),
        xRadius: size * 0.02,
        yRadius: size * 0.02
    )
    NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.28, alpha: 0.95).setFill()
    doc.fill()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: docX + docW * 0.55, y: docY + docH))
    fold.line(to: NSPoint(x: docX + docW, y: docY + docH))
    fold.line(to: NSPoint(x: docX + docW, y: docY + docH * 0.55))
    fold.close()
    NSColor(calibratedRed: 0.78, green: 0.48, blue: 0.18, alpha: 1).setFill()
    fold.fill()

    return image
}

func pngData(from image: NSImage, pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let named: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, px) in named {
    let img = drawIcon(size: CGFloat(px))
    let data = pngData(from: img, pixelSize: px)
    try data.write(to: outDir.appendingPathComponent(name))
}

fputs("Wrote iconset to \(outDir.path)\n", stderr)
